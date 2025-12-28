# Winget helper functions for bootstrap.ps1
# - Is-WingetPackageInstalled
# - Install-Packages-WithWinget
# - Upgrade-All-WithWinget

function Remove-WingetNoise([string[]]$output) {
  # Strip spinner/progress glyphs and non-ASCII noise from winget output.
  if (-not $output) { return @() }
  $filtered = foreach ($line in $output) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    # Skip lines with non-ASCII chars (progress bars) or bare spinner frames.
    $hasNonAscii = $line.ToCharArray() | Where-Object { [int]$_ -gt 127 }
    if ($hasNonAscii) { continue }
    if ($line -match '^[\s\|\\/\\-]+$') { continue }
    $line
  }
  if ($filtered) { return ,$filtered } else { return @() }
}

function Is-WingetPackageInstalled([string]$pkg) {
  # Return $true if winget reports the package present
  try {
    $output = & winget list --id $pkg 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    $text = ($output -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    return $true
  } catch {
    return $false
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
      # --disable-interactivity reduces spinner/progress noise in logs.
      $wargs = @('install','--id',$p,'-e','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity')
      $output = & winget @wargs 2>&1
      $cleanOutput = Remove-WingetNoise $output
      $rc = $LASTEXITCODE
      $text = ($cleanOutput -join "`n").Trim()
      Write-LogBlock 'winget install' "winget $($wargs -join ' ')" $cleanOutput $rc
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

function Upgrade-All-WithWinget {
  # Upgrade all upgradable packages via winget (system-wide)
  Write-Host "Upgrading all available winget packages..."
  try {
    # --disable-interactivity reduces spinner/progress noise in logs.
    $wargs = @('upgrade','--all','-e','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity')
    $output = & winget @wargs 2>&1
    $cleanOutput = Remove-WingetNoise $output
    $rc = $LASTEXITCODE
    $text = ($cleanOutput -join "`n").Trim()
    Write-LogBlock 'winget upgrade --all' "winget $($wargs -join ' ')" $cleanOutput $rc

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
