param(
  [Parameter(Mandatory=$true)][string]$Repo,
  [Parameter(Mandatory=$true)][string]$PromptFile,
  [Parameter(Mandatory=$true)][string]$OutputFile,
  [Parameter(Mandatory=$true)][string]$StderrFile,
  [string]$ClaudeCommand = 'claude',
  [string]$PidFile = '',
  [switch]$NoBypassPermissions
)

$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath $Repo
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputFile),(Split-Path -Parent $StderrFile) | Out-Null

$runner = Join-Path (Split-Path -Parent $StderrFile) ('runner-' + [IO.Path]::GetFileNameWithoutExtension($OutputFile) + '.ps1')
$permissionArgs = if ($NoBypassPermissions) { '' } else { '--permission-mode bypassPermissions' }
@"
`$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath '$Repo'
`$prompt = Get-Content -LiteralPath '$PromptFile' -Raw -Encoding UTF8
& '$ClaudeCommand' -p $permissionArgs --output-format text `$prompt
"@ | Set-Content -LiteralPath $runner -Encoding UTF8

$proc = Start-Process -FilePath 'powershell.exe' `
  -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner) `
  -WorkingDirectory $Repo `
  -RedirectStandardOutput $OutputFile `
  -RedirectStandardError $StderrFile `
  -WindowStyle Hidden `
  -PassThru

if ($PidFile) { $proc.Id | Set-Content -LiteralPath $PidFile -Encoding UTF8 }

[pscustomobject]@{
  pid = $proc.Id
  runner = $runner
  prompt = $PromptFile
  output = $OutputFile
  stderr = $StderrFile
} | ConvertTo-Json -Depth 4