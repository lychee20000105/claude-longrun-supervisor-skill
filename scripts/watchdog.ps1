param(
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [int]$CheckSeconds = 1200,
  [int]$FastCheckSeconds = 300,
  [int]$QuietCheckSeconds = 1800,
  [switch]$FixedCheck
)

$ErrorActionPreference = 'Continue'
$StatusFile = Join-Path $OutputRoot 'longrun-status.json'
$LogDir = Join-Path $OutputRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir 'watchdog.log'
$PidFile = Join-Path $OutputRoot 'watchdog.pid'
$PID | Set-Content -LiteralPath $PidFile -Encoding UTF8

function Get-WatchDelaySeconds($status) {
  if ($FixedCheck) { return [Math]::Max(30, $CheckSeconds) }
  if (-not $status) { return [Math]::Max(60, $CheckSeconds) }
  if ($status.state -in @('auditing','decomposing','draining','final_audit') -or $status.status -in @('auditing','decomposing','draining','final_audit')) {
    return [Math]::Max(30, $FastCheckSeconds)
  }
  if ($status.note -match '(?i)failed|fatal|error|empty|stuck|invalid') { return [Math]::Max(30, $FastCheckSeconds) }
  return [Math]::Max(60, $QuietCheckSeconds)
}

function Write-WatchLog([string]$Message) {
  Add-Content -LiteralPath $LogFile -Value ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss K') + '] ' + $Message) -Encoding UTF8
}
Write-WatchLog 'watchdog started'
$status = $null
while ($true) {
  Start-Sleep -Seconds (Get-WatchDelaySeconds $status)
  if (-not (Test-Path -LiteralPath $StatusFile)) { continue }
  try {
    $status = Get-Content -LiteralPath $StatusFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($status.state -eq 'completed') {
      Write-WatchLog 'supervisor completed; watchdog exits'
      break
    }
    foreach ($pid in @($status.workerPids)) {
      if (-not $pid) { continue }
      $proc = Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
      if (-not $proc) { continue }
      Write-WatchLog "observed active worker pid=$pid state=$($status.state); no kill without explicit stuck evidence"
    }
  } catch {
    Write-WatchLog ('error: ' + $_.Exception.Message)
  }
}