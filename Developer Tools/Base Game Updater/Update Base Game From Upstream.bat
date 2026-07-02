@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Hoenn Reloaded - Base Game Upstream Updater
color 0A

:: ============================================================
::  CONFIG
:: ============================================================
set "REPO_URL=https://github.com/infinitefusion/infinitefusion-hoenn-public.git"
set "BRANCH=releases"
set "TOOL_ROOT=%~dp0"
set "GAME_ROOT=%~dp0..\.."
set "CACHE_DIR=%~dp0_upstream_cache"
set "UPSTREAM_DIR=%CACHE_DIR%\repo"

for %%I in ("%GAME_ROOT%") do set "GAME_ROOT=%%~fI"
set "MGIT=%GAME_ROOT%\REQUIRED_BY_INSTALLER_UPDATER\cmd\git.exe"

:: ============================================================
::  Header
:: ============================================================
echo.
echo  ============================================================
echo   Hoenn Reloaded - Base Game Upstream Updater
echo  ============================================================
echo.
echo   Source : github.com/infinitefusion/infinitefusion-hoenn-public
echo   Branch : %BRANCH%
echo.
echo   This updates the base game files from upstream without using
echo   or replacing Hoenn Reloaded's .git folder.
echo.
echo   Cache folder:
echo   %CACHE_DIR%
echo.
echo  ============================================================
echo.

if not exist "%GAME_ROOT%\REQUIRED_BY_INSTALLER_UPDATER" (
    color 0C
    echo  [ERROR] This tool must be inside a Hoenn Reloaded game folder.
    echo.
    pause
    exit /b 1
)

if not exist "%MGIT%" (
    color 0C
    echo  [ERROR] Bundled git.exe was not found:
    echo  %MGIT%
    echo.
    pause
    exit /b 1
)

echo  This will copy upstream base files into:
echo  %GAME_ROOT%
echo.
echo  Protected HR paths:
echo  .git, Reloaded, Mods, ModDev, ModsBackup, Modders Tools,
echo  Admin Tools, Developer Tools, .gitignore, Game.ini, and
echo  HR installer files.
echo.
set /p "go=Press ENTER to continue, or close this window to cancel: "
echo.

:: ============================================================
::  Prepare upstream cache
:: ============================================================
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%" >nul 2>&1

if exist "%UPSTREAM_DIR%\.git" (
    echo  [1/3] Updating upstream cache...
    "%MGIT%" -C "%UPSTREAM_DIR%" remote set-url origin "%REPO_URL%" >nul 2>&1
    "%MGIT%" -C "%UPSTREAM_DIR%" fetch --depth=1 --force origin %BRANCH%
    if errorlevel 1 goto fetch_failed
    "%MGIT%" -C "%UPSTREAM_DIR%" reset --hard origin/%BRANCH%
    if errorlevel 1 goto fetch_failed
) else (
    if exist "%UPSTREAM_DIR%" (
        echo  [INFO] Removing incomplete upstream cache...
        rmdir /s /q "%UPSTREAM_DIR%"
    )
    echo  [1/3] Cloning upstream cache...
    "%MGIT%" clone --depth=1 --branch "%BRANCH%" "%REPO_URL%" "%UPSTREAM_DIR%"
    if errorlevel 1 goto fetch_failed
)

:: ============================================================
::  Copy files into HR folder without touching HR .git
:: ============================================================
echo.
echo  [2/3] Copying upstream base files...
robocopy "%UPSTREAM_DIR%" "%GAME_ROOT%" /E /R:2 /W:1 ^
    /XD ".git" "Reloaded" "Mods" "ModDev" "ModsBackup" "Modders Tools" "Admin Tools" "Developer Tools" "Releases" ^
    /XF ".gitignore" "Game.ini" "Hoenn Reloaded Installer.bat" "PIF Hoenn Installer.bat"

set "ROBOCOPY_RESULT=%ERRORLEVEL%"
if %ROBOCOPY_RESULT% GEQ 8 goto copy_failed

:: ============================================================
::  Optional cleanup
:: ============================================================
echo.
echo  [3/3] Base update copy complete.
echo.
set /p "cleanup=Delete upstream cache now? (Y/N): "
if /I "%cleanup%"=="Y" (
    echo  Removing cache...
    rmdir /s /q "%CACHE_DIR%"
)

echo.
echo  ============================================================
echo   Done.
echo  ------------------------------------------------------------
echo   Hoenn Reloaded's .git folder was not touched.
echo   Review changed base files before committing to your fork.
echo  ============================================================
echo.
pause
exit /b 0

:fetch_failed
color 0C
echo.
echo  ============================================================
echo   ERROR: Could not sync the upstream base game cache.
echo  ------------------------------------------------------------
echo   Check your internet connection and GitHub access, then retry.
echo  ============================================================
echo.
pause
exit /b 1

:copy_failed
color 0C
echo.
echo  ============================================================
echo   ERROR: File copy failed.
echo  ------------------------------------------------------------
echo   Robocopy exit code: %ROBOCOPY_RESULT%
echo   Close the game and any files from the folder, then retry.
echo  ============================================================
echo.
pause
exit /b 1
