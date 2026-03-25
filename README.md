# Chatwoot n8n AI Agent

This project implements an AI-powered customer support agent that integrates Chatwoot, n8n, OpenAI, and WooCommerce. The system uses a Retrieval-Augmented Generation (RAG) approach to provide accurate, context-aware responses to customer inquiries.

## Overview

The AI agent workflow:
1. Customer sends a message via Chatwoot (e.g., WhatsApp)
2. Chatwoot triggers an n8n webhook with the message
3. n8n AI Agent node evaluates the message and retrieves relevant data using tools:
   - Product lookup via WooCommerce API
   - Order status lookup via WooCommerce API
   - FAQ lookup from knowledge base
   - Order creation via WooCommerce API
4. Retrieved data is sent to OpenAI for response generation
5. Generated response is sent back to Chatwoot

## Components

- **Chatwoot**: Customer communication platform
- **n8n**: Workflow automation tool
- **OpenAI**: Language model for response generation
- **WooCommerce**: E-commerce platform for product/order data

## Setup Instructions

### Prerequisites
- Chatwoot instance
- n8n instance
- OpenAI API key
- WooCommerce store with API access
- Postgres database (for FAQ and future optimizations)

### Chatwoot Setup
1. Create a test agent in Chatwoot
2. Set up inbox rules to route test messages (from developer's phone) to the test agent
3. Configure webhook to trigger n8n on new messages
4. Deactivate existing bot during testing

### n8n Setup
1. Import the workflow from `workflow.json`
2. Configure credentials:
   - OpenAI API key
   - WooCommerce API credentials
   - Chatwoot API credentials
3. Set up webhook URL in Chatwoot

### Testing
- Use developer's phone number for test messages
- Verify message routing through inbox rules
- Test various scenarios: product questions, order status, FAQ, order creation

### API Testing Scripts
Run the test scripts to verify API connections:

```bash
# Install dependencies
pip install -r requirements.txt

# Test WooCommerce API
python scripts/test_woocommerce_api.py

# Test Chatwoot API
python scripts/test_chatwoot_api.py
```

Update the configuration variables in the scripts with your actual API credentials.

## Files
- `README.md`: This file
- `workflow.json`: n8n workflow configuration
- `faq.json`: Sample FAQ knowledge base
- `scripts/`: Utility scripts for testing and setup

## Development Notes
- Start with WooCommerce API direct access
- Later optimize with Postgres sync for better performance
- Implement RAG for accurate responses
- Add more tools as needed (returns, promotions, etc.)

## Resources
- [Chatwoot Documentation](https://www.chatwoot.com/docs)
- [n8n Documentation](https://docs.n8n.io/)
- [WooCommerce REST API](https://woocommerce.github.io/woocommerce-rest-api-docs/)
- [OpenAI API](https://platform.openai.com/docs)</content>
<parameter name="filePath">F:/github/chatwoot n8n ai agent/README.md