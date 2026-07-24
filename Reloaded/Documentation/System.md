#======================================================
# Reloaded System Documentation
# Author: Stonewall
#======================================================
# Combined reference for the Hoenn Reloaded foundation, settings, save bucket,
# and options framework.
#
# Responsibilities:
#   - Summarize the framework systems currently in place.
#   - Document global settings and save data APIs.
#   - Document the consolidated Options menu and reusable option row types.
#   - Keep broad system documentation in one file instead of several small
#     files.
#
#======================================================

## Foundation Status

Hoenn Reloaded currently has these framework systems in place:

- Bootstrap loader through one documented vanilla hook, with readiness/failure
  tracking and required-system isolation.
- Explicit built-in runtime manifest at `Reloaded/LoadOrder.rb`; Bootstrap
  loads its Core phases before booting framework systems, then loads Modules.
- Runtime window title sync from `Reloaded/Version.md`.
- Central settings file at `Reloaded/Settings.txt`.
- Central logging with modes, reports, bug-report export, and path sanitizing.
- Event API through `Reloaded::Events`.
- Event contracts, handler requirements, and repeated-failure isolation.
- Shared reward registration, validation, atomic grants, and rollback through
  `Reloaded::Rewards`.
- `Reloaded::Hooks` compatibility alias.
- Patch/conflict registry through `Reloaded::Patches`.
- Reloaded save bucket through `Reloaded::SaveData`.
- Sequential save migrations, schema write protection, and rolling backups.
- Central version, API contract, system registry, and feature flag APIs.
- Shared runtime/developer validation with failure-safe reports.
- Runtime asset resolver for active mod assets.
- Lazy per-head Spritepack resolver with separate Base and Expanded
  components, loose/mod asset priority, and one-file cache extraction.
- Shared platform detection and desktop adapters for Windows, Proton, and
  restricted JoiPlay behavior.
- Shared AIO Installer contract with a Public/Testing channel choice, mandatory
  Core plus the latest Full Spritepack, direct Windows/Proton installation,
  progress reporting, and no player-side Git cache.
- Shared streaming large-file downloads through `Reloaded::Download`, with
  atomic `.part` promotion, cancellation, limits, and optional SHA-256 checks.
- Shared safe ZIP/RAR/7Z inspection and extraction through
  `Reloaded::Archive`, including traversal protection and bounded limits.
- Shared validated text/JSON retrieval with last-known-good caches and local
  fallbacks through `Reloaded::RemoteData`.
- Conservative boot cleanup for abandoned Reloaded downloads, extraction
  folders, publishing payloads, temporary scripts, and old unregistered
Remote Data caches, and disposable packed-sprite cache files.
- Shared background tasks with cooperative cancellation, structured outcomes,
  main-thread callbacks, and input-safe Toast delivery through `Reloaded::Task`.
- Shared HR-style determinate and indeterminate task progress through
  `Reloaded::ProgressWindow` for explicit user-started operations.
- Mod scanning, validation, dependency-safe load ordering, and script loading.
- Runtime data patch collector and JSON-style data registry in the `008` core
  range.
- Active item, move, ability, species, trainer, trainer type, encounter, and
  outfit data patch targets.
- Runtime core fixes in `Reloaded/Core/Compatibility/CoreFixes.rb`.
- Script-facing Ability API.
- Profile system stored in `Mods/Reloaded/Profiles/`.
- Profile code export/import using `RLD-code-`.
- Per-mod settings API and Options-style settings UI.
- Public popup window API for Reloaded-styled mod and system popups.
- In-game Mod Manager with installed mods, profiles, browser, tools, and admin
  entry points.
- Mod Browser using the GitHub index for mods and published profiles.
- Consolidated Options menu with collapsible categories.

Current player-facing entry points:

```text
Options -> Visuals & UI -> Reloaded UI
Options -> Gameplay -> PokeVial
Options -> Gameplay -> TM Vault
Options -> Gameplay -> PC Module
Options -> Economy -> Reloaded Mart
Options -> Challenge -> IV Boundaries
Options -> Mods -> Mod Manager
Options -> Mods -> Mod Settings
Options -> Mods -> ModDev
Options -> Developer -> Admin Tools
Options -> Developer -> Foundation Inspector
Options -> Developer -> Logging Mode
Options -> About -> Discord Link
Options -> File A Bug Report
```

Mods belong in:

```text
Mods/<mod folder>/
ModDev/<mod folder>/
```

Player-facing Mod Manager tools are shipped under:

```text
ModDev/Tools/Windows/
ModDev/Tools/Proton/
```

Windows uses batch/PowerShell launchers. Proton uses shell/Python launchers.
Both require GitHub CLI authentication, update GitHub through its API without a
local repository checkout, and remove temporary package files after each run.
Private maintainer checks remain under `ModDev/Foundation Checks/Windows/` and
`ModDev/Foundation Checks/Proton/`; those folders are not shipped. JoiPlay hides external
publishing and archive tools.

## AIO Installer

The player installer is one logical system with platform-specific frontends:

```text
Hoenn Reloaded Installer.bat
Hoenn Reloaded Installer.ps1
Hoenn Reloaded Installer.sh
Hoenn Reloaded Installer.py
```

Windows uses the batch/PowerShell frontend. Proton uses the shell/Python
frontend. Both install into the directory containing the installer and offer:

```text
Hoenn Reloaded
Hoenn Reloaded Testing
```

After the channel is selected, the installer always installs Core and the
latest Full Spritepack. The artifacts remain independently versioned so an
unchanged Full Spritepack is retained without another download.

Public Core reads `Reloaded/InstallerManifest.json` from
`Stonewallxx/Hoenn-Reloaded` and downloads the versioned release archive with
size and SHA-256 verification. Testing Core directly downloads the current
`main` repository snapshot from `Stonewallxx/Hoenn-Reloaded-Testing`; Testing
does not require or publish a GitHub release.

Full Spritepacks are shared by both channels through the public
`Reloaded/Spritepacks.json` catalog. Oversized Full Spritepacks use an ordered
`parts` list. Every part has its own size and SHA-256, while extraction treats
the verified parts as one logical ZIP without creating another full-size copy.
Downloads use resumable `.part` files under
`REQUIRED_BY_INSTALLER_UPDATER/Cache` on the game drive and remove that cache
after a successful installation. Files of at least 24 MiB use six simultaneous
HTTP range connections when supported. Each connection writes directly to its
assigned offset in one preallocated `.part` file. A `.part.meta.json` sidecar
records each completed range plus the source ETag or Last-Modified value so
interrupted downloads can resume without separate segment files. A server that
rejects range requests automatically falls back to the resumable
single-connection path.

Before downloading or extracting, the installer checks available space on the
target drive with a safety margin. Network and rate-limit failures retry with
exponential backoff, jitter, and `Retry-After` support. Schema 3 manifests can
offer a newer Windows/Proton bootstrap; it is downloaded and SHA-256 verified
before the newer installer restarts itself. Release signing keys are not used.

Core and Full Spritepack packages are versioned independently. Routine Core
updates therefore do not redownload an unchanged Full Spritepack. Monthly
Spritepack overlays remain managed separately through the Mod Manager.

`Reloaded/InstallerFiles.json` is generated into Core releases. During an
update, the installer compares the previous and new managed inventories and
removes only obsolete files that were owned by the previous release. Saves,
mods, settings, profiles, imported sprites, installed Spritepacks, unknown
files, and local Git metadata are always protected.

Immediately before either desktop installer begins changing live Core or
Spritepack files, it atomically writes
`Reloaded/InstallerIncomplete.json`. The marker records the channel, requested
package, target version, current phase, timestamps, and Spritepack build ID when
applicable. It is removed only after installed manifests are verified and
obsolete managed files are finalized.

If installation is interrupted, the next Windows or Proton installer launch
reuses the marker's original channel and package choice and forces Repair mode.
Verified Public Core and Spritepack downloads remain in the installer cache for
reuse; Testing snapshots are refreshed from GitHub. Starting the game while
this marker exists shows a repair message and closes before Reloaded modules
load, preventing a partially updated Core from running. The marker is ignored
by Git, protected from package contents, and never included in a Core
release. The Proton installer writes every live file through a same-directory
`.installing` file before atomic replacement. The Windows installer does the
same for Testing files and atomically promotes the small startup-critical file
set after the rest of a Public Core archive has extracted.

Public Core package generation and publishing live under:

```text
Admin Tools/Core Builder/
Admin Tools/Core Publisher/
```

The Core Builder creates the Public Core ZIP, the reusable Windows/Proton
installer bootstrap, checksums, and a release manifest. The Core Publisher
uploads those archives to the versioned public release, verifies the remote
assets, and publishes `Reloaded/InstallerManifest.json` last. Neither tool is
used for Testing or Spritepacks.

Full Spritepack release preparation and publishing live under:

```text
Admin Tools/Spritepack Publisher/
```

That publisher owns splitting, verification, upload, and the public
`Reloaded/Spritepacks.json` update. It does not run the Core Builder.

The JoiPlay builder assembles the verified Public Core Builder output and the
latest Full Spritepack into a complete ready-to-release ZIP. Testing JoiPlay
packages are not produced.

Platform API:

```ruby
Reloaded::Platform.id
Reloaded::Platform.detected_id
Reloaded::Platform.label
Reloaded::Platform.supports?(:browser_downloads)
Reloaded::Platform.supports?(:downloads)
Reloaded::Platform.supports?(:remote_data)
Reloaded::Platform.supports?(:background_tasks)
Reloaded::Platform.supports?(:external_tools)
Reloaded::Platform.capabilities
Reloaded::Platform.open_url(url)
Reloaded::Platform.temporary_directory
Reloaded::Platform.user_data_directory
```

`Reloaded::Platform` is the low-level operating-system adapter. Runtime and mod
code should use `Reloaded::FileActions` for game-local files, folders,
clipboard actions, and text/log exports so path boundaries and sanitization are
applied consistently.

Large runtime downloads must use `Reloaded::Download`, not scene-local HTTP,
PowerShell, or engine download helpers. The shared API confines destinations,
streams into `.part` files, validates expected size and optional SHA-256
metadata, reports progress, supports cooperative cancellation, and preserves
the previous destination on failure. Eligible files use up to three native
byte-range connections, then fall back to one connection if ranges are not
supported. The limit is process-wide, so simultaneous tasks cannot each create
three additional connections. Resumable multipart downloads write directly to
one preallocated `.part` file and persist per-range progress, source validators,
and expected boundaries in `.part.meta.json`. A partial file is preserved only
for interrupted network/transport failures; invalid sizes, source changes, and
checksums discard it.

Runtime archive extraction must use `Reloaded::Archive`, not direct 7-Zip or
shell commands. The shared API applies entry/path validation, extraction limits,
progress reporting, sanitized errors, and the Windows/Proton adapter before any
files are written. Numbered `.zip.001`, `.rar.001`, and `.7z.001` volumes are
validated and extracted as one logical archive. JoiPlay keeps archive
extraction unavailable.

`Reloaded::TempCleanup` runs after Modules have registered their Remote Data
sources. It removes only recognized Reloaded-owned temporary names after 24
hours. Unregistered default Remote Data caches are eligible after 90 days, or
oldest-first if that cache directory exceeds 64 MB. Every cache registered for
the current session is protected regardless of age or size. The cleanup does
not scan installed mods, imported Spritepacks, local fallback files, save data,
or any other installed game content. Unknown files are left untouched.
Packed sprite PNGs under `Reloaded/Cache/SpritePacks` are disposable runtime
materializations, not installed content. Files unused for 30 days are removed,
and the oldest files are pruned if that cache exceeds 2 GB. The source `.pak`
files under `Graphics/SpritePacks` are never removed by cleanup.

Packed sprites use AFI-compatible SPAK v2 files, split by head ID:

```text
Graphics/SpritePacks/Base/Custom/<head>.pak
Graphics/SpritePacks/Base/Base/<head>.pak
Graphics/SpritePacks/Expanded/Custom/<head>.pak
Graphics/SpritePacks/Expanded/Base/<head>.pak
Graphics/SpritePacks/Expanded/Autogen/<head>.pak
Graphics/SpritePacks/Updates/<update-id>/Base/<type>/<head>.pak
Graphics/SpritePacks/Updates/<update-id>/Expanded/<type>/<head>.pak
```

Resolution order is active mod/loose file, monthly updates newest-first, Full
Base, Full Expanded, then the existing spritesheet/download fallback. Only the
requested PNG is copied to the cache. Hoenn Reloaded never expands an entire
head pack during gameplay. A Full manifest can mark the cutoff through which
monthly updates were compacted; those older layers are ignored.
Monthly manifests may also tombstone removed per-head packs so lower layers do
not restore content that was intentionally removed.
Packed alternate indexes are also exposed to the normal sprite-choice flow.
When a legacy spritesheet is absent, the installed pack becomes authoritative
for Pokédex sprite choices and unavailable saved variants are repaired to an
available packed variant when they are next rendered.

`Reloaded::SpritePacks.verify_component(:base)`,
`verify_component(:expanded)`, and `verify_update(update_id)` explicitly
verify manifests, file sizes, SHA-256 checksums, pack structure, and missing
files. Verification is not run during every boot because Full components can
be several gigabytes.

Expanded species data is compiled separately from sprite assets under
`Reloaded/Data/ExpandedDex`. The compact GameData bundle loads before its
battle handlers, while `ExpandedDexIDs.json` permanently reconciles retained
source species numbers with runtime IDs used by the Full Spritepack.

Player-provided PNGs belong in:

```text
Graphics/CustomBattlers/Sprite Import/
```

`Reloaded::SpriteImport` scans that inbox once during startup, validates PNG
signatures and supported sprite filenames, and moves valid files into the
normal loose override folders. Loose imports remain higher priority than
packed sprites. Imports of 20 or more files use a determinate HR progress
window on Windows and Proton; platforms without background-task support use
the same batched importer synchronously. Per-file success logging is avoided.
Conflicts include both existing loose files and entries already present in a
Spritepack, and continue through the existing replace-or-skip prompt.

Systems should query capabilities instead of branching on platform names.
Unsupported actions are omitted from menus rather than displayed as disabled
rows. Windows and Proton expose the full desktop feature set. JoiPlay retains
gameplay, manually installed mods, and installed-mod/profile management while
hiding Browser downloads, background tasks, archives, updating, publishing,
and external tools.

Bootstrap status and shutdown API:

```ruby
Reloaded::Bootstrap.status
Reloaded::Bootstrap.ready?
Reloaded::Bootstrap.degraded?
Reloaded::Bootstrap.failures
Reloaded.shutdown
```

Required Core file or system failures stop initialization and leave the
bootstrap in `:failed`. Optional module and desktop-tool failures are isolated
and leave it in `:degraded` while the remaining systems continue. Shutdown
cooperatively cancels outstanding shared tasks before normal quit or updater
exit. Workers are never force-killed.

Standalone regression tools are available at:

```text
ModDev/Foundation Checks/Windows/Run Foundation Checks.bat
ModDev/Foundation Checks/Proton/Run Foundation Checks.sh
```

They validate the load manifest, Ruby syntax, event behavior, patch conflict
rebuilding, settings normalization, platform capabilities, save protection,
required public assets, documentation references, changelog structure,
generated-file tracking, ignore coverage, and release path safety without
launching the game. The two platform scripts intentionally run the same Ruby
suite so Windows and Proton enforce the same release contract.

These checks do not replace an actual game boot. Before publishing, run the
appropriate platform suite and then perform a Windows gameplay smoke test.
Proton and JoiPlay remain structurally validated until tested on their target
environments.

Recommended mod folder files:

```text
mod.json
Scripts/
Graphics/
Audio/
Settings.json
Changelog.txt
Documentation/
```

Mod authors should use:

- `Reloaded::Log` for diagnostics.
- `Reloaded::Events` for lifecycle hooks.
- `Reloaded::Patches` when changing vanilla behavior.
- `Reloaded::SaveData` for persistent save data.
- `Reloaded::ModSettings` for profile-backed mod settings.
- `Reloaded::Assets` indirectly by placing assets in the mod folder.
- `Reloaded::DataPatches` for runtime data changes.
- `Reloaded::Abilities` for custom ability behavior.
- `Reloaded::PopupWindow` for HR-style popups.
- `Reloaded::ActionMenu` for state-aware popup commands, disabled reasons, and
  callback dispatch.
- `Reloaded::TextInput` for shared HR-style text entry.
- `Reloaded::ListState` for selection, scrolling, cursor memory, disabled rows,
  standard list movement, active-only mouse input, and dialog input gating in
  custom scenes.
- `Reloaded::ListPicker` for popup and full-screen list selection.
- `Reloaded::GameDataPicker` for searchable canonical IDs from items, species,
  moves, abilities, types, maps, and trainer classes.
- `Reloaded::NumberPicker` for shared quantity and integer selection.
- `Reloaded::Form` for validated full-screen text, number, toggle, enum, list,
  GameData, and custom field editing with isolated drafts and save handling.
- `Reloaded::ProgressWindow` for modal progress and cooperative cancellation.
- `Reloaded::Download` for bounded, verifiable large-file downloads on Windows
  and Proton.
- `Reloaded::Archive` for safe ZIP, RAR, and 7Z inspection/extraction on
  Windows and Proton.
- `Reloaded::FileActions` for safe game-local file, folder, clipboard, and
  text/log export actions.
- `Reloaded::RemoteData` for validated small text/JSON sources with remote,
  cache, and local fallback handling.
- `Reloaded::Task` for non-blocking I/O with main-thread completion callbacks.
- `Reloaded::Rewards` for items, currencies, Pokemon, outfits, TM Vault moves,
  feature unlocks, choice/random groups, Mart/Mystery Gift rewards, and custom
  mod reward types.
- `Reloaded::HintText` for shared Reloaded hint text formatting.
- `Reloaded::InputBindings` for read-only labels from the game's bindings.
- `Reloaded::Toast` for short HR-style status messages.
- `Reloaded.message`, `Reloaded.confirm`, `Reloaded.choice`, and
  `Reloaded.toast` as short aliases for common popup/status calls.
- `Reloaded.text_input`, `Reloaded.multiline_input`, `Reloaded.code_input`,
  `Reloaded.url_input`, and `Reloaded.search_input` as short aliases for common
  text-entry calls.
- `Reloaded::Confirm` as a grouped namespace for the same short popup/status
  helpers.

Reloaded uses `Major.Minor.Patch` versioning in `Reloaded/Version.md`.

`Reloaded/Version.md` is the only source for the Hoenn Reloaded version, and
`Reloaded/BaseVersion.md` records the imported base Hoenn version. Read and
compare these values through `Reloaded::Versioning`:

```ruby
Reloaded::Versioning.current
Reloaded::Versioning.base
Reloaded::Versioning.valid?("1.2.3")
Reloaded::Versioning.compare("1.2.3", "1.2.0")
Reloaded::Versioning.at_least?("1.2.3", "1.0.0")
Reloaded::Versioning.requirement_met?("1.0.0")
```

The current imported base Hoenn version is read from `BaseVersion.md` rather
than duplicated in runtime code.

Base-game file edits are tracked locally in
`Reloaded/Documentation/VanillaChanges.md`. That file is ignored because it is
developer-local review metadata, not shipped documentation. Foundation Checks
validate that the base-game paths manually listed there exist; ordinary
upstream base-game updates do not need update-import folders or individual
VanillaChanges entries.

## Settings

Reloaded global settings are stored in:

```text
Reloaded/Settings.txt
```

The format is:

```text
key=value
```

Blank lines and lines starting with `#` are ignored.

Current keys:

```text
logging_mode=Developer
moddev=Off
active_profile=Default
platform_override=Auto
```

`logging_mode` accepts:

```text
Player
Developer
```

`moddev` controls whether `Reloaded::ModManager` scans `ModDev/`.

Accepted true values:

```text
On
true
1
yes
enabled
enable
```

`active_profile` controls which Mod Manager profile is loaded from:

```text
Mods/Reloaded/Profiles/
```

Profiles do not control `ModDev`; ModDev remains global.

`platform_override` is available only while Debug or ModDev is enabled. It
accepts `Auto`, `Windows`, `Proton`, or `JoiPlay` and exists for capability and
menu-visibility testing. Normal players always use automatic detection.

Settings API:

```ruby
Reloaded::Settings.get("moddev", "Off")
Reloaded::Settings.get("logging_mode", "Developer")
Reloaded::Settings.get("active_profile", "Default")
Reloaded::Settings.set("moddev", "On")
Reloaded::Settings.bool("moddev", false)
Reloaded::Settings.set_bool("moddev", true)
Reloaded::Settings.all
Reloaded::Settings.reload!
```

Use `Reloaded/Settings.txt` for global Reloaded settings that are not
save-specific.

## Logging

Reloaded logs are stored in `Reloaded/Logging/`.

Log files:

- `Log.txt` - main Reloaded framework/fork log.
- `Mods.txt` - mod-related logging and mod author output.
- `Coop.txt` - multiplayer/co-op logging.
- `Reports/` - reserved folder for future exported reports.

Log levels:

- `[DEBUG]` - developer-only diagnostic detail.
- `[INFO]` - normal status.
- `[Warning]` - minor issue; the system or mod can continue.
- `[ERROR]` - unexpected failure that was handled if possible.
- `[Critical]` - major issue; the mod/system cannot continue.
- `[FATAL]` - startup or game-critical failure.

Set `logging_mode` in `Reloaded/Settings.txt` to one of these values:

- `Player` - shorter, readable logs focused on fixes.
- `Developer` - detailed technical logging.

Code can change the mode with:

```ruby
Reloaded::Log.set_mode("Player")
Reloaded::Log.set_mode("Developer")
```

Basic use:

```ruby
Reloaded::Log.info("Boot start", :bootstrap)
Reloaded::Log.warning("Optional module missing", :framework)
Reloaded::Log.critical("Mod cannot load", :mods)
Reloaded::Log.mod("example_mod", "Loaded settings")
Reloaded::Log.coop("Session started")
```

Use once-per-boot helpers for messages that can repeat during scans, refreshes,
or validation passes:

```ruby
Reloaded::Log.warning_once(
  "Active profile references missing mod: example_mod",
  :mods,
  key: "profile_missing_mod:Default:example_mod"
)
```

Exceptions:

```ruby
Reloaded::Log.exception("Event handler failed", error, channel: :events)
```

Failure reports:

```ruby
Reloaded::Log.report(
  :type => "Mod Load Failure",
  :mod_id => "example_mod",
  :level => :critical,
  :recommended_fix => "Install the dependency or disable the mod.",
  :error => error
)
```

Reports are written inside `Log.txt` with `[REPORT]` and `[/REPORT]` tags.

Bug report export:

```ruby
Reloaded::Log.export_bug_report
```

This writes `Reloaded/Logging/LatestBugReport.txt` with version information,
environment details, active mod state, warning/error counts, Error/Critical/Fatal
log lines, and all structured report blocks when present. The bug report is also
refreshed automatically whenever an Error, Critical, or Fatal line is logged.
Repeated identical severe lines are collapsed with repeat counts so runaway
error loops do not flood the report.

The environment header includes the operating system, Debug mode, and ModDev
mode. The mod-state section includes enabled and disabled mods with versions and
load-order context plus compact `Mods/` and `ModDev/` folder summaries.

Reloaded sanitizes log output before writing it. Absolute paths inside the game
folder are shortened so logs do not expose local machine paths.

Any new Reloaded-created file, or any system we substantially change, should
include appropriate logging for startup/load success, validation warnings,
recoverable errors, critical failures, and final status for multi-step work.

## Patches

`Reloaded::Patches` is a registry for anything that changes, wraps, replaces,
bridges, or overrides base-game behavior.

The registry records patch points and logs conflicts so Reloaded can explain
what changed and why.

Basic use:

```ruby
Reloaded::Patches.register(
  :mart_ui_override,
  :target => "PokemonMartScreen#pbBuyScreen",
  :type => :wrap,
  :file => __FILE__,
  :owner => :reloaded,
  :priority => 100,
  :conflict_group => "mart_buy_screen",
  :reason => "Route marts through Reloaded's custom mart UI.",
  :recommended_fix => "Disable one mart UI patch or move the change to an event hook."
)
```

Patch types:

- `:wrap`
- `:replace`
- `:append`
- `:prepend`
- `:alias`
- `:event_bridge`
- `:data_patch`
- `:asset_override`

The registry marks a conflict when multiple patches target the same method,
data file, or asset and at least one of these is true:

- either patch explicitly lists the other in `:conflicts_with`,
- either patch uses `:replace`,
- either patch uses `:asset_override`,
- both patches use the same `:conflict_group`,
- both patches use the same type and same priority,
- both patches are order-sensitive and share the same priority.

Optional metadata can make reports more accurate:

```ruby
Reloaded::Patches.register(
  :example_patch,
  :target => "SomeClass#some_method",
  :type => :wrap,
  :owner => :example_mod,
  :priority => 100,
  :conflict_group => "some_method_ui_flow",
  :allow_multiple => false,
  :severity => :warning,
  :metadata => {
    :compatible_with => ["other_mod/known_safe_patch"],
    :conflicts_with => ["other_mod/known_conflicting_patch"]
  }
)
```

Querying:

```ruby
Reloaded::Patches.registered
Reloaded::Patches.registered("PokemonMartScreen#pbBuyScreen")
Reloaded::Patches.conflicts
Reloaded::Patches.conflict?("PokemonMartScreen#pbBuyScreen")
Reloaded::Patches.summary
Reloaded::Patches.write_summary
Reloaded::Patches.targets
Reloaded::Patches.target_summary("PokemonMartScreen#pbBuyScreen")
Reloaded::Patches.grouped_by_target
```

Any Reloaded system that substantially changes vanilla behavior should register
its patch point.

## System Registry

`Reloaded::Systems` is the runtime inventory for Reloaded foundation, modding,
UI, and gameplay systems. It describes and validates systems; it does not
replace `Reloaded/LoadOrder.rb` or load files itself.

Register a substantial mod system with:

```ruby
Reloaded.register_system(
  :example_quests,
  :name => "Example Quests",
  :description => "Adds reusable quest behavior.",
  :owner => :example_mod,
  :required_systems => [:save_data, :events],
  :optional_systems => [:mod_settings],
  :save_keys => [:example_mod],
  :feature_flags => [:example_quests]
)
```

Supported declaration fields are:

- `name`
- `description`
- `owner`
- `constant`
- `load_phase`
- `required_systems`
- `optional_systems`
- `save_keys`
- `feature_flags`
- `platform_capabilities`
- `debug_visible`
- an optional validation block

Duplicate IDs are rejected unless `override: true` is explicit. Required
dependency failures and dependency cycles make a system unavailable. Missing
optional systems or validation warnings make it degraded without disabling it.

Runtime queries:

```ruby
Reloaded::Systems.registered?(:reloaded_mart)
Reloaded::Systems.available?(:reloaded_mart)
Reloaded::Systems.active?(:reloaded_mart)
Reloaded::Systems.state(:reloaded_mart)
Reloaded::Systems.reason(:reloaded_mart)
Reloaded::Systems.system(:reloaded_mart)
Reloaded::Systems.systems
Reloaded::Systems.dependencies(:reloaded_mart)
Reloaded::Systems.validate
Reloaded::Systems.summary
```

Registry inspection returns defensive copies. Final built-in validation runs
after `:modules_loaded`, and system states are included in bug reports.

When Debug or ModDev is active, `Options -> Developer -> Foundation Inspector`
provides one read-only browser for systems, save metadata and migrations,
features, event hooks, and validators. Its Safe Actions page can create a
current-slot backup or refresh the validation report. It does not perform
general-purpose save edits.

## Feature Flags

`Reloaded::Features` gates structural, unfinished, experimental, or debug-only
systems. Feature flags do not replace normal player options such as PokeVial
ON/OFF or Standard/Reloaded UI choices.

```ruby
Reloaded::Features.register(
  :example_advanced_quests,
  :name => "Advanced Quests",
  :owner => :example_mod,
  :default => false,
  :classification => :experimental,
  :required_systems => [:save_data],
  :required_capabilities => [:gameplay]
)
```

Classifications are `stable`, `experimental`, `debug_only`, and `internal`.
Debug-only flags are unavailable outside Debug or ModDev.

Queries and overrides:

```ruby
Reloaded::Features.registered?(:example_advanced_quests)
Reloaded::Features.enabled?(:example_advanced_quests)
Reloaded::Features.available?(:example_advanced_quests)
Reloaded::Features.active?(:example_advanced_quests)
Reloaded::Features.reason(:example_advanced_quests)

Reloaded::Features.enable(:example_advanced_quests, :scope => :session)
Reloaded::Features.disable(:example_advanced_quests, :scope => :save)
Reloaded::Features.enable(:example_advanced_quests, :scope => :global)
Reloaded::Features.reset(:example_advanced_quests, :scope => :session)
```

Effective precedence is session, save, global, then declared default. Missing
systems, debug restrictions, and platform capabilities still prevent a flag
from becoming active. Session overrides are memory-only, save overrides use
`systems/features`, and global overrides use namespaced `feature.<id>` entries
in `Reloaded/Settings.txt`.

Unsupported platform features are unavailable and should be hidden by their UI
rather than displayed as unusable controls.

## Save Data

`Reloaded::SaveData` gives Reloaded systems and mods one central save bucket.

The base game save file receives one Reloaded entry:

```ruby
:reloaded
```

Reloaded stores data in this shape:

```ruby
{
  :schema_version => 1,
  :systems => {},
  :mods => {},
  :metadata => {}
}
```

`systems` is for Reloaded framework systems. `mods` is for mod data.

`metadata` records save compatibility and diagnostic context:

```ruby
{
  "game" => "hoenn",
  "created_at" => "2026-07-11 14:30:00",
  "updated_at" => "2026-07-11 16:45:00",
  "created_with_version" => "0.9.4",
  "last_saved_with_version" => "0.9.4",
  "base_version" => "1.1.0",
  "platform" => "Windows",
  "active_profile" => "Default",
  "enabled_mods" => [
    { "id" => "example_mod", "version" => "1.0.0" }
  ]
}
```

Creation fields are preserved for the life of the save. Updated fields,
platform, active profile, and the enabled-mod snapshot refresh immediately
before each save. Mod snapshots contain IDs and versions only; they never store
installation paths. Missing metadata in an older save is added automatically
and does not block loading.

Metadata is diagnostic in the current save schema. It does not independently
block a save from loading.

Read metadata through defensive-copy helpers:

```ruby
Reloaded::SaveData.metadata
Reloaded::SaveData.metadata_value(:platform, "Other")
Reloaded::SaveData.created_with_version
Reloaded::SaveData.last_saved_with_version
```

Mod use:

```ruby
Reloaded::SaveData.set(:example_mod, :quest_started, true)
Reloaded::SaveData.get(:example_mod, :quest_started, false)
Reloaded::SaveData.has?(:example_mod, :quest_started)
Reloaded::SaveData.delete(:example_mod, :quest_started)

save = Reloaded::SaveData.mod(:example_mod)
save["quest_stage"] = 2
```

System use:

```ruby
Reloaded::SaveData.set(:logging, :last_mode, "Developer", section: :systems)
Reloaded::SaveData.get(:logging, :last_mode, "Player", section: :systems)

save = Reloaded::SaveData.system(:logging)
save["last_mode"] = "Developer"
```

Current Reloaded system namespaces include:

- `:logging`
- `:reloaded_pause_menu`
- `:tm_vault`
- `:reloaded_mart`

Reloaded Mart stores these main keys under `systems/reloaded_mart`:

- `schema_version`
- `favorites`
- `stock`
- `stock_resets`
- `claims`
- `limits`
- `limits_daily`
- `stats`
- `catalog`
- `cache`
- `seen_catalog_versions`
- `daily_featured`

Values must be compatible with Ruby `Marshal.dump`. Avoid storing windows,
sprites, bitmaps, viewports, procs/lambdas, open files, or temporary scene
objects.

Reloaded emits these save events:

- `:reloaded_save_loaded`
- `:reloaded_save_saving`

Both receive:

```ruby
{
  :data => Reloaded::SaveData.data
}
```

The event data includes refreshed metadata when `:reloaded_save_saving` is
emitted.

### Save Migrations

`Reloaded::SaveMigrations` upgrades the selected save's Reloaded bucket when
`Game.load` loads that bucket. Reading save slots for title-screen previews does
not run Reloaded migrations.

Core migrations are sequential and transactional:

```ruby
Reloaded::SaveMigrations.register(
  :reloaded_schema_1_to_2,
  :from => 1,
  :to => 2
) do |bucket|
  bucket[:systems] ||= {}
  bucket
end
```

Each migration must advance exactly one schema version. The complete chain runs
on a deep copy and is committed only if every core migration succeeds. Unknown
system, mod, and metadata values are preserved.

Mods can migrate only their own namespace:

```ruby
Reloaded::SaveMigrations.register_mod(
  :example_mod,
  :from => 0,
  :to => 1
) do |data|
  data["new_field"] ||= false
  data
end
```

Mod schema versions use `_schema_version` inside the mod namespace. A failed
mod migration preserves that mod's original namespace and does not fail core
Reloaded migration or other mod migrations.

Completed migration IDs and isolated mod migration failures are recorded in
save metadata. Reloaded emits:

- `:reloaded_save_migration_started`
- `:reloaded_save_migrated`
- `:reloaded_save_migration_failed`

Before an older Reloaded schema is migrated, Reloaded creates and verifies a
rolling backup of the source slot. If that backup fails, migration does not run,
Reloaded shows a warning, and writes to the Reloaded bucket remain blocked for
that session. If the selected save uses a newer Reloaded schema, or a core
migration fails, the same write protection preserves the original bucket.

Runtime status is available through:

```ruby
Reloaded::SaveData.write_blocked?
Reloaded::SaveData.write_block_reason
```

### Save Protection

`Reloaded::SaveProtection` strengthens the existing multi-save system rather
than creating a separate save location. Before an existing slot is overwritten,
its current file is copied to:

```text
backups/<slot>/
```

Backups are copied in chunks, verified by file size, sorted explicitly, and
pruned to the newest `Settings::SAVEFILE_NB_BACKUPS` files. Retention never
drops below one backup.

Active saves are serialized to a same-directory temporary file first. Windows
and Proton use a rollback file while replacing an existing save. JoiPlay uses
same-filesystem rename replacement and retains the same backup behavior. A
failed replacement restores the previous active save where possible and leaves
the rolling slot backup available.

Migration backups are created only when `Game.load` actually loads an older
Reloaded bucket. Reading a slot for a title-screen preview tracks its source but
does not create a backup, run migrations, or modify the save.

## Options

`Reloaded::Options` extends the base game options system without editing the
vanilla options file. It adds reusable controls, rendering behavior, and a
consolidated collapsible category layout.

Generic Reloaded option UI settings are stored on `$PokemonSystem`:

```ruby
$PokemonSystem.reloaded_option_theme
$PokemonSystem.reloaded_category_theme
$PokemonSystem.reloaded_cursor_theme
$PokemonSystem.reloaded_options_cursor_theme
$PokemonSystem.reloaded_small_text
$PokemonSystem.reloaded_pause_menu
$PokemonSystem.hr_mart_confirm
```

Reloaded option defaults:

- `Menu Frame`: `RLD Transparent Dark`
- `Speech Follows Menu`: `On`
- `Global Small Text`: `On`
- `Pause Menu`: `Reloaded`
- `Options Cursor Color`: `White`
- `Reloaded Mart -> Remove Confirm Prompt`: `Off`
- `Reloaded Mart -> Box Animation`: `On`
- `Battle Style`: always `Set` and hidden from the Options menu.

Themes live in:

```ruby
Reloaded::Options::COLOR_THEMES
Reloaded::Options::CURSOR_THEMES
```

Menu frames are loaded from:

```text
Reloaded/Graphics/Windowskins/
```

The main Options menu is reorganized into collapsible categories:

- `VISUALS & UI`
- `GAMEPLAY`
- `ECONOMY`
- `CHALLENGE`
- `SYSTEM`
- `MODS`
- `DEVELOPER`
- `OTHER`
- `About`

`OTHER` is shown only when an upstream or modded option has no known category.
`About` is always the final collapsible category, followed by the standalone
`File A Bug Report` action.

Reloaded-owned actions and settings are placed before base-game rows in their
respective categories:

- `VISUALS & UI`: `Reloaded UI`.
- `GAMEPLAY`: `PokeVial`, `TM Vault`, and `PC Module`.
- `ECONOMY`: `Reloaded Mart`.
- `CHALLENGE`: `IV Boundaries`.

`Reloaded UI` currently contains:

- `Pause Menu`: `Standard` or `Reloaded`.
- `Overworld Menu`: `Off` or `On`.
- `Reloaded Summary`: `Standard` or `Reloaded`.
- `Reloaded Bag`: `Standard` or `Reloaded`.
- `Big Icons`: `Off` or `On`. When enabled, Pokemon icon displays use
  fitted full sprites, including PC storage icons. Defaults to `Off`.
- `Hint Texts`: `Off` or `On`. Defaults to `On`.
- `Autosort Options`: opens Reloaded Bag sorting and custom list order tools.

`About` contains the framework version, author, and Discord link. The
standalone bug-report action uses the same sanitized export, upload, clipboard,
and Discord workflow as the Mod Manager.

`Reloaded Bag` replaces the standard Bag when set to `Reloaded`. It also
replaces choose-item flows, including the battle bag item picker, while still
using the existing item handlers for item behavior.

Reloaded Bag supports:

- Pocket navigation with Left/Right.
- Favorites pinned to the top with a yellow `*` marker.
- Sort cycling with `L`: `Default`, `A-Z`, `Quantity`, `Type`, and `List`.
- Optional per-pocket sorting from `Autosort Options`.
- Custom List order editing from `Autosort Options`.
- Autosort import/export at `Mods/Reloaded/ReloadedBagAutosort.txt`.
- `NEW` and `HELD` badges.
- TM/HM rows showing their move names.
- Quantity display compatible with the current bag stack maximum.

`MODS` currently contains:

- `Mod Manager`
- `Mod Settings`
- `ModDev`

`DEVELOPER` currently contains:

- `Admin Tools`
- `Foundation Inspector`
- `Logging Mode`

Reloaded does not replace or intercept the game's controls. Players continue to
use the global mkxp keybindings configured by the base game. Reloaded reads
`keybindings.mkxp1` only to display the current labels inside Reloaded Controls
popups.

Mods can add options to existing Reloaded categories with:

```ruby
Reloaded::Options.register_category_option("DEVELOPER", :my_option, priority: 100) do |_scene|
  EnumOption.new(
    _INTL("My Option"),
    [_INTL("Off"), _INTL("On")],
    proc { 0 },
    proc { |value| nil },
    _INTL("Example option added by a mod.")
  )
end
```

Lower priority values appear earlier inside the category.

Hint text should use `Reloaded::HintText` where practical. Full formatted
lists use command-first labels as `Action (input)`, separate entries with
` | `, and use `Reloaded::InputBindings` to read the game's global
keyboard/controller labels. A connected controller is preferred automatically.
Scene footers should prefer
`Reloaded::HintText.draw_footer`, which shows a compact Hints control and can
show active status text such as `Quick-Buy Mode`; the full list should be shown
with `Reloaded::HintText.open_popup` when the Hints action is pressed. Keep
common commands in the standard order: Confirm, Back, Action, Special, Others.
Do not show input category names like `Confirm`, `Action`, or `Special` unless
those are the actual commands.

Supported reusable option row types:

- `CategoryHeader`
- `CollapsibleHeader`
- `TextDisplayOption`
- `ActionButton`
- `LockableEnumOption`
- `HiddenOption`
- `Spacer`

`Window_ReloadedOption` replaces the base option window through
`PokemonOption_Scene#initOptionsWindow`.

## Per-Mod Settings

Per-mod settings are defined in:

```text
Mods/<mod folder>/Settings.json
```

Player-selected values are stored in the active profile under `mod_settings`.

Supported setting types:

- `toggle`
- `enum`
- `slider`
- `number`
- `category_header`
- `spacer`

Runtime API:

```ruby
Reloaded::ModSettings.get("example_mod", "difficulty", "Normal")
Reloaded::ModSettings.set("example_mod", "difficulty", "Hard")
Reloaded::ModSettings.values("example_mod")
Reloaded::ModSettings.defaults("example_mod")
Reloaded::ModSettings.reset("example_mod", "difficulty")
Reloaded::ModSettings.reset("example_mod")
Reloaded::ModSettings.reset_all
Reloaded::ModSettings.stale_keys("example_mod")
Reloaded::ModSettings.prune_stale("example_mod")
Reloaded::ModSettings.restart_required?("example_mod", "difficulty")
```

Players can edit per-mod settings from:

```text
Options -> Mods -> Mod Settings
```

The settings UI uses the same Options scene as the main game options.

## Validation Framework

`Reloaded::Validation` provides shared boot, runtime, developer, and release
checks. Lightweight checks run after modules and game data load. Findings are
kept in memory, logged, and serious findings are included directly in
`LatestBugReport.txt`.

The background checks do not continuously write a separate report. Use
`Options -> Developer -> Foundation Inspector -> Safe Actions -> Refresh
Validation Report` to rerun the registered checks and write
`Reloaded/Logging/ValidationReport.txt` on demand.

A failed validator is isolated and disabled for the rest of the session. It
does not stop unrelated validators or game startup. Foundation checks are
available for Windows and Proton under `ModDev`.

Validation reports use temporary-file replacement and preserve the previous
valid report if replacement fails. Duplicate findings are collapsed and report
output is limited to prevent repeated failures from producing unbounded files.

## Detailed Documentation

- `Manager.md` - Mod Manager, Mod Browser, GitHub index, publishing, profiles,
  and profile codes.
- `DataPatches.md` - runtime data patch format, validation, conflicts, and API.
- `Events.md` - event API.
- `MapIDs.md` - map ID reference for encounter data patches.
- `Modding.md` - main modder-facing reference.
- `ReloadedMart.md` - Reloaded Mart catalog, backend, UI, and save contract.
