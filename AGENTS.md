# AGENTS.md

Orientation for AI coding agents (Codex, Claude Code, Cursor, etc.) working in this repo.

## What this repo is

An n8n workflow JSON that wires Chatwoot (WhatsApp) ↔ OpenAI ↔ WooCommerce ↔ a custom shipping API into a Brazilian-Portuguese sales agent for famivita.com.br. The agent shows products, takes orders end-to-end (preview → PIX payment link), looks up order status, and hands off cancellations to a human.

**The "code" is JavaScript embedded inside n8n Code nodes.** There is no app to build or test runner to run — you edit `.jsCode` strings inside one big JSON file.

## Where to work

```
new version/
  Chatwoot_n8n_AI_Support_Agent_YYYY-MM-DD_vN.json   ← active workflow
  Chatwoot_n8n_AI_Support_Agent_v1.json … v16.json    ← historical
```

Pick the **highest date + highest `_vN`** in `new version/`. That's the current file. Older files are kept for rollback — do not edit them.

The repo root has a `workflow.json` (phase-1 starter). Ignore it unless the user explicitly asks for phase-1 work.

## Versioning rule (strict — user enforces this)

Every change creates a **new file**. Never edit the latest version in place.

- First change today → copy latest → `Chatwoot_n8n_AI_Support_Agent_YYYY-MM-DD_v1.json`
- Next change today → `_v2`, then `_v3`, …
- New calendar day → reset to `_v1`
- Update the JSON's top-level `"name"` field to match the filename (n8n imports it as a new workflow rather than overwriting).

```bash
cp "new version/Chatwoot_n8n_AI_Support_Agent_$(LATEST).json" \
   "new version/Chatwoot_n8n_AI_Support_Agent_$(date -u +%F)_vN.json"
```

Today's date in `currentDate` system context is the authoritative date — use it.

## Workflow architecture (current node graph)

Linear path with three branches off `Parse AI Response` and one off `Plain Reply Pass-through`:

```
Webhook
  → Normalize Event
  → Should Process?              (IF: gates on incoming customer messages)
  → Get Conversation             (HTTP: Chatwoot)
  → Get Catalog                  (Google Sheets: WooCommerce product mirror)
  → Maybe Lookup Order           (HTTP: Woo — by order ID if mentioned)
  → Build AI Request             (Code: assembles system prompt + history)
  → OpenAI Reply                 (HTTP: chat.completions, JSON response)
  → Parse AI Response            (Code: validates + decides resolvedAction)
       ├─ Need Shipping Calc? (IF=calculate_shipping)
       │     → Build Shipping Request → Get Shipping Quote → Fill Preview → Send Reply
       └─ Create Order? (IF=create_order)
             → Build Order Shipping Request → Get Order Shipping Quote
             → Resolve Order Shipping → Build Order Payload → Woo Create Order
             → Build Order Confirmation → Send Reply
       └─ (else) Plain Reply Pass-through
             → Send Reply                           ← user-facing reply
             ↘ Cancel Handoff? (IF: isCancelOrModify)
                  → Build Cancel Handoff
                  → Set Conversation Open           (Chatwoot toggle_status=open)
                  → Post Private Note               (private message to agents)
                  → Send Cancel Email               (SMTP → ops mailbox)
```

### Key Code nodes (where most logic lives)

| Node | What it does |
|---|---|
| `Normalize Event` | Extracts `accountId`, `conversationId`, sender info, builds the `config` object. |
| `Build AI Request` | Builds the **system prompt** (Portuguese, sales-agent persona, rules, schema) and bundles catalog/order/billing memory for OpenAI. The prompt is the most important place for behavior changes. |
| `Parse AI Response` | Validates the AI's JSON. Renders `{PRODUCTS}` blocks deterministically. Appends the order-via-WhatsApp footer. Runs **billing extractors** (regex) on prior user messages. Computes `resolvedAction`. Hosts the **auto-advance** logic, **status-query** detection, and **cancel-or-modify** detection. |
| `Fill Preview` | Renders the shipping preview (Itens / Entrega / Frete / Resumo). |
| `Resolve Order Shipping` + `Build Order Payload` + `Build Order Confirmation` | Order creation: pick shipping method, build Woo REST payload, render the success message with payment URL. Also writes `billing memory` into the workflow's static data (used to skip asking for address next time). |
| `Build Cancel Handoff` | Composes the private-note content and the ops email body when a cancellation request is detected. |

### Important guard rails inside `Parse AI Response`

These exist because the AI used to make specific mistakes — do not remove without understanding:

- **`{PRODUCTS}` substitution** pads with `\n\n` and collapses 3+ newlines, so the AI intro and product cards never butt together.
- **Order-reference scrub** strips `"order number X"`, `"pedido número X"`, `"pedido #X"` from the text before billing extractors run. Without this, "my order number: 1346290" would set `billing_number = 1346290`.
- **`isStatusQuery` gate** prevents `"my order details: 1346297"` from being mistaken for an order intent and force-promoted to `calculate_shipping`.
- **`isCancelOrModify` gate** does the same for cancel/refund/modify messages.
- **Variation guardrail** keeps order items locked to the active variation when the AI tries to substitute a different one in the same product family.
- **Preview-change detection** forces a fresh `calculate_shipping` if billing fields changed since the last preview shown.

## Editing pattern

The workflow file is JSON. Each Code node has a `parameters.jsCode` field which is a JS-source string with `\n` line breaks and `\\` escaped backslashes (for regex literals etc).

### To make a small, targeted change

Use the `Edit` tool with an `old_string` / `new_string` that captures unique context. Inside a `jsCode` string, your `old_string` looks like JS but with `\n` for newlines and `\\` doubled for any regex backslash. Example:

```
old: 'Me diga a *opção 1, 2, 3...* (ou o nome do produto)'
new: 'Me diga a *' + optionHint + '* (ou o nome do produto)'
```

### To make multiple coordinated changes to one node

Write a small Node.js patcher script, run it, then delete it:

```js
// .apply-vN-fix.js
const fs = require('fs');
const wf = JSON.parse(fs.readFileSync('new version/Chatwoot_n8n_AI_Support_Agent_YYYY-MM-DD_vN.json','utf8'));
wf.name = 'Chatwoot n8n AI support Agent YYYY-MM-DD vN';
const node = wf.nodes.find(n => n.name === 'Parse AI Response');
node.parameters.jsCode = node.parameters.jsCode.replace(/foo/g, 'bar');
fs.writeFileSync('new version/Chatwoot_n8n_AI_Support_Agent_YYYY-MM-DD_vN.json', JSON.stringify(wf, null, 2));
```

Patcher scripts must be deleted after running — they're not part of the repo.

### To add a new node

You can hand-edit the JSON (`nodes[]` array + `connections{}` map), but it's faster to do this in the n8n UI and then re-export. If you must do it in JSON:

- Each node needs `parameters`, `type`, `typeVersion`, `position` (`[x, y]`), `id` (UUID v4), `name`, and optionally `credentials`.
- `connections[<from>]["main"]` is an array of arrays: outer index = output port, inner = list of target nodes.
- Copy the structure of a similar existing node rather than constructing from scratch.

## Validation

After every change, before reporting success:

```bash
node -e "JSON.parse(require('fs').readFileSync('new version/Chatwoot_n8n_AI_Support_Agent_YYYY-MM-DD_vN.json','utf8')); console.log('JSON valid')"
```

For regex changes, simulate against representative cases:

```bash
node -e "
const RX = /your-regex-here/i;
const tests = [['some user message', /*expected*/ true], ['other', false]];
let ok = 0;
for (const [t, expected] of tests) {
  const got = RX.test(t.toLowerCase());
  console.log((got === expected ? 'OK  ' : 'FAIL') + '  expected=' + expected + ' got=' + got + '  ' + JSON.stringify(t));
  if (got === expected) ok++;
}
console.log('Passed:', ok, '/', tests.length);
"
```

Do **not** import into n8n yourself. The user will re-import and test in their live n8n instance — your job ends at JSON-valid + simulation passes.

## Commit conventions

The repo uses short imperative commit titles + a body explaining each file in the changeset. The user signs off when ready ("update to git" / "yes" to push). Style:

```
Fix product list spacing, dynamic option hint, and order-status routing

- v16: <what changed in v16>
- 2026-05-11_v1: <what _v1 adds>
- 2026-05-11_v2: <what _v2 adds>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

Stage **only** the files you actually changed. The parent dir has many untracked legacy files (`.tmp_*.js`, `Test-hybrid model_*.json`, `scripts/patch-*.js`); leave them alone. Push only when the user says so.

## Things the workflow CANNOT do (don't let the AI claim otherwise)

If the user asks you to wire up any of these, you'll need to add nodes — don't just update the prompt:

- **Cancel a WooCommerce order** — currently routes to a human via private note + email. There is no `cancel_order` action.
- **Edit a created order** (change items, address) — same as above.
- **Issue a refund** — same.
- **Send a transactional email to the customer** — only the cancellation handoff email exists, and it goes to ops, not the customer.
- **Look up tracking / shipment status** beyond what's in the WooCommerce order record.

The `action_after` enum in the prompt and in `Parse AI Response` is the authoritative list: `"none" | "calculate_shipping" | "create_order"`. If you add a new action, you must:
1. Add the keyword to the AI prompt's "ESQUEMA JSON DE SAÍDA" section
2. Add a branch in `resolvedAction` validation (`Parse AI Response`)
3. Add a routing IF node + downstream HTTP/Code nodes
4. Verify the AI doesn't trigger it unsafely (write regex gate if needed)

## Language

The customer-facing language is **Brazilian Portuguese (PT-BR)**. The system prompt enforces this. Do not introduce English customer-facing strings. Internal-only strings (private notes, ops emails, logs) can be in English if the user prefers — ask.

## When in doubt

- Read the latest version's `Parse AI Response.jsCode` end-to-end before changing it. It's long but linear.
- Search the JSON for the exact string you want to change — most user-visible text appears once.
- Confirm the change with `JSON.parse` and a simulation, then summarize the diff to the user, then ask before committing.
- Never `git push` without explicit confirmation.
