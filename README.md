# Chatwoot n8n AI Agent

n8n workflow that connects **Chatwoot** (WhatsApp inbox) to **OpenAI** + **WooCommerce** + a custom shipping API, acting as a humanlike Brazilian Portuguese sales agent for [famivita.com.br](https://www.famivita.com.br).

The current production workflow lives in [`new version/`](./new%20version). Capabilities:

- Listens to Chatwoot `message_created` webhooks
- Pulls conversation history, WooCommerce catalog (Google Sheet), and any matching order
- Drafts a reply with OpenAI (JSON-structured output)
- Renders product cards with deterministic templates (price, stock, "Saiba mais", "Comprar agora")
- Calculates live shipping via a custom shipping API
- Creates WooCommerce orders end-to-end (PIX payment link returned in chat)
- Looks up existing order status
- **Hands off cancellation / refund / modification requests to a human agent** (Chatwoot private note + status toggle + email to ops)
- Remembers each customer's billing details across conversations (workflow static memory)

## Repo Layout

```
.
├── new version/                         ← active workflow (see below)
│   ├── Chatwoot_n8n_AI_Support_Agent_v1.json … v16.json   (older iteration history)
│   └── Chatwoot_n8n_AI_Support_Agent_YYYY-MM-DD_vN.json   (date-versioned, current)
├── workflow.json                        ← phase-1 starter (legacy, kept for reference)
├── faq.json, n8n.env.example            ← phase-1 supporting files
├── scripts/                             ← Python smoke tests + JS patchers from earlier iterations
├── AGENTS.md                            ← orientation for AI coding agents
└── README.md
```

## Active workflow (`new version/`)

The latest file in `new version/` is the one you want to import into n8n. As of **2026-05-11**, that's `Chatwoot_n8n_AI_Support_Agent_2026-05-11_v5.json`.

### Versioning convention

Each update creates a new file with **today's date** plus an incrementing `_vN`:

- First change of the day → `Chatwoot_n8n_AI_Support_Agent_YYYY-MM-DD_v1.json`
- Subsequent changes the same day → `_v2`, `_v3`, …
- On a new calendar day → reset to `_v1`

Older versions are kept on disk and in git so you can roll back instantly by re-importing a previous file.

### Setup

1. **Import the workflow.** In n8n: *Workflows → Import from File* → pick the latest `Chatwoot_n8n_AI_Support_Agent_YYYY-MM-DD_vN.json`.
2. **Attach credentials.** The HTTP nodes expect named credentials:
   - `chatwoot token` (Header Auth, `api_access_token: <YOUR_CHATWOOT_TOKEN>`)
   - WooCommerce REST credentials on `Maybe Lookup Order` and `Woo Create Order`
   - Google Sheets OAuth on `Get Catalog`
   - OpenAI on `OpenAI Reply`
   - **SMTP** on `Send Cancel Email` (for the cancellation handoff to ops)
3. **Point Chatwoot at the webhook.** Settings → Integrations → Webhooks → paste your n8n Webhook URL. Subscribe to `Message Created` (and optionally `Conversation Created`).
4. **Test with one phone first.** The workflow currently processes every incoming customer message; if you want test-only gating, wire it into `Should Process?`.

## Phase-1 starter (`workflow.json` at root)

The earlier proof-of-concept lives at the repo root. It implements a minimal Chatwoot → OpenAI → WooCommerce reply loop without order creation. Kept here for reference and rollback. If you're starting fresh, use `new version/` instead.

Required env vars for the phase-1 workflow:

- `CHATWOOT_BASE_URL`, `CHATWOOT_API_TOKEN`, `CHATWOOT_ACCOUNT_ID`
- `WOOCOMMERCE_BASE_URL`, `WOOCOMMERCE_CONSUMER_KEY`, `WOOCOMMERCE_CONSUMER_SECRET`
- `OPENAI_API_KEY`
- `CHATWOOT_PROCESSING_MODE` (`test_only` or `live`)
- `CHATWOOT_ALLOWED_TEST_PHONES`, `CHATWOOT_ALLOWED_TEST_LABELS`, `CHATWOOT_ALLOWED_INBOX_IDS`

See [`n8n.env.example`](./n8n.env.example).

## Helper scripts

```bash
pip install -r requirements.txt
python scripts/test_chatwoot_api.py
python scripts/test_woocommerce_api.py
```

## For AI coding agents

If you're an AI agent (Codex, Claude Code, Cursor, etc.) about to edit this repo, read [`AGENTS.md`](./AGENTS.md) first — it covers the workflow's node-by-node architecture, the editing pattern for `jsCode` strings inside the JSON, the versioning rule, validation commands, and known fragile areas.
