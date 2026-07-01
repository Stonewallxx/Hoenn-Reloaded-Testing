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
