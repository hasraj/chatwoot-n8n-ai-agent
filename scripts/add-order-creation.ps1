$ErrorActionPreference = 'Stop'

$targets = @(
  'f:\github\chatwoot n8n ai agent\workflow.json'
)

$prepareOrderDraftCode = @'
const supportContext = $('Gate Test Contact').first().json;
const catalogResponse = $('Merge Product Catalog Rows').first().json ?? {};

const stripText = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const normalizeText = (value) => stripText(value).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const parseNumber = (value) => {
  const cleaned = String(value || '').replace(/[^0-9,.\-]/g, '').trim();
  if (!cleaned) return null;
  const normalized = cleaned.includes(',') && cleaned.includes('.')
    ? cleaned.replace(/\./g, '').replace(',', '.')
    : cleaned.replace(',', '.');
  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : null;
};
const getStaticStore = () => {
  try { if (typeof getWorkflowStaticData === 'function') return getWorkflowStaticData('global'); } catch (error) {}
  try { if (typeof $getWorkflowStaticData === 'function') return $getWorkflowStaticData('global'); } catch (error) {}
  return null;
};
const getCatalogTitle = (row) => row.custom_title || row.product_url || row.product_sku || row.unique_id || row.product_id || '';
const getCanonicalProductUrl = (value) => String(value || '').trim().split('?')[0];
const getVariationLabel = (row) => stripText(row.price_variation_txt_variable || row.price_variation_txt_static || '');
const getEffectivePrice = (row) => {
  for (const candidate of [row.sale_price, row.price, row.regular_price]) {
    const parsed = parseNumber(candidate);
    if (parsed !== null) return parsed;
  }
  return null;
};

const rows = Array.isArray(catalogResponse.body) ? catalogResponse.body : [];
const currentMessage = stripText(supportContext.content);
const recentCustomerMessages = Array.isArray(supportContext.recentMessages)
  ? supportContext.recentMessages.filter((message) => message.role === 'customer').map((message) => stripText(message.content)).filter(Boolean)
  : [];
const conversationMessages = [...recentCustomerMessages, currentMessage].filter(Boolean);
const conversationText = conversationMessages.join(' ');

const emailRegex = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/ig;
let billingEmail = '';
for (const message of conversationMessages) {
  const matches = [...message.matchAll(emailRegex)];
  if (matches.length > 0) billingEmail = String(matches[matches.length - 1][0] || '').trim().toLowerCase();
}

const quantityPatterns = [
  /(?:qty|quantity|quantidade)\s*[:=-]?\s*(\d{1,3})\b/i,
  /\b(\d{1,3})\s*(?:x|units?|unit|pcs?|pieces?|unidades?)\b/i
];
let quantity = null;
for (const message of conversationMessages) {
  for (const pattern of quantityPatterns) {
    const match = message.match(pattern);
    if (!match) continue;
    const parsed = Number.parseInt(match[1], 10);
    if (Number.isInteger(parsed) && parsed > 0) quantity = parsed;
    break;
  }
}

const orderIntentRegex = /(create|new|place|buy|purchase).{0,20}order|order.{0,20}(create|new|place|buy|purchase)|checkout|pay later|payment link|link to pay/i;
const orderConversationRequested = Boolean(supportContext.createOrderRequested || conversationMessages.some((message) => orderIntentRegex.test(message)));
const currentMessageOrderRelated = Boolean(
  orderIntentRegex.test(currentMessage) ||
  /\b(confirm|yes|payment|pay|link|checkout)\b/i.test(currentMessage) ||
  /@/.test(currentMessage) ||
  quantityPatterns.some((pattern) => pattern.test(currentMessage))
);
const orderActionRequested = Boolean(orderConversationRequested && currentMessageOrderRelated);

const productStopWords = new Set([
  'the','and','for','with','this','that','have','from','what','your','about','please','need','want',
  'know','tell','price','stock','order','where','when','does','will','show','much','how','can',
  'you','me','our','get','buy','make','create','status','hello','hi','product','products','item',
  'items','produto','produtos','quero','preciso','gostaria','sobre','tenho','tem','uma','um',
  'support','human','agent','contact','return','refund','exchange','shipping','delivery','payment',
  'track','tracking','pedido','pedidos','email','mail','rastreio','rastrear','acompanhar',
  'below','under','less','than','above','over','between','which','cheap','cheaper','cheapest',
  'abaixo','menor','acima','maior','entre','ate','yes','confirm','checkout','pay','later'
]);
const conversationProductTokens = [...new Set(
  normalizeText(conversationText)
    .replace(/order\s*#?\s*\d+/gi, ' ')
    .replace(/[^a-z0-9\s-]/g, ' ')
    .split(/\s+/)
    .filter((word) => word && word.length > 2 && !productStopWords.has(word) && !/^\d+$/.test(word))
)].sort((left, right) => right.length - left.length || left.localeCompare(right)).slice(0, 6);
const conversationSearchTerm = conversationProductTokens.join(' ');

const getSearchableFields = (row) => ({
  title: normalizeText(getCatalogTitle(row)),
  url: normalizeText(row.product_url),
  sku: normalizeText(row.product_sku),
  manufacturer: normalizeText(row.product_manufacturer),
  tags: normalizeText(row.product_tags),
  summary: normalizeText([row.custom_text, row.custom_text1, row.custom_text2].filter(Boolean).join(' ')),
  variation: normalizeText(getVariationLabel(row)),
  stock: normalizeText(row.stock_status),
  status: normalizeText(row.status)
});

const scoreRow = (row) => {
  const fields = getSearchableFields(row);
  let score = 0;
  if (conversationSearchTerm) {
    if (fields.title === conversationSearchTerm) score += 1400;
    if (fields.title.startsWith(conversationSearchTerm)) score += 950;
    if (fields.title.includes(conversationSearchTerm)) score += 700;
    if (fields.url.includes(conversationSearchTerm)) score += 350;
  }
  let fieldHits = 0;
  for (const token of conversationProductTokens) {
    if (fields.title.split(/\s+/).includes(token)) { fieldHits += 1; score += 220; }
    else if (fields.title.includes(token)) { fieldHits += 1; score += 170; }
    else if (fields.variation.includes(token)) { fieldHits += 1; score += 150; }
    else if (fields.url.includes(token)) { fieldHits += 1; score += 120; }
    else if (fields.sku.includes(token)) { fieldHits += 1; score += 90; }
    else if (fields.tags.includes(token) || fields.manufacturer.includes(token)) { fieldHits += 1; score += 70; }
    else if (fields.summary.includes(token)) { fieldHits += 1; score += 25; }
  }
  if (conversationProductTokens.length > 0 && fieldHits === conversationProductTokens.length) score += 260;
  if (conversationProductTokens.length > 0 && fieldHits === 0) score -= 120;
  if (fields.stock === 'instock') score += 25;
  else if (fields.stock === 'outofstock') score -= 10;
  if (fields.status === 'publish' || fields.status === 'active') score += 5;
  return score;
};

const candidateRows = conversationProductTokens.length > 0
  ? rows.map((row) => ({
      ...row,
      catalog_title: getCatalogTitle(row),
      canonical_product_url: getCanonicalProductUrl(row.product_url),
      variation_label: getVariationLabel(row),
      effective_price: getEffectivePrice(row),
      match_score: scoreRow(row)
    })).filter((row) => row.match_score > 0)
      .sort((left, right) => right.match_score - left.match_score || String(left.catalog_title || '').localeCompare(String(right.catalog_title || '')))
  : [];

const bestProduct = candidateRows[0] ?? null;
const sameProductRows = bestProduct ? candidateRows.filter((row) => String(row.product_id || '') === String(bestProduct.product_id || '')) : [];
const uniqueVariations = [];
const seenVariationKeys = new Set();
for (const row of sameProductRows) {
  const variationKey = String(row.variation_id || row.canonical_product_url || row.product_url || row.unique_id || '').trim();
  if (!variationKey || seenVariationKeys.has(variationKey)) continue;
  seenVariationKeys.add(variationKey);
  uniqueVariations.push(row);
}

const variationAmbiguous = Boolean(bestProduct && uniqueVariations.length > 1 && (Number(uniqueVariations[0]?.match_score ?? 0) - Number(uniqueVariations[1]?.match_score ?? 0) < 80));
const selectedProduct = bestProduct && !variationAmbiguous ? {
  product_id: bestProduct.product_id || '',
  variation_id: bestProduct.variation_id || '',
  title: bestProduct.catalog_title || '',
  product_url: bestProduct.canonical_product_url || bestProduct.product_url || '',
  variation_label: bestProduct.variation_label || '',
  price: bestProduct.price || '',
  effective_price: bestProduct.effective_price ?? null,
  match_score: Number(bestProduct.match_score ?? 0)
} : null;
const variationOptions = variationAmbiguous ? uniqueVariations.slice(0, 4).map((row) => ({
  product_id: row.product_id || '',
  variation_id: row.variation_id || '',
  title: row.catalog_title || '',
  variation_label: row.variation_label || '',
  product_url: row.canonical_product_url || row.product_url || '',
  price: row.price || '',
  effective_price: row.effective_price ?? null,
  match_score: Number(row.match_score ?? 0)
})) : [];

const staticStore = getStaticStore();
const createdOrders = staticStore ? (staticStore.chatwootCreatedWooOrders = staticStore.chatwootCreatedWooOrders || {}) : {};
const now = Date.now();
for (const [key, value] of Object.entries(createdOrders)) {
  const timestamp = value?.createdAt ?? value?.created_at ?? value?.timestamp;
  if (!timestamp || now - Number(timestamp) > 7 * 24 * 60 * 60 * 1000) delete createdOrders[key];
}

const missingFields = [];
if (!selectedProduct && variationOptions.length === 0) missingFields.push('product');
if (!Number.isInteger(quantity) || quantity <= 0) missingFields.push('quantity');
if (!billingEmail) missingFields.push('email');
if (variationOptions.length > 0) missingFields.push('variation');

const orderSignature = selectedProduct && billingEmail && Number.isInteger(quantity) && quantity > 0
  ? [supportContext.conversationId || '', selectedProduct.product_id || '', selectedProduct.variation_id || '0', quantity, billingEmail].join(':')
  : '';
const existingOrder = orderSignature && createdOrders[orderSignature] ? createdOrders[orderSignature] : null;

let orderCreationStatus = 'not_requested';
if (orderActionRequested) {
  if (!supportContext.config.orderCreationEnabled) orderCreationStatus = 'disabled';
  else if (existingOrder) orderCreationStatus = 'existing_order';
  else if (missingFields.length > 0) orderCreationStatus = 'needs_info';
  else orderCreationStatus = 'ready_to_create';
}

let orderPayload = null;
if (orderCreationStatus === 'ready_to_create' && selectedProduct) {
  const lineItem = { product_id: Number.parseInt(selectedProduct.product_id, 10), quantity };
  const parsedVariationId = Number.parseInt(selectedProduct.variation_id || '0', 10);
  if (Number.isInteger(parsedVariationId) && parsedVariationId > 0) lineItem.variation_id = parsedVariationId;
  orderPayload = {
    status: 'pending',
    set_paid: false,
    billing: {
      first_name: supportContext.contactName || 'WhatsApp Customer',
      email: billingEmail,
      phone: supportContext.contactPhone || ''
    },
    line_items: [lineItem],
    customer_note: `Created from Chatwoot conversation ${supportContext.conversationId}.`,
    meta_data: [
      { key: '_chatwoot_conversation_id', value: String(supportContext.conversationId || '') },
      { key: '_chatwoot_contact_phone', value: String(supportContext.contactPhone || '') }
    ]
  };
}

return {
  conversationId: supportContext.conversationId,
  orderConversationRequested,
  orderActionRequested,
  orderCreationStatus,
  missingFields,
  billingEmail,
  quantity,
  product: selectedProduct,
  variationOptions,
  orderSignature,
  existingOrder,
  orderPayload
};
'@

$buildCode = @'
const supportContext = $('Gate Test Contact').first().json;
const orderResponse = $('Woo Order Lookup').first().json ?? {};
const productResponse = $('Sort Product Matches').first().json ?? {};
let orderDraft = {};
try { orderDraft = $('Prepare Woo Order Draft').first().json ?? {}; } catch (error) { orderDraft = {}; }
let createOrderResponse = null;
try { createOrderResponse = $('Woo Create Order').first().json ?? null; } catch (error) { createOrderResponse = null; }

const stripText = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const getStaticStore = () => {
  try { if (typeof getWorkflowStaticData === 'function') return getWorkflowStaticData('global'); } catch (error) {}
  try { if (typeof $getWorkflowStaticData === 'function') return $getWorkflowStaticData('global'); } catch (error) {}
  return null;
};

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
      line_items: Array.isArray(orderBody.line_items) ? orderBody.line_items.map((item) => ({
        product_id: item.product_id,
        name: item.name,
        quantity: item.quantity,
        total: item.total
      })) : []
    }
  : null;

const productLookupRequested = Boolean(supportContext.productLookupRequested);
const priceFilter = supportContext.priceFilter ?? { requested: false, min: null, max: null };
const priceFilterRequested = Boolean(priceFilter.requested);
const sortedProducts = Array.isArray(productResponse.body) ? productResponse.body : [];
const positiveProducts = sortedProducts.filter((product) => Number(product.match_score ?? 0) > 0);
const selectedProducts = productLookupRequested ? (positiveProducts.length > 0 ? positiveProducts : sortedProducts).slice(0, 5) : [];
const productSummary = selectedProducts.map((product) => ({
  product_id: product.product_id || '',
  variation_id: product.variation_id || '',
  unique_id: product.unique_id || '',
  title: product.catalog_title || product.custom_title || '',
  product_url: product.canonical_product_url || product.product_url || '',
  price: product.price || '',
  regular_price: product.regular_price || '',
  sale_price: product.sale_price || '',
  effective_price: product.effective_price ?? null,
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
const hasRelevantProductMatch = Boolean(
  productLookupRequested &&
  bestProductMatch &&
  (priceFilterRequested ? productSummary.length > 0 : bestProductMatch.match_score >= 300)
);
const priceMatchedProducts = priceFilterRequested && hasRelevantProductMatch ? productSummary.slice(0, 5) : [];
const buildOrderPayUrl = (wooBaseUrl, orderId, orderKey) => {
  if (!wooBaseUrl || !orderId || !orderKey) return null;
  return `${String(wooBaseUrl).replace(/\/$/, '')}/checkout/order-pay/${orderId}/?pay_for_order=true&key=${orderKey}`;
};

const staticStore = getStaticStore();
const createdOrders = staticStore ? (staticStore.chatwootCreatedWooOrders = staticStore.chatwootCreatedWooOrders || {}) : {};

let orderCreationStatus = orderDraft.orderCreationStatus || 'not_requested';
let createdOrder = null;
if (createOrderResponse?.statusCode && [200, 201].includes(Number(createOrderResponse.statusCode)) && createOrderResponse.body?.id) {
  const body = createOrderResponse.body;
  const payUrl = buildOrderPayUrl(supportContext.config.wooBaseUrl, body.id, body.order_key);
  createdOrder = {
    id: body.id,
    status: body.status,
    order_key: body.order_key,
    pay_url: payUrl,
    total: body.total,
    billing_email: body.billing?.email || orderDraft.billingEmail || '',
    quantity: orderDraft.quantity || null,
    product_title: orderDraft.product?.title || '',
    createdAt: Date.now()
  };
  orderCreationStatus = 'created';
  if (orderDraft.orderSignature && staticStore) createdOrders[orderDraft.orderSignature] = createdOrder;
} else if (orderDraft.orderCreationStatus === 'existing_order' && orderDraft.existingOrder) {
  createdOrder = orderDraft.existingOrder;
}

const orderPayUrl = createdOrder?.pay_url ?? null;
const retrievedContext = {
  customer: { name: supportContext.contactName, phone_number: supportContext.contactPhone },
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
    price_filter: priceFilter,
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
    requested: Boolean(orderDraft.orderConversationRequested),
    action_requested: Boolean(orderDraft.orderActionRequested),
    enabled: supportContext.config.orderCreationEnabled,
    status: orderCreationStatus,
    missing_fields: orderDraft.missingFields ?? [],
    billing_email: orderDraft.billingEmail || '',
    quantity: orderDraft.quantity || null,
    product: orderDraft.product ?? null,
    variation_options: orderDraft.variationOptions ?? [],
    pay_url: orderPayUrl,
    created_order_id: createdOrder?.id ?? null,
    error_status: createOrderResponse?.statusCode ?? null
  }
};

const systemMessage = [
  'You are the Famivita AI customer support agent working inside Chatwoot.',
  'Reply in the same language as the customer whenever possible.',
  'Use only the retrieved context for factual claims about orders, products, shipping, returns, payment, or policies.',
  'Only treat product_lookup as relevant when product_search.requested is true and product_search.has_relevant_match is true.',
  'If product_search.requested is false, do not mention products or include product URLs.',
  'If product_search.has_relevant_match is true, do not say the product is unavailable or missing from the catalog.',
  'If product_search.price_filter.requested is true and product_lookup has matches, list up to 3 matching products with name, price, and product_url.',
  'If product_search.price_filter.requested is true and product_lookup is empty, clearly say that no products were found for that price range.',
  'If order_creation.status is created or existing_order, confirm that the order is ready and include the exact pay_url.',
  'If order_creation.status is needs_info, ask only for the missing fields.',
  'If the best product has stock_status equal to outofstock, say it exists but is currently out of stock.',
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
  customerName: supportContext.contactName || '',
  originalMessage: supportContext.content,
  productLookupRequested,
  priceFilterRequested,
  priceFilter,
  priceMatchedProducts,
  hasRelevantProductMatch,
  bestProductUrl: (!priceFilterRequested && hasRelevantProductMatch) ? bestProductMatch?.product_url ?? null : null,
  bestProductName: hasRelevantProductMatch ? bestProductMatch?.title ?? null : null,
  orderConversationRequested: Boolean(orderDraft.orderConversationRequested),
  orderActionRequested: Boolean(orderDraft.orderActionRequested),
  orderCreationStatus,
  orderMissingFields: orderDraft.missingFields ?? [],
  orderDraftEmail: orderDraft.billingEmail || '',
  orderDraftQuantity: orderDraft.quantity || null,
  orderDraftProductTitle: orderDraft.product?.title || '',
  orderDraftProductUrl: orderDraft.product?.product_url || '',
  orderVariationOptions: orderDraft.variationOptions ?? [],
  orderPayUrl,
  createdOrderId: createdOrder?.id ?? null,
  openAiRequest: {
    model: supportContext.config.openAiModel,
    temperature: 0.2,
    messages: [
      { role: 'system', content: systemMessage },
      { role: 'user', content: userMessage }
    ]
  }
};
'@

$prepareReplyCode = @'
const requestContext = $('Build OpenAI Request').first().json;
const openAiResponse = $input.first().json;

const parseNumber = (value) => {
  const parsed = Number.parseFloat(String(value ?? '').replace(/[^0-9.\-]/g, ''));
  return Number.isFinite(parsed) ? parsed : null;
};
const formatMoney = (value) => {
  const parsed = parseNumber(value);
  return parsed === null ? null : `R$ ${parsed.toFixed(2).replace('.', ',')}`;
};
const formatPrice = (product) => {
  for (const candidate of [product.effective_price, product.sale_price, product.price, product.regular_price]) {
    const formatted = formatMoney(candidate);
    if (formatted) return formatted;
  }
  return null;
};
const looksPortuguese = (text) => /[ãõáéíóúç]|\b(produtos?|preco|preço|abaixo|acima|entre|pedido|quero|preciso|gostaria|tenho|posso|sim|nao|não|quantidade|email)\b/i.test(String(text || ''));
const isPortuguese = looksPortuguese(requestContext.originalMessage);
const greetingName = String(requestContext.customerName || '').trim();
const greeting = greetingName ? (isPortuguese ? `Olá ${greetingName}!` : `Hello ${greetingName}!`) : (isPortuguese ? 'Olá!' : 'Hello!');
const sanitizeTitle = (product) => {
  const title = String(product?.title || '').trim();
  if (title) return title;
  const url = String(product?.product_url || '').trim();
  if (!url) return isPortuguese ? 'Produto sem nome' : 'Unnamed product';
  const slug = url.split('/').filter(Boolean).pop() || url;
  return slug.replace(/[-_]+/g, ' ');
};
const formatRangeText = (priceFilter) => {
  const min = parseNumber(priceFilter?.min);
  const max = parseNumber(priceFilter?.max);
  if (min !== null && max !== null) return isPortuguese ? `entre R$ ${min.toFixed(2).replace('.', ',')} e R$ ${max.toFixed(2).replace('.', ',')}` : `between R$ ${min.toFixed(2).replace('.', ',')} and R$ ${max.toFixed(2).replace('.', ',')}`;
  if (max !== null) return isPortuguese ? `abaixo de R$ ${max.toFixed(2).replace('.', ',')}` : `below R$ ${max.toFixed(2).replace('.', ',')}`;
  if (min !== null) return isPortuguese ? `acima de R$ ${min.toFixed(2).replace('.', ',')}` : `above R$ ${min.toFixed(2).replace('.', ',')}`;
  return isPortuguese ? 'nessa faixa de preço' : 'in that price range';
};
const formatMissingFields = (fields) => {
  const uniqueFields = [...new Set(Array.isArray(fields) ? fields : [])];
  const mapPt = { product: 'o produto', quantity: 'a quantidade', email: 'o e-mail', variation: 'a opção/tamanho' };
  const mapEn = { product: 'the product', quantity: 'the quantity', email: 'the email', variation: 'the option/size' };
  const labels = uniqueFields.map((field) => isPortuguese ? (mapPt[field] || field) : (mapEn[field] || field));
  if (labels.length <= 1) return labels[0] || '';
  return `${labels.slice(0, -1).join(', ')} ${isPortuguese ? 'e' : 'and'} ${labels[labels.length - 1]}`;
};

let reply = '';
if (requestContext.orderActionRequested) {
  if (requestContext.orderCreationStatus === 'created' || requestContext.orderCreationStatus === 'existing_order') {
    const quantityText = requestContext.orderDraftQuantity ? String(requestContext.orderDraftQuantity) : '1';
    const productTitle = String(requestContext.orderDraftProductTitle || 'the selected product').trim();
    const payUrl = String(requestContext.orderPayUrl || '').trim();
    reply = isPortuguese
      ? `${greeting} Seu pedido de ${quantityText} unidade(s) de ${productTitle} foi preparado. Você pode concluir o pagamento por este link:\n${payUrl}\n\nE-mail do pedido: ${requestContext.orderDraftEmail}`
      : `${greeting} Your order for ${quantityText} unit(s) of ${productTitle} is ready. You can complete the payment using this link:\n${payUrl}\n\nOrder email: ${requestContext.orderDraftEmail}`;
  } else if (requestContext.orderCreationStatus === 'needs_info') {
    const missingFields = Array.isArray(requestContext.orderMissingFields) ? requestContext.orderMissingFields : [];
    if (missingFields.includes('variation') && Array.isArray(requestContext.orderVariationOptions) && requestContext.orderVariationOptions.length > 0) {
      const productTitle = String(requestContext.orderDraftProductTitle || 'this product').trim();
      const optionsText = requestContext.orderVariationOptions.slice(0, 4).map((option) => {
        const title = sanitizeTitle(option);
        const label = String(option.variation_label || '').trim();
        const priceText = formatPrice(option);
        return `- ${title}${label ? ` (${label})` : ''}${priceText ? `: ${priceText}` : ''}`;
      }).join('\n');
      const remaining = missingFields.filter((field) => field !== 'variation');
      reply = isPortuguese
        ? `${greeting} Encontrei mais de uma opção para ${productTitle}. Antes de criar o pedido, me diga qual opção você quer:\n${optionsText}${remaining.length ? `\n\nDepois disso, também preciso de ${formatMissingFields(remaining)}.` : ''}`
        : `${greeting} I found more than one option for ${productTitle}. Before I create the order, please tell me which option you want:\n${optionsText}${remaining.length ? `\n\nAfter that, I also need ${formatMissingFields(remaining)}.` : ''}`;
    } else {
      reply = isPortuguese
        ? `${greeting} Para criar o pedido agora, eu só preciso de ${formatMissingFields(missingFields)}.`
        : `${greeting} To create the order now, I just need ${formatMissingFields(missingFields)}.`;
    }
  } else if (requestContext.orderCreationStatus === 'disabled') {
    reply = isPortuguese
      ? `${greeting} No momento, a criação automática de pedidos ainda está desativada.`
      : `${greeting} Automatic order creation is currently disabled.`;
  }
}

if (!reply && requestContext.priceFilterRequested) {
  const matches = Array.isArray(requestContext.priceMatchedProducts) ? requestContext.priceMatchedProducts.slice(0, 3) : [];
  const rangeText = formatRangeText(requestContext.priceFilter);
  if (matches.length > 0) {
    const intro = isPortuguese ? `${greeting} Encontrei alguns produtos ${rangeText}:` : `${greeting} I found some products ${rangeText}:`;
    const lines = matches.map((product) => {
      const title = sanitizeTitle(product);
      const priceText = formatPrice(product);
      const url = String(product.product_url || '').trim();
      return `- ${title}${priceText ? `: ${priceText}` : ''}${url ? ` - ${url}` : ''}`;
    });
    const closing = isPortuguese ? 'Se quiser, posso procurar outra faixa de preço ou um produto específico.' : 'If you want, I can look for another price range or a specific product.';
    reply = [intro, ...lines, closing].join('\n');
  } else {
    reply = isPortuguese
      ? `${greeting} No momento, não encontrei produtos ${rangeText} no catálogo. Se quiser, posso procurar outra faixa de preço ou encaminhar para um atendente.`
      : `${greeting} I couldn't find products ${rangeText} in the catalog right now. If you want, I can search another price range or hand this over to a human agent.`;
  }
}

if (!reply) {
  if (openAiResponse.statusCode === 200) reply = String(openAiResponse.body?.choices?.[0]?.message?.content || '').trim();
  if (!reply) reply = `Thanks for your message. I need a human teammate to review this so we can help you correctly. You can also reach us at ${requestContext.supportEmail}.`;
  reply = reply.replace(/^['\"]+|['\"]+$/g, '').trim();
  const bestProductUrl = String(requestContext.bestProductUrl || '').trim();
  if (!requestContext.priceFilterRequested && requestContext.productLookupRequested && requestContext.hasRelevantProductMatch && bestProductUrl && !reply.includes(bestProductUrl)) {
    reply = `${reply}\n\n${bestProductUrl}`.trim();
  }
}

return {
  accountId: requestContext.accountId,
  conversationId: requestContext.conversationId,
  chatwootBaseUrl: requestContext.chatwootBaseUrl,
  reply
};
'@

function Ensure-Node {
  param(
    [Parameter(Mandatory = $true)] $Json,
    [Parameter(Mandatory = $true)] [hashtable] $Node
  )

  $existing = $Json.nodes | Where-Object { $_.name -eq $Node.name }
  if ($existing) {
    foreach ($prop in $Node.Keys) { $existing.$prop = $Node[$prop] }
    return
  }

  $Json.nodes += [pscustomobject]$Node
}

function Set-Connection {
  param(
    [Parameter(Mandatory = $true)] $Connections,
    [Parameter(Mandatory = $true)] [string] $Name,
    [Parameter(Mandatory = $true)] $Value
  )

  $existing = $Connections.PSObject.Properties[$Name]
  if ($existing) {
    $existing.Value = $Value
    return
  }

  $Connections | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
}

foreach ($path in $targets) {
  if (-not (Test-Path $path)) { continue }
  $json = Get-Content -Raw $path | ConvertFrom-Json
  ($json.nodes | Where-Object { $_.name -eq 'Build OpenAI Request' }).parameters.jsCode = $buildCode.Trim()
  ($json.nodes | Where-Object { $_.name -eq 'Prepare Chatwoot Reply' }).parameters.jsCode = $prepareReplyCode.Trim()

  Ensure-Node -Json $json -Node @{ parameters = @{ jsCode = $prepareOrderDraftCode.Trim() }; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2520, 60); id = '0d45bdf2-3c9e-49af-a9a4-prepare-woo-order-draft'; name = 'Prepare Woo Order Draft' }
  Ensure-Node -Json $json -Node @{ parameters = @{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'strict'; version = 2 }; conditions = @(@{ id = '4fd707ff-53a2-45f6-b4a3-should-create-woo-order'; leftValue = '={{ $json.orderCreationStatus }}'; rightValue = 'ready_to_create'; operator = @{ type = 'string'; operation = 'equals' } }); combinator = 'and' }; options = @{} }; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(2740, 60); id = 'd8f644a4-0e11-4c4f-9a64-should-create-order'; name = 'Should Create Order?' }
  Ensure-Node -Json $json -Node @{ parameters = @{ method = 'POST'; url = '={{ $(''Gate Test Contact'').first().json.config.wooBaseUrl }}/wp-json/wc/v3/orders?consumer_key={{ $env.WOOCOMMERCE_CONSUMER_KEY }}&consumer_secret={{ $env.WOOCOMMERCE_CONSUMER_SECRET }}'; sendHeaders = $true; headerParameters = @{ parameters = @(@{ name = 'accept'; value = 'application/json' }, @{ name = 'content-type'; value = 'application/json' }) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={{ $json.orderPayload }}'; options = @{ response = @{ response = @{ fullResponse = $true; neverError = $true } } } }; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4.2; position = @(2960, 20); id = 'b4e36d41-0c61-4b9a-84f3-woo-create-order'; name = 'Woo Create Order'; alwaysOutputData = $true; onError = 'continueRegularOutput' }

  Set-Connection -Connections $json.connections -Name 'Sort Product Matches' -Value @{ main = ,(@(@{ node = 'Prepare Woo Order Draft'; type = 'main'; index = 0 })) }
  Set-Connection -Connections $json.connections -Name 'Prepare Woo Order Draft' -Value @{ main = ,(@(@{ node = 'Should Create Order?'; type = 'main'; index = 0 })) }
  Set-Connection -Connections $json.connections -Name 'Should Create Order?' -Value @{ main = @(@(@{ node = 'Woo Create Order'; type = 'main'; index = 0 }), @(@{ node = 'Build OpenAI Request'; type = 'main'; index = 0 })) }
  Set-Connection -Connections $json.connections -Name 'Woo Create Order' -Value @{ main = ,(@(@{ node = 'Build OpenAI Request'; type = 'main'; index = 0 })) }

  $json | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding UTF8
  Write-Output $path
}
