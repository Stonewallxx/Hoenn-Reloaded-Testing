#======================================================
# Reloaded Modding Documentation
# Author: Stonewall
#======================================================
# Living documentation for modding against Hoenn Reloaded.
#
# Responsibilities:
#   - Explain Reloaded systems intended for modding use.
#   - Record recommended modding patterns as systems are added.
#   - Point modders toward logging, events, patches, and future APIs.
#   - Keep compatibility notes in one central document.
#
#======================================================

This file is the main modder-facing reference for Hoenn Reloaded.

It should be updated whenever a Reloaded system gains a public API that modders
are expected to use.

## Current Status

Reloaded is still building its modding foundation. The current public systems
are:

- `Reloaded::Log`
- `Reloaded::Events`
- `Reloaded::Hooks` compatibility alias
- `Reloaded::Patches`
- `Reloaded::SaveData`
- `Reloaded::Assets`
- `Reloaded::ModManager`
- `Reloaded::Profiles`
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
- `Settings.json` - Reserved for future Mod Manager settings.
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
MODS > ModDev
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
- future per-mod settings.

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

See `Reloaded/Documentation/Profiles.md` for the full profile reference.

## Core And Modules

`Reloaded/Core/` contains framework systems that other Reloaded code depends on:
logging, settings, events, patches, save data, assets, profiles, mod loading,
and options.

`Reloaded/Modules/` is for Reloaded-owned feature systems that load after Core
is ready. Good examples are future gameplay systems, optional UI replacements,
or feature modules that use the Core APIs.

Mods should not be placed in `Reloaded/Modules/`. External mods belong in
`Mods/<mod_id>/` or `ModDev/<mod_id>/`.

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
  "tags": ["mod", "gameplay"]
}
```

Rules:

- `id` must use lowercase letters, numbers, and underscores.
- The mod folder name should match `id`.
- `version` and `minimum_reloaded_version` use `Major.Minor.Patch`.
- `authors`, `dependencies`, and `tags` are arrays.
- `enabled` is legacy metadata; active profiles decide whether a mod loads.
- Dependencies load before mods that depend on them.

`load_after`, `load_before`, `priority`, `type`, `scripts`, and
`minimum_base_version` are not part of the current manifest format.

## Mod Tags

Editable tag arrays live at the top of:

```text
Reloaded/Core/005_ModManager.rb
```

Author tags are grouped into role and content tags. System tags are assigned by
Reloaded or the future Mod Manager.

Unknown author tags log warnings rather than blocking a mod.

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

## Future Sections

These sections should be added as the systems are created:

- dependency rules,
- custom content registration,
- data patching,
- asset overrides,
- compatibility guidelines,
- in-game settings integration.
