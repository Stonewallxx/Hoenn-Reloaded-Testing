#======================================================
# Reloaded Profiles Documentation
# Author: Stonewall
#======================================================
# Documents Mod Manager profile storage and behavior.
#
# Responsibilities:
#   - Explain where profiles are stored.
#   - Record the profile JSON format.
#   - Explain how profiles affect mod loading.
#   - Clarify what profiles do not control.
#
#======================================================

Reloaded profiles are named mod load setups.

Profiles are stored in:

```text
Mods/Reloaded/Profiles/
```

The active profile is stored globally in:

```text
Reloaded/Settings.txt
active_profile=Default
```

`ModDev` is not controlled by profiles. It remains a global developer toggle in
`Reloaded/Settings.txt`.

## Default Profile

If no profile exists, Reloaded creates:

```text
Mods/Reloaded/Profiles/Default.json
```

## Profile Format

```json
{
  "id": "default",
  "name": "Default",
  "version": 1,
  "enabled_mods": [],
  "disabled_mods": [],
  "load_order": [],
  "mod_settings": {},
  "notes": "Default Reloaded mod profile."
}
```

## Loading Rules

The Mod Manager uses the active profile after scanning and validating manifests.

- Mods are enabled only when their `id` is listed in `enabled_mods`.
- Mods listed in `disabled_mods` are always disabled.
- `load_order` controls player-preferred ordering.
- Dependencies still load before dependents, even if `load_order` puts them
  later.
- If a profile references a missing mod, Reloaded logs a warning.
- If an enabled mod depends on a disabled mod, the enabled mod is skipped for a
  missing disabled dependency.

## Profile API

Profiles are managed through `Reloaded::Profiles`.

Profile management:

```ruby
Reloaded::Profiles.names
Reloaded::Profiles.list
Reloaded::Profiles.create("Testing")
Reloaded::Profiles.duplicate("Default", "Modded")
Reloaded::Profiles.rename("Testing", "Testing 2")
Reloaded::Profiles.delete("Testing 2")
Reloaded::Profiles.activate("Default")
```

Profile import and export:

```ruby
Reloaded::Profiles.export_profile("Default", "Mods/Reloaded/DefaultExport.json")
Reloaded::Profiles.import_profile("Mods/Reloaded/DefaultExport.json")
```

These methods are intended for the future Mod Manager browser/downloader.
Downloaded modpacks should become imported profiles rather than a separate
runtime system.

## In-Game Profile Page

The Mod Manager includes a Profiles page from its page menu.

Current in-game profile actions:

- Activate a profile.
- Create a profile.
- Duplicate a profile.
- Rename a profile.
- Delete an inactive non-default profile.
- View profile counts for enabled mods, disabled mods, load order entries, and
  profile-scoped mod settings.

Activating, creating, or duplicating a profile from the in-game UI marks the
full Mod Manager as restart-required because the active loaded mod set may
change. The restart popup is only shown when leaving the full Mod Manager.

Mod state:

```ruby
Reloaded::Profiles.enable_mod("example_mod")
Reloaded::Profiles.disable_mod("example_mod")
Reloaded::Profiles.set_mod_enabled("example_mod", true)
Reloaded::Profiles.set_enabled_mods(["example_mod"])
Reloaded::Profiles.set_disabled_mods(["old_mod"])
```

Load order:

```ruby
Reloaded::Profiles.set_load_order(["library_mod", "example_mod"])
Reloaded::Profiles.move_mod("example_mod", -1)
Reloaded::Profiles.ordered_mod_ids(["example_mod", "library_mod"])
```

`load_order` is still dependency-safe. The profile stores the player-preferred
order, then the Mod Manager forces dependencies before dependents during load.

Profile-scoped mod settings:

```ruby
Reloaded::Profiles.set_mod_setting("example_mod", "difficulty", "Hard")
Reloaded::Profiles.mod_setting("example_mod", "difficulty", "Normal")
Reloaded::Profiles.delete_mod_setting("example_mod", "difficulty")
```

These settings are stored inside the active profile under `mod_settings`.

Utility methods:

```ruby
Reloaded::Profiles.active_name
Reloaded::Profiles.active
Reloaded::Profiles.exists?("Default")
Reloaded::Profiles.summary
Reloaded::Profiles.missing_mod_ids(["example_mod"])
Reloaded::Profiles.remove_mod("example_mod")
```

## Current Limits

- Profile import/export exists, but the in-game browser/downloader is not built
  yet.
- The profile page does not yet expose a dedicated load order editor. Installed
  mod order can still be adjusted from the installed mods screen.
- Profiles do not control `ModDev`, `Logging Mode`, or Reloaded visual options.
