const fs = require('fs');
const path = require('path');

const workflowFiles = [
  'chatwoot-ai-main-agent-specialists.json',
  'chatwoot-ai-agent-hybrid.json',
  'chatwoot-ai-product-search-and-order-create-final.json',
];

const workspaceRoot = path.resolve(__dirname, '..');

const replaceOrThrow = (text, searchValue, replaceValue, label) => {
  if (text.includes(searchValue)) {
    return text.replace(searchValue, replaceValue);
  }
  if (text.includes(replaceValue)) {
    return text;
  }
  throw new Error(`Could not find patch target for ${label}`);
};

for (const fileName of workflowFiles) {
  const filePath = path.join(workspaceRoot, fileName);
  const workflow = JSON.parse(fs.readFileSync(filePath, 'utf8'));

  const draftNode = workflow.nodes.find((node) => node.name === 'Prepare Woo Order Draft3');
  if (!draftNode) throw new Error(`Prepare Woo Order Draft3 not found in ${fileName}`);

  draftNode.parameters.jsCode = replaceOrThrow(
    draftNode.parameters.jsCode,
    `const rememberedBillingEmail = String(previousConversationMemory.billingEmail || rememberedProfile.billingEmail || '').trim().toLowerCase();
const rememberedBillingCpf = String(previousConversationMemory.billingCpf || rememberedProfile.billingCpf || '').trim();
const rememberedBillingAddress1 = String(previousConversationMemory.billingAddress1 || rememberedProfile.billingAddress1 || '').trim();
const rememberedBillingNumber = String(previousConversationMemory.billingNumber || rememberedProfile.billingNumber || '').trim();
const rememberedBillingNeighborhood = String(previousConversationMemory.billingNeighborhood || rememberedProfile.billingNeighborhood || '').trim();
const rememberedBillingCity = String(previousConversationMemory.billingCity || rememberedProfile.billingCity || '').trim();
const rememberedBillingState = String(previousConversationMemory.billingState || rememberedProfile.billingState || '').trim();
const rememberedBillingPostcode = String(previousConversationMemory.billingPostcode || rememberedProfile.billingPostcode || '').trim();
const rememberedInterestTags = Array.isArray(rememberedProfile.interestTags) ? rememberedProfile.interestTags : [];`,
    `const looksLikeCorruptedBillingAddress = (value) => {
  const text = stripText(value);
  const normalized = normalizeText(text);
  if (!normalized) return false;
  if (/https?:\\/\\//i.test(text)) return true;
  if (/\\br\\$\\s*\\d/i.test(normalized)) return true;
  if (/^(?:need this|i want|quero|preciso|use same|usar o mesmo|same billing|same address)\\b/i.test(normalized)) return true;
  if (/\\b(?:view product|add to cart|product link|direct add-to-cart|link do produto|link direto|stock status|summary|resumo|price|preco)\\b/i.test(normalized)) return true;
  const dashParts = text.split(/\\s+-\\s+/).filter(Boolean);
  if (dashParts.length >= 3 && !/^(?:rua|avenida|av\\.?|travessa|alameda|estrada|rodovia|praca|pra\\u00e7a|street|road|lane|drive|avenue)\\b/i.test(normalized)) {
    return true;
  }
  return false;
};
const chooseRememberedBillingValue = (primaryValue, fallbackValue, validator = null) => {
  const first = String(primaryValue || '').trim();
  const second = String(fallbackValue || '').trim();
  if (first && (!validator || validator(first))) return first;
  if (second && (!validator || validator(second))) return second;
  return '';
};
const rawRememberedConversationBillingEmail = String(previousConversationMemory.billingEmail || '').trim().toLowerCase();
const rawRememberedProfileBillingEmail = String(rememberedProfile.billingEmail || '').trim().toLowerCase();
const rawRememberedConversationBillingCpf = String(previousConversationMemory.billingCpf || '').trim();
const rawRememberedProfileBillingCpf = String(rememberedProfile.billingCpf || '').trim();
const rawRememberedConversationBillingAddress1 = String(previousConversationMemory.billingAddress1 || '').trim();
const rawRememberedProfileBillingAddress1 = String(rememberedProfile.billingAddress1 || '').trim();
const rawRememberedConversationBillingNumber = String(previousConversationMemory.billingNumber || '').trim();
const rawRememberedProfileBillingNumber = String(rememberedProfile.billingNumber || '').trim();
const rawRememberedConversationBillingNeighborhood = String(previousConversationMemory.billingNeighborhood || '').trim();
const rawRememberedProfileBillingNeighborhood = String(rememberedProfile.billingNeighborhood || '').trim();
const rawRememberedConversationBillingCity = String(previousConversationMemory.billingCity || '').trim();
const rawRememberedProfileBillingCity = String(rememberedProfile.billingCity || '').trim();
const rawRememberedConversationBillingState = String(previousConversationMemory.billingState || '').trim();
const rawRememberedProfileBillingState = String(rememberedProfile.billingState || '').trim();
const rawRememberedConversationBillingPostcode = String(previousConversationMemory.billingPostcode || '').trim();
const rawRememberedProfileBillingPostcode = String(rememberedProfile.billingPostcode || '').trim();
const rememberedBillingEmail = chooseRememberedBillingValue(rawRememberedConversationBillingEmail, rawRememberedProfileBillingEmail);
const rememberedBillingCpf = chooseRememberedBillingValue(rawRememberedConversationBillingCpf, rawRememberedProfileBillingCpf, (value) => Boolean(normalizeCpf(value)));
const rememberedBillingAddress1 = chooseRememberedBillingValue(rawRememberedConversationBillingAddress1, rawRememberedProfileBillingAddress1, (value) => !looksLikeCorruptedBillingAddress(value));
const rememberedBillingNumber = chooseRememberedBillingValue(rawRememberedConversationBillingNumber, rawRememberedProfileBillingNumber);
const rememberedBillingNeighborhood = chooseRememberedBillingValue(rawRememberedConversationBillingNeighborhood, rawRememberedProfileBillingNeighborhood);
const rememberedBillingCity = chooseRememberedBillingValue(rawRememberedConversationBillingCity, rawRememberedProfileBillingCity);
const rememberedBillingState = chooseRememberedBillingValue(rawRememberedConversationBillingState, rawRememberedProfileBillingState);
const rememberedBillingPostcode = chooseRememberedBillingValue(rawRememberedConversationBillingPostcode, rawRememberedProfileBillingPostcode, (value) => Boolean(normalizePostcode(value)));
const rememberedInterestTags = Array.isArray(rememberedProfile.interestTags) ? rememberedProfile.interestTags : [];`,
    `${fileName} remembered billing block`
  );

  draftNode.parameters.jsCode = replaceOrThrow(
    draftNode.parameters.jsCode,
    `const userSeemsToBeChangingProduct = Boolean(
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
}`,
    `const userSeemsToBeChangingProduct = Boolean(
  previousProduct &&
  currentProductTokens.length > 0 &&
  !currentOrderSelectionSignal &&
  bestProduct &&
  String(bestProduct.product_id || '') !== String(previousProduct.product_id || '')
);
const hasClearCurrentProductCandidate = Boolean(
  bestProduct &&
  currentProductTokens.length > 0 &&
  (
    explicitNewOrderRequest ||
    explicitProductInfoRequest ||
    supportContext.productLookupRequested ||
    supportContext.createOrderRequested
  ) &&
  (
    !previousProduct ||
    String(bestProduct.product_id || '') !== String(previousProduct.product_id || '') ||
    String(bestProduct.variation_id || '') !== String(previousProduct.variation_id || '')
  )
);
const shouldKeepPreviousProduct = Boolean(
  previousProduct &&
  orderConversationRequested &&
  !explicitNewOrderRequest &&
  !hasClearCurrentProductCandidate &&
  !userSeemsToBeChangingProduct
);

let selectedProduct = null;
if (matchedOption) {
  const exactRow = candidateRows.find((row) => String(row.variation_id || '') === String(matchedOption.variation_id || ''))
    || rows.find((row) => String(row.variation_id || '') === String(matchedOption.variation_id || ''));
  selectedProduct = buildProductOption(exactRow || matchedOption);
} else if (hasClearCurrentProductCandidate && currentVariationOptions.length <= 1) {
  selectedProduct = buildProductOption(bestProduct);
} else if (shouldKeepPreviousProduct) {
  selectedProduct = previousProduct;
} else if (bestProduct && currentVariationOptions.length <= 1) {
  selectedProduct = buildProductOption(bestProduct);
}`,
    `${fileName} selected product block`
  );

  fs.writeFileSync(filePath, JSON.stringify(workflow, null, 2) + '\n', 'utf8');
  console.log(`Patched ${fileName}`);
}
