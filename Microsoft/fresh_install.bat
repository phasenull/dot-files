icacls %USERPROFILE%\Downloads /deny Everyone:(OI)(IO)(X)
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" ^
 /v AppsUseLightTheme /t REG_DWORD /d 0 /f

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" ^
 /v SystemUsesLightTheme /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" ^
 /v EnableTransparency /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ^
 /v HideFileExt /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ^
 /v Hidden /t REG_DWORD /d 1 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ^
 /v ShowSuperHidden /t REG_DWORD /d 1 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ^
 /v LaunchTo /t REG_DWORD /d 1 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" ^
 /v ShowRecent /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" ^
 /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ^
 /v TaskbarDa /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ^
 /v TaskbarMn /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ^
 /v ShowCopilotButton /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" ^
 /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" ^
 /v Enabled /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy" ^
 /v TailoredExperiencesWithDiagnosticDataEnabled ^
 /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" ^
 /v SystemPaneSuggestionsEnabled /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" ^
 /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ^
 /v Start_IrisRecommendations /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" ^
 /v AllowTelemetry /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Siuf\Rules" ^
 /v NumberOfSIUFInPeriod /t REG_DWORD /d 0 /f
 
reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" ^
 /f /ve
reg add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d 0 /f
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d 0 /f
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" ^
 /v LongPathsEnabled /t REG_DWORD /d 1 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" ^
 /v FullPath /t REG_DWORD /d 1 /f
reg add "HKCU\Control Panel\Accessibility\StickyKeys" ^
 /v Flags /t REG_SZ /d 506 /f
reg add "HKCU\Control Panel\Accessibility\ToggleKeys" ^
 /v Flags /t REG_SZ /d 58 /f
reg add "HKCU\Control Panel\Desktop" ^
 /v UserPreferencesMask /t REG_BINARY /d 9012038010000000 /f


reg add "HKCU\Keyboard Layout\Toggle" /v "Language Hotkey" /t REG_SZ /d 3 /f
reg add "HKCU\Keyboard Layout\Toggle" /v "Layout Hotkey" /t REG_SZ /d 3 /f
reg add "HKCU\Keyboard Layout\Toggle" /v "Hotkey" /t REG_SZ /d 3 /f



powercfg /hibernate off
powercfg /change monitor-timeout-ac 20

taskkill /f /im explorer.exe
start explorer.exe

powershell -NoProfile -ExecutionPolicy Bypass -File bt-audio-fix.ps1 -Apply
@REM ---------- dev toolchain (mirrors darwin/.zshrc + 02-bun.sh) ----------
winget install -e --id Microsoft.VisualStudioCode --silent --accept-package-agreements --accept-source-agreements --override "/VERYSILENT /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,addtopath"
winget install -e --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
winget install -e --id Oven-sh.Bun --silent --accept-package-agreements --accept-source-agreements

@REM roblox-ts (rbxtsc) as a global npm package. npm is not on this shell's PATH yet, so call it by path.
"%ProgramFiles%\nodejs\npm.cmd" install -g roblox-ts

@REM Rokit: latest release zip from GitHub, then its own self-install
@REM (copies itself to %USERPROFILE%\.rokit\bin and puts that on PATH). Rojo is then a Rokit-managed tool.
powershell -NoProfile -Command "$a = (Invoke-RestMethod https://api.github.com/repos/rojo-rbx/rokit/releases/latest).assets | Where-Object name -like '*windows-x86_64.zip'; Invoke-WebRequest $a.browser_download_url -OutFile \"$env:TEMP\rokit.zip\"; Expand-Archive \"$env:TEMP\rokit.zip\" \"$env:TEMP\rokit\" -Force; & \"$env:TEMP\rokit\rokit.exe\" self-install"
"%USERPROFILE%\.rokit\bin\rokit.exe" add --global rojo-rbx/rojo

@REM ---------- VS Code config from vsc/ ----------
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\vsc\import.ps1"

curl -L -o "%TEMP%\Cloudflare_WARP.msi" https://downloads.cloudflareclient.com/v1/download/windows/ga
start /wait "" "%TEMP%\Cloudflare_WARP.msi"
@REM del "%TEMP%\Cloudflare_WARP.msi"

