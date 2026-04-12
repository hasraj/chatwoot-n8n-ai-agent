const fs = require('fs');

const files = [
  'f:/github/chatwoot n8n ai agent/chatwoot-ai-product-search-and-order-create-final.json',
  'f:/github/chatwoot n8n ai agent/chatwoot-ai-main-agent-specialists.json',
  'f:/github/chatwoot n8n ai agent/chatwoot-ai-agent-hybrid.json',
];

for (const file of files) {
  const raw = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
  const data = JSON.parse(raw);
  let updatedNodes = 0;

  for (const node of data.nodes || []) {
    if (typeof node?.parameters?.jsCode !== 'string') continue;
    const fixed = node.parameters.jsCode.replace(/\\`/g, '`');
    if (fixed !== node.parameters.jsCode) {
      node.parameters.jsCode = fixed;
      updatedNodes += 1;
    }
  }

  fs.writeFileSync(file, JSON.stringify(data, null, 2));
  console.log(`${file} :: updatedNodes=${updatedNodes}`);
}
