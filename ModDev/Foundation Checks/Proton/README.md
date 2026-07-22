# Proton Foundation Checks

Private Proton maintainer checks live in this folder. Player-facing Mod and
Profile repository tools ship under `ModDev/Tools/Proton/` and use GitHub CLI
without a repository checkout. JoiPlay does not expose these external tools.

`Run Foundation Checks.sh` runs the same standalone foundation and release
regression suite as Windows. It checks framework behavior, load order, Ruby
syntax, required public files, documentation references, changelog structure,
platform capability policy, and generated-file tracking. It requires Ruby and
Git in Desktop Mode.
