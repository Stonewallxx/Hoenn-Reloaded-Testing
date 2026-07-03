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
- If an enabled mod depends on a newer dependency version than the installed
  one, the enabled mod is skipped and the dependency details show the installed
  and required versions.

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
Reloaded::Profiles.import_data(profile_hash)
```

The Mod Manager browser/downloader and profile-code import flow use these
methods when creating local profiles from downloaded or pasted profile data.
Downloaded modpacks should become imported profiles rather than a separate
runtime system.

## RLD Profile Codes

Profiles can also be exported as a share code:

```ruby
code = Reloaded::ProfileCodes.export_profile("Default")
Reloaded::ProfileCodes.import_code(code)
```

Profile codes start with:

```text
RLD-code-
```

The decoded payload format is named `RLD-code` and includes:

- `preset_name`
- `reloaded_version`
- profile load data
- profile-scoped `mod_settings`
- referenced mod metadata when available

Importing an RLD profile code always creates a new profile with a unique name.
It does not overwrite or edit an existing profile.

If an imported code references mods the player does not have installed, the UI
will show the missing mods and ask whether to download them through
`Reloaded::ModBrowser`.

`Download` installs the missing mods, then imports the new profile with those
newly downloaded missing mods disabled.

`Download & Enable` installs the missing mods, then imports the new profile
normally.

Both profile-code imports and published-profile imports use the browser
download planner. That planner also resolves dependency chains for downloaded
mods, reuses already installed dependencies that satisfy the minimum version,
and reports whether a failure came from a missing browser entry, a too-old
indexed dependency, or a download/install failure.

## In-Game Profile Page

The Mod Manager includes a Profiles page from its footer buttons.

Current in-game profile actions:

- Use `Confirm (C)` on a profile to open that profile's actions.
- Use `Menu (A)` on the Profiles page for page-level actions.
- Enable/disable a profile.
- Create a profile from the page menu.
- Duplicate a profile.
- Rename a profile.
- Delete an inactive non-default profile.
- Export a profile code to the clipboard.
- Import a pasted profile code as a new profile.
- View profile counts for enabled mods, disabled mods, load order entries, and
  profile-scoped mod settings.
- View resolved enabled/disabled mod names when they are installed.

Creating a profile from the in-game UI seeds it from the current installed mod
list so its enabled mod count, disabled mod count, and load order are populated
immediately.

Enabling, disabling, creating, or duplicating a profile from the in-game UI marks
the full Mod Manager as restart-required because the active loaded mod set may
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
Reloaded::Profiles.delete_mod_settings("example_mod")
Reloaded::Profiles.delete_mod_settings
```

These settings are stored inside the active profile under `mod_settings`.
Mods should usually use `Reloaded::ModSettings` instead of calling these
profile methods directly, because `Reloaded::ModSettings` validates values
against the mod's `Settings.json` schema.

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

- Missing-mod downloads require browser source indexes that contain matching
  mod IDs and download URLs.
- The profile page does not expose a separate load order editor. Load order is
  adjusted from the installed mods screen with Load Order mode.
- Profiles do not control `ModDev`, `Logging Mode`, or Reloaded visual options.
