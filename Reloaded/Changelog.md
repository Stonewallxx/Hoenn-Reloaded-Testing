-----------------------------------
  v0.9.4 - Pre-Release
  7-19-26
-----------------------------------

Features
-----------
- Added the Reloaded framework and explicit runtime load order.
-- Provides shared settings, logging, validation, save protection, migrations,
   feature flags, events, patches, assets, Data Patches, and mod APIs.
- Added the Reloaded Pause Menu and categorized Options system.
-- Action pages include Reloaded UI, Controls, Reloaded Bag, IV Boundaries,
   PokeVial, and other installed Reloaded modules.
- Added the in-game Mod Manager, Mod Browser, and Profiles.
-- Supports installed mods, dependencies, incompatibilities, versions, updates,
   mod settings, profile codes, changelogs, and published profile imports.
-- Hoenn Reloaded and Spritepacks are protected pinned entries rather than
   removable normal mods.
- Added the Reloaded Bag for field and battle use.
-- Supports remembered pockets/items, favorites, NEW and HELD badges, default,
   alphabetical, quantity, type, and custom sorting, per-pocket autosort, TM
   move/type details, and Quick Item integration.
- Added the Reloaded Pokemon Stats page.
-- Shows actual stats, IVs, EVs, species base stats, totals, abilities,
   weaknesses, Hidden Power, friendship, and Fuse-Type information.
-- Players can choose Standard or Reloaded summary presentation.
- Added Reloaded Mart.
-- Supports buying and selling with PokeDollars, Coins, Battle Points, Quest
   Points, Glimmer Coins, and registered mod currencies.
-- Supports favorites, featured offers, services, bundles, gifts,
   Mystery Boxes, multiple reward types, and offline Daily Featured offers.
- Added TM Vault.
-- Supports TM/HM browsing, party compatibility, move relearning, filters,
   sorting, type icons, egg-move indicators, and PokeNav access.
- Added the customizable Overworld Menu.
-- Supports multiple named pages, Quick Items, Quick Save, Repel Counter, Time
   Changer, PokeVial, and mod-registered entries.
- Added the PokeVial module.
-- Supports charges, real-time cooldowns, Pokemon Center refills, progression
   upgrades, recharge/refill items, rewards, and mod callbacks.
- Added optional Pause Menu Pokemon Storage access.
-- Opens directly to the full Pokemon Storage experience on configured maps.
- Added IV Boundaries for newly generated Pokemon.
-- Wild, gift, static, and Egg IVs roll inside the selected player boundaries.
-- Trainer boundaries are difficulty-controlled and support class exemptions.
- Added per-Pokemon Hidden Power types.
-- New Pokemon receive a stored random type from the configured type list.
- Added packed Spritepacks and Sprite Import.
-- The Full Spritepack contains Base and Expanded sprites without requiring
   millions of loose installed files.
-- Monthly overlays load above the Full pack, while loose mod/import sprites
   keep priority.
- Added the unified Windows and Proton installer.
-- Installs Public or Testing Core with optional Spritepacks into the installer's
   directory and supports resumable multi-connection downloads.
-- JoiPlay receives a separate complete Public ZIP with the Full Spritepack.
- Added shared reward support for Mart, Mystery Gift, events, and mods.
-- Supports items, currencies, PokeVial uses/refills, Pokemon, outfits, TM Vault
   moves, unlocks, choices, weighted rolls, and atomic reward groups.

Improvement
-----------
- Integrated Hoenn-Clean Update 1.2 through upstream commit `bf07940`.
-- Preserved Reloaded's bootstrap, Sprite Import, expanded economy/Bag limits,
   Options safety guard, and untradeable distribution Pokemon protections.
- Removed Reloaded Mart Promo Codes and their catalog/editor support.
- Reloaded Mart manual refresh now uses `Refresh (Z)`.
- Changed Hidden Power to use each Pokemon's stored type instead of deriving
  its type from IVs; normal battle damage calculations are retained.
- Made IV Boundaries roll each new IV inside its range rather than clamping an
  already generated value.
- Added Level Learned sorting to TM Vault relearn lists and made every relearn
  mode respect the selected sort.
- Improved Reloaded Mart responsiveness for large catalogs and lower-end
  systems.
- Simplified the Reloaded Mart Editor into Content, Categories, Automation &
  Events, Appearance, and Test & Publish workflows.
-- Category pages now show and edit their assigned content directly, while all
   content creation, duplication, and deletion stays under Content.
-- Content entries are automatically separated into type pages instead of
   requiring a manual filter.
-- New item entries begin with the selected GameData item's standard
   description and default buy/sell prices unless they are customized.
-- Entry section rows preview their current fields in the right panel, and
   field-only sections open their full editor directly.
-- Basic Info previews the complete wrapped item description in the right
   panel instead of shortening it to a one-line field value.
-- Content entries can be copied between Online Catalog and Offline Base Stock
   without recreating their fields, rewards, or categories.
-- Empty stock, purchase-limit, schedule, and difficulty fields now show their
   actual unlimited or unrestricted meaning instead of `Not set`.
-- Existing detailed automation, metadata, preset, export, and raw tools remain
   available from the editor's Advanced Tools menu during the rebuild.
- Added editable Offline Base Stock for Reloaded Mart.
-- The shipped base catalog opens immediately without a connection, while a
   fresh validated online catalog replaces it in full instead of merging.
-- The Mart Editor can switch between Online Catalog and Offline Base Stock and
   prevents the base target from being exported or published online.
- Reloaded Mart price-change badges now compare active modifier results against
  the configured Mart price, so custom base prices are not mislabeled as
  discounts or markups relative to vanilla marts.
- Improved NumberPicker navigation for large values.
-- Generic editor values now use Kanto Reloaded's digit picker UI and behavior.
-- Mart and Bag quantity and confirmation popups retain their previous Reloaded
   layouts, price previews, and step controls.
- Rebuilt Daily Featured as a dedicated Reloaded Mart automation.
-- Generates deterministic offers per Eastern calendar day with configurable
   0-100% discount bounds, a configurable 40%+ offer limit, and a three-day
   no-repeat schedule.
-- Excludes mod-added items, curated Featured entries, and items with active
   catalog discounts from automatic selection, with a trusted code-side
   allowlist for Hoenn Reloaded Data Patch additions.
-- Added owner exclusions and a Mart Editor Preview Today report.
-- Added a per-save trusted HTTP timestamp anchor so Daily Featured cannot move
   backward while offline after a successful catalog refresh.
- Added a dedicated Featured Items page to Mart Editor Content and preserved
  the previous page cursor/scroll when backing out of nested editor pages.
- Removed shadows from Reloaded Mart banners, descriptions, Stock text, and
  restock-time text.
- Fixed the Mart Editor failing to open when its mouse handler referenced
  undefined list geometry constants.
- Hardened Mart Editor exit handling so Back input cannot carry into the Mod
  Manager, and fixed valid JSON `null` values in Offline Base Stock loading.
- Fixed Test in Game rendering behind the still-open Mod Manager by temporarily
  raising the Reloaded Mart preview viewport.
- Fixed Reloaded Mart remote-cache verification for catalogs containing
  non-ASCII text.
- Fixed Daily Featured stock editing to begin at 0 and treat 0 as unlimited,
  removed Profile Tuning from Mart Editor navigation, and made Test in Game
  expose its working catalog.
- Added manual Reloaded Mart catalog refresh on `X`; the open Mart rebuilds
  after completion even when the catalog version is unchanged.
- Removed the catalog-wide Mart Automation switch so each automated system
  follows its own enabled state or configured data.
- Made Mod Browser installs resolve dependency chains and report unavailable,
  incompatible, or mismatched dependencies clearly.
- Added background refreshes so Reloaded Mart and Mod Browser scenes can open
  while online data is being checked.
- Added protected download, archive, and install recovery.
-- Large downloads use resumable `.part` files, optional size/SHA-256 checks,
   cooperative cancellation, and atomic completion.
-- Interrupted desktop installs force Repair on the next installer launch and
   block the game from loading a known incomplete Core.
- Added conservative cleanup for abandoned download, extraction, publishing,
  and cache files without deleting installed content.
- Added Windows, Proton/Steam Deck, and JoiPlay capability handling.
-- Unsupported desktop functions are hidden on JoiPlay while gameplay and
   compatible manually installed mods remain available.
- Improved Overworld Menu customization with save-specific ordering, wrapped
  navigation, page names, and remembered state.
- Consolidated Full, Separate, and Catalog Spritepack publishing behind one
  Admin Tool.

Bugfixes
-----------
- Fixed backing out of Reloaded Mart Editor from the standalone Admin Tools
  launcher trying to redraw uninitialized Mod Manager scene sprites.
- Changed Reloaded Mart Editor item selectors to omit redundant bracketed item
  IDs and show TM/HM move names directly in the list.
- Changed Foundation Checks to validate only the manually maintained
  `VanillaChanges.md` paths instead of requiring temporary update-import data.
- Fixed Foundation release checks treating generated installer manifests as
  missing source files.
- Fixed the Spritepack Publisher failing while calculating multipart upload
  size from freshly built metadata.
- Fixed Relearn Moves ignoring the active TM Vault sorting mode.
- Fixed Reloaded Mart reward checks incorrectly reporting that every Bag item
  was full.
- Fixed large Reloaded Mart bundles appearing to freeze during maximum-quantity
  checks.
- Fixed inactive Reloaded Mart entries remaining purchasable, Unlock entries
  charging without setting state, and nested missing reward items escaping
  catalog validation.
- Expanded the Reloaded Mart Editor's guided reward workflows and made invalid
  Mystery Box chance lists block catalog activation/export.
- Fixed the Reloaded Mart master Automation switch not controlling Daily
  Featured generation.
- Fixed promo-code entry, targeting, discounts, and active-time handling.
- Fixed Fast Hatch charging and audio order before the Egg animation.
- Fixed Reloaded Bag toss confirmation and quantity handling.
- Fixed Back in the Autosort pocket chooser opening Key Items instead of
  leaving the chooser.
- Fixed stale Developer Options rows raising errors after Debug was disabled.
- Fixed starter selection crashing when the optional sprite credits file was
  unavailable.
- Fixed Mod Browser entries disappearing after refreshes or downloads.
- Fixed older-version mod downloads installing the latest listed version.
- Fixed Mod Manager uninstall getting stuck on stubborn empty folders.
- Fixed Manager Editor and Spritepack data failing on JSON null values.
- Fixed Manager Editor text fields, Backspace handling, URL paste, and wrapped
  Spritepack labels.
- Fixed bug-report exports omitting severe log lines or showing incorrect
  counts and unknown startup versions.
- Fixed normal game exits being logged as Mod Manager failures.

Visuals & UI
-----------
- Added shared HR popups and Toasts with rounded pulsing cursors, cursor-color
  support, mouse input, consistent Back handling, and no background input bleed.
- Added a shared Controls Toast and standardized `Controls (Y)` access across
  Reloaded scenes.
- Added shared full-screen List, Number, Game Data, Form, Action Menu, Text
  Input, and Progress interfaces.
- Added type-colored TM/HM rows and icons across Reloaded Bag and TM Vault.
- Added egg icons beside Egg Moves in TM Vault relearn lists.
- Added rarity, NEW, HELD, MAX, featured, and item-status treatments
  where supported.
- Added the Reloaded Stats background, scalable Pokemon presentation, type
  information, ability descriptions, and compact footer.
- Reduced shadow text across Reloaded popups, hints, lists, descriptions, and
  status panels.

Performance & Audio
-----------
- Moved network refreshes, downloads, extraction, exports, backups, and
  publishing preparation away from the rendering loop.
- Added packed on-demand sprite materialization to reduce installed loose-file
  count and improve distribution/install performance.
- Added bounded caches and last-known-good remote data to avoid unnecessary
  repeated downloads.
- Improved Reloaded Bag Give flow by reusing prepared party assets.
- Improved Reloaded Mart list scrolling, sorting, and info-panel redraws.
- Moved Fast Hatch money audio to the moment payment is deducted.

Debug & Modding
-----------
- Added stable APIs for Archive, Download, Events, File Actions, Form, Game Data
  Picker, List Picker/State, Number Picker, Patches, Progress Window, Remote
  Data, Rewards, Save Data, Settings, Task, Text Input, Toasts, and validation.
- Added API contracts that classify stable, compatibility, developer, and
  internal integration surfaces.
- Added owned registries, duplicate protection, validation, and inspection for
  systems, features, rewards, event contracts, patches, and remote sources.
- Added save metadata, sequential Reloaded/mod migrations, newer-schema write
  protection, verified migration backups, and rolling save backups.
- Added event-handler failure isolation so one repeatedly failing mod callback
  is disabled without taking down unrelated handlers.
- Added Data Patch support for items, moves, abilities, species, trainers,
  encounters, quests, trainer types, and outfits.
- Added modder APIs for PokeVial, IV Boundaries, TM Vault, Reloaded Mart,
  Overworld Menu, options, abilities, and registered rewards.
- Added ModDev template generation, manifest validation/fixing, log exports,
  backups, and Foundation release checks for Windows and Proton.
- Updated generated mod templates with syntax-checkable examples for Form,
  RemoteData, Task, Download, Archive, and Rewards.
- Kept all base-game file edits documented in
  `Reloaded/Documentation/VanillaChanges.md`.
