# Hoenn Reloaded

Hoenn Reloaded is a Hoenn-focused Pokemon Infinite Fusion project with its own
framework, interfaces, mod manager, spritepack system, gameplay modules, and
cross-platform packaging.

Current development version: **0.9.4 Pre-Release**

Hoenn Reloaded is still being stabilized for 1.0. The Public channel is the
recommended player build. The Testing channel follows active development and
may contain unfinished or recently changed behavior.

## Install Or Update

The installer always installs into the directory containing its files. Extract
the installer package into the folder where Hoenn Reloaded should live, then
run the frontend for your platform.

### Windows

Run:

```text
Hoenn Reloaded Installer.bat
```

### Proton / Steam Deck

Hoenn Reloaded targets Proton compatibility rather than native Linux. Run:

```text
Hoenn Reloaded Installer.sh
```

The Proton installer requires Python 3 and the bundled installer files.

### Installer Channels

Both desktop installers offer a game channel choice:

```text
Hoenn Reloaded
Hoenn Reloaded Testing
```

Every installation includes Core and the latest Full Spritepack containing both
Base and Expanded sprites. Core updates and Spritepack updates remain versioned
separately, so an unchanged Full Spritepack is not downloaded again.

Rerun the same installer for future updates. If an installation is interrupted,
the next launch automatically enters Repair mode using the original channel
choice. The game will not boot from a known incomplete install.

### JoiPlay / Android

Use the complete Public JoiPlay ZIP instead of the desktop installer. The
JoiPlay package already includes the Full Spritepack and excludes unsupported
desktop publishing, download, Admin, and ModDev tools.

Compatible mods can be installed manually under `Mods/<mod folder>/`.

## Launching

Run:

```text
InfiniteFusion2.exe
```

`InfiniteFusion2-performance.exe` is also included for systems where the
alternate runtime performs better.

## Main Features

- Reloaded Pause Menu and categorized Options.
- Reloaded Bag with favorites, sorting, custom order, item badges, and battle
  bag support.
- Reloaded Pokemon Stats page with abilities, IV/EV/BST totals, weaknesses,
  Hidden Power, friendship, and fusion information.
- Mod Manager, Mod Browser, profiles, dependencies, updates, and mod settings.
- Packed Full and monthly Spritepacks with manual `Sprite Import` support.
- Reloaded Mart with multiple currencies, services, bundles,
  gifts, Mystery Boxes, and shared rewards.
- TM Vault with TM/HM browsing, relearn sorting, egg moves, and PokeNav access.
- Customizable Overworld Menu with Quick Items and registered mod entries.
- Optional Pause Menu PC access and PokeVial healing.
- IV Boundary presets for newly generated Pokemon.
- Per-Pokemon stored Hidden Power types.
- Logging, bug reports, safe downloads, archive validation, save protection,
  and modder APIs.

## Mods And Spritepacks

Use the in-game Mod Manager for normal mod, profile, and Spritepack management.
Manual mods belong in:

```text
Mods/<mod folder>/
```

Manually supplied Pokemon sprites belong in:

```text
Graphics/CustomBattlers/Sprite Import/
```

They are validated and sorted when the Sprite Import process runs.

## Saves And Logs

Windows save data is stored under:

```text
%APPDATA%\Hoenn Reloaded
```

Proton save data uses:

```text
~/.local/share/Hoenn Reloaded
```

Reloaded diagnostics are written under `Reloaded/Logging/`. Use the in-game
bug-report action when reporting a crash or reproducible problem.

## Documentation

- Player changes: `Reloaded/Changelog.md`
- Modding API: `Reloaded/Documentation/Modding.md`
- Mod Manager and profiles: `Reloaded/Documentation/Manager.md`
- Framework and installer: `Reloaded/Documentation/System.md`
- Data Patches: `Reloaded/Documentation/DataPatches.md`
- Vanilla file changes: `Reloaded/Documentation/VanillaChanges.md`
- Credits and upstream acknowledgements: `Credits.txt`

## Project Links

- Public releases: https://github.com/Stonewallxx/Hoenn-Reloaded
- Testing source: https://github.com/Stonewallxx/Hoenn-Reloaded-Testing

## Legal

Hoenn Reloaded is a free fan project. Do not pay for it. Pokemon and related
properties belong to their respective owners. Hoenn Reloaded is not affiliated
with or endorsed by Nintendo, Game Freak, The Pokemon Company, or Creatures
Inc.
