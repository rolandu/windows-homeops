# Security and privacy baseline helpers

# Create/update a DWORD registry value at the given path.
function Set-RegDwordValue([string]$Path, [string]$Name, [int]$Value) {
  New-Item -Path $Path -Force | Out-Null
  New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
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
