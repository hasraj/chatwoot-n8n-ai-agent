$ErrorActionPreference = 'Stop'

$targets = @(
  'f:\github\chatwoot n8n ai agent\workflow.json',
  'f:\github\chatwoot n8n ai agent\chatwoot-ai-test-3-google-sheet.json'
)

$gateCode = @'
const event = $('Normalize Incoming Event').first().json;
const messageList = $input.first().json;

const normalizePhone = (value) => String(value || '').replace(/[^+\d]/g, '');
const stripHtml = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const normalizeText = (value) => String(value || '')
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
    answer: 'You can contact our support team at ' + event.config.supportEmail + '.'
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
  'items', 'produto', 'produtos', 'quero', 'preciso', 'gostaria', 'sobre', 'tenho', 'tem', 'uma', 'um',
  'support', 'human', 'agent', 'contact', 'return', 'refund', 'exchange', 'shipping', 'delivery', 'payment',
  'track', 'tracking', 'pedido', 'pedidos', 'email', 'mail', 'rastreio', 'rastrear', 'acompanhar'
]);

const normalizedSearchContent = normalizeText(event.content)
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
const hasEmailAddress = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i.test(event.content);
const orderSupportRequested = Boolean(
  event.detectedOrderId ||
  hasEmailAddress ||
  /(where\s+is\s+my\s+order|track(?:ing)?|order\s+status|status\s+of\s+my\s+order|my\s+order|pedido|rastreio|rastrear|acompanhar|status do pedido|meu pedido)/i.test(event.content)
);
const productLookupRequested = productSearchTokens.length > 0 && !orderSupportRequested;

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
  productLookupRequested,
  orderSupportRequested,
  hasEmailAddress,
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
const catalogResponse = $input.first().json ?? {};

const stripText = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const normalizeText = (value) => stripText(value)
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .toLowerCase();

const rows = Array.isArray(catalogResponse.body) ? catalogResponse.body : [];
const getCatalogTitle = (row) => row.custom_title || row.product_url || row.product_sku || row.unique_id || row.product_id || '';

const productLookupRequested = Boolean(supportContext.productLookupRequested);
const queryTokens = productLookupRequested && Array.isArray(supportContext.productSearchTokens) && supportContext.productSearchTokens.length > 0
  ? supportContext.productSearchTokens.map((token) => normalizeText(token)).filter(Boolean)
  : [];
const queryText = productLookupRequested
  ? normalizeText(supportContext.productSearchTerm || queryTokens.join(' '))
  : '';

if (!productLookupRequested || queryTokens.length === 0 || !queryText) {
  return {
    ...catalogResponse,
    body: rows.map((row) => ({
      ...row,
      catalog_title: getCatalogTitle(row),
      match_score: 0
    })),
    productSearch: {
      source: 'google_sheet',
      requested: false,
      search_term: supportContext.productSearchTerm,
      requested_tokens: supportContext.productSearchTokens ?? [],
      result_count: rows.length,
      top_match_name: null,
      top_match_url: null,
      top_match_score: null
    }
  };
}

const getSearchableFields = (row) => ({
  title: normalizeText(getCatalogTitle(row)),
  url: normalizeText(row.product_url),
  sku: normalizeText(row.product_sku),
  manufacturer: normalizeText(row.product_manufacturer),
  tags: normalizeText(row.product_tags),
  summary: normalizeText([row.custom_text, row.custom_text1, row.custom_text2].filter(Boolean).join(' ')),
  stock: normalizeText(row.stock_status),
  status: normalizeText(row.status),
  price: normalizeText(row.price),
  regularPrice: normalizeText(row.regular_price),
  salePrice: normalizeText(row.sale_price)
});

const scoreRow = (row) => {
  const fields = getSearchableFields(row);
  let score = 0;

  if (queryText) {
    if (fields.title === queryText) {
      score += 1400;
    }
    if (fields.title.startsWith(queryText)) {
      score += 950;
    }
    if (fields.title.includes(queryText)) {
      score += 700;
    }
    if (fields.url.includes(queryText)) {
      score += 350;
    }
  }

  let fieldHits = 0;
  for (const token of queryTokens) {
    if (fields.title.split(/\s+/).includes(token)) {
      fieldHits += 1;
      score += 220;
    } else if (fields.title.includes(token)) {
      fieldHits += 1;
      score += 170;
    } else if (fields.url.includes(token)) {
      fieldHits += 1;
      score += 120;
    } else if (fields.sku.includes(token)) {
      fieldHits += 1;
      score += 90;
    } else if (fields.tags.includes(token) || fields.manufacturer.includes(token)) {
      fieldHits += 1;
      score += 70;
    } else if (fields.summary.includes(token)) {
      fieldHits += 1;
      score += 25;
    }
  }

  if (queryTokens.length > 0 && fieldHits === queryTokens.length) {
    score += 260;
  }
  if (queryTokens.length > 0 && fieldHits === 0) {
    score -= 120;
  }

  if (fields.stock === 'instock') {
    score += 25;
  } else if (fields.stock === 'outofstock') {
    score -= 10;
  }

  if (fields.status === 'publish' || fields.status === 'active') {
    score += 5;
  }

  return score;
};

const sortedBody = rows
  .map((row) => ({
    ...row,
    catalog_title: getCatalogTitle(row),
    match_score: scoreRow(row)
  }))
  .sort((left, right) => right.match_score - left.match_score || String(left.catalog_title || '').localeCompare(String(right.catalog_title || '')));

return {
  ...catalogResponse,
  body: sortedBody,
  productSearch: {
    source: 'google_sheet',
    requested: true,
    search_term: supportContext.productSearchTerm,
    requested_tokens: supportContext.productSearchTokens ?? [],
    result_count: sortedBody.length,
    top_match_name: sortedBody[0]?.catalog_title ?? null,
    top_match_url: sortedBody[0]?.product_url ?? null,
    top_match_score: sortedBody[0]?.match_score ?? null
  }
};
'@

$buildCode = @'
const supportContext = $('Gate Test Contact').first().json;
const orderResponse = $('Woo Order Lookup').first().json ?? {};
const productResponse = $('Sort Product Matches').first().json ?? {};

const stripText = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();

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

const productLookupRequested = Boolean(supportContext.productLookupRequested);
const sortedProducts = Array.isArray(productResponse.body) ? productResponse.body : [];
const positiveProducts = sortedProducts.filter((product) => Number(product.match_score ?? 0) > 0);
const selectedProducts = productLookupRequested
  ? (positiveProducts.length > 0 ? positiveProducts : sortedProducts).slice(0, 5)
  : [];
const productSummary = selectedProducts.map((product) => ({
  product_id: product.product_id || '',
  variation_id: product.variation_id || '',
  unique_id: product.unique_id || '',
  title: product.catalog_title || product.custom_title || '',
  product_url: product.product_url || '',
  price: product.price || '',
  regular_price: product.regular_price || '',
  sale_price: product.sale_price || '',
  status: product.status || '',
  stock_status: product.stock_status || '',
  stock_quantity: product.stock_quantity || '',
  sku: product.product_sku || '',
  manufacturer: product.product_manufacturer || '',
  tags: product.product_tags || '',
  gtin: product.wpfoof_gtin_name || '',
  summary: stripText([product.custom_text, product.custom_text1, product.custom_text2].filter(Boolean).join(' | ')),
  match_score: Number(product.match_score ?? 0)
}));

const bestProductMatch = productSummary[0] ?? null;
const hasRelevantProductMatch = Boolean(productLookupRequested && bestProductMatch && bestProductMatch.match_score >= 300);

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
    source: 'google_sheet',
    requested: productLookupRequested,
    search_term: productResponse.productSearch?.search_term ?? supportContext.productSearchTerm,
    requested_tokens: productResponse.productSearch?.requested_tokens ?? supportContext.productSearchTokens ?? [],
    raw_candidate_count: productResponse.productSearch?.result_count ?? sortedProducts.length,
    has_relevant_match: hasRelevantProductMatch,
    best_match_name: hasRelevantProductMatch ? bestProductMatch?.title ?? null : null,
    best_match_url: hasRelevantProductMatch ? bestProductMatch?.product_url ?? null : null,
    best_match_score: hasRelevantProductMatch ? bestProductMatch?.match_score ?? null : null
  },
  product_lookup: hasRelevantProductMatch ? productSummary : [],
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
  'Only treat product_lookup as relevant when product_search.requested is true and product_search.has_relevant_match is true.',
  'If product_search.requested is false, do not mention products or include product URLs.',
  'If product_search.has_relevant_match is true, do not say the product is unavailable or missing from the catalog.',
  'If the best product has stock_status equal to outofstock, say it exists but is currently out of stock.',
  'When you confirm a product match and best_match_url is available, include that exact URL in the reply.',
  'If the retrieved context is missing or insufficient, say that clearly and ask one short clarifying question or suggest a human handoff.',
  'Never invent order status, delivery dates, product details, stock, prices, promotions, or medical advice.',
  'Keep replies concise, warm, and suitable for WhatsApp.',
  'If you need to escalate, direct the customer to ' + supportContext.config.supportEmail + '.'
].join('\n');

const userMessage = [
  'Latest customer message: ' + supportContext.content,
  'Customer name: ' + (supportContext.contactName || 'Unknown customer'),
  'Retrieved context JSON: ' + JSON.stringify(retrievedContext)
].join('\n\n');

return {
  accountId: supportContext.accountId,
  conversationId: supportContext.conversationId,
  chatwootBaseUrl: supportContext.config.chatwootBaseUrl,
  supportEmail: supportContext.config.supportEmail,
  productLookupRequested,
  hasRelevantProductMatch,
  bestProductUrl: hasRelevantProductMatch ? bestProductMatch?.product_url ?? null : null,
  bestProductName: hasRelevantProductMatch ? bestProductMatch?.title ?? null : null,
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

$prepareCode = @'
const requestContext = $('Build OpenAI Request').first().json;
const openAiResponse = $input.first().json;

let reply = '';
if (openAiResponse.statusCode === 200) {
  reply = String(openAiResponse.body?.choices?.[0]?.message?.content || '').trim();
}

if (!reply) {
  reply = `Thanks for your message. I need a human teammate to review this so we can help you correctly. You can also reach us at ${requestContext.supportEmail}.`;
}

reply = reply.replace(/^['\"]+|['\"]+$/g, '').trim();

const bestProductUrl = String(requestContext.bestProductUrl || '').trim();
if (requestContext.productLookupRequested && requestContext.hasRelevantProductMatch && bestProductUrl && !reply.includes(bestProductUrl)) {
  reply = `${reply}\n\n${bestProductUrl}`.trim();
}

return {
  accountId: requestContext.accountId,
  conversationId: requestContext.conversationId,
  chatwootBaseUrl: requestContext.chatwootBaseUrl,
  reply
};
'@

foreach ($path in $targets) {
  if (-not (Test-Path $path)) { continue }

  $json = Get-Content -Raw $path | ConvertFrom-Json

  ($json.nodes | Where-Object { $_.name -eq 'Gate Test Contact' }).parameters.jsCode = $gateCode.Trim()
  ($json.nodes | Where-Object { $_.name -eq 'Sort Product Matches' }).parameters.jsCode = $sortCode.Trim()
  ($json.nodes | Where-Object { $_.name -eq 'Build OpenAI Request' }).parameters.jsCode = $buildCode.Trim()
  ($json.nodes | Where-Object { $_.name -eq 'Prepare Chatwoot Reply' }).parameters.jsCode = $prepareCode.Trim()

  $json | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding UTF8
  Write-Output $path
}
