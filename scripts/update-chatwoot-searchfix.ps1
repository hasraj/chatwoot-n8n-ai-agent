$ErrorActionPreference = 'Stop'

$source = 'f:\github\chatwoot n8n ai agent\chatwoot-ai-test-3-fixed.json'
$target = 'f:\github\chatwoot n8n ai agent\chatwoot-ai-test-3-searchfix.json'

$json = Get-Content -Raw $source | ConvertFrom-Json

$gateCode = @'
const event = $('Normalize Incoming Event').first().json;
const messageList = $input.first().json;

const normalizePhone = (value) => String(value || '').replace(/[^+\d]/g, '');
const stripHtml = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const normalizeSearchText = (value) => String(value || '')
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .toLowerCase();

const contactPayload = messageList.meta?.contact?.payload;
const contact = Array.isArray(contactPayload)
  ? (contactPayload[0] ?? {})
  : (messageList.meta?.contact ?? {});

const labels = Array.isArray(messageList.meta?.labels) ? messageList.meta.labels : [];
const phoneNumber = normalizePhone(contact.phone_number ?? '');
const allowedPhones = event.config.allowedPhoneNumbers.map(normalizePhone);
const allowedLabels = event.config.allowedLabels.map((label) => label.toLowerCase());
const allowedInboxIds = event.config.allowedInboxIds.map((id) => String(id));
const inboxId = String(event.inboxId ?? '');

const phoneAllowed = allowedPhones.length > 0 && allowedPhones.includes(phoneNumber);
const labelAllowed = labels.some((label) => allowedLabels.includes(String(label).toLowerCase()));
const inboxAllowed = allowedInboxIds.length > 0 && allowedInboxIds.includes(inboxId);
const liveMode = event.config.processingMode === 'live';

const route = liveMode || phoneAllowed || labelAllowed || inboxAllowed ? 'run' : 'skip';
const gateReason = liveMode
  ? 'live_mode'
  : phoneAllowed
    ? 'phone_allowlist'
    : labelAllowed
      ? 'label_allowlist'
      : inboxAllowed
        ? 'inbox_allowlist'
        : 'blocked_in_test_mode';

const knowledgeBase = [
  {
    topic: 'shipping',
    keywords: ['ship', 'shipping', 'delivery'],
    answer: 'We offer free shipping on orders over $50. Standard delivery takes 3-5 business days.'
  },
  {
    topic: 'returns',
    keywords: ['return', 'refund', 'exchange'],
    answer: 'You can return items within 30 days of purchase if they are unused and in their original packaging.'
  },
  {
    topic: 'payment',
    keywords: ['payment', 'pay', 'card', 'bank transfer'],
    answer: 'We accept Visa, Mastercard, PayPal, and bank transfers.'
  },
  {
    topic: 'tracking',
    keywords: ['track', 'tracking', 'where is my order', 'where order'],
    answer: 'You can track your order using the tracking number from your shipping confirmation message.'
  },
  {
    topic: 'contact',
    keywords: ['support', 'human', 'agent', 'contact'],
    answer: `You can contact our support team at ${event.config.supportEmail}.`
  }
];

const lowerMessage = event.content.toLowerCase();
const faqMatches = knowledgeBase
  .filter((entry) => entry.keywords.some((keyword) => lowerMessage.includes(keyword)))
  .map(({ topic, answer }) => ({ topic, answer }))
  .slice(0, 3);

const stopWords = new Set([
  'the', 'and', 'for', 'with', 'this', 'that', 'have', 'from', 'what', 'your', 'about', 'please', 'need', 'want',
  'know', 'tell', 'price', 'stock', 'order', 'where', 'when', 'does', 'will', 'show', 'much', 'how', 'can',
  'you', 'me', 'our', 'get', 'buy', 'make', 'create', 'status', 'hello', 'hi', 'product', 'products', 'item',
  'items', 'produto', 'produtos', 'quero', 'preciso', 'gostaria', 'tenho', 'tem', 'uma', 'um', 'para', 'com'
]);

const normalizedSearchContent = normalizeSearchText(event.content)
  .replace(/order\s*#?\s*\d+/gi, ' ')
  .replace(/[^a-z0-9\s-]/g, ' ');

const productSearchTokens = [...new Set(
  normalizedSearchContent
    .split(/\s+/)
    .filter((word) => word && word.length > 2 && !stopWords.has(word))
)]
  .sort((left, right) => right.length - left.length || left.localeCompare(right))
  .slice(0, 4);

const productSearchTerm = productSearchTokens.join(' ');
const primaryProductToken = productSearchTokens[0] ?? '';

const recentMessages = (Array.isArray(messageList.payload) ? messageList.payload : [])
  .filter((message) => !message.private && String(message.content || '').trim())
  .slice(-event.config.maxConversationMessages)
  .map((message) => ({
    role: message.sender_type === 'contact' || message.message_type === 0 ? 'customer' : 'agent',
    content: stripHtml(message.content),
    created_at: message.created_at
  }));

const createOrderRequested = /(create|place|buy|purchase).{0,20}order|order.{0,20}(create|place|buy|purchase)/i.test(event.content);

return {
  route,
  gateReason,
  accountId: event.accountId,
  conversationId: event.conversationId,
  inboxId: event.inboxId,
  content: event.content,
  orderLookupId: event.detectedOrderId,
  productSearchTerm,
  productSearchTokens,
  primaryProductToken,
  createOrderRequested,
  contactName: contact.name ?? '',
  contactPhone: phoneNumber,
  labels,
  faqMatches,
  recentMessages,
  config: event.config
};
'@

$sortCode = @'
const supportContext = $('Gate Test Contact').first().json;
const productResponse = $input.first().json ?? {};

const stripHtml = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const normalizeText = (value) => stripHtml(value)
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .toLowerCase();
const tokenize = (value) => normalizeText(value)
  .split(/[^a-z0-9]+/)
  .filter((token) => token.length > 1);

const productBody = Array.isArray(productResponse.body) ? productResponse.body : [];
const queryTokens = Array.isArray(supportContext.productSearchTokens) && supportContext.productSearchTokens.length > 0
  ? supportContext.productSearchTokens.map((token) => normalizeText(token)).filter(Boolean)
  : [...new Set(tokenize(supportContext.productSearchTerm || supportContext.content))];
const queryText = normalizeText(supportContext.productSearchTerm || queryTokens.join(' ') || supportContext.content);

const scoreProduct = (product) => {
  const nameText = normalizeText(product.name);
  const slugText = normalizeText(String(product.slug || '').replace(/-/g, ' '));
  const skuText = normalizeText(product.sku);
  const descriptionText = normalizeText(product.short_description || product.description || '');

  let score = 0;
  if (queryText) {
    if (nameText === queryText || slugText === queryText) {
      score += 1400;
    }
    if (nameText.startsWith(queryText) || slugText.startsWith(queryText)) {
      score += 950;
    }
    if (nameText.includes(queryText) || slugText.includes(queryText)) {
      score += 700;
    }
  }

  let titleHits = 0;
  for (const token of queryTokens) {
    const inName = nameText.split(/\s+/).includes(token);
    const inNameLoose = nameText.includes(token);
    const inSlug = slugText.split(/\s+/).includes(token);
    const inSlugLoose = slugText.includes(token);
    const inSku = skuText.includes(token);
    const inDescription = descriptionText.includes(token);

    if (inName || inSlug) {
      titleHits += 1;
      score += 220;
    } else if (inNameLoose || inSlugLoose) {
      titleHits += 1;
      score += 170;
    } else if (inSku) {
      score += 80;
    } else if (inDescription) {
      score += 15;
    }
  }

  if (queryTokens.length > 0 && titleHits === queryTokens.length) {
    score += 260;
  }
  if (queryTokens.length > 0 && titleHits === 0) {
    score -= 120;
  }
  if (product.stock_status === 'instock') {
    score += 25;
  } else if (product.stock_status === 'outofstock') {
    score -= 10;
  }

  return score;
};

const sortedBody = productBody
  .map((product) => ({ ...product, match_score: scoreProduct(product) }))
  .sort((left, right) => right.match_score - left.match_score || String(left.name || '').localeCompare(String(right.name || '')));

return {
  ...productResponse,
  body: sortedBody,
  productSearch: {
    search_term: supportContext.productSearchTerm,
    requested_tokens: supportContext.productSearchTokens ?? [],
    result_count: sortedBody.length,
    top_match_name: sortedBody[0]?.name ?? null,
    top_match_url: sortedBody[0]?.permalink ?? null,
    top_match_score: sortedBody[0]?.match_score ?? null
  }
};
'@

$buildCode = @'
const supportContext = $('Gate Test Contact').first().json;
const orderResponse = $('Woo Order Lookup').first().json ?? {};
const productResponse = $('Sort Product Matches').first().json ?? {};

const stripHtml = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();

const orderBody = orderResponse.body ?? {};
const orderSummary = orderResponse.statusCode === 200 && orderBody.id
  ? {
      id: orderBody.id,
      status: orderBody.status,
      currency: orderBody.currency,
      total: orderBody.total,
      date_created: orderBody.date_created,
      billing_email: orderBody.billing?.email,
      billing_phone: orderBody.billing?.phone,
      line_items: Array.isArray(orderBody.line_items)
        ? orderBody.line_items.map((item) => ({
            product_id: item.product_id,
            name: item.name,
            quantity: item.quantity,
            total: item.total
          }))
        : []
    }
  : null;

const sortedProducts = Array.isArray(productResponse.body) ? productResponse.body : [];
const positiveProducts = sortedProducts.filter((product) => Number(product.match_score ?? 0) > 0);
const selectedProducts = (positiveProducts.length > 0 ? positiveProducts : sortedProducts).slice(0, 5);
const productSummary = selectedProducts.map((product) => ({
  id: product.id,
  name: product.name,
  slug: product.slug,
  sku: product.sku,
  price: product.price,
  regular_price: product.regular_price,
  sale_price: product.sale_price,
  stock_status: product.stock_status,
  permalink: product.permalink,
  short_description: stripHtml(product.short_description || product.description || ''),
  match_score: Number(product.match_score ?? 0)
}));

const bestProductMatch = productSummary[0] ?? null;
const hasRelevantProductMatch = Boolean(bestProductMatch && bestProductMatch.match_score >= 100);

const retrievedContext = {
  customer: {
    name: supportContext.contactName,
    phone_number: supportContext.contactPhone
  },
  routing: {
    processing_mode: supportContext.config.processingMode,
    gate_reason: supportContext.gateReason,
    labels: supportContext.labels
  },
  order_lookup: orderSummary,
  product_search: {
    search_term: productResponse.productSearch?.search_term ?? supportContext.productSearchTerm,
    requested_tokens: productResponse.productSearch?.requested_tokens ?? supportContext.productSearchTokens ?? [],
    raw_candidate_count: productResponse.productSearch?.result_count ?? sortedProducts.length,
    has_relevant_match: hasRelevantProductMatch,
    best_match_name: bestProductMatch?.name ?? null,
    best_match_url: bestProductMatch?.permalink ?? null,
    best_match_score: bestProductMatch?.match_score ?? null
  },
  product_lookup: productSummary,
  faq_matches: supportContext.faqMatches,
  recent_messages: supportContext.recentMessages,
  order_creation: {
    requested: supportContext.createOrderRequested,
    enabled: supportContext.config.orderCreationEnabled,
    instruction: supportContext.config.orderCreationEnabled
      ? 'Order creation is enabled only when all required fields are collected and explicitly confirmed.'
      : 'Order creation is disabled in this phase. If the customer wants to place an order, collect details and route to a human teammate.'
  }
};

const systemMessage = [
  'You are the Famivita AI customer support agent working inside Chatwoot.',
  'Reply in the same language as the customer whenever possible.',
  'Use only the retrieved context for factual claims about orders, products, shipping, returns, payment, or policies.',
  'product_lookup is already sorted by product-title relevance, so the first item is the best match for the customer message.',
  'If product_search.has_relevant_match is true, do not say the product is unavailable or missing from the catalog.',
  'If the best product has stock_status equal to outofstock, say it exists but is currently out of stock.',
  'If the retrieved context is missing or insufficient, say that clearly and ask one short clarifying question or suggest a human handoff.',
  'Never invent order status, delivery dates, product details, stock, prices, promotions, or medical advice.',
  'Keep replies concise, warm, and suitable for WhatsApp.',
  `If you need to escalate, direct the customer to ${supportContext.config.supportEmail}.`
].join('\n');

const userMessage = [
  `Latest customer message: ${supportContext.content}`,
  `Customer name: ${supportContext.contactName || 'Unknown customer'}`,
  `Retrieved context JSON: ${JSON.stringify(retrievedContext)}`
].join('\n\n');

return {
  accountId: supportContext.accountId,
  conversationId: supportContext.conversationId,
  chatwootBaseUrl: supportContext.config.chatwootBaseUrl,
  supportEmail: supportContext.config.supportEmail,
  openAiRequest: {
    model: supportContext.config.openAiModel,
    temperature: 0.2,
    messages: [
      {
        role: 'system',
        content: systemMessage
      },
      {
        role: 'user',
        content: userMessage
      }
    ]
  }
};
'@

$productUrl = @'
={{ $('Gate Test Contact').first().json.config.wooBaseUrl }}/wp-json/wc/v3/products?search={{ encodeURIComponent($('Gate Test Contact').first().json.productSearchTerm || $('Gate Test Contact').first().json.primaryProductToken || 'zzzz-no-match-zzzz') }}&per_page=30&status=publish
'@

($json.nodes | Where-Object { $_.name -eq 'Gate Test Contact' }).parameters.jsCode = $gateCode.Trim()
($json.nodes | Where-Object { $_.name -eq 'Woo Product Search' }).parameters.url = $productUrl.Trim()
($json.nodes | Where-Object { $_.name -eq 'Sort Product Matches' }).parameters.jsCode = $sortCode.Trim()
($json.nodes | Where-Object { $_.name -eq 'Build OpenAI Request' }).parameters.jsCode = $buildCode.Trim()

$json | ConvertTo-Json -Depth 100 | Set-Content -Path $target -Encoding UTF8
Write-Output $target
