param(
  [Parameter(Mandatory=$true)][string]$InputFile,
  [Parameter(Mandatory=$true)][string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail($message) {
  Write-Error $message
  exit 1
}

if (-not (Test-Path -LiteralPath $InputFile)) { Fail "InputFile not found: $InputFile" }
$text = Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8
$jsonText = $null

$match = [regex]::Match($text, '(?s)```json\s*(\{.*?\})\s*```')
if ($match.Success) { $jsonText = $match.Groups[1].Value }

if (-not $jsonText) {
  $match = [regex]::Match($text, '(?s)<!--\s*LONGRUN_PLAN_JSON\s*-->\s*(\{.*?\})\s*<!--\s*/LONGRUN_PLAN_JSON\s*-->')
  if ($match.Success) { $jsonText = $match.Groups[1].Value }
}

if (-not $jsonText) {
  $first = $text.IndexOf('{')
  $last = $text.LastIndexOf('}')
  if ($first -ge 0 -and $last -gt $first) { $jsonText = $text.Substring($first, $last - $first + 1) }
}

if (-not $jsonText) { Fail 'No JSON object found in decomposition output.' }

try { $plan = $jsonText | ConvertFrom-Json }
catch { Fail "Invalid JSON in decomposition output: $($_.Exception.Message)" }

if (-not ($plan.PSObject.Properties.Name -contains 'tasks')) { Fail 'Plan JSON must contain a tasks array.' }
if (-not $plan.tasks -or $plan.tasks.Count -lt 1) { Fail 'Plan JSON tasks array is empty.' }

$normalizedTasks = @()
$seenIds = @{}
foreach ($task in $plan.tasks) {
  $id = [string]$task.id
  if ([string]::IsNullOrWhiteSpace($id)) { Fail 'Every task must include id.' }
  if ($seenIds.ContainsKey($id)) { Fail "Duplicate task id: $id" }
  $seenIds[$id] = $true

  $title = [string]$task.title
  $prompt = [string]$task.prompt
  if ([string]::IsNullOrWhiteSpace($title)) { Fail "Task $id must include title." }
  if ([string]::IsNullOrWhiteSpace($prompt)) { Fail "Task $id must include prompt." }

  $writeScopes = @()
  if ($task.PSObject.Properties.Name -contains 'write_scopes' -and $task.write_scopes) {
    foreach ($scope in $task.write_scopes) {
      $scopeText = ([string]$scope).Trim()
      if (-not [string]::IsNullOrWhiteSpace($scopeText)) { $writeScopes += $scopeText }
    }
  }

  $dependsOn = @()
  if ($task.PSObject.Properties.Name -contains 'depends_on' -and $task.depends_on) {
    foreach ($dep in $task.depends_on) {
      $depText = ([string]$dep).Trim()
      if (-not [string]::IsNullOrWhiteSpace($depText)) { $dependsOn += $depText }
    }
  }

  $normalizedTasks += [pscustomobject]@{
    id = $id
    title = $title
    prompt = $prompt
    write_scopes = $writeScopes
    depends_on = $dependsOn
    max_minutes = if ($task.PSObject.Properties.Name -contains 'max_minutes') { [int]$task.max_minutes } else { 30 }
  }
}

foreach ($task in $normalizedTasks) {
  foreach ($dep in $task.depends_on) {
    if (-not $seenIds.ContainsKey($dep)) { Fail "Task $($task.id) depends on unknown task: $dep" }
  }
}

$normalized = [pscustomobject]@{
  objective = if ($plan.PSObject.Properties.Name -contains 'objective') { [string]$plan.objective } else { '' }
  notes = if ($plan.PSObject.Properties.Name -contains 'notes') { [string]$plan.notes } else { '' }
  tasks = $normalizedTasks
}

$parent = Split-Path -Parent $OutputFile
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$normalized | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
Write-Output $OutputFile