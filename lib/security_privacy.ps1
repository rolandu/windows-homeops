# Security and privacy baseline helpers

# Create/update a DWORD registry value at the given path.
function Set-RegDwordValue([string]$Path, [string]$Name, [int]$Value) {
  New-Item -Path $Path -Force | Out-Null
  New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

# Disable startup entries (Task Manager "Startup apps") by marking them Disabled in StartupApproved.
function Disable-StartupItems([string[]]$ApproxNames) {
  if (-not $ApproxNames -or $ApproxNames.Count -eq 0) { return }

  $disabledBytes = [byte[]](0x03,0,0,0,0,0,0,0,0,0,0,0) # 0x03 = Disabled
  $cimItems = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
  $startupApprovedPaths = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupTasks',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupTasks'
  )

  foreach ($approx in $ApproxNames) {
    $targets = @()

    # Existing StartupApproved registry entries (only disable what already exists)
    foreach ($path in $startupApprovedPaths) {
      if (-not (Test-Path $path)) { continue }
      try {
        $props = (Get-ItemProperty -Path $path).PSObject.Properties.Name
        $matches = $props | Where-Object { $_ -notmatch '^PS' -and $_ -like "*$approx*" }
        foreach ($m in $matches) {
          if ($m -and ($m -is [string]) -and $m.Trim() -ne '') {
            $targets += [pscustomobject]@{ Path = $path; Name = $m.Trim() }
          }
        }
      } catch { }
    }

    # Add entries discovered via Win32_StartupCommand, mapped to the right StartupApproved hive
    if ($cimItems) {
      foreach ($item in $cimItems) {
        if (-not $item -or -not $item.PSObject.Properties['Name']) { continue }
        if (-not ($item.Name -like "*$approx*" -or ($item.Command -and $item.Command -like "*$approx*"))) { continue }

        $loc = if ($item.PSObject.Properties['Location']) { $item.Location } else { "" }
        $name = $item.Name
        if (-not ($name -is [string])) { continue }
        $name = $name.Trim()
        if (-not $name) { continue }

        $candidatePaths = @()
        if ($loc -match 'HKLM' -and $loc -match 'CurrentVersion\\Run') {
          $candidatePaths += 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        } elseif ($loc -match 'HKCU' -and $loc -match 'CurrentVersion\\Run') {
          $candidatePaths += 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        } elseif ($loc -match 'Common Startup' -or $loc -match 'All Users' -or $loc -match '\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\StartUp') {
          $candidatePaths += 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        } elseif ($loc -match 'Startup' -or $loc -match '\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup') {
          $candidatePaths += 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        }

        foreach ($p in $candidatePaths | Select-Object -Unique) {
          $valueName = $name
          if ($p -like '*StartupFolder') {
            if (-not $valueName.EndsWith('.lnk', [StringComparison]::OrdinalIgnoreCase)) {
              $valueName = "$valueName.lnk"
            }
          }
          if ($valueName -and $valueName.Trim() -ne '') {
            $targets += [pscustomobject]@{ Path = $p; Name = $valueName.Trim() }
          }
        }
      }
    }

    # Add entries discovered via Win32_StartupCommand, mapped to the right StartupApproved hive
    if ($cimItems) {
      foreach ($item in $cimItems) {
        if (-not $item -or -not $item.PSObject.Properties['Name']) { continue }
        if (-not ($item.Name -like "*$approx*" -or ($item.Command -and $item.Command -like "*$approx*"))) { continue }

        $loc = if ($item.PSObject.Properties['Location']) { $item.Location } else { "" }
        $name = $item.Name
        if (-not ($name -is [string])) { continue }
        $name = $name.Trim()
        if (-not $name) { continue }

        $candidatePaths = @()
        if ($loc -match 'HKLM' -and $loc -match 'CurrentVersion\\Run') {
          $candidatePaths += 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        } elseif ($loc -match 'HKCU' -and $loc -match 'CurrentVersion\\Run') {
          $candidatePaths += 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        } elseif ($loc -match 'Common Startup' -or $loc -match 'All Users' -or $loc -match '\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\StartUp') {
          $candidatePaths += 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        } elseif ($loc -match 'Startup' -or $loc -match '\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup') {
          $candidatePaths += 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        }

        foreach ($p in $candidatePaths | Select-Object -Unique) {
          $valueName = $name
          if ($p -like '*StartupFolder' -and -not $valueName.EndsWith('.lnk', [StringComparison]::OrdinalIgnoreCase)) {
            $valueName = "$valueName.lnk"
          }
          if ($valueName -and $valueName.Trim() -ne '') {
            $targets += [pscustomobject]@{ Path = $p; Name = $valueName.Trim() }
          }
        }
      }
    }

    # If nothing matched, record a skip and continue
    if (-not $targets -or $targets.Count -eq 0) {
      Write-ResultRecord 'startup-disable' $approx 'Skipped' 0 'No matching startup entries found'
      continue
    }

    # Deduplicate by path/name to avoid repeated writes
    $uniqueTargets = @()
    $seen = @{}
    foreach ($t in $targets) {
      $key = "$($t.Path)|$($t.Name)"
      if (-not $seen.ContainsKey($key)) {
        $seen[$key] = $true
        $uniqueTargets += $t
      }
    }

    foreach ($target in $uniqueTargets) {
      $anySuccess = $false
      $errors = @()

      # If already disabled (leading byte 0x03), skip to avoid repeat successes.
      try {
        $existing = Get-ItemProperty -Path $target.Path -Name $target.Name -ErrorAction SilentlyContinue
        if ($existing) {
          $val = $existing.($target.Name)
          if ($val -is [byte[]] -and $val.Length -gt 0 -and $val[0] -eq 0x03) {
            Write-ResultRecord 'startup-disable' $target.Name 'Skipped' 0 "Already disabled in $($target.Path)"
            Write-Host "Startup item already disabled: $($target.Name) ($($target.Path))"
            continue
          }
        }
      } catch {
        # Ignore read errors; fall through to attempt setting
      }

      try {
        New-Item -Path $target.Path -Force | Out-Null
        New-ItemProperty -Path $target.Path -Name $target.Name -PropertyType Binary -Value $disabledBytes -Force | Out-Null
        $anySuccess = $true
      } catch {
        $errors += $_.Exception.Message
      }

      if ($anySuccess) {
        Write-ResultRecord 'startup-disable' $target.Name 'Success' 0 "Disabled in $($target.Path)"
        Write-Host "Startup item disabled: $($target.Name) ($($target.Path))"
      } else {
        $msg = if ($errors) { ($errors | Select-Object -Unique) -join '; ' } else { 'Failed to write StartupApproved entry' }
        Write-ResultRecord 'startup-disable' $target.Name 'Failed' 1 $msg
        Write-Host "Failed to disable startup item: $($target.Name)"
      }
    }
  }
}

# Apply a conservative security/privacy baseline (best-effort per step).
function Invoke-SecurityPrivacyBaseline {
  Confirm-AdminPrivilege

  $failures = @()
  $steps = @(
    @{ Name = "Enable Defender realtime monitoring"; Action = { Set-MpPreference -DisableRealtimeMonitoring $false } },
    @{ Name = "Enable Defender cloud-delivered protection"; Action = { Set-MpPreference -MAPSReporting Advanced; Set-MpPreference -SubmitSamplesConsent 1 } },
    @{ Name = "Enable Defender PUA protection"; Action = { Set-MpPreference -PUAProtection Enabled } },
    @{ Name = "Enable Windows Firewall for all profiles"; Action = { Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True } },
    @{ Name = "Disable SMBv1 optional feature"; Action = { Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null } },
    @{ Name = "Disable SMBv1 server configuration"; Action = { Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force | Out-Null } },
    @{ Name = "Disable Remote Assistance"; Action = { Set-RegDwordValue "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" "fAllowToGetHelp" 0 } },
    @{ Name = "Set diagnostics telemetry to Required (1)"; Action = {
        Set-RegDwordValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 1
        Set-RegDwordValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" 1
      }
    },
    @{ Name = "Disable tailored experiences"; Action = { Set-RegDwordValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableTailoredExperiencesWithDiagnosticData" 1 } },
    @{ Name = "Disable Advertising ID"; Action = { Set-RegDwordValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy" 1 } },
    @{ Name = "Disable Activity History"; Action = {
        Set-RegDwordValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0
        Set-RegDwordValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
        Set-RegDwordValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 0
      }
    },
    @{ Name = "Disable Bing search integration (current user)"; Action = { Set-RegDwordValue "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1 } },
    @{ Name = "Disable Bing search integration (local machine)"; Action = { Set-RegDwordValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1 } },
    @{ Name = "Disable Search Highlights"; Action = { Set-RegDwordValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "EnableDynamicContentInWSB" 0 } }
  )

  foreach ($step in $steps) {
    try {
      & $step.Action
      Write-Host "OK: $($step.Name)"
      Write-ResultRecord 'security-privacy' $step.Name 'Success' 0 ''
    } catch {
      Write-Host "SKIP/FAIL: $($step.Name)"
      $message = "$($_.Exception.Message)".Trim()
      if (-not $message) { $message = 'Exception during step' }
      Write-ResultRecord 'security-privacy' $step.Name 'Failed' 1 $message
      $failures += $step.Name
    }
  }

  Write-Host "Security/Privacy baseline applied."
  Write-Host "Some changes may require sign-out or reboot to fully apply."
}
