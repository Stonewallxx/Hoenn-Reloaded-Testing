# Base Game Upstream Updater

Developer-only tool for updating Hoenn Reloaded's base game files from the upstream Hoenn repository without replacing Hoenn Reloaded's `.git` folder.

## What It Does

- Clones or fetches `infinitefusion/infinitefusion-hoenn-public` into `_upstream_cache/`.
- Copies upstream base files into the Hoenn Reloaded game folder.
- Leaves Hoenn Reloaded's `.git` folder untouched.
- Excludes Reloaded/mod/user/tool folders from the copy.
- Offers to delete `_upstream_cache/` after the update.

## Protected Paths

The updater does not copy over these paths:

- `.git`
- `.gitignore`
- `Reloaded`
- `Mods`
- `ModDev`
- `ModsBackup`
- `Modders Tools`
- `Admin Tools`
- `Developer Tools`
- `Hoenn Reloaded Installer.bat`
- `PIF Hoenn Installer.bat`

## Workflow

1. Run `Update Base Game From Upstream.bat`.
2. Let it sync the upstream cache and copy files.
3. Delete the cache when prompted if you do not need it.
4. Review the changed base files in Git before committing.

This folder is intended for development only and should not be included in player builds.
