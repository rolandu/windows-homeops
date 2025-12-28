<#
security-privacy.ps1
Applies a conservative "power user" security + privacy baseline.

Covers:
- Defender: realtime + cloud protection (best effort)
- Firewall: ensure enabled
- SMBv1: disabled
- Remote Assistance: disabled
- Diagnostics: required only + disable tailored experiences + advertising ID
- Search: disable Bing in Start (web search) + disable Search Highlights
- Activity History: disable

Run elevated.

Notes:
- Some settings may be overridden by Windows editions/updates/policies.
- For Home vs Pro: most of this works on both. Some registry keys are best-effort.
#>


Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Run this script as Administrator." }
}

function Set-RegDword([string]$Path, [string]$Name, [int]$Value) {
  New-Item -Path $Path -Force | Out-Null
  New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Try-Run([string]$What, [ScriptBlock]$Block) {
  try {
    & $Block
    Write-Host "OK: $What"
  } catch {
    Write-Host "SKIP/FAIL: $What"
  }
}

Assert-Admin

# -------------------------
# SECURITY
# -------------------------

# Defender (best effort: may be blocked by 3rd-party AV/policy)
Try-Run "Enable Defender realtime monitoring" {
  Set-MpPreference -DisableRealtimeMonitoring $false
}
Try-Run "Enable Defender cloud-delivered protection" {
  # 0 = default/enabled; 1 = disabled (per docs/behavior; varies slightly by build)
  Set-MpPreference -MAPSReporting Advanced
  Set-MpPreference -SubmitSamplesConsent 1
}
Try-Run "Enable Defender potentially unwanted app protection (PUA)" {
  Set-MpPreference -PUAProtection Enabled
}

# Firewall on (all profiles)
Try-Run "Enable Windows Firewall for all profiles" {
  Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
}

# Disable SMBv1
Try-Run "Disable SMBv1 optional feature" {
  Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null
}
Try-Run "Disable SMBv1 server configuration" {
  Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force | Out-Null
}

# Disable Remote Assistance
Try-Run "Disable Remote Assistance" {
  Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" "fAllowToGetHelp" 0
}

# -------------------------
# PRIVACY / TELEMETRY
# -------------------------

# Diagnostics: "Required only" (best effort)
# AllowTelemetry: 0 (Security/Enterprise), 1 (Basic/Required), 2 (Enhanced), 3 (Full)
# On Home/Pro, 1 is the lowest reliably honored.
Try-Run "Set diagnostics telemetry to Required (1)" {
  Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 1
  Set-RegDword "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" 1
}

# Disable tailored experiences
Try-Run "Disable tailored experiences" {
  Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableTailoredExperiencesWithDiagnosticData" 1
}

# Disable Advertising ID
Try-Run "Disable Advertising ID" {
  Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy" 1
}

# Disable activity history (and upload)
Try-Run "Disable Activity History" {
  Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0
  Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
  Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 0
}

# Disable Bing/web search in Start/Search
Try-Run "Disable Bing search integration in Start/Search (current user)" {
  Set-RegDword "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1
}
Try-Run "Disable Bing search integration in Start/Search (local machine)" {
  Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1
}

# Disable Search Highlights
Try-Run "Disable Search Highlights" {
  # Commonly honored on Win11. (Some builds may ignore.)
  Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "EnableDynamicContentInWSB" 0
}

Write-Host "Security/Privacy baseline applied."
Write-Host "Some changes may require sign-out or reboot to fully apply."
