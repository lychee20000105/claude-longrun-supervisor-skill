param(
  [Parameter(Mandatory=$true)][string]$Repo,
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [string]$Objective = ''
)

$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath $Repo
$RoundsDir = Join-Path $OutputRoot 'rounds'
$AuditsDir = Join-Path $OutputRoot 'audits'
$TestsDir = Join-Path $OutputRoot 'test-results'
$Summary = Join-Path $OutputRoot 'final-summary.md'
$StatusFile = Join-Path $OutputRoot 'longrun-status.json'
$rounds = @(Get-ChildItem -LiteralPath $RoundsDir -Filter 'round*-output.md' -File -ErrorAction SilentlyContinue | Sort-Object Name)
$audits = @(Get-ChildItem -LiteralPath $AuditsDir -Filter '*audit.md' -File -ErrorAction SilentlyContinue | Sort-Object Name)
$tests = @(Get-ChildItem -LiteralPath $TestsDir -File -ErrorAction SilentlyContinue | Sort-Object Name)
$gitStatus = ''
try { $gitStatus = git -c safe.directory=* status --short | Out-String } catch { $gitStatus = 'git status unavailable: ' + $_.Exception.Message }
$diffCheck = ''
try { $diffCheck = git -c safe.directory=* diff --check 2>&1 | Out-String } catch { $diffCheck = 'git diff --check unavailable: ' + $_.Exception.Message }
$statusText = if (Test-Path -LiteralPath $StatusFile) { Get-Content -LiteralPath $StatusFile -Raw -Encoding UTF8 } else { '{}' }
@"
# Final Long-Run Summary

## Objective

$Objective

## Status

````json
$statusText
````

## Artifacts

- Output root: `$OutputRoot`
- Worker outputs: $($rounds.Count)
- Audit reports: $($audits.Count)
- Test/result files: $($tests.Count)

## Git Status

````text
$gitStatus
````

## Diff Check

````text
$diffCheck
````

## Remaining Required Review

- Read latest audit report.
- Confirm any commits/dependencies/system config changes recorded by workers.
- Confirm manual environment checks that cannot be proven locally.
- Produce user-facing summary.
"@ | Set-Content -LiteralPath $Summary -Encoding UTF8
Write-Output $Summary