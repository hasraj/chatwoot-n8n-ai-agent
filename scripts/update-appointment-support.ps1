$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$workflowPath = Join-Path $repoRoot 'workflow.json'

$workflow = Get-Content -Raw $workflowPath | ConvertFrom-Json -Depth 100

function Get-Node {
  param(
    [Parameter(Mandatory)]
    [string]$Name
  )

  $node = $workflow.nodes | Where-Object name -eq $Name | Select-Object -First 1
  if (-not $node) {
    throw "Node not found: $Name"
  }

  return $node
}

function Remove-Node {
  param(
    [Parameter(Mandatory)]
    [string]$Name
  )

  $workflow.nodes = @($workflow.nodes | Where-Object name -ne $Name)
}

function Add-OrReplace-Connection {
  param(
    [Parameter(Mandatory)]
    [string]$Name,
    [Parameter(Mandatory)]
    [object]$Value
  )

  $workflow.connections | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

$gateTestContactCode = @'
const event = $('Normalize Incoming Event').first().json;
const messageList = $input.first().json;

const normalizePhone = (value) => String(value || '').replace(/[^+\d]/g, '');
const stripHtml = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const normalizeText = (value) => String(value || '')
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .toLowerCase();
const parseNumber = (value) => {
  const cleaned = String(value || '').replace(/[^0-9,.\-]/g, '').trim();
  if (!cleaned) {
    return null;
  }

  const normalized = cleaned.includes(',') && cleaned.includes('.')
    ? cleaned.replace(/\./g, '').replace(',', '.')
    : cleaned.replace(',', '.');
  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : null;
};
const extractFirstEmail = (value) => {
  const match = String(value || '').match(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i);
  return match ? match[0].toLowerCase() : '';
};
const extractLookupId = (value, patterns) => {
  const text = String(value || '');
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match?.[1]) {
      return match[1];
    }
  }
  return '';
};

const contactPayload = messageList.meta?.contact?.payload;
const contact = Array.isArray(contactPayload)
  ? (contactPayload[0] ?? {})
  : (messageList.meta?.contact ?? {});
const labels = Array.isArray(messageList.meta?.labels) ? messageList.meta.labels : [];
const phoneNumber = normalizePhone(contact.phone_number ?? '');
const allowedPhones = event.config.allowedPhoneNumbers.map(normalizePhone);
const allowedLabels = event.config.allowedLabels.map((label) => label.toLowerCase());
const allowedInboxIds = event.config.allowedInboxIds.map((id) => String(id));
const inboxId = String(event.inboxId ?? '');

const phoneAllowed = allowedPhones.length > 0 && allowedPhones.includes(phoneNumber);
const labelAllowed = labels.some((label) => allowedLabels.includes(String(label).toLowerCase()));
const inboxAllowed = allowedInboxIds.length > 0 && allowedInboxIds.includes(inboxId);
const liveMode = event.config.processingMode === 'live';

const route = liveMode || phoneAllowed || labelAllowed || inboxAllowed ? 'run' : 'skip';
const gateReason = liveMode
  ? 'live_mode'
  : phoneAllowed
    ? 'phone_allowlist'
    : labelAllowed
      ? 'label_allowlist'
      : inboxAllowed
        ? 'inbox_allowlist'
        : 'blocked_in_test_mode';

const knowledgeBase = [
  {
    topic: 'shipping',
    keywords: ['ship', 'shipping', 'delivery'],
    answer: 'We offer free shipping on orders over $50. Standard delivery takes 3-5 business days.'
  },
  {
    topic: 'returns',
    keywords: ['return', 'refund', 'exchange'],
    answer: 'You can return items within 30 days of purchase if they are unused and in their original packaging.'
  },
  {
    topic: 'payment',
    keywords: ['payment', 'pay', 'card', 'bank transfer'],
    answer: 'We accept Visa, Mastercard, PayPal, and bank transfers.'
  },
  {
    topic: 'tracking',
    keywords: ['track', 'tracking', 'where is my order', 'where order'],
    answer: 'You can track your order using the tracking number from your shipping confirmation message.'
  },
  {
    topic: 'contact',
    keywords: ['support', 'human', 'agent', 'contact'],
    answer: 'You can contact our support team at ' + event.config.supportEmail + '.'
  }
];

const lowerMessage = event.content.toLowerCase();
const faqMatches = knowledgeBase
  .filter((entry) => entry.keywords.some((keyword) => lowerMessage.includes(keyword)))
  .map(({ topic, answer }) => ({ topic, answer }))
  .slice(0, 3);

const stopWords = new Set([
  'the', 'and', 'for', 'with', 'this', 'that', 'have', 'from', 'what', 'your', 'about', 'please', 'need', 'want',
  'know', 'tell', 'price', 'stock', 'order', 'where', 'when', 'does', 'will', 'show', 'much', 'how', 'can',
  'you', 'me', 'our', 'get', 'buy', 'make', 'create', 'status', 'hello', 'hi', 'product', 'products', 'item',
  'items', 'produto', 'produtos', 'quero', 'preciso', 'gostaria', 'sobre', 'tenho', 'tem', 'uma', 'um',
  'support', 'human', 'agent', 'contact', 'return', 'refund', 'exchange', 'shipping', 'delivery', 'payment',
  'track', 'tracking', 'pedido', 'pedidos', 'email', 'mail', 'rastreio', 'rastrear', 'acompanhar',
  'appointment', 'appointments', 'booking', 'bookings', 'reservation', 'reserva', 'reservas', 'consulta', 'consultas',
  'agendamento', 'agendamentos', 'below', 'under', 'less', 'than', 'above', 'over', 'between', 'which', 'cheap',
  'cheaper', 'cheapest', 'abaixo', 'menor', 'acima', 'maior', 'entre', 'ate', 'ate', 'ate'
]);

const normalizedContent = normalizeText(event.content)
  .replace(/order\s*#?\s*\d+/gi, ' ')
  .replace(/(?:appointment|booking|reservation|reserva|agendamento|consulta)\s*#?\s*\d+/gi, ' ')
  .replace(/[^a-z0-9\s-]/g, ' ');

const productSearchTokens = [...new Set(
  normalizedContent
    .split(/\s+/)
    .filter((word) => word && word.length > 2 && !stopWords.has(word) && !/^\d+$/.test(word))
)]
  .sort((left, right) => right.length - left.length || left.localeCompare(right))
  .slice(0, 4);

const productSearchTerm = productSearchTokens.join(' ');
const emailAddress = extractFirstEmail(event.content);
const hasEmailAddress = Boolean(emailAddress);
const appointmentLookupId = extractLookupId(event.content, [
  /(?:appointment|booking|reservation|reserve|reserva|agendamento|consulta|exam|exame|booking id|appointment id)\s*#?\s*(\d{3,})/i,
  /(?:appt|agend)\s*#?\s*(\d{3,})/i
]);
const explicitOrderLookupId = extractLookupId(event.content, [
  /(?:order|pedido)\s*#?\s*(\d{4,})/i
]);
const appointmentSupportRequested = Boolean(
  appointmentLookupId ||
  /(appointment|booking|reservation|reserva|agendamento|consulta|exam|exame|reschedule|cancel my appointment|my appointment|minha consulta|minha reserva|meu agendamento)/i.test(event.content)
);
const orderLookupId = explicitOrderLookupId || (appointmentSupportRequested ? '' : event.detectedOrderId);
const orderSupportRequested = Boolean(
  orderLookupId ||
  /(where\s+is\s+my\s+order|track(?:ing)?|order\s+status|status\s+of\s+my\s+order|my\s+order|pedido|rastreio|rastrear|acompanhar|status do pedido|meu pedido)/i.test(event.content) ||
  (!appointmentSupportRequested && hasEmailAddress)
);

const normalizedIntentText = normalizeText(event.content);
const priceFilter = { requested: false, min: null, max: null };
const betweenMatch = normalizedIntentText.match(/\b(?:between|entre)\s*(\d+(?:[.,]\d+)?)\s*(?:and|e)\s*(\d+(?:[.,]\d+)?)/);
const belowMatch = normalizedIntentText.match(/\b(?:below|under|less than|abaixo de|menor que|ate|ate)\s*(\d+(?:[.,]\d+)?)/);
const aboveMatch = normalizedIntentText.match(/\b(?:above|over|more than|acima de|maior que)\s*(\d+(?:[.,]\d+)?)/);

if (betweenMatch) {
  const firstValue = parseNumber(betweenMatch[1]);
  const secondValue = parseNumber(betweenMatch[2]);
  if (firstValue !== null && secondValue !== null) {
    priceFilter.requested = true;
    priceFilter.min = Math.min(firstValue, secondValue);
    priceFilter.max = Math.max(firstValue, secondValue);
  }
} else if (belowMatch) {
  const maxValue = parseNumber(belowMatch[1]);
  if (maxValue !== null) {
    priceFilter.requested = true;
    priceFilter.max = maxValue;
  }
} else if (aboveMatch) {
  const minValue = parseNumber(aboveMatch[1]);
  if (minValue !== null) {
    priceFilter.requested = true;
    priceFilter.min = minValue;
  }
}

const productLookupRequested = !orderSupportRequested && !appointmentSupportRequested && (productSearchTokens.length > 0 || priceFilter.requested);

const recentMessages = (Array.isArray(messageList.payload) ? messageList.payload : [])
  .filter((message) => !message.private && String(message.content || '').trim())
  .slice(-event.config.maxConversationMessages)
  .map((message) => ({
    role: message.sender_type === 'contact' || message.message_type === 0 ? 'customer' : 'agent',
    content: stripHtml(message.content),
    created_at: message.created_at
  }));

const createOrderRequested = /(create|place|buy|purchase).{0,20}order|order.{0,20}(create|place|buy|purchase)/i.test(event.content);

return {
  route,
  gateReason,
  accountId: event.accountId,
  conversationId: event.conversationId,
  inboxId: event.inboxId,
  content: event.content,
  orderLookupId,
  appointmentLookupId,
  appointmentSupportRequested,
  productSearchTerm,
  productSearchTokens,
  productLookupRequested,
  orderSupportRequested,
  emailAddress,
  hasEmailAddress,
  priceFilter,
  createOrderRequested,
  contactName: contact.name ?? '',
  contactPhone: phoneNumber,
  labels,
  faqMatches,
  recentMessages,
  config: event.config
};
'@

$buildOpenAiRequestCode = @'
const supportContext = $('Gate Test Contact').first().json;
const directOrderResponse = $('Woo Order Lookup').first().json ?? {};
const appointmentV3Response = $('Woo Appointment Lookup v3').first().json ?? {};
const appointmentLegacyResponse = $('Woo Appointment Lookup Legacy').first().json ?? {};
const appointmentOrderResponse = $('Woo Appointment Order Lookup').first().json ?? {};
const productResponse = $('Sort Product Matches').first().json ?? {};

const stripText = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const normalizeEmail = (value) => String(value || '').trim().toLowerCase();
const summarizeOrder = (response, source) => {
  const body = response.body ?? {};
  if (response.statusCode !== 200 || !body.id) {
    return null;
  }

  return {
    source,
    id: body.id,
    status: body.status,
    currency: body.currency,
    total: body.total,
    date_created: body.date_created,
    billing_email: body.billing?.email,
    billing_phone: body.billing?.phone,
    line_items: Array.isArray(body.line_items)
      ? body.line_items.map((item) => ({
          product_id: item.product_id,
          name: item.name,
          quantity: item.quantity,
          total: item.total
        }))
      : []
  };
};
const pickAppointmentResponse = () => {
  const v3Body = appointmentV3Response.body ?? {};
  if (appointmentV3Response.statusCode === 200 && v3Body.id) {
    return { response: appointmentV3Response, body: v3Body, source: 'wc/v3' };
  }

  const legacyBody = appointmentLegacyResponse.body ?? {};
  if (appointmentLegacyResponse.statusCode === 200 && legacyBody.id) {
    return { response: appointmentLegacyResponse, body: legacyBody, source: 'wc-appointments/v1' };
  }

  return { response: null, body: {}, source: null };
};

const directOrderSummary = summarizeOrder(directOrderResponse, 'message_order_id');
const appointmentOrderSummary = summarizeOrder(appointmentOrderResponse, 'appointment_order_id');
const orderSummary = directOrderSummary ?? appointmentOrderSummary;

const appointmentResult = pickAppointmentResponse();
const appointmentBody = appointmentResult.body ?? {};
const appointmentSummary = appointmentResult.source
  ? {
      source: appointmentResult.source,
      id: appointmentBody.id,
      status: appointmentBody.status ?? appointmentBody.appointment_status ?? null,
      customer_status: appointmentBody.customer_status ?? null,
      order_id: appointmentBody.order_id ?? null,
      customer_id: appointmentBody.customer_id ?? null,
      product_id: appointmentBody.product_id ?? null,
      resource_id: appointmentBody.resource_id ?? null,
      staff_ids: Array.isArray(appointmentBody.staff_ids) ? appointmentBody.staff_ids : [],
      start: appointmentBody.start ?? null,
      end: appointmentBody.end ?? null,
      all_day: appointmentBody.all_day ?? null,
      date_created: appointmentBody.date_created ?? null,
      date_modified: appointmentBody.date_modified ?? null
    }
  : null;

const requestedEmail = normalizeEmail(supportContext.emailAddress);
const linkedOrderEmail = normalizeEmail(orderSummary?.billing_email);
const linkedOrderEmailMatches = requestedEmail && linkedOrderEmail
  ? requestedEmail === linkedOrderEmail
  : null;

const productLookupRequested = Boolean(supportContext.productLookupRequested);
const priceFilter = supportContext.priceFilter ?? { requested: false, min: null, max: null };
const priceFilterRequested = Boolean(priceFilter.requested);
const sortedProducts = Array.isArray(productResponse.body) ? productResponse.body : [];
const positiveProducts = sortedProducts.filter((product) => Number(product.match_score ?? 0) > 0);
const selectedProducts = productLookupRequested
  ? (positiveProducts.length > 0 ? positiveProducts : sortedProducts).slice(0, 5)
  : [];
const productSummary = selectedProducts.map((product) => ({
  product_id: product.product_id || '',
  variation_id: product.variation_id || '',
  unique_id: product.unique_id || '',
  title: product.catalog_title || product.custom_title || '',
  product_url: product.canonical_product_url || product.product_url || '',
  price: product.price || '',
  regular_price: product.regular_price || '',
  sale_price: product.sale_price || '',
  effective_price: product.effective_price ?? null,
  status: product.status || '',
  stock_status: product.stock_status || '',
  stock_quantity: product.stock_quantity || '',
  sku: product.product_sku || '',
  manufacturer: product.product_manufacturer || '',
  tags: product.product_tags || '',
  gtin: product.wpfoof_gtin_name || '',
  summary: stripText([product.custom_text, product.custom_text1, product.custom_text2].filter(Boolean).join(' | ')),
  match_score: Number(product.match_score ?? 0)
}));

const bestProductMatch = productSummary[0] ?? null;
const hasRelevantProductMatch = Boolean(
  productLookupRequested &&
  bestProductMatch &&
  (
    priceFilterRequested
      ? productSummary.length > 0
      : bestProductMatch.match_score >= 300
  )
);
const priceMatchedProducts = priceFilterRequested && hasRelevantProductMatch
  ? productSummary.slice(0, 5)
  : [];

const appointmentLookup = {
  requested: Boolean(supportContext.appointmentSupportRequested),
  appointment_id: supportContext.appointmentLookupId || null,
  request_email: requestedEmail || null,
  found: Boolean(appointmentSummary),
  missing_identifier: Boolean(supportContext.appointmentSupportRequested && !supportContext.appointmentLookupId),
  not_found: Boolean(supportContext.appointmentLookupId && !appointmentSummary),
  linked_order_found: Boolean(orderSummary),
  linked_order_email_match: linkedOrderEmailMatches
};

const retrievedContext = {
  customer: {
    name: supportContext.contactName,
    phone_number: supportContext.contactPhone
  },
  routing: {
    processing_mode: supportContext.config.processingMode,
    gate_reason: supportContext.gateReason,
    labels: supportContext.labels
  },
  order_lookup: orderSummary,
  appointment_lookup: appointmentLookup,
  appointment_summary: appointmentSummary,
  product_search: {
    source: 'google_sheet',
    requested: productLookupRequested,
    search_term: productResponse.productSearch?.search_term ?? supportContext.productSearchTerm,
    requested_tokens: productResponse.productSearch?.requested_tokens ?? supportContext.productSearchTokens ?? [],
    price_filter: priceFilter,
    raw_candidate_count: productResponse.productSearch?.result_count ?? sortedProducts.length,
    has_relevant_match: hasRelevantProductMatch,
    best_match_name: hasRelevantProductMatch ? bestProductMatch?.title ?? null : null,
    best_match_url: hasRelevantProductMatch ? bestProductMatch?.product_url ?? null : null,
    best_match_score: hasRelevantProductMatch ? bestProductMatch?.match_score ?? null : null
  },
  product_lookup: hasRelevantProductMatch ? productSummary : [],
  faq_matches: supportContext.faqMatches,
  recent_messages: supportContext.recentMessages,
  order_creation: {
    requested: supportContext.createOrderRequested,
    enabled: supportContext.config.orderCreationEnabled,
    instruction: supportContext.config.orderCreationEnabled
      ? 'Order creation is enabled only when all required fields are collected and explicitly confirmed.'
      : 'Order creation is disabled in this phase. If the customer wants to place an order, collect details and route to a human teammate.'
  }
};

const systemMessage = [
  'You are the Famivita AI customer support agent working inside Chatwoot.',
  'Reply in the same language as the customer whenever possible.',
  'Use only the retrieved context for factual claims about orders, appointments, bookings, products, shipping, returns, payment, or policies.',
  'Use appointment_lookup and appointment_summary for booking, reservation, consultation, or appointment questions.',
  'If appointment_lookup.requested is true and appointment_lookup.found is false because appointment_lookup.missing_identifier is true, ask for the appointment ID or WooCommerce order number.',
  'If appointment_lookup.requested is true and appointment_lookup.found is false because appointment_lookup.not_found is true, say the appointment ID could not be found and ask the customer to confirm the appointment ID or order number.',
  'If appointment_summary exists, use appointment_summary.status, appointment_summary.start, appointment_summary.end, and order_lookup.billing_email when relevant.',
  'Do not say an appointment is confirmed, cancelled, completed, or rescheduled unless appointment_summary explicitly supports that.',
  'Only treat product_lookup as relevant when product_search.requested is true and product_search.has_relevant_match is true.',
  'If product_search.requested is false, do not mention products or include product URLs.',
  'If product_search.has_relevant_match is true, do not say the product is unavailable or missing from the catalog.',
  'If product_search.price_filter.requested is true and product_lookup has matches, list up to 3 matching products with name, price, and product_url.',
  'If product_search.price_filter.requested is true and product_lookup is empty, clearly say that no products were found for that price range.',
  'If the best product has stock_status equal to outofstock, say it exists but is currently out of stock.',
  'When you confirm a specific product match and best_match_url is available, include that exact URL in the reply.',
  'If the retrieved context is missing or insufficient, say that clearly and ask one short clarifying question or suggest a human handoff.',
  'Never invent order status, appointment details, delivery dates, product details, stock, prices, promotions, or medical advice.',
  'Keep replies concise, warm, and suitable for WhatsApp.',
  'If you need to escalate, direct the customer to ' + supportContext.config.supportEmail + '.'
].join('\n');

const userMessage = [
  'Latest customer message: ' + supportContext.content,
  'Customer name: ' + (supportContext.contactName || 'Unknown customer'),
  'Retrieved context JSON: ' + JSON.stringify(retrievedContext)
].join('\n\n');

return {
  accountId: supportContext.accountId,
  conversationId: supportContext.conversationId,
  chatwootBaseUrl: supportContext.config.chatwootBaseUrl,
  supportEmail: supportContext.config.supportEmail,
  customerName: supportContext.contactName || '',
  originalMessage: supportContext.content,
  productLookupRequested,
  priceFilterRequested,
  priceFilter,
  priceMatchedProducts,
  hasRelevantProductMatch,
  bestProductUrl: (!priceFilterRequested && hasRelevantProductMatch) ? bestProductMatch?.product_url ?? null : null,
  bestProductName: hasRelevantProductMatch ? bestProductMatch?.title ?? null : null,
  openAiRequest: {
    model: supportContext.config.openAiModel,
    temperature: 0.2,
    messages: [
      {
        role: 'system',
        content: systemMessage
      },
      {
        role: 'user',
        content: userMessage
      }
    ]
  }
};
'@

$appointmentLookupV3Url = @'
={{ $('Gate Test Contact').first().json.config.wooBaseUrl }}/wp-json/wc/v3/appointments/{{ $('Gate Test Contact').first().json.appointmentLookupId || '0' }}?consumer_key={{ $env.WOOCOMMERCE_CONSUMER_KEY }}&consumer_secret={{ $env.WOOCOMMERCE_CONSUMER_SECRET }}
'@.Trim()

$appointmentLookupLegacyUrl = @'
={{ $('Gate Test Contact').first().json.config.wooBaseUrl }}/wp-json/wc-appointments/v1/appointments/{{ $('Gate Test Contact').first().json.appointmentLookupId || '0' }}?consumer_key={{ $env.WOOCOMMERCE_CONSUMER_KEY }}&consumer_secret={{ $env.WOOCOMMERCE_CONSUMER_SECRET }}
'@.Trim()

$appointmentOrderLookupUrl = @'
={{ (() => {
  const current = $('Woo Appointment Lookup v3').first().json ?? {};
  const legacy = $('Woo Appointment Lookup Legacy').first().json ?? {};
  const currentBody = current.body ?? {};
  const legacyBody = legacy.body ?? {};
  const appointment = current.statusCode === 200 && currentBody.id
    ? currentBody
    : legacy.statusCode === 200 && legacyBody.id
      ? legacyBody
      : {};
  const orderId = appointment.order_id || 0;
  return $('Gate Test Contact').first().json.config.wooBaseUrl + '/wp-json/wc/v3/orders/' + orderId + '?consumer_key=' + $env.WOOCOMMERCE_CONSUMER_KEY + '&consumer_secret=' + $env.WOOCOMMERCE_CONSUMER_SECRET;
})() }}
'@.Trim()

(Get-Node 'Gate Test Contact').parameters.jsCode = $gateTestContactCode.Trim()
(Get-Node 'Build OpenAI Request').parameters.jsCode = $buildOpenAiRequestCode.Trim()

$positionUpdates = @{
  'Google Sheet Product Catalog' = @(2520, 220)
  'Merge Product Catalog Rows'   = @(2740, 220)
  'Sort Product Matches'         = @(2960, 220)
  'Build OpenAI Request'         = @(3180, 220)
  'OpenAI Reply'                 = @(3400, 220)
  'Prepare Chatwoot Reply'       = @(3620, 220)
  'Send Reply to Chatwoot'       = @(3840, 220)
}

foreach ($entry in $positionUpdates.GetEnumerator()) {
  (Get-Node $entry.Key).position = $entry.Value
}

foreach ($name in @('Woo Appointment Lookup v3', 'Woo Appointment Lookup Legacy', 'Woo Appointment Order Lookup')) {
  Remove-Node $name
}

$newNodes = @(
  [pscustomobject]@{
    parameters = [pscustomobject]@{
      method = 'GET'
      url = $appointmentLookupV3Url
      sendHeaders = $true
      headerParameters = [pscustomobject]@{
        parameters = @(
          [pscustomobject]@{
            name = 'accept'
            value = 'application/json'
          }
        )
      }
      options = [pscustomobject]@{
        response = [pscustomobject]@{
          response = [pscustomobject]@{
            fullResponse = $true
            neverError = $true
          }
        }
      }
    }
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4.2
    position = @(1860, 220)
    id = '9d0cdf43-79c4-4f1d-bb13-e70387402252'
    name = 'Woo Appointment Lookup v3'
    alwaysOutputData = $true
    onError = 'continueRegularOutput'
  },
  [pscustomobject]@{
    parameters = [pscustomobject]@{
      method = 'GET'
      url = $appointmentLookupLegacyUrl
      sendHeaders = $true
      headerParameters = [pscustomobject]@{
        parameters = @(
          [pscustomobject]@{
            name = 'accept'
            value = 'application/json'
          }
        )
      }
      options = [pscustomobject]@{
        response = [pscustomobject]@{
          response = [pscustomobject]@{
            fullResponse = $true
            neverError = $true
          }
        }
      }
    }
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4.2
    position = @(2080, 220)
    id = '8e7b4ad7-998a-4f4b-9af1-781ca857767d'
    name = 'Woo Appointment Lookup Legacy'
    alwaysOutputData = $true
    onError = 'continueRegularOutput'
  },
  [pscustomobject]@{
    parameters = [pscustomobject]@{
      method = 'GET'
      url = $appointmentOrderLookupUrl
      sendHeaders = $true
      headerParameters = [pscustomobject]@{
        parameters = @(
          [pscustomobject]@{
            name = 'accept'
            value = 'application/json'
          }
        )
      }
      options = [pscustomobject]@{
        response = [pscustomobject]@{
          response = [pscustomobject]@{
            fullResponse = $true
            neverError = $true
          }
        }
      }
    }
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4.2
    position = @(2300, 220)
    id = 'f7c1c8fc-15ec-4350-bf2f-0e76d520560a'
    name = 'Woo Appointment Order Lookup'
    alwaysOutputData = $true
    onError = 'continueRegularOutput'
  }
)

$workflow.nodes = @($workflow.nodes + $newNodes)

Add-OrReplace-Connection -Name 'Woo Order Lookup' -Value ([pscustomobject]@{
  main = @(
    @(
      [pscustomobject]@{
        node = 'Woo Appointment Lookup v3'
        type = 'main'
        index = 0
      }
    )
  )
})

Add-OrReplace-Connection -Name 'Woo Appointment Lookup v3' -Value ([pscustomobject]@{
  main = @(
    @(
      [pscustomobject]@{
        node = 'Woo Appointment Lookup Legacy'
        type = 'main'
        index = 0
      }
    )
  )
})

Add-OrReplace-Connection -Name 'Woo Appointment Lookup Legacy' -Value ([pscustomobject]@{
  main = @(
    @(
      [pscustomobject]@{
        node = 'Woo Appointment Order Lookup'
        type = 'main'
        index = 0
      }
    )
  )
})

Add-OrReplace-Connection -Name 'Woo Appointment Order Lookup' -Value ([pscustomobject]@{
  main = @(
    @(
      [pscustomobject]@{
        node = 'Google Sheet Product Catalog'
        type = 'main'
        index = 0
      }
    )
  )
})

$workflow | ConvertTo-Json -Depth 100 | Set-Content -Path $workflowPath
Write-Host "Updated workflow.json with appointment support."
