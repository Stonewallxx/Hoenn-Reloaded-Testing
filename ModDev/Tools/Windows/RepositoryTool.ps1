param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("Publish", "Update", "Delete")]
  [string]$Action,
  [ValidateSet("", "Mod", "Profile", "mod", "profile")]
  [string]$Kind = "",
  [string]$GameRoot = "",
  [string]$Repository = "Stonewallxx/Hoenn-Reloaded-Mods",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Branch = "main"
$MaxPackageBytes = 1GB
$BlockedExtensions = @(".exe", ".dll", ".bat", ".cmd", ".ps1", ".psm1", ".vbs", ".js", ".jar", ".msi", ".scr", ".com", ".sh", ".py")
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GameRoot)) { $GameRoot = Join-Path $ScriptRoot "..\..\.." }
$GameRoot = [IO.Path]::GetFullPath($GameRoot.Trim().Trim([char]34))
$TempParent = Join-Path ([IO.Path]::GetTempPath()) "HoennReloadedPublisher"
$TempRoot = Join-Path $TempParent ("Hoenn-Reloaded-Mods-{0}" -f [Guid]::NewGuid().ToString("N"))
$Collection = ""
$Login = ""
$RepoOwner = $Repository.Split('/')[0].ToLowerInvariant()

function Write-Phase([int]$Current, [int]$Total, [string]$Message) {
  Write-Host ""
  Write-Host ("[{0}/{1}] {2}" -f $Current, $Total, $Message) -ForegroundColor Cyan
}

function Write-Bar([long]$Current, [long]$Total, [string]$Label = "") {
  $ratio = if ($Total -le 0) { 1.0 } else { [Math]::Max(0.0, [Math]::Min(1.0, $Current / [double]$Total)) }
  $percent = [int]($ratio * 100)
  $prefix = "["
  $suffix = if ($Label) { ("] {0,3}% {1}" -f $percent, $Label) } else { ("] {0,3}%" -f $percent) }
  $consoleWidth = 56 + $prefix.Length + $suffix.Length + 1
  try {
    if ([Console]::WindowWidth -gt 0) { $consoleWidth = [Console]::WindowWidth }
  } catch {
  }
  $width = [Math]::Max(16, $consoleWidth - $prefix.Length - $suffix.Length - 1)
  $filled = [int][Math]::Floor($width * $ratio)
  Write-Host $prefix -NoNewline
  if ($filled -gt 0) { Write-Host (" " * $filled) -NoNewline -BackgroundColor Cyan }
  if ($width - $filled -gt 0) { Write-Host (" " * ($width - $filled)) -NoNewline -BackgroundColor DarkGray }
  Write-Host $suffix
}

function Quote-ProcessArgument([string]$Value) {
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-Gh([string[]]$Arguments, [string]$Status = "Working", [switch]$AllowFailure) {
  $outputPath = Join-Path $TempRoot ("gh-{0}.txt" -f [Guid]::NewGuid().ToString("N"))
  $errorPath = Join-Path $TempRoot ("gh-{0}.err.txt" -f [Guid]::NewGuid().ToString("N"))
  $argumentLine = ($Arguments | ForEach-Object { Quote-ProcessArgument $_ }) -join " "
  $process = Start-Process -FilePath "gh.exe" -ArgumentList $argumentLine -NoNewWindow -PassThru -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
  # Accessing Handle immediately keeps ExitCode available after polling on Windows.
  $processHandle = $process.Handle
  $frames = @(
    [char]0x280B, [char]0x2819, [char]0x2839, [char]0x2838, [char]0x283C,
    [char]0x2834, [char]0x2826, [char]0x2827, [char]0x2807, [char]0x280F
  )
  $frame = 0
  while (-not $process.HasExited) {
    Write-Host -NoNewline ("`r  {0} {1}" -f $frames[$frame % $frames.Count], $Status)
    $frame++
    Start-Sleep -Milliseconds 90
    $process.Refresh()
  }
  $process.WaitForExit()
  $process.Refresh()
  $exitCode = $process.ExitCode
  Write-Host -NoNewline ("`r" + (" " * ([Math]::Min(100, $Status.Length + 8))) + "`r")
  $output = if (Test-Path -LiteralPath $outputPath) { Get-Content -LiteralPath $outputPath -Raw } else { "" }
  if (Test-Path -LiteralPath $errorPath) { $output += (Get-Content -LiteralPath $errorPath -Raw) }
  Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue
  $result = @{ ExitCode = $exitCode; Output = $output }
  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw ([Exception]::new(($output.Trim() | ForEach-Object { if ($_){$_}else{"GitHub CLI command failed."} })))
  }
  return $result
}

function ConvertTo-Hashtable($Value) {
  if ($null -eq $Value) { return $null }
  if ($Value -is [Collections.IDictionary]) {
    $map = @{}
    foreach ($key in $Value.Keys) { $map[$key.ToString()] = ConvertTo-Hashtable $Value[$key] }
    return $map
  }
  if ($Value -is [Management.Automation.PSCustomObject]) {
    $map = @{}
    foreach ($property in $Value.PSObject.Properties) { $map[$property.Name] = ConvertTo-Hashtable $property.Value }
    return $map
  }
  if ($Value -is [Collections.IEnumerable] -and -not ($Value -is [string])) {
    $items = @($Value | ForEach-Object { ConvertTo-Hashtable $_ })
    return ,$items
  }
  return $Value
}

function Read-Json([string]$Path) {
  return ConvertTo-Hashtable ((Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json)
}

function Write-Json([string]$Path, $Value) {
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $text = ($Value | ConvertTo-Json -Depth 100) + "`n"
  [IO.File]::WriteAllText($Path, $text, (New-Object Text.UTF8Encoding($false)))
}

function Normalize-Id($Value) {
  if ($null -eq $Value) { return "" }
  $text = $Value.ToString().Trim().ToLowerInvariant() -replace '[^a-z0-9_]+', '_'
  return $text.Trim('_')
}

function Test-Version([string]$Value) { return $Value -match '^\d+\.\d+\.\d+$' }

function Version-Key([string]$Value) {
  if (-not (Test-Version $Value)) { return @(0, 0, 0) }
  return @($Value.Split('.') | ForEach-Object { [int]$_ })
}

function Compare-Version([string]$Left, [string]$Right) {
  $a = Version-Key $Left; $b = Version-Key $Right
  for ($i = 0; $i -lt 3; $i++) {
    if ($a[$i] -lt $b[$i]) { return -1 }
    if ($a[$i] -gt $b[$i]) { return 1 }
  }
  return 0
}

function Increment-Version([string]$Value) {
  if (-not (Test-Version $Value)) { return "1.0.0" }
  $parts = Version-Key $Value
  return "{0}.{1}.{2}" -f $parts[0], $parts[1], ($parts[2] + 1)
}

function Select-Row([string]$Title, [object[]]$Rows) {
  if (-not $Rows -or $Rows.Count -eq 0) { throw "No choices are available for $($Title.ToLowerInvariant())." }
  Write-Host ""
  Write-Host $Title -ForegroundColor Cyan
  for ($i = 0; $i -lt $Rows.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $Rows[$i].Label) }
  Write-Host "  0. Cancel"
  $choice = Read-Host "Choice"
  if ([string]::IsNullOrWhiteSpace($choice) -or $choice -eq "0") { throw [OperationCanceledException]::new("Cancelled") }
  $number = 0
  if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $Rows.Count) { throw "Invalid selection." }
  return $Rows[$number - 1].Value
}

function Confirm-Exact([string]$Message, [string]$Expected) {
  Write-Host ""
  Write-Host $Message -ForegroundColor Yellow
  $value = Read-Host "Type $Expected to continue"
  if ($value -cne $Expected) { throw [OperationCanceledException]::new("Cancelled") }
}

function Short-Value($Value, [int]$Maximum = 42) {
  $text = if ($Value -is [array]) { @($Value) -join ", " } else { [string]$Value }
  $text = $text.Replace("`r", " ").Replace("`n", " ").Trim()
  if (-not $text) { return "<empty>" }
  if ($text.Length -le $Maximum) { return $text }
  return $text.Substring(0, [Math]::Max(1, $Maximum - 3)) + "..."
}

function Read-OnlineText([string]$Label, $Current, [switch]$Required) {
  Write-Host ""
  Write-Host ("Current {0}: {1}" -f $Label.ToLowerInvariant(), (Short-Value $Current 90)) -ForegroundColor DarkGray
  $value = Read-Host "$Label (blank keeps current; type <clear> to clear)"
  if ([string]::IsNullOrWhiteSpace($value)) { return [string]$Current }
  if ($value -eq "<clear>") {
    if ($Required) { throw "$Label cannot be empty." }
    return ""
  }
  return $value.Trim()
}

function Read-OnlineList([string]$Label, $Current, [switch]$Required) {
  $existing = @($Current | ForEach-Object { $_.ToString() })
  Write-Host ""
  Write-Host ("Current {0}: {1}" -f $Label.ToLowerInvariant(), (Short-Value $existing 90)) -ForegroundColor DarkGray
  $value = Read-Host "$Label, comma-separated (blank keeps current; type <clear> to clear)"
  if ([string]::IsNullOrWhiteSpace($value)) { return ,$existing }
  if ($value -eq "<clear>") {
    if ($Required) { throw "$Label cannot be empty." }
    return ,@()
  }
  $items = @($value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  if ($Required -and $items.Count -eq 0) { throw "$Label cannot be empty." }
  return ,$items
}

function Get-Index {
  $result = Invoke-Gh @("api", "repos/$Repository/contents/index.json?ref=$Branch") "Fetching index.json"
  $response = ConvertTo-Hashtable ($result.Output | ConvertFrom-Json)
  $bytes = [Convert]::FromBase64String(($response.content -replace '\s', ''))
  $text = [Text.Encoding]::UTF8.GetString($bytes)
  $data = ConvertTo-Hashtable ($text | ConvertFrom-Json)
  if ($data -is [array]) { $data = @{ version = 1; mods = @($data); profiles = @() } }
  if (-not $data.ContainsKey("mods")) { $data.mods = @() }
  if (-not $data.ContainsKey("profiles")) { $data.profiles = @() }
  return @{ Data = $data; Sha = $response.sha }
}

function Put-Index($Data, [string]$Sha, [string]$Message) {
  $content = ($Data | ConvertTo-Json -Depth 100) + "`n"
  $request = @{ message = $Message; content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content)); branch = $Branch }
  if ($Sha) { $request.sha = $Sha }
  $requestPath = Join-Path $TempRoot "index-request.json"
  Write-Json $requestPath $request
  Invoke-Gh @("api", "--method", "PUT", "repos/$Repository/contents/index.json", "--input", $requestPath) "Updating index.json" | Out-Null
}

function Update-Index([scriptblock]$Mutation, [string]$Message) {
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $snapshot = Get-Index
    $updated = & $Mutation $snapshot.Data
    try {
      Put-Index $updated $snapshot.Sha $Message
      return $updated
    } catch {
      if ($attempt -ge 3 -or $_.Exception.Message -notmatch '409|422') { throw }
      Start-Sleep -Seconds $attempt
    }
  }
}

function Get-Release([string]$Tag) {
  $result = Invoke-Gh @("release", "view", $Tag, "--repo", $Repository, "--json", "tagName,name,body,url,isImmutable,assets") "Checking release" -AllowFailure
  if ($result.ExitCode -ne 0) {
    $result = Invoke-Gh @("release", "view", $Tag, "--repo", $Repository, "--json", "tagName,name,body,url,assets") "Checking release" -AllowFailure
  }
  if ($result.ExitCode -ne 0) { return $null }
  return ConvertTo-Hashtable ($result.Output | ConvertFrom-Json)
}

function Get-LocalSources([string]$ContentKind) {
  $sources = @()
  if ($ContentKind -eq "profile") {
    $root = Join-Path $GameRoot "Mods\Reloaded\Profiles"
    if (Test-Path -LiteralPath $root) {
      Get-ChildItem -LiteralPath $root -File -Filter *.json | Sort-Object Name | ForEach-Object {
        $data = Read-Json $_.FullName
        $id = Normalize-Id $(if ($data.id) { $data.id } else { $data.name })
        $sources += @{ Path = $_.FullName; Data = $data; Id = $id; Name = $data.name }
      }
    }
    return $sources
  }
  foreach ($rootName in @("Mods", "ModDev")) {
    $root = Join-Path $GameRoot $rootName
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name | ForEach-Object {
      if ($_.Name -eq "Tools") { return }
      $manifestPath = Join-Path $_.FullName "mod.json"
      if (Test-Path -LiteralPath $manifestPath) {
        $data = Read-Json $manifestPath
        $sources += @{ Path = $_.FullName; Data = $data; Id = (Normalize-Id $data.id); Name = $data.name; Root = $rootName }
      }
    }
  }
  return $sources
}

function Get-SourceLabel($Source) {
  $label = ("{0} {1}" -f $Source.Name, $Source.Data.version).Trim()
  if ([string]::IsNullOrWhiteSpace($Source.Root)) { return $label }
  $location = if ($Source.Root -eq "ModDev") { "ModDev" } else { "Installed" }
  return "[$location] $label"
}

function Get-OnlineEntryLabel($Entry) {
  $name = if ($Entry.name) { $Entry.name.ToString() } else { $Entry.id.ToString() }
  $version = if ($Entry.latest_version) { $Entry.latest_version.ToString() } else { $Entry.version.ToString() }
  return ("{0} {1}" -f $name, $version).Trim()
}

function Validate-Source($Source, [string]$ContentKind) {
  if ($Source.Id -notmatch '^[a-z0-9_]+$') { throw "The content id must use lowercase letters, numbers, and underscores." }
  if ([string]::IsNullOrWhiteSpace($Source.Data.name)) { throw "A display name is required." }
  if ($ContentKind -eq "profile") {
    foreach ($field in @("enabled_mods", "disabled_mods", "load_order")) {
      if ($null -ne $Source.Data[$field] -and -not ($Source.Data[$field] -is [array])) { throw "Profile field $field must be a list." }
    }
    return
  }
  if (-not (Test-Version $Source.Data.version)) { throw "The mod version must use Major.Minor.Patch." }
  if (-not ($Source.Data.authors -is [array]) -or $Source.Data.authors.Count -eq 0) { throw "The mod manifest needs at least one author." }
  if ($null -ne $Source.Data.dependencies -and -not ($Source.Data.dependencies -is [array])) { throw "The mod dependencies field must be a list." }
  $seen = @{}
  [long]$total = 0
  Get-ChildItem -LiteralPath $Source.Path -Recurse -File -Force | ForEach-Object {
    if ($BlockedExtensions -contains $_.Extension.ToLowerInvariant()) { throw "Blocked file type: $($_.FullName.Substring($Source.Path.Length + 1))" }
    $relative = $_.FullName.Substring($Source.Path.Length + 1).Replace('\', '/').ToLowerInvariant()
    if ($seen.ContainsKey($relative)) { throw "Case-colliding package path: $relative" }
    $seen[$relative] = $true
    $total += $_.Length
  }
  if ($total -gt $MaxPackageBytes) { throw "The package exceeds the 1 GiB mod-package limit." }
}

function Get-ProfileMods($Profile) {
  $manifests = @{}
  foreach ($source in (Get-LocalSources "mod")) { $manifests[$source.Id] = $source.Data }
  $ids = @()
  foreach ($field in @("enabled_mods", "disabled_mods", "load_order")) { $ids += @($Profile[$field]) }
  if ($Profile.mod_settings -is [hashtable]) { $ids += @($Profile.mod_settings.Keys) }
  $rows = @()
  foreach ($id in @($ids | ForEach-Object { Normalize-Id $_ } | Where-Object { $_ } | Sort-Object -Unique)) {
    if (-not $manifests.ContainsKey($id)) { throw "Profile references a missing local mod: $id" }
    $rows += @{ id = $id; version = $manifests[$id].version.ToString() }
  }
  if ($rows.Count -eq 0) { throw "A published profile must reference at least one mod." }
  return $rows
}

function Get-ReloadedVersion {
  $path = Join-Path $GameRoot "Reloaded\Version.md"
  if (-not (Test-Path -LiteralPath $path)) { return "" }
  return (Get-Content -LiteralPath $path -Raw).Trim()
}

function Get-Owned($Entry) {
  $publisher = $Entry.publisher_login.ToString().Trim().ToLowerInvariant()
  return $Login.ToLowerInvariant() -eq $RepoOwner -or ($publisher -and $publisher -eq $Login.ToLowerInvariant())
}

function Assert-Owned($Entry) {
  if (Get-Owned $Entry) { return }
  if ([string]::IsNullOrWhiteSpace($Entry.publisher_login)) { throw "This legacy entry has no publisher owner. The repository owner must migrate it." }
  throw "Only @$($Entry.publisher_login) or the repository owner can change this entry."
}

function Get-DependencyWarnings($Index, [string]$ContentId) {
  $wanted = Normalize-Id $ContentId
  $warnings = @()
  foreach ($mod in @($Index.mods)) {
    $ids = @($mod.dependencies | ForEach-Object { if ($_ -is [hashtable]) { Normalize-Id $_.id } else { Normalize-Id $_ } })
    if ($ids -contains $wanted) { $warnings += "Mod: $(if ($mod.name) { $mod.name } else { $mod.id })" }
  }
  foreach ($profile in @($Index.profiles)) {
    $ids = @($profile.mods | ForEach-Object { if ($_ -is [hashtable]) { Normalize-Id $_.id } else { Normalize-Id $_ } })
    if ($ids -contains $wanted) { $warnings += "Profile: $(if ($profile.name) { $profile.name } else { $profile.id })" }
  }
  return $warnings
}

function Build-Asset($Source, $Metadata) {
  if ($Kind -eq "profile") {
    $asset = Join-Path $TempRoot ("{0}-{1}.json" -f $Metadata.id, $Metadata.version)
    $payload = @{ format = "RLD-code"; version = 1; preset_name = $Metadata.name; reloaded_version = $Metadata.reloaded_version; profile = $Source.Data; mods = $Metadata.mods }
    Write-Json $asset $payload
    return $asset
  }
  $asset = Join-Path $TempRoot ("{0}-{1}.zip" -f $Metadata.id, $Metadata.version)
  $sevenZip = Join-Path $GameRoot "REQUIRED_BY_INSTALLER_UPDATER\7z.exe"
  if (Test-Path -LiteralPath $sevenZip) {
    $parent = Split-Path -Parent $Source.Path
    $leaf = Split-Path -Leaf $Source.Path
    $sevenZipArguments = @("a", "-tzip", "-mx=6", $asset, $leaf)
    $sevenZipArgumentLine = ($sevenZipArguments | ForEach-Object { Quote-ProcessArgument $_ }) -join " "
    $process = Start-Process -FilePath $sevenZip -ArgumentList $sevenZipArgumentLine -WorkingDirectory $parent -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "7-Zip could not create the package." }
  } else {
    Compress-Archive -LiteralPath $Source.Path -DestinationPath $asset -CompressionLevel Optimal
  }
  return $asset
}

function Get-Sha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Build-VersionRecord($Metadata) {
  $url = "https://github.com/$Repository/releases/download/$($Metadata.tag)/$($Metadata.asset_name)"
  $record = @{ version = $Metadata.version; sha256 = $Metadata.sha256; size = $Metadata.size; reloaded_version = $Metadata.reloaded_version }
  if ($Kind -eq "mod") {
    $record.download_url = $url
    $record.dependencies = @($Metadata.dependencies)
    $record.changelogurl = [string]$Metadata.source.Data.changelogurl
  } else {
    $record.profile_url = $url
    $record.mods = @($Metadata.mods)
  }
  return $record
}

function Build-Entry($Metadata, $Existing = $null) {
  $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  $versions = @()
  if ($Existing) { $versions = @($Existing.versions | Where-Object { $_.version.ToString() -ne $Metadata.version }) }
  $versions += Build-VersionRecord $Metadata
  $versions = @($versions | Sort-Object -Property @{ Expression = { (Version-Key $_.version)[0] }; Descending = $true }, @{ Expression = { (Version-Key $_.version)[1] }; Descending = $true }, @{ Expression = { (Version-Key $_.version)[2] }; Descending = $true })
  $latest = $versions[0]
  $entry = if ($Existing) { ConvertTo-Hashtable $Existing } else { @{} }
  $entry.id = $Metadata.id; $entry.name = $Metadata.name; $entry.version = $latest.version; $entry.latest_version = $latest.version
  $entry.authors = @($Metadata.authors); $entry.description = $Metadata.description; $entry.tags = @($Metadata.tags)
  $entry.publisher_login = if ($Existing -and $Existing.publisher_login) { $Existing.publisher_login } else { $Login }
  $entry.release_url = $Metadata.release_url
  $entry.published_at = if ($Existing -and $Existing.published_at) { $Existing.published_at } else { $now }
  $entry.updated_at = $now; $entry.versions = $versions
  if ($Kind -eq "mod") {
    $entry.dependencies = @($Metadata.dependencies); $entry.download_url = $latest.download_url
    $entry.sha256 = $latest.sha256; $entry.size = $latest.size; $entry.changelogurl = [string]$Metadata.source.Data.changelogurl
  } else {
    $entry.profile_url = $latest.profile_url; $entry.mods = @($latest.mods); $entry.sha256 = $latest.sha256
    $entry.size = $latest.size; $entry.reloaded_version = $latest.reloaded_version
  }
  return $entry
}

function Write-ReleaseBody($Metadata, [string]$Path) {
  $authors = (@($Metadata.authors) -join ", ")
  if (-not $authors) { $authors = $Login }
  $publisher = [string]$Metadata.publisher_login
  if (-not $publisher) { $publisher = $Login }
  $body = @($Metadata.description.Trim(), "", "Authors: $authors", "Latest Version: $($Metadata.version)", "Publisher: @$publisher", "Minimum Reloaded: $($Metadata.reloaded_version)") -join "`n"
  [IO.File]::WriteAllText($Path, $body.Trim() + "`n", (New-Object Text.UTF8Encoding($false)))
}

function Prepare-Metadata($Source, $Index) {
  Validate-Source $Source $Kind
  $existing = @($Index[$Collection] | Where-Object { (Normalize-Id $_.id) -eq $Source.Id } | Select-Object -First 1)
  $existing = if ($existing.Count) { $existing[0] } else { $null }
  if ($existing) { Assert-Owned $existing }
  if ($Kind -eq "mod") {
    $version = [string]$Source.Data.version; $authors = @($Source.Data.authors); $description = [string]$Source.Data.description
    $tags = @($Source.Data.tags); $dependencies = @($Source.Data.dependencies); $mods = @()
  } else {
    $defaultVersion = if ($existing) { Increment-Version $(if ($existing.latest_version) { $existing.latest_version } else { $existing.version }) } else { "1.0.0" }
    $version = (Read-Host "Version [$defaultVersion]").Trim(); if (-not $version) { $version = $defaultVersion }
    if (-not (Test-Version $version)) { throw "Version must use Major.Minor.Patch." }
    $authors = if ($existing -and $existing.authors) { @($existing.authors) } else { @($Login) }
    $description = [string]$Source.Data.notes; if (-not $description) { $description = "Hoenn Reloaded profile $($Source.Data.name)." }
    $tags = @("Profile"); $dependencies = @(); $mods = @(Get-ProfileMods $Source.Data)
  }
  if ($existing -and (Compare-Version $version $(if ($existing.latest_version) { $existing.latest_version } else { $existing.version })) -lt 0) {
    Confirm-Exact "This version is older than the published latest version." "ALLOW OLDER $($Source.Id) $version"
  }
  return @{
    id = $Source.Id; name = $Source.Data.name.ToString(); version = $version; authors = $authors; description = $description
    tags = $tags; dependencies = $dependencies; mods = $mods; source = $Source; old = $existing
    tag = "$Kind-$($Source.Id)"; release_url = "https://github.com/$Repository/releases/tag/$Kind-$($Source.Id)"
    reloaded_version = Get-ReloadedVersion
    publisher_login = $(if ($existing -and $existing.publisher_login) { [string]$existing.publisher_login } else { $Login })
  }
}

function Select-Source($Index) {
  $sources = @(Get-LocalSources $Kind)
  $rows = @($sources | ForEach-Object { @{ Label = (Get-SourceLabel $_); Value = $_ } })
  return Select-Row "Choose a $Kind to publish" $rows
}

function Select-OwnedOnlineEntry($Index) {
  $entries = @($Index[$Collection] | Where-Object { Get-Owned $_ })
  $rows = @($entries | Sort-Object @{ Expression = { $_.name.ToString().ToLowerInvariant() } }, @{ Expression = { $_.id.ToString() } } | ForEach-Object {
    @{ Label = (Get-OnlineEntryLabel $_); Value = $_ }
  })
  return Select-Row "Choose an owned online $Kind" $rows
}

function Edit-OnlineListingFields($Entry) {
  $working = ConvertTo-Hashtable (($Entry | ConvertTo-Json -Depth 100) | ConvertFrom-Json)
  while ($true) {
    $rows = @(
      @{ Label = "Name: $(Short-Value $working.name)"; Value = "name" },
      @{ Label = "Authors: $(Short-Value $working.authors)"; Value = "authors" },
      @{ Label = "Description: $(Short-Value $working.description)"; Value = "description" },
      @{ Label = "Tags: $(Short-Value $working.tags)"; Value = "tags" },
      @{ Label = "Changelog URL: $(Short-Value $working.changelogurl)"; Value = "changelogurl" },
      @{ Label = "Homepage URL: $(Short-Value $working.homepage_url)"; Value = "homepage_url" },
      @{ Label = "Save Online Listing"; Value = "save" }
    )
    $field = Select-Row "Edit online listing for $($working.name)" $rows
    switch ($field) {
      "name" { $working.name = Read-OnlineText "Name" $working.name -Required }
      "authors" { $working.authors = @(Read-OnlineList "Authors" $working.authors -Required) }
      "description" { $working.description = Read-OnlineText "Description" $working.description -Required }
      "tags" { $working.tags = @(Read-OnlineList "Tags" $working.tags) }
      "changelogurl" { $working.changelogurl = Read-OnlineText "Changelog URL" $working.changelogurl }
      "homepage_url" { $working.homepage_url = Read-OnlineText "Homepage URL" $working.homepage_url }
      "save" {
        foreach ($fieldName in @("changelogurl", "homepage_url")) {
          $url = [string]$working[$fieldName]
          if ($url -and $url -notmatch '^https?://') { throw "$fieldName must use a complete http:// or https:// URL." }
        }
        return $working
      }
    }
  }
}

function Write-OnlineReleaseBody($Entry, [string]$Path) {
  $version = [string]$(if ($Entry.latest_version) { $Entry.latest_version } else { $Entry.version })
  $record = @($Entry.versions | Where-Object { $_.version.ToString() -eq $version } | Select-Object -First 1)
  $minimum = [string]$Entry.reloaded_version
  if (-not $minimum -and $record.Count) { $minimum = [string]$record[0].reloaded_version }
  $metadata = @{
    description = [string]$Entry.description
    authors = @($Entry.authors)
    version = $version
    reloaded_version = $minimum
    publisher_login = [string]$Entry.publisher_login
  }
  Write-ReleaseBody $metadata $Path
}

function Edit-OnlineListing($Entry) {
  Assert-Owned $Entry
  $edited = Edit-OnlineListingFields $Entry
  $entryId = Normalize-Id $Entry.id
  $expected = "SAVE ONLINE $entryId"
  Confirm-Exact "This changes the public listing and release page without replacing any version assets." $expected
  $tag = "$Kind-$entryId"
  $release = Get-Release $tag
  if (-not $release) { throw "The persistent GitHub release is missing. The repository owner must repair it." }
  if ($release.isImmutable -eq $true) { throw "This GitHub release is immutable. Disable immutable releases before editing it." }
  $bodyPath = Join-Path $TempRoot "online-release-body.txt"
  Write-OnlineReleaseBody $edited $bodyPath
  $version = [string]$(if ($edited.latest_version) { $edited.latest_version } else { $edited.version })
  $title = ("{0} {1}" -f $edited.name, $version).Trim()
  $fields = @("name", "authors", "description", "tags", "changelogurl", "homepage_url")
  $changes = @{}
  foreach ($fieldName in $fields) { $changes[$fieldName] = $edited[$fieldName] }
  Invoke-Gh @("release", "edit", $tag, "--repo", $Repository, "--title", $title, "--notes-file", $bodyPath) "Updating release page" | Out-Null
  try {
    $mutation = {
      param($data)
      $position = -1
      for ($i = 0; $i -lt @($data[$Collection]).Count; $i++) {
        if ((Normalize-Id $data[$Collection][$i].id) -eq $entryId) { $position = $i; break }
      }
      if ($position -lt 0) { throw "The online index entry disappeared during the edit." }
      Assert-Owned $data[$Collection][$position]
      foreach ($fieldName in $fields) { $data[$Collection][$position][$fieldName] = $changes[$fieldName] }
      $data[$Collection][$position].updated_at = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
      return $data
    }
    Update-Index $mutation "Edit online listing for $Kind $entryId" | Out-Null
  } catch {
    $oldBody = Join-Path $TempRoot "old-online-release-body.txt"
    [IO.File]::WriteAllText($oldBody, [string]$release.body, (New-Object Text.UTF8Encoding($false)))
    Invoke-Gh @("release", "edit", $tag, "--repo", $Repository, "--title", [string]$release.name, "--notes-file", $oldBody) "Restoring release page" -AllowFailure | Out-Null
    throw
  }
  $verified = Get-Index
  $current = @($verified.Data[$Collection] | Where-Object { (Normalize-Id $_.id) -eq $entryId } | Select-Object -First 1)
  if (-not $current.Count) { throw "The edited online listing could not be verified." }
  foreach ($fieldName in $fields) {
    $actual = $current[0][$fieldName] | ConvertTo-Json -Depth 20 -Compress
    $wanted = $changes[$fieldName] | ConvertTo-Json -Depth 20 -Compress
    if ($actual -ne $wanted) { throw "The edited $fieldName field could not be verified." }
  }
  Write-Host "`n[SUCCESS] Updated the online listing for $($edited.name)." -ForegroundColor Green
}

function Publish-Content($Asset, $Metadata) {
  if (Get-Release $Metadata.tag) { throw "The stable release tag already exists but is missing from the online index. The repository owner must repair it." }
  $body = Join-Path $TempRoot "release-body.txt"; Write-ReleaseBody $Metadata $body
  Invoke-Gh @("release", "create", $Metadata.tag, $Asset, "--repo", $Repository, "--title", "$($Metadata.name) $($Metadata.version)", "--notes-file", $body) "Creating release and uploading asset" | Out-Null
  try {
    $mutation = {
      param($data)
      if (@($data[$Collection] | Where-Object { (Normalize-Id $_.id) -eq $Metadata.id }).Count) { throw "The id was published by another operation. Run Publish again." }
      $data[$Collection] = @($data[$Collection]) + @(Build-Entry $Metadata)
      return $data
    }
    Update-Index $mutation "Publish $Kind $($Metadata.id) $($Metadata.version)" | Out-Null
  } catch {
    Invoke-Gh @("release", "delete", $Metadata.tag, "--repo", $Repository, "--cleanup-tag", "--yes") "Rolling back release" -AllowFailure | Out-Null
    throw
  }
}

function Update-Content($Asset, $Metadata) {
  $release = Get-Release $Metadata.tag
  if (-not $release) { throw "The persistent GitHub release is missing. The repository owner must repair it." }
  if ($release.isImmutable -eq $true) { throw "This GitHub release is immutable. Disable immutable releases before updating it." }
  $oldVersion = @($Metadata.old.versions | Where-Object { $_.version.ToString() -eq $Metadata.version } | Select-Object -First 1)
  $backup = $null
  if ($oldVersion.Count) {
    Confirm-Exact "This version is already published and will be replaced." "REPLACE $($Metadata.id) $($Metadata.version)"
    $oldUrl = if ($oldVersion[0].download_url) { $oldVersion[0].download_url } else { $oldVersion[0].profile_url }
    $oldAsset = Split-Path -Leaf ([Uri]$oldUrl).AbsolutePath
    $backupDir = Join-Path $TempRoot "asset-backup"; New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Invoke-Gh @("release", "download", $Metadata.tag, "--repo", $Repository, "--pattern", $oldAsset, "--dir", $backupDir) "Backing up old asset" | Out-Null
    $backup = Join-Path $backupDir $oldAsset
    Invoke-Gh @("release", "delete-asset", $Metadata.tag, $oldAsset, "--repo", $Repository, "--yes") "Removing old asset" | Out-Null
  }
  Invoke-Gh @("release", "upload", $Metadata.tag, $Asset, "--repo", $Repository) "Uploading version asset" | Out-Null
  $body = Join-Path $TempRoot "release-body.txt"; Write-ReleaseBody $Metadata $body
  Invoke-Gh @("release", "edit", $Metadata.tag, "--repo", $Repository, "--title", "$($Metadata.name) $($Metadata.version)", "--notes-file", $body) "Updating release details" | Out-Null
  try {
    $mutation = {
      param($data)
      $position = -1
      for ($i = 0; $i -lt @($data[$Collection]).Count; $i++) { if ((Normalize-Id $data[$Collection][$i].id) -eq $Metadata.id) { $position = $i; break } }
      if ($position -lt 0) { throw "The online index entry disappeared during the update." }
      Assert-Owned $data[$Collection][$position]
      $data[$Collection][$position] = Build-Entry $Metadata $data[$Collection][$position]
      return $data
    }
    Update-Index $mutation "Publish $Kind $($Metadata.id) $($Metadata.version)" | Out-Null
  } catch {
    Invoke-Gh @("release", "delete-asset", $Metadata.tag, $Metadata.asset_name, "--repo", $Repository, "--yes") "Rolling back asset" -AllowFailure | Out-Null
    if ($backup -and (Test-Path -LiteralPath $backup)) { Invoke-Gh @("release", "upload", $Metadata.tag, $backup, "--repo", $Repository) "Restoring old asset" -AllowFailure | Out-Null }
    throw
  }
}

function Delete-Content($Index) {
  Write-Phase 3 6 "Choosing published content"
  $entries = @($Index[$Collection] | Where-Object { Get-Owned $_ })
  $entry = Select-Row "Choose a $Kind to delete" @($entries | ForEach-Object { @{ Label = ("{0} {1}" -f $_.name, $_.latest_version); Value = $_ } })
  Assert-Owned $entry
  $versions = @($entry.versions)
  $deleteRows = @($versions | ForEach-Object { @{ Label = "Version $($_.version)"; Value = @{ Mode = "version"; Version = $_ } } })
  $deleteRows += @{ Label = "Entire entry and release"; Value = @{ Mode = "entry"; Version = $null } }
  $selection = Select-Row "Choose what to delete" $deleteRows
  $warnings = @(Get-DependencyWarnings $Index $entry.id)
  if ($warnings.Count) {
    Write-Host "`n[WARNING] This content is referenced by:" -ForegroundColor Yellow
    foreach ($warning in $warnings) { Write-Host "  - $warning" }
  }
  $expected = if ($selection.Mode -eq "entry") { $entry.id } else { "$($entry.id) $($selection.Version.version)" }
  Confirm-Exact "This permanently changes the public repository." $expected
  $remaining = if ($selection.Mode -eq "entry") { @() } else { @($versions | Where-Object { $_.version.ToString() -ne $selection.Version.version.ToString() }) }
  if ($remaining.Count -eq 0) { $selection.Mode = "entry" }
  $before = ConvertTo-Hashtable $entry
  Write-Phase 4 6 "Updating the public index"
  $mutation = {
    param($data)
    $position = -1
    for ($i = 0; $i -lt @($data[$Collection]).Count; $i++) { if ((Normalize-Id $data[$Collection][$i].id) -eq (Normalize-Id $entry.id)) { $position = $i; break } }
    if ($position -lt 0) { throw "The entry is no longer present in the online index." }
    Assert-Owned $data[$Collection][$position]
    if ($selection.Mode -eq "entry") { $data[$Collection] = @($data[$Collection] | Where-Object { (Normalize-Id $_.id) -ne (Normalize-Id $entry.id) }) }
    else {
      $current = $data[$Collection][$position]
      $current.versions = @($current.versions | Where-Object { $_.version.ToString() -ne $selection.Version.version.ToString() })
      $latest = @($current.versions | Sort-Object -Property @{ Expression = { (Version-Key $_.version)[0] }; Descending = $true }, @{ Expression = { (Version-Key $_.version)[1] }; Descending = $true }, @{ Expression = { (Version-Key $_.version)[2] }; Descending = $true })[0]
      $current.version = $latest.version; $current.latest_version = $latest.version; $current.updated_at = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
      if ($Kind -eq "mod") { $current.download_url = $latest.download_url } else { $current.profile_url = $latest.profile_url; $current.mods = @($latest.mods) }
      $current.sha256 = $latest.sha256; $current.size = $latest.size
      $data[$Collection][$position] = $current
    }
    return $data
  }
  Update-Index $mutation "Delete $Kind $expected" | Out-Null
  Write-Phase 5 6 "Deleting GitHub release content"
  $tag = "$Kind-$(Normalize-Id $entry.id)"
  try {
    if ($selection.Mode -eq "entry") { Invoke-Gh @("release", "delete", $tag, "--repo", $Repository, "--cleanup-tag", "--yes") "Deleting release and tag" | Out-Null }
    else {
      $url = if ($selection.Version.download_url) { $selection.Version.download_url } else { $selection.Version.profile_url }
      $assetName = Split-Path -Leaf ([Uri]$url).AbsolutePath
      Invoke-Gh @("release", "delete-asset", $tag, $assetName, "--repo", $Repository, "--yes") "Deleting release asset" | Out-Null
      $latest = @($remaining | Sort-Object -Property @{ Expression = { (Version-Key $_.version)[0] }; Descending = $true }, @{ Expression = { (Version-Key $_.version)[1] }; Descending = $true }, @{ Expression = { (Version-Key $_.version)[2] }; Descending = $true })[0]
      $body = Join-Path $TempRoot "release-body.txt"
      $releaseMetadata = @{ description = [string]$entry.description; authors = @($entry.authors); version = $latest.version; reloaded_version = [string]$latest.reloaded_version }
      Write-ReleaseBody $releaseMetadata $body
      Invoke-Gh @("release", "edit", $tag, "--repo", $Repository, "--title", "$($entry.name) $($latest.version)", "--notes-file", $body) "Updating release details" | Out-Null
    }
  } catch {
    $restore = { param($data); $data[$Collection] = @($data[$Collection] | Where-Object { (Normalize-Id $_.id) -ne (Normalize-Id $before.id) }) + @($before); return $data }
    Update-Index $restore "Restore $Kind $($entry.id) after failed delete" | Out-Null
    throw
  }
  Write-Phase 6 6 "Verifying deletion"
  $check = Get-Index
  $current = @($check.Data[$Collection] | Where-Object { (Normalize-Id $_.id) -eq (Normalize-Id $entry.id) })
  if ($selection.Mode -eq "entry" -and $current.Count) { throw "The entry still exists after deletion." }
  Write-Host "`n[SUCCESS] Deleted $expected." -ForegroundColor Green
}

try {
  New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
  if (-not (Test-Path -LiteralPath (Join-Path $GameRoot "Reloaded"))) { throw "The Hoenn Reloaded game directory is invalid." }
  if ([string]::IsNullOrWhiteSpace($Kind)) { $Kind = Select-Row "Choose content type" @(@{ Label = "Mod"; Value = "mod" }, @{ Label = "Profile"; Value = "profile" }) }
  $Kind = $Kind.ToLowerInvariant(); $Collection = if ($Kind -eq "mod") { "mods" } else { "profiles" }
  Write-Host ("=" * 60); Write-Host " Hoenn Reloaded $Action - $($Kind.Substring(0,1).ToUpper() + $Kind.Substring(1))"; Write-Host ("=" * 60)
  if ($DryRun) {
    if ($Action -eq "Update") {
      Write-Phase 1 1 "Checking the metadata-only Update workflow"
      Write-Host "[OK] Update edits owned online listings and never reads or packages local content."
      Write-Host "[SUCCESS] Dry run completed without network or repository changes." -ForegroundColor Green
      exit 0
    }
    Write-Phase 1 2 "Scanning local content"
    $sources = @(Get-LocalSources $Kind); Write-Host "[OK] Found $($sources.Count) local $Kind(s)."
    Write-Phase 2 2 "Validating local source files"
    foreach ($source in $sources) { Validate-Source $source $Kind }
    Write-Host "[SUCCESS] Dry run completed without network or repository changes." -ForegroundColor Green
    exit 0
  }
  Write-Phase 1 6 "Checking GitHub authentication"
  if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) { throw "GitHub CLI was not found. Install it, then run gh auth login." }
  try {
    $Login = (Invoke-Gh @("api", "user", "--jq", ".login") "Reading GitHub account").Output.Trim()
  } catch {
    if ($_.Exception.Message -match "401|Requires authentication|Bad credentials") {
      throw "GitHub authentication is expired or invalid. Run: gh auth login --hostname github.com --web"
    }
    throw
  }
  if (-not $Login) { throw "GitHub authentication did not return a user name." }
  Write-Host "[OK] Authenticated as $Login"
  Write-Phase 2 6 "Reading the online index"
  $snapshot = Get-Index; $index = $snapshot.Data
  if ($Action -eq "Delete") { Delete-Content $index; exit 0 }
  if ($Action -eq "Update") {
    $onlineEntry = Select-OwnedOnlineEntry $index
    Edit-OnlineListing $onlineEntry
    exit 0
  }
  $source = Select-Source $index
  Write-Phase 3 6 "Validating local content"
  $metadata = Prepare-Metadata $source $index
  Write-Host "[OK] $($metadata.name) $($metadata.version) passed validation"
  Write-Phase 4 6 "Building the release asset"
  $asset = Build-Asset $source $metadata
  $metadata.asset_name = Split-Path -Leaf $asset; $metadata.size = (Get-Item -LiteralPath $asset).Length; $metadata.sha256 = Get-Sha256 $asset
  Write-Bar 1 1 "$($metadata.asset_name) ($($metadata.size) bytes)"
  Write-Phase 5 6 "Publishing to GitHub"
  if ($metadata.old) { Update-Content $asset $metadata } else { Publish-Content $asset $metadata }
  Write-Phase 6 6 "Verifying the published entry"
  $verified = Get-Index
  $entry = @($verified.Data[$Collection] | Where-Object { (Normalize-Id $_.id) -eq $metadata.id } | Select-Object -First 1)
  if (-not $entry.Count -or -not @($entry[0].versions | Where-Object { $_.version -eq $metadata.version -and [long]$_.size -eq [long]$metadata.size -and $_.sha256 -eq $metadata.sha256 }).Count) { throw "The online version metadata did not match the uploaded asset." }
  $release = Get-Release $metadata.tag
  $remoteAsset = @($release.assets | Where-Object { $_.name -eq $metadata.asset_name } | Select-Object -First 1)
  if (-not $release -or -not $remoteAsset.Count -or [long]$remoteAsset[0].size -ne [long]$metadata.size) { throw "The uploaded GitHub release asset size could not be verified." }
  Write-Host "[OK] Index entry, checksum, release asset, and remote size are present."
  Write-Host "`n[SUCCESS] $($metadata.name) $($metadata.version) is published." -ForegroundColor Green
  exit 0
} catch [OperationCanceledException] {
  Write-Host "`n[CANCELLED] No further changes were made." -ForegroundColor Yellow
  exit 2
} catch {
  $message = $_.Exception.Message.Replace($GameRoot, "<Game>").Replace($TempRoot, "<Temp>")
  Write-Host "`n[FAILED] $message" -ForegroundColor Red
  exit 1
} finally {
  if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
