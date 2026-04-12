$ErrorActionPreference = 'Stop'

$sourcePath = 'f:\github\chatwoot n8n ai agent\chatwoot-ai-product-search-and-order-create-final.json'
$targetPath = 'f:\github\chatwoot n8n ai agent\chatwoot-ai-agent-hybrid.json'

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

if (-not (Test-Path $sourcePath)) {
  throw "Source workflow not found: $sourcePath"
}

$json = Get-Content -Raw $sourcePath | ConvertFrom-Json

$buildNodeName = Resolve-NodeName -Json $json -BaseName 'Build OpenAI Request'
$replyNodeName = Resolve-NodeName -Json $json -BaseName 'Prepare Chatwoot Reply'
$openAiNodeName = Resolve-NodeName -Json $json -BaseName 'OpenAI Reply'

$suffixMatch = [regex]::Match($buildNodeName, '(\d+)$')
$suffix = if ($suffixMatch.Success) { $suffixMatch.Groups[1].Value } else { '' }

$aiAgentNodeName = "AI Agent$suffix"
$chatModelNodeName = "OpenAI Chat Model$suffix"
$memoryNodeName = "Simple Memory$suffix"
$toolNodeName = "Context Helper Tool$suffix"
$wrapNodeName = "Wrap AI Agent Output$suffix"
$noteNodeName = "Hybrid AI Note$suffix"

$wrapCode = @'
const agentOutput = $input.first().json ?? {};
const content = String(
  agentOutput.output ??
  agentOutput.text ??
  agentOutput.response ??
  agentOutput.answer ??
  ''
).trim();

return [{
  json: {
    statusCode: 200,
    body: {
      choices: [
        {
          message: {
            content
          }
        }
      ]
    }
  }
}];
'@

$json.name = 'Hybrid: chatwoot ai agent'
$json.active = $false

Ensure-Node -Json $json -Node @{
  id = 'a9d623db-7a2f-4e9f-bd88-hybrid-ai-agent-root'
  name = $aiAgentNodeName
  type = '@n8n/n8n-nodes-langchain.agent'
  typeVersion = 2.2
  position = @(3320, 120)
  parameters = @{
    promptType = 'define'
    text = '={{ $json.openAiRequest.messages[1].content }}'
    options = @{
      systemMessage = '={{ $json.openAiRequest.messages[0].content }}'
      maxIterations = 4
      returnIntermediateSteps = $false
    }
  }
}

Ensure-Node -Json $json -Node @{
  id = 'e5727761-4f7f-4a50-b4f0-hybrid-openai-chat-model'
  name = $chatModelNodeName
  type = '@n8n/n8n-nodes-langchain.lmChatOpenAi'
  typeVersion = 1.2
  position = @(3320, 420)
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
  id = '774cb79f-18fc-42b7-8761-hybrid-memory'
  name = $memoryNodeName
  type = '@n8n/n8n-nodes-langchain.memoryBufferWindow'
  typeVersion = 1.3
  position = @(3560, 420)
  parameters = @{
    sessionKey = '={{ $json.conversationId }}'
    sessionIdType = 'customKey'
    contextWindowLength = 10
  }
}

Ensure-Node -Json $json -Node @{
  id = '7ffb6c0b-8ae0-49c7-a9cf-hybrid-context-tool'
  name = $toolNodeName
  type = '@n8n/n8n-nodes-langchain.toolCode'
  typeVersion = 1.2
  position = @(3080, 420)
  parameters = @{
    name = 'context_helper'
    description = 'Use this only if you need a quick reminder that the main prompt already contains the retrieved product, order, price, billing, and conversation context. In most cases you should answer directly from the main prompt and not call this tool.'
    language = 'javaScript'
    jsCode = "return 'The main prompt already contains the retrieved Famivita context. Use that context directly. If something is missing there, ask one short clarifying question instead of guessing.'"
  }
}

Ensure-Node -Json $json -Node @{
  id = '1ea0cc47-113f-4fa6-a4f7-hybrid-wrap-output'
  name = $wrapNodeName
  type = 'n8n-nodes-base.code'
  typeVersion = 2
  position = @(3560, 120)
  parameters = @{
    jsCode = $wrapCode.Trim()
  }
}

Ensure-Node -Json $json -Node @{
  id = '720f41a2-65b0-4fb4-9e7c-hybrid-note'
  name = $noteNodeName
  type = 'n8n-nodes-base.stickyNote'
  typeVersion = 1
  position = @(3020, -60)
  parameters = @{
    width = 500
    height = 140
    content = "## Hybrid AI Agent test\nThis version keeps the current deterministic product and order logic, but swaps the plain OpenAI reply step for an **AI Agent**.\n\nAfter import, connect an **OpenAI account** credential to `$chatModelNodeName` manually."
  }
}

Set-Connection -Connections $json.connections -Name $buildNodeName -Value @{
  main = ,(@(@{ node = $aiAgentNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $aiAgentNodeName -Value @{
  main = ,(@(@{ node = $wrapNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $wrapNodeName -Value @{
  main = ,(@(@{ node = $replyNodeName; type = 'main'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $chatModelNodeName -Value @{
  ai_languageModel = ,(@(@{ node = $aiAgentNodeName; type = 'ai_languageModel'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $memoryNodeName -Value @{
  ai_memory = ,(@(@{ node = $aiAgentNodeName; type = 'ai_memory'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $toolNodeName -Value @{
  ai_tool = ,(@(@{ node = $aiAgentNodeName; type = 'ai_tool'; index = 0 }))
}

Set-Connection -Connections $json.connections -Name $openAiNodeName -Value @{
  main = @(@())
}

$json | ConvertTo-Json -Depth 100 | Set-Content -Path $targetPath -Encoding UTF8
Write-Output $targetPath
