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
  [switch]$KeepDownloads,
  [switch]$SkipSelfUpdate
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::DefaultConnectionLimit = 6
Add-Type -AssemblyName System.Net.Http

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $GameRoot) { $GameRoot = $ScriptRoot }
$GameRoot = $GameRoot.Trim().Trim([char]34)
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
$SevenZip = Join-Path $GameRoot "REQUIRED_BY_INSTALLER_UPDATER\7z.exe"
$BufferSize = 1024 * 1024
$DownloadConnections = 6
$SegmentedDownloadMinimum = 24MB
$DownloadRetries = 3
$DownloadRetryDelay = 1.0
$DiskSpaceMargin = 64MB
$InstallerVersion = "4.1.0"
$ManagedManifestPath = Join-Path $GameRoot "Reloaded\InstallerFiles.json"
$IncompleteInstallPath = Join-Path $GameRoot "Reloaded\InstallerIncomplete.json"
$SpriteStatePath = Join-Path $GameRoot "Mods\Reloaded\SpritepacksInstalled.json"
$CriticalInstallPaths = @(
  "Game.exe",
  "Game.ini",
  "mkxp.json",
  "Data/Scripts/999_Main/999_Main.rb",
  "Reloaded/Bootstrap.rb",
  "Reloaded/LoadOrder.rb",
  "Reloaded/Version.md",
  "Reloaded/InstallerFiles.json"
)

$TempRoot = Join-Path $GameRoot "REQUIRED_BY_INSTALLER_UPDATER\Cache"
$PreviousManagedManifestPath = Join-Path $TempRoot "PreviousInstallerFiles.json"
$TestingStageRoot = Join-Path $TempRoot "TestingStage"
$CriticalInstallRoot = Join-Path $TempRoot "CriticalInstall"

$ProtectedPrefixes = @(
  "mods/",
  "reloaded/logging/",
  "reloaded/cache/",
  "reloaded/settings.txt",
  "reloaded/installerincomplete.json",
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
  '^Reloaded/InstallerIncomplete\.json$',
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
  $temporary = "$Path.tmp"
  try {
    [IO.File]::WriteAllText(
      $temporary,
      (($Value | ConvertTo-Json -Depth $Depth) + "`r`n"),
      (New-Object Text.UTF8Encoding($false))
    )
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
  }
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

function Write-InstallMarker(
  [string]$Phase,
  [string]$Version,
  [string]$SpritepackBuildId = ""
) {
  $existing = $null
  try { $existing = Read-JsonFile $IncompleteInstallPath } catch {}
  $startedAt = if ($existing -and $existing.started_at) {
    $existing.started_at.ToString()
  } else {
    (Get-Date).ToUniversalTime().ToString("o")
  }
  $channelValue = $Channel.ToString().ToLowerInvariant()
  $installTypeValue = if ($InstallType -eq "CoreAndSpritepacks") { "full" } else { "core" }
  Write-JsonFile ([ordered]@{
    schema = 1
    state = "incomplete"
    channel = $channelValue
    install_type = $installTypeValue
    version = $Version
    phase = $Phase
    spritepack_build_id = $SpritepackBuildId
    started_at = $startedAt
    updated_at = (Get-Date).ToUniversalTime().ToString("o")
  }) $IncompleteInstallPath
}

function Remove-InstallMarker {
  Remove-Item -LiteralPath $IncompleteInstallPath -Force -ErrorAction SilentlyContinue
}

function Copy-FileAtomically([string]$Source, [string]$Destination) {
  $parent = Split-Path -Parent $Destination
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $temporary = "$Destination.installing"
  try {
    Copy-Item -LiteralPath $Source -Destination $temporary -Force
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
      [IO.File]::Replace($temporary, $Destination, $null, $true)
    } else {
      [IO.File]::Move($temporary, $Destination)
    }
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
  }
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

function Remove-DownloadSegments([string]$PartPath) {
  for ($index = 0; $index -lt $DownloadConnections; $index++) {
    Remove-Item -LiteralPath "$PartPath.segment$index" -Force -ErrorAction SilentlyContinue
  }
}

function Get-PartMetaPath([string]$PartPath) {
  return "$PartPath.meta.json"
}

function Remove-PartialDownload([string]$PartPath) {
  Remove-Item -LiteralPath $PartPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Get-PartMetaPath $PartPath) -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath "$(Get-PartMetaPath $PartPath).tmp" -Force -ErrorAction SilentlyContinue
  Remove-DownloadSegments $PartPath
}

function Get-TextSha256([string]$Value) {
  $hash = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace("-", "").ToLowerInvariant()
  } finally {
    $hash.Dispose()
  }
}

function Get-RemoteDownloadInfo([string]$Url) {
  $request = [Net.HttpWebRequest]::Create($Url)
  $request.Method = "HEAD"
  $request.AllowAutoRedirect = $true
  $request.Timeout = 30000
  $request.ReadWriteTimeout = 30000
  $request.UserAgent = "HoennReloadedInstaller/4"
  try {
    $response = $request.GetResponse()
    try {
      return [pscustomobject]@{
        size = [long]$response.ContentLength
        etag = [string]$response.Headers["ETag"]
        last_modified = [string]$response.Headers["Last-Modified"]
      }
    } finally {
      $response.Close()
    }
  } catch {
    return [pscustomobject]@{ size = 0L; etag = ""; last_modified = "" }
  }
}

function Test-ResumeMetadata($Metadata, [string]$Url, [long]$Total, $Info, [string]$Mode) {
  if (-not $Metadata) { return $false }
  if ([int]$Metadata.version -ne 1 -or
      $Metadata.mode.ToString() -ne $Mode -or
      $Metadata.url_sha256.ToString() -ne (Get-TextSha256 $Url) -or
      [long]$Metadata.total -ne $Total) {
    return $false
  }
  $etag = $Info.etag.ToString()
  $modified = $Info.last_modified.ToString()
  if ($etag -and $Metadata.etag.ToString() -ne $etag) { return $false }
  if (-not $etag -and $modified -and $Metadata.last_modified.ToString() -ne $modified) { return $false }
  return $true
}

function Get-SegmentedReceivedBytes($Metadata, [string]$Url, [long]$Total, $Info) {
  if (-not (Test-ResumeMetadata $Metadata $Url $Total $Info "segmented") -or
      -not $Metadata.ranges -or
      @($Metadata.ranges).Count -ne $DownloadConnections) {
    return -1L
  }
  $baseSize = [long][Math]::Floor($Total / $DownloadConnections)
  $receivedTotal = 0L
  for ($index = 0; $index -lt $DownloadConnections; $index++) {
    $expectedStart = $index * $baseSize
    $expectedEnd = if ($index -eq ($DownloadConnections - 1)) {
      $Total - 1
    } else {
      (($index + 1) * $baseSize) - 1
    }
    $range = @($Metadata.ranges)[$index]
    $length = ($expectedEnd - $expectedStart) + 1
    if ([long]$range.start -ne $expectedStart -or
        [long]$range.end -ne $expectedEnd -or
        [long]$range.received -lt 0 -or
        [long]$range.received -gt $length) {
      return -1L
    }
    $receivedTotal += [long]$range.received
  }
  return [Math]::Min($Total, $receivedTotal)
}

function Assert-FreeDiskSpace([string]$Path, [long]$Required, [string]$Label) {
  if ($Required -le 0) { return }
  $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
  $drive = New-Object IO.DriveInfo($root)
  $needed = $Required + $DiskSpaceMargin
  if ($drive.AvailableFreeSpace -lt $needed) {
    throw ("Not enough free disk space for {0}. Required {1:N2} GB; available {2:N2} GB." -f
      $Label, ($needed / 1GB), ($drive.AvailableFreeSpace / 1GB))
  }
}

function Wait-DownloadRetry([int]$Attempt, $ErrorRecord = $null) {
  $delay = $DownloadRetryDelay * [Math]::Pow(2, [Math]::Max(0, $Attempt - 1))
  if ($ErrorRecord -and $ErrorRecord.Exception -and $ErrorRecord.Exception.Response) {
    $header = $ErrorRecord.Exception.Response.Headers["Retry-After"]
    $serverDelay = 0.0
    if ($header -and [double]::TryParse($header, [ref]$serverDelay)) {
      $delay = [Math]::Max($delay, $serverDelay)
    } elseif ($header) {
      $retryDate = [DateTimeOffset]::MinValue
      if ([DateTimeOffset]::TryParse($header, [ref]$retryDate)) {
        $dateDelay = ($retryDate.ToUniversalTime() - [DateTimeOffset]::UtcNow).TotalSeconds
        $delay = [Math]::Max($delay, [Math]::Max(0.0, $dateDelay))
      }
    }
  }
  $delay += (Get-Random -Minimum 0 -Maximum 500) / 1000.0
  Write-Host ("Retrying in {0:N1} seconds..." -f $delay) -ForegroundColor Yellow
  Start-Sleep -Milliseconds ([int]($delay * 1000))
}

function Invoke-SingleHttpDownload(
  [string]$Url,
  [string]$PartPath,
  [long]$ExpectedSize,
  [string]$Label,
  $Info,
  [bool]$AllowResume = $true
) {
  $metaPath = Get-PartMetaPath $PartPath
  $metadata = Read-JsonFile $metaPath
  $totalHint = if ($ExpectedSize -gt 0) { $ExpectedSize } else { [long]$Info.size }
  if (-not (Test-ResumeMetadata $metadata $Url $totalHint $Info "single")) {
    Remove-PartialDownload $PartPath
    $metadata = $null
  }
  $existing = if ($AllowResume -and (Test-Path -LiteralPath $PartPath -PathType Leaf)) {
    (Get-Item -LiteralPath $PartPath).Length
  } else {
    0L
  }
  if ($ExpectedSize -gt 0 -and $existing -gt $ExpectedSize) {
    Remove-PartialDownload $PartPath
    $existing = 0L
  }

  $request = [Net.HttpWebRequest]::Create($Url)
  $request.AllowAutoRedirect = $true
  $request.Timeout = 30000
  $request.ReadWriteTimeout = 30000
  $request.UserAgent = "HoennReloadedInstaller/4"
  if ($existing -gt 0) {
    $request.AddRange($existing)
    $validator = if ($Info.etag) { $Info.etag.ToString() } else { $Info.last_modified.ToString() }
    if ($validator) { $request.Headers["If-Range"] = $validator }
  }

  try {
    $response = $request.GetResponse()
  } catch {
    if ($existing -gt 0) {
      Remove-PartialDownload $PartPath
      return Invoke-SingleHttpDownload $Url $PartPath $ExpectedSize $Label $Info $false
    }
    throw
  }

  try {
    $append = $existing -gt 0 -and [int]$response.StatusCode -eq 206
    if (-not $append) {
      Remove-PartialDownload $PartPath
      $existing = 0L
    }
    $mode = if ($append) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }
    $output = New-Object IO.FileStream($PartPath, $mode, [IO.FileAccess]::Write, [IO.FileShare]::None)
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
        $state = [ordered]@{
          version = 1
          mode = "single"
          url_sha256 = Get-TextSha256 $Url
          total = $total
          etag = $Info.etag.ToString()
          last_modified = $Info.last_modified.ToString()
          received = $received
        }
        Write-JsonFile $state $metaPath
        $buffer = New-Object byte[] $BufferSize
        $lastProgress = [Environment]::TickCount
        while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
          $output.Write($buffer, 0, $read)
          $received += $read
          $state.received = $received
          $now = [Environment]::TickCount
          if (($now - $lastProgress) -ge 250) {
            if ($total -gt 0) {
              $percent = [Math]::Min(100, [int](($received * 100L) / $total))
              Write-Progress -Activity "Downloading $Label" -Status ("{0:N1} MB / {1:N1} MB" -f ($received / 1MB), ($total / 1MB)) -PercentComplete $percent
            } else {
              Write-Progress -Activity "Downloading $Label" -Status ("{0:N1} MB" -f ($received / 1MB))
            }
            $lastProgress = $now
            Write-JsonFile $state $metaPath
          }
        }
        Write-JsonFile $state $metaPath
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
}

function Invoke-SegmentedHttpDownload(
  [string]$Url,
  [string]$PartPath,
  [long]$TotalSize,
  [string]$Label,
  $Info
) {
  if ($TotalSize -lt $SegmentedDownloadMinimum) { return $false }

  $metaPath = Get-PartMetaPath $PartPath
  $baseSize = [long][Math]::Floor($TotalSize / $DownloadConnections)
  $expectedRanges = @()
  for ($index = 0; $index -lt $DownloadConnections; $index++) {
    $start = $index * $baseSize
    $end = if ($index -eq ($DownloadConnections - 1)) {
      $TotalSize - 1
    } else {
      (($index + 1) * $baseSize) - 1
    }
    $expectedRanges += [pscustomobject]@{ start = $start; end = $end; received = 0L }
  }
  $state = Read-JsonFile $metaPath
  $validState = (Test-ResumeMetadata $state $Url $TotalSize $Info "segmented") -and
    $state.ranges -and @($state.ranges).Count -eq $DownloadConnections -and
    (Test-Path -LiteralPath $PartPath -PathType Leaf) -and
    (Get-Item -LiteralPath $PartPath).Length -eq $TotalSize
  if ($validState) {
    for ($index = 0; $index -lt $DownloadConnections; $index++) {
      $saved = @($state.ranges)[$index]
      $expected = $expectedRanges[$index]
      $length = ([long]$expected.end - [long]$expected.start) + 1
      if ([long]$saved.start -ne [long]$expected.start -or
          [long]$saved.end -ne [long]$expected.end -or
          [long]$saved.received -lt 0 -or
          [long]$saved.received -gt $length) {
        $validState = $false
        break
      }
    }
  }

  if (-not $validState) {
    Remove-PartialDownload $PartPath
    $state = [pscustomobject]@{
      version = 1
      mode = "segmented"
      url_sha256 = Get-TextSha256 $Url
      total = $TotalSize
      etag = $Info.etag.ToString()
      last_modified = $Info.last_modified.ToString()
      ranges = $expectedRanges
    }
    $initial = New-Object IO.FileStream($PartPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try {
      $initial.SetLength($TotalSize)
    } finally {
      $initial.Dispose()
    }
    Write-JsonFile $state $metaPath
  }

  $requests = @()
  $responses = @()
  $streams = @()
  $outputs = @()
  $copyTasks = @()
  $client = $null
  $handler = $null
  $unsupported = $false
  try {
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $client = New-Object Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(60)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("HoennReloadedInstaller/4")
    $validator = if ($Info.etag) { $Info.etag.ToString() } else { $Info.last_modified.ToString() }
    $responseTasks = @()

    foreach ($range in @($state.ranges)) {
      $segmentLength = ([long]$range.end - [long]$range.start) + 1
      $received = [long]$range.received
      if ($received -lt 0 -or $received -gt $segmentLength) {
        throw "The download resume metadata is invalid."
      }
      if ($received -eq $segmentLength) {
        $requests += $null
        $responseTasks += $null
        continue
      }
      $request = New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Get, $Url)
      $request.Headers.Range = New-Object Net.Http.Headers.RangeHeaderValue(([long]$range.start + $received), [long]$range.end)
      if ($validator) { $request.Headers.TryAddWithoutValidation("If-Range", $validator) | Out-Null }
      $requests += $request
      $responseTasks += $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead)
    }

    for ($index = 0; $index -lt $DownloadConnections; $index++) {
      if (-not $responseTasks[$index]) {
        $responses += $null
        $streams += $null
        $outputs += $null
        $copyTasks += $null
        continue
      }
      $response = $responseTasks[$index].GetAwaiter().GetResult()
      $responses += $response
      if ([int]$response.StatusCode -ne 206) {
        $unsupported = $true
        return $false
      }
      $range = @($state.ranges)[$index]
      $expectedStart = [long]$range.start + [long]$range.received
      $expectedLength = ([long]$range.end - $expectedStart) + 1
      $contentRange = $response.Content.Headers.ContentRange
      if (-not $contentRange -or
          [long]$contentRange.From -ne $expectedStart -or
          [long]$contentRange.To -ne [long]$range.end -or
          ($contentRange.Length -and [long]$contentRange.Length -ne $TotalSize) -or
          ($response.Content.Headers.ContentLength -and
           [long]$response.Content.Headers.ContentLength -ne $expectedLength)) {
        $unsupported = $true
        return $false
      }
      $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
      $streams += $stream
      $output = New-Object IO.FileStream($PartPath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
      $output.Seek(([long]$range.start + [long]$range.received), [IO.SeekOrigin]::Begin) | Out-Null
      $outputs += $output
      $copyTasks += $stream.CopyToAsync($output, $BufferSize)
    }

    while (@($copyTasks | Where-Object { $_ -and -not $_.IsCompleted }).Count -gt 0) {
      $receivedTotal = 0L
      for ($index = 0; $index -lt $DownloadConnections; $index++) {
        $range = @($state.ranges)[$index]
        if ($outputs[$index]) {
          $range.received = [long]$outputs[$index].Position - [long]$range.start
        }
        $receivedTotal += [long]$range.received
      }
      Write-JsonFile $state $metaPath
      $percent = [Math]::Min(100, [int](($receivedTotal * 100L) / $TotalSize))
      Write-Progress -Activity "Downloading $Label ($DownloadConnections connections)" -Status ("{0:N1} MB / {1:N1} MB" -f ($receivedTotal / 1MB), ($TotalSize / 1MB)) -PercentComplete $percent
      Start-Sleep -Milliseconds 250
    }
    foreach ($task in $copyTasks) {
      if ($task) { $task.GetAwaiter().GetResult() }
    }
    $receivedTotal = 0L
    for ($index = 0; $index -lt $DownloadConnections; $index++) {
      $range = @($state.ranges)[$index]
      if ($outputs[$index]) {
        $range.received = [long]$outputs[$index].Position - [long]$range.start
      }
      $receivedTotal += [long]$range.received
    }
    Write-JsonFile $state $metaPath
    if ($receivedTotal -ne $TotalSize) {
      throw "The ranged download was incomplete."
    }
  } finally {
    foreach ($output in $outputs) { if ($output) { $output.Dispose() } }
    foreach ($stream in $streams) { if ($stream) { $stream.Dispose() } }
    foreach ($response in $responses) { if ($response) { $response.Dispose() } }
    foreach ($request in $requests) { if ($request) { $request.Dispose() } }
    if ($client) { $client.Dispose() }
    if ($handler) { $handler.Dispose() }
    Write-Progress -Activity "Downloading $Label ($DownloadConnections connections)" -Completed
  }
  Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
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
    Remove-PartialDownload $part
  } elseif (Test-DownloadedFile $Destination $ExpectedSize $ExpectedSha256) {
    Remove-PartialDownload $part
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
    Assert-FreeDiskSpace $part $total $Label
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

  $info = Get-RemoteDownloadInfo $Url
  $downloadSize = if ($ExpectedSize -gt 0) { $ExpectedSize } else { [long]$info.size }
  $resumeMetadata = Read-JsonFile (Get-PartMetaPath $part)
  $existingBytes = 0L
  if ((Test-Path -LiteralPath $part -PathType Leaf) -and
      $resumeMetadata -and $resumeMetadata.mode.ToString() -eq "segmented") {
    $resumeReceived = Get-SegmentedReceivedBytes $resumeMetadata $Url $downloadSize $info
    if ($resumeReceived -ge 0 -and (Get-Item -LiteralPath $part).Length -eq $downloadSize) {
      $existingBytes = $downloadSize
    } else {
      Remove-PartialDownload $part
    }
  } elseif (Test-Path -LiteralPath $part -PathType Leaf) {
    $existingBytes = (Get-Item -LiteralPath $part).Length
  }
  Assert-FreeDiskSpace $part ([Math]::Max(0L, $downloadSize - $existingBytes)) $Label
  $segmented = $false
  if ($downloadSize -ge $SegmentedDownloadMinimum) {
    for ($attempt = 1; $attempt -le $DownloadRetries; $attempt++) {
      try {
        Write-Host "Downloading $Label with $DownloadConnections connections..."
        $segmented = Invoke-SegmentedHttpDownload $Url $part $downloadSize $Label $info
        if (-not $segmented) {
          Write-Host "The server did not accept segmented downloading. Using one connection."
          Remove-PartialDownload $part
        }
        break
      } catch {
        if ($attempt -ge $DownloadRetries) { throw }
        Wait-DownloadRetry $attempt $_
      }
    }
  }
  if (-not $segmented) {
    for ($attempt = 1; $attempt -le $DownloadRetries; $attempt++) {
      try {
        Invoke-SingleHttpDownload $Url $part $downloadSize $Label $info
        break
      } catch {
        if ($attempt -ge $DownloadRetries) { throw }
        Wait-DownloadRetry $attempt $_
      }
    }
  }

  Move-Item -LiteralPath $part -Destination $Destination -Force
  Remove-Item -LiteralPath (Get-PartMetaPath $part) -Force -ErrorAction SilentlyContinue
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

function Convert-InstallerVersion([string]$Value) {
  $match = [regex]::Match($Value, '\d+(?:\.\d+){0,3}')
  if (-not $match.Success) { return [version]"0.0.0" }
  $parts = @($match.Value.Split("."))
  while ($parts.Count -lt 3) { $parts += "0" }
  return [version]($parts -join ".")
}

function Invoke-InstallerSelfUpdate($Manifest) {
  if ($SkipSelfUpdate -or [int]$Manifest.schema -lt 3) { return }
  $bootstrap = $Manifest.bootstrap
  $remoteText = if ($bootstrap.version) { $bootstrap.version.ToString() } else { $Manifest.version.ToString() }
  $remoteVersion = Convert-InstallerVersion $remoteText
  $minimumVersion = Convert-InstallerVersion ([string]$Manifest.minimum_installer_version)
  $currentVersion = Convert-InstallerVersion $InstallerVersion
  if ($remoteVersion -le $currentVersion -and $minimumVersion -le $currentVersion) { return }
  if (-not $bootstrap.url -or -not $bootstrap.sha256) {
    throw "The release manifest has no hash-verified installer update."
  }
  $archiveName = if ($bootstrap.file) { $bootstrap.file.ToString() } else { "InstallerUpdate.zip" }
  $archive = Join-Path $TempRoot $archiveName
  Invoke-Download $bootstrap.url.ToString() $archive ([long]$bootstrap.size) $bootstrap.sha256.ToString() "Installer update" $false
  $updateRoot = Join-Path $TempRoot "InstallerUpdate-$remoteText"
  Remove-Item -LiteralPath $updateRoot -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $updateRoot | Out-Null
  Assert-SafeArchive $archive $true
  & $SevenZip x -y "-o$updateRoot" -- $archive | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "The installer update could not be extracted." }
  $stagedInstaller = Join-Path $updateRoot "Hoenn Reloaded Installer.ps1"
  if (-not (Test-Path -LiteralPath $stagedInstaller -PathType Leaf)) {
    throw "The installer update package is invalid."
  }
  Get-ChildItem -LiteralPath $updateRoot -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $ScriptRoot -Recurse -Force
  }
  $updated = Join-Path $ScriptRoot "Hoenn Reloaded Installer.ps1"
  Write-Host "Updating installer $InstallerVersion -> $remoteText..." -ForegroundColor Cyan
  $arguments = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $updated,
    "-GameRoot", $GameRoot, "-SkipSelfUpdate",
    "-PublicManifestUrl", $PublicManifestUrl,
    "-TestingArchiveUrl", $TestingArchiveUrl,
    "-SpritepackCatalogUrl", $SpritepackCatalogUrl
  )
  if ($Channel) { $arguments += @("-Channel", $Channel) }
  if ($InstallType) { $arguments += @("-InstallType", $InstallType) }
  if ($ManifestFile) { $arguments += @("-ManifestFile", $ManifestFile) }
  if ($TestingArchiveFile) { $arguments += @("-TestingArchiveFile", $TestingArchiveFile) }
  if ($SpritepackCatalogFile) { $arguments += @("-SpritepackCatalogFile", $SpritepackCatalogFile) }
  if ($Repair) { $arguments += "-Repair" }
  if ($KeepDownloads) { $arguments += "-KeepDownloads" }
  & powershell.exe @arguments
  exit $LASTEXITCODE
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
  $critical = @()
  if (-not $AllowProtected) {
    $archiveEntries = @(& $SevenZip l -slt -- $Archive 2>&1 | ForEach-Object {
      if ($_ -match '^Path = (.+)$') {
        try { Convert-ToSafeRelativePath $Matches[1] } catch {}
      }
    })
    $entrySet = @{}
    foreach ($entry in $archiveEntries) {
      if ($entry) { $entrySet[$entry.ToLowerInvariant()] = $true }
    }
    $critical = @($CriticalInstallPaths | Where-Object {
      $entrySet.ContainsKey($_.ToLowerInvariant())
    })
  }

  $excludeArguments = @($critical | ForEach-Object { "-x!$_" })
  & $SevenZip x -aoa -y -bsp1 -bb0 "-o$GameRoot" @excludeArguments -- $Archive
  if ($LASTEXITCODE -ne 0) {
    throw "7-Zip failed while installing $Label (exit code $LASTEXITCODE)."
  }

  if ($critical.Count -gt 0) {
    Remove-Item -LiteralPath $CriticalInstallRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $CriticalInstallRoot | Out-Null
    & $SevenZip x -aoa -y -bsp0 -bb0 "-o$CriticalInstallRoot" -- $Archive @critical
    if ($LASTEXITCODE -ne 0) {
      throw "7-Zip failed while preparing critical $Label files (exit code $LASTEXITCODE)."
    }
    foreach ($relative in $critical) {
      $source = Join-Path $CriticalInstallRoot $relative
      $destination = Join-Path $GameRoot $relative
      if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Critical install file was not extracted: $relative"
      }
      Copy-FileAtomically $source $destination
    }
    Remove-Item -LiteralPath $CriticalInstallRoot -Recurse -Force -ErrorAction SilentlyContinue
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
    Copy-FileAtomically $file.FullName $destination
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

  if (Test-Path -LiteralPath $IncompleteInstallPath -PathType Leaf) {
    $incomplete = $null
    try { $incomplete = Read-JsonFile $IncompleteInstallPath } catch {}
    $Repair = $true
    if ($incomplete -and $incomplete.channel -match '\A(?:public|testing)\z') {
      $Channel = if ($incomplete.channel -eq "testing") { "Testing" } else { "Public" }
    }
    if ($incomplete -and $incomplete.install_type -match '\A(?:core|full)\z') {
      $InstallType = if ($incomplete.install_type -eq "full") { "CoreAndSpritepacks" } else { "Core" }
    }
    Write-Host ""
    Write-Host "An interrupted installation was detected." -ForegroundColor Yellow
    Write-Host "Repair mode is required and has been enabled." -ForegroundColor Yellow
  }

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
  $publicManifest = Get-JsonSource $ManifestFile $PublicManifestUrl "Public Core manifest"
  if (@(1, 2, 3) -notcontains [int]$publicManifest.schema -or
      $publicManifest.ready -eq $false -or
      -not $publicManifest.core) {
    throw "The Public Core manifest is invalid or not ready."
  }
  Invoke-InstallerSelfUpdate $publicManifest
  if ($Channel -eq "Public") {
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
    $coreInstalledSize = if ($core.installed_size) {
      [long]$core.installed_size
    } else {
      [long](Get-Item -LiteralPath $coreArchive).Length
    }
    Assert-FreeDiskSpace $GameRoot $coreInstalledSize "Hoenn Reloaded Public Core extraction"
    Write-InstallMarker "core" $version
    Expand-Direct $coreArchive "Hoenn Reloaded Public Core" $false
  } else {
    Assert-FreeDiskSpace $GameRoot ([long](Get-Item -LiteralPath $coreArchive).Length) "Hoenn Reloaded Testing extraction"
    Write-InstallMarker "core" $version
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
      $spriteInstalledSize = if ($spritepack.installed_size) {
        [long]$spritepack.installed_size
      } else {
        [long](Get-Item -LiteralPath $spriteArchive).Length
      }
      Assert-FreeDiskSpace $GameRoot $spriteInstalledSize "Full Spritepack extraction"
      Write-InstallMarker "spritepack" $version $wantedSpritepackId
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
  Write-InstallMarker "finalizing" $version $(if ($includeSpritepacks) { $wantedSpritepackId } else { "" })
  Remove-ObsoleteManagedFiles $oldManagedFiles $newManagedFiles
  Remove-Item -LiteralPath $PreviousManagedManifestPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $TestingStageRoot -Recurse -Force -ErrorAction SilentlyContinue
  Remove-InstallMarker
  if (-not $KeepDownloads) {
    Remove-Item -LiteralPath $coreArchive -Force -ErrorAction SilentlyContinue
    foreach ($archive in $spriteArchives) {
      Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
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
