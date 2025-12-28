# Library helpers for bootstrap.ps1
# Contains logging, reporting and helper functions used by the main bootstrap script.

function Write-Log([string]$line) {
  if (-not $LogPath) { return }
  $time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Add-Content -Path $LogPath -Value ("[$time] $line")
}

function Write-LogBlock([string]$title, [string]$cmd, [string[]]$output, [int]$exitCode) {
  Write-Log("---- $title ----")
  Write-Log("Command: $cmd")
  Write-Log("ExitCode: $exitCode")
  if ($output) {
    Write-Log("Output:")
    $output | ForEach-Object { Write-Log("  $_") }
  }
  Write-Log("---- End $title ----")
}

function Is-ChocoPackageInstalled([string]$pkg) {
  # Check if a package is installed locally via Chocolatey
  try {
    $args = @('list','--local-only','--exact',$pkg,'--limit-output')
    $output = & choco @args 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    if (-not $output) { return $false }
    $text = $output -join "`n"
    return -not [string]::IsNullOrWhiteSpace($text)
  } catch {
    return $false
  }
}

function Report-Result([string]$operation, [string]$package, [string]$status, [int]$exitCode, [string]$message) {
  # Ensure the results array exists
  if (-not (Test-Path variable:Script:OperationResults)) { $Script:OperationResults = @() }

  # Append log path for failures to aid debugging
  if ($status -eq 'Failed') {
    if ($message -and $message -ne '') { $message = "$message (log: $LogPath)" } else { $message = "See log: $LogPath" }
  }

  $Script:OperationResults += [pscustomobject]@{
    Operation = $operation
    Package   = $package
    Status    = $status
    ExitCode  = $exitCode
    Message   = $message
  }
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

function Run-ExternalScript([string]$FilePath) {
  if (-not $FilePath) { throw 'FilePath required' }

  $name = [System.IO.Path]::GetFileName($FilePath)
  if (-not (Test-Path $FilePath)) {
    Write-Host "$name not found; skipping." -ForegroundColor Yellow
    Report-Result 'script' $name 'Skipped' 0 'Not found'
    return
  }

  Write-Host "Running $name..." -ForegroundColor Cyan
  try {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $FilePath 2>&1
    $rc = $LASTEXITCODE
    $text = ($output -join "`n").Trim()

    Write-LogBlock "external script: $name" "powershell -File $FilePath" $output $rc

    if ($rc -eq 0) {
      Write-Host "$name completed successfully." -ForegroundColor Green
      Report-Result 'script' $name 'Success' $rc ''
    } else {
      Write-Warning "$name failed (exit $rc)."
      Report-Result 'script' $name 'Failed' $rc ($text -replace "\s+"," ")
    }
  } catch {
    Write-Warning "$name execution failed: $_"
    Report-Result 'script' $name 'Failed' -1 "Exception: $_"
  }
}
