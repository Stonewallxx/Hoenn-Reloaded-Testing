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

## Current Limits

- There is no in-game profile editor yet.
- `mod_settings` is reserved for the future Mod Manager UI.
- Profiles do not control `ModDev`, `Logging Mode`, or Reloaded visual options.
