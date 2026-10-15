<#
.SYNOPSIS
  Export Brave settings to JSON files you can commit to a dotfiles repo, with secrets kept out.

.DESCRIPTION
  Writes, in -OutDir (default: next to this script):
    brave-settings.json    allowlisted keys from Preferences and Local State, plus the few "protected"
                           prefs (startup, homepage, search engine) that brave-import.ps1 applies as policy
    brave-extensions.json  ids + names of Web Store extensions (installed on import through a policy)
    brave-bookmarks.json   only with -Bookmarks (sync metadata and checksum stripped). Bookmarks are not
                           secrets but they are private; do not commit them to a public repo.

  Safety model, in order:
    1. ALLOWLIST: only the listed pref paths are read at all. Everything else (sync seed, wallet keyrings,
       rewards, password hashes, site history, window geometry, metrics) is never touched.
    2. DENYLIST: inside the allowed subtrees, keys that look like secrets or metrics are dropped and listed.
    3. VALUE SCAN: any long opaque string (base64/hex blob, GUID) is dropped and listed.
    4. Your user profile path is replaced by %USERPROFILE% so the export is machine-independent.
  Review the output once before the first commit; it is small and readable.

.EXAMPLE
  .\brave-export.ps1
  .\brave-export.ps1 -Bookmarks
#>
[CmdletBinding()]
param(
    [string]$UserDataDir = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data",
    [string]$Profile = 'Default',
    [string]$OutDir,
    [switch]$Bookmarks
)
$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Split-Path -Parent $PSCommandPath }

# Dotted paths. A path selects that whole subtree. Add to these lists when Brave grows a setting you care about.
$ALLOW_PREFS = @(
    'alternate_error_pages', 'bookmark_bar', 'NewTabPage', 'ntp', 'intl', 'spellcheck', 'settings',
    'tab_search', 'toolbar', 'vertical_tabs', 'webkit.webprefs', 'translate', 'translate_blocked_languages',
    'credentials_enable_service', 'credentials_enable_autosignin', 'download', 'savefile',
    'omnibox.prevent_url_elisions', 'search.suggest_enabled', 'privacy_sandbox.first_party_sets_enabled',
    'safebrowsing.enabled', 'safebrowsing.enhanced', 'https_only_mode_enabled', 'https_only_mode_auto_enabled',
    'autofill.credit_card_enabled', 'autofill.profile_enabled', 'payments.can_make_payment_enabled',
    'profile.name', 'profile.avatar_index', 'profile.default_content_setting_values',
    'browser.clear_data', 'browser.theme', 'browser.show_home_button', 'browser.has_seen_welcome_page',
    'browser.enable_spellchecking', 'browser.confirm_to_quit',
    'brave.accelerators', 'brave.ai_chat', 'brave.always_show_bookmark_bar_on_ntp', 'brave.autocomplete_enabled',
    'brave.ask_widevine_install', 'brave.enable_media_router_on_restart', 'brave.enable_window_closing_confirm',
    'brave.has_seen_brave_welcome_page', 'brave.location_bar_is_wide', 'brave.new_tab_page', 'brave.omnibox',
    'brave.search', 'brave.shields', 'brave.no_script_default', 'brave.show_bookmarks_button',
    'brave.show_side_panel_button', 'brave.sidebar', 'brave.tabs', 'brave.top_site_suggestions_enabled',
    'brave.webtorrent_enabled', 'brave.hangouts_enabled', 'brave.ipfs', 'brave.speedreader',
    'brave.web_discovery.enabled', 'brave.today.opted_in', 'brave.today.should_show_toolbar_button',
    'brave.rewards.show_brave_rewards_button_in_location_bar', 'brave.rewards.inline_tip_buttons_enabled',
    'brave.wallet.default_wallet2', 'brave.wallet.default_solana_wallet', 'brave.wallet.show_wallet_icon_on_toolbar',
    'brave.brave_vpn.show_button', 'brave.playlist.enabled', 'brave.de_amp.enabled', 'brave.debounce.enabled',
    'brave.reduce_language', 'brave.google_login_default', 'brave.fb_embed_default', 'brave.twitter_embed_default',
    'brave.linkedin_embed_default', 'brave.ethereum_provider', 'brave.solana_provider', 'brave.cardano_provider'
)
# Signed ("protected") prefs. Brave refuses unsigned copies, so brave-import.ps1 applies these as policy.
$ALLOW_PROTECTED = @(
    'default_search_provider_data.template_url_data', 'session.restore_on_startup', 'session.startup_urls',
    'homepage', 'homepage_is_newtabpage'
)
$SEARCH_FIELDS = 'short_name', 'keyword', 'url', 'suggestions_url', 'favicon_url', 'prepopulate_id'
$ALLOW_LOCAL = @(
    'browser.enabled_labs_experiments', 'dns_over_https', 'hardware_acceleration_mode',
    'brave.ad_block', 'brave.widevine_opted_in', 'brave.dont_ask_for_crash_reporting',
    'brave.enable_search_suggestions_by_default', 'brave.ai_chat.default_model_key'
)
$DENY_KEY = '(?i)^(protection|sync|brave_sync_v2|os_crypt|keyrings?|password_hash_data_list|install_signature|receiver_id_hash_token|upload_encoding_seed|signin|gaia_cookie|account_values|macs|super_mac|cookie_list_uuid|custom_filters)$|token|seed|secret|signature|passphrase|private_key|mnemonic|encrypted|p3a|metrics'
$DENY_VALUE = '^[A-Za-z0-9+/_=-]{32,}$'   # base64 / hex blobs / GUIDs

# ---------------------------------------------------------------- JSON in (JavaScriptSerializer) / out (own writer)
Add-Type -AssemblyName System.Web.Extensions
$js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$js.MaxJsonLength = [int]::MaxValue
$js.RecursionLimit = 200
function Read-Json($path) { $js.DeserializeObject((Get-Content $path -Raw -Encoding UTF8)) }

# Own JSON writer: deterministic, pretty (git-friendly) and immune to PowerShell's object wrappers.
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
function Get-Path($obj, [string]$path) {
    $cur = $obj
    foreach ($k in $path.Split('.')) {
        if ($cur -is [System.Collections.IDictionary] -and $cur.ContainsKey($k)) { $cur = $cur[$k] } else { return $null }
    }
    $cur
}
function Set-Path($obj, [string]$path, $value) {
    $parts = $path.Split('.'); $cur = $obj
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        if (-not $cur.ContainsKey($parts[$i])) { $cur[$parts[$i]] = New-Dict }
        $cur = $cur[$parts[$i]]
    }
    $cur[$parts[-1]] = $value
}

$script:dropped = New-Object System.Collections.Generic.List[string]
$userProfile = [regex]::Escape($env:USERPROFILE)
function Scrub($value, [string]$where) {
    if ($value -is [System.Collections.IDictionary]) {
        $out = New-Dict
        foreach ($k in @($value.Keys)) {
            if ($k -match $DENY_KEY) { $script:dropped.Add("$where.$k (key name)"); continue }
            $v = Scrub $value[$k] "$where.$k"
            if ($null -ne $v -or $null -eq $value[$k]) { $out[$k] = $v }
        }
        return $out
    }
    if ($value -is [array]) { return ,@($value | ForEach-Object { Scrub $_ "$where[]" }) }
    if ($value -is [string]) {
        if ($value -match $DENY_VALUE) { $script:dropped.Add("$where (opaque value)"); return $null }
        return ($value -replace "(?i)$userProfile", '%USERPROFILE%')
    }
    $value
}
function Export-Subset($source, [string[]]$allow, [string]$label) {
    $out = New-Dict
    foreach ($p in $allow) {
        $v = Get-Path $source $p
        if ($null -eq $v) { continue }
        $clean = Scrub $v "$label.$p"
        if ($null -ne $clean) { Set-Path $out $p $clean }
    }
    $out
}

# ---------------------------------------------------------------- export
$profDir = Join-Path $UserDataDir $Profile
if (-not (Test-Path "$profDir\Preferences")) { throw "No profile at $profDir" }
$prefs  = Read-Json "$profDir\Preferences"
$secure = if (Test-Path "$profDir\Secure Preferences") { Read-Json "$profDir\Secure Preferences" } else { New-Dict }
$local  = Read-Json "$UserDataDir\Local State"

$settings = New-Dict
$settings['exported_at'] = (Get-Date).ToString('s')
$settings['preferences'] = Export-Subset $prefs $ALLOW_PREFS 'preferences'
$protected = Export-Subset $secure $ALLOW_PROTECTED 'protected'
$tu = Get-Path $protected 'default_search_provider_data.template_url_data'
if ($tu) {
    $slim = New-Dict
    foreach ($f in $SEARCH_FIELDS) { if ($tu.ContainsKey($f)) { $slim[$f] = $tu[$f] } }
    $protected['default_search_provider_data'] = $slim
}
$settings['protected_preferences'] = $protected
$settings['local_state'] = Export-Subset $local $ALLOW_LOCAL 'local_state'

# Web Store extensions: id + name only. Component / built-in extensions are skipped.
$exts = New-Object System.Collections.Generic.List[object]
$extSettings = Get-Path $secure 'extensions.settings'
if ($extSettings) {
    foreach ($id in $extSettings.Keys) {
        $e = $extSettings[$id]
        if (-not ($e.ContainsKey('from_webstore') -and $e['from_webstore'])) { continue }
        $name = $null
        if ($e.ContainsKey('manifest') -and $e['manifest'].ContainsKey('name')) { $name = $e['manifest']['name'] }
        if (-not $name -and $e.ContainsKey('path')) {
            $m = Join-Path "$profDir\Extensions" "$($e['path'])\manifest.json"
            if (Test-Path $m) { $name = (Read-Json $m)['name'] }
        }
        $ext = New-Dict; $ext['id'] = $id; $ext['name'] = $name; $ext['enabled'] = ($e['state'] -eq 1)
        $exts.Add($ext)
    }
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
Write-Json $settings (Join-Path $OutDir 'brave-settings.json')
Write-Json $exts.ToArray() (Join-Path $OutDir 'brave-extensions.json')
Write-Host "wrote brave-settings.json and brave-extensions.json ($($exts.Count) extensions) to $OutDir"

if ($Bookmarks -and (Test-Path "$profDir\Bookmarks")) {
    $bm = Read-Json "$profDir\Bookmarks"
    foreach ($k in 'sync_metadata', 'checksum') { if ($bm.ContainsKey($k)) { $bm.Remove($k) | Out-Null } }
    Write-Json $bm (Join-Path $OutDir 'brave-bookmarks.json')
    Write-Host 'wrote brave-bookmarks.json (private: keep out of public repos)'
}

if ($script:dropped.Count) {
    Write-Host "dropped as secret-looking ($($script:dropped.Count)):"
    $script:dropped | ForEach-Object { Write-Host "  $_" }
}
