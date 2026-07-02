#======================================================
# Reloaded Browser Documentation
# Author: Stonewall
#======================================================
# Documents the Mod Browser source registry, download backend, and UI.
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
- `S` or clicking the search field starts browser search.

Footer buttons use the shared Mod Manager footer system. The browser page
currently has a right-most `Back` footer button; downloads and imports are
handled from the selected entry's action menu.

Mod actions:

- `Download`
- `Download & Enable`
- `Versions`
- `View Changelog`, when `changelogurl` is configured

Published profile actions:

- `Import Profile`
- `Import & Enable Mods`
- `View Changelog`, when `changelogurl` is configured

Developers can add optional extra sources through:

```text
Modders Tools/Sources.json
```

That file is only for development and testing. The public player source should
come from GitHub.

## Index Format

A source index may be either a raw array of mod entries or an object with a
`mods`, `entries`, or `value` array.

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
      "dependencies": [],
      "changelogurl": "https://example.com/example_mod_changelog.txt",
      "versions": [
        {
          "version": "1.1.0",
          "download_url": "https://example.com/example_mod_1.1.0.zip",
          "reloaded_version": "0.1.0",
          "changelogurl": "https://example.com/example_mod_1.1.0_changelog.txt"
        },
        {
          "version": "1.0.0",
          "download_url": "https://example.com/Old%20Versions/example_mod_1.0.0.zip",
          "reloaded_version": "0.1.0",
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
      "reloaded_version": "0.1.0",
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

`changelogurl` may point to a raw text file. The Mod Browser exposes it through
`View Changelog` and displays the text in the right panel with scrolling.

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

Published profiles are listed under `profiles`. These replace traditional
modpacks internally. The UI may still call them modpacks for players, but the
backend treats them as profile imports.

Profiles can be marked with `featured` or `special_entry` in the GitHub index.
Those labels are admin-controlled index metadata, not normal mod tags. Featured
entries sort above special entries, and special entries sort above normal rows.

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

## Profile Import Downloads

When importing an `RLD-code-` profile code, missing mod IDs are resolved through
`Reloaded::ModBrowser`.

The player-facing choices are:

- `Download` - install missing mods, then import the profile with those newly
  downloaded missing mods disabled.
- `Download & Enable` - install missing mods, then import the profile normally.
- `Back` - cancel the import.

## API

```ruby
Reloaded::ModBrowser.refresh(fetch_remote: true)
Reloaded::ModBrowser.sources
Reloaded::ModBrowser.entries
Reloaded::ModBrowser.profile_entries
Reloaded::ModBrowser.entry("example_mod")
Reloaded::ModBrowser.entry_for("example_mod", "1.0.0")
Reloaded::ModBrowser.resolve_mod_ids(["example_mod"])
Reloaded::ModBrowser.download_mods(["example_mod"], enable: true)
Reloaded::ModBrowser.import_published_profile("challenge_profile")
```

## Publishing

Publishing is handled by:

```text
Modders Tools/Publish to GitHub.bat
```

The in-game Mod Manager `Tools -> Publish` menu launches the publisher.

The batch file selects the mod or profile, validates it before uploading, uses
a sparse Git checkout for only the index and selected target folder, updates the
GitHub index, packages mods, writes profile payloads, commits, and pushes to:

```text
Stonewallxx/Hoenn-Reloaded-Mods
```

Mods and profiles are not published through local `Mods/Reloaded/Publish`
folders.

## Admin Index Editing

Admin-only index editing lives outside the shipped player files:

```text
Admin Tools/
Admin Tools/Admin.txt
Admin Tools/Manager Editor/ManagerEditor.rb
```

When `Admin.txt` and the Manager Editor are present, the in-game Mod Manager
shows `Tools -> Admin Tools -> Manager Editor`.

The Manager Editor edits the sparse GitHub index checkout used by the publisher.
It can save the local index, pull the latest index, push index changes, edit
entry fields, and toggle admin-only `Featured` / `Special` placement.

## Current Limits

- Publisher tools require Git and GitHub credentials or collaborator access.
- Remote JSON fetches use the engine HTTP helpers.
- Mod archive downloads use `pbDownloadToFile`.
- Archive extraction uses `7z.exe`; PowerShell extraction is avoided so the
  browser does not trip Windows malicious-command warnings.
- The browser uses GitHub index data. If the remote index changes, opening or
  refreshing the Mod Manager fetches a fresh index instead of trusting stale
  local cache data.
