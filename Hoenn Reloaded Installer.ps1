param(
  [string]$GameRoot = "",
  [string]$Channel = "",
  [string]$InstallType = "",
  [string]$PublicManifestUrl = "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/main/Reloaded/InstallerManifest.json",
  [string]$TestingArchiveUrl = "https://github.com/Stonewallxx/Hoenn-Reloaded-Testing/archive/refs/heads/main.zip",
  [string]$SpritepackCatalogUrl = "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/main/Reloaded/Spritepacks.json",
  [string]$ManifestFile = "",
  [string]$TestingArchiveFile = "",
  [string]$SpritepackCatalogFile = "",
  [switch]$Repair,
  [switch]$KeepDownloads
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $GameRoot) { $GameRoot = $ScriptRoot }
$GameRoot = $GameRoot.Trim().Trim([char]34)
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
$SevenZip = Join-Path $GameRoot "REQUIRED_BY_INSTALLER_UPDATER\7z.exe"
$BufferSize = 1024 * 1024
$ManagedManifestPath = Join-Path $GameRoot "Reloaded\InstallerFiles.json"
$SpriteStatePath = Join-Path $GameRoot "Mods\Reloaded\SpritepacksInstalled.json"

$pathHasher = [Security.Cryptography.SHA256]::Create()
try {
  $pathBytes = [Text.Encoding]::UTF8.GetBytes($GameRoot.ToLowerInvariant())
  $pathHash = ([BitConverter]::ToString($pathHasher.ComputeHash($pathBytes))).Replace("-", "").Substring(0, 12)
} finally {
  $pathHasher.Dispose()
}
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) "HoennReloadedInstaller\$pathHash"
$PreviousManagedManifestPath = Join-Path $TempRoot "PreviousInstallerFiles.json"
$TestingStageRoot = Join-Path $TempRoot "TestingStage"

$ProtectedPrefixes = @(
  "mods/",
  "reloaded/logging/",
  "reloaded/cache/",
  "reloaded/settings.txt",
  "graphics/custombattlers/sprite import/",
  "graphics/spritepacks/",
  ".git/"
)

$TestingExcludedPatterns = @(
  '^(?:\.agents|\.codex|\.git|\.github|\.vscode)/',
  '^(?:Admin Tools|Developer Tools|ModDev)/',
  '^REQUIRED_BY_INSTALLER_UPDATER/',
  '^Mods/',
  '^Graphics/SpritePacks/',
  '^Graphics/CustomBattlers/(?:Sprite Import|custom_sprites|local_sprites/(?:BaseSprites|indexed)|spritesheets/spritesheets_(?:base|custom))/',
  '^Reloaded/(?:Cache|Logging)/',
  '^Reloaded/Settings\.txt$',
  '^Reloaded/InstallerManifest\.json$',
  '^Reloaded/InstallerFiles\.json$',
  '^Reloaded/Documentation/(?:To-Do|VanillaChanges|ReloadedMart-To-Do)\.md$',
  '^\.gitignore$',
  '^\.DS_Store$',
  '^outside\.zip$'
)

function Write-Phase([int]$Step, [int]$Total, [string]$Message) {
  Write-Host ""
  Write-Host ("[{0}/{1}] {2}" -f $Step, $Total, $Message) -ForegroundColor Cyan
}

function Write-JsonFile([object]$Value, [string]$Path, [int]$Depth = 12) {
  $parent = Split-Path -Parent $Path
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  [IO.File]::WriteAllText(
    $Path,
    (($Value | ConvertTo-Json -Depth $Depth) + "`r`n"),
    (New-Object Text.UTF8Encoding($false))
  )
}

function Select-InstallerOption([string]$Title, [string[]]$Options) {
  while ($true) {
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    for ($index = 0; $index -lt $Options.Count; $index++) {
      Write-Host ("  {0}. {1}" -f ($index + 1), $Options[$index])
    }
    $answer = Read-Host "Select an option"
    $number = 0
    if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Options.Count) {
      return $number
    }
    Write-Host "Enter a number from 1 to $($Options.Count)." -ForegroundColor Yellow
  }
}

function Convert-ToSafeRelativePath([string]$Path) {
  $value = $Path.Replace("\", "/").TrimStart("/")
  if (-not $value -or
      [IO.Path]::IsPathRooted($Path) -or
      $value -match '(^|/)\.\.(/|$)' -or
      $value -match '^[A-Za-z]:') {
    throw "Unsafe package path: $Path"
  }
  return $value
}

function Test-ProtectedPath([string]$RelativePath) {
  $value = $RelativePath.Replace("\", "/").TrimStart("/").ToLowerInvariant()
  foreach ($prefix in $ProtectedPrefixes) {
    if ($value -eq $prefix.TrimEnd("/") -or $value.StartsWith($prefix)) {
      return $true
    }
  }
  return $false
}

function Test-TestingExcluded([string]$RelativePath) {
  $value = $RelativePath.Replace("\", "/").TrimStart("/")
  foreach ($pattern in $TestingExcludedPatterns) {
    if ($value -match $pattern) { return $true }
  }
  return $false
}

function Read-JsonFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $null
  }
  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-Sha256WithProgress([string]$Path) {
  $length = (Get-Item -LiteralPath $Path).Length
  $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  $hash = [Security.Cryptography.SHA256]::Create()
  try {
    $buffer = New-Object byte[] $BufferSize
    $complete = 0L
    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
      $hash.TransformBlock($buffer, 0, $read, $buffer, 0) | Out-Null
      $complete += $read
      $percent = if ($length -gt 0) { [int](($complete * 100L) / $length) } else { 100 }
      Write-Progress -Activity "Verifying $(Split-Path -Leaf $Path)" -Status ("{0:N1} MB / {1:N1} MB" -f ($complete / 1MB), ($length / 1MB)) -PercentComplete $percent
    }
    $hash.TransformFinalBlock((New-Object byte[] 0), 0, 0) | Out-Null
    return ([BitConverter]::ToString($hash.Hash)).Replace("-", "").ToLowerInvariant()
  } finally {
    $hash.Dispose()
    $stream.Dispose()
    Write-Progress -Activity "Verifying $(Split-Path -Leaf $Path)" -Completed
  }
}

function Test-DownloadedFile([string]$Path, [long]$ExpectedSize, [string]$ExpectedSha256) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  if ($ExpectedSize -gt 0 -and (Get-Item -LiteralPath $Path).Length -ne $ExpectedSize) {
    return $false
  }
  if ($ExpectedSha256) {
    return (Get-Sha256WithProgress $Path) -eq $ExpectedSha256.Trim().ToLowerInvariant()
  }
  return $true
}

function Invoke-Download(
  [string]$Url,
  [string]$Destination,
  [long]$ExpectedSize,
  [string]$ExpectedSha256,
  [string]$Label,
  [bool]$Force = $false
) {
  if (-not $Url) { throw "No download URL was provided for $Label." }

  $part = "$Destination.part"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
  if ($Force) {
    Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
  } elseif (Test-DownloadedFile $Destination $ExpectedSize $ExpectedSha256) {
    Write-Host "Using verified cached $Label."
    return
  } elseif (Test-Path -LiteralPath $Destination -PathType Leaf) {
    Remove-Item -LiteralPath $Destination -Force
  }

  $sourceUri = $null
  if ([Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$sourceUri) -and $sourceUri.IsFile) {
    $sourcePath = $sourceUri.LocalPath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
      throw "Local $Label package was not found."
    }
    $total = (Get-Item -LiteralPath $sourcePath).Length
    $input = New-Object IO.FileStream($sourcePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $output = New-Object IO.FileStream($part, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
      $copied = 0L
      $buffer = New-Object byte[] $BufferSize
      while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $output.Write($buffer, 0, $read)
        $copied += $read
        $percent = if ($total -gt 0) { [int](($copied * 100L) / $total) } else { 100 }
        Write-Progress -Activity "Copying $Label" -Status ("{0:N1} MB / {1:N1} MB" -f ($copied / 1MB), ($total / 1MB)) -PercentComplete $percent
      }
    } finally {
      $input.Dispose()
      $output.Dispose()
      Write-Progress -Activity "Copying $Label" -Completed
    }
    Move-Item -LiteralPath $part -Destination $Destination -Force
    if (-not (Test-DownloadedFile $Destination $ExpectedSize $ExpectedSha256)) {
      Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
      throw "$Label failed size or SHA-256 verification."
    }
    return
  }

  $existing = if (Test-Path -LiteralPath $part -PathType Leaf) {
    (Get-Item -LiteralPath $part).Length
  } else {
    0L
  }
  if ($ExpectedSize -gt 0 -and $existing -gt $ExpectedSize) {
    Remove-Item -LiteralPath $part -Force
    $existing = 0L
  }

  $request = [Net.HttpWebRequest]::Create($Url)
  $request.AllowAutoRedirect = $true
  $request.Timeout = 30000
  $request.ReadWriteTimeout = 30000
  $request.UserAgent = "HoennReloadedInstaller/2"
  if ($existing -gt 0) { $request.AddRange($existing) }

  try {
    $response = $request.GetResponse()
  } catch {
    if ($existing -gt 0) {
      Remove-Item -LiteralPath $part -Force
      return Invoke-Download $Url $Destination $ExpectedSize $ExpectedSha256 $Label $Force
    }
    throw
  }

  try {
    $append = $existing -gt 0 -and [int]$response.StatusCode -eq 206
    if (-not $append) { $existing = 0L }
    $mode = if ($append) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }
    $output = New-Object IO.FileStream($part, $mode, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
      $input = $response.GetResponseStream()
      try {
        $total = if ($ExpectedSize -gt 0) {
          $ExpectedSize
        } elseif ($response.ContentLength -gt 0) {
          $existing + $response.ContentLength
        } else {
          0L
        }
        $received = $existing
        $buffer = New-Object byte[] $BufferSize
        while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
          $output.Write($buffer, 0, $read)
          $received += $read
          if ($total -gt 0) {
            $percent = [Math]::Min(100, [int](($received * 100L) / $total))
            Write-Progress -Activity "Downloading $Label" -Status ("{0:N1} MB / {1:N1} MB" -f ($received / 1MB), ($total / 1MB)) -PercentComplete $percent
          } else {
            Write-Progress -Activity "Downloading $Label" -Status ("{0:N1} MB" -f ($received / 1MB))
          }
        }
      } finally {
        if ($input) { $input.Dispose() }
      }
    } finally {
      $output.Dispose()
    }
  } finally {
    $response.Close()
    Write-Progress -Activity "Downloading $Label" -Completed
  }

  Move-Item -LiteralPath $part -Destination $Destination -Force
  if (-not (Test-DownloadedFile $Destination $ExpectedSize $ExpectedSha256)) {
    Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    throw "$Label failed size or SHA-256 verification."
  }
}

function Get-JsonSource([string]$File, [string]$Url, [string]$Name) {
  if ($File) {
    $resolved = [IO.Path]::GetFullPath($File)
    $data = Read-JsonFile $resolved
    if (-not $data) { throw "$Name file was not found or was invalid." }
    return $data
  }
  $target = Join-Path $TempRoot (($Name -replace '[^0-9A-Za-z._-]', '_') + ".json")
  Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
  Invoke-Download $Url $target 0 "" $Name $true
  $data = Read-JsonFile $target
  if (-not $data) { throw "$Name download was invalid." }
  return $data
}

function Assert-SafeArchive([string]$Archive, [bool]$AllowProtected) {
  $lines = & $SevenZip l -slt -- $Archive 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "7-Zip could not inspect $(Split-Path -Leaf $Archive)."
  }
  $archiveName = [IO.Path]::GetFileName($Archive)
  foreach ($line in $lines) {
    if ($line -notmatch '^Path = (.+)$') { continue }
    $entry = $Matches[1]
    if ($entry -eq $Archive -or $entry -eq $archiveName) { continue }
    $relative = Convert-ToSafeRelativePath $entry
    if (-not $AllowProtected -and (Test-ProtectedPath $relative)) {
      throw "Core package contains protected user/runtime content."
    }
  }
}

function Expand-Direct([string]$Archive, [string]$Label, [bool]$AllowProtected) {
  Assert-SafeArchive $Archive $AllowProtected
  Write-Host "Installing $Label directly into:"
  Write-Host "  $GameRoot"
  & $SevenZip x -aoa -y -bsp1 -bb0 "-o$GameRoot" -- $Archive
  if ($LASTEXITCODE -ne 0) {
    throw "7-Zip failed while installing $Label (exit code $LASTEXITCODE)."
  }
}

function Get-ManagedFiles([string]$Path) {
  $data = Read-JsonFile $Path
  if (-not $data) { return @() }
  return @($data.files | ForEach-Object { Convert-ToSafeRelativePath $_ })
}

function Remove-ObsoleteManagedFiles([string[]]$OldFiles, [string[]]$NewFiles) {
  $newSet = @{}
  foreach ($file in $NewFiles) { $newSet[$file.ToLowerInvariant()] = $true }
  $removed = 0
  foreach ($file in $OldFiles) {
    if ($newSet.ContainsKey($file.ToLowerInvariant()) -or (Test-ProtectedPath $file)) {
      continue
    }
    $target = [IO.Path]::GetFullPath((Join-Path $GameRoot $file))
    $rootPrefix = $GameRoot.TrimEnd("\") + "\"
    if (-not $target.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    if (Test-Path -LiteralPath $target -PathType Leaf) {
      Remove-Item -LiteralPath $target -Force
      $removed++
    }
  }
  Write-Host "Removed $removed obsolete managed Core file(s)."
}

function Install-TestingSnapshot([string]$Archive) {
  if (Test-Path -LiteralPath $TestingStageRoot) {
    Remove-Item -LiteralPath $TestingStageRoot -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $TestingStageRoot | Out-Null
  Assert-SafeArchive $Archive $true
  & $SevenZip x -aoa -y -bsp1 -bb0 "-o$TestingStageRoot" -- $Archive | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "7-Zip failed while opening the Testing repository snapshot."
  }

  $sourceRoot = $TestingStageRoot
  if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot "Reloaded") -PathType Container)) {
    $candidates = @(Get-ChildItem -LiteralPath $TestingStageRoot -Directory | Where-Object {
      Test-Path -LiteralPath (Join-Path $_.FullName "Reloaded") -PathType Container
    })
    if ($candidates.Count -ne 1) {
      throw "The Testing repository snapshot has an unexpected layout."
    }
    $sourceRoot = $candidates[0].FullName
  }

  $files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force)
  $managed = New-Object Collections.Generic.List[string]
  $copied = 0
  foreach ($file in $files) {
    $relative = $file.FullName.Substring($sourceRoot.TrimEnd("\").Length).TrimStart("\").Replace("\", "/")
    $relative = Convert-ToSafeRelativePath $relative
    if ((Test-TestingExcluded $relative) -or (Test-ProtectedPath $relative)) {
      continue
    }
    $destination = [IO.Path]::GetFullPath((Join-Path $GameRoot $relative))
    $rootPrefix = $GameRoot.TrimEnd("\") + "\"
    if (-not $destination.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Testing snapshot file leaves the install directory."
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    $managed.Add($relative)
    $copied++
    $percent = if ($files.Count -gt 0) { [int](($copied * 100) / $files.Count) } else { 100 }
    Write-Progress -Activity "Installing Hoenn Reloaded Testing" -Status "$copied files copied" -PercentComplete ([Math]::Min(100, $percent))
  }
  Write-Progress -Activity "Installing Hoenn Reloaded Testing" -Completed
  $managed.Add("Reloaded/InstallerFiles.json")
  $managedFiles = @($managed | Sort-Object -Unique)
  $versionPath = Join-Path $sourceRoot "Reloaded\Version.md"
  $version = if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
    (Get-Content -LiteralPath $versionPath -Raw).Trim()
  } else {
    "Testing"
  }
  Write-JsonFile ([ordered]@{
    schema = 1
    version = $version
    channel = "testing"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    files = $managedFiles
  }) $ManagedManifestPath
  return $version
}

function Get-LatestFullSpritepack($Catalog) {
  $full = @($Catalog.files | Where-Object { $_.full -eq $true })
  if ($full.Count -eq 0) {
    throw "The online Spritepack catalog has no Full Spritepack."
  }
  $latest = @($full | Where-Object { $_.latest -eq $true })
  $pack = if ($latest.Count -gt 0) { $latest[0] } else { $full[0] }
  if (-not $pack.build_id) {
    throw "The published Full Spritepack entry has no build_id."
  }
  return $pack
}

function Get-InstalledSpritepackId {
  $manifest = Read-JsonFile (Join-Path $GameRoot "Graphics\SpritePacks\manifest.json")
  if ($manifest -and $manifest.build_id) { return $manifest.build_id.ToString() }
  return ""
}

function Write-SpritepackInstallState($Spritepack) {
  $existing = Read-JsonFile $SpriteStatePath
  $files = [ordered]@{}
  if ($existing -and $existing.files) {
    foreach ($property in $existing.files.PSObject.Properties) {
      $files[$property.Name] = $property.Value
    }
  }
  $sourceUrl = if ($Spritepack.url) {
    $Spritepack.url.ToString()
  } elseif ($Spritepack.parts -and @($Spritepack.parts).Count -gt 0) {
    $Spritepack.parts[0].url.ToString()
  } else {
    ""
  }
  $id = $Spritepack.id.ToString()
  $files[$id] = [ordered]@{
    id = $id
    name = $Spritepack.name.ToString()
    url = $sourceUrl
    components = @()
    updated_at = $Spritepack.updated_at.ToString()
    full = $true
    monthly = $false
    manual = $false
    files_total = 0
    files_copied = 0
    files_skipped = 0
    files_failed = 0
    import_elapsed_seconds = "0.00"
    installed_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
    destination = "."
  }
  Write-JsonFile ([ordered]@{ version = 1; files = $files }) $SpriteStatePath
}

try {
  Write-Host ""
  Write-Host "============================================================" -ForegroundColor Cyan
  Write-Host " Hoenn Reloaded Installer" -ForegroundColor Cyan
  Write-Host "============================================================" -ForegroundColor Cyan
  Write-Host " Install directory: $GameRoot"

  if (-not (Test-Path -LiteralPath $SevenZip -PathType Leaf)) {
    throw "7z.exe was not found beside the installer files."
  }
  New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

  if (-not $Channel) {
    $selected = Select-InstallerOption "Choose a game channel:" @(
      "Hoenn Reloaded",
      "Hoenn Reloaded Testing"
    )
    $Channel = if ($selected -eq 1) { "Public" } else { "Testing" }
  }
  if ($Channel -notmatch '\A(?:Public|Testing)\z') {
    throw "Channel must be Public or Testing."
  }

  if (-not $InstallType) {
    $selected = Select-InstallerOption "Choose what to install:" @(
      "Core",
      "Core + Spritepacks"
    )
    $InstallType = if ($selected -eq 1) { "Core" } else { "CoreAndSpritepacks" }
  }
  if ($InstallType -notmatch '\A(?:Core|CoreAndSpritepacks)\z') {
    throw "InstallType must be Core or CoreAndSpritepacks."
  }
  $includeSpritepacks = $InstallType -eq "CoreAndSpritepacks"

  Write-Host ""
  Write-Host " Channel: $Channel"
  Write-Host (" Package: {0}" -f $(if ($includeSpritepacks) { "Core + Spritepacks" } else { "Core" }))
  Write-Host " Existing saves, mods, settings, profiles, and imports are preserved."

  Write-Phase 1 5 "Checking source"
  $publicManifest = $null
  if ($Channel -eq "Public") {
    $publicManifest = Get-JsonSource $ManifestFile $PublicManifestUrl "Public Core manifest"
    if (@(1, 2) -notcontains [int]$publicManifest.schema -or
        $publicManifest.ready -eq $false -or
        -not $publicManifest.core) {
      throw "The Public Core manifest is invalid or not ready."
    }
    $version = $publicManifest.version.ToString()
    $core = $publicManifest.core
    $coreName = if ($core.file) {
      $core.file.ToString()
    } else {
      [IO.Path]::GetFileName(([Uri]$core.url).AbsolutePath)
    }
    $coreArchive = Join-Path $TempRoot $coreName
  } else {
    $version = "Testing"
    $coreArchive = Join-Path $TempRoot "Hoenn-Reloaded-Testing-main.zip"
  }
  Write-Host "Selected version: $version"

  if (Test-Path -LiteralPath $PreviousManagedManifestPath -PathType Leaf) {
    $oldManagedFiles = Get-ManagedFiles $PreviousManagedManifestPath
  } else {
    $oldManagedFiles = Get-ManagedFiles $ManagedManifestPath
    if (Test-Path -LiteralPath $ManagedManifestPath -PathType Leaf) {
      Copy-Item -LiteralPath $ManagedManifestPath -Destination $PreviousManagedManifestPath -Force
    }
  }

  Write-Phase 2 5 "Downloading Core"
  if ($Channel -eq "Public") {
    Invoke-Download $core.url $coreArchive ([long]$core.size) $core.sha256 "Hoenn Reloaded Public Core" $false
  } elseif ($TestingArchiveFile) {
    $testingUri = (New-Object Uri([IO.Path]::GetFullPath($TestingArchiveFile))).AbsoluteUri
    Invoke-Download $testingUri $coreArchive 0 "" "Hoenn Reloaded Testing" $true
  } else {
    Invoke-Download $TestingArchiveUrl $coreArchive 0 "" "Hoenn Reloaded Testing" $true
  }

  Write-Phase 3 5 "Installing Core"
  if ($Channel -eq "Public") {
    Expand-Direct $coreArchive "Hoenn Reloaded Public Core" $false
  } else {
    $version = Install-TestingSnapshot $coreArchive
  }
  $newManagedFiles = Get-ManagedFiles $ManagedManifestPath
  if ($newManagedFiles.Count -eq 0) {
    throw "The installed Core did not provide a managed file inventory."
  }

  $spriteArchives = @()
  Write-Phase 4 5 $(if ($includeSpritepacks) { "Checking Spritepacks" } else { "Preserving Spritepacks" })
  if ($includeSpritepacks) {
    $catalogUrl = if ($publicManifest -and $publicManifest.spritepack_catalog_url) {
      $publicManifest.spritepack_catalog_url.ToString()
    } else {
      $SpritepackCatalogUrl
    }
    $catalog = Get-JsonSource $SpritepackCatalogFile $catalogUrl "Spritepack catalog"
    $spritepack = Get-LatestFullSpritepack $catalog
    $wantedSpritepackId = $spritepack.build_id.ToString()
    $installedSpritepackId = Get-InstalledSpritepackId
    if ($Repair -or -not $installedSpritepackId -or $installedSpritepackId -ne $wantedSpritepackId) {
      $parts = @($spritepack.parts)
      if ($parts.Count -gt 0) {
        $partNumber = 0
        foreach ($part in $parts) {
          $partNumber++
          $partName = if ($part.file) {
            $part.file.ToString()
          } else {
            [IO.Path]::GetFileName(([Uri]$part.url).AbsolutePath)
          }
          $partPath = Join-Path $TempRoot $partName
          Invoke-Download $part.url $partPath ([long]$part.size) $part.sha256 "Full Spritepack part $partNumber/$($parts.Count)" $false
          $spriteArchives += $partPath
        }
        $spriteArchive = $spriteArchives[0]
      } else {
        if (-not $spritepack.url) { throw "Full Spritepack has no download URL or parts." }
        $spriteName = [IO.Path]::GetFileName(([Uri]$spritepack.url).AbsolutePath)
        $spriteArchive = Join-Path $TempRoot $spriteName
        Invoke-Download $spritepack.url $spriteArchive ([long]$spritepack.size) $spritepack.sha256 "Full Spritepack" $false
        $spriteArchives += $spriteArchive
      }
      Expand-Direct $spriteArchive "Full Spritepack" $true
      if ((Get-InstalledSpritepackId) -ne $wantedSpritepackId) {
        throw "The installed Full Spritepack manifest does not match the catalog."
      }
      Write-SpritepackInstallState $spritepack
    } else {
      Write-Host "Full Spritepack $installedSpritepackId is already installed."
    }
  } else {
    Write-Host "Core-only selected. Existing Spritepacks were not changed."
  }

  Write-Phase 5 5 "Finalizing installation"
  Remove-ObsoleteManagedFiles $oldManagedFiles $newManagedFiles
  Remove-Item -LiteralPath $PreviousManagedManifestPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $TestingStageRoot -Recurse -Force -ErrorAction SilentlyContinue
  if (-not $KeepDownloads) {
    Remove-Item -LiteralPath $coreArchive -Force -ErrorAction SilentlyContinue
    foreach ($archive in $spriteArchives) {
      Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    }
  }

  Write-Host ""
  Write-Host "Hoenn Reloaded $Channel ($version) is installed." -ForegroundColor Green
  exit 0
} catch {
  Write-Progress -Activity "Hoenn Reloaded installation" -Completed
  Write-Host ""
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Rerun the installer to resume or repair the installation."
  exit 1
}
