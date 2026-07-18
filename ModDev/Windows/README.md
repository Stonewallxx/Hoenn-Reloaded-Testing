# Windows ModDev Tools

`Publish to GitHub.bat` is the Windows publisher for Hoenn Reloaded mods and
profiles. It requires Git and uses GitHub CLI authentication when available,
falling back to existing Git credentials.

The tool creates a shallow sparse checkout under the Windows temporary folder
for the current publish only. It removes that checkout when the publisher
closes, so players and modders do not retain a GitHub repository cache.

`Run Foundation Checks.bat` runs the standalone foundation and release
regression suite. It checks framework behavior, load order, Ruby syntax,
required public files, documentation references, changelog structure, platform
capability policy, and generated-file tracking. It requires Ruby and Git.
