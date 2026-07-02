@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Hoenn Reloaded - Full Update
color 0A

:: ============================================================
::  CONFIG
:: ============================================================
set "REPO_URL=https://github.com/Stonewallxx/Hoenn-Reloaded.git"
set "REPO_RAW=https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/main"
set "BRANCH=main"
set "MGIT=.\REQUIRED_BY_INSTALLER_UPDATER\cmd\git.exe"
set "VER_FILE=Reloaded\Version.md"

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
        `powershell -NoProfile -Command "try{(Get-Content '%VER_FILE%' -Raw).Trim()}catch{'unknown'}"`
    ) do set "LOCAL_VER=%%A"
)

:: ============================================================
::  Fetch remote version for preview
:: ============================================================
set "REMOTE_VER=unknown"
for /f "usebackq tokens=*" %%A in (
    `powershell -NoProfile -Command "try{(Invoke-WebRequest -Uri '%REPO_RAW%/Reloaded/Version.md' -UseBasicParsing -TimeoutSec 5).Content.Trim()}catch{'unknown'}"`
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
echo   SOURCE: github.com/Stonewallxx/Hoenn-Reloaded
echo  ============================================================
echo.
set /p "go=  Press ENTER to update, or close this window to cancel: "
echo.

:: ============================================================
::  Sanity checks
:: ============================================================
if not exist "%MGIT%" (
    color 0C
    echo.
    echo  ============================================================
    echo   ERROR: Bundled git.exe was not found.
    echo  ------------------------------------------------------------
    echo   Expected path:
    echo   %MGIT%
    echo  ------------------------------------------------------------
    echo   Your installation may be incomplete.
    echo  ============================================================
    echo.
    pause
    exit /b 1
)

:: Remove stale locks if present
if exist ".git\shallow.lock" (
    echo  [INFO] Removing stale git shallow lock...
    erase /f /q ".git\shallow.lock"
)
if exist ".git\index.lock" (
    echo  [INFO] Removing stale git index lock...
    erase /f /q ".git\index.lock"
)

:: ============================================================
::  Download and apply
:: ============================================================
echo  [1/3] Initializing repository...
%MGIT% init . >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    color 0C
    echo  ============================================================
    echo   ERROR: Failed to initialize the updater repository.
    echo  ------------------------------------------------------------
    echo   Close other Git/updater windows and try again.
    echo  ============================================================
    echo.
    pause
    exit /b 1
)

echo  [2/3] Fetching latest release from GitHub...
%MGIT% remote remove origin >nul 2>&1
%MGIT% remote add origin "%REPO_URL%" >nul 2>&1
%MGIT% fetch --depth=1 --force origin %BRANCH%
if %errorlevel% neq 0 (
    echo.
    color 0C
    echo  ============================================================
    echo   ERROR: Failed to fetch update from GitHub.
    echo  ------------------------------------------------------------
    echo   - Check your internet connection
    echo   - GitHub may be temporarily unavailable
    echo   - Another Git process may be locking files
    echo   - Screenshot this window if you need help
    echo  ============================================================
    echo.
    pause
    exit /b 1
)

echo  [3/3] Applying update...
%MGIT% reset --hard origin/%BRANCH%
if %errorlevel% neq 0 (
    echo.
    color 0C
    echo  ============================================================
    echo   ERROR: Failed to apply update.
    echo  ------------------------------------------------------------
    echo   Close the game and any Git/updater windows, then try again.
    echo  ============================================================
    echo.
    pause
    exit /b 1
)

:: ============================================================
::  Re-read version after update
:: ============================================================
set "NEW_VER=unknown"
if exist "%VER_FILE%" (
    for /f "usebackq tokens=*" %%A in (
        `powershell -NoProfile -Command "try{(Get-Content '%VER_FILE%' -Raw).Trim()}catch{'unknown'}"`
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
