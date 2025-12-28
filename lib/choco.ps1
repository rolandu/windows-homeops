# Chocolatey helper functions for bootstrap.ps1
# - Ensure-Chocolatey: installs Chocolatey if missing
# - Ensure-ChocoDefaults: sets safe defaults
# - Is-ChocoPackageInstalled / Install-Packages-WithChoco / Upgrade-All-Choco

function Ensure-Chocolatey {
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
  # Chocolatey defaults (features/config) to make scripting smoother
  try {
    # Use direct invocation and capture output to avoid noisy Chocolatey banner lines.
    $chocoArgs = @('feature','enable','-n','allowGlobalConfirmation')
    $output = & choco @chocoArgs 2>&1
    $rc = $LASTEXITCODE
    Write-LogBlock 'choco feature enable' "choco $($chocoArgs -join ' ')" $output $rc
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

    $chocoArgs = @('config','set','--name','commandExecutionTimeoutSeconds','--value','2700')
    $output = & choco @chocoArgs 2>&1
    $rc = $LASTEXITCODE
    Write-LogBlock 'choco config set' "choco $($chocoArgs -join ' ')" $output $rc
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

function Is-ChocoPackageInstalled([string]$pkg) {
  # Check if a package is installed locally via Chocolatey
  try {
    $chocoArgs = @('list','--local-only','--exact',$pkg,'--limit-output')
    $output = & choco @chocoArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    if (-not $output) { return $false }
    $text = $output -join "`n"
    return -not [string]::IsNullOrWhiteSpace($text)
  } catch {
    return $false
  }
}

function Install-Packages-WithChoco([string[]]$pkgs) {
  # Install packages via Chocolatey (skips already-installed packages)
  if (-not $pkgs -or $pkgs.Count -eq 0) { return }

  foreach ($p in $pkgs) {
    try {
      if (Is-ChocoPackageInstalled $p) {
        Write-Host "$p already installed via Chocolatey; skipping."
        Report-Result 'choco-install' $p 'Skipped' 0 'Already installed'
        continue
      }
      Write-Host "Ensuring package installed: $p"

      $args = @('install',$p,'-y','--no-progress','--limit-output')
      $output = & choco @args 2>&1
      $rc = $LASTEXITCODE
      Write-LogBlock "choco install $p" "choco $($args -join ' ')" $output $rc
      if ($rc -ne 0) {
        Write-Warning "Failed to install $p via Chocolatey (exit $rc)."
        Report-Result 'choco-install' $p 'Failed' $rc "install returned non-zero"
      } else {
        Report-Result 'choco-install' $p 'Success' $rc ""
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
