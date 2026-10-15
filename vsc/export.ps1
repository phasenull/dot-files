<#
.SYNOPSIS
  Export VS Code user config into this folder: user-settings.json, keybindings.json, snippets/, extensions.txt.

.DESCRIPTION
  Scrubbing, in order:
    1. "remote.SSH.remotePlatform" is emptied (it lists your SSH hosts and IPs).
    2. Your user profile path becomes %USERPROFILE% so the file works under any user name.
    3. Any key that looks like a credential, or any long opaque string value, aborts the export with the
       offending line printed. Remove it from settings.json (or keep it in VS Code's secret storage instead).
  Comments and formatting of settings.json are preserved; it is edited as text, not re-serialized.

.EXAMPLE
  .\export.ps1
#>
[CmdletBinding()]
param(
    [string]$UserDir = "$env:APPDATA\Code\User",
    [string]$OutDir,
    [string]$Code
)
$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Split-Path -Parent $PSCommandPath }
if (-not $Code) {
    $Code = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd", "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $Code) { $Code = (Get-Command code -ErrorAction SilentlyContinue).Source }
}
$enc = New-Object Text.UTF8Encoding $false

# ---------------------------------------------------------------- settings.json
$settings = Get-Content "$UserDir\settings.json" -Raw -Encoding UTF8
$settings = [regex]::Replace($settings, '("remote\.SSH\.remotePlatform"\s*:\s*)\{[^}]*\}', '$1{}')
$up = $env:USERPROFILE
foreach ($form in $up, $up.Replace('\', '/'), $up.Replace('\', '\\')) {
    $settings = [regex]::Replace($settings, [regex]::Escape($form), '%USERPROFILE%', 'IgnoreCase')
}
$bad = @()
foreach ($line in ($settings -split "`r?`n")) {
    if ($line -match '^\s*"[^"]*(token|secret|password|apikey|api_key|credential|private)[^"]*"\s*:') { $bad += $line.Trim() }
    elseif ($line -match ':\s*"[A-Za-z0-9+/_=-]{32,}"') { $bad += $line.Trim() }
}
if ($bad.Count) {
    Write-Host 'export aborted, these lines in settings.json look like secrets:'
    $bad | ForEach-Object { Write-Host "  $_" }
    exit 1
}
New-Item -ItemType Directory -Force $OutDir | Out-Null
[IO.File]::WriteAllText((Join-Path $OutDir 'user-settings.json'), $settings, $enc)

# ---------------------------------------------------------------- keybindings, snippets
Copy-Item "$UserDir\keybindings.json" (Join-Path $OutDir 'keybindings.json') -Force
if (Test-Path "$UserDir\snippets") {
    $snip = Join-Path $OutDir 'snippets'
    New-Item -ItemType Directory -Force $snip | Out-Null
    Copy-Item "$UserDir\snippets\*" $snip -Force
}

# ---------------------------------------------------------------- extensions
if ($Code) {
    $exts = & $Code --list-extensions 2>$null | Where-Object { $_ } | Sort-Object
    [IO.File]::WriteAllText((Join-Path $OutDir 'extensions.txt'), (($exts -join "`n") + "`n"), $enc)
    Write-Host "wrote user-settings.json, keybindings.json, snippets/, extensions.txt ($($exts.Count) extensions) to $OutDir"
} else {
    Write-Host "wrote user-settings.json, keybindings.json, snippets/ to $OutDir (code.cmd not found, extensions.txt left as is)"
}
