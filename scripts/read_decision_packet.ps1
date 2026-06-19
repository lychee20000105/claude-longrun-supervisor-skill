param(
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [int]$DigestChars = 1600,
  [int]$MaxRecentDigests = 3
)

$ErrorActionPreference = 'Continue'

function Read-JsonFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return @{ error = $_.Exception.Message; path = $Path } }
}

function Get-DigestFromFile([string]$Path, [int]$MaxChars) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $digest = $null
  if ($text -match '(?s)## Supervisor Digest\s*(.*?)(\r?\n## |\z)') {
    $digest = $Matches[1].Trim()
  } elseif ($text.Length -gt 0) {
    $digest = $text.Substring(0, [Math]::Min($text.Length, $MaxChars)).Trim()
  }
  if ($digest -and $digest.Length -gt $MaxChars) { $digest = $digest.Substring(0, $MaxChars) }
  return $digest
}

$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
$statusPath = Join-Path $OutputRoot 'longrun-status.json'
$tokenPath = Join-Path $OutputRoot 'token-budget-summary.json'
$finalPath = Join-Path $OutputRoot 'final-summary.md'

$recentFiles = @()
foreach ($subdir in @('audits','rounds','batches')) {
  $dir = Join-Path $OutputRoot $subdir
  if (Test-Path -LiteralPath $dir) {
    $recentFiles += Get-ChildItem -LiteralPath $dir -Recurse -File -Include '*.md','*.txt' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First $MaxRecentDigests
  }
}
$recentFiles = $recentFiles | Sort-Object LastWriteTime -Descending | Select-Object -First $MaxRecentDigests

$packet = [ordered]@{
  outputRoot = $OutputRoot
  generatedAt = (Get-Date).ToString('o')
  tokenBudgetSummary = Read-JsonFile $tokenPath
  status = Read-JsonFile $statusPath
  finalSummaryExists = Test-Path -LiteralPath $finalPath
  recentDigests = @($recentFiles | ForEach-Object {
    [ordered]@{
      path = $_.FullName
      updatedAt = $_.LastWriteTime.ToString('o')
      digest = Get-DigestFromFile $_.FullName $DigestChars
    }
  })
  readPolicy = 'Supervisor should stop here unless decisionNeeded is not none, validation failed, publish blocked, safety risk exists, or user asks for detailed evidence.'
}

$packet | ConvertTo-Json -Depth 12
