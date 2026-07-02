#======================================================
# Reloaded Settings Documentation
# Author: Stonewall
#======================================================
# Documents Reloaded/Settings.txt and the Reloaded::Settings API.
#
# Responsibilities:
#   - Explain the central Reloaded settings file.
#   - Record supported settings keys.
#   - Show how Reloaded systems should read and write settings.
#
#======================================================

Reloaded global settings are stored in:

```text
Reloaded/Settings.txt
```

The format is simple:

```text
key=value
```

Blank lines and lines starting with `#` are ignored.

## Current Keys

```text
logging_mode=Developer
moddev=Off
active_profile=Default
```

`logging_mode` controls how much detail Reloaded writes to its log files.

Accepted values:

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

Anything else is treated as false.

`active_profile` controls which Mod Manager profile is loaded from:

```text
Mods/Reloaded/Profiles/
```

Profiles do not control `ModDev`; ModDev remains global.

## API

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

Use this file for global Reloaded settings that are not save-specific.

## Mod Settings

Per-mod settings are different from global Reloaded settings.

Mods define their editable settings in:

```text
Mods/<mod folder>/Settings.json
```

That file describes available settings and defaults. Player-selected values are
stored in the active profile under `mod_settings`, not inside the mod folder.

Example `Settings.json`:

```json
{
  "settings": {
    "general": {
      "type": "category_header",
      "label": "General",
      "description": "General settings for this mod."
    },
    "difficulty": {
      "type": "enum",
      "label": "Difficulty",
      "description": "Controls this mod's difficulty.",
      "default": "Normal",
      "options": ["Easy", "Normal", "Hard"],
      "restart_required": true
    },
    "show_hints": {
      "type": "toggle",
      "label": "Show Hints",
      "default": true
    },
    "spawn_rate": {
      "type": "slider",
      "label": "Spawn Rate",
      "default": 5,
      "min": 1,
      "max": 10,
      "step": 1
    }
  }
}
```

Supported setting types:

- `toggle`
- `enum`
- `slider`
- `number`
- `category_header`, shown as a collapsed collapsible header in-game
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

Settings saved through this API are profile-specific.

If a setting is removed from `Settings.json` but an old profile still stores a
value for it, `Reloaded::ModSettings.values` ignores that stale value. Stale
values remain in the profile until `prune_stale`, per-mod reset, or reset-all
removes them.

## In-Game UI

Players can edit per-mod settings from:

```text
Options -> Mods -> Mod Settings
```

The Mod Manager also shows a `Settings` action for installed mods that expose a
valid `Settings.json` schema.

The `Mod Settings` list also includes:

- `Clean Stale Settings` - removes stored values whose setting keys no longer
  exist in the current schemas.
- `Reset All Mod Settings` - clears every mod setting stored in the active
  profile.

If a changed setting is marked `restart_required`, Reloaded reports that a
restart is required before the change is fully applied.

The settings UI uses the same Options scene as the main game options. This
means mod setting pages inherit the Reloaded option theme, cursor, frame, and
small-text behavior.
