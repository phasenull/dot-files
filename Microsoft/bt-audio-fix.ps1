<#
.SYNOPSIS
  Fix Windows 11 Bluetooth headphones that connect as "Connected" instead of "Connected music".

.DESCRIPTION
  Root causes this addresses (all are Windows defaults, so they follow you to every PC):
    1. The Bluetooth radio is allowed to USB-selective-suspend (power state D2) while a headset is
       linked. The ACL link survives the suspend but the host-side profile (A2DP) setup stalls, leaving
       the device "Connected" with no audio endpoint. Fix: turn off "Allow the computer to turn off this
       device" on every Bluetooth radio and turn off USB selective suspend in the active power plan.
    2. The Handsfree Telephony (HFP) profile stays enabled at stack level even when its audio device is
       disabled in Device Manager. Windows then negotiates HFP + A2DP on every reconnect and they race.
       Fix: disable the HFP (and HSP) service for every paired A2DP device, the same thing as unticking
       "Handsfree Telephony" in the device's Services tab. Hands-free is NEVER enabled by this script.

  Modes:
    -Status   show radios, power state, paired audio devices and their profile/endpoint state (no admin)
    -Apply    apply the persistent fix, then toggle the radio so it takes effect (self-elevates)
    -Kick     headphones stuck at "Connected" right now: toggle the radio off/on the way the Settings
              switch does and wait for the A2DP endpoint (no admin, ~3 s)

  Needs Windows PowerShell 5.1 for the WinRT radio API; re-launches itself from pwsh automatically.

.EXAMPLE
  .\bt-audio-fix.ps1 -Status
  .\bt-audio-fix.ps1 -Apply
  .\bt-audio-fix.ps1 -Kick
#>
[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$Apply,
    [switch]$Kick,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
if (-not ($Status -or $Apply -or $Kick)) { $Status = $true }

$A2DP_SINK = '{0000110b-0000-1000-8000-00805f9b34fb}'
$HFP_AG    = '{0000111e-0000-1000-8000-00805f9b34fb}'
$HSP_AG    = '{00001108-0000-1000-8000-00805f9b34fb}'
$SUB_USB   = '2a737441-1930-4402-8d77-b2bebba308a3'
$USB_SUSP  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RelaunchArgs {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Status) { $a += '-Status' }
    if ($Apply)  { $a += '-Apply' }
    if ($Kick)   { $a += '-Kick' }
    if ($LogPath) { $a += @('-LogPath', "`"$LogPath`"") }
    $a
}

# ---------------------------------------------------------------- relaunch under 5.1 / elevate
if ($PSVersionTable.PSEdition -eq 'Core') {
    Start-Process powershell.exe -ArgumentList (Get-RelaunchArgs) -Wait -NoNewWindow
    exit
}
if ($Apply -and -not (Test-Admin)) {
    Write-Host 'Elevating (UAC prompt)...'
    Start-Process powershell.exe -Verb RunAs -ArgumentList (Get-RelaunchArgs) -Wait
    exit
}

if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }

# ---------------------------------------------------------------- WinRT radio (what the Settings toggle uses)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$script:asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, $type) {
    $t = $script:asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result
}
[Windows.Devices.Radios.Radio, Windows.System.Devices, ContentType = WindowsRuntime] | Out-Null
[Windows.Devices.Radios.RadioAccessStatus, Windows.System.Devices, ContentType = WindowsRuntime] | Out-Null
[Windows.Devices.Radios.RadioState, Windows.System.Devices, ContentType = WindowsRuntime] | Out-Null

function Get-WinRtBtRadios {
    $access = Await ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus])
    if ($access -ne 'Allowed') { throw "Radio access $access (Settings > Privacy > Radios: let apps control radios)" }
    $all = Await ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
    $all | Where-Object Kind -eq 'Bluetooth'
}

function Restart-BtRadio {
    foreach ($r in Get-WinRtBtRadios) {
        Await ($r.SetStateAsync([Windows.Devices.Radios.RadioState]::Off)) ([Windows.Devices.Radios.RadioAccessStatus]) | Out-Null
        Start-Sleep 3
        Await ($r.SetStateAsync([Windows.Devices.Radios.RadioState]::On)) ([Windows.Devices.Radios.RadioAccessStatus]) | Out-Null
    }
}

# ---------------------------------------------------------------- discovery
function Get-BtRadios {
    Get-PnpDevice -Class Bluetooth -PresentOnly | Where-Object {
        $_.InstanceId -like 'USB\*' -or $_.InstanceId -like 'PCI\*' -or $_.Service -in 'BTHUSB', 'BTHMINI'
    }
}

function Get-RadioPowerState($radio) {
    # DEVPKEY_Device_PowerData: offset 4 = most recent D state (1=D0 .. 4=D3)
    $b = (Get-PnpDeviceProperty -InstanceId $radio.InstanceId -KeyName DEVPKEY_Device_PowerData -ErrorAction SilentlyContinue).Data
    if ($b) { 'D' + ([BitConverter]::ToUInt32($b, 4) - 1) } else { '?' }
}

function Get-RadioPowerMgmt($radio) {
    $id = $radio.InstanceId
    Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceName -like "$id*" }
}

function Get-PairedAudioDevices {
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices'
    $present = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue
    $endpoints = $present | Where-Object { $_.Class -eq 'AudioEndpoint' -and $_.Status -eq 'OK' }
    foreach ($dev in Get-ChildItem $root -ErrorAction SilentlyContinue) {
        $mac = $dev.PSChildName
        $svcKeys = Get-ChildItem $dev.PSPath | Where-Object PSChildName -like 'ServicesFor*'
        $a2dp = $false; $hfpKeys = @()
        foreach ($sk in $svcKeys) {
            if (Test-Path (Join-Path $sk.PSPath $A2DP_SINK)) { $a2dp = $true }
            foreach ($g in $HFP_AG, $HSP_AG) {
                $p = Join-Path $sk.PSPath $g
                if (Test-Path $p) { $hfpKeys += Get-ChildItem $p }
            }
        }
        if (-not $a2dp) { continue }
        $nameBytes = (Get-ItemProperty $dev.PSPath -ErrorAction SilentlyContinue).Name
        $name = if ($nameBytes) { ([Text.Encoding]::ASCII.GetString($nameBytes)).Trim([char]0) } else { $mac }
        $hfpEnabled = @($hfpKeys | ForEach-Object { (Get-ItemProperty $_.PSPath).Enabled }) -contains 1
        [pscustomobject]@{
            Name = $name; Mac = $mac
            Connected          = [bool]($present | Where-Object InstanceId -like "BTHENUM\DEV_$mac\*")
            A2dpEndpointActive = [bool]($endpoints | Where-Object FriendlyName -like "*($name)")
            HfpServiceEnabled  = $hfpEnabled
            HfpDevicePresent   = [bool]($present | Where-Object InstanceId -like "BTHENUM\$HFP_AG*$mac*")
            HfpRegKeys         = $hfpKeys
        }
    }
}

function Wait-A2dp($mac, $seconds = 30) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        $d = Get-PairedAudioDevices | Where-Object Mac -eq $mac
        if ($d.A2dpEndpointActive) { return $true }
        Start-Sleep 1
    }
    $false
}

# BluetoothSetServiceState is what the Services tab / Settings toggle call. Falls back to the registry.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class BtSvc {
  [StructLayout(LayoutKind.Sequential)] public struct SYSTEMTIME { public ushort y,m,dow,d,h,mi,s,ms; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct BLUETOOTH_DEVICE_INFO {
    public uint dwSize; public ulong Address; public uint ulClassofDevice;
    public int fConnected; public int fRemembered; public int fAuthenticated;
    public SYSTEMTIME stLastSeen; public SYSTEMTIME stLastUsed;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=248)] public string szName;
  }
  [DllImport("bthprops.cpl", SetLastError=true)]
  static extern uint BluetoothSetServiceState(IntPtr hRadio, ref BLUETOOTH_DEVICE_INFO pbtdi, ref Guid pGuidService, uint dwServiceFlags);
  public static uint SetState(ulong addr, Guid svc, bool enable) {
    var i = new BLUETOOTH_DEVICE_INFO();
    i.dwSize = (uint)Marshal.SizeOf(typeof(BLUETOOTH_DEVICE_INFO)); i.Address = addr; i.szName = "";
    return BluetoothSetServiceState(IntPtr.Zero, ref i, ref svc, enable ? 1u : 0u);
  }
}
'@ -ErrorAction SilentlyContinue

function Disable-HandsFree($dev) {
    $addr = [Convert]::ToUInt64($dev.Mac, 16)
    foreach ($g in $HFP_AG, $HSP_AG) {
        $rc = [BtSvc]::SetState($addr, [Guid]$g, $false)
        if ($rc -notin 0, 1168) { Write-Host "  BluetoothSetServiceState($g) returned $rc, using registry" }  # 1168 = not found
    }
    foreach ($k in $dev.HfpRegKeys) { Set-ItemProperty $k.PSPath -Name Enabled -Value 0 -Type DWord }
}

# ---------------------------------------------------------------- modes
function Show-Status {
    Write-Host "== Bluetooth radios =="
    foreach ($r in Get-BtRadios) {
        $pm = Get-RadioPowerMgmt $r
        $pmText = if ($pm) { if ($pm.Enable) { 'ON (bad)' } else { 'off (good)' } } else { 'n/a' }
        Write-Host ("  {0}`n    power state: {1}   allow-OS-to-turn-off: {2}" -f $r.FriendlyName, (Get-RadioPowerState $r), $pmText)
    }
    $susp = (powercfg /q SCHEME_CURRENT $SUB_USB $USB_SUSP | Select-String 'Current AC Power Setting Index') -replace '.*:\s*', ''
    Write-Host ("  USB selective suspend (AC): {0}" -f $(if ($susp -match '0$') { 'off (good)' } else { 'ON (bad)' }))
    Write-Host "== Paired audio devices =="
    foreach ($d in Get-PairedAudioDevices) {
        Write-Host ("  {0} [{1}]" -f $d.Name, $d.Mac)
        Write-Host ("    connected: {0}   A2DP endpoint active: {1}" -f $d.Connected, $d.A2dpEndpointActive)
        Write-Host ("    HFP service enabled: {0}   HFP device present: {1}" -f $d.HfpServiceEnabled, $d.HfpDevicePresent)
    }
}

function Invoke-Apply {
    Write-Host "== Radios: disable power management =="
    foreach ($r in Get-BtRadios) {
        $pm = Get-RadioPowerMgmt $r
        if ($pm -and $pm.Enable) {
            $pm | Set-CimInstance -Property @{ Enable = $false }
            Write-Host "  $($r.FriendlyName): allow-OS-to-turn-off -> off"
        } else { Write-Host "  $($r.FriendlyName): already off" }
    }
    Write-Host "== Power plan: USB selective suspend off =="
    powercfg /setacvalueindex SCHEME_CURRENT $SUB_USB $USB_SUSP 0 | Out-Null
    powercfg /setdcvalueindex SCHEME_CURRENT $SUB_USB $USB_SUSP 0 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    Write-Host "== Paired audio devices: disable Handsfree Telephony =="
    $devs = @(Get-PairedAudioDevices)
    foreach ($d in $devs) {
        if ($d.HfpServiceEnabled) { Disable-HandsFree $d; Write-Host "  $($d.Name): HFP -> disabled" }
        else { Write-Host "  $($d.Name): HFP already disabled" }
    }
    Write-Host "== Toggle radio so the settings take effect =="
    $connected = $devs | Where-Object Connected
    Restart-BtRadio
    foreach ($d in $connected) {
        Write-Host ("  {0}: A2DP back = {1}" -f $d.Name, (Wait-A2dp $d.Mac))
    }
    Show-Status
}

function Invoke-Kick {
    $devs = @(Get-PairedAudioDevices | Where-Object Connected)
    if (-not $devs) { Write-Host 'No connected Bluetooth audio device.'; return }
    if (-not ($devs | Where-Object { -not $_.A2dpEndpointActive })) { Write-Host 'A2DP already active on every connected device.'; return }
    $t0 = Get-Date
    Write-Host 'Toggling Bluetooth radio off/on...'
    Restart-BtRadio
    foreach ($d in $devs) {
        $ok = Wait-A2dp $d.Mac
        Write-Host ("  {0}: {1} after {2:n1}s" -f $d.Name, $(if ($ok) { 'A2DP active' } else { 'still no A2DP endpoint' }), ((Get-Date) - $t0).TotalSeconds)
    }
}

try {
    if ($Apply) { Invoke-Apply }
    elseif ($Kick) { Invoke-Kick }
    else { Show-Status }
} finally {
    if ($LogPath) { Stop-Transcript | Out-Null }
}
