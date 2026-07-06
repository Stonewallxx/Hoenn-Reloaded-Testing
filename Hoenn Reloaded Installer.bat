@echo off
setlocal enabledelayedexpansion
title Hoenn Reloaded - Full Update
color 0A

:: ============================================================
::  CONFIG
:: ============================================================
set "REPO_URL=https://github.com/Stonewallxx/Hoenn-Reloaded.git"
set "REPO_RAW=https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/main"
set "BRANCH=main"
set "SCRIPT_DIR=%~dp0"
set "GAME_ROOT="
set "FILES_PROTECTED=REQUIRED_BY_INSTALLER_UPDATER, this installer, plus ignored/user-created files. Other tracked release files are updated."
set "FILES_UPDATED=Not started"
set "CLEANUP_STATUS=No temporary cleanup needed"

for %%I in ("%SCRIPT_DIR%.") do set "SCRIPT_DIR=%%~fI"
call :find_game_root "%SCRIPT_DIR%"
if not defined GAME_ROOT set "GAME_ROOT=%SCRIPT_DIR%"
cd /d "%GAME_ROOT%"
set "MGIT=%GAME_ROOT%\REQUIRED_BY_INSTALLER_UPDATER\cmd\git.exe"
set "VER_FILE=%GAME_ROOT%\Reloaded\Version.md"

:: ============================================================
::  What this tool does
:: ============================================================
echo.
echo  ============================================================
echo   Hoenn Reloaded Installer
echo  ============================================================
echo   Purpose:
echo   - Install or update Hoenn Reloaded from the public release repo.
echo   - Keep this folder connected to Stonewallxx/Hoenn-Reloaded.
echo   - Replace tracked release files with the latest release branch files.
echo.
echo   Protected:
echo   - REQUIRED_BY_INSTALLER_UPDATER is protected so bundled Git is not replaced while running.
echo   - This installer is protected so it does not delete itself during update.
echo   - Git ignored/user-created files are left alone by Git.
echo   - Save data is not stored in this repo and is not changed by this tool.
echo.
echo   Not protected:
echo   - Tracked release files outside REQUIRED_BY_INSTALLER_UPDATER are updated.
echo  ============================================================
echo.

echo   Target Folder:
echo   %GAME_ROOT%
echo.

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
echo   Target Folder      : %GAME_ROOT%
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
"%MGIT%" init . >nul 2>&1
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
"%MGIT%" remote remove origin >nul 2>&1
"%MGIT%" remote add origin "%REPO_URL%" >nul 2>&1
"%MGIT%" fetch --depth=1 --force origin %BRANCH%
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

echo  [3/3] Applying update while protecting installer runtime...
set "DELETE_LIST=%TEMP%\hr_installer_deleted_%RANDOM%.txt"
"%MGIT%" diff --name-only --diff-filter=D HEAD origin/%BRANCH% -- . ":(exclude)REQUIRED_BY_INSTALLER_UPDATER/**" ":(exclude)Hoenn Reloaded Installer.bat" > "%DELETE_LIST%" 2>nul
if exist "%DELETE_LIST%" (
    for /f "usebackq delims=" %%F in ("%DELETE_LIST%") do if exist "%%F" erase /f /q "%%F"
    erase /f /q "%DELETE_LIST%" >nul 2>&1
)
"%MGIT%" checkout -f origin/%BRANCH% -- . ":(exclude)REQUIRED_BY_INSTALLER_UPDATER/**" ":(exclude)Hoenn Reloaded Installer.bat"
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
"%MGIT%" update-ref refs/heads/%BRANCH% origin/%BRANCH% >nul 2>&1
"%MGIT%" symbolic-ref HEAD refs/heads/%BRANCH% >nul 2>&1
set "FILES_UPDATED=Updated tracked files from %REPO_URL% branch %BRANCH%, excluding REQUIRED_BY_INSTALLER_UPDATER and this installer"

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
echo   Files Protected   : !FILES_PROTECTED!
echo   Files Updated     : !FILES_UPDATED!
echo   Cleanup           : !CLEANUP_STATUS!
echo  ============================================================
echo.
pause
exit /b 0

:find_game_root
set "SEARCH_DIR=%~f1"
:find_game_root_loop
if exist "%SEARCH_DIR%\Game.exe" set "GAME_ROOT=%SEARCH_DIR%" & exit /b 0
if exist "%SEARCH_DIR%\Game.rxproj" set "GAME_ROOT=%SEARCH_DIR%" & exit /b 0
if exist "%SEARCH_DIR%\REQUIRED_BY_INSTALLER_UPDATER\cmd\git.exe" set "GAME_ROOT=%SEARCH_DIR%" & exit /b 0
for %%I in ("%SEARCH_DIR%\..") do set "PARENT_DIR=%%~fI"
if /I "%PARENT_DIR%"=="%SEARCH_DIR%" exit /b 0
set "SEARCH_DIR=%PARENT_DIR%"
goto find_game_root_loop
