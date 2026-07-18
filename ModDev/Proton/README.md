# Proton ModDev Tools

`Publish to GitHub.sh` is the Steam Deck/Proton publisher for Hoenn Reloaded
mods and profiles. Run it from Desktop Mode or launch it through the in-game
Mod Manager when a supported terminal is installed.

Requirements:

- Git
- Python 3
- One supported terminal: Konsole, xterm, or GNOME Terminal
- Existing GitHub write authentication for `Stonewallxx/Hoenn-Reloaded-Mods`

The publisher creates a shallow sparse checkout under the system temporary
directory for the current publish only. It validates the selected content,
packages mods with Python's ZIP support, updates `index.json`, commits, pushes,
and removes the temporary checkout when it closes.

JoiPlay does not expose these external publishing tools.

`Run Foundation Checks.sh` runs the same standalone foundation and release
regression suite as Windows. It checks framework behavior, load order, Ruby
syntax, required public files, documentation references, changelog structure,
platform capability policy, and generated-file tracking. It requires Ruby and
Git in Desktop Mode.
