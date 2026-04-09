$ErrorActionPreference = 'Stop'

$basePath = 'f:\github\chatwoot n8n ai agent\chatwoot-ai-test-3-fixed.json'
$templatePath = 'f:\github\chatwoot n8n ai agent\workflow.json'
$targetPath = 'f:\github\chatwoot n8n ai agent\chatwoot-ai-test-3-google-sheet.json'

$base = Get-Content -Raw $basePath | ConvertFrom-Json
$template = Get-Content -Raw $templatePath | ConvertFrom-Json

$nodesToImport = @(
  'Gate Test Contact',
  'Google Sheet Product Catalog',
  'Merge Product Catalog Rows',
  'Sort Product Matches',
  'Build OpenAI Request'
)

$nodesToRemove = @($nodesToImport + 'Woo Product Search')
$base.nodes = @(
  $base.nodes | Where-Object { $nodesToRemove -notcontains $_.name }
)

$importedNodes = @(
  $template.nodes | Where-Object { $nodesToImport -contains $_.name }
)

$base.nodes += $importedNodes
$base.name = 'chatwoot ai test - google sheet'

if ($base.connections.PSObject.Properties.Name -contains 'Woo Product Search') {
  $base.connections.PSObject.Properties.Remove('Woo Product Search')
}

foreach ($name in @(
  'Gate Test Contact',
  'Woo Order Lookup',
  'Google Sheet Product Catalog',
  'Merge Product Catalog Rows',
  'Sort Product Matches',
  'Build OpenAI Request'
)) {
  $value = $template.connections.$name
  Add-Member -InputObject $base.connections -NotePropertyName $name -NotePropertyValue $value -Force
}

$base | ConvertTo-Json -Depth 100 | Set-Content -Path $targetPath -Encoding UTF8
Write-Output $targetPath
