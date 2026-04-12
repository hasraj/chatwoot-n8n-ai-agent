$ErrorActionPreference = 'Stop'

$targetPaths = @(
  'f:\github\chatwoot n8n ai agent\chatwoot-ai-product-search-and-order-create-final.json',
  'f:\github\chatwoot n8n ai agent\chatwoot-ai-agent-hybrid.json'
)

function Patch-GateNodeCode {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Code
  )

  if ($Code -notmatch "const stopWords = new Set\(\[") {
    return $Code
  }

  if ($Code -match "'some', 'give', 'gimme', 'gime', 'list'") {
    return $Code
  }

  $anchor = "'abaixo', 'menor', 'acima', 'maior', 'entre', 'ate', 'ate', 'ate'"
  $replacement = "'abaixo', 'menor', 'acima', 'maior', 'entre', 'ate', 'ate', 'ate',`n  'some', 'give', 'gimme', 'gime', 'list', 'lists', 'catalog', 'catalogue', 'catalogo', 'option', 'options',`n  'suggest', 'suggestion', 'suggestions', 'recommend', 'recommendation', 'recommendations', 'available', 'availability',`n  'disponivel', 'disponiveis', 'mostrar', 'mostre', 'sugira', 'sugerir', 'recomende', 'lista', 'listar'"

  return $Code.Replace($anchor, $replacement)
}

function Patch-SortNodeCode {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Code
  )

  if ($Code -notmatch 'const queryText = hasTextQuery') {
    return $Code
  }

  $Code = $Code -replace "`r`n", "`n"

  $singleSynonymBlock = @'
const synonymGroups = [
  ['vitamin', 'vitamins', 'vitamina', 'vitaminas', 'suplemento', 'suplementos'],
  ['pregnancy', 'pregnant', 'fertility', 'fertile', 'gravidez', 'gestante', 'gestacao', 'concepcao', 'preconcepcao', 'engravidar'],
  ['lubricant', 'lubrificante', 'lubrificantes'],
  ['omega', 'omega3', 'dha']
];
const expandTokenVariants = (token) => {
  const normalized = normalizeText(token);
  const variants = new Set([normalized]);
  if (!normalized) {
    return [];
  }

  if (normalized.endsWith('s') && normalized.length > 3) {
    variants.add(normalized.slice(0, -1));
  } else if (!normalized.endsWith('s')) {
    variants.add(`${normalized}s`);
  }

  for (const group of synonymGroups) {
    if (group.includes(normalized)) {
      for (const alias of group) {
        variants.add(alias);
      }
    }
  }

  return [...variants].filter(Boolean);
};
'@

  $queryPrefixPattern = "(?s)(const queryText = hasTextQuery\s+  \? normalizeText\(supportContext\.productSearchTerm \|\| queryTokens\.join\(' '\)\)\s+  : '';\s*)"
  if ($Code -match $queryPrefixPattern) {
    $queryPrefix = [regex]::Match($Code, $queryPrefixPattern).Groups[1].Value
    $productLookupMarker = "if (!productLookupRequested)"
    $firstSynonymIndex = $Code.IndexOf("const synonymGroups = [")
    $productLookupIndex = $Code.IndexOf($productLookupMarker)

    if ($firstSynonymIndex -ge 0 -and $productLookupIndex -gt $firstSynonymIndex) {
      $prefix = $Code.Substring(0, $firstSynonymIndex)
      $suffix = $Code.Substring($productLookupIndex)
      $Code = $prefix + $singleSynonymBlock + "`n" + $suffix
    } elseif ($productLookupIndex -gt 0) {
      $Code = [regex]::Replace(
        $Code,
        $queryPrefixPattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
          param($m)
          $m.Groups[1].Value + $singleSynonymBlock + "`n"
        },
        1
      )
    }
  }

  $oldScoreLoop = @'
  let fieldHits = 0;
  if (hasTextQuery) {
    for (const token of queryTokens) {
      if (fields.title.split(/\s+/).includes(token)) {
        fieldHits += 1;
        score += 220;
      } else if (fields.title.includes(token)) {
        fieldHits += 1;
        score += 170;
      } else if (fields.url.includes(token)) {
        fieldHits += 1;
        score += 120;
      } else if (fields.sku.includes(token)) {
        fieldHits += 1;
        score += 90;
      } else if (fields.tags.includes(token) || fields.manufacturer.includes(token)) {
        fieldHits += 1;
        score += 70;
      } else if (fields.summary.includes(token)) {
        fieldHits += 1;
        score += 25;
      }
    }

    if (queryTokens.length > 0 && fieldHits === queryTokens.length) {
      score += 260;
    }
    if (queryTokens.length > 0 && fieldHits === 0) {
      score -= 120;
    }
  }
'@

  $newScoreLoop = @'
  let fieldHits = 0;
  if (hasTextQuery) {
    const titleWords = fields.title.split(/\s+/).filter(Boolean);
    for (const token of queryTokens) {
      const variants = expandTokenVariants(token);
      if (variants.some((variant) => titleWords.includes(variant))) {
        fieldHits += 1;
        score += 220;
      } else if (variants.some((variant) => fields.title.includes(variant))) {
        fieldHits += 1;
        score += 170;
      } else if (variants.some((variant) => fields.url.includes(variant))) {
        fieldHits += 1;
        score += 120;
      } else if (variants.some((variant) => fields.sku.includes(variant))) {
        fieldHits += 1;
        score += 90;
      } else if (variants.some((variant) => fields.tags.includes(variant) || fields.manufacturer.includes(variant))) {
        fieldHits += 1;
        score += 70;
      } else if (variants.some((variant) => fields.summary.includes(variant))) {
        fieldHits += 1;
        score += 25;
      }
    }

    if (queryTokens.length > 0 && fieldHits === queryTokens.length) {
      score += 260;
    }
    if (queryTokens.length > 0 && fieldHits === 0) {
      score -= 120;
    }
  }
'@

  if ($Code.Contains($oldScoreLoop)) {
    $Code = [regex]::Replace($Code, [regex]::Escape($oldScoreLoop), [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $newScoreLoop }, 1)
  }

  return ($Code -replace "`n", "`r`n")
}

foreach ($path in $targetPaths) {
  if (-not (Test-Path $path)) {
    continue
  }

  $json = Get-Content -Raw $path | ConvertFrom-Json

  $gateNode = $json.nodes | Where-Object { $_.name -like 'Gate Test Contact*' } | Select-Object -First 1
  if ($gateNode -and $gateNode.parameters.jsCode) {
    $gateNode.parameters.jsCode = Patch-GateNodeCode -Code ([string]$gateNode.parameters.jsCode)
  }

  $sortNode = $json.nodes | Where-Object { $_.name -like 'Sort Product Matches*' } | Select-Object -First 1
  if ($sortNode -and $sortNode.parameters.jsCode) {
    $sortNode.parameters.jsCode = Patch-SortNodeCode -Code ([string]$sortNode.parameters.jsCode)
  }

  $json | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding UTF8
  Write-Output "Patched $path"
}
