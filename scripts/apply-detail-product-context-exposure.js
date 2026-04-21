const fs = require('fs');
const path = require('path');

const cwd = process.cwd();
const files = fs.readdirSync(cwd)
  .filter((name) => name.toLowerCase().endsWith('.json'))
  .map((name) => path.join(cwd, name));

const detailIntentSnippet = `const cartLinkRequested = /\\b(?:cart|add to cart|buy now|checkout link|buy link|purchase link|link to buy|link para comprar|link de compra|link do carrinho|adicionar ao carrinho|comprar agora|carrinho|checkout)\\b/i.test(String(supportContext.content || ''));`;
const detailIntentReplacement = `${detailIntentSnippet}
const detailIntentRequested = /\\b(?:detail|details|info|information|about|summary|ingredient|ingredients|detalhe|detalhes|informacao|informacoes|sobre)\\b/i.test(String(supportContext.content || ''));`;

const matchSnippet = `const hasRelevantProductMatch = Boolean(
  productLookupRequested &&
  bestProductMatch &&
  (priceFilterRequested ? uniqueProductSummary.length > 0 : bestProductMatch.match_score >= relevanceThreshold)
);`;
const matchReplacement = `${matchSnippet}
const shouldExposeProductLookup = Boolean(
  hasRelevantProductMatch ||
  (detailIntentRequested && productSummary.length > 0)
);`;

const lookupSnippet = `  product_lookup: hasRelevantProductMatch ? productSummary : [],`;
const lookupReplacement = `  product_lookup: shouldExposeProductLookup ? productSummary : [],`;

const compactLookupSnippet = `const compactProductLookup = (hasRelevantProductMatch ? productSummary : [])`;
const compactLookupReplacement = `const compactProductLookup = (shouldExposeProductLookup ? productSummary : [])`;

const returnSnippet = `  priceMatchedProducts,
  hasRelevantProductMatch,`;
const returnReplacement = `  priceMatchedProducts,
  productLookup: shouldExposeProductLookup ? productSummary : [],
  hasRelevantProductMatch,`;

let updated = 0;

for (const filePath of files) {
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    continue;
  }
  if (!Array.isArray(parsed.nodes)) continue;
  let changed = false;

  for (const node of parsed.nodes) {
    if (!node?.parameters?.jsCode || typeof node.parameters.jsCode !== 'string') continue;
    if (node.name !== 'Build OpenAI Request3') continue;

    let next = node.parameters.jsCode;
    if (!next.includes('detailIntentRequested') && next.includes(detailIntentSnippet)) {
      next = next.replace(detailIntentSnippet, detailIntentReplacement);
    }
    if (!next.includes('shouldExposeProductLookup') && next.includes(matchSnippet)) {
      next = next.replace(matchSnippet, matchReplacement);
    }
    if (next.includes(lookupSnippet)) {
      next = next.replace(lookupSnippet, lookupReplacement);
    }
    if (next.includes(compactLookupSnippet)) {
      next = next.replace(compactLookupSnippet, compactLookupReplacement);
    }
    if (!next.includes('productLookup: shouldExposeProductLookup ? productSummary : [],') && next.includes(returnSnippet)) {
      next = next.replace(returnSnippet, returnReplacement);
    }

    if (next !== node.parameters.jsCode) {
      node.parameters.jsCode = next;
      changed = true;
    }
  }

  if (changed) {
    fs.writeFileSync(filePath, JSON.stringify(parsed, null, 2) + '\n', 'utf8');
    updated += 1;
    console.log(`Updated ${path.basename(filePath)}`);
  }
}

console.log(`Patched ${updated} workflow file(s).`);
