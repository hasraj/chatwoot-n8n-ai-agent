$ErrorActionPreference = 'Stop'

$paths = @(
  'f:\github\chatwoot n8n ai agent\chatwoot-ai-product-search-and-order-create-final.json',
  'f:\github\chatwoot n8n ai agent\chatwoot-ai-main-agent-specialists.json',
  'f:\github\chatwoot n8n ai agent\chatwoot-ai-agent-hybrid.json'
)

foreach ($path in $paths) {
  if (-not (Test-Path $path)) {
    continue
  }

  $json = Get-Content -Raw $path | ConvertFrom-Json
  $gateNode = $json.nodes | Where-Object { $_.name -like 'Gate Test Contact*' } | Select-Object -First 1
  $sortNode = $json.nodes | Where-Object { $_.name -like 'Sort Product Matches*' } | Select-Object -First 1

  if (-not $gateNode -or -not $sortNode) {
    continue
  }

  $gateName = $gateNode.name.Replace("'", "\'")
  $gateCode = [string]$gateNode.parameters.jsCode

  if ($gateCode -notmatch "'some', 'give', 'gimme', 'gime', 'list'") {
    $anchor = "'abaixo', 'menor', 'acima', 'maior', 'entre', 'ate', 'ate', 'ate'"
    $replacement = "'abaixo', 'menor', 'acima', 'maior', 'entre', 'ate', 'ate', 'ate',`r`n  'some', 'give', 'gimme', 'gime', 'list', 'lists', 'catalog', 'catalogue', 'catalogo', 'option', 'options',`r`n  'suggest', 'suggestion', 'suggestions', 'recommend', 'recommendation', 'recommendations', 'available', 'availability',`r`n  'disponivel', 'disponiveis', 'mostrar', 'mostre', 'sugira', 'sugerir', 'recomende', 'lista', 'listar'"
    $gateNode.parameters.jsCode = $gateCode.Replace($anchor, $replacement)
  }

  $sortCode = @'
const supportContext = $('__GATE_NAME__').first().json;
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

const productLookupRequested = Boolean(supportContext.productLookupRequested);
const priceFilter = supportContext.priceFilter ?? { requested: false, min: null, max: null };
const priceFilterRequested = Boolean(priceFilter.requested);
const queryTokens = Array.isArray(supportContext.productSearchTokens) && supportContext.productSearchTokens.length > 0
  ? supportContext.productSearchTokens.map((token) => normalizeText(token)).filter(Boolean)
  : [];
const hasTextQuery = productLookupRequested && queryTokens.length > 0;
const queryText = hasTextQuery
  ? normalizeText(supportContext.productSearchTerm || queryTokens.join(' '))
  : '';
const synonymGroups = [
  ['vitamin', 'vitamins', 'vitamina', 'vitaminas', 'suplemento', 'suplementos'],
  ['pregnancy', 'pregnant', 'fertility', 'fertile', 'gravidez', 'gestante', 'gestacao', 'concepcao', 'preconcepcao', 'engravidar'],
  ['lubricant', 'lubrificante', 'lubrificantes'],
  ['omega', 'omega3', 'dha']
];
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
    if (group.includes(normalized)) {
      for (const alias of group) {
        variants.add(alias);
      }
    }
  }

  return [...variants].filter(Boolean);
};

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
      requested_tokens: supportContext.productSearchTokens ?? [],
      price_filter: priceFilter,
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

  let fieldHits = 0;
  if (hasTextQuery) {
    const titleWords = fields.title.split(/\s+/).filter(Boolean);
    for (const token of queryTokens) {
      const variants = expandTokenVariants(token);
      if (variants.some((variant) => titleWords.includes(variant))) {
        fieldHits += 1;
        score += 220;
      } else if (variants.some((variant) => fields.title.includes(variant))) {
        fieldHits += 1;
        score += 170;
      } else if (variants.some((variant) => fields.url.includes(variant))) {
        fieldHits += 1;
        score += 120;
      } else if (variants.some((variant) => fields.sku.includes(variant))) {
        fieldHits += 1;
        score += 90;
      } else if (variants.some((variant) => fields.tags.includes(variant) || fields.manufacturer.includes(variant))) {
        fieldHits += 1;
        score += 70;
      } else if (variants.some((variant) => fields.summary.includes(variant))) {
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
    effective_price: getEffectivePrice(row),
    match_score: scoreRow(row)
  }))
  .sort((left, right) => {
    if (priceFilterRequested && !hasTextQuery) {
      const leftPrice = Number.isFinite(left.effective_price) ? left.effective_price : Number.POSITIVE_INFINITY;
      const rightPrice = Number.isFinite(right.effective_price) ? right.effective_price : Number.POSITIVE_INFINITY;
      if (leftPrice !== rightPrice) {
        return leftPrice - rightPrice;
      }
    }

    return right.match_score - left.match_score || String(left.catalog_title || '').localeCompare(String(right.catalog_title || ''));
  });

const getDedupKey = (row) => {
  const productId = String(row.product_id || '').trim();
  if (productId) {
    return `product:${productId}`;
  }

  const canonicalUrl = String(row.canonical_product_url || '').trim();
  if (canonicalUrl) {
    return `url:${canonicalUrl}`;
  }

  const normalizedTitle = normalizeText(row.catalog_title || '');
  if (normalizedTitle) {
    return `title:${normalizedTitle}`;
  }

  const uniqueId = String(row.unique_id || row.variation_id || '').trim();
  if (uniqueId) {
    return `unique:${uniqueId}`;
  }

  return `fallback:${Math.random().toString(36).slice(2)}`;
};

const dedupedBody = [];
const seenKeys = new Set();
for (const row of sortedBody) {
  const dedupKey = getDedupKey(row);
  if (seenKeys.has(dedupKey)) {
    continue;
  }
  seenKeys.add(dedupKey);
  dedupedBody.push(row);
}

return {
  ...catalogResponse,
  body: dedupedBody,
  productSearch: {
    source: 'google_sheet',
    requested: true,
    search_term: supportContext.productSearchTerm,
    requested_tokens: supportContext.productSearchTokens ?? [],
    price_filter: priceFilter,
    result_count: dedupedBody.length,
    top_match_name: dedupedBody[0]?.catalog_title ?? null,
    top_match_url: dedupedBody[0]?.canonical_product_url ?? dedupedBody[0]?.product_url ?? null,
    top_match_score: dedupedBody[0]?.match_score ?? null
  }
};
'@

  $sortCode = $sortCode.Replace('__GATE_NAME__', $gateName)
  $sortCode = $sortCode.Replace('const supportContext = $gateName.first().json;', ("const supportContext = `$(''{0}'').first().json;" -f $gateName))
  $sortCode = $sortCode.Replace('const catalogResponse = \.first().json ?? {};', 'const catalogResponse = $input.first().json ?? {};')

  $sortNode.parameters.jsCode = $sortCode
  $json | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding UTF8
  Write-Output "Reset $path"
}
