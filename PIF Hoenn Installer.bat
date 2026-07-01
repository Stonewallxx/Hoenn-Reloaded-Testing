@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Infinite Fusion Hoenn - Installer / Updater
color 0A

:: ============================================================
::  Read current version info before update
:: ============================================================
set "HOENN_VER=unknown"
set "LATEST_VER=unknown"
for /f "usebackq tokens=*" %%A in (`powershell -NoProfile -Command "$l=(Select-String 'HOENN_VERSION_NUMBER' 'Data\Scripts\001_Settings.rb').Line; if($l){($l -replace '.*\x22(.+)\x22.*','$1')}else{'unknown'}"`) do set "HOENN_VER=%%A"
for /f "usebackq tokens=*" %%A in (`powershell -NoProfile -Command "try{$r=(Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/infinitefusion/infinitefusion-hoenn-public/releases/Data/Scripts/001_Settings.rb' -UseBasicParsing -TimeoutSec 5).Content; $l=($r -split '\n' | Select-String 'HOENN_VERSION_NUMBER'); if($l){($l.Line -replace '.*\x22(.+)\x22.*','$1')}else{'unknown'}}catch{'unknown'}"`) do set "LATEST_VER=%%A"

:: ============================================================
::  Header
:: ============================================================
echo.
echo  ==========================================================
echo   Infinite Fusion Hoenn  ^|  Installer ^& Updater
echo  ==========================================================
echo   Current Version  : !HOENN_VER!
echo   Latest Version   : !LATEST_VER!
echo  ----------------------------------------------------------
echo.
echo   This will download the latest release from GitHub
echo   and apply it to your game folder.
echo.
echo   Your saves will NOT be affected by this update.
echo.
echo   SOURCE: github.com/infinitefusion/infinitefusion-hoenn-public
echo  ==========================================================
echo.
set /p "go=  Press ENTER to update, or close this window to cancel: "

echo.
echo  Preparing update...
echo.

:: ============================================================
::  Cleanup stale lock if present
:: ============================================================
if exist ".git\shallow.lock" (
    echo  [INFO] Removing stale git lock...
    erase /f /q ".git\shallow.lock"
)

:: ============================================================
::  Download and apply update
:: ============================================================
set mgit="%~dp0REQUIRED_BY_INSTALLER_UPDATER\cmd\git.exe"

echo  [1/3] Initializing repository...
%mgit% init . >nul 2>&1

echo  [2/3] Fetching latest release from GitHub...
%mgit% remote remove origin >nul 2>&1
%mgit% remote add origin "https://github.com/infinitefusion/infinitefusion-hoenn-public.git" >nul 2>&1
%mgit% fetch --depth=1 origin releases
if %errorlevel% neq 0 (
    echo.
    color 0C
    echo  ==========================================================
    echo   ERROR: Failed to download update.
    echo  ----------------------------------------------------------
    echo   Possible causes:
    echo   - No internet connection
    echo   - GitHub is temporarily unavailable
    echo  ----------------------------------------------------------
    echo   Screenshot this window for further help.
    echo  ==========================================================
    echo.
    pause
    exit /b 1
)

echo  [3/3] Applying update...
%mgit% reset --hard origin/releases

:: ============================================================
::  Re-read version after update
:: ============================================================
set "NEW_HOENN_VER=unknown"
for /f "usebackq tokens=*" %%A in (`powershell -NoProfile -Command "$l=(Select-String 'HOENN_VERSION_NUMBER' 'Data\Scripts\001_Settings.rb').Line; if($l){($l -replace '.*\x22(.+)\x22.*','$1')}else{'unknown'}"`) do set "NEW_HOENN_VER=%%A"

echo.
echo  ==========================================================
echo   Update Complete!
echo  ----------------------------------------------------------
echo   Previous Version  : !HOENN_VER!
echo   Installed Version : !NEW_HOENN_VER!
echo  ==========================================================
echo.
pause