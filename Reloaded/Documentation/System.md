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

- Bootstrap loader through one documented vanilla hook.
- Runtime window title sync from `Reloaded/Version.md`.
- Central settings file at `Reloaded/Settings.txt`.
- Central logging with modes, reports, bug-report export, and path sanitizing.
- Event API through `Reloaded::Events`.
- `Reloaded::Hooks` compatibility alias.
- Patch/conflict registry through `Reloaded::Patches`.
- Reloaded save bucket through `Reloaded::SaveData`.
- Runtime asset resolver for active mod assets.
- Mod scanning, validation, dependency-safe load ordering, and script loading.
- Runtime data patch collector and JSON-style data registry in the `008` core
  range.
- Active item, move, ability, species, trainer, trainer type, encounter, and
  outfit data patch targets.
- Runtime core fixes in `Reloaded/Core/009_CoreFixes.rb`.
- Script-facing Ability API.
- Profile system stored in `Mods/Reloaded/Profiles/`.
- Profile code export/import using `RLD-code-`.
- Per-mod settings API and Options-style settings UI.
- In-game Mod Manager with installed mods, profiles, browser, tools, and admin
  entry points.
- Mod Browser using the GitHub index for mods and published profiles.
- Consolidated Options menu with collapsible categories.

Current player-facing entry points:

```text
Options -> Reloaded -> Reloaded Mart
Options -> Reloaded -> [ TM Vault ]
Options -> Mods -> Mod Manager
Options -> Mods -> Mod Settings
Options -> Mods -> ModDev
Options -> Developer -> Admin Tools
Options -> Developer -> Logging Mode
```

Mods belong in:

```text
Mods/<mod folder>/
ModDev/<mod folder>/
```

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

Reloaded uses `Major.Minor.Patch` versioning in `Reloaded/Version.md`.

The current imported base Hoenn version is `1.1.0`.

Base-game file edits are tracked locally in
`Reloaded/Documentation/VanillaChanges.md`. That file is ignored because it is
developer-local review metadata, not shipped documentation.

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
```

`logging_mode` accepts:

```text
Player
Developer
Bug Report
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
- `Bug Report` - compact report-focused mode for exported diagnostics.

Code can change the mode with:

```ruby
Reloaded::Log.set_mode("Player")
Reloaded::Log.set_mode("Developer")
Reloaded::Log.set_mode("Bug Report")
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
warning/error counts, and recent report blocks.

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
- `active_coupons`
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

- `RELOADED`
- `VISUALS & UI`
- `GAMEPLAY`
- `ECONOMY`
- `CHALLENGE`
- `SYSTEM`
- `MODS`
- `DEVELOPER`
- `OTHER`

`RELOADED` is first in the category order.

`MODS` currently contains:

- `Mod Manager`
- `Mod Settings`
- `ModDev`

`DEVELOPER` currently contains:

- `Admin Tools`
- `Logging Mode`

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

Hint text should use the format `Action (input)`. The normal order is:
`Confirm (C) Back (B) ActionInput (A) SpecialInput (Z) Others`.

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

## Detailed Documentation

- `Manager.md` - Mod Manager, Mod Browser, GitHub index, publishing, profiles,
  and profile codes.
- `DataPatches.md` - runtime data patch format, validation, conflicts, and API.
- `Events.md` - event API.
- `MapIDs.md` - map ID reference for encounter data patches.
- `Modding.md` - main modder-facing reference.
- `ReloadedMart.md` - Reloaded Mart catalog, backend, UI, and save contract.
