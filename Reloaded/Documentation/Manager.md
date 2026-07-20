#======================================================
# Reloaded Manager Documentation
# Author: Stonewall
#======================================================
# Documents the Mod Manager, Mod Browser, profiles, source registry, download
# backend, and UI.
#
# Responsibilities:
#   - Explain the GitHub browser source.
#   - Record the index JSON format.
#   - Explain missing-mod download behavior.
#   - Track current browser behavior and limits.
#
#======================================================

The Mod Browser is handled by `Reloaded::ModBrowser` and the in-game Mod
Manager browser page.

It is responsible for finding downloadable mods, resolving missing profile
mods, downloading archives, and installing mod folders into `Mods/`.

The Mod Manager also injects protected non-mod entries for `Hoenn Reloaded` and
`Spritepacks`. They are pinned above normal mods in the installed list. These
entries are read-only as normal mods: players can use their custom actions, but
they cannot be disabled, reordered, downloaded, or uninstalled as normal mods.

## GitHub Source

The Mod Browser uses the official GitHub index by default:

```text
https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded-Mods/main/index.json
```

Reloaded does not create local Browser or Publish folders for this. Remote
fetching happens when the Mod Manager asks for browser data or missing-mod
downloads.

## In-Game Browser

Open the browser from:

```text
Options -> Mods -> Mod Manager -> Browser
```

Current controls:

- `Confirm (C)` opens actions for the selected entry.
- `Back (B)` returns to the installed mods page.
- `Menu (A)` opens the same action menu as confirm.
- `Filter (Z)` filters all entries, mods, profiles, installed entries, or
  available entries.
- `L/R` swaps between the Mod Browser and Profile Browser.
- Clicking the search field starts browser search.

Footer buttons use the shared Mod Manager footer system. The browser page
currently has a right-most `Back` footer button; downloads and imports are
handled from the selected entry's action menu.

Mod actions:

- `Download`
- `Download & Enable`
- `Versions`

The pinned `Hoenn Reloaded` installed-list entry shows `Update` when a public
update is available, plus `Check Updates` or `Update Status`, `Patch Notes`,
`File A Bug Report`, and `Open Mods Folder` instead of normal mod actions.
`Update` confirms, closes the game, and launches the AIO installer. It uses
`Hoenn Reloaded Installer.bat` on Windows and `Hoenn Reloaded Installer.sh` on
Proton. Both frontends install into their own directory and offer:

- `Hoenn Reloaded` or `Hoenn Reloaded Testing`
- `Core` or `Core + Spritepacks`

Public Core uses a versioned GitHub release with size and SHA-256 verification.
Testing Core downloads the current `Stonewallxx/Hoenn-Reloaded-Testing`
repository snapshot directly because Testing does not publish player releases.
Neither path creates a player-side Git repository or repository cache.
Large remote packages use up to six simultaneous HTTP range connections.
Servers that do not support ranged downloads automatically use the resumable
single-connection path instead. Range workers write to one preallocated
`.part` file, and a metadata sidecar safely resumes each completed range after
an interruption. The installer checks download and extraction space first,
retries transient/rate-limit failures with backoff, and can replace itself from
a newer SHA-256-verified bootstrap listed in the release manifest.

Core and Spritepacks are independent. Core-only leaves installed Spritepacks
unchanged. Core + Spritepacks reads the shared public Spritepack catalog and
only downloads the Full Spritepack when its build ID differs. The managed Core
inventory permits obsolete release files to be removed without scanning or
deleting saves, mods, settings, profiles, imported sprites, Spritepack updates,
or unknown user files.

The Full Spritepack is published as multiple GitHub release assets because the
combined archive is larger than GitHub's per-asset limit. The installer
manifest presents those assets as one logical package. Every part is
downloaded and verified independently, then Windows and Proton read the
volumes as one archive without creating a second full-size temporary copy.

`Patch Notes` opens a submenu with `View` and `Open`. `File A Bug Report`
exports
`LatestBugReport.txt` with the same paste upload flow as
`Tools -> Log Files -> Export`, copies the exported URL as a Discord-ready
`[Bug Report](url)` link, and opens the Hoenn Reloaded bug-report Discord
thread.

The pinned `Spritepacks` installed-list entry opens a downloader menu:

- `Latest`
  - `Full Spritepack`
  - latest monthly Spritepack update
- `All Files`
  - `Full Spritepack`
  - all configured monthly updates, newest first

Spritepack downloads read the public GitHub copy of
`Reloaded/Spritepacks.json` first, then fall back to the local file if the
online fetch fails. Downloads use `Reloaded::Download` to stream an archive to
a temporary `.part` file, validate optional size/SHA-256 metadata, atomically
finish the archive, then validate and extract it through `Reloaded::Archive`.
Runtime archives of at least 24 MiB use up to three simultaneous byte-range
connections when supported, with automatic single-connection fallback.
Spritepack extraction intentionally uses overwrite mode
without a second staging copy, while still rejecting unsafe archive entries.
Successful installs update a local marker at
`Mods/Reloaded/SpritepacksInstalled.json`, which lets the protected installed
list entry show whether the current Full Spritepack and latest monthly update
are installed.

The Full Spritepack is one player-facing archive containing internal Base and
Expanded components under `Graphics/SpritePacks`. Base wins duplicate logical
sprite names; Expanded supplies missing current sprites, expanded-species
sprites, icons, and cries. Existing loose sprites and active mod overrides win
over both components.

Monthly archives install sparse overlays under
`Graphics/SpritePacks/Updates/<update-id>`. They load newest-first above both
Full components. When monthly updates are compacted into a new Full archive,
the Full manifest records a cutoff and the runtime ignores included older
update layers without deleting their files.

Component archives should include the builder-generated `manifest.json`.
Every per-head `.pak` record in that manifest has an entry count, exact size,
and SHA-256. The outer Spritepack catalog row should still provide its own
optional archive `size`, `installed_size`, and `sha256`. The installer uses
`installed_size` for extraction-space preflight and checks archive size/hash
before extraction.
Downloaded packs and `Reloaded/Cache/SpritePacks` are runtime output and must
not be committed.

Published profile actions:

- `Import Profile`
- `Import & Enable Mods`

Developers can add optional extra sources through:

```text
ModDev/Sources.json
```

That file is only for development and testing. The public player source should
come from GitHub.

## Index Format

A source index may be either a raw array of mod entries or an object with a
`mods`, `entries`, or `value` array.

Mod version rows and Spritepack file rows may include:

```json
{
  "download_url": "https://example.com/example.zip",
  "sha256": "64 hexadecimal characters",
  "size": 12345678
}
```

Spritepack rows use `url` instead of `download_url`. `sha256` and `size` are
optional, but current Windows and Proton mod publishers add both automatically.
An oversized Full pack may leave `url` empty and provide an ordered `parts`
array. Each part requires its original numbered filename, URL, size, and
SHA-256.

A Full Spritepack may use verified split volumes:

```json
{
  "id": "full_spritepack_2026_08",
  "name": "Full Spritepack (August 2026)",
  "full": true,
  "updated_at": "07-17-26 21:30:00",
  "url": "",
  "size": 123456789,
  "sha256": "SHA-256 of the complete ZIP",
  "parts": [
    {
      "file": "full-spritepack.zip.001",
      "url": "https://example.com/full-spritepack.zip.001",
      "size": 100000000,
      "sha256": "SHA-256 of this part"
    },
    {
      "file": "full-spritepack.zip.002",
      "url": "https://example.com/full-spritepack.zip.002",
      "size": 23456789,
      "sha256": "SHA-256 of this part"
    }
  ]
}
```

Monthly updates remain ordinary single-archive rows:

```json
{
  "id": "spritepack_update_2026_09",
  "name": "Spritepack Update (September 2026)",
  "monthly": true,
  "latest": true,
  "updated_at": "09-01-26 12:00:00",
  "url": "https://example.com/spritepack-update-2026-09.zip",
  "size": 1234567,
  "sha256": "64 hexadecimal characters"
}
```

Spritepack archives use resumable `.part` downloads when the host supports
byte ranges. The older `components` field remains readable for compatibility,
but new Full releases should use one logical archive represented by one URL or
an ordered set of numbered volumes. Both the in-game downloader and Complete
Installer support the same `parts` records.

Recommended format:

```json
{
  "version": 1,
  "mods": [
    {
      "id": "example_mod",
      "name": "Example Mod",
      "latest_version": "1.1.0",
      "authors": ["Mod Author"],
      "description": "Short description.",
      "tags": ["gameplay"],
      "dependencies": [
        { "id": "example_library", "version": "1.0.0" }
      ],
      "changelogurl": "https://example.com/example_mod_changelog.txt",
      "versions": [
        {
          "version": "1.1.0",
          "download_url": "https://example.com/example_mod_1.1.0.zip",
          "reloaded_version": "0.5.0",
          "changelogurl": "https://example.com/example_mod_1.1.0_changelog.txt"
        },
        {
          "version": "1.0.0",
          "download_url": "https://example.com/Old%20Versions/example_mod_1.0.0.zip",
          "reloaded_version": "0.5.0",
          "changelogurl": "https://example.com/Old%20Versions/example_mod_1.0.0_changelog.txt"
        }
      ],
      "homepage_url": "https://example.com/example_mod"
    }
  ],
  "profiles": [
    {
      "id": "challenge_profile",
      "name": "Challenge Profile",
      "version": "1.0.0",
      "authors": ["Profile Author"],
      "description": "A curated set of difficulty mods.",
      "tags": ["difficulty", "gameplay"],
      "reloaded_version": "0.5.0",
      "profile_code": "RLD-code-...",
      "changelogurl": "https://example.com/challenge_profile_changelog.txt",
      "mods": [
        { "id": "example_mod", "version": "1.1.0" }
      ]
    }
  ]
}
```

`uid` is accepted as an alias for `id`.

`author` is accepted as an alias for `authors`.

`url` is accepted as an alias for `download_url`.

`dependencies` entries use mod IDs and optional minimum versions. The browser
download planner installs dependencies before the selected mod. If a dependency
is already installed at the required version or newer, it is reused instead of
downloaded again. If the dependency cannot be found in the GitHub index, or the
index has no version new enough, the UI reports that specifically. Entries that
exist in the index but do not have a `download_url` are also reported separately.

Installed `mod.json` manifests may include an optional `required_features`
array. Every listed ID must be registered and active through
`Reloaded::Features` or the Mod Manager rejects the mod before loading its
scripts. This is separate from mod-to-mod `dependencies`.

`changelogurl` may point to a raw text file for installed mod details and
published metadata.

Installed mods can also provide a local changelog file in their mod folder:

```text
Changelog.txt
changelog.txt
CHANGELOG.txt
CHANGELOG.md
Changelog.md
changelog.md
```

For installed mods, Reloaded checks `changelogurl` first, then local changelog
files, then browser index metadata.

If `versions` is present, `latest_version` decides the default download. Older
versions are kept in the same entry so the browser can expose them later without
guessing from GitHub folder names. The archive files may still physically live
in an `Old Versions` folder on GitHub.

The in-game version picker labels versions as `Latest`, `Installed`, or
`Newer` when that context is known. Installing an older version over a newer
installed version requires an extra confirmation.

Published profiles are listed under `profiles`. These replace traditional
modpacks internally. The UI may still call them modpacks for players, but the
backend treats them as profile imports.

Profiles can be marked with `featured` or `special_entry` in the GitHub index.
Those labels are admin-controlled index metadata, not normal mod tags. Featured
entries sort above special entries, and special entries sort above normal rows.
The built-in `Hoenn Reloaded` entry is always treated as featured and special.

## Archive Format

Download archives should be `.zip` files containing one or more mod folders.

Recommended archive layout:

```text
example_mod/
  mod.json
  Scripts/
  Graphics/
  Audio/
  Settings.json
```

The installer searches the extracted archive for `mod.json` files. If a mod
with the same manifest `id` already exists, the existing folder is updated.
Otherwise the extracted folder name is preserved. The manifest `id`, not the
folder name, is the stable identifier for profiles, dependencies, and browser
entries.

Installed archives must include mod manifests with `"game": "hoenn"`. Empty
values or other game IDs are rejected before scripts can load.

Archive installs are rollback-protected. Before replacing an existing mod
folder, Reloaded moves the old folder into `Mods/.ReloadedInstallBackups/`.
If extraction or copying fails, Reloaded restores the previous folder and
removes the partial install. Successful installs clean up the backup folder.

## Profile Import Downloads

When importing an `RLD-code-` profile code, missing mod IDs are resolved through
`Reloaded::ModBrowser`.

The player-facing choices are:

- `Download` - install missing mods, then import the profile with those newly
  downloaded missing mods disabled.
- `Download & Enable` - install missing mods, then import the profile normally.
- `Back` - cancel the import.

Missing profile mods are resolved through the browser index. Their own
dependencies are also planned and installed. Profile mod versions are treated as
exact requests when the index has that version; dependency versions are treated
as minimum required versions.

## Local Profiles

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

If no profile exists, Reloaded creates:

```text
Mods/Reloaded/Profiles/Default.json
```

Profile format:

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

Loading rules:

- Mods are enabled only when their `id` is listed in `enabled_mods`.
- Mods listed in `disabled_mods` are always disabled.
- `load_order` controls player-preferred ordering.
- Dependencies still load before dependents.
- Missing mod references are logged.
- Enabled mods with disabled, missing, or too-old dependencies are skipped.

Profile management API:

```ruby
Reloaded::Profiles.names
Reloaded::Profiles.list
Reloaded::Profiles.create("Testing")
Reloaded::Profiles.duplicate("Default", "Modded")
Reloaded::Profiles.rename("Testing", "Testing 2")
Reloaded::Profiles.delete("Testing 2")
Reloaded::Profiles.activate("Default")
Reloaded::Profiles.export_profile("Default", "Mods/Reloaded/DefaultExport.json")
Reloaded::Profiles.import_profile("Mods/Reloaded/DefaultExport.json")
Reloaded::Profiles.import_data(profile_hash)
```

Mod state API:

```ruby
Reloaded::Profiles.enable_mod("example_mod")
Reloaded::Profiles.disable_mod("example_mod")
Reloaded::Profiles.set_mod_enabled("example_mod", true)
Reloaded::Profiles.set_enabled_mods(["example_mod"])
Reloaded::Profiles.set_disabled_mods(["old_mod"])
```

Load order API:

```ruby
Reloaded::Profiles.set_load_order(["library_mod", "example_mod"])
Reloaded::Profiles.move_mod("example_mod", -1)
Reloaded::Profiles.ordered_mod_ids(["example_mod", "library_mod"])
```

Profile-scoped mod settings API:

```ruby
Reloaded::Profiles.set_mod_setting("example_mod", "difficulty", "Hard")
Reloaded::Profiles.mod_setting("example_mod", "difficulty", "Normal")
Reloaded::Profiles.delete_mod_setting("example_mod", "difficulty")
Reloaded::Profiles.delete_mod_settings("example_mod")
Reloaded::Profiles.delete_mod_settings
```

Mods should usually use `Reloaded::ModSettings` instead of calling profile
settings directly, because `Reloaded::ModSettings` validates values against the
mod's `Settings.json` schema.

Utility methods:

```ruby
Reloaded::Profiles.active_name
Reloaded::Profiles.active
Reloaded::Profiles.exists?("Default")
Reloaded::Profiles.summary
Reloaded::Profiles.missing_mod_ids(["example_mod"])
Reloaded::Profiles.remove_mod("example_mod")
```

## RLD Profile Codes

Profiles can be exported as share codes:

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
can download missing mods through `Reloaded::ModBrowser`.

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
- View profile counts and resolved enabled/disabled mod names.

Creating a profile from the in-game UI seeds it from the current installed mod
list.

Enabling, disabling, creating, or duplicating a profile from the in-game UI marks
the full Mod Manager as restart-required because the active loaded mod set may
change.

## API

```ruby
Reloaded::ModBrowser.refresh(fetch_remote: true)
Reloaded::ModBrowser.sources
Reloaded::ModBrowser.entries
Reloaded::ModBrowser.profile_entries
Reloaded::ModBrowser.core_entry
Reloaded::ModBrowser.spritepack_entry
Reloaded::ModBrowser.spritepack_files
Reloaded::ModBrowser.download_spritepack(Reloaded::ModBrowser.spritepack_files.first)
Reloaded::ModBrowser.entry("example_mod")
Reloaded::ModBrowser.entry_for("example_mod", "1.0.0")
Reloaded::ModBrowser.resolve_mod_ids(["example_mod"])
Reloaded::ModBrowser.build_download_plan(["example_mod"])
Reloaded::ModBrowser.download_mods(["example_mod"], enable: true)
Reloaded::ModBrowser.import_published_profile("challenge_profile")
```

## Publishing

Publishing is handled by:

```text
ModDev/Windows/Publish to GitHub.bat
ModDev/Proton/Publish to GitHub.sh
```

The in-game Mod Manager `Tools -> Publish` menu launches the publisher.

The Browser, updater, backup, publishing, folder-opening, and other desktop
actions are capability-gated through `Reloaded::Platform`. JoiPlay keeps the
installed mod/profile manager but hides unsupported desktop and download
actions. Proton uses the same player-facing manager features as Windows.

The platform publisher selects the mod or profile, validates it before
uploading, uses a sparse Git checkout for only the index and selected target
folder, updates the GitHub index, packages mods, writes profile payloads,
commits, and pushes to:

```text
Stonewallxx/Hoenn-Reloaded-Mods
```

Mods and profiles are not published through local `Mods/Reloaded/Publish`
folders.

## Admin Index Editing

Manager Editor documentation lives beside the local tool at:

```text
Admin Tools/Manager Editor/ManagerEditor.md
```

The private Spritepack release publisher is:

```text
Admin Tools/Spritepack Publisher/Publish Spritepacks.bat
```

It independently builds and verifies GitHub-sized release parts, uploads them
to the `Spritepacks` release, verifies the remote asset sizes, updates the Full
row, and publishes `Reloaded/Spritepacks.json` without cloning the public
repository. It never invokes a Core build. The Manager Editor launches this
same publisher in Catalog mode for JSON-only catalog edits.

## Current Limits

- Publisher tools require Git and GitHub credentials or collaborator access.
- Remote JSON fetches use the engine HTTP helpers.
- Mod and Spritepack archives use `Reloaded::Download`; incomplete `.part`
  files never replace completed downloads. Eligible runtime archives use up to
  three range connections across the entire game process, independently of the
  standalone installer's six-connection package downloader.
- Archive extraction uses `Reloaded::Archive` with the bundled `7z.exe` adapter;
  PowerShell extraction is avoided. ZIP, RAR, and 7Z entries are preflighted for
  traversal, links, encryption, collisions, and configured safety limits.
- The browser uses GitHub index data. If the remote index changes, opening or
  refreshing the Mod Manager fetches a fresh index instead of trusting stale
  local cache data.
