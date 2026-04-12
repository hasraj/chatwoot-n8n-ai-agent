const fs = require('fs');

const file = 'f:/github/chatwoot n8n ai agent/chatwoot-ai-product-search-and-order-create-final.json';

function replaceOrThrow(code, from, to, label) {
  if (!code.includes(from)) throw new Error(`Pattern not found: ${label}`);
  return code.replace(from, to);
}

const raw = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
const data = JSON.parse(raw);

const draftNode = data.nodes.find((node) => node.name === 'Prepare Woo Order Draft3');
if (!draftNode) throw new Error('Prepare Woo Order Draft3 not found');
draftNode.parameters.jsCode = replaceOrThrow(
  draftNode.parameters.jsCode,
  "      address_2: billingNumber,\n      neighborhood: billingNeighborhood,",
  "      address_2: '',\n      neighborhood: billingNeighborhood,",
  'billing address_2 in draft payload'
);
draftNode.parameters.jsCode = replaceOrThrow(
  draftNode.parameters.jsCode,
  "      address_2: billingNumber,\n      city: billingCity,",
  "      address_2: '',\n      city: billingCity,",
  'shipping address_2 in draft payload'
);

const payloadNode = data.nodes.find((node) => node.name === 'Prepare Woo Order Payload3');
if (!payloadNode) throw new Error('Prepare Woo Order Payload3 not found');
payloadNode.parameters.jsCode = replaceOrThrow(
  payloadNode.parameters.jsCode,
  "    first_name: existingBilling.first_name || customerBilling.first_name || matchedCustomer.first_name || '',\n    last_name: existingBilling.last_name || customerBilling.last_name || matchedCustomer.last_name || ''",
  "    first_name: existingBilling.first_name || customerBilling.first_name || matchedCustomer.first_name || '',\n    last_name: existingBilling.last_name || customerBilling.last_name || matchedCustomer.last_name || '',\n    address_2: ''",
  'force empty billing address_2 in payload merge'
);

fs.writeFileSync(file, JSON.stringify(data, null, 2));
console.log('patched address_2 to empty');
