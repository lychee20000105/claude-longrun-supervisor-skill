param(
  [Parameter(Mandatory=$true)][string]$Repo,
  [Parameter(Mandatory=$true)][string]$PlanFile,
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [string]$ClaudeCommand = 'claude',
  [int]$MaxParallelWorkers = 0,
  [switch]$NoBypassPermissions,
  [switch]$AllowOverlappingWriteScopes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SkillRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$RunRoundScript = Join-Path $SkillRoot 'scripts\run_round.ps1'
if (-not (Test-Path -LiteralPath $RunRoundScript)) { throw "run_round.ps1 not found: $RunRoundScript" }
if (-not (Test-Path -LiteralPath $PlanFile)) { throw "PlanFile not found: $PlanFile" }
if (-not (Test-Path -LiteralPath $Repo)) { throw "Repo not found: $Repo" }

$plan = Get-Content -LiteralPath $PlanFile -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $plan.tasks -or $plan.tasks.Count -lt 1) { throw 'Plan has no tasks.' }

$ParallelRoot = Join-Path $OutputRoot ('parallel-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$PromptDir = Join-Path $ParallelRoot 'prompts'
$OutputDir = Join-Path $ParallelRoot 'outputs'
$LogDir = Join-Path $ParallelRoot 'logs'
foreach($dir in @($ParallelRoot,$PromptDir,$OutputDir,$LogDir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$ManifestFile = Join-Path $ParallelRoot 'manifest.json'

function Normalize-Scope([string]$scope) {
  $value = $scope.Trim().Replace('\\','/')
  while($value.StartsWith('./')) { $value = $value.Substring(2) }
  return $value.TrimEnd('/')
}

function Scopes-Overlap([string]$left, [string]$right) {
  if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) { return $false }
  $a = Normalize-Scope $left
  $b = Normalize-Scope $right
  if ($a -eq '*' -or $b -eq '*') { return $true }
  if ($a -eq $b) { return $true }
  return ($a.StartsWith($b + '/') -or $b.StartsWith($a + '/'))
}

if (-not $AllowOverlappingWriteScopes) {
  $tasksForCheck = @($plan.tasks)
  for($i=0; $i -lt $tasksForCheck.Count; $i++) {
    for($j=$i+1; $j -lt $tasksForCheck.Count; $j++) {
      $leftScopes = @($tasksForCheck[$i].write_scopes)
      $rightScopes = @($tasksForCheck[$j].write_scopes)
      foreach($left in $leftScopes) {
        foreach($right in $rightScopes) {
          if (Scopes-Overlap ([string]$left) ([string]$right)) {
            throw "Overlapping write scopes between $($tasksForCheck[$i].id) and $($tasksForCheck[$j].id): '$left' vs '$right'. Split tasks or rerun with -AllowOverlappingWriteScopes after review."
          }
        }
      }
    }
  }
}

$remaining = @{}
$completed = @{}
$running = @{}
foreach($task in @($plan.tasks)) { $remaining[[string]$task.id] = $task }
$launchRecords = @()

function Dependencies-Complete($task, $completedMap) {
  foreach($dep in @($task.depends_on)) {
    if (-not $completedMap.ContainsKey([string]$dep)) { return $false }
  }
  return $true
}

function Safe-FilePart([string]$value) {
  return ($value -replace '[^A-Za-z0-9_.-]', '_')
}

function Start-Task($task) {
  $idPart = Safe-FilePart ([string]$task.id)
  $promptFile = Join-Path $PromptDir ($idPart + '.md')
  $outputFile = Join-Path $OutputDir ($idPart + '-output.md')
  $stderrFile = Join-Path $LogDir ($idPart + '-stderr.log')
  $pidFile = Join-Path $LogDir ($idPart + '.pid')

  $scopesText = (@($task.write_scopes) | ForEach-Object { "- $_" }) -join [Environment]::NewLine
  $depsText = (@($task.depends_on) | ForEach-Object { "- $_" }) -join [Environment]::NewLine
  if (-not $scopesText) { $scopesText = '- none declared; do not edit files unless the prompt explicitly requires it' }
  if (-not $depsText) { $depsText = '- none' }

  @"
# Claude CLI Parallel Worker Task

You are one Claude CLI worker inside a supervised long-running local task.

## Task ID
$($task.id)

## Title
$($task.title)

## Repository
$Repo

## Write scopes
$scopesText

## Dependencies
$depsText

## Rules

- Only work inside the declared write scopes unless the task is read-only.
- Do not revert or overwrite work from other workers.
- If you need a scope outside your assignment, stop and document the request.
- Document every modified file, command, validation result, risk, and next step in your output.
- Do not push, deploy, publish, permanently delete, expose secrets, or mutate production data.
- If you install dependencies, run web searches, modify system config, or create commits, document exact commands and rollback notes.

## Task Prompt
$($task.prompt)
"@ | Set-Content -LiteralPath $promptFile -Encoding UTF8

  $args = @('-Repo',$Repo,'-PromptFile',$promptFile,'-OutputFile',$outputFile,'-StderrFile',$stderrFile,'-ClaudeCommand',$ClaudeCommand,'-PidFile',$pidFile)
  if ($NoBypassPermissions) { $args += '-NoBypassPermissions' }
  $launch = & $RunRoundScript @args | ConvertFrom-Json
  return [pscustomobject]@{
    id = [string]$task.id
    title = [string]$task.title
    pid = [int]$launch.pid
    prompt_file = $promptFile
    output_file = $outputFile
    stderr_file = $stderrFile
    pid_file = $pidFile
    started_at = (Get-Date).ToString('o')
    completed_at = $null
    exit_observed = $false
  }
}

while($remaining.Count -gt 0 -or $running.Count -gt 0) {
  $capacity = if ($MaxParallelWorkers -le 0) { [int]::MaxValue } else { $MaxParallelWorkers - $running.Count }
  if ($capacity -gt 0) {
    $readyIds = @()
    foreach($entry in $remaining.GetEnumerator()) {
      if (Dependencies-Complete $entry.Value $completed) { $readyIds += [string]$entry.Key }
    }
    foreach($id in $readyIds | Sort-Object) {
      if ($capacity -le 0) { break }
      $task = $remaining[$id]
      $record = Start-Task $task
      $running[$id] = $record
      $launchRecords += $record
      $remaining.Remove($id)
      $capacity--
    }
  }

  foreach($id in @($running.Keys)) {
    $record = $running[$id]
    $proc = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
    if (-not $proc) {
      $record.completed_at = (Get-Date).ToString('o')
      $record.exit_observed = $true
      $completed[$id] = $record
      $running.Remove($id)
    }
  }

  [pscustomobject]@{
    plan_file = $PlanFile
    repo = $Repo
    output_root = $ParallelRoot
    status = if ($remaining.Count -eq 0 -and $running.Count -eq 0) { 'completed' } else { 'running' }
    max_parallel_workers = $MaxParallelWorkers
    remaining = @($remaining.Keys)
    running = @($running.Keys)
    completed = @($completed.Keys)
    records = $launchRecords
    updated_at = (Get-Date).ToString('o')
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ManifestFile -Encoding UTF8

  if ($remaining.Count -eq 0 -and $running.Count -eq 0) { break }
  Start-Sleep -Seconds 15
}

Write-Output $ManifestFile