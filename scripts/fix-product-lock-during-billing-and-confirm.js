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
);`,
    `const currentMessagePrimarilyBillingOrConfirmation = Boolean(
  previousProduct &&
  !matchedOption &&
  !hasChoiceSelection &&
  (
    hasBillingFieldUpdate ||
    reusePreviousBillingRequested ||
    /@/.test(currentMessage) ||
    currentQuantity !== null ||
    confirmRegex.test(currentMessage)
  )
);
const userSeemsToBeChangingProduct = Boolean(
  previousProduct &&
  currentProductTokens.length > 0 &&
  !currentOrderSelectionSignal &&
  !currentMessagePrimarilyBillingOrConfirmation &&
  bestProduct &&
  String(bestProduct.product_id || '') !== String(previousProduct.product_id || '')
);
const hasClearCurrentProductCandidate = Boolean(
  bestProduct &&
  currentProductTokens.length > 0 &&
  !currentMessagePrimarilyBillingOrConfirmation &&
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
  (
    currentMessagePrimarilyBillingOrConfirmation ||
    (!hasClearCurrentProductCandidate && !userSeemsToBeChangingProduct)
  )
);`,
    `${fileName} product lock block`
  );

  fs.writeFileSync(filePath, JSON.stringify(workflow, null, 2) + '\n', 'utf8');
  console.log(`Patched ${fileName}`);
}
