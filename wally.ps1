# ============================================
# Disable Windows Defender
# Run as Administrator
# ============================================

# Disable Real-Time Protection
Set-MpPreference -DisableRealtimeMonitoring $true

# Disable other Defender features
Set-MpPreference -DisableBehaviorMonitoring $true
Set-MpPreference -DisableBlockAtFirstSeen $true
Set-MpPreference -DisableIOAVProtection $true
Set-MpPreference -DisablePrivacyMode $true
Set-MpPreference -DisableScriptScanning $true
Set-MpPreference -DisableIntrusionPreventionSystem $true

# Disable via service (may require Tamper Protection disabled first)
Stop-Service -Name WinDefend -Force
Set-Service -Name WinDefend -StartupType Disabled

# Disable via registry (persistent)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1

# Add exclusion paths instead (less intrusive)
Add-MpPreference -ExclusionPath "C:\Tools"
Add-MpPreference -ExclusionPath "C:\Users\Administrator\Downloads"

# ============================================
# Disable Avast
# ============================================

# Stop Avast services
Stop-Service -Name "avast! Antivirus" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "AvastSvc" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "aswbIDSAgent" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "AvastWscReporter" -Force -ErrorAction SilentlyContinue

# Disable Avast services
Set-Service -Name "AvastSvc" -StartupType Disabled -ErrorAction SilentlyContinue
Set-Service -Name "aswbIDSAgent" -StartupType Disabled -ErrorAction SilentlyContinue
Set-Service -Name "AvastWscReporter" -StartupType Disabled -ErrorAction SilentlyContinue

# Kill Avast processes
Get-Process -Name "Avast*" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "asw*" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "AvastUI" -ErrorAction SilentlyContinue | Stop-Process -Force

# ============================================
# Verify disabled
# ============================================

# Check Defender status
Get-MpComputerStatus | Select-Object RealTimeProtectionEnabled, AntivirusEnabled

# Check services
Get-Service -Name WinDefend, AvastSvc -ErrorAction SilentlyContinue | Select-Object Name, Status