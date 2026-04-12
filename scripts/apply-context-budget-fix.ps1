$ErrorActionPreference = 'Stop'

$workflowPath = 'f:\github\chatwoot n8n ai agent\chatwoot-ai-product-search-and-order-create-final.json'

function Resolve-Node {
  param(
    [Parameter(Mandatory = $true)] $Json,
    [Parameter(Mandatory = $true)] [string] $BaseName
  )

  $exact = $Json.nodes | Where-Object { $_.name -eq $BaseName } | Select-Object -First 1
  if ($exact) { return $exact }

  $prefixed = $Json.nodes | Where-Object { $_.name -like "$BaseName*" } | Select-Object -First 1
  if ($prefixed) { return $prefixed }

  throw "Node '$BaseName' was not found in $($Json.name)"
}

function Replace-Between {
  param(
    [Parameter(Mandatory = $true)] [string] $Text,
    [Parameter(Mandatory = $true)] [string] $StartToken,
    [Parameter(Mandatory = $true)] [string] $EndToken,
    [Parameter(Mandatory = $true)] [string] $Replacement,
    [string] $Label = 'text'
  )

  $startIndex = $Text.IndexOf($StartToken)
  if ($startIndex -lt 0) { throw "Start token '$StartToken' not found in $Label" }

  $endIndex = $Text.IndexOf($EndToken, $startIndex)
  if ($endIndex -lt 0) { throw "End token '$EndToken' not found in $Label" }

  return $Text.Substring(0, $startIndex) + $Replacement + $Text.Substring($endIndex)
}

if (-not (Test-Path $workflowPath)) {
  throw "Workflow not found: $workflowPath"
}

$json = Get-Content -Raw $workflowPath | ConvertFrom-Json

$normalizeNode = Resolve-Node -Json $json -BaseName 'Normalize Incoming Event3'
$buildNode = Resolve-Node -Json $json -BaseName 'Build OpenAI Request3'

$normalizeCode = $normalizeNode.parameters.jsCode
$normalizeCode = $normalizeCode.Replace('maxConversationMessages: 20,', 'maxConversationMessages: 8,')
$normalizeNode.parameters.jsCode = $normalizeCode

$buildCode = $buildNode.parameters.jsCode
$buildCode = $buildCode.Replace("const stripText = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();", @"
const stripText = (value) => String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const truncateText = (value, maxLength = 220) => {
  const text = stripText(value);
  if (!text) return '';
  return text.length <= maxLength ? text : `${text.slice(0, Math.max(0, maxLength - 3)).trim()}...`;
};
"@)

$buildCode = $buildCode.Replace(".slice(0, broadCatalogQueryRequested ? 8 : 5)", ".slice(0, broadCatalogQueryRequested ? 4 : 3)")
$buildCode = $buildCode.Replace(".slice(0, broadCatalogQueryRequested ? 8 : 5)", ".slice(0, broadCatalogQueryRequested ? 4 : 3)")
$buildCode = $buildCode.Replace(".filter((message) => message.role === 'user')", ".filter((message) => message.role === 'customer')")

$compactContextBlock = @"
const compactProductLookup = (hasRelevantProductMatch ? productSummary : [])
  .slice(0, broadCatalogQueryRequested ? 4 : 3)
  .map((product) => ({
    title: truncateText(product.title, 120),
    variation_label: truncateText(product.variation_label, 80),
    effective_price: product.effective_price ?? product.price ?? null,
    stock_status: product.stock_status || '',
    product_url: product.product_url || '',
    cart_url: product.cart_url || '',
    summary: truncateText(product.summary, 140)
  }));
const compactFaqMatches = (Array.isArray(supportContext.faqMatches) ? supportContext.faqMatches : [])
  .slice(0, 2)
  .map((item) => ({
    topic: item.topic || '',
    answer: truncateText(item.answer, 140)
  }));
const compactRecentMessages = (Array.isArray(supportContext.recentMessages) ? supportContext.recentMessages : [])
  .slice(-6)
  .map((message) => ({
    role: message.role,
    content: truncateText(message.content, 180)
  }));
const compactCustomerProfile = customerProfileMemory ? {
  contact_name: customerProfileMemory.contactName || '',
  billing_email: customerProfileMemory.billingEmail || '',
  billing_city: customerProfileMemory.billingCity || '',
  billing_state: customerProfileMemory.billingState || '',
  preferred_language: customerProfileMemory.preferredLanguage || '',
  interest_tags: (customerProfileMemory.interestTags || []).slice(0, 6),
  recent_search_terms: (customerProfileMemory.recentSearchTerms || []).slice(-5),
  recent_semantic_tokens: (customerProfileMemory.recentSemanticTokens || []).slice(-8),
  last_viewed_products: (customerProfileMemory.lastViewedProducts || []).slice(-3).map((item) => ({
    title: truncateText(item.title, 100),
    product_url: item.product_url || ''
  })),
  last_ordered_products: (customerProfileMemory.lastOrderedProducts || []).slice(-3).map((item) => ({
    product_title: truncateText(item.product_title, 100),
    quantity: item.quantity || null
  }))
} : null;
const compactRetrievedContext = {
  customer: {
    name: supportContext.contactName || '',
    phone_number: supportContext.contactPhone || ''
  },
  routing: {
    processing_mode: supportContext.config.processingMode,
    gate_reason: supportContext.gateReason
  },
  order_lookup: orderSummary ? {
    id: orderSummary.id,
    status: orderSummary.status,
    total: orderSummary.total,
    billing_email: orderSummary.billing_email || '',
    line_items: (orderSummary.line_items || []).slice(0, 2)
  } : null,
  product_search: {
    requested: productLookupRequested,
    search_term: productResponse.productSearch?.search_term ?? supportContext.productSearchTerm,
    requested_tokens: (productResponse.productSearch?.requested_tokens ?? supportContext.productSearchTokens ?? []).slice(0, 6),
    semantic_tokens: (productResponse.productSearch?.semantic_tokens ?? semanticSearchTokens).slice(0, 8),
    intent_tags: (productResponse.productSearch?.intent_tags ?? categoryIntentTags).slice(0, 6),
    broad_catalog_query: productResponse.productSearch?.broad_catalog_query ?? broadCatalogQueryRequested,
    price_filter: priceFilter,
    raw_candidate_count: productResponse.productSearch?.result_count ?? sortedProducts.length,
    has_relevant_match: hasRelevantProductMatch,
    best_match_name: hasRelevantProductMatch ? bestProductMatch?.title ?? null : null,
    best_match_url: hasRelevantProductMatch ? bestProductMatch?.product_url ?? null : null
  },
  cart_link: {
    requested: cartLinkRequested,
    best_cart_url: bestProductCartUrl,
    best_product_page_url: hasRelevantProductMatch ? bestProductMatch?.product_url ?? null : null
  },
  product_lookup: compactProductLookup,
  faq_matches: compactFaqMatches,
  recent_messages: compactRecentMessages,
  short_term_memory: {
    recent_customer_messages: recentCustomerMessages.slice(-4).map((message) => ({
      content: truncateText(message.content, 160)
    })),
    current_intent_tags: categoryIntentTags.slice(0, 6),
    current_semantic_tokens: semanticSearchTokens.slice(0, 8),
    broad_catalog_query: broadCatalogQueryRequested
  },
  customer_profile_memory: compactCustomerProfile,
  order_creation: {
    requested: Boolean(orderDraft.orderConversationRequested),
    action_requested: Boolean(orderDraft.orderActionRequested),
    enabled: supportContext.config.orderCreationEnabled,
    status: orderCreationStatus,
    missing_fields: (orderDraft.missingFields ?? []).slice(0, 8),
    billing_email: orderDraft.billingEmail || '',
    quantity: orderDraft.quantity || null,
    product: orderDraft.product ? {
      title: truncateText(orderDraft.product.title || '', 120),
      product_url: orderDraft.product.product_url || ''
    } : null,
    variation_options: (orderDraft.variationOptions ?? []).slice(0, 3).map((item) => ({
      title: truncateText(item.title || '', 120),
      variation_label: truncateText(item.variation_label || '', 80),
      effective_price: item.effective_price ?? item.price ?? null,
      product_url: item.product_url || ''
    })),
    pay_url: orderPayUrl,
    created_order_id: createdOrder?.id ?? null,
    error_status: createOrderResponse?.statusCode ?? null
  }
};
const compactContextText = JSON.stringify(compactRetrievedContext);

const systemMessage = [
  'You are the Famivita AI customer support agent working inside Chatwoot.',
  'Act like an excellent Famivita sales specialist: friendly, clear, persuasive, and accurate.',
  'Reply in the same language as the customer whenever possible.',
  'Use only the retrieved context for factual claims about orders, products, shipping, returns, payment, or policies.',
  'Only treat product_lookup as relevant when product_search.requested is true and product_search.has_relevant_match is true.',
  'If product_search.requested is false, do not mention products or include product URLs.',
  'If product_search.has_relevant_match is true, do not say the product is unavailable or missing from the catalog.',
  'Use product_lookup fields such as title, variation_label, price, stock_status, manufacturer, tags, summary, free_shipping_tag, discount_tag, and cart_url to answer product questions accurately.',
  'For broad category queries like vitamins for pregnancy, fertility supplements, or trying to conceive, recommend a short curated list of the best-matching products from product_lookup.',
  'Use customer_profile_memory and short_term_memory to personalize suggestions, but do not mention hidden memory or internal storage.',
  'Use recent_messages and short_term_memory to resolve follow-up references such as "that one", "same as before", or "the last product".',
  'If product_search.price_filter.requested is true and product_lookup has matches, list up to 3 matching products with name, price, and product_url.',
  'If product_search.price_filter.requested is true and product_lookup is empty, clearly say that no products were found for that price range.',
  'If cart_link.requested is true and cart_link.best_cart_url is available, include that exact cart URL and also include the product page URL when helpful.',
  'If order_creation.status is created, confirm that the order is ready and include the exact pay_url.',
  'If order_creation.status is needs_info, ask only for the missing fields.',
  'If the best product has stock_status equal to outofstock, say it exists but is currently out of stock.',
  'When a product lookup has a confirmed best_match_url and the message is not part of order creation, include that exact URL in the reply.',
  'If the retrieved context is missing or insufficient, say that clearly and ask one short clarifying question or suggest a human handoff.',
  'Never invent order status, delivery dates, product details, stock, prices, promotions, or medical advice.',
  'Keep replies concise, warm, and suitable for WhatsApp.',
  'If you need to escalate, direct the customer to ' + supportContext.config.supportEmail + '.'
].join('\n');

const userMessage = [
"@

$buildCode = Replace-Between -Text $buildCode -StartToken 'const systemMessage = [' -EndToken "const userMessage = [" -Replacement $compactContextBlock -Label 'Build OpenAI Request3'
$buildCode = $buildCode.Replace("'Retrieved context JSON: ' + JSON.stringify(retrievedContext)", "'Retrieved context JSON: ' + compactContextText")
$buildCode = $buildCode.Replace("  orderCreateErrorMessage: createOrderErrorMessage,`n  openAiRequest: {", "  orderCreateErrorMessage: createOrderErrorMessage,`n  compactContextText,`n  compactContext: compactRetrievedContext,`n  openAiRequest: {")

$buildNode.parameters.jsCode = $buildCode

$json | ConvertTo-Json -Depth 100 | Set-Content -Path $workflowPath
Write-Output "Updated workflow: $workflowPath"
