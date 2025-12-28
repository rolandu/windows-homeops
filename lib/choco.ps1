# Chocolatey helper functions for bootstrap.ps1
# - Ensure-ChocoDefaults: sets safe defaults
# - Install-Packages-WithChoco: installs a list of packages via choco (skips installed)
# - Upgrade-All-Choco: upgrades all chocolatey packages

function Ensure-ChocoDefaults {
  # -------------------------------------------------------------------------
  # Chocolatey defaults (features/config) to make scripting smoother
  # -------------------------------------------------------------------------
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
