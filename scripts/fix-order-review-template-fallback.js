const fs = require('fs');

const files = [
  'f:/github/chatwoot n8n ai agent/chatwoot-ai-product-search-and-order-create-final.json',
  'f:/github/chatwoot n8n ai agent/chatwoot-ai-main-agent-specialists.json',
  'f:/github/chatwoot n8n ai agent/chatwoot-ai-agent-hybrid.json',
];

const brokenBlock = [
  "  } else if (orderStatus === 'awaiting_confirmation') {",
  "    reply = buildConfirmationSummary() || (isPortuguese",
  "      ? `\\${greeting} Seu pedido de \\${orderQuantity} unidade(s) de \\${orderProductTitle}\\${orderEmail ? ` com o e-mail \\${orderEmail}` : ''} esta pronto para ser criado. Responda \"confirmar\" para eu criar o pedido e enviar o link de pagamento.`",
  "      : `\\${greeting} Your order for \\${orderQuantity} unit(s) of \\${orderProductTitle}\\${orderEmail ? ` with the email \\${orderEmail}` : ''} is ready to be created. Reply \"confirm\" and I will create the order and send the payment link.`);",
].join('\n');

const fixedBlock = [
  "  } else if (orderStatus === 'awaiting_confirmation') {",
  "    const emailSuffix = orderEmail ? (isPortuguese ? ` com o e-mail ${orderEmail}` : ` with the email ${orderEmail}`) : '';",
  "    reply = buildConfirmationSummary() || (isPortuguese",
  "      ? `${greeting} Seu pedido de ${orderQuantity} unidade(s) de ${orderProductTitle}${emailSuffix} esta pronto para ser criado. Responda \"confirmar\" para eu criar o pedido e enviar o link de pagamento.`",
  "      : `${greeting} Your order for ${orderQuantity} unit(s) of ${orderProductTitle}${emailSuffix} is ready to be created. Reply \"confirm\" and I will create the order and send the payment link.`);",
].join('\n');

for (const file of files) {
  const raw = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
  const data = JSON.parse(raw);
  let updatedNodes = 0;

  for (const node of data.nodes || []) {
    if (typeof node?.parameters?.jsCode !== 'string') continue;
    if (!node.parameters.jsCode.includes(brokenBlock)) continue;
    node.parameters.jsCode = node.parameters.jsCode.replace(brokenBlock, fixedBlock);
    updatedNodes += 1;
  }

  fs.writeFileSync(file, JSON.stringify(data, null, 2));
  console.log(`${file} :: updatedNodes=${updatedNodes}`);
}
