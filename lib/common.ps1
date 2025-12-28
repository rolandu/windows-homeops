# Common helpers for the bootstrap workflow.
# - Initialize-Logging: create a timestamped log file under logs/
# - Write-Log / Write-LogBlock: structured logging helpers
# - Report-Result: track operation outcomes for final summary
# - Assert-Admin: ensure the script is running elevated
# - Enable-TlsForDownloads: enforce modern TLS for downloads

function Initialize-Logging([string]$ScriptRoot, [string]$Prefix = 'bootstrap') {
  if (-not $ScriptRoot) { throw 'ScriptRoot is required to build the log path.' }

  $logDir = Join-Path $ScriptRoot 'logs'
  New-Item -Path $logDir -ItemType Directory -Force | Out-Null

  $timestamp = (Get-Date).ToString('yyyyMMdd-Hmmss')
  $logPath = Join-Path $logDir "$Prefix-$timestamp.log"

  # Expose log path for other helpers
  $Script:LogPath = $logPath
  return $logPath
}

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

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Run this script as Administrator." }
}

function Enable-TlsForDownloads {
  # Ensure TLS 1.2/1.3 are enabled for secure downloads
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

function Write-OperationSummary([array]$OperationResults) {
  $results = @($OperationResults)
  if (-not ($results -and $results.Count -gt 0)) {
    Write-Host "No operations recorded." -ForegroundColor Yellow
    return
  }

  $successItems = @($results | Where-Object { $_.Status -eq 'Success' })
  $failedItems  = @($results | Where-Object { $_.Status -eq 'Failed' })
  $skippedItems = @($results | Where-Object { $_.Status -eq 'Skipped' })

  $total   = $results.Count
  $success = $successItems.Count
  $failed  = $failedItems.Count
  $skipped = $skippedItems.Count

  Write-Host ""
  Write-Host "Bootstrap summary:" -ForegroundColor Cyan
  Write-Host "Total: $total    Success: $success    Failed: $failed    Skipped: $skipped" -ForegroundColor Cyan

  if ($success -gt 0) {
    Write-Host "Successful operations ($success):" -ForegroundColor Green
    $successItems | ForEach-Object {
      Write-Host "- $($_.Operation) $($_.Package)" -ForegroundColor Green
    }
    Write-Host ""
  }

  if ($skipped -gt 0) {
    Write-Host "Skipped operations ($skipped):" -ForegroundColor Yellow
    $skippedItems | ForEach-Object {
      $msg = if ($_.Message) { " - $($_.Message)" } else { "" }
      Write-Host "- $($_.Operation) $($_.Package)$msg" -ForegroundColor Yellow
    }
    Write-Host ""
  }

  if ($failed -gt 0) {
    Write-Host "Failed operations ($failed):" -ForegroundColor Red
    $failedItems | ForEach-Object {
      Write-Host "- $($_.Operation) $($_.Package) (exit $($_.ExitCode)): $($_.Message)" -ForegroundColor Red
    }
    Write-Host ""
  }
}
