# Hoenn Reloaded ModDev Tools

This folder contains the player-facing Mod and Profile repository tools shipped
with Hoenn Reloaded.

```text
ModDev/Tools/
  Windows/
    Publish.bat
    Update.bat
    Delete.bat
  Proton/
    Publish.sh
    Update.sh
    Delete.sh
```

Each launcher asks whether it should operate on a Mod or Profile when that
choice was not supplied by the in-game Mod Manager. `Publish`, `Update`, and
`Delete` are separate tools so repository changes are always explicit.

Publish selects local content. It creates the first persistent release for a
new ID or adds/replaces a version asset for an existing ID owned by the current
GitHub account. Update never reads or packages local content. It lists only
owned online entries and edits their display name, authors, description, tags,
changelog URL, and homepage URL in `index.json` and the release page.

The tools require GitHub CLI authentication. They use the GitHub API directly,
do not clone or retain a repository cache, and remove temporary package files
after each run.

Each Mod or Profile owns one persistent GitHub release. Versioned assets remain
under that release, while its title shows the display name and latest version.
Publishing another version, Update, and Delete are restricted to the GitHub
account that first published the entry or the repository owner.

Private release and framework checks are maintained separately under
`ModDev/Foundation Checks/` and are not included in player packages.
