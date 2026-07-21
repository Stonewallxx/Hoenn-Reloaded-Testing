#======================================================
# Reloaded Mart Documentation
# Author: Stonewall
#======================================================
# Permanent reference for the Reloaded Mart system.
#
# Responsibilities:
#   - Document the online catalog schema and normalized backend.
#   - Document buy/sell UI controls and transaction behavior.
#   - Document events, save state, and vanilla mart integration.
#   - Document mod-added item compatibility rules.
#
#======================================================

Reloaded Mart is implemented in:

```text
Reloaded/Modules/ReloadedMart/Backend.rb
Reloaded/Modules/ReloadedMart/Automation/DailyFeatured.rb
Reloaded/Modules/ReloadedMart/Automation/EconomyEvents.rb
Reloaded/Modules/ReloadedMart/UI.rb
Reloaded/Modules/ReloadedMart/Services.rb
```

`Backend.rb` owns catalog loading, validation, pricing, availability,
stock, limits, inventory transactions, stats, events, and save data.

`UI.rb` owns the REX buy/sell screens and the vanilla
`pbPokemonMart` wrapper.

## Entry Points

Standalone Reloaded Mart:

```ruby
pbOpenReloadedMart
ReloadedMart.open
```

The Reloaded Pause Menu opens `ReloadedMart.open`.

Vanilla NPC marts still call:

```ruby
pbPokemonMart(stock, speech_welcome = nil, cantsell = false, speech_bye = nil, speech_what_else = nil)
```

Reloaded wraps this method at runtime and routes it through the REX UI while
preserving vanilla stock, custom mart prices, dialogue, and `cantsell`.

## Options

Reloaded Mart adds one action button in the `RELOADED` category:

```text
Reloaded Mart
```

That button opens the Reloaded Mart options submenu:

```text
Remove Confirm Prompt: Off / On
Box Animation: Off / On
```

Defaults:

```text
Remove Confirm Prompt: Off
Box Animation: On
```

When On, purchase and sale confirmation prompts are skipped for Reloaded Mart
and the REX vanilla mart wrapper. Quantity selection still appears unless the
Mart UI's Quick Buy toggle is On.

`Box Animation` controls Mystery Box and bundle chest animations. When Off,
Mystery Boxes and bundles use the simpler text result popup after purchase.

Chest animation assets live in:

```text
Reloaded/Graphics/Boxes/bundle.png
Reloaded/Graphics/Boxes/mysterybox.png
```

Each file is a 6-frame horizontal sprite sheet. The expected frame size is
48x32 pixels, for a total sheet size of 288x32 pixels. If a sheet is missing,
the UI falls back to the built-in drawn chest animation.

## Catalog Loading

The standalone Reloaded Mart has a shipped offline catalog and a separate
online catalog.

On open:

- `Reloaded/ReloadedMartBase.json` loads immediately.
- The mart opens from that base stock and refreshes through `Reloaded::Task`.
- Every online fetch uses a cache-busted URL.
- Only a valid, freshly confirmed online response replaces the base catalog.
- Replacement is complete. Base and online entries are never merged.
- Failed requests and cached RemoteData responses leave the current base
  catalog active. A failed open-time refresh does not discard a fresh catalog
  that was already confirmed during the current session.
- Last-good online data is retained for metadata and diagnostics but never
  exposes expired curated offers while offline.
- Daily Featured remains available against the active base catalog and uses
  its built-in defaults until a fresh catalog arrives.

The current online URL is:

```ruby
ReloadedMart::ONLINE_CATALOG_URL
```

The shipped base path is:

```ruby
ReloadedMart::BASE_CATALOG_RELATIVE_PATH
```

The Admin-only Reloaded Mart Editor can switch between `Online Catalog` and
`Offline Base Stock`. Base stock is saved directly to the shipped JSON and
cannot be exported or published as the online payload.

Content entries expose `Copy to Online` or `Copy to Offline` based on the
current catalog. Copying preserves the complete entry and adds any missing
category definitions. An existing destination entry with the same stable ID
must be explicitly replaced. Offline copies use `offline_allowed`; online
copies use `fresh_required`.

## Catalog Versions

`schema_version` tracks JSON structure compatibility.

`catalog_version` tracks content releases. It is used for cache metadata,
stock reset rules, transaction stats, and NEW! badge tracking.

The Mart Editor manages catalog versions automatically. Online versions use
`MM.DD.YY vN`. The first changed save on a new day becomes that day's `v1`;
additional changed saves on the same day increment the revision. Offline Base
Stock uses `base-N`. Saving without a meaningful content change preserves the
current version while still refreshing `generated_at`.

Each entry also has an automatically managed `entry_version`. New and copied
entries start at 1. Editing that stable entry's content increments its version;
reordering unrelated entries or changing another entry does not. Catalog and
entry version fields are read-only in the normal editor and are corrected
during save/export even if raw JSON changed them manually.

Supported schema version:

```ruby
ReloadedMart::SCHEMA_VERSION
```

## Admin Editor Workflow

The Admin-only editor's normal root is:

```text
Catalog Source
Content
Categories
Automation & Events
Appearance
Test & Publish
```

Create catalog entries only through `Content`. Category pages organize and
edit assigned entries but do not create duplicates of the creation workflow.
`Automation & Events` owns Daily Featured, reusable Economy Event templates,
the shipped Automated pool, and Curated/Themed drafts. Only the active
Curated/Themed winner is included in an online export.

The normal release flow is `Save Draft`, `Test in Game`, then `Publish
Catalog`. Publish saves the working catalog, blocks on validation errors,
writes the runtime-only `ReloadedMartOnline.json`, and launches
`PublishReloadedMart.bat`. Offline Base Stock can be saved and previewed but
cannot be exported or published as online data. Advanced Tools is limited to
metadata, presets, raw JSON, currency reference, export instructions, and
local file operations.

## Catalog Schema

Top-level fields:

```json
{
  "schema_version": 2,
  "catalog_version": "07.20.26 v1",
  "generated_at": "2026-07-04T12:00:00Z",
  "stock_epoch": "summer_2026",
  "banner": {
    "active": true,
    "text": "Summer sale is live!"
  },
  "banners": {
    "reloaded_buy": { "active": true, "text": "Reloaded Mart sale!" },
    "reloaded_sell": { "active": true, "text": "Bonus sell event!" },
    "vanilla_buy": { "active": true, "text": "Local marts are discounted!" },
    "vanilla_sell": { "active": true, "text": "Local marts pay extra!" }
  },
  "categories": [
    { "id": "featured", "name": "FEATURED", "tags": ["featured"] }
  ],
  "economy_events": [],
  "daily_featured": {
    "enabled": true,
    "count": 3,
    "discount_min_percent": 5,
    "discount_max_percent": 50,
    "high_discount_limit": 1,
    "category_id": "featured",
    "category_name": "FEATURED",
    "pool": "game_items",
    "blacklist": ["MASTERBALL", "RARECANDY"]
  },
  "entries": []
}
```

The loader also migrates the old reference-style mart preset shape into the
normalized schema.

Promo Codes and Profile Tuning are not part of the current schema or pricing
pipeline. The editor removes those legacy keys when an older working catalog
is loaded and saved.

`banner` is the standalone Reloaded Mart buy banner. Use `banners` for
page-specific banners. Supported keys include `reloaded_buy`, `reloaded_sell`,
`vanilla_buy`, `vanilla_sell`, `regular_buy`, and `regular_sell`. Sell pages do
not inherit the top-level Reloaded buy banner. The daily featured item is shown
as a row badge, not appended to the banner ticker.

`daily_featured` generates deterministic Featured rows from the base game's
item pool. The same `catalog_version` and Eastern calendar day produce the same
items for every player. The schedule uses disjoint item groups to prevent an
item from repeating during the previous three days when the eligible pool can
supply four full rotations.

Key items, TMs/HMs/TRs, important/untossable items, 0-price items, mod-added
items, the built-in owner blacklist, online `blacklist` entries,
curated Featured items, and catalog items with an active discount are excluded.
The runtime identifies additions from Data Patch ownership and by comparing the
active item registry with the compiled base `Data/items.dat`. Trusted
Hoenn Reloaded additions can be admitted by adding their item IDs to
`ADDED_ITEM_ALLOWLIST` near the top of `DailyFeatured.rb`; this does not bypass
the other eligibility filters. Other mod-added items can still be curated
explicitly as normal online catalog entries.

Generated discounts are deterministic and configurable from 0-100% off.
`high_discount_limit` controls how many of the day's generated offers may
receive a discount of 40% or more. All remaining offers are capped at 39%.
When a configured minimum is 40 or higher, it applies to the selected 40%+
offers; remaining offers still use the standard 0-39% range.

A successful online catalog response also supplies the trusted HTTP server
timestamp used by Daily Featured. The timestamp and its local observation point
are stored per save. In-session elapsed time uses a monotonic clock, and offline
time cannot move backward past the last recorded Daily Featured day. A later
successful online response is authoritative and corrects the clock to current
server time. Players who have never completed an online catalog fetch use the
device clock as the offline fallback.

The shipped `DailyFeatured.rb` configuration is the offline authority. A fresh
online catalog can override `daily_featured`; cached or unavailable online data
does not expose stale curated offers. There is no catalog-wide Automation
switch. Daily Featured uses its own `enabled` field, while stock resets and
economy events follow their own data.

Press `Special/Z` from the Reloaded Mart to open the Mart Actions popup. It
currently contains `View Event` and `Back`, and can accept more actions later.
View Event uses a centered HR Toast showing the event name, remaining time,
discount, and two randomly chosen item icons affected by the event.
The Mart remains open while its automatic open-time refresh runs. Completed
data is staged until the player returns to the idle browsing loop, so stock and
pricing never change underneath a quantity picker, confirmation, reward,
service, or active transaction.

## Economy Events

Economy Events are owned by:

```text
Reloaded/Modules/ReloadedMart/Automation/EconomyEvents.rb
```

Only one event can be active globally. Winner order is:

```text
Curated > Themed > Automated
```

Events of the same type use their numeric `priority`; higher wins. A stable
event ID resolves any remaining tie. A losing event is suspended if it can
resume after the winner ends, or superseded if the winner lasts through its
deadline.

Curated and Themed events are online-only. The generated online catalog uses
`economy_events` for the single event active at export time. It needs an ID,
type, Eastern start/end time, and at least one pricing rule or temporary entry.
Expired, disabled, future, and lower-priority events remain in the Admin
library and are not published.

The Mart Editor stores reusable blueprints and all Curated/Themed drafts in:

```text
Admin Tools/Reloaded Mart Editor/EconomyEventLibrary.json
```

This file and all `internal_notes` are Admin-only and are never published. A
blueprint can be copied to Automated, Curated, or Themed Events without
changing the original. Curated and Themed copies receive a new two-day
schedule and remain disabled until reviewed.

New editor working catalogs begin with 18 editable built-in blueprints containing 248
temporary item entries. Every template contains 10-15 offerings. The starting
library covers evolution supplies, training equipment, competitive held items,
weather tools, type boosters, Gems, Berries, Poke Balls, medicine, Vitamins,
Fossils, treasures, breeding, Plates, Mail, exploration, and battle supplies.
Related themes use one broader template instead of several smaller variants.
Each built-in price rule is
tag-scoped to that template's temporary entries, so copying a template does not
change unrelated Mart prices.

```json
{
  "id": "summer_healing",
  "event_type": "curated",
  "enabled": true,
  "label": "Summer Healing",
  "description": "Healing supplies are discounted.",
  "priority": 10,
  "available_from": "2026-07-20 00:00:00",
  "available_until": "2026-07-22 00:00:00",
  "pricing_rules": [
    {
      "id": "healing_discount",
      "label": "Healing Sale",
      "operation": "discount_percent",
      "value": 25,
      "mode": "buy",
      "tags": ["healing"],
      "exclusions": {
        "item_ids": ["MAXREVIVE"]
      }
    }
  ],
  "temporary_entries": [],
  "display": {
    "banner_text": "Summer Healing is active!",
    "description": "Selected healing items are 25% off.",
    "show_countdown": true
  }
}
```

Supported pricing operations are `discount_percent`, `markup_percent`,
`subtract_flat`, `add_flat`, `set_price`, `min`, and `max`. A rule can target
catalog entry IDs, GameData item IDs, categories, content kinds, tags,
currencies, and buy/sell/both modes. The same selectors can be placed in
`exclusions`.

`temporary_entries` use the normal catalog-entry schema and transaction
handlers. They exist only while their winning event is active, then disappear
without modifying the permanent catalog. Their IDs must not collide with
permanent entries.

Daily Featured is not suppressed by an event. If an item is both Daily Featured
and matched by the winning event, the event price is used without compounding
the Daily Featured discount.

Automated events use the shipped local runtime pool:

```text
Reloaded/Modules/ReloadedMart/Data/AutomatedEvents.json
```

They remain available offline and do not increase the online catalog size.
Starting at `cycle_anchor`, the schedule permanently repeats two Eastern
calendar days active followed by one day off. A deterministic template is
selected for each active cycle, and adjacent cycles avoid repeating the same
template when at least two exist. The Mart Editor exposes this at `Economy
Events > Automated Events > Cycle Anchor` and writes the local runtime file.

Automated percent changes are clamped to 50%, invalid templates fail closed,
and positive buy prices cannot be reduced below 1. A valid active Curated or
Themed event always beats the local Automated event. When the online event
expires or is unavailable, local automation resumes automatically.

Changing an active Curated/Themed event advances the catalog version when the
editor saves or publishes it, then takes effect on the next successful Mart
refresh. Local automation changes ship through a Core update.

## Entry Kinds

Supported entry kinds:

- `item`
- `bundle`
- `gift`
- `service`
- `unlock`

All entries share these fields where applicable:

```json
{
  "id": "item:POTION",
  "entry_version": 1,
  "kind": "item",
  "item": "POTION",
  "name": "Potion",
  "category_id": "medicine",
  "category_name": "MEDICINE",
  "tags": ["medicine"],
  "price": 300,
  "sell_price": 150,
  "currency": "money",
  "stock": 10,
  "stock_reset": "daily",
  "availability": {},
  "limits": {},
  "display": {},
  "requires": {},
  "grants": []
}
```

`item` entries grant one item stack based on `item`.

Purchases can use `money`, `coins`, `battle_points`, `quest_points`, or
`cosmetics_money`. Mods can add currencies through
`Reloaded::Rewards.register_currency`; the same wallet API is used for Mart
validation, debit, and refunds.

`bundle` and `gift` entries grant every registered reward listed in `grants`.
Items use the built-in `item` reward type. Mods can register additional grant
types through `Reloaded::Rewards` before the catalog is opened.

`service` currently supports `display.service_key: "instant_hatch"`, which
opens the party screen, lets the player choose one Egg, and hatches that Egg
immediately. Unknown service keys remain unavailable until a handler is added.

`unlock` requires a non-empty `display.unlock_key`. A successful purchase sets
that key in the per-save Mart `unlocks` state. Unlock purchases are limited to
one at a time, cannot be bought again after activation, and participate in
transaction rollback if a later purchase step fails. Gameplay and mod code can
query `ReloadedMart.unlocked?("key")`.

## Bundles, Gifts, And Mystery Boxes

Bundle/gift grant example:

```json
{
  "id": "starter_kit",
  "kind": "bundle",
  "name": "Starter Kit",
  "category_id": "bundles",
  "category_name": "BUNDLES",
  "price": 1200,
  "grants": [
    { "id": "POTION", "qty": 5 },
    { "id": "POKEBALL", "qty": 10 }
  ]
}
```

Mystery Box example:

```json
{
  "id": "mystery_box_daily",
  "kind": "bundle",
  "name": "Mystery Box",
  "price": 5000,
  "display": {
    "description": "Contains one possible reward outcome.",
    "mystery_box": true
  },
  "grants": [
    {
      "type": "item", "id": "RARECANDY", "quantity": 1,
      "rarity": "rare", "chance": 25
    },
    {
      "type": "group", "name": "Potion Supply", "rarity": "common",
      "chance": 75,
      "grants": [
        { "type": "item", "id": "POTION", "quantity": 5 },
        { "type": "item", "id": "POKEBALL", "quantity": 2 }
      ]
    }
  ]
}
```

The UI lists possible outcome names and colors them by rarity, but never shows
exact chances. Chances must total exactly 100. One outcome is selected per box;
a `group` outcome grants every child reward atomically.

The transaction ledger stores the selected outcome before charging. Mystery
transactions force a save before the debit and again after successful delivery,
before the reveal UI begins. A prepared transaction found after an interrupted
session is marked abandoned because the prepared save predates the debit.

All grant payloads are normalized and applied through `Reloaded::Rewards`.
Unknown reward types invalidate the containing bundle instead of being ignored.
Custom reward handlers should implement rollback when they can change state so
mixed bundles remain atomic.

### Pokemon Distributions

Bundles, gifts, and Mystery outcomes can use `type: "pokemon"`. Supported
distribution fields include species and fallback species, level, quantity,
delivery destination, Egg/form/shiny/gender/nature/ability data, optional
nickname, held item, Poke Ball, friendship, moves, exact or ranged IVs, EVs,
custom types, OT data, origin text, distribution ID/version, duplicate policy,
evolution policy, and an optional trade lock.

`species_mode` controls the Pokemon source:

- `single` uses `species`. The Mart Editor picker includes every species in the
  loaded base and Expanded Dex registry.
- `fusion` builds a fusion from `fusion_head_species` and
  `fusion_body_species`.
- `random_type` selects a loaded non-fusion species matching `random_type`.
- `random_bst` selects a loaded non-fusion species between `bst_min` and
  `bst_max`, inclusive.

Random and fusion sources resolve once before transaction validation. The same
resolved species is delivered after payment. `fallback_species` is used if the
requested species or random pool is unavailable.

```json
{ "type": "pokemon", "species_mode": "single", "species": "TREECKO", "level": 10 }
{ "type": "pokemon", "species_mode": "fusion", "fusion_head_species": "TREECKO", "fusion_body_species": "TORCHIC", "level": 10 }
{ "type": "pokemon", "species_mode": "random_type", "random_type": "GRASS", "level": 10 }
{ "type": "pokemon", "species_mode": "random_bst", "bst_min": 300, "bst_max": 450, "level": 10 }
```

New editor-authored rewards default `generate_moves` to `true`, which gives the
Pokemon the normal level-up moves for its configured level. Set it to `false`
and provide up to four `moves` for a custom moveset. An omitted or empty
`types` array keeps the species' native typing. Blank nickname and OT fields
keep the normal species name and current-player ownership data. If only some OT
fields are customized, every untouched field still uses the current player's
normal value. Nature choices
in the editor show their increased and decreased stats, and forms are selected
from the chosen species' available form list.

Pokemon granted by Reloaded Mart always bypass player IV Boundaries. Their IVs
come only from the distribution payload or normal generation when no IV fields
are supplied. `untradeable: true` requires a stable `distribution_id` and is
enforced by normal trades, NPC trades, Wonder Trade, and fusions containing the
distribution. `duplicate_policy` accepts `allow`, `reject`, or `replace`;
`evolution_policy` accepts `allow` or `block`.

### PokeVial Grants

Bundles, gifts, and Mystery Boxes can grant PokeVial rewards instead of normal
bag items. Mystery Gift payloads can use the same reward markers.

Single-use charge:

```json
{ "type": "pokevial", "quantity": 1 }
{ "type": "pokevial_charge", "quantity": 1 }
```

Full refill:

```json
{ "type": "pokevial_refill" }
```

Max-charge unlock:

```json
{ "type": "pokevial_max_uses", "max_uses": 4 }
```

Supported aliases include `poke_vial`, `pokevial_charge`, `POKEVIAL_CHARGE`,
`pokevial_uses`, `POKEVIAL_USES`, `pokevial_refill`, `POKEVIAL_REFILL`,
`refill_pokevial`, `pokevial_unlock`, and `POKEVIAL_MAX_USES`.

PokeVial rewards are preflighted before the selected currency is charged. A single-use charge
requires an empty charge slot, a full refill requires the vial to be below max,
and a max-charge unlock must increase the player's current max.

### IV Boundary Rewards

Bundles, gifts, and Mystery Boxes can grant IV Boundary rewards instead of
normal bag items.

Temporary boost:

```json
{ "type": "iv_boundary_boost", "scope": "wild", "floor_bonus": 5, "duration_seconds": 600 }
{ "type": "iv_boundary_boost", "scope": "egg", "min": 20, "max": 31, "duration_minutes": 10 }
```

One-shot next Pokemon rule:

```json
{ "type": "iv_boundary_force_next", "scope": "gift", "perfect_ivs": 3, "quantity": 1 }
```

Supported scopes are `wild`, `gift`, `static`, `egg`, `player`, and `trainer`.
`iv_boundary_boost` expires by real time. `iv_boundary_force_next` is consumed
by the next matching newly generated Pokemon.

Reloaded also registers two hidden internal Medicine-pocket item datapatches for
normal item rewards or shops. They can also be placed in Overworld Menu Quick
Items:

- `POKEVIAL_CHARGE` - restores one PokeVial charge when used from the Bag.
- `POKEVIAL_REFILL` - restores all missing PokeVial charges when used from the Bag.

## Mod-Added Items

Catalog entries may reference mod-added item IDs.

Compatibility rules:

- If a normal item entry references a missing item, that entry is skipped.
- If a required dependency item is missing, that entry is skipped.
- If a bundle/gift grant item is missing, the whole bundle/gift is skipped.
- Optional mod dependency hints may be listed in `requires.mods`.
- Runtime availability can also require active mods through `requires.mods`.

This lets catalogs include mod-specific entries without breaking players who do
not have those mods installed.

## Availability

Availability checks support:

- `active`
- `available_from`
- `available_until`
- `hidden`
- `visible_when_locked`
- `display`
- `lock_text`
- `requires_badges` or `min_badges`
- `requires_switches`
- `requires_variables`
- `difficulty_allowlist`
- `difficulty_blocklist`
- mod dependencies
- owned item dependencies
- one-time claims
- stock remaining

Locked entries show clean player-facing messages. Technical details are logged.
Set `active` to `false` to disable an entry. It follows the same hidden or
visible-when-locked display policy as other failed availability checks.

## Stock And Limits

`stock: nil` means unlimited.

`stock: 0` means sold out.

Supported stock reset rules:

- `never`
- `daily`
- `weekly`
- `monthly`
- `catalog_version`
- `stock_epoch`

Supported limits:

```json
{
  "max_per_purchase": 5,
  "max_per_save": 10,
  "max_per_day": 2,
  "one_time": true
}
```

Stock, daily limits, save limits, and one-time claims are stored per save.

## Pricing

The price pipeline is:

1. base game item price
2. catalog price or sell price
3. entry-level modifiers
4. active catalog economy event modifiers
5. daily featured modifier
6. runtime registered price modifier handlers

Supported modifier types:

- `flat`
- `percent`
- `set` / `set_price`
- `min`
- `max`

Matching supports mode, entry ID(s), item ID(s), kind, category ID(s), tag,
and minimum loyalty spend.

`PriceResult` exposes:

```ruby
base
catalog
modifiers
final
currency
display
```

The configured catalog price is the normal Reloaded Mart price. `% OFF` and
`% MORE` badges compare the final price against that catalog price, so simply
setting a Mart price above or below the vanilla item price does not create a
price-change badge.

The built-in purchase currencies are `money`, `coins`, `battle_points`,
`quest_points`, and `cosmetics_money`. A mod-registered currency is also valid
when it provides a readable and writable wallet through `Reloaded::Rewards`.

## Transactions

Purchases use one cart path for items, bundles, gifts, services, and unlocks.

The transaction order is:

1. build cart
2. validate availability
3. validate limits
4. validate stock
5. validate handler-specific rules
6. validate the selected currency wallet
7. preflight every registered reward and simulate combined Bag capacity
8. charge the selected currency
9. atomically apply reward grants
10. apply handler side effects
11. record stock, limits, claims, and stats
12. emit events

If a grant or handler step fails after payment moves, the backend rolls back
reward receipts in reverse order and refunds the same currency. Non-reversible
reward side effects should be registered as `Reloaded::Rewards` finalizers so
they run only after the full purchase transaction succeeds.

Catalog grants can use every shared Rewards type, including Pokemon with
stored custom typings, currencies, TM Vault moves, outfits, registered feature
unlocks, player choices, and reward groups. Mystery Box outcomes use direct
`chance` values and reveal the granted leaf rewards rather than the container
entry.

Random reward pools can use arbitrary relative `weight` values or percentages
out of 100 through `percentage` or `chance`. A percentage pool must total
exactly 100 and cannot mix percentages with weights.

Vanilla NPC mart purchases use the REX UI but bypass online catalog stock,
limits, and economy modifiers.

## REX Buy Controls

Standalone Reloaded Mart opens a Buy/Sell/Quit command menu first.

Buy screen controls:

- `Buy (C)`
- `Back (B)`
- `Favorite (A)`
- `Sort (L)`
- `Quick Buy (R)`
- `Page (< >)`
- mouse hover, wheel, and click support

Sort modes:

- Name
- Price Low
- Price High
- Stock

Quick Buy uses the validated maximum quantity.

Rows can show:

- `FREE`
- `MAX`
- stock labels
- `NEW!`
- `FEATURED`
- `LIMITED`
- locked state
- price change badges such as `20% OFF` or `15% MORE` when an active modifier
  changes the configured Reloaded Mart price

## REX Sell Controls

Sell screen controls:

- `Sell (C)`
- `Back (B)`
- `Sort (L)`
- `Sell-All (R)`
- `Page (< >)`
- mouse hover, wheel, and click support

Sort modes:

- Name
- Price High
- Price Low

Sell-All sells the full stack after confirmation.

## Events

Reloaded Mart emits:

```ruby
:reloaded_mart_catalog_loaded
:reloaded_mart_catalog_failed
:reloaded_mart_purchase_validated
:reloaded_mart_purchase_completed
:reloaded_mart_purchase_failed
:reloaded_mart_sale_completed
:reloaded_mart_sale_failed
:reloaded_mart_stock_changed
```

Common transaction payload fields:

- `:source`
- `:catalog_version`
- `:currency`
- `:entries`
- `:grants`
- `:total_price`
- `:result`
- `:message`
- `:details`
- `:context`

TM Vault observes machine item rewards through the shared Rewards item
finalizer after the complete purchase transaction succeeds.

## Save Data

Reloaded Mart state is stored under:

```ruby
Reloaded::SaveData.system(:reloaded_mart)
```

Important saved keys:

- `schema_version`
- `favorites`
- `stock`
- `stock_resets`
- `claims`
- `limits`
- `limits_daily`
- `stats`
- `catalog`
- `cache`
- `seen_catalog_versions`
- `unlocks`
- `daily_featured`
- `transaction_sequence`
- `transactions`
- `pending_deliveries`

The bounded transaction ledger keeps the latest 250 purchase records. Each
record stores a stable transaction ID, entry ID/version, catalog version,
currency, price, selected grants, completion status, and delivered
distribution IDs. This is local correctness metadata and a future multiplayer
reconciliation boundary; it does not add networking by itself.

Do not store sprites, bitmaps, windows, procs, open files, or scene objects in
this bucket.

## Logging

Reloaded Mart logs:

- install
- catalog fetch start/finish/failure
- validation summaries
- skipped entries
- stock resets
- transaction completion/failure
- vanilla mart wrapper failures
- unexpected exceptions

Logs go through `Reloaded::Log`, which sanitizes paths relative to the game
root.

## Verification Checklist

Before deleting `ReloadedMart-To-Do.md`, verify in game:

- standalone Reloaded Mart opens from REPM
- first open with no cache handles online fetch failure cleanly
- malformed catalog does not crash
- missing mod-added item entries are skipped
- bundles with missing required grant items are skipped
- normal purchase succeeds
- free purchase succeeds
- bundle/gift purchase succeeds
- mystery box hides contents but grants the real items
- bag-full purchase fails before payment moves
- insufficient-currency purchase fails before inventory changes
- stock, save limits, daily limits, and one-time claims update
- TM/HM purchase registers with TM Vault
- favorites persist
- NEW! badge behavior is acceptable after catalog version changes
- vanilla NPC mart buy uses vanilla stock/prices
- vanilla NPC mart sell uses vanilla sell prices and `cantsell`
- custom `$game_temp.mart_prices` apply to vanilla marts
- Premier Ball/DNA bonus behavior still works
- logs do not expose absolute paths
