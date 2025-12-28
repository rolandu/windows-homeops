# External script helpers
# - Run-ExternalScript: run a PS1 file and record result

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
