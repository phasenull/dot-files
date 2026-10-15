<#
.SYNOPSIS
  Rebuild Brave settings from the files written by brave-export.ps1.

.DESCRIPTION
  Fresh profile (no Preferences file yet, or -Replace): seeds Preferences, Local State and optionally
  Bookmarks before Brave's first launch, and writes the "First Run" marker so the first-run dialog is skipped.

  Existing profile: deep-merges the preferences and Local State into what is there.

  Protected prefs (startup behaviour, homepage, a non-default search engine) are signed per machine and
  Brave discards unsigned copies, so they are applied as Brave policies under HKCU instead. Extensions are
  applied the same way, with installation_mode "normal_installed": Brave installs them from the Web Store
  on its own and you can still disable or remove them. Any policy makes Brave show "managed by your
  organization" in its menu and locks those specific settings. -NoPolicy skips every policy write and
  prints what to set by hand instead.

  Brave must be closed. -Force closes it for you. Policy writes need an elevated shell.

.EXAMPLE
  .\brave-import.ps1 -Force               # fresh machine after winget installed Brave
  .\brave-import.ps1 -Force -Replace      # wipe the profile Brave's installer created and seed it
#>
[CmdletBinding()]
param(
    [string]$UserDataDir = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data",
    [string]$Profile = 'Default',
    [string]$InDir,
    [string]$PolicyKey = 'HKCU:\SOFTWARE\Policies\BraveSoftware\Brave',
    [switch]$Force,
    [switch]$Replace,
    [switch]$NoPolicy,
    [switch]$SkipBookmarks
)
$ErrorActionPreference = 'Stop'
if (-not $InDir) { $InDir = Split-Path -Parent $PSCommandPath }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $NoPolicy -and -not $isAdmin -and $PolicyKey -like '*\Policies\*') { throw 'Writing Brave policies needs an elevated shell (HKCU\Software\Policies is admin-only). Run elevated, or pass -NoPolicy.' }

# ---------------------------------------------------------------- JSON in / out
Add-Type -AssemblyName System.Web.Extensions
$js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$js.MaxJsonLength = [int]::MaxValue
$js.RecursionLimit = 200
function Read-Json($path) { $js.DeserializeObject((Get-Content $path -Raw -Encoding UTF8)) }

function Json-Escape([string]$s) {
    [regex]::Replace($s, '["\\\x00-\x1f]', { param($m) switch ($m.Value) { '"' { '\"' } '\' { '\\' } "`n" { '\n' } "`r" { '\r' } "`t" { '\t' } default { '\u{0:x4}' -f [int][char]$m.Value } } })
}
function ConvertTo-JsonText($v, [int]$level = 0, [switch]$Compact) {
    $nl = if ($Compact) { '' } else { "`n" }
    $pad = if ($Compact) { '' } else { '  ' * ($level + 1) }
    $padEnd = if ($Compact) { '' } else { '  ' * $level }
    if ($null -eq $v) { return 'null' }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [string]) { return '"' + (Json-Escape $v) + '"' }
    if ($v -is [System.Collections.IDictionary]) {
        if ($v.Count -eq 0) { return '{}' }
        $sep = if ($Compact) { ':' } else { ': ' }
        $items = foreach ($k in @($v.Keys)) { $pad + '"' + (Json-Escape ([string]$k)) + '"' + $sep + (ConvertTo-JsonText $v[$k] ($level + 1) -Compact:$Compact) }
        return '{' + $nl + ($items -join (',' + $nl)) + $nl + $padEnd + '}'
    }
    if ($v -is [System.Collections.IList]) {
        if ($v.Count -eq 0) { return '[]' }
        $items = foreach ($e in $v) { $pad + (ConvertTo-JsonText $e ($level + 1) -Compact:$Compact) }
        return '[' + $nl + ($items -join (',' + $nl)) + $nl + $padEnd + ']'
    }
    if ($v -is [ValueType]) { return [Convert]::ToString($v, [Globalization.CultureInfo]::InvariantCulture) }
    return '"' + (Json-Escape ([string]$v)) + '"'
}
function Write-Json($obj, $path) { [IO.File]::WriteAllText($path, (ConvertTo-JsonText $obj), (New-Object Text.UTF8Encoding $false)) }

# ---------------------------------------------------------------- helpers
function New-Dict { New-Object 'System.Collections.Generic.Dictionary[string,object]' }
function Expand($value) {
    if ($value -is [System.Collections.IDictionary]) {
        $out = New-Dict
        foreach ($k in @($value.Keys)) { $out[$k] = Expand $value[$k] }
        return $out
    }
    if ($value -is [array]) { return ,@($value | ForEach-Object { Expand $_ }) }
    if ($value -is [string]) { return $value.Replace('%USERPROFILE%', $env:USERPROFILE) }
    $value
}
function Merge-Into($target, $source) {
    foreach ($k in @($source.Keys)) {
        if ($source[$k] -is [System.Collections.IDictionary] -and $target.ContainsKey($k) -and $target[$k] -is [System.Collections.IDictionary]) {
            Merge-Into $target[$k] $source[$k]
        } else { $target[$k] = $source[$k] }
    }
}
function Count-Leaves($d) {
    $n = 0
    foreach ($v in $d.Values) { if ($v -is [System.Collections.IDictionary]) { $n += Count-Leaves $v } else { $n++ } }
    $n
}
function Get-Path($obj, [string]$path) {
    $cur = $obj
    foreach ($k in $path.Split('.')) {
        if ($cur -is [System.Collections.IDictionary] -and $cur.ContainsKey($k)) { $cur = $cur[$k] } else { return $null }
    }
    $cur
}
function Set-Policy([string]$name, $value, [string]$type) {
    if (-not (Test-Path $PolicyKey)) { New-Item -Path $PolicyKey -Force | Out-Null }
    Set-ItemProperty -Path $PolicyKey -Name $name -Value $value -Type $type
    Write-Host "  policy $name = $value"
}
function Set-PolicyList([string]$name, [string[]]$values) {
    $sub = Join-Path $PolicyKey $name
    if (Test-Path $sub) { Remove-Item $sub -Recurse -Force }
    New-Item -Path $sub -Force | Out-Null
    for ($i = 0; $i -lt $values.Count; $i++) { Set-ItemProperty -Path $sub -Name ($i + 1) -Value $values[$i] -Type String }
    Write-Host "  policy $name = $($values -join ', ')"
}

# ---------------------------------------------------------------- load
$settingsPath = Join-Path $InDir 'brave-settings.json'
if (-not (Test-Path $settingsPath)) { throw "brave-settings.json not found in $InDir" }
$settings = Read-Json $settingsPath

$liveDir = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
if ($UserDataDir -eq $liveDir -and (Get-Process brave -ErrorAction SilentlyContinue)) {
    if (-not $Force) { throw 'Brave is running. Close it or pass -Force.' }
    Stop-Process -Name brave -Force
    Start-Sleep 2
}

# ---------------------------------------------------------------- profile preferences
$profDir = Join-Path $UserDataDir $Profile
if ($Replace -and (Test-Path $profDir)) {
    Write-Host "removing existing profile $profDir"
    [IO.Directory]::Delete($profDir, $true)
}
$fresh = -not (Test-Path "$profDir\Preferences")
New-Item -ItemType Directory -Force $profDir | Out-Null
$prefs = Expand $settings['preferences']
$local = Expand $settings['local_state']

if ($fresh) {
    Write-Json $prefs "$profDir\Preferences"
    New-Item -ItemType File -Force "$UserDataDir\First Run" | Out-Null
    Write-Host ("fresh profile seeded with {0} preferences" -f (Count-Leaves $prefs))
    $bmPath = Join-Path $InDir 'brave-bookmarks.json'
    if (-not $SkipBookmarks -and (Test-Path $bmPath)) {
        Copy-Item $bmPath "$profDir\Bookmarks" -Force
        Write-Host 'bookmarks seeded'
    }
} else {
    $existing = Read-Json "$profDir\Preferences"
    Merge-Into $existing $prefs
    Write-Json $existing "$profDir\Preferences"
    Write-Host ("existing profile: merged {0} preferences" -f (Count-Leaves $prefs))
}

$localPath = Join-Path $UserDataDir 'Local State'
$ls = if (Test-Path $localPath) { Read-Json $localPath } else { New-Dict }
Merge-Into $ls $local
Write-Json $ls $localPath
Write-Host ("local state: merged {0} values" -f (Count-Leaves $local))

# ---------------------------------------------------------------- protected prefs -> policy
$prot = $settings['protected_preferences']
$byHand = New-Object System.Collections.Generic.List[string]
if ($prot) {
    Write-Host 'protected prefs:'
    $restore = Get-Path $prot 'session.restore_on_startup'      # 1 = last session, 4 = these pages, 5 = new tab
    $urls = Get-Path $prot 'session.startup_urls'
    $homeUrl = Get-Path $prot 'homepage'
    $homeNtp = Get-Path $prot 'homepage_is_newtabpage'
    $search = Get-Path $prot 'default_search_provider_data'
    $customSearch = $search -and $search['prepopulate_id'] -ne 550   # 550 = Brave Search, Brave's own default
    if ($NoPolicy) {
        if ($null -ne $restore) { $byHand.Add("On startup: $(@{1='continue where you left off';4='open specific pages';5='open new tab page'}[[int]$restore]) $(if ($urls) { '(' + ($urls -join ', ') + ')' })") }
        if ($homeUrl) { $byHand.Add("Home page: $homeUrl") }
        if ($customSearch) { $byHand.Add("Default search: $($search['short_name']) $($search['url'])") }
    } else {
        if ($null -ne $restore) { Set-Policy RestoreOnStartup ([int]$restore) DWord }
        if ($urls -and $urls.Count) { Set-PolicyList RestoreOnStartupURLs ([string[]]$urls) }
        if ($homeUrl) { Set-Policy HomepageLocation ([string]$homeUrl) String }
        if ($null -ne $homeNtp) { Set-Policy HomepageIsNewTabPage ([int][bool]$homeNtp) DWord }
        if ($customSearch) {
            Set-Policy DefaultSearchProviderEnabled 1 DWord
            Set-Policy DefaultSearchProviderName ([string]$search['short_name']) String
            Set-Policy DefaultSearchProviderKeyword ([string]$search['keyword']) String
            Set-Policy DefaultSearchProviderSearchURL ([string]$search['url']) String
            if ($search['suggestions_url']) { Set-Policy DefaultSearchProviderSuggestURL ([string]$search['suggestions_url']) String }
            if ($search['favicon_url']) { Set-Policy DefaultSearchProviderIconURL ([string]$search['favicon_url']) String }
        } elseif ($search) { Write-Host '  search engine is Brave Search (default), no policy needed' }
    }
}

# ---------------------------------------------------------------- extensions -> policy
$extPath = Join-Path $InDir 'brave-extensions.json'
if (Test-Path $extPath) {
    $exts = @(Read-Json $extPath)
    if ($exts.Count -and -not $NoPolicy) {
        $policy = New-Dict
        foreach ($e in $exts) {
            $entry = New-Dict
            $entry['installation_mode'] = 'normal_installed'
            $entry['update_url'] = 'https://clients2.google.com/service/update2/crx'
            $policy[$e['id']] = $entry
        }
        if (-not (Test-Path $PolicyKey)) { New-Item -Path $PolicyKey -Force | Out-Null }
        Set-ItemProperty -Path $PolicyKey -Name ExtensionSettings -Value (ConvertTo-JsonText $policy -Compact) -Type String
        Write-Host "  policy ExtensionSettings: $(($exts | ForEach-Object { $_['name'] }) -join ', ')"
    } elseif ($exts.Count) {
        $exts | ForEach-Object { $byHand.Add("Extension: $($_['name'])  https://chromewebstore.google.com/detail/$($_['id'])") }
    }
}
if ($byHand.Count) { Write-Host 'set by hand (-NoPolicy):'; $byHand | ForEach-Object { Write-Host "  $_" } }
Write-Host 'done. Start Brave.'
