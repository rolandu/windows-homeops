# Winget helper functions for bootstrap.ps1

# Remove spinner/progress lines and non-ASCII noise from winget output.
function Filter-WingetOutput([string[]]$output) {
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

# Return $true if winget reports the package present.
function Test-WingetPackage([string]$pkg) {
  # Return $true if winget reports the package present
  try {
    $wargs = @('list','--id',$pkg,'-e','--accept-source-agreements','--disable-interactivity')
    $output = & winget @wargs 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    $text = ($output -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    return $true
  } catch {
    return $false
  }
}

# Install packages via winget (skip already-installed packages).
function Install-WingetPackages([string[]]$pkgs) {
  # Install packages via winget (skips already-installed packages)
  if (-not $pkgs -or $pkgs.Count -eq 0) { return }

  foreach ($p in $pkgs) {
    if (Test-WingetPackage $p) {
      Write-Host "$p already installed via winget; skipping."
      Write-ResultRecord 'winget-install' $p 'Skipped' 0 'Already installed'
      continue
    }
    Write-Host "Ensuring winget package installed: $p"
    try {
      # --disable-interactivity reduces spinner/progress noise in logs.
      $wargs = @('install','--id',$p,'-e','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity')
      $output = & winget @wargs 2>&1
      $cleanOutput = Filter-WingetOutput $output
      $rc = $LASTEXITCODE
      $text = ($cleanOutput -join "`n").Trim()
      Write-LogBlock 'winget install' "winget $($wargs -join ' ')" $cleanOutput $rc
      if ($rc -ne 0) {
        # Some winget errors are informative; report failure but include output
        Write-Warning "Failed to install $p via winget (exit $rc)."
        Write-ResultRecord 'winget-install' $p 'Failed' $rc "$text"
      } else {
        Write-ResultRecord 'winget-install' $p 'Success' $rc "$text"
      }
    } catch {
      Write-Warning "Failed to install $p via winget: $_"
      Write-ResultRecord 'winget-install' $p 'Failed' -1 "Exception: $_"
    }
  }
}

# Upgrade all upgradable winget packages (system-wide).
function Update-WingetPackages {
  # Upgrade all upgradable packages via winget (system-wide)
  Write-Host "Upgrading all available winget packages..."
  try {
    # --disable-interactivity reduces spinner/progress noise in logs.
    $wargs = @('upgrade','--all','-e','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity')
    $output = & winget @wargs 2>&1
    $cleanOutput = Filter-WingetOutput $output
    $rc = $LASTEXITCODE
    $text = ($cleanOutput -join "`n").Trim()
    Write-LogBlock 'winget upgrade --all' "winget $($wargs -join ' ')" $cleanOutput $rc

    if ($rc -ne 0) {
      # If winget reports no upgrades, treat as skipped
      if ($text -match 'No available upgrade found' -or $text -match 'No newer package versions are available' -or $text -match 'No applicable upgrades') {
        Write-Host "No upgrades available via winget." -ForegroundColor Yellow
        Write-ResultRecord 'winget-upgrade' 'all' 'Skipped' $rc 'No upgrades available'
      } else {
        Write-Warning "winget --all upgrade failed (exit $rc)."
        Write-ResultRecord 'winget-upgrade' 'all' 'Failed' $rc "$text"
      }
    } else {
      Write-Host "winget --all upgrade completed." -ForegroundColor Green
      Write-ResultRecord 'winget-upgrade' 'all' 'Success' $rc "$text"
    }
  } catch {
    Write-Warning "winget --all upgrade failed: $_"
    Write-ResultRecord 'winget-upgrade' 'all' 'Failed' -1 "Exception: $_"
  }
}
