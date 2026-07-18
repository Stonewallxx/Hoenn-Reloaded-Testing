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
Reloaded/Modules/ReloadedMart/UI.rb
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

## Online Catalog Loading

The standalone Reloaded Mart is online-catalog driven.

On open:

- The mart opens immediately and refreshes the catalog through `Reloaded::Task`.
- Every online fetch uses a cache-busted URL.
- A valid online response replaces the last-good cache.
- Curated catalog entries, banners, events, and promo codes are shown only
  while the current source is a freshly confirmed online response.
- Cached catalog data is retained for recovery and metadata but never exposes
  expired curated offers while offline.
- Locally generated automation, including Daily Featured, remains available
  offline and uses its built-in defaults until a fresh catalog arrives.

The current online URL is:

```ruby
ReloadedMart::ONLINE_CATALOG_URL
```

## Catalog Versions

`schema_version` tracks JSON structure compatibility.

`catalog_version` tracks content releases. It is used for cache metadata,
stock reset rules, transaction stats, and NEW! badge tracking.

Catalog versions should use `MM.DD.YY`, for example `07.04.26`.

Supported schema version:

```ruby
ReloadedMart::SCHEMA_VERSION
```

## Catalog Schema

Top-level fields:

```json
{
  "schema_version": 2,
  "catalog_version": "07.04.26",
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
  "profile_tuning": {},
  "daily_featured": {
    "enabled": true,
    "count": 2,
    "discount_min_percent": 10,
    "discount_max_percent": 40,
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

`banner` is the standalone Reloaded Mart buy banner. Use `banners` for
page-specific banners. Supported keys include `reloaded_buy`, `reloaded_sell`,
`vanilla_buy`, `vanilla_sell`, `regular_buy`, and `regular_sell`. Sell pages do
not inherit the top-level Reloaded buy banner. The daily featured item is shown
as a row badge, not appended to the banner ticker.

`daily_featured` generates deterministic real-day Featured rows from the game's
item pool. The same `catalog_version` and calendar day produce the same items
for every player. Key items, TMs/HMs/TRs, important/untossable items, 0-price
items, the built-in powerful-item blacklist, and any online `blacklist` entries
are excluded. Each generated item gets its own deterministic discount from the
online catalog range set by `discount_min_percent` and
`discount_max_percent`; values are clamped to 10-40% off and there is no player
option for changing them.

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

`service` and `unlock` are registry-backed entry kinds. `service` currently
supports `display.service_key: "instant_hatch"`, which opens the party screen,
lets the player choose one Egg, and hatches that Egg immediately. Unknown
service keys remain unavailable until a handler is added.

## Promo Codes

Promo codes are top-level catalog data, not Mart entries. Players enter a code
with `Promo Code (Z)` on the Reloaded Mart buy page. A valid code activates its
discount for 5 minutes and is immediately marked used for that save file, so it
cannot be reactivated later. Only one promo code can be active at a time.

Example:

```json
{
  "promo_codes": [
    {
      "id": "healing_20",
      "code": "HEAL20",
      "label": "20% Healing Discount",
      "enabled": true,
      "available_from": "",
      "available_until": "",
      "modifier": {
        "mode": "buy",
        "type": "percent",
        "value": -20,
        "category_ids": ["medicine"],
        "entry_ids": [],
        "item_ids": [],
        "tags": []
      }
    }
  ]
}
```

Promo modifiers use the same targeting fields as other price modifiers, such as
`entry_id`, `entry_ids`, `item_id`, `item_ids`, `category`, `category_id`,
`category_ids`, `tag`, and `tags`. Leave entry/item/category/tag targets empty
to let the promo apply wherever the remaining modifier rules match. If the local
clock moves backward while a promo code is active, active promo codes are
cleared and already-used codes stay used.

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
delivery destination, Egg/form/shiny/gender/nature/ability data, nickname,
held item, Poke Ball, friendship, moves, exact or ranged IVs, EVs, custom
types, OT data, origin text, distribution ID/version, duplicate policy,
evolution policy, and an optional trade lock.

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

Supported scopes are `wild`, `gift`, `static`, `egg`, and `player`.
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
5. profile tuning modifiers
6. daily featured modifier
7. active promo code modifiers
8. runtime registered price modifier handlers

Supported modifier types:

- `flat`
- `percent`
- `set` / `set_price`
- `min`
- `max`

Matching supports mode, entry ID(s), item ID(s), kind, category ID(s), tag,
promo code, and minimum loyalty spend.

`PriceResult` exposes:

```ruby
base
catalog
modifiers
final
currency
display
```

The built-in purchase currencies are `money`, `coins`, `battle_points`,
`quest_points`, and `cosmetics_money`. A mod-registered currency is also valid
when it provides a readable and writable wallet through `Reloaded::Rewards`.

## Transactions

Purchases use one cart path for items, bundles, gifts, services, unlocks, and
legacy coupon entries.

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
- price change badges such as `20% OFF` or `15% MORE` when the final price differs from the base price

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
- `promo_codes`
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
