$ErrorActionPreference = 'Stop'

$workflowPath = 'f:\github\chatwoot n8n ai agent\chatwoot-ai-product-search-and-order-create-final.json'

function Resolve-Node {
  param(
    [Parameter(Mandatory = $true)] $Json,
    [Parameter(Mandatory = $true)] [string] $BaseName
  )

  $exact = $Json.nodes | Where-Object { $_.name -eq $BaseName } | Select-Object -First 1
  if ($exact) { return $exact }

  $prefixed = $Json.nodes | Where-Object { $_.name -like "$BaseName*" } | Select-Object -First 1
  if ($prefixed) { return $prefixed }

  throw "Node '$BaseName' was not found in $($Json.name)"
}

function Replace-Between {
  param(
    [Parameter(Mandatory = $true)] [string] $Text,
    [Parameter(Mandatory = $true)] [string] $StartToken,
    [Parameter(Mandatory = $true)] [string] $EndToken,
    [Parameter(Mandatory = $true)] [string] $Replacement,
    [string] $Label = 'text'
  )

  $startIndex = $Text.IndexOf($StartToken)
  if ($startIndex -lt 0) {
    throw "Start token '$StartToken' not found in $Label"
  }

  $endIndex = $Text.IndexOf($EndToken, $startIndex)
  if ($endIndex -lt 0) {
    throw "End token '$EndToken' not found in $Label"
  }

  return $Text.Substring(0, $startIndex) + $Replacement + $Text.Substring($endIndex)
}

if (-not (Test-Path $workflowPath)) {
  throw "Workflow not found: $workflowPath"
}

$json = Get-Content -Raw $workflowPath | ConvertFrom-Json

$gateNode = Resolve-Node -Json $json -BaseName 'Gate Test Contact3'
$sortNode = Resolve-Node -Json $json -BaseName 'Sort Product Matches3'
$buildNode = Resolve-Node -Json $json -BaseName 'Build OpenAI Request3'
$draftNode = Resolve-Node -Json $json -BaseName 'Prepare Woo Order Draft3'

$gateBlock = @'
const stopWords = new Set([
  'the', 'and', 'for', 'with', 'this', 'that', 'have', 'from', 'what', 'your', 'about', 'please', 'need', 'want',
  'know', 'tell', 'price', 'stock', 'order', 'where', 'when', 'does', 'will', 'show', 'much', 'how', 'can',
  'you', 'me', 'our', 'get', 'buy', 'make', 'create', 'status', 'hello', 'hi', 'product', 'products', 'item',
  'items', 'produto', 'produtos', 'quero', 'preciso', 'gostaria', 'sobre', 'tenho', 'tem', 'uma', 'um',
  'support', 'human', 'agent', 'contact', 'return', 'refund', 'exchange', 'shipping', 'delivery', 'payment',
  'track', 'tracking', 'pedido', 'pedidos', 'email', 'mail', 'rastreio', 'rastrear', 'acompanhar',
  'below', 'under', 'less', 'than', 'above', 'over', 'between', 'which', 'cheap', 'cheaper', 'cheapest',
  'abaixo', 'menor', 'acima', 'maior', 'entre', 'ate',
  'some', 'give', 'gimme', 'gime', 'list', 'lists', 'catalog', 'catalogue', 'catalogo', 'option', 'options',
  'suggest', 'suggestion', 'suggestions', 'recommend', 'recommendation', 'recommendations', 'available', 'availability',
  'disponivel', 'disponiveis', 'mostrar', 'mostre', 'sugira', 'sugerir', 'recomende', 'lista', 'listar'
]);

const normalizedContent = normalizeText(event.content)
  .replace(/order\s*#?\s*\d+/gi, ' ')
  .replace(/[^a-z0-9\s-]/g, ' ');

const productSearchTokens = [...new Set(
  normalizedContent
    .split(/\s+/)
    .filter((word) => word && word.length > 2 && !stopWords.has(word) && !/^\d+$/.test(word))
)]
  .sort((left, right) => right.length - left.length || left.localeCompare(right))
  .slice(0, 6);

const categoryLexicon = [
  {
    tag: 'vitamins',
    aliases: ['vitamin', 'vitamins', 'vitamina', 'vitaminas', 'supplement', 'supplements', 'suplemento', 'suplementos']
  },
  {
    tag: 'pregnancy',
    aliases: ['pregnancy', 'pregnant', 'gravidez', 'gestante', 'gestacao', 'prenatal', 'pre natal']
  },
  {
    tag: 'fertility',
    aliases: ['fertility', 'fertile', 'fertilidade', 'fertil', 'engravidar', 'conceive', 'conception', 'concepcao', 'preconcepcao', 'pre concepcao', 'trying to conceive', 'trying conceive', 'ttc']
  },
  {
    tag: 'ovulation',
    aliases: ['ovulation', 'ovulacao', 'ovular', 'ovulate']
  },
  {
    tag: 'omega',
    aliases: ['omega', 'omega3', 'omega 3', 'dha']
  },
  {
    tag: 'intimate_care',
    aliases: ['lubricant', 'lubrificante', 'lubrificantes', 'vaginal', 'secura vaginal', 'intimo', 'intima']
  },
  {
    tag: 'menopause',
    aliases: ['menopause', 'menopausa', 'climaterio']
  }
];

const categorySeedMap = {
  vitamins: ['vitamin', 'vitamina', 'suplemento'],
  pregnancy: ['pregnancy', 'gravidez', 'gestacao'],
  fertility: ['fertility', 'fertilidade', 'engravidar', 'concepcao'],
  ovulation: ['ovulation', 'ovulacao'],
  omega: ['omega', 'dha'],
  intimate_care: ['lubricant', 'lubrificante', 'intimo'],
  menopause: ['menopause', 'menopausa']
};

const categoryIntentTags = [...new Set(
  categoryLexicon
    .filter((entry) => entry.aliases.some((alias) => normalizedContent.includes(normalizeText(alias))))
    .map((entry) => entry.tag)
)];

const semanticSearchTokens = [...new Set([
  ...productSearchTokens,
  ...categoryIntentTags.flatMap((tag) => categorySeedMap[tag] || [])
].filter((token) => token && token.length > 2))]
  .sort((left, right) => right.length - left.length || left.localeCompare(right))
  .slice(0, 10);

const productSearchTerm = productSearchTokens.slice(0, 4).join(' ');
const hasEmailAddress = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i.test(event.content);
const orderSupportRequested = Boolean(
  event.detectedOrderId ||
  hasEmailAddress ||
  /(where\s+is\s+my\s+order|track(?:ing)?|order\s+status|status\s+of\s+my\s+order|my\s+order|pedido|rastreio|rastrear|acompanhar|status do pedido|meu pedido)/i.test(event.content)
);

const normalizedIntentText = normalizeText(event.content);
const priceFilter = { requested: false, min: null, max: null };
const betweenMatch = normalizedIntentText.match(/\b(?:between|entre)\s*(\d+(?:[.,]\d+)?)\s*(?:and|e)\s*(\d+(?:[.,]\d+)?)/);
const belowMatch = normalizedIntentText.match(/\b(?:below|under|less than|abaixo de|menor que|ate|ate)\s*(\d+(?:[.,]\d+)?)/);
const aboveMatch = normalizedIntentText.match(/\b(?:above|over|more than|acima de|maior que)\s*(\d+(?:[.,]\d+)?)/);

if (betweenMatch) {
  const firstValue = parseNumber(betweenMatch[1]);
  const secondValue = parseNumber(betweenMatch[2]);
  if (firstValue !== null && secondValue !== null) {
    priceFilter.requested = true;
    priceFilter.min = Math.min(firstValue, secondValue);
    priceFilter.max = Math.max(firstValue, secondValue);
  }
} else if (belowMatch) {
  const maxValue = parseNumber(belowMatch[1]);
  if (maxValue !== null) {
    priceFilter.requested = true;
    priceFilter.max = maxValue;
  }
} else if (aboveMatch) {
  const minValue = parseNumber(aboveMatch[1]);
  if (minValue !== null) {
    priceFilter.requested = true;
    priceFilter.min = minValue;
  }
}

const broadCatalogQueryRequested = Boolean(
  !orderSupportRequested &&
  categoryIntentTags.length > 0 &&
  (
    /\b(?:some|give|gimme|gime|list|catalog|catalogue|suggest|recommend|show|looking|products?|produtos?|lista|listar|mostrar|sugira|recomende|quero|preciso)\b/i.test(event.content) ||
    semanticSearchTokens.length <= 6
  )
);

const languageHint = /\b(?:produto|produtos|pedido|pedidos|quero|preciso|gostaria|vitamina|vitaminas|gravidez|fertilidade|gestacao|gestante|sugira|recomende|lista|mostrar|endereco|cidade|estado|cep|cpf)\b/i.test(event.content)
  ? 'pt-BR'
  : 'en';

const productLookupRequested = !orderSupportRequested && (
  productSearchTokens.length > 0 ||
  semanticSearchTokens.length > 0 ||
  priceFilter.requested ||
  broadCatalogQueryRequested
);

'@

$gateCode = $gateNode.parameters.jsCode
$gateCode = Replace-Between -Text $gateCode -StartToken 'const stopWords = new Set([' -EndToken 'const recentMessages =' -Replacement $gateBlock -Label 'Gate Test Contact3'
$gateCode = $gateCode.Replace("  productSearchTerm,`n  productSearchTokens,`n  productLookupRequested,", "  productSearchTerm,`n  productSearchTokens,`n  semanticSearchTokens,`n  categoryIntentTags,`n  broadCatalogQueryRequested,`n  languageHint,`n  productLookupRequested,")
$gateNode.parameters.jsCode = $gateCode

$sortCode = @'
const supportContext = $('Gate Test Contact3').first().json;
const catalogResponse = $input.first().json ?? {};

const stripText = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const normalizeText = (value) => stripText(value)
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .toLowerCase();
const parseNumber = (value) => {
  const cleaned = String(value || '').replace(/[^0-9,.\-]/g, '').trim();
  if (!cleaned) {
    return null;
  }

  const normalized = cleaned.includes(',') && cleaned.includes('.')
    ? cleaned.replace(/\./g, '').replace(',', '.')
    : cleaned.replace(',', '.');
  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : null;
};

const rows = Array.isArray(catalogResponse.body) ? catalogResponse.body : [];
const getCatalogTitle = (row) => row.custom_title || row.product_url || row.product_sku || row.unique_id || row.product_id || '';
const getCanonicalProductUrl = (value) => String(value || '').trim().split('?')[0];
const getEffectivePrice = (row) => {
  const priceCandidates = [row.sale_price, row.price, row.regular_price];
  for (const candidate of priceCandidates) {
    const parsed = parseNumber(candidate);
    if (parsed !== null) {
      return parsed;
    }
  }
  return null;
};
const getSearchableFields = (row) => {
  const title = normalizeText(getCatalogTitle(row));
  const variation = normalizeText(row.price_variation_txt_variable || row.price_variation_txt_static || '');
  const url = normalizeText(row.product_url);
  const sku = normalizeText(row.product_sku);
  const manufacturer = normalizeText(row.product_manufacturer);
  const tags = normalizeText(row.product_tags);
  const summary = normalizeText([row.custom_text, row.custom_text1, row.custom_text2].filter(Boolean).join(' '));
  const stock = normalizeText(row.stock_status);
  const status = normalizeText(row.status);

  return {
    title,
    variation,
    url,
    sku,
    manufacturer,
    tags,
    summary,
    stock,
    status,
    combined: [title, variation, url, sku, manufacturer, tags, summary].filter(Boolean).join(' ')
  };
};

const productLookupRequested = Boolean(supportContext.productLookupRequested);
const priceFilter = supportContext.priceFilter ?? { requested: false, min: null, max: null };
const priceFilterRequested = Boolean(priceFilter.requested);
const broadCatalogQueryRequested = Boolean(supportContext.broadCatalogQueryRequested);
const languageHint = String(supportContext.languageHint || 'auto');
const requestedTokens = Array.isArray(supportContext.productSearchTokens) ? supportContext.productSearchTokens : [];
const queryTokens = Array.isArray(supportContext.semanticSearchTokens) && supportContext.semanticSearchTokens.length > 0
  ? supportContext.semanticSearchTokens.map((token) => normalizeText(token)).filter(Boolean)
  : requestedTokens.map((token) => normalizeText(token)).filter(Boolean);
const intentTags = Array.isArray(supportContext.categoryIntentTags) ? supportContext.categoryIntentTags : [];
const hasTextQuery = productLookupRequested && queryTokens.length > 0;
const queryText = hasTextQuery
  ? normalizeText(supportContext.productSearchTerm || queryTokens.join(' '))
  : '';

const synonymGroups = [
  ['vitamin', 'vitamins', 'vitamina', 'vitaminas', 'supplement', 'supplements', 'suplemento', 'suplementos'],
  ['pregnancy', 'pregnant', 'gravidez', 'gestante', 'gestacao', 'prenatal', 'pre natal'],
  ['fertility', 'fertile', 'fertilidade', 'fertil', 'conceive', 'conception', 'concepcao', 'engravidar', 'preconcepcao', 'pre concepcao', 'trying to conceive', 'trying conceive', 'ttc'],
  ['ovulation', 'ovulacao', 'ovular', 'ovulate'],
  ['lubricant', 'lubrificante', 'lubrificantes', 'vaginal', 'intimo', 'intima'],
  ['omega', 'omega3', 'omega 3', 'dha'],
  ['menopause', 'menopausa', 'climaterio']
];
const categoryLexicon = {
  vitamins: ['vitamin', 'vitamins', 'vitamina', 'vitaminas', 'supplement', 'supplements', 'suplemento', 'suplementos'],
  pregnancy: ['pregnancy', 'pregnant', 'gravidez', 'gestante', 'gestacao', 'prenatal', 'pre natal'],
  fertility: ['fertility', 'fertile', 'fertilidade', 'fertil', 'conceive', 'conception', 'concepcao', 'engravidar', 'preconcepcao', 'pre concepcao', 'trying to conceive', 'trying conceive', 'ttc'],
  ovulation: ['ovulation', 'ovulacao', 'ovular', 'ovulate'],
  omega: ['omega', 'omega3', 'omega 3', 'dha'],
  intimate_care: ['lubricant', 'lubrificante', 'lubrificantes', 'vaginal', 'intimo', 'intima', 'secura vaginal'],
  menopause: ['menopause', 'menopausa', 'climaterio']
};
const expandTokenVariants = (token) => {
  const normalized = normalizeText(token);
  const variants = new Set([normalized]);
  if (!normalized) {
    return [];
  }

  if (normalized.endsWith('s') && normalized.length > 3) {
    variants.add(normalized.slice(0, -1));
  } else if (!normalized.endsWith('s')) {
    variants.add(`${normalized}s`);
  }

  for (const group of synonymGroups) {
    if (group.some((alias) => alias === normalized)) {
      for (const alias of group) {
        variants.add(normalizeText(alias));
      }
    }
  }

  return [...variants].filter(Boolean);
};
const getTagAliases = (tag) => (categoryLexicon[tag] || []).map((alias) => normalizeText(alias)).filter(Boolean);

if (!productLookupRequested) {
  return {
    ...catalogResponse,
    body: rows.map((row) => ({
      ...row,
      catalog_title: getCatalogTitle(row),
      canonical_product_url: getCanonicalProductUrl(row.product_url),
      effective_price: getEffectivePrice(row),
      match_score: 0
    })),
    productSearch: {
      source: 'google_sheet',
      requested: false,
      search_term: supportContext.productSearchTerm,
      requested_tokens: requestedTokens,
      semantic_tokens: queryTokens,
      intent_tags: intentTags,
      broad_catalog_query: broadCatalogQueryRequested,
      language_hint: languageHint,
      price_filter: priceFilter,
      result_count: rows.length,
      top_match_name: null,
      top_match_url: null,
      top_match_score: null
    }
  };
}

const filteredRows = rows.filter((row) => {
  if (!priceFilterRequested) {
    return true;
  }

  const effectivePrice = getEffectivePrice(row);
  if (effectivePrice === null) {
    return false;
  }
  if (priceFilter.min !== null && effectivePrice < Number(priceFilter.min)) {
    return false;
  }
  if (priceFilter.max !== null && effectivePrice > Number(priceFilter.max)) {
    return false;
  }
  return true;
});

const scoreRow = (row) => {
  const fields = getSearchableFields(row);
  const effectivePrice = getEffectivePrice(row);
  let score = 0;
  let tokenHits = 0;
  let categoryHits = 0;

  if (hasTextQuery && queryText) {
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

  if (hasTextQuery) {
    const titleWords = fields.title.split(/\s+/).filter(Boolean);
    for (const token of queryTokens) {
      const variants = expandTokenVariants(token);
      if (variants.some((variant) => titleWords.includes(variant))) {
        tokenHits += 1;
        score += 230;
      } else if (variants.some((variant) => fields.title.includes(variant))) {
        tokenHits += 1;
        score += 180;
      } else if (variants.some((variant) => fields.variation.includes(variant))) {
        tokenHits += 1;
        score += 150;
      } else if (variants.some((variant) => fields.url.includes(variant))) {
        tokenHits += 1;
        score += 120;
      } else if (variants.some((variant) => fields.sku.includes(variant))) {
        tokenHits += 1;
        score += 90;
      } else if (variants.some((variant) => fields.tags.includes(variant) || fields.manufacturer.includes(variant))) {
        tokenHits += 1;
        score += 85;
      } else if (variants.some((variant) => fields.summary.includes(variant))) {
        tokenHits += 1;
        score += 40;
      }
    }

    if (queryTokens.length > 0 && tokenHits === queryTokens.length) {
      score += 260;
    }
    if (!broadCatalogQueryRequested && queryTokens.length > 0 && tokenHits === 0) {
      score -= 120;
    }
  }

  for (const tag of intentTags) {
    const aliases = getTagAliases(tag);
    if (aliases.length === 0) {
      continue;
    }

    if (aliases.some((alias) => fields.title.includes(alias) || fields.variation.includes(alias))) {
      categoryHits += 1;
      score += 240;
    } else if (aliases.some((alias) => fields.tags.includes(alias) || fields.manufacturer.includes(alias))) {
      categoryHits += 1;
      score += 170;
    } else if (aliases.some((alias) => fields.summary.includes(alias))) {
      categoryHits += 1;
      score += 125;
    } else if (aliases.some((alias) => fields.url.includes(alias))) {
      categoryHits += 1;
      score += 80;
    }
  }

  if (intentTags.length > 0 && categoryHits === intentTags.length) {
    score += 220;
  } else if (broadCatalogQueryRequested && intentTags.length > 0 && categoryHits === 0 && tokenHits === 0) {
    score -= 220;
  }

  if (priceFilterRequested && effectivePrice !== null) {
    score += 300;
    if (priceFilter.max !== null) {
      score += Math.max(0, 100 - effectivePrice);
    } else if (priceFilter.min !== null) {
      score += Math.min(100, effectivePrice);
    }
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

const sortedBody = filteredRows
  .map((row) => ({
    ...row,
    catalog_title: getCatalogTitle(row),
    canonical_product_url: getCanonicalProductUrl(row.product_url),
    variation_label: stripText(row.price_variation_txt_variable || row.price_variation_txt_static || ''),
    effective_price: getEffectivePrice(row),
    match_score: scoreRow(row)
  }))
  .filter((row) => priceFilterRequested || row.match_score > 0)
  .sort((left, right) => right.match_score - left.match_score || String(left.catalog_title || '').localeCompare(String(right.catalog_title || '')));

const bestMatch = sortedBody[0] ?? null;

return {
  ...catalogResponse,
  body: sortedBody,
  productSearch: {
    source: 'google_sheet',
    requested: productLookupRequested,
    search_term: supportContext.productSearchTerm,
    requested_tokens: requestedTokens,
    semantic_tokens: queryTokens,
    intent_tags: intentTags,
    broad_catalog_query: broadCatalogQueryRequested,
    language_hint: languageHint,
    price_filter: priceFilter,
    result_count: sortedBody.length,
    top_match_name: bestMatch?.catalog_title ?? null,
    top_match_url: bestMatch?.canonical_product_url ?? null,
    top_match_score: bestMatch?.match_score ?? null
  }
};
'@
$sortNode.parameters.jsCode = $sortCode

$buildInitialBlock = @'
const productLookupRequested = Boolean(supportContext.productLookupRequested);
const priceFilter = supportContext.priceFilter ?? { requested: false, min: null, max: null };
const priceFilterRequested = Boolean(priceFilter.requested);
const broadCatalogQueryRequested = Boolean(supportContext.broadCatalogQueryRequested);
const languageHint = String(supportContext.languageHint || 'auto');
const categoryIntentTags = Array.isArray(supportContext.categoryIntentTags) ? supportContext.categoryIntentTags : [];
const semanticSearchTokens = Array.isArray(supportContext.semanticSearchTokens) ? supportContext.semanticSearchTokens : [];
const sortedProducts = Array.isArray(productResponse.body) ? productResponse.body : [];
const positiveProducts = sortedProducts.filter((product) => Number(product.match_score ?? 0) > 0);
const selectedProducts = productLookupRequested ? (positiveProducts.length > 0 ? positiveProducts : sortedProducts).slice(0, broadCatalogQueryRequested ? 8 : 5) : [];
const cartLinkRequested = /\b(?:cart|add to cart|buy now|checkout link|buy link|purchase link|link to buy|link para comprar|link de compra|link do carrinho|adicionar ao carrinho|comprar agora|carrinho|checkout)\b/i.test(String(supportContext.content || ''));
'@

$buildMatchBlock = @'
const bestProductMatch = productSummary[0] ?? null;
const relevanceThreshold = broadCatalogQueryRequested ? 140 : 300;
const hasRelevantProductMatch = Boolean(
  productLookupRequested &&
  bestProductMatch &&
  (priceFilterRequested ? productSummary.length > 0 : bestProductMatch.match_score >= relevanceThreshold)
);
const priceMatchedProducts = priceFilterRequested && hasRelevantProductMatch ? productSummary.slice(0, broadCatalogQueryRequested ? 8 : 5) : [];
const bestProductCartUrl = cartLinkRequested && hasRelevantProductMatch
  ? buildCartUrl(supportContext.config.wooBaseUrl, selectedProducts[0], orderDraft.quantity || 1)
  : null;
'@

$buildStaticBlock = @'
const staticStore = getStaticStore();
const orderDrafts = staticStore ? (staticStore.chatwootOrderDrafts = staticStore.chatwootOrderDrafts || {}) : {};
const customerProfiles = staticStore ? (staticStore.chatwootCustomerProfiles = staticStore.chatwootCustomerProfiles || {}) : {};
const normalizeProfileKey = (kind, value) => {
  const cleaned = stripText(value).toLowerCase();
  return cleaned ? `${kind}:${cleaned}` : '';
};
const conversationKey = String(supportContext.conversationId || '');
const profileKeys = [...new Set([
  normalizeProfileKey('phone', supportContext.contactPhone),
  normalizeProfileKey('email', orderDraft.billingEmail),
  normalizeProfileKey('email', orderSummary?.billing_email)
].filter(Boolean))];
let customerProfileMemory = profileKeys
  .map((key) => customerProfiles[key])
  .find((entry) => entry && typeof entry === 'object') || null;
const createOrderReturnedList = Array.isArray(createOrderResponse?.body);
const createOrderBody = normalizeWooResponseBody(createOrderResponse?.body);
const createOrderErrorMessage = createOrderReturnedList
  ? 'Woo create endpoint returned a list of orders instead of a new order. This usually means the POST was redirected or treated as GET.'
  : String(createOrderBody?.message || createOrderResponse?.body?.message || createOrderResponse?.statusMessage || '').trim();

'@

$buildSystemMessage = @'
const systemMessage = [
  'You are the Famivita AI customer support agent working inside Chatwoot.',
  'Act like an excellent Famivita sales specialist: friendly, clear, persuasive, and accurate.',
  'Reply in the same language as the customer whenever possible.',
  'Use only the retrieved context for factual claims about orders, products, shipping, returns, payment, or policies.',
  'Only treat product_lookup as relevant when product_search.requested is true and product_search.has_relevant_match is true.',
  'If product_search.requested is false, do not mention products or include product URLs.',
  'If product_search.has_relevant_match is true, do not say the product is unavailable or missing from the catalog.',
  'Use product_lookup fields such as title, variation_label, price, stock_status, manufacturer, tags, summary, free_shipping_tag, discount_tag, and cart_url to answer product questions accurately.',
  'For broad category queries like vitamins for pregnancy, fertility supplements, or trying to conceive, recommend a short curated list of the best-matching products from product_lookup.',
  'Use customer_profile_memory and short_term_memory to personalize suggestions, but do not mention hidden memory or internal storage.',
  'Use recent_messages and short_term_memory to resolve follow-up references such as "that one", "same as before", or "the last product".',
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

'@

$buildCode = $buildNode.parameters.jsCode
$buildCode = Replace-Between -Text $buildCode -StartToken 'const productLookupRequested = Boolean(supportContext.productLookupRequested);' -EndToken 'const buildCartUrl = (wooBaseUrl, product, quantity = 1) => {' -Replacement $buildInitialBlock -Label 'Build OpenAI Request3'
$buildCode = Replace-Between -Text $buildCode -StartToken 'const bestProductMatch = productSummary[0] ?? null;' -EndToken 'const buildOrderPayUrl = (wooBaseUrl, orderId, orderKey) => {' -Replacement $buildMatchBlock -Label 'Build OpenAI Request3'
$buildCode = Replace-Between -Text $buildCode -StartToken 'const staticStore = getStaticStore();' -EndToken 'let orderCreationStatus =' -Replacement $buildStaticBlock -Label 'Build OpenAI Request3'
$buildCode = $buildCode.Replace("const orderPayUrl = createdOrder?.pay_url ?? null;`nconst retrievedContext = {", @"
const orderPayUrl = createdOrder?.pay_url ?? null;
const recentCustomerMessages = (Array.isArray(supportContext.recentMessages) ? supportContext.recentMessages : [])
  .filter((message) => message.role === 'user')
  .slice(-6)
  .map((message) => ({
    content: stripText(message.content),
    created_at: message.created_at
  }));

if (createdOrder && staticStore && profileKeys.length > 0) {
  const baseProfile = customerProfileMemory && typeof customerProfileMemory === 'object' ? customerProfileMemory : {};
  const lastOrderedProducts = Array.isArray(baseProfile.lastOrderedProducts) ? baseProfile.lastOrderedProducts : [];
  const nextProfile = {
    ...baseProfile,
    contactName: supportContext.contactName || baseProfile.contactName || '',
    phoneNumber: supportContext.contactPhone || baseProfile.phoneNumber || '',
    billingEmail: createdOrder.billing_email || orderDraft.billingEmail || baseProfile.billingEmail || '',
    preferredLanguage: languageHint || baseProfile.preferredLanguage || '',
    interestTags: [...new Set([...(Array.isArray(baseProfile.interestTags) ? baseProfile.interestTags : []), ...categoryIntentTags])].filter(Boolean).slice(-12),
    recentSearchTerms: [...new Set([...(Array.isArray(baseProfile.recentSearchTerms) ? baseProfile.recentSearchTerms : []), supportContext.productSearchTerm].filter(Boolean))].slice(-12),
    recentSemanticTokens: [...new Set([...(Array.isArray(baseProfile.recentSemanticTokens) ? baseProfile.recentSemanticTokens : []), ...semanticSearchTokens])].filter(Boolean).slice(-20),
    lastOrderedProducts: [...lastOrderedProducts, {
      order_id: createdOrder.id,
      product_title: createdOrder.product_title || '',
      quantity: createdOrder.quantity || null,
      created_at: createdOrder.createdAt || Date.now()
    }].slice(-10),
    updatedAt: Date.now()
  };
  for (const key of profileKeys) {
    customerProfiles[key] = nextProfile;
  }
  customerProfileMemory = nextProfile;
}

const retrievedContext = {
"@)
$buildCode = $buildCode.Replace("  product_search: {`n    source: 'google_sheet',`n    requested: productLookupRequested,`n    search_term: productResponse.productSearch?.search_term ?? supportContext.productSearchTerm,`n    requested_tokens: productResponse.productSearch?.requested_tokens ?? supportContext.productSearchTokens ?? [],`n    price_filter: priceFilter,`n    raw_candidate_count: productResponse.productSearch?.result_count ?? sortedProducts.length,`n    has_relevant_match: hasRelevantProductMatch,`n    best_match_name: hasRelevantProductMatch ? bestProductMatch?.title ?? null : null,`n    best_match_url: hasRelevantProductMatch ? bestProductMatch?.product_url ?? null : null,`n    best_match_score: hasRelevantProductMatch ? bestProductMatch?.match_score ?? null : null`n  },", @"
  product_search: {
    source: 'google_sheet',
    requested: productLookupRequested,
    search_term: productResponse.productSearch?.search_term ?? supportContext.productSearchTerm,
    requested_tokens: productResponse.productSearch?.requested_tokens ?? supportContext.productSearchTokens ?? [],
    semantic_tokens: productResponse.productSearch?.semantic_tokens ?? semanticSearchTokens,
    intent_tags: productResponse.productSearch?.intent_tags ?? categoryIntentTags,
    broad_catalog_query: productResponse.productSearch?.broad_catalog_query ?? broadCatalogQueryRequested,
    language_hint: productResponse.productSearch?.language_hint ?? languageHint,
    price_filter: priceFilter,
    raw_candidate_count: productResponse.productSearch?.result_count ?? sortedProducts.length,
    has_relevant_match: hasRelevantProductMatch,
    best_match_name: hasRelevantProductMatch ? bestProductMatch?.title ?? null : null,
    best_match_url: hasRelevantProductMatch ? bestProductMatch?.product_url ?? null : null,
    best_match_score: hasRelevantProductMatch ? bestProductMatch?.match_score ?? null : null
  },
"@)
$buildCode = $buildCode.Replace("  faq_matches: supportContext.faqMatches,`n  recent_messages: supportContext.recentMessages,`n  order_creation: {", @"
  faq_matches: supportContext.faqMatches,
  recent_messages: supportContext.recentMessages,
  short_term_memory: {
    recent_customer_messages: recentCustomerMessages,
    current_intent_tags: categoryIntentTags,
    current_semantic_tokens: semanticSearchTokens,
    broad_catalog_query: broadCatalogQueryRequested
  },
  customer_profile_memory: customerProfileMemory ? {
    contact_name: customerProfileMemory.contactName || '',
    phone_number: customerProfileMemory.phoneNumber || '',
    billing_email: customerProfileMemory.billingEmail || '',
    billing_city: customerProfileMemory.billingCity || '',
    billing_state: customerProfileMemory.billingState || '',
    preferred_language: customerProfileMemory.preferredLanguage || '',
    interest_tags: customerProfileMemory.interestTags || [],
    recent_search_terms: customerProfileMemory.recentSearchTerms || [],
    recent_semantic_tokens: customerProfileMemory.recentSemanticTokens || [],
    last_viewed_products: customerProfileMemory.lastViewedProducts || [],
    last_ordered_products: customerProfileMemory.lastOrderedProducts || []
  } : null,
  order_creation: {
"@)
$buildCode = Replace-Between -Text $buildCode -StartToken 'const systemMessage = [' -EndToken 'const userMessage = [' -Replacement $buildSystemMessage -Label 'Build OpenAI Request3'
$buildNode.parameters.jsCode = $buildCode

$draftStaticBlock = @'
const staticStore = getStaticStore();
const orderDrafts = staticStore ? (staticStore.chatwootOrderDrafts = staticStore.chatwootOrderDrafts || {}) : {};
const conversationMemory = staticStore ? (staticStore.chatwootConversationOrderMemory = staticStore.chatwootConversationOrderMemory || {}) : {};
const customerProfiles = staticStore ? (staticStore.chatwootCustomerProfiles = staticStore.chatwootCustomerProfiles || {}) : {};
const conversationKey = String(supportContext.conversationId || '');
const previousDraft = conversationKey && orderDrafts[conversationKey] ? orderDrafts[conversationKey] : {};
const previousConversationMemory = conversationKey && conversationMemory[conversationKey] ? conversationMemory[conversationKey] : {};
const normalizeProfileKey = (kind, value) => {
  const cleaned = stripText(value).toLowerCase();
  return cleaned ? `${kind}:${cleaned}` : '';
};
const previousDraftEmail = String(previousDraft.billingEmail || '').trim().toLowerCase();
const profileKeyCandidates = [...new Set([
  normalizeProfileKey('phone', supportContext.contactPhone),
  normalizeProfileKey('email', previousDraftEmail),
  normalizeProfileKey('email', previousConversationMemory.billingEmail || '')
].filter(Boolean))];
const rememberedProfile = profileKeyCandidates
  .map((key) => customerProfiles[key])
  .find((entry) => entry && typeof entry === 'object') || {};
const rememberedBillingEmail = String(previousConversationMemory.billingEmail || rememberedProfile.billingEmail || '').trim().toLowerCase();
const rememberedBillingCpf = String(previousConversationMemory.billingCpf || rememberedProfile.billingCpf || '').trim();
const rememberedBillingAddress1 = String(previousConversationMemory.billingAddress1 || rememberedProfile.billingAddress1 || '').trim();
const rememberedBillingNumber = String(previousConversationMemory.billingNumber || rememberedProfile.billingNumber || '').trim();
const rememberedBillingCity = String(previousConversationMemory.billingCity || rememberedProfile.billingCity || '').trim();
const rememberedBillingState = String(previousConversationMemory.billingState || rememberedProfile.billingState || '').trim();
const rememberedBillingPostcode = String(previousConversationMemory.billingPostcode || rememberedProfile.billingPostcode || '').trim();
const rememberedInterestTags = Array.isArray(rememberedProfile.interestTags) ? rememberedProfile.interestTags : [];
const previousProduct = previousDraft.product ?? null;
'@

$draftBillingBlock = @'
const billingEmail = currentEmail || (carryForwardOrderDraft ? previousDraft.billingEmail : '') || (reusePreviousBillingRequested ? rememberedBillingEmail : '') || '';
const billingCpf = currentBillingCpf || (carryForwardOrderDraft ? previousDraft.billingCpf : '') || (reusePreviousBillingRequested ? rememberedBillingCpf : '') || '';
const billingAddress1 = currentBillingAddress1 || (carryForwardOrderDraft ? previousDraft.billingAddress1 : '') || (reusePreviousBillingRequested ? rememberedBillingAddress1 : '') || '';
const billingNumber = currentBillingNumber || (carryForwardOrderDraft ? previousDraft.billingNumber : '') || (reusePreviousBillingRequested ? rememberedBillingNumber : '') || '';
const billingCity = currentBillingCity || (carryForwardOrderDraft ? previousDraft.billingCity : '') || (reusePreviousBillingRequested ? rememberedBillingCity : '') || '';
const billingState = currentBillingState || (carryForwardOrderDraft ? previousDraft.billingState : '') || (reusePreviousBillingRequested ? rememberedBillingState : '') || '';
const billingPostcode = currentBillingPostcode || (carryForwardOrderDraft ? previousDraft.billingPostcode : '') || (reusePreviousBillingRequested ? rememberedBillingPostcode : '') || '';
'@

$draftSaveBlock = @'
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

  const currentProfileKeys = [...new Set([
    ...profileKeyCandidates,
    normalizeProfileKey('phone', supportContext.contactPhone),
    normalizeProfileKey('email', billingEmail)
  ].filter(Boolean))];

  if (currentProfileKeys.length > 0) {
    const baseProfile = currentProfileKeys
      .map((key) => customerProfiles[key])
      .find((entry) => entry && typeof entry === 'object') || rememberedProfile || {};

    const priorViewedProducts = Array.isArray(baseProfile.lastViewedProducts) ? baseProfile.lastViewedProducts : [];
    const nextViewedProducts = [...priorViewedProducts];
    if (selectedProduct?.title) {
      nextViewedProducts.push({
        product_id: selectedProduct.product_id || '',
        variation_id: selectedProduct.variation_id || '',
        title: selectedProduct.title || '',
        product_url: selectedProduct.product_url || '',
        updatedAt: now
      });
    }

    const dedupedViewedProducts = [];
    const seenViewedKeys = new Set();
    for (const entry of nextViewedProducts.slice(-12).reverse()) {
      const key = `${entry.product_id || ''}:${entry.variation_id || ''}:${entry.title || ''}`;
      if (!key.trim() || seenViewedKeys.has(key)) continue;
      seenViewedKeys.add(key);
      dedupedViewedProducts.unshift(entry);
    }

    const nextProfile = {
      ...baseProfile,
      contactName: supportContext.contactName || baseProfile.contactName || '',
      phoneNumber: supportContext.contactPhone || baseProfile.phoneNumber || '',
      billingEmail: billingEmail || baseProfile.billingEmail || '',
      billingCpf: billingCpf || baseProfile.billingCpf || '',
      billingAddress1: billingAddress1 || baseProfile.billingAddress1 || '',
      billingNumber: billingNumber || baseProfile.billingNumber || '',
      billingCity: billingCity || baseProfile.billingCity || '',
      billingState: billingState || baseProfile.billingState || '',
      billingPostcode: billingPostcode || baseProfile.billingPostcode || '',
      preferredLanguage: supportContext.languageHint || baseProfile.preferredLanguage || '',
      interestTags: [...new Set([...(Array.isArray(baseProfile.interestTags) ? baseProfile.interestTags : []), ...rememberedInterestTags, ...((Array.isArray(supportContext.categoryIntentTags) ? supportContext.categoryIntentTags : []))])].filter(Boolean).slice(-12),
      recentSearchTerms: [...new Set([...(Array.isArray(baseProfile.recentSearchTerms) ? baseProfile.recentSearchTerms : []), supportContext.productSearchTerm].filter(Boolean))].slice(-12),
      recentSemanticTokens: [...new Set([...(Array.isArray(baseProfile.recentSemanticTokens) ? baseProfile.recentSemanticTokens : []), ...((Array.isArray(supportContext.semanticSearchTokens) ? supportContext.semanticSearchTokens : []))])].filter(Boolean).slice(-20),
      lastViewedProducts: dedupedViewedProducts,
      lastOrderDraftProduct: selectedProduct || baseProfile.lastOrderDraftProduct || null,
      updatedAt: now
    };

    for (const key of currentProfileKeys) {
      customerProfiles[key] = nextProfile;
    }
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

'@

$draftCode = $draftNode.parameters.jsCode
$draftCode = Replace-Between -Text $draftCode -StartToken 'const staticStore = getStaticStore();' -EndToken 'const previousProduct = previousDraft.product ?? null;' -Replacement $draftStaticBlock -Label 'Prepare Woo Order Draft3'
$draftCode = Replace-Between -Text $draftCode -StartToken 'const billingEmail = currentEmail' -EndToken 'const hasExplicitQuantity =' -Replacement $draftBillingBlock -Label 'Prepare Woo Order Draft3'
$draftCode = Replace-Between -Text $draftCode -StartToken 'if (conversationKey && staticStore) {' -EndToken 'return {' -Replacement $draftSaveBlock -Label 'Prepare Woo Order Draft3'
$draftNode.parameters.jsCode = $draftCode

$json | ConvertTo-Json -Depth 100 | Set-Content -Path $workflowPath
Write-Output "Updated workflow: $workflowPath"
