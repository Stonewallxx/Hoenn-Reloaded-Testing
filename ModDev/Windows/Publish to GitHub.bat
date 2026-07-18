@echo off
setlocal enabledelayedexpansion
title Hoenn Reloaded GitHub Publisher
color 0A

set "GAME_DIR=%~dp0..\.."
set "TOOLS_DIR=%~dp0"
set "REPO_URL=https://github.com/Stonewallxx/Hoenn-Reloaded-Mods.git"
set "REPO_RAW=https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded-Mods/main"
set "PUBLISH_TEMP_ROOT=%TEMP%\HoennReloadedPublisher"
set "REPO_DIR=%PUBLISH_TEMP_ROOT%\Hoenn-Reloaded-Mods-%RANDOM%-%RANDOM%"
set "INDEX_FILE=%REPO_DIR%\index.json"
set "BLOCKED_EXT=.exe .dll .bat .cmd .ps1 .vbs .js .jar .msi .scr .com"

echo ============================================
echo       Hoenn Reloaded GitHub Publisher
echo ============================================
echo.

call :check_git
if errorlevel 1 goto :done
call :check_auth
if errorlevel 1 goto :done
call :sync_index_only
if errorlevel 1 goto :done
call :choose_publish_type
if errorlevel 1 goto :done
if /i "%PUBLISH_TYPE%"=="mod" (
  call :choose_mod
  if errorlevel 1 goto :done
)
if /i "%PUBLISH_TYPE%"=="profile" (
  call :choose_profile
  if errorlevel 1 goto :done
)
call :sync_repo
if errorlevel 1 goto :done
if /i "%PUBLISH_TYPE%"=="mod" (
  call :publish_mod
  if errorlevel 1 goto :done
)
if /i "%PUBLISH_TYPE%"=="profile" (
  call :publish_profile
  if errorlevel 1 goto :done
)
call :commit_push
goto :done

:check_git
where git >NUL 2>&1
if %errorlevel%==0 (
  echo [OK] Git found.
  echo.
  exit /b 0
)
color 0E
echo [!] Git is not installed.
echo.
set /p installgit="Install Git automatically via winget? (Y/N): "
if /i not "%installgit%"=="Y" (
  echo Install Git from: https://git-scm.com/downloads
  pause
  exit /b 1
)
where winget >NUL 2>&1
if not %errorlevel%==0 (
  color 0C
  echo [ERROR] winget is not available.
  echo Install Git manually from: https://git-scm.com/downloads
  pause
  exit /b 1
)
winget install Git.Git --accept-source-agreements --accept-package-agreements
echo.
echo Git installed. Close and reopen this publisher.
pause
exit /b 1

:check_auth
echo Checking GitHub authentication...
where gh >NUL 2>&1
if not %errorlevel%==0 goto :auth_git_credentials
gh auth status >NUL 2>&1
if %errorlevel%==0 goto :auth_done
echo [!] Not logged into GitHub CLI.
set /p login="Log in with browser now? (Y/N): "
if /i "%login%"=="Y" (
  gh auth login --hostname github.com --git-protocol https --web
  if not %errorlevel%==0 (
    color 0C
    echo [ERROR] GitHub login failed.
    pause
    exit /b 1
  )
  gh auth setup-git
  goto :auth_done
)

:auth_git_credentials
echo GitHub CLI not used. Git credentials/PAT must already be configured.
echo.

:auth_done
set "gituser="
set "gitemail="
for /f "tokens=*" %%A in ('git config --global user.name 2^>NUL') do set "gituser=%%A"
for /f "tokens=*" %%A in ('git config --global user.email 2^>NUL') do set "gitemail=%%A"
if not defined gituser (
  set /p gituser="Commit name: "
  git config --global user.name "!gituser!"
)
if not defined gitemail (
  set /p gitemail="Commit email: "
  git config --global user.email "!gitemail!"
)
color 0A
echo [OK] Auth check complete.
echo.
exit /b 0

:sync_repo
echo ============================================
echo  Syncing Hoenn-Reloaded-Mods sparse checkout
echo ============================================
echo.
if exist "%REPO_DIR%\.git" goto :repo_pull
if not exist "%PUBLISH_TEMP_ROOT%" mkdir "%PUBLISH_TEMP_ROOT%"
git clone --depth 1 --filter=blob:none --no-checkout "%REPO_URL%" "%REPO_DIR%"
if not %errorlevel%==0 (
  color 0C
  echo [ERROR] Could not clone %REPO_URL%.
  pause
  exit /b 1
)
pushd "%REPO_DIR%"
git sparse-checkout init --no-cone
call :set_sparse_paths
git checkout main
if not %errorlevel%==0 git checkout master
popd
goto :repo_ready

:repo_pull
pushd "%REPO_DIR%"
call :set_sparse_paths
git pull origin main
if not %errorlevel%==0 git pull origin master
popd

:repo_ready
echo.
exit /b 0

:sync_index_only
echo ============================================
echo  Syncing Hoenn-Reloaded-Mods index
echo ============================================
echo.
if exist "%REPO_DIR%\.git" goto :index_pull
if not exist "%PUBLISH_TEMP_ROOT%" mkdir "%PUBLISH_TEMP_ROOT%"
git clone --depth 1 --filter=blob:none --no-checkout "%REPO_URL%" "%REPO_DIR%"
if not %errorlevel%==0 (
  color 0C
  echo [ERROR] Could not clone %REPO_URL%.
  pause
  exit /b 1
)
pushd "%REPO_DIR%"
git sparse-checkout init --no-cone
git sparse-checkout set --no-cone "/index.json"
git checkout main
if not %errorlevel%==0 git checkout master
popd
goto :index_ready

:index_pull
pushd "%REPO_DIR%"
git sparse-checkout set --no-cone "/index.json"
git pull origin main
if not %errorlevel%==0 git pull origin master
popd

:index_ready
if not exist "%INDEX_FILE%" (
  color 0C
  echo [ERROR] index.json was not found after sync.
  pause
  exit /b 1
)
echo [OK] Index synced.
echo.
exit /b 0

:set_sparse_paths
if /i "%PUBLISH_TYPE%"=="mod" (
  git sparse-checkout set --no-cone "/index.json" "/Mods/%MOD_ID%/"
) else (
  git sparse-checkout set --no-cone "/index.json" "/Profiles/%PROFILE_ID%/"
)
exit /b 0

:choose_publish_type
echo ============================================
echo  What do you want to publish?
echo ============================================
echo.
echo   1. Mod
echo   2. Profile
echo   0. Cancel
echo.
set /p typechoice="Choice: "
if "%typechoice%"=="1" set "PUBLISH_TYPE=mod"
if "%typechoice%"=="2" set "PUBLISH_TYPE=profile"
if "%typechoice%"=="0" exit /b 1
if not defined PUBLISH_TYPE (
  echo [ERROR] Invalid choice.
  pause
  exit /b 1
)
echo.
exit /b 0

:choose_mod
set count=0
echo Mods available to publish:
echo.
for %%B in ("Mods" "ModDev") do (
  if exist "%GAME_DIR%\%%~B" (
    for /d %%D in ("%GAME_DIR%\%%~B\*") do (
      if exist "%%D\mod.json" (
        set /a count+=1
        set "mod_!count!=%%D"
        for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$m=Get-Content '%%D\mod.json' -Raw|ConvertFrom-Json; $m.id"`) do set "mid=%%I"
        for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "$m=Get-Content '%%D\mod.json' -Raw|ConvertFrom-Json; $m.version"`) do set "mver=%%V"
        echo   !count!. !mid! v!mver! [%%~B]
      )
    )
  )
)
if "%count%"=="0" (
  color 0E
  echo [!] No mods with mod.json were found in Mods or ModDev.
  pause
  exit /b 1
)
echo.
set /p choice="Select mod number: "
set "MOD_DIR=!mod_%choice%!"
if not defined MOD_DIR (
  color 0C
  echo [ERROR] Invalid selection.
  pause
  exit /b 1
)
set "MOD_JSON=%MOD_DIR%\mod.json"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$m=Get-Content '%MOD_JSON%' -Raw|ConvertFrom-Json; $m.id.Trim().ToLower() -replace '[^a-z0-9_]+','_' -replace '^_+|_+$',''"`) do set "MOD_ID=%%I"
if "%MOD_ID%"=="" (
  color 0C
  echo [ERROR] Selected mod has an invalid id.
  pause
  exit /b 1
)
exit /b 0

:choose_profile
set count=0
set "PROFILE_DIR=%GAME_DIR%\Mods\Reloaded\Profiles"
if not exist "%PROFILE_DIR%" (
  color 0C
  echo [ERROR] Profile folder not found.
  pause
  exit /b 1
)
echo Profiles available to publish:
echo.
for %%F in ("%PROFILE_DIR%\*.json") do (
  set /a count+=1
  set "profile_!count!=%%F"
  for /f "usebackq delims=" %%N in (`powershell -NoProfile -Command "$p=Get-Content '%%F' -Raw|ConvertFrom-Json; $p.name"`) do set "pname=%%N"
  echo   !count!. !pname!
)
if "%count%"=="0" (
  color 0E
  echo [!] No profiles were found.
  pause
  exit /b 1
)
echo.
set /p choice="Select profile number: "
set "PROFILE_FILE=!profile_%choice%!"
if not defined PROFILE_FILE (
  color 0C
  echo [ERROR] Invalid selection.
  pause
  exit /b 1
)
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$p=Get-Content '%PROFILE_FILE%' -Raw|ConvertFrom-Json; $raw=if($p.id){$p.id}else{$p.name}; $raw.Trim().ToLower() -replace '[^a-z0-9_]+','_' -replace '^_+|_+$',''"`) do set "PROFILE_ID=%%I"
if "%PROFILE_ID%"=="" (
  color 0C
  echo [ERROR] Selected profile has an invalid id/name.
  pause
  exit /b 1
)
exit /b 0

:publish_mod
echo.
echo ============================================
echo  Validating Mod
echo ============================================
echo.
set "MOD_JSON=%MOD_DIR%\mod.json"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$m=Get-Content '%MOD_JSON%' -Raw|ConvertFrom-Json; $m.id"`) do set "MOD_ID=%%I"
for /f "usebackq delims=" %%N in (`powershell -NoProfile -Command "$m=Get-Content '%MOD_JSON%' -Raw|ConvertFrom-Json; $m.name"`) do set "MOD_NAME=%%N"
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "$m=Get-Content '%MOD_JSON%' -Raw|ConvertFrom-Json; $m.version"`) do set "MOD_VER=%%V"

if "%MOD_ID%"=="" goto :mod_invalid_id
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "'%MOD_ID%'.Trim().ToLower() -replace '[^a-z0-9_]+','_' -replace '^_+|_+$',''"`) do set "MOD_ID=%%I"
if "%MOD_ID%"=="" goto :mod_invalid_id
if "%MOD_NAME%"=="" goto :mod_invalid_name
powershell -NoProfile -Command "if('%MOD_VER%' -match '^\d+\.\d+\.\d+$'){exit 0}else{exit 1}"
if errorlevel 1 goto :mod_invalid_version

for %%E in (%BLOCKED_EXT%) do (
  for /r "%MOD_DIR%" %%F in (*%%E) do (
    color 0C
    echo [ERROR] Blocked file type found:
    echo %%F
    pause
    exit /b 1
  )
)

echo [OK] Mod validated.
echo   ID:      %MOD_ID%
echo   Name:    %MOD_NAME%
echo   Version: %MOD_VER%
echo.
set /p confirm="Publish this mod to GitHub? (Y/N): "
if /i not "%confirm%"=="Y" exit /b 1

set "REPO_MOD_DIR=%REPO_DIR%\Mods\%MOD_ID%"
if not exist "%REPO_MOD_DIR%" mkdir "%REPO_MOD_DIR%"
set "ZIP_NAME=%MOD_ID%_%MOD_VER%.zip"
set "ZIP_PATH=%REPO_MOD_DIR%\%ZIP_NAME%"
if exist "%ZIP_PATH%" (
  set /p overwrite="This version already exists. Replace it? (Y/N): "
  if /i not "!overwrite!"=="Y" exit /b 1
  del /f /q "%ZIP_PATH%"
)
powershell -NoProfile -Command "Compress-Archive -Path '%MOD_DIR%' -DestinationPath '%ZIP_PATH%' -Force"
if not exist "%ZIP_PATH%" (
  color 0C
  echo [ERROR] Could not create zip.
  pause
  exit /b 1
)

for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '%ZIP_PATH%').Hash.ToLowerInvariant()"`) do set "ZIP_SHA256=%%H"
for %%F in ("%ZIP_PATH%") do set "ZIP_SIZE=%%~zF"
set "DOWNLOAD_URL=%REPO_RAW%/Mods/%MOD_ID%/%ZIP_NAME%"
powershell -NoProfile -Command "$idxPath='%INDEX_FILE%'; $idx=if(Test-Path $idxPath){Get-Content $idxPath -Raw|ConvertFrom-Json}else{[pscustomobject]@{version=1;mods=@();profiles=@()}}; if($idx -is [array]){$idx=[pscustomobject]@{version=1;mods=@($idx);profiles=@()}}; if($null -eq $idx.mods){$idx|Add-Member -NotePropertyName mods -NotePropertyValue @()}; if($null -eq $idx.profiles){$idx|Add-Member -NotePropertyName profiles -NotePropertyValue @()}; $m=Get-Content '%MOD_JSON%' -Raw|ConvertFrom-Json; $old=@($idx.mods|Where-Object{$_.id -eq '%MOD_ID%' -or $_.uid -eq '%MOD_ID%'}|Select-Object -First 1); $versions=@(); if($old.Count -gt 0){$versions=@($old[0].versions|Where-Object{$_.version -ne '%MOD_VER%'})}; $versions += [pscustomobject]@{version='%MOD_VER%';download_url='%DOWNLOAD_URL%';sha256='%ZIP_SHA256%';size=[int64]'%ZIP_SIZE%';reloaded_version=(Get-Content '%GAME_DIR%\Reloaded\Version.md' -Raw).Trim();changelog='';changelogurl=$m.changelogurl;dependencies=@($m.dependencies)}; $entry=[pscustomobject]@{id='%MOD_ID%';name=$m.name;latest_version='%MOD_VER%';authors=@($m.authors);description=$m.description;tags=@($m.tags);dependencies=@($m.dependencies);changelogurl=$m.changelogurl;versions=$versions}; $idx.mods=@($idx.mods|Where-Object{$_.id -ne '%MOD_ID%' -and $_.uid -ne '%MOD_ID%'}) + $entry; $json=$idx|ConvertTo-Json -Depth 20; [IO.File]::WriteAllText($idxPath,$json,[Text.UTF8Encoding]::new($false))"
if not %errorlevel%==0 (
  color 0C
  echo [ERROR] Could not update index.json.
  pause
  exit /b 1
)
set "COMMIT_MESSAGE=Publish %MOD_ID% v%MOD_VER%"
exit /b 0

:mod_invalid
color 0C
echo [ERROR] Mod failed validation. Check id/name/version in mod.json.
pause
exit /b 1

:mod_invalid_id
color 0C
echo [ERROR] Mod failed validation. Check id in mod.json.
pause
exit /b 1

:mod_invalid_name
color 0C
echo [ERROR] Mod failed validation. Check name in mod.json.
pause
exit /b 1

:mod_invalid_version
color 0C
echo [ERROR] Mod failed validation. Check version in mod.json.
echo Version must use Major.Minor.Patch, for example 1.0.0.
pause
exit /b 1

:publish_profile
echo.
echo ============================================
echo  Validating Profile
echo ============================================
echo.
for /f "usebackq delims=" %%N in (`powershell -NoProfile -Command "$p=Get-Content '%PROFILE_FILE%' -Raw|ConvertFrom-Json; $p.name"`) do set "PROFILE_NAME=%%N"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$p=Get-Content '%PROFILE_FILE%' -Raw|ConvertFrom-Json; if($p.id){$p.id}else{$p.name}"`) do set "PROFILE_ID_RAW=%%I"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "'%PROFILE_ID_RAW%'.Trim().ToLower() -replace '[^a-z0-9_]+','_' -replace '^_+|_+$',''"`) do set "PROFILE_ID=%%I"

if "%PROFILE_ID%"=="" (
  color 0C
  echo [ERROR] Profile id/name is invalid.
  pause
  exit /b 1
)

powershell -NoProfile -Command "$game='%GAME_DIR%'; $p=Get-Content '%PROFILE_FILE%' -Raw|ConvertFrom-Json; $ids=@(); $ids+=@($p.enabled_mods); $ids+=@($p.disabled_mods); $ids+=@($p.load_order); if($p.mod_settings){$ids+=@($p.mod_settings.PSObject.Properties.Name)}; $ids=@($ids|Where-Object{$_}|ForEach-Object{$_.ToString().Trim().ToLower() -replace '[^a-z0-9_]+','_' -replace '^_+|_+$',''}|Where-Object{$_}|Sort-Object -Unique); if(@($ids).Count -eq 0){exit 2}; $installed=@(); foreach($base in @('Mods','ModDev')){$dir=Join-Path $game $base; if(Test-Path -LiteralPath $dir){Get-ChildItem -LiteralPath $dir -Directory|ForEach-Object{$mf=Join-Path $_.FullName 'mod.json'; if(Test-Path -LiteralPath $mf){try{$m=Get-Content -LiteralPath $mf -Raw|ConvertFrom-Json; $installed += ($m.id.ToString().Trim().ToLower() -replace '[^a-z0-9_]+','_' -replace '^_+|_+$','')}catch{}}}}}; $missing=@($ids|Where-Object{$installed -notcontains $_}); if(@($missing).Count -gt 0){Write-Host ($missing -join ', '); exit 3}; exit 0"
if "%errorlevel%"=="2" (
  color 0C
  echo [ERROR] Profile does not reference any mods.
  pause
  exit /b 1
)
if "%errorlevel%"=="3" (
  color 0C
  echo [ERROR] Profile references a missing mod.
  pause
  exit /b 1
)

for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "$idxPath='%INDEX_FILE%'; if(Test-Path $idxPath){$idx=Get-Content $idxPath -Raw|ConvertFrom-Json; $old=@($idx.profiles|Where-Object{$_.id -eq '%PROFILE_ID%'}|Select-Object -First 1); if($old.Count -gt 0 -and $old[0].version -match '^\d+\.\d+\.\d+$'){$p=$old[0].version.Split('.'); '{0}.{1}.{2}' -f $p[0],$p[1],([int]$p[2]+1)}else{'1.0.0'}}else{'1.0.0'}"`) do set "PROFILE_VER=%%V"

echo [OK] Profile validated.
echo   ID:      %PROFILE_ID%
echo   Name:    %PROFILE_NAME%
echo   Version: %PROFILE_VER%
echo.
set /p confirm="Publish this profile to GitHub? (Y/N): "
if /i not "%confirm%"=="Y" exit /b 1

set "REPO_PROFILE_DIR=%REPO_DIR%\Profiles\%PROFILE_ID%"
if not exist "%REPO_PROFILE_DIR%" mkdir "%REPO_PROFILE_DIR%"
set "PROFILE_JSON_NAME=%PROFILE_ID%_%PROFILE_VER%.json"
set "PROFILE_REPO_FILE=%REPO_PROFILE_DIR%\%PROFILE_JSON_NAME%"
set "PROFILE_URL=%REPO_RAW%/Profiles/%PROFILE_ID%/%PROFILE_JSON_NAME%"
powershell -NoProfile -Command "function FindMod($game,$id){foreach($base in @('Mods','ModDev')){$dir=Join-Path $game $base; if(Test-Path -LiteralPath $dir){foreach($folder in Get-ChildItem -LiteralPath $dir -Directory){$mf=Join-Path $folder.FullName 'mod.json'; if(Test-Path -LiteralPath $mf){try{$m=Get-Content -LiteralPath $mf -Raw|ConvertFrom-Json; $mid=$m.id.ToString().Trim().ToLower() -replace '[^a-z0-9_]+','_' -replace '^_+|_+$',''; if($mid -eq $id){return $mf}}catch{}}}}}; return $null}; $game='%GAME_DIR%'; $p=Get-Content '%PROFILE_FILE%' -Raw|ConvertFrom-Json; $mods=@(); $ids=@(); $ids+=@($p.enabled_mods); $ids+=@($p.disabled_mods); $ids+=@($p.load_order); if($p.mod_settings){$ids+=$p.mod_settings.PSObject.Properties.Name}; $ids=$ids|Where-Object{$_}|ForEach-Object{ $_.ToString().Trim().ToLower() -replace '[^a-z0-9_]+','_' -replace '^_+|_+$',''}|Where-Object{$_}|Sort-Object -Unique; foreach($id in $ids){ $mf=FindMod $game $id; $m=Get-Content -LiteralPath $mf -Raw|ConvertFrom-Json; $mods += [pscustomobject]@{id=$id;version=$m.version} }; $payload=[pscustomobject]@{format='RLD-code';version=1;preset_name=$p.name;reloaded_version=(Get-Content '%GAME_DIR%\Reloaded\Version.md' -Raw).Trim();profile=$p;mods=$mods}; $json=$payload|ConvertTo-Json -Depth 20; [IO.File]::WriteAllText('%PROFILE_REPO_FILE%',$json,[Text.UTF8Encoding]::new($false)); $idxPath='%INDEX_FILE%'; $idx=if(Test-Path $idxPath){Get-Content $idxPath -Raw|ConvertFrom-Json}else{[pscustomobject]@{version=1;mods=@();profiles=@()}}; if($idx -is [array]){$idx=[pscustomobject]@{version=1;mods=@($idx);profiles=@()}}; if($null -eq $idx.mods){$idx|Add-Member -NotePropertyName mods -NotePropertyValue @()}; if($null -eq $idx.profiles){$idx|Add-Member -NotePropertyName profiles -NotePropertyValue @()}; $entry=[pscustomobject]@{id='%PROFILE_ID%';name=$p.name;version='%PROFILE_VER%';authors=@();description=$p.notes;tags=@('profile');reloaded_version=(Get-Content '%GAME_DIR%\Reloaded\Version.md' -Raw).Trim();profile_url='%PROFILE_URL%';changelogurl=$p.changelogurl;mods=$mods}; $idx.profiles=@($idx.profiles|Where-Object{$_.id -ne '%PROFILE_ID%'}) + $entry; $json=$idx|ConvertTo-Json -Depth 20; [IO.File]::WriteAllText($idxPath,$json,[Text.UTF8Encoding]::new($false))"
if not %errorlevel%==0 (
  color 0C
  echo [ERROR] Could not publish profile payload/index.
  pause
  exit /b 1
)
set "COMMIT_MESSAGE=Publish profile %PROFILE_ID% v%PROFILE_VER%"
exit /b 0

:commit_push
echo.
echo ============================================
echo  Committing and pushing
echo ============================================
echo.
pushd "%REPO_DIR%"
git add .
set "has_changes="
for /f "delims=" %%S in ('git status --porcelain 2^>NUL') do set "has_changes=1"
if not defined has_changes (
  echo No changes detected.
  popd
  echo.
  exit /b 0
)
git commit -m "%COMMIT_MESSAGE%"
git push origin main
if %errorlevel%==0 (
  popd
  color 0A
  echo.
  echo SUCCESS. Published to GitHub.
  echo.
  exit /b 0
)
popd
color 0E
echo.
echo Push failed. The temporary checkout will be removed.
echo Confirm collaborator access or Git credentials, then try again.
echo.
exit /b 1

:done
set "PUBLISH_RESULT=%ERRORLEVEL%"
if exist "%REPO_DIR%" rmdir /s /q "%REPO_DIR%"
rmdir "%PUBLISH_TEMP_ROOT%" 2>NUL
echo.
pause
exit /b %PUBLISH_RESULT%
