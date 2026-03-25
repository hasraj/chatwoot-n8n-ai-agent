# Chatwoot n8n AI Agent

This repository now contains a safer phase-1 implementation for a Chatwoot + n8n + OpenAI + WooCommerce support agent.

The workflow in [workflow.json](./workflow.json) is designed to:

1. Receive `message_created` events from Chatwoot.
2. Ignore anything that is not a new incoming customer message.
3. Pull the conversation messages from Chatwoot so we can read the contact phone number, labels, and recent message history.
4. Run only for approved test contacts while `CHATWOOT_PROCESSING_MODE=test_only`.
5. Retrieve lightweight context from WooCommerce:
   - order lookup by detected order number
   - product lookup by a simple keyword search
6. Add FAQ snippets and recent chat context.
7. Ask OpenAI to draft a grounded reply.
8. Send the reply back to Chatwoot.

## What is implemented

This repo is now set up for a practical phase 1:

- Chatwoot webhook intake in n8n
- test-mode gating for your own phone number, labels, or inbox IDs
- direct WooCommerce order lookup
- direct WooCommerce product lookup
- lightweight FAQ / policy retrieval
- OpenAI response generation
- reply posting back into Chatwoot

This phase does **not** fully automate Woo order creation yet. That is intentional. Order creation from free-text customer messages is high-risk unless we first collect and confirm the required fields in a structured way.

## Recommended Chatwoot Test Strategy

For the live WhatsApp inbox, the safest first rollout is:

1. Keep the current production bot disconnected while testing this workflow.
2. Create a Chatwoot webhook that points to the n8n webhook URL.
3. Set `CHATWOOT_PROCESSING_MODE=test_only`.
4. Put only your own WhatsApp number in `CHATWOOT_ALLOWED_TEST_PHONES`.
5. Optionally add an `ai-test` label rule in Chatwoot and include that label in `CHATWOOT_ALLOWED_TEST_LABELS`.

Why this is safer:

- Account webhooks let us receive conversation events without forcing the whole inbox into bot mode.
- Chatwoot Agent Bots are inbox-level. If you attach one directly to the live inbox too early, all new conversations in that inbox can become bot-handled.

Later, once the workflow is stable, you can switch to:

- `CHATWOOT_PROCESSING_MODE=live`, or
- a dedicated test inbox with a Chatwoot Agent Bot, or
- an automation rule that only routes selected conversations into the bot flow.

## Configuration

Use [n8n.env.example](./n8n.env.example) as your starting point.

Required variables:

- `CHATWOOT_BASE_URL`
- `CHATWOOT_API_TOKEN`
- `CHATWOOT_ACCOUNT_ID`
- `WOOCOMMERCE_BASE_URL`
- `WOOCOMMERCE_CONSUMER_KEY`
- `WOOCOMMERCE_CONSUMER_SECRET`
- `OPENAI_API_KEY`

Important behavior flags:

- `CHATWOOT_PROCESSING_MODE`
  - `test_only`: only allowed test contacts/labels/inboxes trigger replies
  - `live`: all qualifying incoming customer messages can trigger replies
- `CHATWOOT_ALLOWED_TEST_PHONES`
  - comma-separated E.164 phone numbers such as `+8801XXXXXXXXX`
- `CHATWOOT_ALLOWED_TEST_LABELS`
  - comma-separated labels such as `ai-test`
- `CHATWOOT_ALLOWED_INBOX_IDS`
  - optional comma-separated Chatwoot inbox IDs
- `ENABLE_WOO_ORDER_CREATION`
  - currently kept `false`

## Workflow Notes

The workflow is intentionally simple and resilient:

- It responds to the webhook immediately, then continues processing in the background.
- It ignores outgoing messages, private notes, and non-customer events.
- It fetches conversation messages before replying so the workflow has:
  - contact phone number
  - labels
  - recent message history
- WooCommerce requests are configured to continue even if no order is found, so the bot can still answer from FAQ or ask a clarifying question.
- If OpenAI fails, the workflow falls back to a human-review reply.

## Setup

### 1. Import the workflow into n8n

Import [workflow.json](./workflow.json).

### 2. Set the environment variables in n8n

Use the values from [n8n.env.example](./n8n.env.example) and your real credentials.

### 3. Configure Chatwoot webhook

Point Chatwoot to:

```text
https://YOUR-N8N/webhook/chatwoot-ai-agent
```

### 4. Start in test mode

Use:

```text
CHATWOOT_PROCESSING_MODE=test_only
CHATWOOT_ALLOWED_TEST_PHONES=+YOUR_NUMBER
```

### 5. Send a WhatsApp test message from the approved number

The workflow should:

- receive the Chatwoot event
- fetch the conversation history
- confirm the phone number is allowed
- generate a reply
- send the reply into the same Chatwoot conversation

## Future Phase 2

Once the basic flow is stable, the next upgrade path should be:

1. Move FAQ and product knowledge into Postgres.
2. Add embeddings and semantic search for RAG.
3. Sync WooCommerce orders/products into a lightweight Postgres copy.
4. Add structured order-creation steps with explicit confirmation.
5. Add human-handoff actions and private-note summaries for agents.

## Helper Scripts

Scripts in [scripts](./scripts) use environment variables instead of hard-coded secrets:

- [scripts/test_chatwoot_api.py](./scripts/test_chatwoot_api.py)
- [scripts/test_woocommerce_api.py](./scripts/test_woocommerce_api.py)

Install dependencies:

```bash
pip install -r requirements.txt
```

Run the checks:

```bash
python scripts/test_chatwoot_api.py
python scripts/test_woocommerce_api.py
```

## Reference Files

- [workflow.json](./workflow.json): n8n workflow
- [faq.json](./faq.json): starter FAQ data
- [n8n.env.example](./n8n.env.example): environment variable template
