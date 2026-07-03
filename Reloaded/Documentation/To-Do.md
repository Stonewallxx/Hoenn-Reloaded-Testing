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

- Continue tightening mod loader/browser/profile logging as new UI actions are
  added.
- Improve bug report exports with compact Mod Manager profile, browser source,
  and latest validation summaries.
- Consider log rotation or cleanup if generated logs become too large.

## Modding Documentation

- Add dependency rules once finalized.
- Add compatibility guidelines after patch/data systems mature.

## Events

- Add event names as official vanilla bridge points are created.
- Document event context payloads for each public event.
- Add examples for common modding use cases.

## Save Data

- Add migration helpers if the Reloaded save bucket schema needs to change.
- Add examples after real mods begin storing persistent data.
- Decide whether any Reloaded settings should be global files, per-save data, or
  both.

## Options

- Decide whether the Mod Manager also needs a title-screen entry after the
  Options entry is stable.

## Patches

- Register patch points whenever Reloaded systems alter vanilla behavior.
- Consider helper APIs for safe method wrapping after the registry proves useful.
- Expand real compatibility rules as more third-party mods register patch
  metadata.

## Future Systems

- Publisher script fields for custom author overrides, description, tags,
  changelog, and download URL fields.
- Per-mod settings preset/share-code design and UI.
- Data patch follow-up targets:
  - Species forms, after forms need mod support.
  - Quests, after the quest data model is reviewed.
  - Direct event/map edits, only after a safe map/event patch format is designed.
  - New trainer type asset workflow, including required graphics/audio checks.
- Economy/Reloaded Mart system for shop behavior and mart stock.
- Direct `Bitmap.new` asset redirect review if needed.
- Dedicated Profile page load order editor, if the installed-list Load Order
  mode proves too limited.
- Mod Browser polish: richer changelog display, better source failure messages,
  and clearer installed/update states.
- Remaining Modders Tools from the reference folder, reviewed and rebuilt only
  where they still fit the new Reloaded foundation.
