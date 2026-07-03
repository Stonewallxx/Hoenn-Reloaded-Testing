#======================================================
# Reloaded Foundation
# Author: Stonewall
#======================================================
# Current high-level status of the Hoenn Reloaded framework foundation.
#
# Responsibilities:
#   - Summarize the systems currently in place.
#   - Explain how the foundation supports modding and future tools.
#   - Point maintainers to the detailed documentation files.
#
#======================================================

This document is the short status map for the current Hoenn Reloaded
foundation. Detailed behavior still lives in the focused documentation files.

## Current Foundation Status

Hoenn Reloaded currently has the following framework systems in place:

- Bootstrap loader through one documented vanilla hook.
- Runtime window title sync from `Reloaded/Version.md`.
- Central settings file at `Reloaded/Settings.txt`.
- Central logging with modes, reports, bug-report export, and path sanitizing.
- Event API through `Reloaded::Events`.
- `Reloaded::Hooks` compatibility alias.
- Patch/conflict registry through `Reloaded::Patches`, including conflict
  groups, explicit compatibility metadata, and per-target summaries.
- Reloaded save bucket through `Reloaded::SaveData`.
- Runtime asset resolver for active mod assets.
- Mod scanning, validation, dependency-safe load ordering, and script loading.
- Browser-backed dependency-chain downloads with clearer missing, disabled, and
  version-mismatch reporting.
- Runtime data patch collector and JSON-style data registry in the `008` core
  range.
- Active item, move, ability, species core, species learnset, species evolution,
  species ability list, trainer, trainer type, encounter, and outfit data patch
  targets, with a reserved bridge file for future quest data.
- Runtime core fixes in `Reloaded/Core/009_CoreFixes.rb`, currently including
  the locked overworld Pokemon interaction battle fix.
- Script-facing Ability API for registering modded ability behavior through the
  existing battle handler system.
- Profile system stored in `Mods/Reloaded/Profiles/`.
- Profile code export/import using `RLD-code-`.
- Per-mod settings API and Options-style settings UI.
- In-game Mod Manager with installed mods, profiles, browser, tools, and admin
  entry points.
- Mod Browser using the GitHub index for mods and published profiles.
- Publisher batch tool for uploading mods/profiles to the GitHub index.
- Admin-only Manager Editor for editing GitHub index metadata.
- Consolidated Options menu with collapsible categories.

## Current Player-Facing Entry Points

```text
Options -> Mods -> Mod Manager
Options -> Mods -> Mod Settings
Options -> Mods -> ModDev
Options -> Developer -> Logging Mode
```

The Mod Manager currently contains:

- installed mods page,
- Profiles footer page,
- Browser footer page,
- Tools footer page,
- optional Admin Tools menu when local admin files are present.

## Current Modder-Facing Entry Points

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
- `Reloaded::Events` for broad lifecycle hooks.
- `Reloaded::Patches` when changing vanilla behavior.
- `Reloaded::SaveData` for persistent save data.
- `Reloaded::ModSettings` for profile-backed mod settings.
- `Reloaded::Assets` indirectly by placing assets in the mod folder.
- `Reloaded::DataPatches` for runtime item, move, ability, species core,
  species learnset, species evolution, species ability list, trainer, trainer
  type, encounter, and outfit data.
- `Reloaded::Abilities` for custom ability behavior.

## Version And Update Notes

Reloaded uses `Major.Minor.Patch` versioning in `Reloaded/Version.md`.

The current imported base Hoenn version is `1.1.0`.

Each mod manifest includes `minimum_reloaded_version`, and the Mod Manager
marks mods as outdated when the fork version is too old.

This fork is a custom base-game fork. Base-game file edits are intentionally
kept small and tracked in:

```text
Reloaded/Documentation/VanillaChanges.md
```

The developer-only upstream base updater lives in:

```text
Developer Tools/Base Game Updater/
```

It updates base files from upstream without touching Hoenn Reloaded's `.git`
folder. It protects `Game.ini`, because it contains Reloaded-specific root
configuration. `mkxp.json` may be refreshed from upstream, while Reloaded
applies the current versioned window title again during boot.

## Detailed Documentation

- `Browser.md` - Mod Browser, GitHub index, publishing, and Manager Editor.
- `DataPatches.md` - runtime data patch format, validation, conflicts, and API.
- `Events.md` - event API.
- `Logging.md` - logging files, modes, reports, and path sanitizing.
- `MapIDs.md` - map ID reference for encounter data patches.
- `Modding.md` - main modder-facing reference.
- `Options.md` - Options menu framework and categories.
- `Patches.md` - patch registry and conflict reports.
- `Profiles.md` - profiles and profile codes.
- `SaveData.md` - save bucket API.
- `Settings.md` - global settings and per-mod settings.
- `To-Do.md` - deferred work.
- `VanillaChanges.md` - base game file edits.

## Remaining Foundation Work

The foundation is usable for early Reloaded modding, but these areas still need
future work:

- Direct base game data patch targets for species forms, safe map/event edits,
  and quests.
- Economy/Reloaded Mart system for shop behavior and mart stock.
- More official event bridge points as real integration points are needed.
- Remaining Modders Tools review against the reference folder.
