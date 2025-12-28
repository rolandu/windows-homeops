# External script helpers

# Run a PS1 file (NoProfile, bypass policy), log output, and record result.
function Invoke-ExternalScript([string]$FilePath) {
  if (-not $FilePath) { throw 'FilePath required' }

  $name = [System.IO.Path]::GetFileName($FilePath)
  if (-not (Test-Path $FilePath)) {
    Write-Host "$name not found; skipping." -ForegroundColor Yellow
    Write-ResultRecord 'script' $name 'Skipped' 0 'Not found'
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
      Write-ResultRecord 'script' $name 'Success' $rc ''
    } else {
      Write-Warning "$name failed (exit $rc)."
      Write-ResultRecord 'script' $name 'Failed' $rc ($text -replace "\s+"," ")
    }
  } catch {
    Write-Warning "$name execution failed: $_"
    Write-ResultRecord 'script' $name 'Failed' -1 "Exception: $_"
  }
}
