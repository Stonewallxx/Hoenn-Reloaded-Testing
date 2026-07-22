# Windows Foundation Checks

Private Windows maintainer checks live in this folder. Player-facing Mod and
Profile repository tools ship under `ModDev/Tools/Windows/` and use GitHub CLI
without a repository checkout.

`Run Foundation Checks.bat` runs the standalone foundation and release
regression suite. It checks framework behavior, load order, Ruby syntax,
required public files, documentation references, changelog structure, platform
capability policy, and generated-file tracking. It requires Ruby and Git.
