@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Hoenn Reloaded - Full Update
color 0A

:: ============================================================
::  CONFIG
:: ============================================================
set "REPO_URL=https://github.com/infinitefusion/infinitefusion-hoenn-public.git"
set "REPO_RAW=https://raw.githubusercontent.com/infinitefusion/infinitefusion-hoenn-public/releases"
set "BRANCH=releases"
set "MGIT=.\REQUIRED_BY_INSTALLER_UPDATER\cmd\git.exe"
set "VER_FILE=Reloaded\000a_Version.rb"

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

:: ============================================================
::  Read current local version
:: ============================================================
set "LOCAL_VER=unknown"
if exist "%VER_FILE%" (
    for /f "usebackq tokens=*" %%A in (
        `powershell -NoProfile -Command "$m=(Select-String 'VERSION\s*=\s*""(.+)""' '%VER_FILE%'); if($m){$m.Matches[0].Groups[1].Value}else{'unknown'}"`
    ) do set "LOCAL_VER=%%A"
)

:: ============================================================
::  Fetch remote version for preview
:: ============================================================
set "REMOTE_VER=unknown"
for /f "usebackq tokens=*" %%A in (
    `powershell -NoProfile -Command "try{$r=(Invoke-WebRequest -Uri '%REPO_RAW%/Reloaded/000a_Version.rb' -UseBasicParsing -TimeoutSec 5).Content; $m=[regex]::Match($r,'VERSION\s*=\s*""(.+)""'); if($m.Success){$m.Groups[1].Value}else{'unknown'}}catch{'unknown'}"`
) do set "REMOTE_VER=%%A"

:: ============================================================
::  Header
:: ============================================================
echo.
echo  ============================================================
echo   Hoenn Reloaded  ^|  Full Update
echo  ============================================================
echo   Installed Version  : !LOCAL_VER!
echo   Available Version  : !REMOTE_VER!
echo  ------------------------------------------------------------
echo.
echo   This will pull the full Hoenn Reloaded release from GitHub,
echo   including all game files and Mod Manager files.
echo.
echo   Your saves will NOT be affected.
echo.
echo   SOURCE: github.com/infinitefusion/infinitefusion-hoenn-public
echo  ============================================================
echo.
set /p "go=  Press ENTER to update, or close this window to cancel: "
echo.

:: ============================================================
::  Sanity checks
:: ============================================================
if not exist "%MGIT%" (
    color 0C
    echo  [ERROR] Bundled git.exe not found at: %MGIT%
    echo  Your installation may be incomplete.
    echo.
    pause
    exit /b 1
)

:: Remove stale lock if present
if exist ".git\shallow.lock" (
    echo  [INFO] Removing stale git lock...
    erase /f /q ".git\shallow.lock"
)

:: ============================================================
::  Download and apply
:: ============================================================
echo  [1/3] Initializing repository...
%MGIT% init . >nul 2>&1

echo  [2/3] Fetching latest release from GitHub...
%MGIT% remote remove origin >nul 2>&1
%MGIT% remote add origin "%REPO_URL%" >nul 2>&1
%MGIT% fetch --depth=1 origin %BRANCH%
if %errorlevel% neq 0 (
    echo.
    color 0C
    echo  ============================================================
    echo   ERROR: Failed to fetch update from GitHub.
    echo  ------------------------------------------------------------
    echo   - Check your internet connection
    echo   - GitHub may be temporarily unavailable
    echo   - Screenshot this window if you need help
    echo  ============================================================
    echo.
    pause
    exit /b 1
)

echo  [3/3] Applying update...
%MGIT% reset --hard origin/%BRANCH%

:: ============================================================
::  Re-read version after update
:: ============================================================
set "NEW_VER=unknown"
if exist "%VER_FILE%" (
    for /f "usebackq tokens=*" %%A in (
        `powershell -NoProfile -Command "$m=(Select-String 'VERSION\s*=\s*""(.+)""' '%VER_FILE%'); if($m){$m.Matches[0].Groups[1].Value}else{'unknown'}"`
    ) do set "NEW_VER=%%A"
)

:: ============================================================
::  Done
:: ============================================================
echo.
echo  ============================================================
echo   Update Complete!
echo  ------------------------------------------------------------
echo   Previous Version  : !LOCAL_VER!
echo   Installed Version : !NEW_VER!
echo  ============================================================
echo.
pause
