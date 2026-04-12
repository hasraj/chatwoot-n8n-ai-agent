$ErrorActionPreference = 'Stop'

$targets = @(
  'f:\github\chatwoot n8n ai agent\Test_ chatwoot ai with order create.json'
)

$wooCanonicalBaseUrl = 'https://www.famivita.com.br'

$prepareOrderDraftCode = @'
const supportContext = $('Gate Test Contact').first().json;
const catalogResponse = $('Merge Product Catalog Rows').first().json ?? {};

const stripText = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const normalizeText = (value) => stripText(value).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const compactText = (value) => normalizeText(value).replace(/\s+/g, '');
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
const buildProductOption = (row) => row ? ({
  product_id: row.product_id || '',
  variation_id: row.variation_id || '',
  title: row.catalog_title || getCatalogTitle(row) || '',
  product_url: row.canonical_product_url || getCanonicalProductUrl(row.product_url) || row.product_url || '',
  variation_label: row.variation_label || getVariationLabel(row) || '',
  price: row.price || '',
  effective_price: row.effective_price ?? getEffectivePrice(row),
  match_score: Number(row.match_score ?? 0)
}) : null;
const extractWithPatterns = (text, patterns) => {
  const value = String(text || '');
  for (const pattern of patterns) {
    const match = value.match(pattern);
    if (match && match[1]) return String(match[1]).trim();
  }
  return '';
};
const extractLastValue = (messages, extractor) => {
  let value = '';
  for (const message of messages) {
    const parsed = extractor(message);
    if (parsed) value = parsed;
  }
  return value;
};
const normalizeCpf = (value) => {
  const digits = String(value || '').replace(/\D/g, '');
  if (digits.length === 11) {
    return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6, 9)}-${digits.slice(9, 11)}`;
  }
  return '';
};
const normalizePostcode = (value) => {
  const digits = String(value || '').replace(/\D/g, '');
  if (digits.length === 8) {
    return `${digits.slice(0, 5)}-${digits.slice(5, 8)}`;
  }
  return '';
};
const normalizeState = (value) => {
  const trimmed = String(value || '').trim();
  return trimmed.length <= 3 ? trimmed.toUpperCase() : trimmed;
};
const extractLastEmail = (messages) => {
  const emailRegex = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/ig;
  let email = '';
  for (const message of messages) {
    const matches = [...String(message || '').matchAll(emailRegex)];
    if (matches.length > 0) email = String(matches[matches.length - 1][0] || '').trim().toLowerCase();
  }
  return email;
};
const extractBillingCpf = (text) => normalizeCpf(extractWithPatterns(text, [
  /\b(?:cpf|billing[_ ]?cpf)\b\s*[:=-]?\s*([0-9.\-]{11,18})/i,
  /^\s*([0-9.\-]{11,18})\s*$/
]));
const extractBillingAddress1 = (text) => extractWithPatterns(text, [
  /\b(?:address|billing address|endereco|endereço|rua)\b\s*[:=-]?\s*(.+?)(?=(?:\s+\b(?:number|numero|número|city|cidade|state|estado|uf|postcode|cep|cpf)\b)|$)/i
]);
const extractBillingNumber = (text) => extractWithPatterns(text, [
  /\b(?:number|numero|número|billing number)\b\s*[:=-]?\s*([A-Za-z0-9\-\/]{1,20})/i
]);
const extractBillingCity = (text) => extractWithPatterns(text, [
  /\b(?:city|cidade)\b\s*[:=-]?\s*([^\n,]{2,60})/i
]);
const extractBillingState = (text) => normalizeState(extractWithPatterns(text, [
  /\b(?:state|estado|uf)\b\s*[:=-]?\s*([A-Za-z]{2,30})/i
]));
const extractBillingPostcode = (text) => normalizePostcode(extractWithPatterns(text, [
  /\b(?:postcode|zip(?:\s*code)?|cep)\b\s*[:=-]?\s*([0-9\-]{8,10})/i,
  /^\s*([0-9\-]{8,10})\s*$/
]));
const extractQuantity = (text) => {
  for (const pattern of quantityPatterns) {
    const match = String(text || '').match(pattern);
    if (!match) continue;
    const parsed = Number.parseInt(match[1], 10);
    if (Number.isInteger(parsed) && parsed > 0) return parsed;
  }
  return null;
};
const extractLastQuantity = (messages) => {
  let quantity = null;
  for (const message of messages) {
    const parsed = extractQuantity(message);
    if (parsed !== null) quantity = parsed;
  }
  return quantity;
};
const extractMeasureTokens = (text) => [...new Set(
  (normalizeText(text).match(/\b\d+\s?(?:g|kg|ml|capsulas?|capsules?|comprimidos?|saches?|sachets?|tiras?|unidades?|weeks?|semanas?)\b/g) || [])
    .map((token) => token.replace(/\s+/g, ''))
)];
const containsMeasureToken = (value, token) => compactText(value).includes(String(token || '').replace(/\s+/g, ''));
const parseChoiceIndex = (text) => {
  const normalized = normalizeText(text);
  const patterns = [
    { regex: /\b(first|1st|option 1|opcao 1|opção 1)\b/, index: 0 },
    { regex: /\b(second|2nd|option 2|opcao 2|opção 2)\b/, index: 1 },
    { regex: /\b(third|3rd|option 3|opcao 3|opção 3)\b/, index: 2 },
    { regex: /\b(fourth|4th|option 4|opcao 4|opção 4)\b/, index: 3 }
  ];
  for (const entry of patterns) {
    if (entry.regex.test(normalized)) return entry.index;
  }
  const numericMatch = normalized.match(/\boption\s*(\d)\b/);
  if (numericMatch) {
    const parsed = Number.parseInt(numericMatch[1], 10);
    if (Number.isInteger(parsed) && parsed >= 1 && parsed <= 4) return parsed - 1;
  }
  return null;
};
const chooseOptionFromMessage = (options, message) => {
  if (!Array.isArray(options) || options.length === 0) return null;
  const currentText = normalizeText(message);
  const currentCompact = compactText(message);
  const choiceIndex = parseChoiceIndex(message);
  if (choiceIndex !== null && options[choiceIndex]) return options[choiceIndex];
  const measureTokens = extractMeasureTokens(message);
  const scored = options.map((option) => {
    const optionTitle = normalizeText(option.title);
    const optionVariation = normalizeText(option.variation_label);
    const optionUrl = normalizeText(option.product_url);
    const optionText = normalizeText([option.title, option.variation_label, option.product_url].filter(Boolean).join(' '));
    const optionCompact = compactText([option.title, option.variation_label].filter(Boolean).join(' '));
    const titleTokens = optionTitle.split(/\s+/).filter((token) => token && token.length > 2);
    let score = 0;
    if (currentText && currentText.length > 2) {
      if (optionText === currentText) score += 1200;
      if (optionText.includes(currentText)) score += 800;
      if (currentText.includes(optionText)) score += 950;
      if (optionTitle === currentText) score += 1000;
      if (optionVariation === currentText) score += 900;
      if (optionTitle && currentText.includes(optionTitle)) score += 1000;
      if (optionVariation && currentText.includes(optionVariation)) score += 850;
      if (optionUrl && currentText.includes(optionUrl)) score += 900;
    }
    if (currentCompact && optionCompact) {
      if (currentCompact === optionCompact) score += 1200;
      if (currentCompact.includes(optionCompact)) score += 1000;
    }
    let tokenHits = 0;
    for (const token of titleTokens) {
      if (currentText.includes(token)) tokenHits += 1;
    }
    if (titleTokens.length > 0) {
      if (tokenHits === titleTokens.length) score += 900;
      else if (tokenHits >= Math.max(2, Math.ceil(titleTokens.length * 0.6))) score += 550;
    }
    for (const token of measureTokens) {
      if (containsMeasureToken(optionText, token)) score += 700;
    }
    return { option, score };
  }).filter((entry) => entry.score > 0).sort((left, right) => right.score - left.score);
  if (scored.length === 0) return null;
  if (scored.length === 1) return scored[0].option;
  if (scored[0].score > scored[1].score) return scored[0].option;
  return null;
};

const rows = Array.isArray(catalogResponse.body) ? catalogResponse.body : [];
const currentMessage = stripText(supportContext.content);
const recentCustomerMessages = Array.isArray(supportContext.recentMessages)
  ? supportContext.recentMessages.filter((message) => message.role === 'customer').map((message) => stripText(message.content)).filter(Boolean)
  : [];
const recentAgentMessages = Array.isArray(supportContext.recentMessages)
  ? supportContext.recentMessages.filter((message) => message.role === 'agent').map((message) => stripText(message.content)).filter(Boolean)
  : [];
const normalizedRecentAgentMessages = recentAgentMessages.map((message) => normalizeText(message));
const conversationMessages = [...recentCustomerMessages, currentMessage].filter(Boolean);
const conversationText = conversationMessages.join(' ');

const quantityPatterns = [
  /(?:qty|quantity|quantidade)\s*[:=-]?\s*(\d{1,3})\b/i,
  /\b(\d{1,3})\s*(?:x|units?|unit|pcs?|pieces?|unidades?)\b/i
];
const staticStore = getStaticStore();
const orderDrafts = staticStore ? (staticStore.chatwootOrderDrafts = staticStore.chatwootOrderDrafts || {}) : {};
const conversationMemory = staticStore ? (staticStore.chatwootConversationOrderMemory = staticStore.chatwootConversationOrderMemory || {}) : {};
const conversationKey = String(supportContext.conversationId || '');
const previousDraft = conversationKey && orderDrafts[conversationKey] ? orderDrafts[conversationKey] : {};
const previousConversationMemory = conversationKey && conversationMemory[conversationKey] ? conversationMemory[conversationKey] : {};
const rememberedBillingEmail = String(previousConversationMemory.billingEmail || '').trim().toLowerCase();
const rememberedBillingCpf = String(previousConversationMemory.billingCpf || '').trim();
const rememberedBillingAddress1 = String(previousConversationMemory.billingAddress1 || '').trim();
const rememberedBillingNumber = String(previousConversationMemory.billingNumber || '').trim();
const rememberedBillingCity = String(previousConversationMemory.billingCity || '').trim();
const rememberedBillingState = String(previousConversationMemory.billingState || '').trim();
const rememberedBillingPostcode = String(previousConversationMemory.billingPostcode || '').trim();
const previousProduct = previousDraft.product ?? null;
const previousVariationOptions = Array.isArray(previousDraft.variationOptions) ? previousDraft.variationOptions : [];
const previousOrderCreationStatus = String(previousDraft.orderCreationStatus || '').trim();
const previousMissingFields = Array.isArray(previousDraft.missingFields) ? previousDraft.missingFields : [];
const hasOpenDraft = Boolean(
  previousDraft.orderConversationRequested ||
  previousProduct ||
  previousDraft.billingEmail ||
  previousDraft.billingCpf ||
  previousDraft.billingAddress1 ||
  previousDraft.billingNumber ||
  previousDraft.billingCity ||
  previousDraft.billingState ||
  previousDraft.billingPostcode ||
  previousDraft.quantity ||
  previousVariationOptions.length > 0
);

const currentEmail = extractLastEmail([currentMessage]);
const currentBillingCpf = extractBillingCpf(currentMessage);
const currentBillingAddress1 = extractBillingAddress1(currentMessage);
const currentBillingNumber = extractBillingNumber(currentMessage);
const currentBillingCity = extractBillingCity(currentMessage);
const currentBillingState = extractBillingState(currentMessage);
const currentBillingPostcode = extractBillingPostcode(currentMessage);
const currentQuantity = extractQuantity(currentMessage);
const normalizedCurrentMessage = normalizeText(currentMessage);
const currentMeasureTokens = extractMeasureTokens(currentMessage);

const orderIntentRegex = /\b(?:create|new|place|buy|purchase|need|want)\b.{0,20}\border\b|\border\b.{0,20}\b(?:create|new|place|buy|purchase|now)\b|\b(?:checkout|pay later|payment link|link to pay|criar pedido|fazer pedido|quero pedir|quero comprar)\b/i;
const explicitNewOrderRequestRegex = /\b(?:create|new|another|place|buy|purchase|need|want)\b.{0,20}\border\b|\border\b.{0,20}\b(?:create|new|another|place|buy|purchase|now)\b|\b(?:criar pedido|novo pedido|outro pedido)\b/i;
const productDetailsIntentRegex = /\b(?:detail|details|info|information|about|detalhe|detalhes|informacao|informacoes|sobre)\b/i;
const confirmRegex = /\b(confirm|confirmed|confirmar|yes|yeah|yep|ok|okay|proceed|continue|go ahead|do it|create it|sim|confirmo|correct|right|isso)\b/i;
const hardConfirmRegex = /\b(confirm|confirmed|confirmar|proceed|continue|go ahead|do it|create it|sim|confirmo|correct|right|isso)\b/i;
const softConfirmRegex = /\b(yes|yeah|yep|ok|okay)\b/i;
const agentOrderPromptRegex = /\b(?:criar o pedido|create(?: the)? order|inform(?:e| me) a quantidade|quantity desired|reply "?confirm"?|responda "?confirm(?:ar)?"?|link de pagamento|payment link|escolha(?: uma)? opcao|choose(?: one)? option|billing email|e-mail(?: para faturamento)?|confirmar para eu criar|confirm to create)\b/i;
const agentOrderPrompted = normalizedRecentAgentMessages.some((message) => agentOrderPromptRegex.test(message));
const explicitNewOrderRequest = explicitNewOrderRequestRegex.test(currentMessage);
const explicitProductInfoRequest = Boolean(
  supportContext.productLookupRequested &&
  !supportContext.createOrderRequested &&
  !orderIntentRegex.test(currentMessage) &&
  !confirmRegex.test(currentMessage) &&
  !/@/.test(currentMessage) &&
  currentQuantity === null &&
  productDetailsIntentRegex.test(normalizedCurrentMessage)
);
const carryForwardOrderDraft = !explicitProductInfoRequest;
const reusePreviousBillingRequested = (() => {
  const text = normalizedCurrentMessage;
  if (!text) return false;

  const explicitPhraseMatch = /\b(?:same(?: as| like)? before|same(?: [a-z]+){0,3} like previous order|same(?: [a-z]+){0,3} as last order|same billing|same address|same email|same details|same info|previous order|last order|use previous order|use last order|get(?: all)? details from previous order|get(?: all)? details from last order|igual(?: ao?| a)? ?antes|igual(?: ao?| a)? ?pedido anterior|mesmo endereco|mesmo email|mesmos dados|pedido anterior|ultimo pedido)\b/i.test(text);
  if (explicitPhraseMatch) return true;

  const sameWords = /\b(?:same|igual|mesmo|mesma|mesmos|mesmas)\b/i.test(text);
  const reuseWords = /\b(?:use|reuse|recover|copy|repeat|keep|get|pull|usar|reutilizar|aproveitar|copiar|repetir|manter|pegar|trazer)\b/i.test(text);
  const previousWords = /\b(?:before|previous|last|prior|earlier|anterior|ultimo|ultima|anteriormente)\b/i.test(text);
  const orderWords = /\b(?:order|pedido|compra)\b/i.test(text);
  const billingWords = /\b(?:billing|address|email|details|detail|info|information|cpf|cep|city|state|postcode|zip|faturamento|endereco|numero|cidade|estado|dados|informacao|informacoes)\b/i.test(text);

  if ((sameWords || reuseWords) && (previousWords || orderWords) && billingWords) return true;
  if (reuseWords && /\b(?:from|do|da|de)\b/i.test(text) && (previousWords || orderWords)) return true;

  return false;
})();
const orderConversationRequested = Boolean(
  (carryForwardOrderDraft && (
    previousDraft.orderConversationRequested ||
    previousOrderCreationStatus === 'needs_info' ||
    previousOrderCreationStatus === 'awaiting_confirmation' ||
    previousOrderCreationStatus === 'ready_to_create'
  )) ||
  supportContext.createOrderRequested ||
  orderIntentRegex.test(currentMessage) ||
  (carryForwardOrderDraft && agentOrderPrompted && (confirmRegex.test(currentMessage) || /@/.test(currentMessage) || currentQuantity !== null || currentMeasureTokens.length > 0))
);
const currentMessageOrderRelated = Boolean(
  (carryForwardOrderDraft && hasOpenDraft) ||
  orderIntentRegex.test(currentMessage) ||
  confirmRegex.test(currentMessage) ||
  /@/.test(currentMessage) ||
  currentQuantity !== null ||
  currentMeasureTokens.length > 0
);
const explicitCreateNow = Boolean(
  orderIntentRegex.test(currentMessage) ||
  /\b(payment link|pay link|create now|finalize|place order|create order)\b/i.test(normalizedCurrentMessage) ||
  hardConfirmRegex.test(currentMessage) ||
  (softConfirmRegex.test(currentMessage) && previousOrderCreationStatus === 'awaiting_confirmation')
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
  'abaixo','menor','acima','maior','entre','ate','yes','confirm','checkout','pay','later',
  'option','opcao','opção'
]);
const conversationProductTokens = [...new Set(
  normalizeText(conversationText)
    .replace(/order\s*#?\s*\d+/gi, ' ')
    .replace(/[^a-z0-9\s-]/g, ' ')
    .split(/\s+/)
    .filter((word) => word && word.length > 2 && !productStopWords.has(word) && !/^\d+$/.test(word))
)].sort((left, right) => right.length - left.length || left.localeCompare(right)).slice(0, 6);
const currentProductTokens = [...new Set(
  normalizeText(currentMessage)
    .replace(/order\s*#?\s*\d+/gi, ' ')
    .replace(/[^a-z0-9\s-]/g, ' ')
    .split(/\s+/)
    .filter((word) => word && word.length > 2 && !productStopWords.has(word) && !/^\d+$/.test(word))
)];
const searchTokens = explicitNewOrderRequest && currentProductTokens.length > 0
  ? currentProductTokens
  : conversationProductTokens;
const conversationSearchTerm = searchTokens.join(' ');

const billingEmail = currentEmail || (carryForwardOrderDraft ? previousDraft.billingEmail : '') || (reusePreviousBillingRequested ? rememberedBillingEmail : '') || '';
const billingCpf = currentBillingCpf || (carryForwardOrderDraft ? previousDraft.billingCpf : '') || (reusePreviousBillingRequested ? rememberedBillingCpf : '') || '';
const billingAddress1 = currentBillingAddress1 || (carryForwardOrderDraft ? previousDraft.billingAddress1 : '') || (reusePreviousBillingRequested ? rememberedBillingAddress1 : '') || '';
const billingNumber = currentBillingNumber || (carryForwardOrderDraft ? previousDraft.billingNumber : '') || (reusePreviousBillingRequested ? rememberedBillingNumber : '') || '';
const billingCity = currentBillingCity || (carryForwardOrderDraft ? previousDraft.billingCity : '') || (reusePreviousBillingRequested ? rememberedBillingCity : '') || '';
const billingState = currentBillingState || (carryForwardOrderDraft ? previousDraft.billingState : '') || (reusePreviousBillingRequested ? rememberedBillingState : '') || '';
const billingPostcode = currentBillingPostcode || (carryForwardOrderDraft ? previousDraft.billingPostcode : '') || (reusePreviousBillingRequested ? rememberedBillingPostcode : '') || '';
const hasExplicitQuantity = currentQuantity !== null || Boolean(carryForwardOrderDraft && Number.isInteger(previousDraft.quantity) && previousDraft.quantity > 0);
const quantity = currentQuantity ?? (carryForwardOrderDraft && !explicitNewOrderRequest ? previousDraft.quantity : null) ?? 1;

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

const previousProductId = (!carryForwardOrderDraft || explicitNewOrderRequest) ? '' : String(previousProduct?.product_id || '').trim();
const previousVariationId = (!carryForwardOrderDraft || explicitNewOrderRequest) ? '' : String(previousProduct?.variation_id || '').trim();
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
  for (const token of searchTokens) {
    if (fields.title.split(/\s+/).includes(token)) { fieldHits += 1; score += 220; }
    else if (fields.title.includes(token)) { fieldHits += 1; score += 170; }
    else if (fields.variation.includes(token)) { fieldHits += 1; score += 150; }
    else if (fields.url.includes(token)) { fieldHits += 1; score += 120; }
    else if (fields.sku.includes(token)) { fieldHits += 1; score += 90; }
    else if (fields.tags.includes(token) || fields.manufacturer.includes(token)) { fieldHits += 1; score += 70; }
    else if (fields.summary.includes(token)) { fieldHits += 1; score += 25; }
  }
  if (searchTokens.length > 0 && fieldHits === searchTokens.length) score += 260;
  if (searchTokens.length > 0 && fieldHits === 0) score -= 120;
  if (fields.stock === 'instock') score += 25;
  else if (fields.stock === 'outofstock') score -= 10;
  if (fields.status === 'publish' || fields.status === 'active') score += 5;
  if (previousProductId && String(row.product_id || '') === previousProductId) score += 60;
  if (previousVariationId && String(row.variation_id || '') === previousVariationId) score += 160;
  for (const token of currentMeasureTokens) {
    if (containsMeasureToken(fields.title, token) || containsMeasureToken(fields.variation, token) || containsMeasureToken(fields.url, token)) {
      score += 520;
    }
  }
  if (normalizedCurrentMessage && normalizedCurrentMessage.length > 2) {
    if (fields.title === normalizedCurrentMessage || fields.variation === normalizedCurrentMessage) score += 1000;
  }
  return score;
};

const candidateRows = searchTokens.length > 0 || previousProductId
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

const currentVariationOptions = uniqueVariations.slice(0, 4).map((row) => buildProductOption(row)).filter(Boolean);
const matchedPreviousOption = chooseOptionFromMessage(previousVariationOptions, currentMessage);
const matchedCurrentOption = chooseOptionFromMessage(currentVariationOptions, currentMessage);
const matchedOption = matchedCurrentOption || matchedPreviousOption;
const currentOrderSelectionSignal = Boolean(
  currentQuantity !== null ||
  /@/.test(currentMessage) ||
  currentMeasureTokens.length > 0 ||
  confirmRegex.test(currentMessage) ||
  /\b(option|opcao|same like before|igual(?: ao?| a)? ?antes|send me link|payment link|link)\b/i.test(normalizedCurrentMessage)
);
const userSeemsToBeChangingProduct = Boolean(
  previousProduct &&
  currentProductTokens.length > 0 &&
  !currentOrderSelectionSignal &&
  bestProduct &&
  String(bestProduct.product_id || '') !== String(previousProduct.product_id || '')
);
const shouldKeepPreviousProduct = Boolean(
  previousProduct &&
  orderConversationRequested &&
  !explicitNewOrderRequest &&
  !userSeemsToBeChangingProduct
);

let selectedProduct = null;
if (matchedOption) {
  const exactRow = candidateRows.find((row) => String(row.variation_id || '') === String(matchedOption.variation_id || ''))
    || rows.find((row) => String(row.variation_id || '') === String(matchedOption.variation_id || ''));
  selectedProduct = buildProductOption(exactRow || matchedOption);
} else if (shouldKeepPreviousProduct) {
  selectedProduct = previousProduct;
} else if (bestProduct && currentVariationOptions.length <= 1) {
  selectedProduct = buildProductOption(bestProduct);
}

let variationOptions = [];
if (!selectedProduct) {
  variationOptions = currentVariationOptions.length > 0 ? currentVariationOptions : previousVariationOptions;
}
if (!orderConversationRequested) {
  selectedProduct = null;
  variationOptions = [];
}

const now = Date.now();

const missingFields = [];
if (!selectedProduct && variationOptions.length > 0) missingFields.push('variation');
else if (!selectedProduct) missingFields.push('product');
if (!Number.isInteger(quantity) || quantity <= 0) missingFields.push('quantity');
if (!billingEmail) missingFields.push('email');
if (!billingCpf) missingFields.push('cpf');
if (!billingAddress1) missingFields.push('address_1');
if (!billingNumber) missingFields.push('number');
if (!billingCity) missingFields.push('city');
if (!billingState) missingFields.push('state');
if (!billingPostcode) missingFields.push('postcode');

let orderCreationStatus = 'not_requested';
const carryForwardReadyState = previousOrderCreationStatus === 'ready_to_create' && previousMissingFields.length === 0;
if (orderActionRequested) {
  if (!supportContext.config.orderCreationEnabled) orderCreationStatus = 'disabled';
  else if (missingFields.length > 0) orderCreationStatus = 'needs_info';
  else if (explicitCreateNow || carryForwardReadyState) orderCreationStatus = 'ready_to_create';
  else orderCreationStatus = 'awaiting_confirmation';
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
      phone: supportContext.contactPhone || '',
      address_1: billingAddress1,
      address_2: billingNumber,
      city: billingCity,
      state: billingState,
      postcode: billingPostcode,
      country: 'BR'
    },
    line_items: [lineItem],
    customer_note: `Created from Chatwoot conversation ${supportContext.conversationId}.`,
    meta_data: [
      { key: '_chatwoot_conversation_id', value: String(supportContext.conversationId || '') },
      { key: '_chatwoot_contact_phone', value: String(supportContext.contactPhone || '') },
      { key: '_billing_cpf', value: billingCpf },
      { key: '_billing_address_1', value: billingAddress1 },
      { key: '_billing_number', value: billingNumber },
      { key: '_billing_city', value: billingCity },
      { key: '_billing_state', value: billingState },
      { key: '_billing_postcode', value: billingPostcode }
    ]
  };
}

if (conversationKey && staticStore) {
  if (billingEmail || billingCpf || billingAddress1 || billingNumber || billingCity || billingState || billingPostcode) {
    conversationMemory[conversationKey] = {
      ...(conversationMemory[conversationKey] || {}),
      billingEmail,
      billingCpf,
      billingAddress1,
      billingNumber,
      billingCity,
      billingState,
      billingPostcode,
      updatedAt: now
    };
  }
  if (orderConversationRequested || selectedProduct || billingEmail || billingCpf || billingAddress1 || billingNumber || billingCity || billingState || billingPostcode || hasExplicitQuantity || variationOptions.length > 0) {
    orderDrafts[conversationKey] = {
      orderConversationRequested,
      orderActionRequested,
      orderCreationStatus,
      missingFields,
      billingEmail,
      billingCpf,
      billingAddress1,
      billingNumber,
      billingCity,
      billingState,
      billingPostcode,
      quantity,
      product: selectedProduct || (!explicitNewOrderRequest ? previousProduct : null) || null,
      variationOptions: variationOptions.length > 0 ? variationOptions : (!explicitNewOrderRequest ? previousVariationOptions : []),
      updatedAt: now
    };
  } else {
    delete orderDrafts[conversationKey];
  }
}

return {
  conversationId: supportContext.conversationId,
  orderConversationRequested,
  orderActionRequested,
  orderCreationStatus,
  missingFields,
  billingEmail,
  billingCpf,
  billingAddress1,
  billingNumber,
  billingCity,
  billingState,
  billingPostcode,
  quantity,
  product: selectedProduct,
  variationOptions,
  orderPayload
};
'@

$prepareOrderPayloadCode = @'
const orderDraft = $('Prepare Woo Order Draft').first().json ?? {};
let customerLookupResponse = null;
try { customerLookupResponse = $('Woo Customer Lookup').first().json ?? null; } catch (error) { customerLookupResponse = null; }

const cloneValue = (value) => {
  if (value === null || value === undefined) return value;
  return JSON.parse(JSON.stringify(value));
};
const toArray = (value) => Array.isArray(value) ? value : [];
const normalizeEmail = (value) => String(value || '').trim().toLowerCase();

const customers = toArray(customerLookupResponse?.body);
const targetEmail = normalizeEmail(orderDraft.billingEmail);
const matchedCustomer = customers.find((customer) => normalizeEmail(customer?.email) === targetEmail) || customers[0] || null;

const orderPayload = cloneValue(orderDraft.orderPayload);
if (orderPayload && matchedCustomer?.id) {
  const parsedCustomerId = Number.parseInt(String(matchedCustomer.id), 10);
  orderPayload.customer_id = Number.isInteger(parsedCustomerId) ? parsedCustomerId : matchedCustomer.id;

  const customerBilling = matchedCustomer.billing && typeof matchedCustomer.billing === 'object' ? matchedCustomer.billing : {};
  const existingBilling = orderPayload.billing && typeof orderPayload.billing === 'object' ? orderPayload.billing : {};
  orderPayload.billing = {
    ...customerBilling,
    ...existingBilling,
    email: orderDraft.billingEmail || existingBilling.email || customerBilling.email || matchedCustomer.email || '',
    phone: existingBilling.phone || customerBilling.phone || '',
    first_name: existingBilling.first_name || customerBilling.first_name || matchedCustomer.first_name || '',
    last_name: existingBilling.last_name || customerBilling.last_name || matchedCustomer.last_name || ''
  };
}

return {
  ...orderDraft,
  registeredCustomer: matchedCustomer ? {
    id: matchedCustomer.id,
    email: matchedCustomer.email || '',
    first_name: matchedCustomer.first_name || '',
    last_name: matchedCustomer.last_name || ''
  } : null,
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
const normalizeWooResponseBody = (value) => (value && typeof value === 'object' && !Array.isArray(value) ? value : {});

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
const cartLinkRequested = /\b(?:cart|add to cart|buy now|checkout link|buy link|purchase link|link to buy|link para comprar|link de compra|link do carrinho|adicionar ao carrinho|comprar agora|carrinho|checkout)\b/i.test(String(supportContext.content || ''));
const buildCartUrl = (wooBaseUrl, product, quantity = 1) => {
  const baseUrl = String(wooBaseUrl || '').replace(/\/$/, '');
  const productId = String(product?.product_id || '').trim();
  if (!baseUrl || !productId) return null;

  const params = [];
  const setParam = (key, value) => {
    const finalKey = String(key || '').trim();
    const finalValue = String(value || '').trim();
    if (!finalKey || !finalValue) return;
    const existingIndex = params.findIndex((entry) => entry.key === finalKey);
    if (existingIndex >= 0) params.splice(existingIndex, 1);
    params.push({ key: finalKey, value: finalValue });
  };
  const variationId = String(product?.variation_id || '').trim();
  const requestedQuantity = Number.isFinite(Number(quantity)) && Number(quantity) > 0 ? String(Number(quantity)) : '1';

  if (variationId) setParam('add-to-cart', variationId);
  else setParam('add-to-cart', productId);
  setParam('quantity', requestedQuantity);

  const originalUrl = String(product?.product_url || product?.canonical_product_url || '').trim();
  if (originalUrl) {
    try {
      const queryString = originalUrl.includes('?') ? originalUrl.split('?').slice(1).join('?') : '';
      for (const part of queryString.split('&')) {
        const trimmedPart = String(part || '').trim();
        if (!trimmedPart) continue;
        const [rawKey, ...rawValueParts] = trimmedPart.split('=');
        const key = decodeURIComponent(String(rawKey || '').trim());
        const value = decodeURIComponent(rawValueParts.join('=').trim());
        if (key.startsWith('attribute_') && value) setParam(key, value);
      }
    } catch (error) {}
  }

  const query = params
    .map((entry) => `${encodeURIComponent(entry.key)}=${encodeURIComponent(entry.value)}`)
    .join('&');
  return query ? `${baseUrl}/?${query}` : null;
};
const productSummary = selectedProducts.map((product) => ({
  product_id: product.product_id || '',
  variation_id: product.variation_id || '',
  unique_id: product.unique_id || '',
  title: product.catalog_title || product.custom_title || '',
  product_url: product.canonical_product_url || product.product_url || '',
  product_query_url: product.product_url || '',
  variation_label: product.variation_label || product.price_variation_txt_variable || product.price_variation_txt_static || '',
  price: product.price || '',
  regular_price: product.regular_price || '',
  sale_price: product.sale_price || '',
  effective_price: product.effective_price ?? null,
  price_source: product.price_source || '',
  status: product.status || '',
  stock_status: product.stock_status || '',
  stock_quantity: product.stock_quantity || '',
  manage_stock: product.manage_stock || '',
  sku: product.product_sku || '',
  manufacturer: product.product_manufacturer || '',
  tags: product.product_tags || '',
  gtin: product.wpfoof_gtin_name || '',
  free_shipping_tag: product.free_shipping_tag || '',
  discount_tag: product.discount_tag || '',
  cheapest_tag: product.cheapest_tag || '',
  higher_grey_price: product.higher_grey_price || '',
  summary: stripText([product.custom_text, product.custom_text1, product.custom_text2, product.price_variation_txt_static, product.price_variation_txt_variable].filter(Boolean).join(' | ')),
  image_url: product.image_url || product.product_image || product.thumbnail || product.image || '',
  cart_url: buildCartUrl(supportContext.config.wooBaseUrl, product, 1),
  match_score: Number(product.match_score ?? 0)
}));

const bestProductMatch = productSummary[0] ?? null;
const hasRelevantProductMatch = Boolean(
  productLookupRequested &&
  bestProductMatch &&
  (priceFilterRequested ? productSummary.length > 0 : bestProductMatch.match_score >= 300)
);
const priceMatchedProducts = priceFilterRequested && hasRelevantProductMatch ? productSummary.slice(0, 5) : [];
const bestProductCartUrl = cartLinkRequested && hasRelevantProductMatch
  ? buildCartUrl(supportContext.config.wooBaseUrl, selectedProducts[0], orderDraft.quantity || 1)
  : null;
const buildOrderPayUrl = (wooBaseUrl, orderId, orderKey) => {
  if (!wooBaseUrl || !orderId || !orderKey) return null;
  return `${String(wooBaseUrl).replace(/\/$/, '')}/finalizacao-de-compra/pagar-pedido/${orderId}/?pay_for_order=true&key=${orderKey}`;
};

const staticStore = getStaticStore();
const orderDrafts = staticStore ? (staticStore.chatwootOrderDrafts = staticStore.chatwootOrderDrafts || {}) : {};
const conversationKey = String(supportContext.conversationId || '');
const createOrderReturnedList = Array.isArray(createOrderResponse?.body);
const createOrderBody = normalizeWooResponseBody(createOrderResponse?.body);
const createOrderErrorMessage = createOrderReturnedList
  ? 'Woo create endpoint returned a list of orders instead of a new order. This usually means the POST was redirected or treated as GET.'
  : String(createOrderBody?.message || createOrderResponse?.body?.message || createOrderResponse?.statusMessage || '').trim();

let orderCreationStatus = orderDraft.orderCreationStatus || 'not_requested';
let createdOrder = null;
if (!createOrderReturnedList && createOrderBody?.id && (!createOrderResponse?.statusCode || Number(createOrderResponse.statusCode) < 400)) {
  const body = createOrderBody;
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
  if (conversationKey && staticStore) delete orderDrafts[conversationKey];
} else if ((createOrderResponse?.statusCode && Number(createOrderResponse.statusCode) >= 400) || (orderDraft.orderCreationStatus === 'ready_to_create' && createOrderResponse?.body)) {
  orderCreationStatus = 'create_failed';
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
  cart_link: {
    requested: cartLinkRequested,
    best_cart_url: bestProductCartUrl,
    best_product_page_url: hasRelevantProductMatch ? bestProductMatch?.product_url ?? null : null
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
    billing_cpf: orderDraft.billingCpf || '',
    billing_address_1: orderDraft.billingAddress1 || '',
    billing_number: orderDraft.billingNumber || '',
    billing_city: orderDraft.billingCity || '',
    billing_state: orderDraft.billingState || '',
    billing_postcode: orderDraft.billingPostcode || '',
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
  'Act like an excellent Famivita sales specialist: friendly, clear, persuasive, and accurate.',
  'Reply in the same language as the customer whenever possible.',
  'Use only the retrieved context for factual claims about orders, products, shipping, returns, payment, or policies.',
  'Only treat product_lookup as relevant when product_search.requested is true and product_search.has_relevant_match is true.',
  'If product_search.requested is false, do not mention products or include product URLs.',
  'If product_search.has_relevant_match is true, do not say the product is unavailable or missing from the catalog.',
  'Use product_lookup fields such as title, variation_label, price, stock_status, manufacturer, tags, summary, free_shipping_tag, discount_tag, and cart_url to answer product questions accurately.',
  'If product_search.price_filter.requested is true and product_lookup has matches, list up to 3 matching products with name, price, and product_url.',
  'If product_search.price_filter.requested is true and product_lookup is empty, clearly say that no products were found for that price range.',
  'If cart_link.requested is true and cart_link.best_cart_url is available, include that exact cart URL and also include the product page URL when helpful.',
  'If order_creation.status is created, confirm that the order is ready and include the exact pay_url.',
  'If order_creation.status is needs_info, ask only for the missing fields.',
  'If the best product has stock_status equal to outofstock, say it exists but is currently out of stock.',
  'When a product lookup has a confirmed best_match_url and the message is not part of order creation, include that exact URL in the reply.',
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
  cartLinkRequested,
  priceMatchedProducts,
  hasRelevantProductMatch,
  bestProductUrl: (!priceFilterRequested && hasRelevantProductMatch && !Boolean(orderDraft.orderConversationRequested)) ? bestProductMatch?.product_url ?? null : null,
  bestProductCartUrl,
  bestProductName: hasRelevantProductMatch ? bestProductMatch?.title ?? null : null,
  orderConversationRequested: Boolean(orderDraft.orderConversationRequested),
  orderActionRequested: Boolean(orderDraft.orderActionRequested),
  orderCreationStatus,
  orderMissingFields: orderDraft.missingFields ?? [],
  orderDraftEmail: orderDraft.billingEmail || '',
  orderDraftBillingCpf: orderDraft.billingCpf || '',
  orderDraftBillingAddress1: orderDraft.billingAddress1 || '',
  orderDraftBillingNumber: orderDraft.billingNumber || '',
  orderDraftBillingCity: orderDraft.billingCity || '',
  orderDraftBillingState: orderDraft.billingState || '',
  orderDraftBillingPostcode: orderDraft.billingPostcode || '',
  orderDraftQuantity: orderDraft.quantity || null,
  orderDraftProductTitle: orderDraft.product?.title || '',
  orderDraftProductUrl: orderDraft.product?.product_url || '',
  orderVariationOptions: orderDraft.variationOptions ?? [],
  orderPayUrl,
  createdOrderId: createdOrder?.id ?? null,
  orderCreateErrorMessage: createOrderErrorMessage,
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
  if (requestContext.orderCreationStatus === 'created') {
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

$prepareReplyCodeV2 = @'
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
const looksPortuguese = (text) => /\b(produtos?|preco|abaixo|acima|entre|pedido|quero|preciso|gostaria|tenho|posso|sim|nao|quantidade|email|ola|confirmar|criar)\b/i.test(String(text || ''));
const isPortuguese = looksPortuguese(requestContext.originalMessage);
const greetingName = String(requestContext.customerName || '').trim();
const greeting = greetingName ? (isPortuguese ? `Ola ${greetingName}!` : `Hello ${greetingName}!`) : (isPortuguese ? 'Ola!' : 'Hello!');
const sanitizeTitle = (product) => {
  const title = String(product?.title || '').trim();
  if (title) return title;
  const url = String(product?.product_url || '').trim();
  if (!url) return isPortuguese ? 'produto selecionado' : 'the selected product';
  const slug = url.split('/').filter(Boolean).pop() || url;
  return slug.replace(/[-_]+/g, ' ');
};
const formatRangeText = (priceFilter) => {
  const min = parseNumber(priceFilter?.min);
  const max = parseNumber(priceFilter?.max);
  if (min !== null && max !== null) return isPortuguese ? `entre R$ ${min.toFixed(2).replace('.', ',')} e R$ ${max.toFixed(2).replace('.', ',')}` : `between R$ ${min.toFixed(2).replace('.', ',')} and R$ ${max.toFixed(2).replace('.', ',')}`;
  if (max !== null) return isPortuguese ? `abaixo de R$ ${max.toFixed(2).replace('.', ',')}` : `below R$ ${max.toFixed(2).replace('.', ',')}`;
  if (min !== null) return isPortuguese ? `acima de R$ ${min.toFixed(2).replace('.', ',')}` : `above R$ ${min.toFixed(2).replace('.', ',')}`;
  return isPortuguese ? 'nessa faixa de preco' : 'in that price range';
};
const formatMissingFields = (fields) => {
  const uniqueFields = [...new Set(Array.isArray(fields) ? fields : [])];
  const mapPt = {
    product: 'o produto',
    quantity: 'a quantidade',
    email: 'o e-mail',
    variation: 'a opcao/tamanho',
    cpf: 'o CPF',
    address_1: 'o endereco',
    number: 'o numero',
    city: 'a cidade',
    state: 'o estado',
    postcode: 'o CEP'
  };
  const mapEn = {
    product: 'the product',
    quantity: 'the quantity',
    email: 'the email',
    variation: 'the option/size',
    cpf: 'the CPF/tax ID',
    address_1: 'the address',
    number: 'the address number',
    city: 'the city',
    state: 'the state',
    postcode: 'the postcode'
  };
  const labels = uniqueFields.map((field) => isPortuguese ? (mapPt[field] || field) : (mapEn[field] || field));
  if (labels.length <= 1) return labels[0] || '';
  return `${labels.slice(0, -1).join(', ')} ${isPortuguese ? 'e' : 'and'} ${labels[labels.length - 1]}`;
};
const formatOptionLine = (option, index) => {
  const title = sanitizeTitle(option);
  const variationLabel = String(option?.variation_label || '').trim();
  const priceText = formatPrice(option);
  const parts = [title];
  if (variationLabel && variationLabel.toLowerCase() !== title.toLowerCase()) parts.push(variationLabel);
  let line = `${index + 1}. ${parts.join(' - ')}`;
  if (priceText) line += `: ${priceText}`;
  return line;
};

const orderStatus = String(requestContext.orderCreationStatus || '').trim();
const orderMissingFields = Array.isArray(requestContext.orderMissingFields) ? requestContext.orderMissingFields : [];
const orderProductTitle = sanitizeTitle({ title: requestContext.orderDraftProductTitle, product_url: requestContext.orderDraftProductUrl });
const orderEmail = String(requestContext.orderDraftEmail || '').trim();
const orderQuantity = Number.isFinite(Number(requestContext.orderDraftQuantity)) && Number(requestContext.orderDraftQuantity) > 0
  ? String(Number(requestContext.orderDraftQuantity))
  : '1';
const orderPayUrl = String(requestContext.orderPayUrl || '').trim();
const orderCreateErrorMessage = String(requestContext.orderCreateErrorMessage || '').trim();
const orderVariationOptions = Array.isArray(requestContext.orderVariationOptions) ? requestContext.orderVariationOptions.slice(0, 4) : [];
const cartLinkRequested = Boolean(requestContext.cartLinkRequested);
const bestProductCartUrl = String(requestContext.bestProductCartUrl || '').trim();
const bestProductUrl = String(requestContext.bestProductUrl || '').trim();
const bestProductName = String(requestContext.bestProductName || '').trim();

let reply = '';
if (requestContext.orderActionRequested) {
  if (orderStatus === 'created') {
    reply = isPortuguese
      ? `${greeting} Seu pedido de ${orderQuantity} unidade(s) de ${orderProductTitle} esta pronto. Voce pode concluir o pagamento por este link:\n${orderPayUrl}\n\nE-mail do pedido: ${orderEmail}`
      : `${greeting} Your order for ${orderQuantity} unit(s) of ${orderProductTitle} is ready. You can complete the payment using this link:\n${orderPayUrl}\n\nOrder email: ${orderEmail}`;
  } else if (orderStatus === 'awaiting_confirmation') {
    reply = isPortuguese
      ? `${greeting} Seu pedido de ${orderQuantity} unidade(s) de ${orderProductTitle}${orderEmail ? ` com o e-mail ${orderEmail}` : ''} esta pronto para ser criado. Responda "confirmar" para eu criar o pedido e enviar o link de pagamento.`
      : `${greeting} Your order for ${orderQuantity} unit(s) of ${orderProductTitle}${orderEmail ? ` with the email ${orderEmail}` : ''} is ready to be created. Reply "confirm" and I will create the order and send the payment link.`;
  } else if (orderStatus === 'create_failed') {
    reply = isPortuguese
      ? `${greeting} Nao consegui criar o pedido automaticamente desta vez.${orderCreateErrorMessage ? ` WooCommerce informou: ${orderCreateErrorMessage}.` : ''} Se quiser, responda "confirmar" para eu tentar novamente, ou eu posso encaminhar para o time em ${requestContext.supportEmail}.`
      : `${greeting} I couldn't create the order automatically this time.${orderCreateErrorMessage ? ` WooCommerce said: ${orderCreateErrorMessage}.` : ''} If you want, reply "confirm" and I will try again, or I can hand this over to our team at ${requestContext.supportEmail}.`;
  } else if (orderStatus === 'needs_info') {
    const billingFields = ['cpf', 'address_1', 'number', 'city', 'state', 'postcode'];
    const missingBillingFields = orderMissingFields.filter((field) => billingFields.includes(field));
    if (orderMissingFields.includes('variation') && orderVariationOptions.length > 0) {
      const optionsText = orderVariationOptions.map((option, index) => formatOptionLine(option, index)).join('\n');
      const remaining = orderMissingFields.filter((field) => field !== 'variation');
      reply = isPortuguese
        ? `${greeting} Encontrei mais de uma opcao para ${orderProductTitle}. Antes de criar o pedido, escolha uma opcao:\n${optionsText}${remaining.length ? `\n\nDepois disso, tambem preciso de ${formatMissingFields(remaining)}.` : `\n\nDepois disso, responda "confirmar" para eu criar o pedido.`}`
        : `${greeting} I found more than one option for ${orderProductTitle}. Before I create the order, choose one option:\n${optionsText}${remaining.length ? `\n\nAfter that, I also need ${formatMissingFields(remaining)}.` : `\n\nAfter that, reply "confirm" and I will create the order.`}`;
    } else if (missingBillingFields.length > 0) {
      const otherMissing = orderMissingFields.filter((field) => !billingFields.includes(field));
      const intro = isPortuguese
        ? `${greeting} Para criar o pedido, ainda preciso${otherMissing.length ? ` de ${formatMissingFields(otherMissing)} e ` : ' '}dos dados de faturamento: ${formatMissingFields(missingBillingFields)}.`
        : `${greeting} To create the order, I still need${otherMissing.length ? ` ${formatMissingFields(otherMissing)} and ` : ' '}the billing details: ${formatMissingFields(missingBillingFields)}.`;
      const example = isPortuguese
        ? 'Envie assim:\nCPF: 048.532.001-00\nEndereco: Rua Exemplo\nNumero: 123\nCidade: Sao Paulo\nEstado: SP\nCEP: 50070-130'
        : 'Please send them like this:\nCPF: 048.532.001-00\nAddress: Example Street\nNumber: 123\nCity: Sao Paulo\nState: SP\nPostcode: 50070-130';
      reply = `${intro}\n\n${example}`;
    } else {
      reply = isPortuguese
        ? `${greeting} Para criar o pedido agora, eu so preciso de ${formatMissingFields(orderMissingFields)}.`
        : `${greeting} To create the order now, I just need ${formatMissingFields(orderMissingFields)}.`;
    }
  } else if (orderStatus === 'disabled') {
    reply = isPortuguese
      ? `${greeting} No momento, a criacao automatica de pedidos esta desativada.`
      : `${greeting} Automatic order creation is currently disabled.`;
  }
}

if (!reply && cartLinkRequested && !requestContext.orderConversationRequested && requestContext.hasRelevantProductMatch) {
  const productName = bestProductName || orderProductTitle;
  const productPrice = Array.isArray(requestContext.productLookup) && requestContext.productLookup[0]
    ? formatPrice(requestContext.productLookup[0])
    : null;
  if (bestProductCartUrl) {
    reply = isPortuguese
      ? `${greeting} ${productName ? `Separei ${productName}` : 'Separei esse produto'}${productPrice ? ` por ${productPrice}` : ''}. Para comprar agora, use este link direto do carrinho:\n${bestProductCartUrl}${bestProductUrl ? `\n\nDetalhes do produto:\n${bestProductUrl}` : ''}`
      : `${greeting} ${productName ? `${productName} is ready` : 'This product is ready'}${productPrice ? ` for ${productPrice}` : ''}. To buy now, use this direct cart link:\n${bestProductCartUrl}${bestProductUrl ? `\n\nProduct details:\n${bestProductUrl}` : ''}`;
  } else if (bestProductUrl) {
    reply = isPortuguese
      ? `${greeting} ${productName ? `Encontrei ${productName}` : 'Encontrei o produto'}${productPrice ? ` por ${productPrice}` : ''}. No momento eu consigo te enviar o link do produto:\n${bestProductUrl}`
      : `${greeting} ${productName ? `I found ${productName}` : 'I found the product'}${productPrice ? ` for ${productPrice}` : ''}. Right now I can send you the product page link:\n${bestProductUrl}`;
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
    const closing = isPortuguese ? 'Se quiser, posso procurar outra faixa de preco ou um produto especifico.' : 'If you want, I can look for another price range or a specific product.';
    reply = [intro, ...lines, closing].join('\n');
  } else {
    reply = isPortuguese
      ? `${greeting} No momento, nao encontrei produtos ${rangeText} no catalogo. Se quiser, posso procurar outra faixa de preco ou encaminhar para um atendente.`
      : `${greeting} I couldn't find products ${rangeText} in the catalog right now. If you want, I can search another price range or hand this over to a human agent.`;
  }
}

if (!reply) {
  if (openAiResponse.statusCode === 200) reply = String(openAiResponse.body?.choices?.[0]?.message?.content || '').trim();
  if (!reply) reply = `Thanks for your message. I need a human teammate to review this so we can help you correctly. You can also reach us at ${requestContext.supportEmail}.`;
  reply = reply.replace(/^['\"]+|['\"]+$/g, '').trim();
  if (!requestContext.orderConversationRequested && !requestContext.priceFilterRequested && requestContext.productLookupRequested && requestContext.hasRelevantProductMatch && bestProductUrl && !reply.includes(bestProductUrl)) {
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

function Resolve-NodeName {
  param(
    [Parameter(Mandatory = $true)] $Json,
    [Parameter(Mandatory = $true)] [string] $BaseName
  )

  $exact = $Json.nodes | Where-Object { $_.name -eq $BaseName } | Select-Object -First 1
  if ($exact) {
    return $exact.name
  }

  $prefixed = $Json.nodes | Where-Object { $_.name -like "$BaseName*" } | Select-Object -First 1
  if ($prefixed) {
    return $prefixed.name
  }

  throw "Node '$BaseName' was not found in $($Json.name)"
}

foreach ($path in $targets) {
  if (-not (Test-Path $path)) { continue }
  $json = Get-Content -Raw $path | ConvertFrom-Json

  $normalizeNodeName = Resolve-NodeName -Json $json -BaseName 'Normalize Incoming Event'
  $gateNodeName = Resolve-NodeName -Json $json -BaseName 'Gate Test Contact'
  $mergeNodeName = Resolve-NodeName -Json $json -BaseName 'Merge Product Catalog Rows'
  $sortNodeName = Resolve-NodeName -Json $json -BaseName 'Sort Product Matches'
  $orderLookupNodeName = Resolve-NodeName -Json $json -BaseName 'Woo Order Lookup'
  $buildNodeName = Resolve-NodeName -Json $json -BaseName 'Build OpenAI Request'
  $replyNodeName = Resolve-NodeName -Json $json -BaseName 'Prepare Chatwoot Reply'
  $openAiNodeName = Resolve-NodeName -Json $json -BaseName 'OpenAI Reply'

  $suffixMatch = [regex]::Match($buildNodeName, '(\d+)$')
  $suffix = if ($suffixMatch.Success) { $suffixMatch.Groups[1].Value } else { '' }
  $prepareOrderDraftNodeName = "Prepare Woo Order Draft$suffix"
  $shouldCreateOrderNodeName = "Should Create Order?$suffix"
  $wooCustomerLookupNodeName = "Woo Customer Lookup$suffix"
  $prepareOrderPayloadNodeName = "Prepare Woo Order Payload$suffix"
  $wooCreateOrderNodeName = "Woo Create Order$suffix"

  $prepareOrderDraftCodeForFile = $prepareOrderDraftCode.Trim().
    Replace("'Gate Test Contact'", "'$gateNodeName'").
    Replace("'Merge Product Catalog Rows'", "'$mergeNodeName'")

  $prepareOrderPayloadCodeForFile = $prepareOrderPayloadCode.Trim().
    Replace("'Prepare Woo Order Draft'", "'$prepareOrderDraftNodeName'").
    Replace("'Woo Customer Lookup'", "'$wooCustomerLookupNodeName'")

  $buildCodeForFile = $buildCode.Trim().
    Replace("'Gate Test Contact'", "'$gateNodeName'").
    Replace("'Woo Order Lookup'", "'$orderLookupNodeName'").
    Replace("'Sort Product Matches'", "'$sortNodeName'").
    Replace("'Prepare Woo Order Draft'", "'$prepareOrderDraftNodeName'").
    Replace("'Woo Create Order'", "'$wooCreateOrderNodeName'")

  $prepareReplyCodeForFile = $prepareReplyCodeV2.Trim().
    Replace("'Build OpenAI Request'", "'$buildNodeName'")

  $wooCreateUrl = "={{ `$('${gateNodeName}').first().json.config.wooBaseUrl }}/wp-json/wc/v3/orders/?consumer_key={{ `$env.WOOCOMMERCE_CONSUMER_KEY }}&consumer_secret={{ `$env.WOOCOMMERCE_CONSUMER_SECRET }}"
  $wooCreateUrlWithCredential = "={{ `$('${gateNodeName}').first().json.config.wooBaseUrl }}/wp-json/wc/v3/orders/"
  $wooCustomerLookupUrlWithCredential = "={{ `$('${gateNodeName}').first().json.config.wooBaseUrl + '/wp-json/wc/v3/customers?role=all&per_page=5&email=' + encodeURIComponent(`$json.billingEmail || '') }}"

  $normalizeNode = $json.nodes | Where-Object { $_.name -eq $normalizeNodeName } | Select-Object -First 1
  $gateNode = $json.nodes | Where-Object { $_.name -eq $gateNodeName } | Select-Object -First 1
  $orderLookupNode = $json.nodes | Where-Object { $_.name -eq $orderLookupNodeName } | Select-Object -First 1
  if ($normalizeNode -and $normalizeNode.parameters.jsCode -match 'orderCreationEnabled:\s*false') {
    $normalizeNode.parameters.jsCode = $normalizeNode.parameters.jsCode -replace 'orderCreationEnabled:\s*false', 'orderCreationEnabled: true'
  }
  if ($normalizeNode -and $normalizeNode.parameters.jsCode -match 'maxConversationMessages:\s*\d+') {
    $normalizeNode.parameters.jsCode = $normalizeNode.parameters.jsCode -replace 'maxConversationMessages:\s*\d+', 'maxConversationMessages: 20'
  }
  if ($normalizeNode -and $normalizeNode.parameters.jsCode -match 'https://famivita\.com\.br') {
    $normalizeNode.parameters.jsCode = $normalizeNode.parameters.jsCode -replace 'https://famivita\.com\.br', $wooCanonicalBaseUrl
  }
  if ($gateNode) {
    $gateNode.parameters.jsCode = $gateNode.parameters.jsCode.Replace(
      "const createOrderRequested = /(create|place|buy|purchase).{0,20}order|order.{0,20}(create|place|buy|purchase)/i.test(event.content);",
      "const createOrderRequested = /\b(?:create|place|buy|purchase|need|want)\b.{0,20}\border\b|\border\b.{0,20}\b(?:create|place|buy|purchase|now)\b|\b(?:checkout|pay later|payment link|link to pay|criar pedido|fazer pedido|quero pedir|quero comprar)\b/i.test(event.content);"
    )
  }

  ($json.nodes | Where-Object { $_.name -eq $buildNodeName }).parameters.jsCode = $buildCodeForFile
  ($json.nodes | Where-Object { $_.name -eq $replyNodeName }).parameters.jsCode = $prepareReplyCodeForFile

  Ensure-Node -Json $json -Node @{ parameters = @{ jsCode = $prepareOrderDraftCodeForFile }; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2520, 60); id = '0d45bdf2-3c9e-49af-a9a4-prepare-woo-order-draft-attached'; name = $prepareOrderDraftNodeName }
  Ensure-Node -Json $json -Node @{ parameters = @{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'strict'; version = 2 }; conditions = @(@{ id = '4fd707ff-53a2-45f6-b4a3-should-create-woo-order-attached'; leftValue = '={{ $json.orderCreationStatus }}'; rightValue = 'ready_to_create'; operator = @{ type = 'string'; operation = 'equals' } }); combinator = 'and' }; options = @{} }; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(2740, 60); id = 'd8f644a4-0e11-4c4f-9a64-should-create-order-attached'; name = $shouldCreateOrderNodeName }
  Ensure-Node -Json $json -Node @{ parameters = @{ method = 'GET'; url = $wooCustomerLookupUrlWithCredential; sendHeaders = $true; headerParameters = @{ parameters = @(@{ name = 'accept'; value = 'application/json' }) }; options = @{ response = @{ response = @{ fullResponse = $true; neverError = $true } } } }; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4.2; position = @(2960, -20); id = '2199a9a4-7d8c-4a9f-8c3b-woo-customer-lookup-attached'; name = $wooCustomerLookupNodeName; alwaysOutputData = $true; onError = 'continueRegularOutput' }
  Ensure-Node -Json $json -Node @{ parameters = @{ jsCode = $prepareOrderPayloadCodeForFile }; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(3180, -20); id = 'f6f042c3-7a6a-42aa-9e5c-prepare-woo-order-payload-attached'; name = $prepareOrderPayloadNodeName }
  Ensure-Node -Json $json -Node @{ parameters = @{ method = 'POST'; url = $wooCreateUrl; sendHeaders = $true; headerParameters = @{ parameters = @(@{ name = 'accept'; value = 'application/json' }, @{ name = 'content-type'; value = 'application/json' }) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={{ $json.orderPayload }}'; options = @{ response = @{ response = @{ fullResponse = $true; neverError = $true } } } }; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4.2; position = @(3400, 20); id = 'b4e36d41-0c61-4b9a-84f3-woo-create-order-attached'; name = $wooCreateOrderNodeName; alwaysOutputData = $true; onError = 'continueRegularOutput' }

  $wooCustomerLookupNode = $json.nodes | Where-Object { $_.name -eq $wooCustomerLookupNodeName } | Select-Object -First 1
  $wooCreateNode = $json.nodes | Where-Object { $_.name -eq $wooCreateOrderNodeName } | Select-Object -First 1
  if ($wooCustomerLookupNode -and $orderLookupNode -and $orderLookupNode.credentials.httpBasicAuth) {
    $wooCustomerLookupNode.parameters.url = $wooCustomerLookupUrlWithCredential
    $wooCustomerLookupNode.parameters.authentication = 'genericCredentialType'
    $wooCustomerLookupNode.parameters.genericAuthType = 'httpBasicAuth'
    if ($wooCustomerLookupNode.PSObject.Properties['credentials']) {
      $wooCustomerLookupNode.credentials = $orderLookupNode.credentials
    } else {
      $wooCustomerLookupNode | Add-Member -NotePropertyName 'credentials' -NotePropertyValue $orderLookupNode.credentials
    }
  }
  if ($wooCreateNode -and $orderLookupNode -and $orderLookupNode.credentials.httpBasicAuth) {
    $wooCreateNode.parameters.url = $wooCreateUrlWithCredential
    $wooCreateNode.parameters.authentication = 'genericCredentialType'
    $wooCreateNode.parameters.genericAuthType = 'httpBasicAuth'
    if ($wooCreateNode.PSObject.Properties['credentials']) {
      $wooCreateNode.credentials = $orderLookupNode.credentials
    } else {
      $wooCreateNode | Add-Member -NotePropertyName 'credentials' -NotePropertyValue $orderLookupNode.credentials
    }
  }

  Set-Connection -Connections $json.connections -Name $sortNodeName -Value @{ main = ,(@(@{ node = $prepareOrderDraftNodeName; type = 'main'; index = 0 })) }
  Set-Connection -Connections $json.connections -Name $prepareOrderDraftNodeName -Value @{ main = ,(@(@{ node = $shouldCreateOrderNodeName; type = 'main'; index = 0 })) }
  Set-Connection -Connections $json.connections -Name $shouldCreateOrderNodeName -Value @{ main = @(@(@{ node = $wooCustomerLookupNodeName; type = 'main'; index = 0 }), @(@{ node = $buildNodeName; type = 'main'; index = 0 })) }
  Set-Connection -Connections $json.connections -Name $wooCustomerLookupNodeName -Value @{ main = ,(@(@{ node = $prepareOrderPayloadNodeName; type = 'main'; index = 0 })) }
  Set-Connection -Connections $json.connections -Name $prepareOrderPayloadNodeName -Value @{ main = ,(@(@{ node = $wooCreateOrderNodeName; type = 'main'; index = 0 })) }
  Set-Connection -Connections $json.connections -Name $wooCreateOrderNodeName -Value @{ main = ,(@(@{ node = $buildNodeName; type = 'main'; index = 0 })) }

  $json | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding UTF8
  Write-Output $path
}
