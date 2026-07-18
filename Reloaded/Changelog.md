
-----------------------------------
  v1.0.0 - Initial Release
  7-5-26
-----------------------------------

Features
-----------
- Added the Reloaded framework.
-- Adds the core systems that power Reloaded features, settings, logging,
   profiles, mod support, and save data.
- Added the in-game Mod Manager.
-- Supports installed mods, profiles, mod settings, dependency/conflict details,
   changelog viewing, updates, and admin tools.
- Added the Mod Browser.
-- Uses the Hoenn Reloaded Mods GitHub index for mod downloads, versions,
   dependencies, and published profile imports.
- Added a protected Hoenn Reloaded entry.
-- Pinned above normal mods in the browser and installed list.
-- Supports update status, Patch Notes view/open, and Open Mods Folder.
- Added Reloaded Mart.
-- Custom buy/sell UI with favorites, daily featured rows, promo codes,
   services, and animated boxes.
-- Supports PokeDollars, Coins, Battle Points, Quest Points, Glimmer Coins,
   and mod-registered purchase currencies.
-- Bundles, gifts, and Mystery Boxes can grant any shared reward type,
   including fully configured Pokemon and atomic multi-reward outcomes.
-- Mystery Boxes show possible contents by rarity without exposing exact odds,
   and persist the selected result through a per-save transaction ledger.
-- Curated offers require a fresh online catalog; generated Daily Featured
   offers remain available offline.
- Added Reloaded Mart Editor.
-- Local Admin Tools editor for entries, categories, services, promo codes,
   target tags, affected entries, dates, times, and publishing.
-- Added typed reward creation, Pokemon distribution controls, entry versions,
   bundle-value checks, and Mystery Box expected-value checks.
- Added TM Vault.
-- Supports TM/HM browsing, relearn flows, filters, type icons, and PokeNav
   integration.
- Added Overworld Menu.
-- Supports Quick Items, Quick Save, Repel Counter, Time Changer, page editing,
   page renaming, left/right pages, and modder-registered entries.

Improvement
-----------
- Made Mod Manager and Mod Browser feature/special rows sort above normal rows.
- Made Mod Browser installs resolve dependency chains and report missing,
  mismatched, or unavailable downloads clearly.
- Improved Reloaded Mart performance on large catalogs and lower-end machines.
- Improved Overworld Menu customization with save-specific ordering, page names,
  page switching, and wrapped top/bottom navigation.
- Made Mod Manager search bars click-only.

Bugfixes
-----------
- Fixed Reloaded Mart daily featured rows after online catalog changes.
- Fixed promo-code input crashing or closing unexpectedly.
- Fixed promo-code targeting and active discount application.
- Fixed Fast Hatch so payment and money audio happen before egg animation.
- Fixed Overworld Menu Repel Counter visibility when no repel is active.

Visuals & UI
-----------
- Added green pricing and a PROMO badge for promo-discounted mart rows.
- Added promo-code remaining time text to the promo-code popup.
- Added bundle, gift, and mystery box box animations.
- Updated Reloaded Mart quantity UI for 9999 max quantities.
- Added picker UI for Reloaded Mart Editor date/time fields.
- Added Shift+Enter multiline description editing in the mart editor.
- Added MM-style Overworld Menu Page Options popup.
- Added gold picked-up reorder cursor and custom page-name headers.

Performance & Audio
-----------
- Improved Reloaded Mart list scrolling, sorting, and info-panel redraw speed.
- Moved Fast Hatch money-spent audio to the moment money is deducted.

Debug & Modding
-----------
- Made Hoenn Reloaded a protected virtual entry instead of a normal mod folder.
- Added manifest validation for mod IDs, versions, authors, tags, dependencies,
  incompatibilities, settings, and system tags.
- Added ModDev scanning through Reloaded/Settings.txt.
- Added optional development browser sources through ModDev/Sources.json.
- Added rollback protection for archive installs.
- Added Reloaded::ModBrowser.core_entry for the Hoenn Reloaded pinned entry.
- Added public APIs for logging, events, patches, save data, settings, assets,
  data patches, mart services, and Overworld Menu entries.
- Kept base-file edit notes in Reloaded/Documentation/VanillaChanges.md.
