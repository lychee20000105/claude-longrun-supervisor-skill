param(
  [Parameter(Mandatory=$true)][string]$Repo,
  [Parameter(Mandatory=$true)][string]$Objective,
  [double]$Hours = 12,
  [string]$OutputRoot = '',
  [int]$StatusCheckMinutes = 20,
  [int]$FastStatusCheckMinutes = 5,
  [int]$QuietStatusCheckMinutes = 30,
  [switch]$FixedStatusCheck,
  [int]$AuditEveryRounds = 3,
  [int]$NoIssueSwitchRounds = 5,
  [string]$ClaudeCommand = 'claude',
  [switch]$NoBypassPermissions
)

$ErrorActionPreference = 'Continue'
$SkillRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$RunRoundScript = Join-Path $SkillRoot 'scripts\run_round.ps1'

function Resolve-OutputRoot([string]$Repo, [string]$OutputRoot) {
  if ($OutputRoot) { return $OutputRoot }
  $docsMaint = Join-Path $Repo 'docs\maintenance'
  if (Test-Path -LiteralPath $docsMaint) { return $docsMaint }
  $gitDir = Join-Path $Repo '.git'
  if (Test-Path -LiteralPath $gitDir) { return (Join-Path $Repo '.longrun') }
  return (Join-Path (Get-Location).Path 'work\longrun')
}

function Write-Log([string]$Message) {
  $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss K') + '] ' + $Message
  Add-Content -LiteralPath $SupervisorLog -Value $line -Encoding UTF8
}


function Get-StatusCheckSeconds {
  param(
    [int]$Round = 0,
    [string]$State = 'running',
    [switch]$HadSignal
  )
  if ($FixedStatusCheck) { return [Math]::Max(30, $StatusCheckMinutes * 60) }
  if ($HadSignal -or $State -in @('auditing','draining','final_audit')) { return [Math]::Max(30, $FastStatusCheckMinutes * 60) }
  if ($Round -le 1) { return [Math]::Max(60, $StatusCheckMinutes * 60) }
  return [Math]::Max(60, $QuietStatusCheckMinutes * 60)
}

function Write-State([string]$State, [int]$Round, [string]$Note, [int[]]$WorkerPids = @()) {
  $obj = [ordered]@{
    state = $State
    round = $Round
    note = $Note
    objective = $Objective
    startedAt = $StartedAt.ToString('o')
    targetEndAt = $TargetEndAt.ToString('o')
    updatedAt = (Get-Date).ToString('o')
    supervisorPid = $PID
    workerPids = $WorkerPids
    repo = $Repo
    outputRoot = $OutputRoot
    supervisorLog = $SupervisorLog
    checkPolicy = if ($FixedStatusCheck) { 'fixed' } else { 'adaptive' }
    nextSuggestedSupervisorCheckAt = (Get-Date).AddSeconds((Get-StatusCheckSeconds -Round $Round -State $State)).ToString('o')
  }
  ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $StatusFile -Encoding UTF8
@"
# Long-Run Heartbeat

- 鐘舵€侊細$State
- 杞锛?Round
- 璇存槑锛?Note
- 寮€濮嬶細$($StartedAt.ToString('yyyy-MM-dd HH:mm:ss K'))
- 鐩爣缁撴潫锛?($TargetEndAt.ToString('yyyy-MM-dd HH:mm:ss K'))
- 鏇存柊鏃堕棿锛?(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')
- Supervisor PID锛?PID
- Worker PID锛?($WorkerPids -join ', ')
- 杈撳嚭鐩綍锛?OutputRoot
"@ | Set-Content -LiteralPath $HeartbeatFile -Encoding UTF8
}

function New-WorkerPrompt([int]$Round, [string]$Mode) {
  $promptPath = Join-Path $RoundsDir ('round{0:D3}-{1}-task.md' -f $Round,$Mode)
  $recent = Get-ChildItem -LiteralPath $RoundsDir -Filter 'round*-output.md' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3 -ExpandProperty FullName
  $recentText = if ($recent) { ($recent | ForEach-Object { '- ' + $_ }) -join "`n" } else { '- none' }
@"
# Claude CLI Worker Round $Round ($Mode)

## Objective

$Objective

## Repo

$Repo

## Output Root

$OutputRoot

## Current Mode

$Mode

## Recent Outputs

$recentText

## Rules

- You are Claude CLI, the fixed local worker.
- Do the dirty work: inspect files, run commands, edit local files when useful, install dependencies if needed, search the web if needed, and write records.
- Whoever modifies files must document the modification in this round.
- Keep work local unless explicitly authorized.
- Do not upload, deploy, publish, push, permanently delete, write secrets, mutate production data, or run destructive Git commands.
- If changing system-level config, record old value, new value, reason, validation, and rollback in `system-config-changes.md` before/with the change.
- If committing, commit only focused relevant changes and document the commit.

## Task

1. Read `resume-prompt.md`, `longrun-progress.md`, recent outputs, and recent test results if they exist.
2. Decide a small useful next task aligned with the objective and current mode.
3. Execute it locally.
4. Run relevant validation.
5. Write round output to this same output file's intended path via stdout and update maintenance files.
6. Include pass/fail counts, modified files, commands, risks, and next-round recommendation.

## Required stdout shape

- Whether code/config/docs changed.
- Modified files.
- Commands run.
- Validation results.
- Risks.
- Next recommended task.
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
  return $promptPath
}

function New-AuditPrompt([int]$Round) {
  $promptPath = Join-Path $AuditsDir ('round{0:D3}-audit-task.md' -f $Round)
  $recent = Get-ChildItem -LiteralPath $RoundsDir -Filter 'round*-output.md' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3 -ExpandProperty FullName
  $recentText = if ($recent) { ($recent | ForEach-Object { '- ' + $_ }) -join "`n" } else { '- none' }
@"
# Claude CLI Audit Round $Round

You are the audit worker. Do not continue implementation unless needed to inspect. Do dirty review work and write an audit report.

## Objective

$Objective

## Recent outputs to audit

$recentText

## Audit requirements

1. Read recent outputs, progress, test results, and git diff/status.
2. Check whether modifications are reasonable and documented.
3. Check whether validation evidence is strong enough.
4. Check for safety boundary violations.
5. Check whether next tasks should continue, rework, split, parallelize, switch to regression/documentation mode, drain, or stop.
6. Write a concise structured audit report.

## Required stdout shape

# Audit Report

## Scope
## Modification Reasonableness
## Validation Sufficiency
## Documentation Completeness
## Risks
## Decision Recommendation
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
  return $promptPath
}

Set-Location -LiteralPath $Repo
$OutputRoot = Resolve-OutputRoot $Repo $OutputRoot
$RoundsDir = Join-Path $OutputRoot 'rounds'
$AuditsDir = Join-Path $OutputRoot 'audits'
$TestsDir = Join-Path $OutputRoot 'test-results'
$LogsDir = Join-Path $OutputRoot 'logs'
New-Item -ItemType Directory -Force -Path $OutputRoot,$RoundsDir,$AuditsDir,$TestsDir,$LogsDir | Out-Null

$StartedAt = Get-Date
$TargetEndAt = $StartedAt.AddHours($Hours)
$StatusFile = Join-Path $OutputRoot 'longrun-status.json'
$HeartbeatFile = Join-Path $OutputRoot 'longrun-heartbeat.md'
$ProgressFile = Join-Path $OutputRoot 'longrun-progress.md'
$ResumeFile = Join-Path $OutputRoot 'resume-prompt.md'
$SupervisorLog = Join-Path $LogsDir ('supervisor-' + $StartedAt.ToString('yyyyMMdd-HHmmss') + '.log')
$PidFile = Join-Path $OutputRoot 'supervisor.pid'
$PID | Set-Content -LiteralPath $PidFile -Encoding UTF8

@"
# Long-Run Progress

- Objective: $Objective
- Started: $($StartedAt.ToString('yyyy-MM-dd HH:mm:ss K'))
- Target end: $($TargetEndAt.ToString('yyyy-MM-dd HH:mm:ss K'))
- Repo: $Repo
"@ | Set-Content -LiteralPath $ProgressFile -Encoding UTF8
@"
# Resume Prompt

Continue the long-running local task.

- Objective: $Objective
- Repo: $Repo
- Output root: $OutputRoot
- Status file: $StatusFile
- Progress file: $ProgressFile
"@ | Set-Content -LiteralPath $ResumeFile -Encoding UTF8

Write-Log "started objective=$Objective targetEnd=$($TargetEndAt.ToString('o'))"
$round = 1
$mode = 'fix-verify'
$noIssueRounds = 0
Write-State 'running' $round 'Supervisor started.'

while ($true) {
  $now = Get-Date
  if ($now -ge $TargetEndAt) {
    Write-State 'draining' $round 'Total duration reached. No new worker rounds will start; moving to final audit after current point.'
    break
  }

  if ($noIssueRounds -ge $NoIssueSwitchRounds) { $mode = 'regression-docs' }

  $prompt = New-WorkerPrompt $round $mode
  $output = Join-Path $RoundsDir ('round{0:D3}-output.md' -f $round)
  $stderr = Join-Path $LogsDir ('round{0:D3}-stderr.log' -f $round)
  $workerPidFile = Join-Path $LogsDir ('round{0:D3}.pid' -f $round)
  $args = @('-Repo',$Repo,'-PromptFile',$prompt,'-OutputFile',$output,'-StderrFile',$stderr,'-ClaudeCommand',$ClaudeCommand,'-PidFile',$workerPidFile)
  if ($NoBypassPermissions) { $args += '-NoBypassPermissions' }
  $launch = & $RunRoundScript @args | ConvertFrom-Json
  $workerPid = [int]$launch.pid
  Write-Log "round $round started pid=$workerPid output=$output"
  Write-State 'running' $round "Worker round $round running." @($workerPid)

  while ($true) {
    Start-Sleep -Seconds (Get-StatusCheckSeconds -Round $round -State 'running')
    $proc = Get-Process -Id $workerPid -ErrorAction SilentlyContinue
    if (-not $proc) { break }
    Write-State 'running' $round "Worker round $round still active." @($workerPid)
  }
  Write-Log "round $round finished"

  $outText = if (Test-Path -LiteralPath $output) { Get-Content -LiteralPath $output -Raw -Encoding UTF8 } else { '' }
  $changed = $outText -match '(?i)modified files|code changed|changed files|files changed|git status|git diff|created|updated|patched'
  $failed = $outText -match '(?i)fail|failed|failure|error|exception|traceback|cannot|unable|timed out'
  if ($changed -or $failed) { $noIssueRounds = 0 } else { $noIssueRounds++ }

  if (($round % $AuditEveryRounds -eq 0) -or $changed -or $failed) {
    Write-State 'auditing' $round "Audit round for worker round $round."
    $auditPrompt = New-AuditPrompt $round
    $auditOutput = Join-Path $AuditsDir ('round{0:D3}-audit.md' -f $round)
    $auditErr = Join-Path $LogsDir ('round{0:D3}-audit-stderr.log' -f $round)
    $auditPidFile = Join-Path $LogsDir ('round{0:D3}-audit.pid' -f $round)
    $aargs = @('-Repo',$Repo,'-PromptFile',$auditPrompt,'-OutputFile',$auditOutput,'-StderrFile',$auditErr,'-ClaudeCommand',$ClaudeCommand,'-PidFile',$auditPidFile)
    if ($NoBypassPermissions) { $aargs += '-NoBypassPermissions' }
    $auditLaunch = & $RunRoundScript @aargs | ConvertFrom-Json
    $auditPid = [int]$auditLaunch.pid
    Write-Log "audit for round $round started pid=$auditPid"
    while ($true) {
      Start-Sleep -Seconds (Get-StatusCheckSeconds -Round $round -State 'auditing' -HadSignal)
      $aproc = Get-Process -Id $auditPid -ErrorAction SilentlyContinue
      if (-not $aproc) { break }
      Write-State 'auditing' $round "Audit for round $round still active." @($auditPid)
    }
    Write-Log "audit for round $round finished"
  }

  $round++
}

Write-State 'final_audit' $round 'Generating final audit.'
$FinalAuditScript = Join-Path $SkillRoot 'scripts\final_audit.ps1'
& $FinalAuditScript -Repo $Repo -OutputRoot $OutputRoot -Objective $Objective | Out-Null
Write-State 'completed' $round 'Long-running task completed.'
Write-Log 'completed'
