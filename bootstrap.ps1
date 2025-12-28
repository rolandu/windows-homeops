<#
bootstrap.ps1
- Idempotent baseline bootstrap for Windows
- Installs Chocolatey if missing
- Installs a list of packages (Chocolatey)
- Installs a list of packages (winget)
- Upgrades Chocolatey packages and runs winget --all
- Applies the security/privacy baseline from lib/security_privacy.ps1

Editable areas:
- Update `settings.psd1` (or pass -ConfigPath) to control Chocolatey/winget packages.

Run elevated (Admin) or via Scheduled Task with highest privileges.
#>

[CmdletBinding()]
param(
  # Optional override path for package settings (PowerShell data file)
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSScriptRoot) { $ScriptRoot = $PSScriptRoot } else { $ScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent }

. (Join-Path $ScriptRoot 'lib\common.ps1')
. (Join-Path $ScriptRoot 'lib\choco.ps1')
. (Join-Path $ScriptRoot 'lib\winget.ps1')
. (Join-Path $ScriptRoot 'lib\scripts.ps1')
. (Join-Path $ScriptRoot 'lib\security_privacy.ps1')

$LogPath = Initialize-Logging -ScriptRoot $ScriptRoot -Prefix 'bootstrap'
# Use a separate transcript file so the structured log stays writable
$TranscriptPath = "$LogPath.transcript"
$Script:OperationResults = @()
$caughtError = $null

# Load package configuration
if (-not $ConfigPath) { $ConfigPath = Join-Path $ScriptRoot 'settings.psd1' }
if (-not (Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$config = Import-PowerShellDataFile -Path $ConfigPath
$Packages = $config.Packages
$WingetPackages = $config.WingetPackages

$transcriptStarted = $false
try {
  try {
    Start-Transcript -Path $TranscriptPath -Append | Out-Null
    $transcriptStarted = $true
  } catch {
    Write-Warning "Unable to start transcript logging to ${TranscriptPath}: $($_)"
  }

  try {
    Assert-Admin
    Write-Host ""

    # Install/upgrade via choco
    Write-Host "Starting Chocolatey tasks..." -ForegroundColor Cyan
    Ensure-Chocolatey
    Write-Host ""
    Ensure-ChocoDefaults
    Write-Host ""
    Install-Packages-WithChoco -pkgs $Packages
    Write-Host ""
    Upgrade-All-Choco
    Write-Host ""

    # Install/upgrade via winget
    Write-Host "Starting winget tasks..." -ForegroundColor Cyan
    Install-Packages-WithWinget -pkgs $WingetPackages
    Write-Host ""
    Upgrade-All-WithWinget
    Write-Host ""

    # Security/privacy baseline
    Write-Host "Applying security/privacy baseline..." -ForegroundColor Cyan
    Invoke-SecurityPrivacyBaseline
    Write-Host ""
  } catch {
    $caughtError = $_
    Write-Warning "Bootstrap encountered an error: $($_)"
    Report-Result 'bootstrap' 'fatal' 'Failed' -1 "$($_)"
  }
}
finally {
  Write-OperationSummary -OperationResults $Script:OperationResults
  Write-Host "Detailed log: $LogPath" -ForegroundColor Cyan
  if ($transcriptStarted) {
    Write-Host "Console transcript: $TranscriptPath" -ForegroundColor Cyan
  }
  Write-Host "Bootstrap complete." -ForegroundColor Cyan

  if ($transcriptStarted) {
    try { Stop-Transcript | Out-Null } catch { }
  }
}
