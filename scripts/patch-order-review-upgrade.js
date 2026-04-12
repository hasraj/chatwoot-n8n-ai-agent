const fs = require('fs');

const basePath = 'f:/github/chatwoot n8n ai agent/chatwoot-ai-product-search-and-order-create-final.json';

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(path, value) {
  fs.writeFileSync(path, JSON.stringify(value, null, 2));
}

function replaceOrThrow(code, from, to, label) {
  if (!code.includes(from)) {
    throw new Error(`Pattern not found: ${label}`);
  }
  return code.replace(from, to);
}

function replaceBetweenOrThrow(code, startToken, endToken, replacement, label) {
  const startIndex = code.indexOf(startToken);
  if (startIndex < 0) {
    throw new Error(`Start token not found: ${label}`);
  }
  const endIndex = code.indexOf(endToken, startIndex);
  if (endIndex < 0) {
    throw new Error(`End token not found: ${label}`);
  }
  return code.slice(0, startIndex) + replacement + code.slice(endIndex);
}

const data = readJson(basePath);

const draftNode = data.nodes.find((node) => node.name === 'Prepare Woo Order Draft3');
if (!draftNode) throw new Error('Prepare Woo Order Draft3 not found');
let draftCode = draftNode.parameters.jsCode;

draftCode = replaceOrThrow(
  draftCode,
  String.raw`const buildProductOption = (row) => row ? ({
  product_id: row.product_id || '',
  variation_id: row.variation_id || '',
  title: row.catalog_title || getCatalogTitle(row) || '',
  product_url: row.canonical_product_url || getCanonicalProductUrl(row.product_url) || row.product_url || '',
  variation_label: row.variation_label || getVariationLabel(row) || '',
  price: row.price || '',
  effective_price: row.effective_price ?? getEffectivePrice(row),
  match_score: Number(row.match_score ?? 0)
}) : null;`,
  String.raw`const buildProductOption = (row) => row ? ({
  product_id: row.product_id || '',
  variation_id: row.variation_id || '',
  title: row.catalog_title || getCatalogTitle(row) || '',
  product_url: row.canonical_product_url || getCanonicalProductUrl(row.product_url) || row.product_url || '',
  variation_label: row.variation_label || getVariationLabel(row) || '',
  price: row.price || '',
  effective_price: row.effective_price ?? getEffectivePrice(row),
  free_shipping_tag: row.free_shipping_tag || '',
  stock_status: row.stock_status || '',
  match_score: Number(row.match_score ?? 0)
}) : null;
const isTruthyTag = (value) => {
  const normalized = normalizeText(value).replace(/\s+/g, '');
  return ['1', 'true', 'yes', 'sim', 'free', 'gratis'].includes(normalized);
};
const buildOrderDisplayName = (product) => {
  const title = stripText(product?.title || '');
  const variationLabel = stripText(product?.variation_label || '');
  if (!title) return variationLabel;
  if (!variationLabel) return title;
  return normalizeText(title) === normalizeText(variationLabel) ? title : \`\${title} - \${variationLabel}\`;
};`,
  'buildProductOption block'
);

draftCode = replaceBetweenOrThrow(
  draftCode,
  `const missingFields = [];`,
  `if (conversationKey && staticStore) {`,
  String.raw`const missingFields = [];
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

const unitPrice = selectedProduct ? parseNumber(selectedProduct.effective_price ?? selectedProduct.price) : null;
const subtotal = selectedProduct && unitPrice !== null && Number.isInteger(quantity) && quantity > 0
  ? Number((unitPrice * quantity).toFixed(2))
  : null;
const shippingCost = selectedProduct && isTruthyTag(selectedProduct.free_shipping_tag) ? 0 : null;
const totalAmount = subtotal !== null ? Number((subtotal + (shippingCost ?? 0)).toFixed(2)) : null;
const orderReview = selectedProduct ? {
  items: [{
    product_id: selectedProduct.product_id || '',
    variation_id: selectedProduct.variation_id || '',
    display_name: buildOrderDisplayName(selectedProduct),
    title: selectedProduct.title || '',
    variation_label: selectedProduct.variation_label || '',
    quantity,
    unit_price: unitPrice,
    line_total: subtotal,
    product_url: selectedProduct.product_url || ''
  }],
  subtotal,
  shipping_cost: shippingCost,
  shipping_cost_known: shippingCost !== null,
  total_amount: totalAmount,
  total_amount_is_estimate: shippingCost === null,
  billing_email: billingEmail,
  billing_cpf: billingCpf,
  delivery_address: {
    address_1: billingAddress1,
    number: billingNumber,
    neighborhood: billingNeighborhood,
    city: billingCity,
    state: billingState,
    postcode: billingPostcode,
    country: 'BR'
  }
} : null;

let orderCreationStatus = 'not_requested';
const explicitConfirmationToCreate = confirmRegex.test(currentMessage)
  && (previousOrderCreationStatus === 'awaiting_confirmation' || previousOrderCreationStatus === 'create_failed' || previousOrderCreationStatus === 'ready_to_create')
  && previousMissingFields.length === 0
  && Boolean(previousProduct || selectedProduct);
if (orderActionRequested) {
  if (!supportContext.config.orderCreationEnabled) orderCreationStatus = 'disabled';
  else if (missingFields.length > 0) orderCreationStatus = 'needs_info';
  else if (explicitConfirmationToCreate) orderCreationStatus = 'ready_to_create';
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
      neighborhood: billingNeighborhood,
      bairro: billingNeighborhood,
      city: billingCity,
      state: billingState,
      postcode: billingPostcode,
      country: 'BR'
    },
    shipping: {
      first_name: supportContext.contactName || 'WhatsApp Customer',
      address_1: billingAddress1,
      address_2: billingNumber,
      city: billingCity,
      state: billingState,
      postcode: billingPostcode,
      country: 'BR'
    },
    line_items: [lineItem],
    customer_note: \`Created from Chatwoot conversation \${supportContext.conversationId}.\`,
    meta_data: [
      { key: '_chatwoot_conversation_id', value: String(supportContext.conversationId || '') },
      { key: '_chatwoot_contact_phone', value: String(supportContext.contactPhone || '') },
      { key: '_billing_cpf', value: billingCpf },
      { key: '_billing_address_1', value: billingAddress1 },
      { key: '_billing_number', value: billingNumber },
      { key: '_billing_neighborhood', value: billingNeighborhood },
      { key: '_billing_bairro', value: billingNeighborhood },
      { key: '_billing_city', value: billingCity },
      { key: '_billing_state', value: billingState },
      { key: '_billing_postcode', value: billingPostcode },
      { key: '_shipping_number', value: billingNumber },
      { key: '_shipping_neighborhood', value: billingNeighborhood },
      { key: '_shipping_bairro', value: billingNeighborhood }
    ]
  };
}
`,
  'order state block'
);

draftCode = replaceOrThrow(
  draftCode,
  String.raw`      variationOptions: variationOptions.length > 0 ? variationOptions : (!explicitNewOrderRequest ? previousVariationOptions : []),
      updatedAt: now
    };`,
  String.raw`      variationOptions: variationOptions.length > 0 ? variationOptions : (!explicitNewOrderRequest ? previousVariationOptions : []),
      orderReview,
      updatedAt: now
    };`,
  'persist orderReview'
);

draftCode = replaceOrThrow(
  draftCode,
  String.raw`  billingPostcode,
  quantity,
  product: selectedProduct,
  variationOptions,
  orderPayload
};`,
  String.raw`  billingPostcode,
  quantity,
  product: selectedProduct,
  variationOptions,
  orderReview,
  orderPayload
};`,
  'return orderReview'
);

draftNode.parameters.jsCode = draftCode;

const buildNode = data.nodes.find((node) => node.name === 'Build OpenAI Request3');
if (!buildNode) throw new Error('Build OpenAI Request3 not found');
let buildCode = buildNode.parameters.jsCode;

buildCode = replaceOrThrow(
  buildCode,
  String.raw`    billing_address_1: orderDraft.billingAddress1 || '',
    billing_number: orderDraft.billingNumber || '',
    billing_city: orderDraft.billingCity || '',
    billing_state: orderDraft.billingState || '',
    billing_postcode: orderDraft.billingPostcode || '',
    quantity: orderDraft.quantity || null,`,
  String.raw`    billing_address_1: orderDraft.billingAddress1 || '',
    billing_number: orderDraft.billingNumber || '',
    billing_neighborhood: orderDraft.billingNeighborhood || '',
    billing_city: orderDraft.billingCity || '',
    billing_state: orderDraft.billingState || '',
    billing_postcode: orderDraft.billingPostcode || '',
    quantity: orderDraft.quantity || null,`,
  'context billing neighborhood'
);

buildCode = replaceOrThrow(
  buildCode,
  String.raw`    variation_options: orderDraft.variationOptions ?? [],
    pay_url: orderPayUrl,`,
  String.raw`    variation_options: orderDraft.variationOptions ?? [],
    order_review: orderDraft.orderReview || null,
    pay_url: orderPayUrl,`,
  'context order review'
);

buildCode = replaceOrThrow(
  buildCode,
  String.raw`    billing_email: orderDraft.billingEmail || '',
    quantity: orderDraft.quantity || null,`,
  String.raw`    billing_email: orderDraft.billingEmail || '',
    billing_neighborhood: orderDraft.billingNeighborhood || '',
    quantity: orderDraft.quantity || null,`,
  'compact billing neighborhood'
);

buildCode = replaceOrThrow(
  buildCode,
  String.raw`    variation_options: (orderDraft.variationOptions ?? []).slice(0, 3).map((item) => ({
      title: truncateText(item.title || '', 120),
      variation_label: truncateText(item.variation_label || '', 80),
      effective_price: item.effective_price ?? item.price ?? null,
      product_url: item.product_url || ''
    })),
    pay_url: orderPayUrl,`,
  String.raw`    variation_options: (orderDraft.variationOptions ?? []).slice(0, 3).map((item) => ({
      title: truncateText(item.title || '', 120),
      variation_label: truncateText(item.variation_label || '', 80),
      effective_price: item.effective_price ?? item.price ?? null,
      product_url: item.product_url || ''
    })),
    order_review: orderDraft.orderReview ? {
      items: (orderDraft.orderReview.items || []).slice(0, 3).map((item) => ({
        display_name: truncateText(item.display_name || '', 120),
        quantity: item.quantity || null,
        unit_price: item.unit_price ?? null,
        line_total: item.line_total ?? null
      })),
      subtotal: orderDraft.orderReview.subtotal ?? null,
      shipping_cost: orderDraft.orderReview.shipping_cost ?? null,
      shipping_cost_known: Boolean(orderDraft.orderReview.shipping_cost_known),
      total_amount: orderDraft.orderReview.total_amount ?? null,
      total_amount_is_estimate: Boolean(orderDraft.orderReview.total_amount_is_estimate),
      delivery_address: orderDraft.orderReview.delivery_address || null
    } : null,
    pay_url: orderPayUrl,`,
  'compact order review'
);

buildCode = replaceOrThrow(
  buildCode,
  String.raw`  orderDraftBillingNumber: orderDraft.billingNumber || '',
  orderDraftBillingCity: orderDraft.billingCity || '',
  orderDraftBillingState: orderDraft.billingState || '',
  orderDraftBillingPostcode: orderDraft.billingPostcode || '',
  orderDraftQuantity: orderDraft.quantity || null,`,
  String.raw`  orderDraftBillingNumber: orderDraft.billingNumber || '',
  orderDraftBillingNeighborhood: orderDraft.billingNeighborhood || '',
  orderDraftBillingCity: orderDraft.billingCity || '',
  orderDraftBillingState: orderDraft.billingState || '',
  orderDraftBillingPostcode: orderDraft.billingPostcode || '',
  orderDraftQuantity: orderDraft.quantity || null,`,
  'return neighborhood'
);

buildCode = replaceOrThrow(
  buildCode,
  String.raw`  orderDraftProductTitle: orderDraft.product?.title || '',
  orderDraftProductUrl: orderDraft.product?.product_url || '',
  orderVariationOptions: orderDraft.variationOptions ?? [],
  orderPayUrl,`,
  String.raw`  orderDraftProductTitle: orderDraft.product?.title || '',
  orderDraftProductUrl: orderDraft.product?.product_url || '',
  orderVariationOptions: orderDraft.variationOptions ?? [],
  orderReview: orderDraft.orderReview || null,
  orderPayUrl,`,
  'return orderReview top level'
);

buildNode.parameters.jsCode = buildCode;

const replyNode = data.nodes.find((node) => node.name === 'Prepare Chatwoot Reply3');
if (!replyNode) throw new Error('Prepare Chatwoot Reply3 not found');
let replyCode = replyNode.parameters.jsCode;

replyCode = replaceBetweenOrThrow(
  replyCode,
  `const formatOptionLine = (option, index) => {`,
  `const orderStatus = String(requestContext.orderCreationStatus || '').trim();`,
  String.raw`const formatOptionLine = (option, index) => {
  const title = sanitizeTitle(option);
  const variationLabel = String(option?.variation_label || '').trim();
  const priceText = formatPrice(option);
  const parts = [title];
  if (variationLabel && variationLabel.toLowerCase() !== title.toLowerCase()) parts.push(variationLabel);
  let line = \`\${index + 1}. \${parts.join(' - ')}\`;
  if (priceText) line += \`: \${priceText}\`;
  return line;
};
const orderReview = requestContext.orderReview && typeof requestContext.orderReview === 'object' ? requestContext.orderReview : null;
const formatAddressSummary = (review) => {
  const address = review?.delivery_address || {};
  const lines = [];
  const firstLine = [address.address_1 || '', address.number || ''].filter(Boolean).join(', ');
  if (firstLine) lines.push(firstLine);
  if (address.neighborhood) lines.push(address.neighborhood);
  const cityState = [address.city || '', address.state || ''].filter(Boolean).join(' - ');
  if (cityState) lines.push(cityState);
  if (address.postcode) lines.push(address.postcode);
  return lines.join('\n');
};
const formatShippingSummary = (review) => {
  if (!review) return isPortuguese ? 'a calcular' : 'to be calculated';
  if (review.shipping_cost_known) {
    return review.shipping_cost === 0
      ? (isPortuguese ? 'Gratis' : 'Free')
      : (formatMoney(review.shipping_cost) || (isPortuguese ? 'a calcular' : 'to be calculated'));
  }
  return isPortuguese ? 'sera calculado na etapa de pagamento' : 'will be calculated at payment';
};
const buildConfirmationSummary = () => {
  if (!orderReview) return '';
  const itemLines = (Array.isArray(orderReview.items) ? orderReview.items : []).map((item, index) => {
    const name = sanitizeTitle({ title: item.display_name || item.title, product_url: item.product_url });
    const unitPrice = formatMoney(item.unit_price);
    const lineTotal = formatMoney(item.line_total);
    const qty = Number.isFinite(Number(item.quantity)) && Number(item.quantity) > 0 ? String(Number(item.quantity)) : orderQuantity;
    let text = \`\${index + 1}. \${name}\`;
    if (unitPrice) text += isPortuguese ? \`\n   Quantidade: \${qty} x \${unitPrice}\` : \`\n   Quantity: \${qty} x \${unitPrice}\`;
    if (lineTotal) text += isPortuguese ? \`\n   Total do item: \${lineTotal}\` : \`\n   Item total: \${lineTotal}\`;
    return text;
  });
  const subtotalText = formatMoney(orderReview.subtotal);
  const totalText = formatMoney(orderReview.total_amount);
  const shippingText = formatShippingSummary(orderReview);
  const addressText = formatAddressSummary(orderReview);
  const lines = [];
  lines.push(isPortuguese ? \`\${greeting} So para confirmar, este sera o seu pedido:\` : \`\${greeting} Just to confirm, this will be your order:\`);
  if (itemLines.length > 0) lines.push(itemLines.join('\n'));
  if (subtotalText) lines.push(isPortuguese ? \`Subtotal dos produtos: \${subtotalText}\` : \`Products subtotal: \${subtotalText}\`);
  lines.push(isPortuguese ? \`Frete: \${shippingText}\` : \`Shipping: \${shippingText}\`);
  if (totalText) {
    const totalLabel = orderReview.total_amount_is_estimate
      ? (isPortuguese ? 'Total estimado sem frete' : 'Estimated total without shipping')
      : (isPortuguese ? 'Total' : 'Total');
    lines.push(\`\${totalLabel}: \${totalText}\`);
  }
  if (orderEmail) lines.push(isPortuguese ? \`E-mail: \${orderEmail}\` : \`Email: \${orderEmail}\`);
  if (requestContext.orderDraftBillingCpf) lines.push(\`CPF: \${requestContext.orderDraftBillingCpf}\`);
  if (addressText) lines.push((isPortuguese ? 'Endereco de entrega:\n' : 'Delivery address:\n') + addressText);
  lines.push(isPortuguese
    ? 'Se estiver tudo certo, responda "confirmar" e eu criarei o pedido com o link de pagamento.'
    : 'If everything looks right, reply "confirm" and I will create the order and send the payment link.');
  return lines.join('\n\n');
};
`,
  'add confirmation helpers'
);

replyCode = replaceBetweenOrThrow(
  replyCode,
  `  } else if (orderStatus === 'awaiting_confirmation') {`,
  `  } else if (orderStatus === 'create_failed') {`,
  String.raw`  } else if (orderStatus === 'awaiting_confirmation') {
    reply = buildConfirmationSummary() || (isPortuguese
      ? \`\${greeting} Seu pedido de \${orderQuantity} unidade(s) de \${orderProductTitle}\${orderEmail ? \` com o e-mail \${orderEmail}\` : ''} esta pronto para ser criado. Responda "confirmar" para eu criar o pedido e enviar o link de pagamento.\`
      : \`\${greeting} Your order for \${orderQuantity} unit(s) of \${orderProductTitle}\${orderEmail ? \` with the email \${orderEmail}\` : ''} is ready to be created. Reply "confirm" and I will create the order and send the payment link.\`);
`,
  'awaiting_confirmation summary'
);

replyNode.parameters.jsCode = replyCode;

writeJson(basePath, data);
console.log('updated base workflow');

