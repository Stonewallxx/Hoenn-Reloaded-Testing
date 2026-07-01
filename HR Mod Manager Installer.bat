@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Hoenn Reloaded - Mod Manager Update
color 0A

:: ============================================================
::  CONFIG
:: ============================================================
set "REPO_RAW=https://raw.githubusercontent.com/infinitefusion/infinitefusion-hoenn-public/releases"
set "TARGET=%~dp0Reloaded"
set "MM_VER_FILE=Reloaded\001_ModManager.rb"

:: Files to update (all relative to Reloaded/ in the repo)
set "FILES=001_ModManager.rb 002_ModManagerUI.rb 003_ModderTools.rb 004_Logging.rb"

:: ============================================================
::  Must be run from game root
:: ============================================================
if not exist "Game.exe" if not exist "Game.rxproj" (
    color 0C
    echo.
    echo  [ERROR] Run this from inside your Hoenn Reloaded game folder.
    echo.
    pause
    exit /b 1
)

if not exist "%TARGET%" (
    color 0C
    echo.
    echo  [ERROR] Reloaded\ folder not found. Your installation may be incomplete.
    echo.
    pause
    exit /b 1
)

:: ============================================================
::  Read local MM version
:: ============================================================
set "LOCAL_MM_VER=unknown"
if exist "%MM_VER_FILE%" (
    for /f "usebackq tokens=*" %%A in (
        `powershell -NoProfile -Command "$m=(Select-String 'VERSION\s*=\s*""(.+)""' '%MM_VER_FILE%'); if($m){$m.Matches[0].Groups[1].Value}else{'unknown'}"`
    ) do set "LOCAL_MM_VER=%%A"
)

:: ============================================================
::  Fetch remote MM version for preview
:: ============================================================
set "REMOTE_MM_VER=unknown"
for /f "usebackq tokens=*" %%A in (
    `powershell -NoProfile -Command "try{$r=(Invoke-WebRequest -Uri '%REPO_RAW%/Reloaded/001_ModManager.rb' -UseBasicParsing -TimeoutSec 5).Content; $m=[regex]::Match($r,'VERSION\s*=\s*""(.+)""'); if($m.Success){$m.Groups[1].Value}else{'unknown'}}catch{'unknown'}"`
) do set "REMOTE_MM_VER=%%A"

:: ============================================================
::  Header
:: ============================================================
echo.
echo  ============================================================
echo   Hoenn Reloaded  ^|  Mod Manager Update
echo  ============================================================
echo   Installed MM Version  : !LOCAL_MM_VER!
echo   Available MM Version  : !REMOTE_MM_VER!
echo  ------------------------------------------------------------
echo.
echo   Updates only the 4 Mod Manager script files:
echo     001_ModManager.rb
echo     002_ModManagerUI.rb
echo     003_ModderTools.rb
echo     004_Logging.rb
echo.
echo   All other game files are NOT touched.
echo   Your saves will NOT be affected.
echo  ============================================================
echo.
set /p "go=  Press ENTER to update, or close this window to cancel: "
echo.

:: ============================================================
::  Pick downloader: curl (Win10+) or PowerShell fallback
:: ============================================================
where curl >NUL 2>&1
if %errorlevel%==0 (
    set "USE_CURL=1"
) else (
    set "USE_CURL=0"
    echo  [INFO] curl not found, using PowerShell to download.
    echo.
)

:: ============================================================
::  Download each file
:: ============================================================
set "FAILED=0"
set "COUNT=0"

for %%F in (%FILES%) do (
    set /a COUNT+=1
    echo  [!COUNT!] Downloading %%F...

    if "!USE_CURL!"=="1" (
        curl --ssl-no-revoke -fSL -o "%TARGET%\%%F" "%REPO_RAW%/Reloaded/%%F"
    ) else (
        powershell -NoProfile -Command ^
          "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try{Invoke-WebRequest -Uri '%REPO_RAW%/Reloaded/%%F' -OutFile '%TARGET%\%%F' -UseBasicParsing}catch{Write-Host '  FAILED: '+$_.Exception.Message; exit 1}"
    )

    if !errorlevel! neq 0 (
        echo  [WARN] Failed: %%F
        set "FAILED=1"
    ) else (
        echo  [OK]   %%F
    )
)

:: ============================================================
::  Read new MM version
:: ============================================================
set "NEW_MM_VER=unknown"
if exist "%MM_VER_FILE%" (
    for /f "usebackq tokens=*" %%A in (
        `powershell -NoProfile -Command "$m=(Select-String 'VERSION\s*=\s*""(.+)""' '%MM_VER_FILE%'); if($m){$m.Matches[0].Groups[1].Value}else{'unknown'}"`
    ) do set "NEW_MM_VER=%%A"
)

:: ============================================================
::  Done
:: ============================================================
echo.
if "!FAILED!"=="0" (
    color 0A
    echo  ============================================================
    echo   Mod Manager Update Complete!
    echo  ------------------------------------------------------------
    echo   Previous Version  : !LOCAL_MM_VER!
    echo   Installed Version : !NEW_MM_VER!
    echo  ============================================================
) else (
    color 0E
    echo  ============================================================
    echo   Update finished with errors - some files may not have
    echo   downloaded. Check your internet connection and try again.
    echo  ============================================================
)
echo.
pause
