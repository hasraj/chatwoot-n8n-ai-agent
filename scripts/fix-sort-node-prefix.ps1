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
  $sortNode = $json.nodes | Where-Object { $_.name -like 'Sort Product Matches*' } | Select-Object -First 1
  $gateNode = $json.nodes | Where-Object { $_.name -like 'Gate Test Contact*' } | Select-Object -First 1
  if (-not $sortNode -or -not $gateNode) {
    continue
  }

  $code = [string]$sortNode.parameters.jsCode
  $normalizedCode = $code -replace "`r`n", "`n"
  $suffixIndex = $normalizedCode.IndexOf("if (!productLookupRequested) {")
  if ($suffixIndex -lt 0) {
    throw "Could not find the product lookup section marker in $path"
  }

  $suffix = $normalizedCode.Substring($suffixIndex)
  $gateName = $gateNode.name.Replace("'", "\'")

  $prefix = @"
const supportContext = $('$gateName').first().json;
const catalogResponse = \$input.first().json ?? {};

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
"@

  $sortNode.parameters.jsCode = (($prefix.TrimEnd() + "`n`n" + $suffix.TrimStart()) -replace "`n", "`r`n")
  $json | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding UTF8
  Write-Output "Fixed $path"
}
