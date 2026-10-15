<#
.SYNOPSIS
  Apply the VS Code config in this folder: settings, keybindings, snippets and extensions.

.DESCRIPTION
  Copies user-settings.json (with %USERPROFILE% expanded), keybindings.json and snippets/ into the VS Code
  user directory, keeping a one-time .bak of any file it replaces, then installs every extension listed in
  extensions.txt that is not installed yet. VS Code can stay open; it picks the files up live.

.EXAMPLE
  .\import.ps1
  .\import.ps1 -SkipExtensions
#>
[CmdletBinding()]
param(
    [string]$UserDir = "$env:APPDATA\Code\User",
    [string]$InDir,
    [string]$Code,
    [switch]$SkipExtensions
)
$ErrorActionPreference = 'Stop'
if (-not $InDir) { $InDir = Split-Path -Parent $PSCommandPath }
if (-not $Code) {
    $Code = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd", "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $Code) { $Code = (Get-Command code -ErrorAction SilentlyContinue).Source }
}
$enc = New-Object Text.UTF8Encoding $false
New-Item -ItemType Directory -Force $UserDir | Out-Null

function Backup($path) { if ((Test-Path $path) -and -not (Test-Path "$path.bak")) { Copy-Item $path "$path.bak" } }

# ---------------------------------------------------------------- settings, keybindings, snippets
$settings = Get-Content (Join-Path $InDir 'user-settings.json') -Raw -Encoding UTF8
$settings = $settings.Replace('%USERPROFILE%', $env:USERPROFILE.Replace('\', '/'))
Backup "$UserDir\settings.json"
[IO.File]::WriteAllText("$UserDir\settings.json", $settings, $enc)
Write-Host 'settings.json applied'

if (Test-Path (Join-Path $InDir 'keybindings.json')) {
    Backup "$UserDir\keybindings.json"
    Copy-Item (Join-Path $InDir 'keybindings.json') "$UserDir\keybindings.json" -Force
    Write-Host 'keybindings.json applied'
}
if (Test-Path (Join-Path $InDir 'snippets')) {
    New-Item -ItemType Directory -Force "$UserDir\snippets" | Out-Null
    Copy-Item (Join-Path $InDir 'snippets\*') "$UserDir\snippets" -Force
    Write-Host "snippets applied ($((Get-ChildItem (Join-Path $InDir 'snippets')).Count) files)"
}

# ---------------------------------------------------------------- extensions
$listPath = Join-Path $InDir 'extensions.txt'
if ($SkipExtensions -or -not (Test-Path $listPath)) { exit 0 }
if (-not $Code) { Write-Host 'code.cmd not found, extensions skipped'; exit 0 }
$wanted = Get-Content $listPath | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
$have = & $Code --list-extensions 2>$null
$missing = $wanted | Where-Object { $have -notcontains $_ }
Write-Host "extensions: $($wanted.Count) wanted, $($missing.Count) to install"
foreach ($id in $missing) {
    & $Code --install-extension $id --force 2>&1 | Select-String -Pattern 'successfully|already|failed|error' | ForEach-Object { Write-Host "  $id : $($_.Line.Trim())" }
}
