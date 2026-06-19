param(
  [Parameter(Mandatory=$true)][string]$Repo,
  [Parameter(Mandatory=$true)][string]$Objective,
  [double]$Hours = 12,
  [string]$OutputRoot = '',
  [int]$StatusCheckMinutes = 20,
  [int]$FastStatusCheckMinutes = 5,
  [int]$QuietStatusCheckMinutes = 30,
  [switch]$FixedStatusCheck,
  [int]$AuditEveryBatches = 1,
  [int]$MaxParallelWorkers = 0,
  [string]$ClaudeCommand = 'claude',
  [switch]$NoBypassPermissions,
  [switch]$AllowOverlappingWriteScopes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SkillRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$RunRoundScript = Join-Path $SkillRoot 'scripts\run_round.ps1'
$ParsePlanScript = Join-Path $SkillRoot 'scripts\parse_decomposition_plan.ps1'
$ParallelScript = Join-Path $SkillRoot 'scripts\start_parallel_round.ps1'
$FinalAuditScript = Join-Path $SkillRoot 'scripts\final_audit.ps1'

foreach($required in @($RunRoundScript,$ParsePlanScript,$ParallelScript,$FinalAuditScript)) {
  if (-not (Test-Path -LiteralPath $required)) { throw "Required script not found: $required" }
}
if (-not (Test-Path -LiteralPath $Repo)) { throw "Repo not found: $Repo" }


function Get-StatusCheckSeconds {
  param(
    [int]$Batch = 0,
    [string]$State = 'running',
    [switch]$HadSignal
  )
  if ($FixedStatusCheck) { return [Math]::Max(30, $StatusCheckMinutes * 60) }
  if ($HadSignal -or $State -in @('decomposing','auditing','draining','final_audit')) { return [Math]::Max(30, $FastStatusCheckMinutes * 60) }
  if ($Batch -le 1) { return [Math]::Max(60, $StatusCheckMinutes * 60) }
  return [Math]::Max(60, $QuietStatusCheckMinutes * 60)
}

function Resolve-OutputRoot {
  param([string]$RepoPath,[string]$Requested)
  if (-not [string]::IsNullOrWhiteSpace($Requested)) {
    New-Item -ItemType Directory -Path $Requested -Force | Out-Null
    return (Resolve-Path -LiteralPath $Requested).Path
  }
  $docsMaintenance = Join-Path $RepoPath 'docs\maintenance'
  if (Test-Path -LiteralPath $docsMaintenance) { return (Resolve-Path -LiteralPath $docsMaintenance).Path }
  $gitDir = Join-Path $RepoPath '.git'
  if (Test-Path -LiteralPath $gitDir) {
    $longrun = Join-Path $RepoPath '.longrun'
    New-Item -ItemType Directory -Path $longrun -Force | Out-Null
    return (Resolve-Path -LiteralPath $longrun).Path
  }
  $work = Join-Path (Get-Location).Path 'work\longrun'
  New-Item -ItemType Directory -Path $work -Force | Out-Null
  return (Resolve-Path -LiteralPath $work).Path
}

$Repo = (Resolve-Path -LiteralPath $Repo).Path
$OutputRoot = Resolve-OutputRoot -RepoPath $Repo -Requested $OutputRoot
$BatchesDir = Join-Path $OutputRoot 'decomposed-batches'
$DecompDir = Join-Path $OutputRoot 'decompositions'
$AuditsDir = Join-Path $OutputRoot 'audits'
$LogsDir = Join-Path $OutputRoot 'logs'
foreach($dir in @($BatchesDir,$DecompDir,$AuditsDir,$LogsDir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$StatusFile = Join-Path $OutputRoot 'decomposed-longrun-status.json'
$HeartbeatFile = Join-Path $OutputRoot 'decomposed-longrun-heartbeat.md'
$ProgressFile = Join-Path $OutputRoot 'decomposed-longrun-progress.md'
$TargetEndAt = (Get-Date).AddHours($Hours)
$LogFile = Join-Path $LogsDir 'decomposed-supervisor.log'

function Write-Log([string]$Message) {
  $line = "{0} {1}" -f (Get-Date).ToString('o'), $Message
  Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Write-State {
  param([string]$State,[int]$Batch,[string]$Message,[string]$CurrentArtifact = '')
  $stateObject = [pscustomobject]@{
    state = $State
    objective = $Objective
    repo = $Repo
    output_root = $OutputRoot
    batch = $Batch
    current_artifact = $CurrentArtifact
    message = $Message
    target_end_at = $TargetEndAt.ToString('o')
    updated_at = (Get-Date).ToString('o')
  }
  $stateObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StatusFile -Encoding UTF8
  @"
# Decomposed Longrun Heartbeat

- State: $State
- Batch: $Batch
- Updated: $((Get-Date).ToString('o'))
- Target end: $($TargetEndAt.ToString('o'))
- Message: $Message
- Current artifact: $CurrentArtifact
"@ | Set-Content -LiteralPath $HeartbeatFile -Encoding UTF8
}

function Get-RecentContext([int]$Batch) {
  $context = @()
  $context += "## Current Time"
  $context += (Get-Date).ToString('o')
  $context += ""
  $context += "## Git Status"
  try { $context += (& git -C $Repo status --short 2>&1 | Out-String).Trim() } catch { $context += "git status unavailable: $($_.Exception.Message)" }
  $previousManifest = Get-ChildItem -LiteralPath $BatchesDir -Recurse -Filter manifest.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($previousManifest) {
    $context += ""
    $context += "## Previous Manifest"
    $context += $previousManifest.FullName
    try {
      $manifest = Get-Content -LiteralPath $previousManifest.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
      $context += ('status=' + $manifest.status + '; running=' + (@($manifest.running).Count) + '; completed=' + (@($manifest.completed).Count) + '; remaining=' + (@($manifest.remaining).Count))
    } catch {
      $context += 'manifest summary unavailable; inspect only if needed'
    }
  }
  $previousAudit = Get-ChildItem -LiteralPath $AuditsDir -Filter '*-audit.md' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($previousAudit) {
    $context += ""
    $context += "## Previous Audit"
    $context += $previousAudit.FullName
    $auditText = Get-Content -LiteralPath $previousAudit.FullName -Raw -Encoding UTF8
    if ($auditText -match '(?s)## Supervisor Digest\s*(.*?)(\r?\n## |\z)') {
      $auditText = $Matches[0]
    } elseif ($auditText.Length -gt 1600) {
      $auditText = $auditText.Substring(0, 1600)
    }
    $context += $auditText
  }
  return ($context -join [Environment]::NewLine)
}

function New-DecompositionPrompt([int]$Batch) {
  $file = Join-Path $DecompDir ('batch{0:D3}-decomposition-prompt.md' -f $Batch)
  $recentContext = Get-RecentContext -Batch $Batch
  @"
# Decomposition Subagent Task

You are the decomposition subagent for a long-running local Claude CLI workflow.

Do not implement code. Do not run tests. Do not modify files. Your only job is to split the next useful work into Claude CLI worker tasks.

## Objective
$Objective

## Repository
$Repo

## Output Root
$OutputRoot

## Batch
$Batch

## Rules

- Produce tasks that are each intended to finish within 30 minutes.
- Prefer parallel tasks with non-overlapping write scopes.
- Use narrow `write_scopes`.
- Use `depends_on` when tasks must be sequential.
- Include at least one audit or validation task when implementation/documentation tasks are proposed.
- If there is nothing useful left to do, produce one read-only audit/report task explaining completion and remaining risks.
- Do not request push, deploy, publish, permanent deletion, secrets logging, production data mutation, `git reset --hard`, or `git clean -fd`.
- If system config may be changed by a worker, the worker prompt must require rollback documentation in `system-config-changes.md`.

## Required Output

First write no more than 8 concise bullets of reasoning.

Then output exactly one fenced `json` block following this schema:

```json
{
  "objective": "Original objective",
  "notes": "Sequencing/risk notes",
  "tasks": [
    {
      "id": "task-001",
      "title": "Short title",
      "prompt": "Complete Claude CLI worker prompt with scope, deliverables, validation, and reporting requirements.",
      "write_scopes": ["relative/path/or/folder/"],
      "depends_on": [],
      "max_minutes": 30
    }
  ]
}
```

## Recent Context
$recentContext

Use recent context as a compact hint only. Do not read raw manifests, full outputs, or full diffs unless needed for a specific blocker, failed validation, safety issue, or missing evidence.
"@ | Set-Content -LiteralPath $file -Encoding UTF8
  return $file
}

function Invoke-ClaudePromptAndWait {
  param(
    [string]$PromptFile,
    [string]$OutputFile,
    [string]$StderrFile,
    [string]$PidFile,
    [string]$State,
    [int]$Batch,
    [string]$Description
  )
  $args = @('-Repo',$Repo,'-PromptFile',$PromptFile,'-OutputFile',$OutputFile,'-StderrFile',$StderrFile,'-ClaudeCommand',$ClaudeCommand,'-PidFile',$PidFile)
  if ($NoBypassPermissions) { $args += '-NoBypassPermissions' }
  $launch = & $RunRoundScript @args | ConvertFrom-Json
  $pid = [int]$launch.pid
  Write-Log "$Description started pid=$pid output=$OutputFile"
  Write-State $State $Batch "$Description running." $OutputFile
  while ($true) {
    Start-Sleep -Seconds (Get-StatusCheckSeconds -Batch $Batch -State $State)
    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if (-not $proc) { break }
    Write-State $State $Batch "$Description still active." $OutputFile
  }
  Write-Log "$Description finished"
  return $OutputFile
}

function New-AuditPrompt([int]$Batch,[string]$ManifestFile) {
  $file = Join-Path $AuditsDir ('batch{0:D3}-audit-prompt.md' -f $Batch)
  @"
# Claude CLI Audit Round

You are an audit worker for a decomposed long-running local task.

## Objective
$Objective

## Repository
$Repo

## Batch
$Batch

## Manifest
$ManifestFile

## Instructions

Read the manifest, worker prompts, worker outputs, stderr logs, repository diff, relevant tests/build logs, and progress files.

Do not do broad implementation work. Only write an audit report unless a tiny documentation fix is necessary and clearly documented.

Audit report must include:

- Batch status.
- Worker outputs reviewed.
- Files changed.
- Suspicious or conflicting edits.
- Test/build/lint status.
- Dependency installs.
- Web searches/sources.
- System config changes and rollback notes.
- Git commits created.
- Remaining risks.
- Whether the next batch should continue implementation, switch to regression/docs, or enter final audit.
"@ | Set-Content -LiteralPath $file -Encoding UTF8
  return $file
}

@"
# Decomposed Longrun Progress

- Objective: $Objective
- Repo: $Repo
- Output root: $OutputRoot
- Started: $((Get-Date).ToString('o'))
- Target end: $($TargetEndAt.ToString('o'))

"@ | Set-Content -LiteralPath $ProgressFile -Encoding UTF8

Write-Log "started decomposed objective=$Objective targetEnd=$($TargetEndAt.ToString('o'))"
$batch = 1
Write-State 'running' $batch 'Decomposed supervisor started.'

while ($true) {
  if ((Get-Date) -ge $TargetEndAt) {
    Write-State 'draining' $batch 'Total duration reached. No new decomposition batch will start.'
    break
  }

  Write-State 'decomposing' $batch "Creating decomposition for batch $batch."
  $decompPrompt = New-DecompositionPrompt -Batch $batch
  $decompOutput = Join-Path $DecompDir ('batch{0:D3}-decomposition-output.md' -f $batch)
  $decompErr = Join-Path $LogsDir ('batch{0:D3}-decomposition-stderr.log' -f $batch)
  $decompPid = Join-Path $LogsDir ('batch{0:D3}-decomposition.pid' -f $batch)
  Invoke-ClaudePromptAndWait -PromptFile $decompPrompt -OutputFile $decompOutput -StderrFile $decompErr -PidFile $decompPid -State 'decomposing' -Batch $batch -Description "Decomposition batch $batch" | Out-Null

  $planFile = Join-Path $DecompDir ('batch{0:D3}-parallel-plan.json' -f $batch)
  try {
    & $ParsePlanScript -InputFile $decompOutput -OutputFile $planFile | Out-Null
  } catch {
    Write-Log "decomposition parse failed batch=$batch error=$($_.Exception.Message)"
    Write-State 'decomposition_failed' $batch "Could not parse decomposition output. See $decompOutput" $decompOutput
    break
  }

  Write-State 'parallel_running' $batch "Starting parallel worker batch $batch." $planFile
  $parallelArgs = @('-Repo',$Repo,'-PlanFile',$planFile,'-OutputRoot',$BatchesDir,'-ClaudeCommand',$ClaudeCommand,'-MaxParallelWorkers',$MaxParallelWorkers)
  if ($NoBypassPermissions) { $parallelArgs += '-NoBypassPermissions' }
  if ($AllowOverlappingWriteScopes) { $parallelArgs += '-AllowOverlappingWriteScopes' }
  try {
    $manifestFile = (& $ParallelScript @parallelArgs | Select-Object -Last 1)
  } catch {
    Write-Log "parallel batch failed batch=$batch error=$($_.Exception.Message)"
    Write-State 'parallel_failed' $batch "Parallel batch failed. $($_.Exception.Message)" $planFile
    break
  }

  Add-Content -LiteralPath $ProgressFile -Encoding UTF8 -Value "- Batch $batch manifest: $manifestFile"
  Write-Log "parallel batch finished batch=$batch manifest=$manifestFile"

  if (($batch % $AuditEveryBatches) -eq 0) {
    Write-State 'auditing' $batch "Auditing batch $batch." $manifestFile
    $auditPrompt = New-AuditPrompt -Batch $batch -ManifestFile $manifestFile
    $auditOutput = Join-Path $AuditsDir ('batch{0:D3}-audit.md' -f $batch)
    $auditErr = Join-Path $LogsDir ('batch{0:D3}-audit-stderr.log' -f $batch)
    $auditPid = Join-Path $LogsDir ('batch{0:D3}-audit.pid' -f $batch)
    Invoke-ClaudePromptAndWait -PromptFile $auditPrompt -OutputFile $auditOutput -StderrFile $auditErr -PidFile $auditPid -State 'auditing' -Batch $batch -Description "Audit batch $batch" | Out-Null
    Add-Content -LiteralPath $ProgressFile -Encoding UTF8 -Value "- Batch $batch audit: $auditOutput"
  }

  $batch++
}

Write-State 'final_audit' $batch 'Generating final audit.'
& $FinalAuditScript -Repo $Repo -OutputRoot $OutputRoot -Objective $Objective | Out-Null
Write-State 'completed' $batch 'Decomposed long-running task completed.'
Write-Log 'completed decomposed longrun'
Write-Output $OutputRoot