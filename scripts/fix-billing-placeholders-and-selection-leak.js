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
    `const currentEmail = extractLastEmail([rawCurrentMessage]);
const currentBillingCpf = extractBillingCpf(rawCurrentMessage);
const currentBillingAddress1 = extractBillingAddress1(rawCurrentMessage) || multilineBilling.address1;
const currentBillingNumber = extractBillingNumber(rawCurrentMessage) || multilineBilling.number;
const currentBillingNeighborhood = extractBillingNeighborhood(rawCurrentMessage) || multilineBilling.neighborhood;
const currentBillingCity = extractBillingCity(rawCurrentMessage) || multilineBilling.city;
const currentBillingState = extractBillingState(rawCurrentMessage) || multilineBilling.state;
const currentBillingPostcode = extractBillingPostcode(rawCurrentMessage) || multilineBilling.postcode;
const currentQuantity = extractQuantity(currentMessage);
const normalizedCurrentMessage = normalizeText(currentMessage);
const currentMeasureTokens = extractMeasureTokens(currentMessage);`,
    `const normalizedCurrentMessage = normalizeText(currentMessage);
const currentMeasureTokens = extractMeasureTokens(currentMessage);
const explicitBillingFieldRegex = /\\b(?:cpf|email|number|numero|cidade|city|estado|state|uf|postcode|cep|zip|address|delivery address|shipping address|billing address|endereco|endere\\u00e7o|bairro|neighborhood)\\b/i;
const explicitSelectionMessageRegex = /\\b(?:need|want|choose|pick|select|quero|preciso|escolho|seleciono)\\b.{0,20}\\b(?:this|that|one|option|opcao|op\\u00e7\\u00e3o|esse|essa|este|esta|ultimo|ultima|last(?: one| option)?)\\b/i;
const numericOptionSelectionRegex = /\\b(?:option|opcao|op\\u00e7\\u00e3o)\\s*\\d+\\b/i;
const currentMessageLooksLikePureProductSelection = Boolean(
  !/@/.test(rawCurrentMessage) &&
  !explicitBillingFieldRegex.test(rawCurrentMessage) &&
  (
    explicitSelectionMessageRegex.test(normalizedCurrentMessage) ||
    numericOptionSelectionRegex.test(normalizedCurrentMessage)
  )
);
const rawCurrentEmail = extractLastEmail([rawCurrentMessage]);
const rawCurrentBillingCpf = extractBillingCpf(rawCurrentMessage);
const rawCurrentBillingAddress1 = extractBillingAddress1(rawCurrentMessage) || multilineBilling.address1;
const rawCurrentBillingNumber = extractBillingNumber(rawCurrentMessage) || multilineBilling.number;
const rawCurrentBillingNeighborhood = extractBillingNeighborhood(rawCurrentMessage) || multilineBilling.neighborhood;
const rawCurrentBillingCity = extractBillingCity(rawCurrentMessage) || multilineBilling.city;
const rawCurrentBillingState = extractBillingState(rawCurrentMessage) || multilineBilling.state;
const rawCurrentBillingPostcode = extractBillingPostcode(rawCurrentMessage) || multilineBilling.postcode;
const currentEmail = currentMessageLooksLikePureProductSelection ? '' : rawCurrentEmail;
const currentBillingCpf = currentMessageLooksLikePureProductSelection ? '' : rawCurrentBillingCpf;
const currentBillingAddress1 = currentMessageLooksLikePureProductSelection ? '' : rawCurrentBillingAddress1;
const currentBillingNumber = currentMessageLooksLikePureProductSelection ? '' : rawCurrentBillingNumber;
const currentBillingNeighborhood = currentMessageLooksLikePureProductSelection ? '' : rawCurrentBillingNeighborhood;
const currentBillingCity = currentMessageLooksLikePureProductSelection ? '' : rawCurrentBillingCity;
const currentBillingState = currentMessageLooksLikePureProductSelection ? '' : rawCurrentBillingState;
const currentBillingPostcode = currentMessageLooksLikePureProductSelection ? '' : rawCurrentBillingPostcode;
const currentQuantity = extractQuantity(currentMessage);`,
    `${fileName} billing extraction block`
  );

  const replyNode = workflow.nodes.find((node) =>
    node.name === 'Package Main Agent Reply3' ||
    node.name === 'Prepare Chatwoot Reply3'
  );
  if (!replyNode) throw new Error(`Reply formatting node not found in ${fileName}`);

  replyNode.parameters.jsCode = replaceOrThrow(
    replyNode.parameters.jsCode,
    `const example = isPortuguese
        ? 'Envie assim:\\nCPF: 048.532.001-00\\nEndereco: Rua Exemplo\\nNumero: 123\\nCidade: Sao Paulo\\nEstado: SP\\nCEP: 50070-130'
        : 'Please send them like this:\\nCPF: 048.532.001-00\\nAddress: Example Street\\nNumber: 123\\nCity: Sao Paulo\\nState: SP\\nPostcode: 50070-130';`,
    `const example = isPortuguese
        ? 'Envie assim:\\nCPF: ###.###.###-##\\nEndereco: Rua Exemplo\\nNumero: ##\\nCidade: Sao Paulo\\nEstado: SP\\nCEP: #####-###'
        : 'Please send them like this:\\nCPF: ###.###.###-##\\nAddress: Example Street\\nNumber: ##\\nCity: Sao Paulo\\nState: SP\\nPostcode: #####-###';`,
    `${fileName} billing example block`
  );

  fs.writeFileSync(filePath, JSON.stringify(workflow, null, 2) + '\n', 'utf8');
  console.log(`Patched ${fileName}`);
}
