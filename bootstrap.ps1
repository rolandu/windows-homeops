<#
bootstrap.ps1
- Idempotent baseline bootstrap for Windows
- Installs Chocolatey if missing
- Installs a list of packages (Chocolatey)
- Installs a list of packages (winget)
- Upgrades Chocolatey packages and runs winget --all
- Runs optional post-setup scripts (e.g. security-privacy.ps1)

Editable areas:
- Update the `$Packages` array to control Chocolatey packages.
- Update the `$WingetPackages` array to control explicit winget installs.
- The `security-privacy.ps1` runner will record a single summary line; replace or add scripts as needed.

Run elevated (Admin) or via Scheduled Task with highest privileges.
#>

[CmdletBinding()]
param(
  [string[]]$Packages = @(
    "7zip",
    "cyberduck",
    "firefox",
    "git",
    "libreoffice-still",
    "notepadplusplus",
    "powershell-core",  # PowerShell 7 (pwsh)
    "rclone",
    "syncthing",
    "synctrayzor",
    "thunderbird",
    "vim",
    "vlc",
    "windirstat",
    "winfsp"
  )
)

# Winget package list (edit as desired). Ensure IDs are correct for winget.
[string[]]$WingetPackages = @(
  "RustDesk.RustDesk"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Initialize operation results array early so Report-Result can safely append
$Script:OperationResults = @()

# ---------------------------
# Logging setup
# Create a `logs` folder next to this script and a timestamped log file
# ---------------------------
if ($PSScriptRoot) { $ScriptRoot = $PSScriptRoot } else { $ScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent }
$LogDir = Join-Path $ScriptRoot 'logs'
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
$timestamp = (Get-Date).ToString('yyyyMMdd-Hmmss')
$LogPath = Join-Path $LogDir "bootstrap-$timestamp.log"
. (Join-Path $ScriptRoot 'lib\bootstrap_lib.ps1')
. (Join-Path $ScriptRoot 'lib\choco.ps1')
. (Join-Path $ScriptRoot 'lib\winget.ps1')
. (Join-Path $ScriptRoot 'lib\scripts.ps1')
function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Run this script as Administrator." }
}

# ---------------------------------------------------------------------------
# Helper: TLS & download helpers
# Ensures TLS 1.2/1.3 are enabled for secure downloads
# ---------------------------------------------------------------------------
function Enable-TlsForDownloads {
  try {
    [Net.ServicePointManager]::SecurityProtocol = `
      [Net.ServicePointManager]::SecurityProtocol -bor `
      [Net.SecurityProtocolType]::Tls12 -bor `
      [Net.SecurityProtocolType]::Tls13
  } catch {
    [Net.ServicePointManager]::SecurityProtocol = `
      [Net.ServicePointManager]::SecurityProtocol -bor `
      [Net.SecurityProtocolType]::Tls12
  }
}

function Ensure-Chocolatey {
  # -------------------------------------------------------------------------
  # Chocolatey installer helper
  # Installs Chocolatey if missing and ensures it's on PATH
  # -------------------------------------------------------------------------
  $chocoExe = Join-Path $env:ProgramData "chocolatey\bin\choco.exe"
  if (Test-Path $chocoExe) {
    Write-Host "Chocolatey already installed."
    $env:Path = "$env:Path;$($env:ProgramData)\chocolatey\bin"
    return
  }

  Write-Host "Installing Chocolatey..."
  Enable-TlsForDownloads
  Set-ExecutionPolicy Bypass -Scope Process -Force | Out-Null

  $installScriptUrl = "https://community.chocolatey.org/install.ps1"
  $scriptText = (New-Object Net.WebClient).DownloadString($installScriptUrl)
  Invoke-Expression $scriptText

  if (-not (Test-Path $chocoExe)) {
    throw "Chocolatey install ran, but choco.exe not found at: $chocoExe"
  }

  $env:Path = "$env:Path;$($env:ProgramData)\chocolatey\bin"
  Write-Host "Chocolatey installed."
}

function Ensure-ChocoDefaults {
  # -------------------------------------------------------------------------
  # Chocolatey defaults (features/config) to make scripting smoother
  # -------------------------------------------------------------------------
  # Safe scripting defaults
  try {
    # Use direct invocation and capture output to avoid noisy Chocolatey banner lines.
    $args = @('feature','enable','-n','allowGlobalConfirmation')
    $output = & choco @args 2>&1
    $rc = $LASTEXITCODE
    Write-LogBlock 'choco feature enable' "choco $($args -join ' ')" $output $rc
    if ($rc -ne 0) {
      Write-Warning "Failed to enable Chocolatey feature allowGlobalConfirmation (exit $rc)."
      Report-Result 'choco-feature' 'allowGlobalConfirmation' 'Failed' $rc "enable feature failed"
      if ($output) { Write-Host ($output -join "`n") }
    } else {
      if ($output -and ($output -join "`n") -match 'Nothing to change') {
        Write-Host "Chocolatey feature allowGlobalConfirmation: already set."
      } else {
        Write-Host "Chocolatey feature allowGlobalConfirmation: set/confirmed."
      }
      Report-Result 'choco-feature' 'allowGlobalConfirmation' 'Success' $rc ""
    }

    $args = @('config','set','--name','commandExecutionTimeoutSeconds','--value','2700')
    $output = & choco @args 2>&1
    $rc = $LASTEXITCODE
    Write-LogBlock 'choco config set' "choco $($args -join ' ')" $output $rc
    if ($rc -ne 0) {
      Write-Warning "Failed to set Chocolatey config commandExecutionTimeoutSeconds (exit $rc)."
      Report-Result 'choco-config' 'commandExecutionTimeoutSeconds' 'Failed' $rc "set config failed"
      if ($output) { Write-Host ($output -join "`n") }
    } else {
      if ($output -and ($output -join "`n") -match 'Nothing to change') {
        Write-Host "Chocolatey config commandExecutionTimeoutSeconds: already set."
      } else {
        Write-Host "Chocolatey config commandExecutionTimeoutSeconds: set/confirmed."
      }
      Report-Result 'choco-config' 'commandExecutionTimeoutSeconds' 'Success' $rc ""
    }
  } catch {
    Write-Warning "Failed to set Chocolatey defaults: $_"
  }
}

function Install-Packages-WithChoco([string[]]$pkgs) {
  # Install packages via Chocolatey (skips already-installed packages)
  if (-not $pkgs -or $pkgs.Count -eq 0) { return }

  foreach ($p in $pkgs) {
    if (Is-ChocoPackageInstalled $p) {
      Write-Host "$p already installed via Chocolatey; skipping."
      Report-Result 'choco-install' $p 'Skipped' 0 'Already installed'
      continue
    }
    Write-Host "Ensuring package installed: $p"
    try {
      $args = @('install',$p,'-y','--no-progress')
      $proc = Start-Process -FilePath 'choco' -ArgumentList $args -Wait -NoNewWindow -PassThru
      if ($proc.ExitCode -ne 0) {
        Write-Warning "Failed to install $p via Chocolatey (exit $($proc.ExitCode))."
        Report-Result 'choco-install' $p 'Failed' $proc.ExitCode "install returned non-zero"
      } else {
        Report-Result 'choco-install' $p 'Success' $proc.ExitCode ""
      }
    } catch {
      Write-Warning "Failed to install $p via Chocolatey: $_"
      Report-Result 'choco-install' $p 'Failed' -1 "Exception: $_"
    }
  }
}

function Upgrade-All-Choco {
  # Upgrade all Chocolatey-managed packages
  Write-Host "Upgrading all Chocolatey packages..."
  try {
    $args = @('upgrade','all','-y','--no-progress')
    $proc = Start-Process -FilePath 'choco' -ArgumentList $args -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -ne 0) {
      Write-Warning "Chocolatey upgrade failed (exit $($proc.ExitCode))."
      Report-Result 'choco-upgrade' 'all' 'Failed' $proc.ExitCode "upgrade returned non-zero"
    } else {
      Report-Result 'choco-upgrade' 'all' 'Success' $proc.ExitCode ""
    }
  } catch {
    Write-Warning "Chocolatey upgrade failed: $_"
    Report-Result 'choco-upgrade' 'all' 'Failed' -1 "Exception: $_"
  }
}

function Install-Packages-WithWinget([string[]]$pkgs) {
  # Install packages via winget (skips already-installed packages)
  if (-not $pkgs -or $pkgs.Count -eq 0) { return }

  foreach ($p in $pkgs) {
    if (Is-WingetPackageInstalled $p) {
      Write-Host "$p already installed via winget; skipping."
      Report-Result 'winget-install' $p 'Skipped' 0 'Already installed'
      continue
    }
    Write-Host "Ensuring winget package installed: $p"
    try {
      $args = @('install','--id',$p,'-e','--accept-package-agreements','--accept-source-agreements','--silent')
      $output = & winget @args 2>&1
      $rc = $LASTEXITCODE
      $text = ($output -join "`n").Trim()
      Write-LogBlock 'winget install' "winget $($args -join ' ')" $output $rc
      if ($rc -ne 0) {
        # Some winget errors are informative; report failure but include output
        Write-Warning "Failed to install $p via winget (exit $rc)."
        Report-Result 'winget-install' $p 'Failed' $rc "$text"
      } else {
        Report-Result 'winget-install' $p 'Success' $rc "$text"
      }
    } catch {
      Write-Warning "Failed to install $p via winget: $_"
      Report-Result 'winget-install' $p 'Failed' -1 "Exception: $_"
    }
  }
}

  # -------------------------------------------------------------------------
  # Reporting & winget helpers
  # Tracks operation results and provides winget installed checks
  

function Upgrade-All-WithWinget {
  # Upgrade all upgradable packages via winget (system-wide)
  Write-Host "Upgrading all available winget packages..."
  try {
    $args = @('upgrade','--all','-e','--accept-package-agreements','--accept-source-agreements','--silent')
    $output = & winget @args 2>&1
    $rc = $LASTEXITCODE
    $text = ($output -join "`n").Trim()
    Write-LogBlock 'winget upgrade --all' "winget $($args -join ' ')" $output $rc

    if ($rc -ne 0) {
      # If winget reports no upgrades, treat as skipped
      if ($text -match 'No available upgrade found' -or $text -match 'No newer package versions are available' -or $text -match 'No applicable upgrades') {
        Write-Host "No upgrades available via winget." -ForegroundColor Yellow
        Report-Result 'winget-upgrade' 'all' 'Skipped' $rc 'No upgrades available'
      } else {
        Write-Warning "winget --all upgrade failed (exit $rc)."
        Report-Result 'winget-upgrade' 'all' 'Failed' $rc "$text"
      }
    } else {
      Write-Host "winget --all upgrade completed." -ForegroundColor Green
      Report-Result 'winget-upgrade' 'all' 'Success' $rc "$text"
    }
  } catch {
    Write-Warning "winget --all upgrade failed: $_"
    Report-Result 'winget-upgrade' 'all' 'Failed' -1 "Exception: $_"
  }
}

# ---- main ----
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

$secScript = Join-Path $PSScriptRoot "security-privacy.ps1"
Run-ExternalScript $secScript

# Print final summary of operations
if ($Script:OperationResults -and $Script:OperationResults.Count -gt 0) {
  $total   = $Script:OperationResults.Count
  $success = ($Script:OperationResults | Where-Object { $_.Status -eq 'Success' }).Count
  $failed  = ($Script:OperationResults | Where-Object { $_.Status -eq 'Failed' }).Count
  $skipped = ($Script:OperationResults | Where-Object { $_.Status -eq 'Skipped' }).Count

  Write-Host ""
  Write-Host "Bootstrap summary:" -ForegroundColor Cyan
  Write-Host "Total: $total    Success: $success    Failed: $failed    Skipped: $skipped" -ForegroundColor Cyan

  Write-Host "Detailed log: $LogPath" -ForegroundColor Cyan

  Write-Host ""
  if ($success -gt 0) {
    Write-Host "Successful operations ($success):" -ForegroundColor Green
    $Script:OperationResults | Where-Object { $_.Status -eq 'Success' } | ForEach-Object {
      Write-Host "- $($_.Operation) $($_.Package)" -ForegroundColor Green
    }
    Write-Host ""
  }

  if ($skipped -gt 0) {
    Write-Host "Skipped operations ($skipped):" -ForegroundColor Yellow
    $Script:OperationResults | Where-Object { $_.Status -eq 'Skipped' } | ForEach-Object {
      $msg = if ($_.Message) { " - $($_.Message)" } else { "" }
      Write-Host "- $($_.Operation) $($_.Package)$msg" -ForegroundColor Yellow
    }
    Write-Host ""
  }

  if ($failed -gt 0) {
    Write-Host "Failed operations ($failed):" -ForegroundColor Red
    $Script:OperationResults | Where-Object { $_.Status -eq 'Failed' } | ForEach-Object {
      Write-Host "- $($_.Operation) $($_.Package) (exit $($_.ExitCode)): $($_.Message)" -ForegroundColor Red
    }
    Write-Host ""
  }

} else {
  Write-Host "No operations recorded." -ForegroundColor Yellow
}

Write-Host "Bootstrap complete." -ForegroundColor Cyan
