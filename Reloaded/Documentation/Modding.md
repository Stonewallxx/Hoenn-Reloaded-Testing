#======================================================
# Reloaded Modding Documentation
# Author: Stonewall
#======================================================
# Living documentation for modding against Hoenn Reloaded.
#
# Responsibilities:
#   - Explain Reloaded systems intended for modding use.
#   - Record recommended modding patterns as systems are added.
#   - Point modders toward logging, events, patches, and public APIs.
#   - Keep compatibility notes in one central document.
#
#======================================================

This file is the main modder-facing reference for Hoenn Reloaded.

It should be updated whenever a Reloaded system gains a public API that modders
are expected to use.

For a high-level status summary of the current fork foundation, see
`Reloaded/Documentation/Foundation.md`.

## Current Status

Reloaded is still building its modding foundation. The current public systems
are:

- `Reloaded::Log`
- `Reloaded::Events`
- `Reloaded::Hooks` compatibility alias
- `Reloaded::Patches`
- `Reloaded::SaveData`
- `Reloaded::Assets`
- `Reloaded::DataPatches`
- `Reloaded::Abilities`
- `Reloaded::ModManager`
- `Reloaded::ModBrowser`
- `Reloaded::Publisher`
- `Reloaded::ModderTools`
- `Reloaded::Profiles`
- `Reloaded::ModSettings`
- `Reloaded::Options`
- `Reloaded::Settings`

## Recommended Modding Rules

- Prefer Reloaded APIs over directly editing base-game files.
- Register behavior through events when an event exists.
- Register major vanilla behavior changes through `Reloaded::Patches`.
- Use `Reloaded::Log.mod` for mod-specific logging.
- Include clear mod IDs, versions, dependency notes, and recommended fixes in
  errors.
- Avoid replacing vanilla methods unless wrapping or events cannot solve the
  problem.

## Logging

Use `Reloaded::Log` for diagnostics and user-facing failure reports.

```ruby
Reloaded::Log.mod("example_mod", "Loaded settings")
Reloaded::Log.warning("Optional feature disabled", :mods)
```

For major failures, write a report:

```ruby
Reloaded::Log.report(
  :type => "Mod Load Failure",
  :mod_id => "example_mod",
  :mod_name => "Example Mod",
  :version => "1.0.0",
  :level => :critical,
  :file_path => __FILE__,
  :dependency_status => "Missing required dependency.",
  :recommended_fix => "Install the missing dependency or disable this mod.",
  :error => error
)
```

See `Reloaded/Documentation/Logging.md` for the full logging reference.

## Events

Use `Reloaded::Events` to attach behavior without directly replacing vanilla
code.

```ruby
Reloaded::Events.on(:bootstrap_loaded, :example_mod_boot, priority: 100) do |ctx|
  Reloaded::Log.mod("example_mod", "Bootstrap event received")
end
```

Use `Reloaded::Events.first_result` when an event should allow one handler to
provide an answer.

`Reloaded::Hooks` currently points to the same system for compatibility.

See `Reloaded/Documentation/Events.md` for the full event reference.

## Patches

Use `Reloaded::Patches` when a mod or Reloaded system changes vanilla behavior,
data, or assets.

```ruby
Reloaded::Patches.register(
  :example_mart_change,
  :target => "PokemonMartScreen#pbBuyScreen",
  :type => :wrap,
  :file => __FILE__,
  :owner => :example_mod,
  :priority => 100,
  :reason => "Add custom shop behavior.",
  :recommended_fix => "Disable one mart patch or move the change to an event."
)
```

This does not automatically patch the game. It records what is being changed so
Reloaded can detect conflicts and explain them in logs.

See `Reloaded/Documentation/Patches.md` for the full patches reference.

## Save Data

Use `Reloaded::SaveData` for persistent mod data.

```ruby
Reloaded::SaveData.set(:example_mod, :quest_stage, 2)
Reloaded::SaveData.get(:example_mod, :quest_stage, 0)
```

For direct access to your mod namespace:

```ruby
save = Reloaded::SaveData.mod(:example_mod)
save["quest_stage"] = 2
```

Do not add random fields to vanilla save objects for mod data unless there is no
Reloaded API that can handle the use case.

See `Reloaded/Documentation/SaveData.md` for the full save data reference.

## Data Patches

Use `DataPatches/**/*.json` for structured runtime data that should be added or
changed by a mod without replacing whole base files.

```text
Mods/<mod folder>/DataPatches/example_data.json
```

Supported operations:

- `add`
- `edit`
- `merge`
- `replace`

`remove` is not supported.

Example:

```json
{
  "target": "example_data",
  "operation": "add",
  "id": "example_entry",
  "data": {
    "name": "Example Entry",
    "value": 10
  }
}
```

Example item patch:

```json
{
  "target": "items",
  "operation": "add",
  "id": "example_reloaded_item",
  "data": {
    "name": "Example Reloaded Item",
    "name_plural": "Example Reloaded Items",
    "pocket": 1,
    "price": 100,
    "description": "A safe example item added by a Reloaded data patch.",
    "field_use": 0,
    "battle_use": 0,
    "type": 0
  }
}
```

For item patches, `id_number` may be provided manually, but it is optional.
Reloaded assigns the next available runtime number when it is omitted.

Example move patch:

```json
{
  "target": "moves",
  "operation": "add",
  "id": "example_reloaded_move",
  "data": {
    "name": "Example Reloaded Move",
    "function_code": "000",
    "base_damage": 40,
    "type": "NORMAL",
    "category": "Physical",
    "accuracy": 100,
    "total_pp": 35,
    "effect_chance": 0,
    "target": "NearOther",
    "priority": 0,
    "flags": "abef",
    "description": "A safe example move added by a Reloaded data patch."
  }
}
```

For move patches, `function_code` points to existing battle behavior. Use `000`
for a normal damage-only move. Custom move behavior still requires a Ruby script.

Example ability patch:

```json
{
  "target": "abilities",
  "operation": "add",
  "id": "example_reloaded_ability",
  "data": {
    "name": "Example Reloaded Ability",
    "description": "A safe example ability added by a Reloaded data patch."
  }
}
```

Ability patches make the ability exist and display. Custom ability behavior
still requires Ruby battle handler code.

Example species core patch:

```json
{
  "target": "species.core",
  "operation": "merge",
  "id": "treecko",
  "data": {
    "base_stats": {
      "SPEED": 75
    },
    "catch_rate": 45,
    "hatch_steps": 5120
  }
}
```

`species.core` changes core fields on existing species, such as types, stats,
EV yields, growth rate, gender ratio, catch rate, egg groups, hatch steps,
height, weight, color, shape, habitat, and generation. It does not add new
species or patch evolutions/forms.

Example species learnset patch:

```json
{
  "target": "species.learnsets",
  "operation": "merge",
  "id": "treecko",
  "data": {
    "add_moves": [
      {
        "level": 8,
        "move": "example_reloaded_move"
      }
    ],
    "add_tutor_moves": ["example_reloaded_move"],
    "add_egg_moves": ["example_reloaded_move"]
  }
}
```

`species.learnsets` changes level-up, tutor, and egg moves for existing
species. Use `add_moves`, `add_tutor_moves`, and `add_egg_moves` for small
additions. Use `moves`, `tutor_moves`, or `egg_moves` only when replacing the
full list.

Example species evolution patch:

```json
{
  "target": "species.evolutions",
  "operation": "merge",
  "id": "treecko",
  "data": {
    "add_evolutions": [
      {
        "species": "grovyle",
        "method": "Level",
        "parameter": 16
      }
    ]
  }
}
```

`species.evolutions` changes forward evolutions for existing species. Reloaded
rebuilds generated prevolution entries after applying these patches.

Example encounter patch:

```json
{
  "target": "encounters.classic",
  "operation": "merge",
  "id": "101_0",
  "data": {
    "add_types": {
      "Land": [
        {
          "chance": 5,
          "species": "example_species",
          "min_level": 8,
          "max_level": 10
        }
      ]
    }
  }
}
```

Encounter targets are `encounters.classic`, `encounters.remix`, and
`encounters.randomized`. IDs use `<map_id>_<version>`, such as `101_0`.
Use `add_types` for small additions and `types` for full encounter table
replacement.

Example species ability patch:

```json
{
  "target": "species.abilities",
  "operation": "replace",
  "id": "treecko",
  "data": {
    "abilities": ["overgrow"],
    "hidden_abilities": ["example_reloaded_ability"]
  }
}
```

`species.abilities` only changes the normal and hidden ability arrays for an
existing species. Use `replace` and provide the full arrays. Broad species data
patching is still future work.

Trainer patches:

- use `trainers.classic`, `trainers.remix`, or `trainers.expert`,
- target trainers by `TRAINER_TYPE|Trainer Name|Version`,
- can patch party Pokemon, held items, trainer battle items, trainer info text,
  battle intro text, lose text, and rematch text fields,
- validate species, moves, items, abilities, party slots, and missing trainer
  targets before runtime data is applied.

Trainer type patches use `trainer_types` for trainer-class-wide data such as
AI skill level, AI flags/skill code, and reward money multipliers. These affect
every trainer using that trainer type while the mod is enabled.

Runtime access:

```ruby
entry = Reloaded::DataPatches.entry("example_data", "example_entry")
all_entries = Reloaded::DataPatches.data("example_data")
```

Data patches are validated, logged, and registered with `Reloaded::Patches`.
They are applied in memory at startup and do not permanently edit base files.

See `Reloaded/Documentation/DataPatches.md` for the full data patch reference.

## Ability Behavior

Use `Reloaded::Abilities` when a modded ability needs battle behavior.

Example speed behavior:

```ruby
Reloaded::Abilities.on_speed_calc(:EXAMPLE_RELOADED_ABILITY) do |_ability, battler, mult|
  next mult * 2 if [:Rain, :HeavyRain].include?(battler.battle.pbWeather)
end
```

This uses the same underlying `BattleHandlers` system as vanilla abilities, but
with clearer Reloaded helper names.

General handler form:

```ruby
Reloaded::Abilities.on(:switch_in, :EXAMPLE_RELOADED_ABILITY) do |ability, battler, battle|
  # behavior here
end
```

Useful helpers include:

- `on_speed_calc`
- `on_status_immunity`
- `on_stat_loss_immunity`
- `on_move_immunity_target`
- `on_damage_calc_user`
- `on_damage_calc_target`
- `on_switch_in`
- `on_switch_out`
- `on_eor_effect`

Mods can also copy existing vanilla behavior:

```ruby
Reloaded::Abilities.copy_behavior(:SWIFTSWIM, :EXAMPLE_RELOADED_ABILITY)
```

`Reloaded::Abilities.register` can create ability data from Ruby scripts, but
JSON `abilities` data patches are preferred for normal mod data.

## Options

Use the Reloaded options framework for new in-game settings screens.

Current reusable types include:

- `CategoryHeader`
- `CollapsibleHeader`
- `TextDisplayOption`
- `ActionButton`
- `LockableEnumOption`
- `HiddenOption`
- `Spacer`

See `Reloaded/Documentation/Options.md` for the full options reference.

Mods can add rows to supported Reloaded categories:

```ruby
Reloaded::Options.register_category_option("DEVELOPER", :debug_toggle, priority: 50) do |_scene|
  EnumOption.new(
    _INTL("Debug"),
    [_INTL("Off"), _INTL("On")],
    proc { $DEBUG ? 1 : 0 },
    proc { |value| $DEBUG = value.to_i == 1 },
    _INTL("Toggles debug mode for this play session.")
  )
end
```

## Per-Mod Settings

Mods can define editable settings in:

```text
Mods/<mod folder>/Settings.json
```

Player values are stored in the active profile, not in the mod folder.
Players can edit these values from `Options -> Mods -> Mod Settings`, or from
the installed mod's `Settings` action in the Mod Manager.

Use `Reloaded::ModSettings` at runtime:

```ruby
difficulty = Reloaded::ModSettings.get("example_mod", "difficulty", "Normal")
Reloaded::ModSettings.set("example_mod", "difficulty", "Hard")
```

Supported setting types are `toggle`, `enum`, `slider`, `number`,
`category_header`, and `spacer`.

See `Reloaded/Documentation/Settings.md` for the full mod settings reference.

## Browser Sources

The Mod Browser backend reads downloadable mod indexes from GitHub-hosted
`index.json` files. The built-in source is:

```text
https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded-Mods/main/index.json
```

Mods and published profiles listed in browser indexes can be downloaded by
profile imports and the in-game Browser page. Reloaded does not require local
Browser or Publish folders for public source data.

See `Reloaded/Documentation/Browser.md` for the source and index formats.

## Publishing

Publishing uses the external Modders Tools script:

```text
Modders Tools/Publish to GitHub.bat
```

In-game, use:

```text
Mod Manager -> Tools -> Publish
```

The external script selects and validates the mod or profile, then does the
GitHub work before pushing.

## UI Hint Text

Use this format for Reloaded UI hint text:

```text
Action (input)
```

The normal order is:

```text
Confirm (C) Back (B) ActionInput (A) SpecialInput (Z) Others
```

Only include actions that are relevant to the current screen.
When `Input::ACTION` opens a page menu, label it as `Menu (A)`.

## Mod Folder Structure

Mods use this layout:

```text
Mods/
  example_mod/
    mod.json
    Scripts/
    Graphics/
    Audio/
    Fonts/
    Settings.json
    Documentation/
```

Required:

- `mod.json`

Optional:

- `Scripts/` - Ruby scripts loaded in alphabetical order.
- `Graphics/` - Graphics assets resolved at runtime.
- `Audio/` - Audio assets resolved at runtime.
- `Fonts/` - Font assets reserved for runtime resolution.
- `Settings.json` - Editable per-mod settings schema.
- `Changelog.txt` or `changelog.txt` - local changelog shown by the installed
  mod `View Changelog` action when no `changelogurl` is set.
- `Documentation/` - Mod author documentation.

## ModDev

`ModDev/` is a developer override folder.

When ModDev is enabled, Reloaded also scans:

```text
ModDev/
  example_mod/
    mod.json
```

If the same mod `id` exists in both `Mods/` and `ModDev/`, the `ModDev/`
version is used and the `Mods/` version is skipped.

ModDev can be changed from the in-game options menu under:

```text
Options -> Mods -> ModDev
```

The setting is stored in:

```text
Reloaded/Settings.txt
moddev=On
```

Changing it applies on the next mod scan or restart.

## Profiles

Profiles are named mod setups stored in:

```text
Mods/Reloaded/Profiles/
```

The active profile is selected by:

```text
Reloaded/Settings.txt
active_profile=Default
```

Profiles control:

- enabled mods,
- disabled mods,
- player-preferred load order,
- profile-scoped per-mod settings.

Profiles do not control `ModDev`, `Logging Mode`, or Reloaded visual options.

Example:

```json
{
  "id": "default",
  "name": "Default",
  "version": 1,
  "enabled_mods": ["example_mod"],
  "disabled_mods": [],
  "load_order": ["example_mod"],
  "mod_settings": {},
  "notes": "Default Reloaded mod profile."
}
```

Dependencies still load before dependents, even if `load_order` places them
later. Missing profile mods log warnings.

Useful profile API examples:

```ruby
Reloaded::Profiles.create("Testing")
Reloaded::Profiles.activate("Testing")
Reloaded::Profiles.enable_mod("example_mod")
Reloaded::Profiles.set_load_order(["library_mod", "example_mod"])
Reloaded::Profiles.set_mod_setting("example_mod", "difficulty", "Hard")
Reloaded::Profiles.export_profile("Testing", "Mods/Reloaded/Testing.json")
```

See `Reloaded/Documentation/Profiles.md` for the full profile reference.

## Core And Modules

`Reloaded/Core/` contains framework systems that other Reloaded code depends on:
logging, settings, events, patches, save data, assets, profiles, mod loading,
and options.

`Reloaded/Modules/` is for Reloaded-owned feature systems that load after Core
is ready. Good examples are gameplay systems, optional UI replacements, or
feature modules that use the Core APIs.

Mods should not be placed in `Reloaded/Modules/`. External mods belong in
`Mods/<mod folder>/` or `ModDev/<mod folder>/`.

## Mod Manager Backend API

The Mod Manager exposes read-only helper methods for UI screens and debug
tooling.

```ruby
Reloaded::ModManager.mod_ids
Reloaded::ModManager.mod_rows
Reloaded::ModManager.mod_row("example_mod")
Reloaded::ModManager.mod_status("example_mod")
Reloaded::ModManager.dependency_status("example_mod")
Reloaded::ModManager.incompatibility_status("example_mod")
Reloaded::ModManager.profile_summary
```

`mod_rows` returns display-ready hashes with mod metadata, profile enabled
state, validation warnings/errors, dependency status, incompatibility status,
system tags, source folder, loaded state, and script count.

Common status values:

- `:enabled`
- `:disabled`
- `:missing_dependency`
- `:conflict`
- `:broken`
- `:invalid`
- `:missing`

## Mod Manager UI

The in-game Mod Manager UI is available from:

```text
Options -> Mods -> Mod Manager
```

Current UI features:

- installed mod list,
- active profile summary,
- search,
- filters for enabled, disabled, dependency issues, and conflicts,
- right-side mod details,
- dependency and incompatibility details,
- enable/disable through the active profile,
- load order mode with pick-up/place controls,
- installed mod update, changelog, settings, and uninstall actions,
- Profiles footer page for profile management and profile code import/export,
- Browser footer page for mod/profile downloads from the GitHub index,
- Tools footer page for logs, backups, modder tools, publishing, and admin-only
  index editing,
- restart-required exit warning for mod load changes,
- keyboard/controller and mouse hover/click support.

Changing profile state from the UI updates the active profile immediately and
refreshes mod metadata. Changes that affect the loaded mod set or load order
show a restart-required popup when leaving the full Mod Manager. Ruby scripts
are not hot-loaded or unloaded while the game is running, so script changes
should still be treated as restart-required.

## Modder Tools

The Mod Manager Tools page includes local utilities for mod development and
debugging:

```text
Mod Manager -> Tools
```

Log Files:

- `View Log.txt`
- `View Mods.txt`
- `View Coop.txt`
- `View LatestBugReport.txt`
- `Clear Logs`
- `Export`

Viewing a log opens the file directly from `Reloaded/Logging/`. Export uploads
the selected log to `paste.rs` and copies the returned URL to the clipboard.
`LatestBugReport.txt` is created automatically if it does not already exist.
Clear Logs empties all Reloaded log files for a fresh troubleshooting run.

Backup Mods:

- `All Mods`
- `Select Mods`

Backups are written as timestamped `.zip` files under:

```text
ModsBackup/
```

Backups use the bundled `REQUIRED_BY_INSTALLER_UPDATER/7z.exe`. The profile
folder `Mods/Reloaded/` is not included in mod backups.

Tools menu order:

- `Admin Tools` when local admin files are present
- `Template Generator`
- `Manifest Validator/Fixer`
- `Log Files`
- `Backup Mods`
- `Publish`

The manifest validator scans `Mods/` and enabled `ModDev/` folders and reports
missing or invalid manifest fields. The fixer only applies safe structural
defaults, such as missing `id`, `name`, `version`, `authors`, `dependencies`,
`tags`, and `minimum_reloaded_version`. It does not rewrite mod code.

The template generator can create:

- a starter mod folder with `mod.json`, `Scripts/`, assets folders,
  `Settings.json`, `Changelog.txt`, and documentation,
- a starter profile under `Mods/Reloaded/Profiles/`.

The backend API is:

```ruby
Reloaded::ModderTools.open_log("Log.txt")
Reloaded::ModderTools.export_log("Mods.txt")
Reloaded::ModderTools.backup_all_mods
Reloaded::ModderTools.validate_manifests
Reloaded::ModderTools.create_mod_template("My Mod")
Reloaded::ModderTools.create_profile_template("My Profile")
```

## Mod Manifest

Each mod must include `mod.json`:

```json
{
  "id": "example_mod",
  "name": "Example Mod",
  "version": "1.0.0",
  "authors": ["Stonewall"],
  "description": "Example Reloaded mod.",
  "minimum_reloaded_version": "1.0.0",
  "dependencies": [],
  "incompatible": [],
  "tags": ["mod", "gameplay"],
  "changelogurl": "https://example.com/example_mod_changelog.txt"
}
```

Rules:

- `id` must use lowercase letters, numbers, and underscores.
- `id` is the stable identifier Reloaded uses for profiles, dependencies,
  browser entries, and published filenames.
- The mod folder name does not need to match `id`.
- `version` and `minimum_reloaded_version` use `Major.Minor.Patch`.
- `authors`, `dependencies`, and `tags` are arrays.
- `enabled` is legacy metadata; active profiles decide whether a mod loads.
- `changelogurl` is optional and should point to a raw text changelog if used.
  Mods can instead include a local `Changelog.txt`/`changelog.txt` in their mod
  folder.
- Dependencies load before mods that depend on them. Dependency `version`
  values are minimum required versions, not exact locks.
- If a dependency is missing, disabled in the active profile, or installed below
  the required version, Reloaded skips the dependent mod and reports the exact
  reason in the dependency details/logs.
- Browser downloads install dependency chains before the selected mod when the
  required dependency entries exist in the GitHub index.

`load_after`, `load_before`, `priority`, `type`, `scripts`, and
`minimum_base_version` are not part of the current manifest format.

## Mod Tags

Editable tag arrays live at the top of:

```text
Reloaded/Core/005_ModManager.rb
```

Author tags are grouped into role and content tags. System tags are assigned by
Reloaded or the Mod Manager.

Unknown author tags log warnings rather than blocking a mod.

Special entries are admin-controlled browser/index metadata. Mod authors cannot
grant this placement through normal `mod.json` tags. `Special Entry`,
and `Featured` are reserved admin labels; if they appear in normal mod tags,
Reloaded ignores them as display tags and logs a warning.

The current special-entry metadata is:

- `featured`: curated/admin-highlighted entry. Shows above special entries.
- `special_entry`: generic admin-highlighted entry shown above normal rows.

## Script Loading

Reloaded loads every Ruby file in:

```text
Mods/example_mod/Scripts/**/*.rb
```

Files load alphabetically, so mod authors should name ordered scripts like:

```text
001_Main.rb
002_Items.rb
003_Events.rb
```

Mods without a `Scripts/` folder can still provide metadata and assets.

## Asset Loading

Mod assets are not copied into base game folders.

Reloaded scans active mods and resolves assets at runtime:

```text
Mods/example_mod/Graphics/Pictures/foo.png
Mods/example_mod/Audio/BGM/song.ogg
```

When the game asks for:

```text
Graphics/Pictures/foo
Audio/BGM/song
```

Reloaded checks active mod assets first, then falls back to vanilla files.

The first resolver patches common helper paths:

- `RPG::Cache.load_bitmap`
- `RPG::Cache.load_bitmap_path`
- `AnimatedBitmap.new`
- `pbResolveBitmap`
- `pbBitmapName`
- `FileTest.image_exist?`
- `FileTest.audio_exist?`
- `Audio.bgm_play`
- `Audio.me_play`
- `Audio.bgs_play`
- `Audio.se_play`

Reloaded does not globally patch `Bitmap.new` yet.

## Planned Documentation Sections

These sections should be added as the systems are created:

- dependency rules,
- broader custom content registration,
- compatibility guidelines.
