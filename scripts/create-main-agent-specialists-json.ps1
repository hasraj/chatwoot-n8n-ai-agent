$ErrorActionPreference = 'Stop'

$sourcePath = 'f:\github\chatwoot n8n ai agent\chatwoot-ai-product-search-and-order-create-final.json'
$targetPath = 'f:\github\chatwoot n8n ai agent\chatwoot-ai-main-agent-specialists.json'

function Resolve-NodeName {
  param(
    [Parameter(Mandatory = $true)] $Json,
    [Parameter(Mandatory = $true)] [string] $BaseName
  )

  $exact = $Json.nodes | Where-Object { $_.name -eq $BaseName } | Select-Object -First 1
  if ($exact) { return $exact.name }

  $prefixed = $Json.nodes | Where-Object { $_.name -like "$BaseName*" } | Select-Object -First 1
  if ($prefixed) { return $prefixed.name }

  throw "Node '$BaseName' was not found in $($Json.name)"
}

function Ensure-Node {
  param(
    [Parameter(Mandatory = $true)] $Json,
    [Parameter(Mandatory = $true)] [hashtable] $Node
  )

  $existing = $Json.nodes | Where-Object { $_.name -eq $Node.name } | Select-Object -First 1
  if ($existing) {
    foreach ($prop in $Node.Keys) { $existing.$prop = $Node[$prop] }
    return
  }

  $Json.nodes += [pscustomobject]$Node
}

function Set-Connection {
  param(
    [Parameter(Mandatory = $true)] $Connections,
    [Parameter(Mandatory = $true)] [string] $Name,
    [Parameter(Mandatory = $true)] $Value
  )

  $existing = $Connections.PSObject.Properties[$Name]
  if ($existing) {
    $existing.Value = $Value
    return
  }

  $Connections | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
}

function Remove-Connection {
  param(
    [Parameter(Mandatory = $true)] $Connections,
    [Parameter(Mandatory = $true)] [string] $Name
  )

  $Connections.PSObject.Properties.Remove($Name) | Out-Null
}

function Remove-Node {
  param(
    [Parameter(Mandatory = $true)] $Json,
    [Parameter(Mandatory = $true)] [string] $Name
  )

  $Json.nodes = @($Json.nodes | Where-Object { $_.name -ne $Name })
}

if (-not (Test-Path $sourcePath)) {
  throw "Source workflow not found: $sourcePath"
}

$json = Get-Content -Raw $sourcePath | ConvertFrom-Json

$buildNodeName = Resolve-NodeName -Json $json -BaseName 'Build OpenAI Request'
$replyNodeName = Resolve-NodeName -Json $json -BaseName 'Prepare Chatwoot Reply'
$openAiNodeName = Resolve-NodeName -Json $json -BaseName 'OpenAI Reply'
$sendNodeName = Resolve-NodeName -Json $json -BaseName 'Send Reply to Chatwoot'

$suffixMatch = [regex]::Match($buildNodeName, '(\d+)$')
$suffix = if ($suffixMatch.Success) { $suffixMatch.Groups[1].Value } else { '' }

$supportReqNodeName = "Build Support Specialist Request$suffix"
$supportAgentNodeName = "Support Specialist Agent$suffix"
$supportWrapNodeName = "Wrap Support Specialist Output$suffix"

$recommendReqNodeName = "Build Recommendation Specialist Request$suffix"
$recommendAgentNodeName = "Recommendation Specialist Agent$suffix"
$recommendWrapNodeName = "Wrap Recommendation Specialist Output$suffix"

$safetyReqNodeName = "Build Safety Specialist Request$suffix"
$safetyAgentNodeName = "Health Safety Specialist Agent$suffix"
$safetyWrapNodeName = "Wrap Health Safety Output$suffix"

$mainReqNodeName = "Build Main Conversation Request$suffix"
$mainAgentNodeName = "Main Conversation Agent$suffix"
$mainWrapNodeName = "Wrap Main Conversation Output$suffix"
$packageReplyNodeName = "Package Main Agent Reply$suffix"

$sharedModelNodeName = "Shared OpenAI Chat Model$suffix"
$mainMemoryNodeName = "Main Agent Memory$suffix"
$mainToolNodeName = "Main Context Helper Tool$suffix"
$noteNodeName = "Main Speaks Note$suffix"

$buildSupportCode = @'
const requestContext = $('Build OpenAI Request').first().json ?? {};

const systemPrompt = [
  'You are the internal Famivita support specialist.',
  'You never speak to the customer directly.',
  'Return only compact JSON.',
  'Focus on support reasoning, order/help routing, policy-like handling, and whether human escalation is needed.',
  'Do not invent store facts. Use only the deterministic context provided.'
].join('\n');

const userPrompt = [
  'Analyze this deterministic customer-support context and return JSON with keys:',
  '{"support_intent":"","support_outcome":"","handoff_recommended":false,"handoff_reason":"","notes":[]}',
  '',
  'Deterministic context:',
  requestContext.openAiRequest?.messages?.[1]?.content || ''
].join('\n');

return [{
  json: {
    ...requestContext,
    supportSpecialistSystemPrompt: systemPrompt,
    supportSpecialistUserPrompt: userPrompt
  }
}];
'@

$buildRecommendationCode = @'
const previous = $('Wrap Support Specialist Output').first().json ?? {};

const systemPrompt = [
  'You are the internal Famivita recommendation specialist.',
  'You never speak to the customer directly.',
  'Return only compact JSON.',
  'Focus on product fit, product suggestions, cross-sell opportunities, and commercial helpfulness.',
  'Do not invent product data. Use only the deterministic context provided.'
].join('\n');

const userPrompt = [
  'Analyze this deterministic product and customer context and return JSON with keys:',
  '{"customer_goal":"","best_product_fit":"","recommended_products":[],"cross_sell":[],"notes":[]}',
  '',
  'Deterministic context:',
  previous.openAiRequest?.messages?.[1]?.content || '',
  '',
  'Support specialist internal JSON:',
  JSON.stringify(previous.supportSpecialist ?? {})
].join('\n');

return [{
  json: {
    ...previous,
    recommendationSpecialistSystemPrompt: systemPrompt,
    recommendationSpecialistUserPrompt: userPrompt
  }
}];
'@

$buildSafetyCode = @'
const previous = $('Wrap Recommendation Specialist Output').first().json ?? {};

const systemPrompt = [
  'You are the internal Famivita health-safety specialist.',
  'You never speak to the customer directly.',
  'Return only compact JSON.',
  'Decide whether the question is health-sensitive and whether safe general guidance is okay.',
  'If it is risky, recommend caution or escalation. Do not invent medical advice.'
].join('\n');

const userPrompt = [
  'Analyze this message and context and return JSON with keys:',
  '{"health_sensitive":false,"safe_to_answer":true,"warning_level":"low","escalate":false,"notes":[]}',
  '',
  'Deterministic context:',
  previous.openAiRequest?.messages?.[1]?.content || '',
  '',
  'Recommendation specialist internal JSON:',
  JSON.stringify(previous.recommendationSpecialist ?? {})
].join('\n');

return [{
  json: {
    ...previous,
    safetySpecialistSystemPrompt: systemPrompt,
    safetySpecialistUserPrompt: userPrompt
  }
}];
'@

$wrapSupportCode = @'
const previous = $('Build Support Specialist Request').first().json ?? {};
const agentOutput = $input.first().json ?? {};
const raw = String(agentOutput.output ?? agentOutput.text ?? agentOutput.response ?? agentOutput.answer ?? '').trim();

let parsed = {};
try { parsed = raw ? JSON.parse(raw) : {}; } catch (error) { parsed = { raw }; }

return [{
  json: {
    ...previous,
    supportSpecialist: parsed,
    supportSpecialistRaw: raw
  }
}];
'@

$wrapRecommendationCode = @'
const previous = $('Build Recommendation Specialist Request').first().json ?? {};
const agentOutput = $input.first().json ?? {};
const raw = String(agentOutput.output ?? agentOutput.text ?? agentOutput.response ?? agentOutput.answer ?? '').trim();

let parsed = {};
try { parsed = raw ? JSON.parse(raw) : {}; } catch (error) { parsed = { raw }; }

return [{
  json: {
    ...previous,
    recommendationSpecialist: parsed,
    recommendationSpecialistRaw: raw
  }
}];
'@

$wrapSafetyCode = @'
const previous = $('Build Health Safety Specialist Request').first().json ?? {};
const agentOutput = $input.first().json ?? {};
const raw = String(agentOutput.output ?? agentOutput.text ?? agentOutput.response ?? agentOutput.answer ?? '').trim();

let parsed = {};
try { parsed = raw ? JSON.parse(raw) : {}; } catch (error) { parsed = { raw }; }

return [{
  json: {
    ...previous,
    safetySpecialist: parsed,
    safetySpecialistRaw: raw
  }
}];
'@

$buildMainCode = @'
const previous = $('Wrap Health Safety Output').first().json ?? {};

const specialistBundle = {
  support_specialist: previous.supportSpecialist ?? {},
  recommendation_specialist: previous.recommendationSpecialist ?? {},
  health_safety_specialist: previous.safetySpecialist ?? {}
};

const systemPrompt = [
  previous.openAiRequest?.messages?.[0]?.content || '',
  '',
  'You are the main Famivita conversation agent.',
  'You are the only agent allowed to speak to the customer.',
  'The specialist agents are internal only. Never mention them, quote them, or expose their names.',
  'Deterministic workflow context is the source of truth for products, prices, customer/order data, billing validation, actions, order creation, payment links, and escalation signals.',
  'Use the specialist outputs only as internal reasoning aids to improve the final reply.',
  'If order_creation.status is created, send the exact payment link and do not ask the customer again for the same order.',
  'If order_creation.status is needs_info, ask only for the missing fields and do not repeat fields already provided.',
  'If order_creation.status is awaiting_confirmation, ask for confirmation clearly once.',
  'If the health safety specialist says the topic is unsafe or escalation is needed, avoid risky health claims and suggest safe next steps.',
  'Keep the reply concise, clear, and natural for WhatsApp.'
].filter(Boolean).join('\n');

const userPrompt = [
  previous.openAiRequest?.messages?.[1]?.content || '',
  '',
  'Internal specialist outputs JSON:',
  JSON.stringify(specialistBundle)
].join('\n\n');

return [{
  json: {
    ...previous,
    mainConversationSystemPrompt: systemPrompt,
    mainConversationUserPrompt: userPrompt
  }
}];
'@

$wrapMainCode = @'
const requestContext = $('Build Main Conversation Request').first().json ?? {};
const agentOutput = $input.first().json ?? {};
const content = String(agentOutput.output ?? agentOutput.text ?? agentOutput.response ?? agentOutput.answer ?? '').trim();

return [{
  json: {
    ...requestContext,
    mainConversationReply: content
  }
}];
'@

$packageReplyCode = @'
const requestContext = $('Wrap Main Conversation Output').first().json ?? {};
const reply = String(requestContext.mainConversationReply || '').trim()
  || `Thanks for your message. I need a human teammate to review this so we can help you correctly. You can also reach us at ${requestContext.supportEmail}.`;

return [{
  json: {
    accountId: requestContext.accountId,
    conversationId: requestContext.conversationId,
    chatwootBaseUrl: requestContext.chatwootBaseUrl,
    reply
  }
}];
'@

$buildSupportCodeForFile = $buildSupportCode.Trim()
$buildSupportCodeForFile = $buildSupportCodeForFile.Replace("'Build OpenAI Request'", "'$buildNodeName'")

$buildRecommendationCodeForFile = $buildRecommendationCode.Trim()
$buildRecommendationCodeForFile = $buildRecommendationCodeForFile.Replace("'Wrap Support Specialist Output'", "'$supportWrapNodeName'")

$buildSafetyCodeForFile = $buildSafetyCode.Trim()
$buildSafetyCodeForFile = $buildSafetyCodeForFile.Replace("'Wrap Recommendation Specialist Output'", "'$recommendWrapNodeName'")

$wrapSupportCodeForFile = $wrapSupportCode.Trim()
$wrapSupportCodeForFile = $wrapSupportCodeForFile.Replace("'Build Support Specialist Request'", "'$supportReqNodeName'")

$wrapRecommendationCodeForFile = $wrapRecommendationCode.Trim()
$wrapRecommendationCodeForFile = $wrapRecommendationCodeForFile.Replace("'Build Recommendation Specialist Request'", "'$recommendReqNodeName'")

$wrapSafetyCodeForFile = $wrapSafetyCode.Trim()
$wrapSafetyCodeForFile = $wrapSafetyCodeForFile.Replace("'Build Health Safety Specialist Request'", "'$safetyReqNodeName'")

$buildMainCodeForFile = $buildMainCode.Trim()
$buildMainCodeForFile = $buildMainCodeForFile.Replace("'Wrap Health Safety Output'", "'$safetyWrapNodeName'")

$wrapMainCodeForFile = $wrapMainCode.Trim()
$wrapMainCodeForFile = $wrapMainCodeForFile.Replace("'Build Main Conversation Request'", "'$mainReqNodeName'")

$packageReplyCodeForFile = $packageReplyCode.Trim()
$packageReplyCodeForFile = $packageReplyCodeForFile.Replace("'Wrap Main Conversation Output'", "'$mainWrapNodeName'")

$json.name = 'Main agent speaks: chatwoot ai'
$json.active = $false

Ensure-Node -Json $json -Node @{
  id = '0a6f8c52-2e0a-44a4-b8a9-main-speaks-note'
  name = $noteNodeName
  type = 'n8n-nodes-base.stickyNote'
  typeVersion = 1
  position = @(2960, -160)
  parameters = @{
    width = 760
    height = 180
    content = "## Main agent speaks, other agents think\nThis hybrid export keeps the deterministic product/order workflow.\n\nOnly **$mainAgentNodeName** writes the customer-facing message.\nThe support, recommendation, and health-safety agents work behind the scenes and return structured JSON to the main agent."
  }
}

Ensure-Node -Json $json -Node @{
  id = '9e733d17-33c2-4ce9-bbd2-build-support-request'
  name = $supportReqNodeName
  type = 'n8n-nodes-base.code'
  typeVersion = 2
  position = @(3180, 0)
  parameters = @{ jsCode = $buildSupportCodeForFile }
}

Ensure-Node -Json $json -Node @{
  id = '4f09ca0d-3e64-4314-a20a-support-agent'
  name = $supportAgentNodeName
  type = '@n8n/n8n-nodes-langchain.agent'
  typeVersion = 2.2
  position = @(3400, 0)
  parameters = @{
    promptType = 'define'
    text = '={{ $json.supportSpecialistUserPrompt }}'
    options = @{
      systemMessage = '={{ $json.supportSpecialistSystemPrompt }}'
      maxIterations = 3
      returnIntermediateSteps = $false
    }
  }
}

Ensure-Node -Json $json -Node @{
  id = 'b96dc601-8ff4-4163-9330-wrap-support'
  name = $supportWrapNodeName
  type = 'n8n-nodes-base.code'
  typeVersion = 2
  position = @(3620, 0)
  parameters = @{ jsCode = $wrapSupportCodeForFile }
}

Ensure-Node -Json $json -Node @{
  id = '1d6d38c6-6178-4f22-a84f-build-recommend'
  name = $recommendReqNodeName
  type = 'n8n-nodes-base.code'
  typeVersion = 2
  position = @(3840, 0)
  parameters = @{ jsCode = $buildRecommendationCodeForFile }
}

Ensure-Node -Json $json -Node @{
  id = '6dc736e1-2cb1-4e74-bbc6-recommend-agent'
  name = $recommendAgentNodeName
  type = '@n8n/n8n-nodes-langchain.agent'
  typeVersion = 2.2
  position = @(4060, 0)
  parameters = @{
    promptType = 'define'
    text = '={{ $json.recommendationSpecialistUserPrompt }}'
    options = @{
      systemMessage = '={{ $json.recommendationSpecialistSystemPrompt }}'
      maxIterations = 3
      returnIntermediateSteps = $false
    }
  }
}

Ensure-Node -Json $json -Node @{
  id = '02a5a57a-296f-47e4-8ae9-wrap-recommend'
  name = $recommendWrapNodeName
  type = 'n8n-nodes-base.code'
  typeVersion = 2
  position = @(4280, 0)
  parameters = @{ jsCode = $wrapRecommendationCodeForFile }
}

Ensure-Node -Json $json -Node @{
  id = 'f0289b43-5d1f-4d95-8caa-build-safety'
  name = $safetyReqNodeName
  type = 'n8n-nodes-base.code'
  typeVersion = 2
  position = @(4500, 0)
  parameters = @{ jsCode = $buildSafetyCodeForFile }
}

Ensure-Node -Json $json -Node @{
  id = '0feec7b0-9135-4ab4-9ed8-safety-agent'
  name = $safetyAgentNodeName
  type = '@n8n/n8n-nodes-langchain.agent'
  typeVersion = 2.2
  position = @(4720, 0)
  parameters = @{
    promptType = 'define'
    text = '={{ $json.safetySpecialistUserPrompt }}'
    options = @{
      systemMessage = '={{ $json.safetySpecialistSystemPrompt }}'
      maxIterations = 3
      returnIntermediateSteps = $false
    }
  }
}

Ensure-Node -Json $json -Node @{
  id = '87e19086-669b-4b4a-9e4a-wrap-safety'
  name = $safetyWrapNodeName
  type = 'n8n-nodes-base.code'
  typeVersion = 2
  position = @(4940, 0)
  parameters = @{ jsCode = $wrapSafetyCodeForFile }
}

Ensure-Node -Json $json -Node @{
  id = 'ca3ab4c7-d586-4fe6-9238-build-main-conversation'
  name = $mainReqNodeName
  type = 'n8n-nodes-base.code'
  typeVersion = 2
  position = @(5160, 0)
  parameters = @{ jsCode = $buildMainCodeForFile }
}

Ensure-Node -Json $json -Node @{
  id = 'ae0ae86b-a519-4e87-a4d8-main-conversation-agent'
  name = $mainAgentNodeName
  type = '@n8n/n8n-nodes-langchain.agent'
  typeVersion = 2.2
  position = @(5380, 0)
  parameters = @{
    promptType = 'define'
    text = '={{ $json.mainConversationUserPrompt }}'
    options = @{
      systemMessage = '={{ $json.mainConversationSystemPrompt }}'
      maxIterations = 4
      returnIntermediateSteps = $false
    }
  }
}

Ensure-Node -Json $json -Node @{
  id = 'adb72e7d-454f-49f8-b870-shared-chat-model'
  name = $sharedModelNodeName
  type = '@n8n/n8n-nodes-langchain.lmChatOpenAi'
  typeVersion = 1.2
  position = @(5380, 360)
  parameters = @{
    model = @{
      '__rl' = $true
      mode = 'list'
      value = 'gpt-4o-mini'
      cachedResultName = 'gpt-4o-mini'
    }
    options = @{
      temperature = 0.2
    }
  }
}

Ensure-Node -Json $json -Node @{
  id = 'e3e3865d-2672-4e4e-bbc8-main-memory'
  name = $mainMemoryNodeName
  type = '@n8n/n8n-nodes-langchain.memoryBufferWindow'
  typeVersion = 1.3
  position = @(5600, 360)
  parameters = @{
    sessionKey = '={{ $(''' + $mainReqNodeName + ''').first().json.conversationId }}'
    sessionIdType = 'customKey'
    contextWindowLength = 12
  }
}

Ensure-Node -Json $json -Node @{
  id = '36d71d3d-93ee-4cbf-a3e8-main-context-tool'
  name = $mainToolNodeName
  type = '@n8n/n8n-nodes-langchain.toolCode'
  typeVersion = 1.2
  position = @(5160, 360)
  parameters = @{
    name = 'context_helper'
    description = 'Use this only if you need a reminder that deterministic product, order, billing, price, and action context is already included in the prompt. Usually answer directly from the prompt.'
    language = 'javaScript'
    jsCode = "return 'Deterministic product, order, billing, payment, and escalation context is already present in the main prompt. Use that context as the source of truth.'"
  }
}

Ensure-Node -Json $json -Node @{
  id = '47ccf690-5a4d-4e73-b242-wrap-main-conversation'
  name = $mainWrapNodeName
  type = 'n8n-nodes-base.code'
  typeVersion = 2
  position = @(5600, 0)
  parameters = @{ jsCode = $wrapMainCodeForFile }
}

Ensure-Node -Json $json -Node @{
  id = '9c378d7e-8c20-45a7-a2fa-package-main-reply'
  name = $packageReplyNodeName
  type = 'n8n-nodes-base.code'
  typeVersion = 2
  position = @(5820, 0)
  parameters = @{ jsCode = $packageReplyCodeForFile }
}

Set-Connection -Connections $json.connections -Name $buildNodeName -Value @{
  main = ,(@(@{ node = $supportReqNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $supportReqNodeName -Value @{
  main = ,(@(@{ node = $supportAgentNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $supportAgentNodeName -Value @{
  main = ,(@(@{ node = $supportWrapNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $supportWrapNodeName -Value @{
  main = ,(@(@{ node = $recommendReqNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $recommendReqNodeName -Value @{
  main = ,(@(@{ node = $recommendAgentNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $recommendAgentNodeName -Value @{
  main = ,(@(@{ node = $recommendWrapNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $recommendWrapNodeName -Value @{
  main = ,(@(@{ node = $safetyReqNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $safetyReqNodeName -Value @{
  main = ,(@(@{ node = $safetyAgentNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $safetyAgentNodeName -Value @{
  main = ,(@(@{ node = $safetyWrapNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $safetyWrapNodeName -Value @{
  main = ,(@(@{ node = $mainReqNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $mainReqNodeName -Value @{
  main = ,(@(@{ node = $mainAgentNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $mainAgentNodeName -Value @{
  main = ,(@(@{ node = $mainWrapNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $mainWrapNodeName -Value @{
  main = ,(@(@{ node = $packageReplyNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $packageReplyNodeName -Value @{
  main = ,(@(@{ node = $sendNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $sharedModelNodeName -Value @{
  ai_languageModel = ,(@(
    @{ node = $supportAgentNodeName; type = 'ai_languageModel'; index = 0 },
    @{ node = $recommendAgentNodeName; type = 'ai_languageModel'; index = 0 },
    @{ node = $safetyAgentNodeName; type = 'ai_languageModel'; index = 0 },
    @{ node = $mainAgentNodeName; type = 'ai_languageModel'; index = 0 }
  ))
}

Set-Connection -Connections $json.connections -Name $mainMemoryNodeName -Value @{
  ai_memory = ,(@(@{ node = $mainAgentNodeName; type = 'ai_memory'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $mainToolNodeName -Value @{
  ai_tool = ,(@(@{ node = $mainAgentNodeName; type = 'ai_tool'; index = 0 }))
}

Remove-Connection -Connections $json.connections -Name $openAiNodeName
Remove-Connection -Connections $json.connections -Name $replyNodeName
Remove-Node -Json $json -Name $openAiNodeName
Remove-Node -Json $json -Name $replyNodeName

$json | ConvertTo-Json -Depth 100 | Set-Content -Path $targetPath -Encoding UTF8
Write-Output $targetPath
