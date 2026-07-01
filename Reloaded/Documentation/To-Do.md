#======================================================
# Reloaded To-Do
# Author: Stonewall
#======================================================
# Living backlog for deferred Hoenn Reloaded work.
#
# Responsibilities:
#   - Track work that should be done later but is not blocking now.
#   - Record system ideas that need more design before implementation.
#   - Keep deferred logging, modding, and compatibility tasks visible.
#   - Update as Reloaded systems are created, changed, or completed.
#
#======================================================

This file tracks Reloaded work that is intentionally deferred.

Update it whenever a useful task is discovered but should not be handled
immediately.

## Logging

- Add in-game settings for changing `Reloaded/LogMode.txt`.
- Add mod loader-specific logging once the mod loader exists.
- Improve bug report exports after mod metadata, dependency checks, and load
  order are implemented.
- Consider log rotation or cleanup if generated logs become too large.

## Modding Documentation

- Add mod folder format once finalized.
- Add mod metadata format once finalized.
- Add dependency rules once finalized.
- Add load order rules once finalized.
- Add compatibility guidelines after patch/data systems mature.

## Events

- Add event names as official vanilla bridge points are created.
- Document event context payloads for each public event.
- Add examples for common modding use cases.

## Patches

- Register patch points whenever Reloaded systems alter vanilla behavior.
- Add stronger conflict rules after the mod loader and load order rules exist.
- Consider helper APIs for safe method wrapping after the registry proves useful.

## Future Systems

- Mod loader.
- Mod metadata parser.
- Dependency validator.
- Load order resolver.
- Data patching system.
- Asset override system.
- In-game Reloaded settings menu.
