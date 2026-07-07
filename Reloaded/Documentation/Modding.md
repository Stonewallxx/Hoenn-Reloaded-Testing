#======================================================
# Reloaded Modding Documentation
# Author: Stonewall
#======================================================
# Living documentation for modding against Hoenn Reloaded.
#
# Responsibilities:
#   - Explain Reloaded systems intended for modding use.
#   - Record recommended modding patterns as systems are added.
#   - Point modders toward logging, events, patches, and public APIs.
#   - Keep compatibility notes in one central document.
#
#======================================================

This file is the main modder-facing reference for Hoenn Reloaded.

It should be updated whenever a Reloaded system gains a public API that modders
are expected to use.

For a high-level status summary of the current fork foundation, see
`Reloaded/Documentation/System.md`.

## Current Status

Reloaded is still building its modding foundation. The current public systems
are:

- `Reloaded::Log`
- `Reloaded::Events`
- `Reloaded::Hooks` compatibility alias
- `Reloaded::Patches`
- `Reloaded::SaveData`
- `Reloaded::Assets`
- `Reloaded::DataPatches`
- `Reloaded::Abilities`
- `Reloaded::ModManager`
- `Reloaded::ModBrowser`
- `Reloaded::Publisher`
- `Reloaded::ModderTools`
- `Reloaded::Profiles`
- `Reloaded::ModSettings`
- `Reloaded::Options`
- `Reloaded::Settings`
- `ReloadedPauseMenu`
- `ReloadedIVBoundaries`
- `ReloadedPokeVial`

## Recommended Modding Rules

- Prefer Reloaded APIs over directly editing base-game files.
- Register behavior through events when an event exists.
- Register major vanilla behavior changes through `Reloaded::Patches`.
- Use `Reloaded::Log.mod` for mod-specific logging.
- Include clear mod IDs, versions, dependency notes, and recommended fixes in
  errors.
- Avoid replacing vanilla methods unless wrapping or events cannot solve the
  problem.

## Logging

Use `Reloaded::Log` for diagnostics and user-facing failure reports.

```ruby
Reloaded::Log.mod("example_mod", "Loaded settings")
Reloaded::Log.warning("Optional feature disabled", :mods)
```

For major failures, write a report:

```ruby
Reloaded::Log.report(
  :type => "Mod Load Failure",
  :mod_id => "example_mod",
  :mod_name => "Example Mod",
  :version => "1.0.0",
  :level => :critical,
  :file_path => __FILE__,
  :dependency_status => "Missing required dependency.",
  :recommended_fix => "Install the missing dependency or disable this mod.",
  :error => error
)
```

See `Reloaded/Documentation/System.md` for the full logging reference.

## Events

Use `Reloaded::Events` to attach behavior without directly replacing vanilla
code.

```ruby
Reloaded::Events.on(:bootstrap_loaded, :example_mod_boot, priority: 100) do |ctx|
  Reloaded::Log.mod("example_mod", "Bootstrap event received")
end
```

Use `Reloaded::Events.first_result` when an event should allow one handler to
provide an answer.

`Reloaded::Hooks` currently points to the same system for compatibility.

See `Reloaded/Documentation/Events.md` for the full event reference.

## Patches

Use `Reloaded::Patches` when a mod or Reloaded system changes vanilla behavior,
data, or assets.

```ruby
Reloaded::Patches.register(
  :example_mart_change,
  :target => "PokemonMartScreen#pbBuyScreen",
  :type => :wrap,
  :file => __FILE__,
  :owner => :example_mod,
  :priority => 100,
  :reason => "Add custom shop behavior.",
  :recommended_fix => "Disable one mart patch or move the change to an event."
)
```

This does not automatically patch the game. It records what is being changed so
Reloaded can detect conflicts and explain them in logs.

See `Reloaded/Documentation/System.md` for the full patches reference.

## Save Data

Use `Reloaded::SaveData` for persistent mod data.

```ruby
Reloaded::SaveData.set(:example_mod, :quest_stage, 2)
Reloaded::SaveData.get(:example_mod, :quest_stage, 0)
```

For direct access to your mod namespace:

```ruby
save = Reloaded::SaveData.mod(:example_mod)
save["quest_stage"] = 2
```

Do not add random fields to vanilla save objects for mod data unless there is no
Reloaded API that can handle the use case.

See `Reloaded/Documentation/System.md` for the full save data reference.

## Data Patches

Use `DataPatches/**/*.json` for structured runtime data that should be added or
changed by a mod without replacing whole base files.

```text
Mods/<mod folder>/DataPatches/example_data.json
```

Supported operations:

- `add`
- `edit`
- `merge`
- `replace`

`remove` is not supported.

Example:

```json
{
  "target": "example_data",
  "operation": "add",
  "id": "example_entry",
  "data": {
    "name": "Example Entry",
    "value": 10
  }
}
```

Example item patch:

```json
{
  "target": "items",
  "operation": "add",
  "id": "example_reloaded_item",
  "data": {
    "name": "Example Reloaded Item",
    "name_plural": "Example Reloaded Items",
    "pocket": 1,
    "price": 100,
    "description": "A safe example item added by a Reloaded data patch.",
    "field_use": 0,
    "battle_use": 0,
    "type": 0
  }
}
```

For item patches, `id_number` may be provided manually, but it is optional.
Reloaded assigns the next available runtime number when it is omitted.

Reloaded validates GameData-backed patches before applying them. Unknown
species, moves, abilities, items, encounter types, evolution methods, trainer
types, invalid stat objects, invalid encounter levels, and invalid trainer party
slot edits are logged and skipped instead of being allowed into runtime data.

Example move patch:

```json
{
  "target": "moves",
  "operation": "add",
  "id": "example_reloaded_move",
  "data": {
    "name": "Example Reloaded Move",
    "function_code": "000",
    "base_damage": 40,
    "type": "NORMAL",
    "category": "Physical",
    "accuracy": 100,
    "total_pp": 35,
    "effect_chance": 0,
    "target": "NearOther",
    "priority": 0,
    "flags": "abef",
    "description": "A safe example move added by a Reloaded data patch."
  }
}
```

For move patches, `function_code` points to existing battle behavior. Use `000`
for a normal damage-only move. Custom move behavior still requires a Ruby script.

Example ability patch:

```json
{
  "target": "abilities",
  "operation": "add",
  "id": "example_reloaded_ability",
  "data": {
    "name": "Example Reloaded Ability",
    "description": "A safe example ability added by a Reloaded data patch."
  }
}
```

Ability patches make the ability exist and display. Custom ability behavior
still requires Ruby battle handler code.

Example species core patch:

```json
{
  "target": "species.core",
  "operation": "merge",
  "id": "treecko",
  "data": {
    "base_stats": {
      "SPEED": 75
    },
    "catch_rate": 45,
    "hatch_steps": 5120
  }
}
```

`species.core` changes core fields on existing species, such as types, stats,
EV yields, growth rate, gender ratio, catch rate, egg groups, hatch steps,
height, weight, color, shape, habitat, and generation. It does not add new
species or patch evolutions/forms.

Example species learnset patch:

```json
{
  "target": "species.learnsets",
  "operation": "merge",
  "id": "treecko",
  "data": {
    "add_moves": [
      {
        "level": 8,
        "move": "example_reloaded_move"
      }
    ],
    "add_tutor_moves": ["example_reloaded_move"],
    "add_egg_moves": ["example_reloaded_move"]
  }
}
```

`species.learnsets` changes level-up, tutor, and egg moves for existing
species. Use `add_moves`, `add_tutor_moves`, and `add_egg_moves` for small
additions. Use `moves`, `tutor_moves`, or `egg_moves` only when replacing the
full list.

Example species evolution patch:

```json
{
  "target": "species.evolutions",
  "operation": "merge",
  "id": "treecko",
  "data": {
    "add_evolutions": [
      {
        "species": "grovyle",
        "method": "Level",
        "parameter": 16
      }
    ]
  }
}
```

`species.evolutions` changes forward evolutions for existing species. Reloaded
rebuilds generated prevolution entries after applying these patches.

Example encounter patch:

```json
{
  "target": "encounters.classic",
  "operation": "merge",
  "id": "101_0",
  "data": {
    "add_types": {
      "Land": [
        {
          "chance": 5,
          "species": "example_species",
          "min_level": 8,
          "max_level": 10
        }
      ]
    }
  }
}
```

Encounter targets are `encounters.classic`, `encounters.remix`, and
`encounters.randomized`. IDs use `<map_id>_<version>`, such as `101_0`.
Use `add_types` for small additions and `types` for full encounter table
replacement.

Example species ability patch:

```json
{
  "target": "species.abilities",
  "operation": "replace",
  "id": "treecko",
  "data": {
    "abilities": ["overgrow"],
    "hidden_abilities": ["example_reloaded_ability"]
  }
}
```

`species.abilities` only changes the normal and hidden ability arrays for an
existing species. Use `replace` and provide the full arrays. Broad species data
patching is still future work.

Trainer patches:

- use `trainers.classic`, `trainers.remix`, or `trainers.expert`,
- target trainers by `TRAINER_TYPE|Trainer Name|Version`,
- can patch party Pokemon, held items, trainer battle items, trainer info text,
  battle intro text, lose text, and rematch text fields,
- validate species, moves, items, abilities, party slots, and missing trainer
  targets before runtime data is applied.

Trainer type patches use `trainer_types` for trainer-class-wide data such as
AI skill level, AI flags/skill code, and reward money multipliers. These affect
every trainer using that trainer type while the mod is enabled.

Runtime access:

```ruby
entry = Reloaded::DataPatches.entry("example_data", "example_entry")
all_entries = Reloaded::DataPatches.data("example_data")
```

Data patches are validated, logged, and registered with `Reloaded::Patches`.
They are applied in memory at startup and do not permanently edit base files.

See `Reloaded/Documentation/DataPatches.md` for the full data patch reference.

## Ability Behavior

Use `Reloaded::Abilities` when a modded ability needs battle behavior.

Example speed behavior:

```ruby
Reloaded::Abilities.on_speed_calc(:EXAMPLE_RELOADED_ABILITY) do |_ability, battler, mult|
  next mult * 2 if [:Rain, :HeavyRain].include?(battler.battle.pbWeather)
end
```

This uses the same underlying `BattleHandlers` system as vanilla abilities, but
with clearer Reloaded helper names.

General handler form:

```ruby
Reloaded::Abilities.on(:switch_in, :EXAMPLE_RELOADED_ABILITY) do |ability, battler, battle|
  # behavior here
end
```

Useful helpers include:

- `on_speed_calc`
- `on_status_immunity`
- `on_stat_loss_immunity`
- `on_move_immunity_target`
- `on_damage_calc_user`
- `on_damage_calc_target`
- `on_switch_in`
- `on_switch_out`
- `on_eor_effect`

Mods can also copy existing vanilla behavior:

```ruby
Reloaded::Abilities.copy_behavior(:SWIFTSWIM, :EXAMPLE_RELOADED_ABILITY)
```

`Reloaded::Abilities.register` can create ability data from Ruby scripts, but
JSON `abilities` data patches are preferred for normal mod data.

## Options

Use the Reloaded options framework for new in-game settings screens.

Current reusable types include:

- `CategoryHeader`
- `CollapsibleHeader`
- `TextDisplayOption`
- `ActionButton`
- `LockableEnumOption`
- `HiddenOption`
- `Spacer`

See `Reloaded/Documentation/System.md` for the full options reference.

Mods can add rows to supported Reloaded categories:

```ruby
Reloaded::Options.register_category_option("DEVELOPER", :debug_toggle, priority: 50) do |_scene|
  EnumOption.new(
    _INTL("Debug"),
    [_INTL("Off"), _INTL("On")],
    proc { $DEBUG ? 1 : 0 },
    proc { |value| $DEBUG = value.to_i == 1 },
    _INTL("Toggles debug mode for this play session.")
  )
end
```

## Pause Menu Modules

The Reloaded Pause Menu is implemented in:

```text
Reloaded/Modules/001_ReloadedPauseMenu.rb
```

The active pause menu is controlled by the `Pause Menu` option in the
`RELOADED` category:

```text
Standard / Reloaded
```

Default value: `Reloaded`.

### Registering a Module

Future Reloaded systems and mods can add pause menu entries with:

```ruby
ReloadedPauseMenu.register_module(
  :MYMODULE,
  label: "My Module",
  icon: "Mods/My Mod/Graphics/my_icon",
  handler: proc { MyModule.open },
  condition: proc { true },
  hidden: false,
  lock_reason: "This module is not available yet."
)
```

Fields:

- `key`: unique symbol used for ordering, favorites, saved custom rows, and icon fallback.
- `label`: text shown in the menu.
- `icon`: optional path without `.png`.
- `handler`: code run when the entry is selected.
- `condition`: optional proc; false means the module is locked.
- `hidden`: if true, a false condition hides the module instead of showing it locked.
- `lock_reason`: optional string or proc shown when the player selects a locked module.

If `icon` is omitted, REPM loads the icon from:

```text
Reloaded/Graphics/ReloadedMenu/<KEY>.png
```

Example:

```ruby
ReloadedPauseMenu.register_module(
  :QUESTLOG,
  label: "Quest Log",
  handler: proc { ReloadedQuestLog.open },
  condition: proc { defined?(ReloadedQuestLog) },
  lock_reason: "Quest Log is not available yet."
)
```

### Ordering Rules

Ordering is controlled by the REPM order config near the top of
`001_ReloadedPauseMenu.rb`:

- `FIXED_ROW_ORDER`: the fixed first row. Users do not customize this row.
- `CAROUSEL_ORDER`: the default carousel order. Registered modules not listed here are appended to the end.
- The second row is controlled only by the player's custom row save data.

A registered module does not need to be listed in either order constant. If it is
not listed, it can still appear in the carousel after the configured entries and
can be added to the customizable second row by the player.

### Locked and Hidden Modules

When `condition` returns false:

- `hidden: false` shows the module as locked.
- Selecting the locked module shows `lock_reason`.
- `hidden: true` removes the module from the visible menu until it becomes available.

Use locked modules when players should know the feature exists. Use hidden
modules for developer/debug entries or systems that should not be advertised yet.

Current default REPM modules are Pokedex, Pokemon, Bag, PokeNav, Trainer Info,
Outfit, Save, Options, Debug, Title, Reloaded Mart, and TM Vault. Reloaded Mart
and TM Vault stay locked unless their systems exist.

REPM layout state uses the Reloaded save bucket under
`systems/reloaded_pause_menu`. The saved keys are `custom_row` and `favorite`.

## Overworld Menu

The Overworld Menu is implemented in:

```text
Reloaded/Modules/004_OverworldMenu.rb
```

It preserves the reference quick-access overlay UI and opens from the overworld
through `Events.onMapUpdate`.

Mods can register entries:

```ruby
OverworldMenu.register(:my_feature,
  label: "My Feature",
  priority: 50,
  condition: proc { true },
  exit_on_select: false,
  handler: proc { |screen|
    screen.show_popup("MY FEATURE", ["Hello from my feature."])
    nil
  }
)
```

The handler receives the active `OverworldMenuScreen`. Return `:exit_menu`, or
set `exit_on_select: true`, to close the overlay after the entry runs.

See `Reloaded/Documentation/OverworldMenu.md` for the full entry contract.

## IV Boundaries

IV Boundaries is implemented in:

```text
Reloaded/Modules/007_IVBoundaries.rb
```

Players can set IV boundaries for newly generated player-side Pokemon through
the Reloaded options menu. This applies to new wild Pokemon, gifts, static
encounters, and Eggs. Existing party/box Pokemon are not changed.

The options submenu includes presets, custom Min/Max IV sliders, and a preview
action. If Max IV is below 31, perfect IVs are treated like any other
out-of-range value and rerolled inside the active range.

Trainer IV boundaries are not player-editable. They are controlled by difficulty
rules and trainer-class config in `007_IVBoundaries.rb`:

```ruby
ReloadedIVBoundaries::TRAINER_DIFFICULTY_RULES
ReloadedIVBoundaries::TRAINER_CLASS_GROUPS
ReloadedIVBoundaries::TRAINER_CLASS_EXEMPTIONS
```

Mods can apply the same boundaries to custom Pokemon:

```ruby
ReloadedIVBoundaries.apply_to(pokemon, :wild)
ReloadedIVBoundaries.apply_to(pokemon, :gift)
ReloadedIVBoundaries.apply_to(pokemon, :static)
ReloadedIVBoundaries.apply_to(pokemon, :egg)
ReloadedIVBoundaries.apply_to(pokemon, :trainer, :trainer_type => :LEADER)
```

Supported scopes are `:wild`, `:gift`, `:static`, `:egg`, `:player`, and
`:trainer`. Player scopes use the player-facing Min/Max IV options. Trainer
scope uses the current difficulty and trainer class config.

Useful checks and generators:

```ruby
ReloadedIVBoundaries.enabled?(:wild)
ReloadedIVBoundaries.bounds_for(:wild)
ReloadedIVBoundaries.bounds_for(:trainer, :trainer_type => :RIVAL1)
ReloadedIVBoundaries.generate_iv(:wild)
ReloadedIVBoundaries.generate_ivs(:egg)
```

`apply_to` preserves IVs that are already inside the active range. Any IV below
the floor or above the ceiling is rerolled inside the active range instead of
being clamped to the nearest boundary.

One-shot event and reward helpers:

```ruby
ReloadedIVBoundaries.force_next(:egg, { :min => 25, :max => 31 }, source: :event)
ReloadedIVBoundaries.force_next(:gift, { :perfect_ivs => 3 }, source: :event)
ReloadedIVBoundaries.exempt_next(:gift, source: :my_mod)
ReloadedIVBoundaries.grant_temporary_boost(:wild, { :floor_bonus => 5 }, duration_seconds: 600, source: :my_mod)
```

`force_next` affects the next matching newly generated Pokemon and then consumes
itself. `exempt_next` skips the next matching Pokemon. Temporary boosts are
stored in the Reloaded save bucket and expire by real time.

Mods can also mark a specific Pokemon object as exempt:

```ruby
pokemon.reloaded_iv_boundaries_exempt = true
```

Reloaded Mart and Mystery Gift payloads can activate IV rewards:

```json
{ "type": "iv_boundary_boost", "scope": "wild", "floor_bonus": 5, "duration_seconds": 600 }
{ "type": "iv_boundary_boost", "scope": "egg", "min": 20, "max": 31, "duration_minutes": 10 }
{ "type": "iv_boundary_force_next", "scope": "gift", "perfect_ivs": 3, "quantity": 1 }
```

Supported aliases include `iv_boundary`, `iv_boundaries`, `iv_boost`,
`iv_floor_boost`, `iv_force_next`, and `iv_next`.

Mods can register callbacks:

```ruby
ReloadedIVBoundaries.on(:before_apply, :my_mod_iv_check) do |ctx|
  # Return false to cancel. ctx includes :pokemon, :scope, :bounds, and :source.
  true
end

ReloadedIVBoundaries.on(:after_apply, :my_mod_iv_after) do |ctx|
  # ctx includes :changed, :ivs_before, and :ivs_after.
end
```

Supported callback names are `:before_apply` and `:after_apply`.

## PokeVial

PokeVial is implemented in:

```text
Reloaded/Modules/006_PokeVial.rb
```

Mods and Reloaded systems can grant charges, refill the vial, or unlock higher
charge limits through the public script API:

```ruby
ReloadedPokeVial.add_uses(1, source: :my_mod)
ReloadedPokeVial.grant_uses(2, source: :my_mod)
ReloadedPokeVial.grant_full_refill(source: :my_mod)
ReloadedPokeVial.unlock_max_uses(4, source: :my_mod)
ReloadedPokeVial.increase_max_uses(1, source: :my_mod)
```

Use `source:` for logging and compatibility hooks. Good source values are short
symbols such as `:my_mod`, `:reloaded_mart`, `:mystery_gift`, or `:event`.

`grant_full_refill` restores current charges to the current maximum. It returns
false if the vial is already full or unavailable.

`unlock_max_uses(amount)` records a save-specific progression unlock while
Progressive Uses is enabled. It does not lower an existing unlock. The current
maximum also respects the built-in badge progression and any configured
switch/variable progression rules in `006_PokeVial.rb`.

Useful checks:

```ruby
ReloadedPokeVial.enabled?
ReloadedPokeVial.uses
ReloadedPokeVial.configured_max_uses
ReloadedPokeVial.can_add_uses?(1)
ReloadedPokeVial.can_refill?
ReloadedPokeVial.status_text
ReloadedPokeVial.item_id?(:POKEVIAL_CHARGE)
```

`status_text` returns the same short labels used by Reloaded menus:
`Charges: #`, `EMPTY`, or `Cooldown: 04:12`.

Mods can register callbacks for use and refill flow:

```ruby
ReloadedPokeVial.on(:before_use, :my_mod_vial_check) do |ctx|
  # Return false to cancel use. Optional: set ctx[:message].
  true
end

ReloadedPokeVial.on(:after_use, :my_mod_vial_after) do |ctx|
  # ctx includes :source, :uses_before, :uses_after, :max_uses, and :heal_mode.
end

ReloadedPokeVial.on(:before_refill, :my_mod_refill_check) do |ctx|
  # Return false to cancel refill before money is deducted.
  true
end

ReloadedPokeVial.on(:after_refill, :my_mod_refill_after) do |ctx|
  # ctx includes :source, :uses_before, :uses_after, :max_uses, :restored, and :cost.
end
```

Supported callback names are `:before_use`, `:after_use`, `:before_refill`,
and `:after_refill`.

Remove a callback by ID:

```ruby
ReloadedPokeVial.unregister_callback(:before_use, :my_mod_vial_check)
```

Optional progression config lives in `006_PokeVial.rb`:

```ruby
PROGRESSION_SWITCH_UNLOCKS = {
  42 => 4
}

PROGRESSION_VARIABLE_UNLOCKS = {
  12 => {
    3 => 4,
    5 => 5
  }
}
```

Optional per-map denial text also lives in `006_PokeVial.rb`:

```ruby
BLOCKED_MAP_IDS = [123]
BLOCKED_MAP_REASONS = {
  123 => _INTL("The PokeVial signal is blocked here.")
}
```

Reloaded Mart bundles/gifts/mystery boxes and Mystery Gift payloads can use the
same reward markers:

```json
{ "type": "pokevial", "quantity": 1 }
{ "type": "pokevial_charge", "quantity": 1 }
{ "type": "pokevial_refill" }
{ "type": "pokevial_max_uses", "max_uses": 4 }
```

Supported aliases include `poke_vial`, `pokevial_uses`, `POKEVIAL_USES`,
`POKEVIAL_CHARGE`, `POKEVIAL_REFILL`, `refill_pokevial`,
`pokevial_unlock`, and `POKEVIAL_MAX_USES`.

Reloaded also registers two hidden internal item datapatches in the Medicine
pocket. These can be sold, granted, or placed in Overworld Menu Quick Items like
normal Bag-usable items:

- `POKEVIAL_CHARGE` - restores one PokeVial charge.
- `POKEVIAL_REFILL` - restores all missing PokeVial charges.

## TM Vault

TM Vault is implemented in:

```text
Reloaded/Modules/002_TMVault.rb
```

The vault stores its data in the Reloaded save bucket under the `tm_vault`
system namespace, not on `$Trainer`:

```ruby
Reloaded::SaveData.system(:tm_vault)
```

Current saved fields:

- `moves`: registered move IDs.
- `sources`: source labels per registered move.
- `sort_mode`: current TM Vault sort mode.
- `egg_moves`: whether Relearn Moves includes egg moves.

The `[ TM Vault ]` button in the `RELOADED` category opens a submenu:

```text
TM Vault: Off / PokeNav
Egg Moves: Off / On
```

`TM Vault` controls PokeNav visibility. Default value: `PokeNav`.

`Egg Moves` controls whether the vault's Relearn Moves mode includes egg
moves. Default value: `On`.

The Reloaded Pause Menu entry remains available whenever the TM Vault module is
loaded, regardless of the PokeNav option. TM/HM and tutor moves are registered
when the player picks up, receives, buys, or is taught the move, and the vault
also scans the bag on open to catch existing machines.

The PokeNav icon is loaded from:

```text
Reloaded/Graphics/Pokegear/icon_TMVAULT.png
```

### Script Usage

Open the vault:

```ruby
TMVault.open
```

Register a move manually:

```ruby
TMVault.register(:THUNDERBOLT)
TMVault.register(:ICEBEAM, source: :script)
TMVault.register(:FLAMETHROWER, notify: true, source: :receive)
TMVault.egg_moves_enabled = false
```

Check saved data:

```ruby
TMVault.vault             # => registered move IDs
TMVault.source_for(:CUT)  # => source labels for that move
TMVault.sort_mode          # => 0 Name, 1 Type, 2 Category, 3 Recent
TMVault.egg_moves_enabled? # => true/false
```

Supported source labels are normalized to:

- `Machine`
- `Tutor`
- `Shop`
- `Pickup`
- `Receive`
- `Bag Scan`
- `Script`

If a saved move no longer exists, such as when a modded move is removed by a
disabled mod, TM Vault logs one warning for that move during validation and
removes it from the active vault list.

### Events

TM Vault emits these Reloaded events:

```ruby
Reloaded::Events.on(:tm_vault_move_registered, :my_mod) do |ctx|
  move_id = ctx[:move]
  source  = ctx[:source]
end

Reloaded::Events.on(:tm_vault_opened, :my_mod) do |ctx|
  count = ctx[:move_count]
end

Reloaded::Events.on(:tm_vault_move_taught, :my_mod) do |ctx|
  move_id = ctx[:move]
  pokemon = ctx[:pokemon]
end
```

Event payloads include:

- `:tm_vault_move_registered`: `:move`, `:move_data`, `:source`.
- `:tm_vault_opened`: `:move_count`.
- `:tm_vault_move_taught`: `:move`, `:move_data`, `:pokemon`.

## Reloaded Mart

Reloaded Mart is implemented in:

```text
Reloaded/Modules/003_ReloadedMart.rb
Reloaded/Modules/003a_ReloadedMartUI.rb
```

Standalone Reloaded Mart fetches the online catalog every time it opens,
validates it, and stores a last-good fallback cache in:

```ruby
Reloaded::SaveData.system(:reloaded_mart)
```

Catalog entries can reference mod-added items. If the item is missing, that
entry is skipped. If a bundle/gift grant is missing, the whole bundle/gift is
skipped. This lets a shared catalog include optional mod content without
breaking players who do not have that mod.

Example item entry:

```json
{
  "id": "my_mod:rare_seed",
  "kind": "item",
  "item": "MY_MOD_RARE_SEED",
  "name": "Rare Seed",
  "category_id": "event",
  "category_name": "EVENT",
  "tags": ["event", "my_mod"],
  "price": 2400,
  "requires": {
    "mods": ["my_mod"]
  }
}
```

Example bundle:

```json
{
  "id": "my_mod:seed_bundle",
  "kind": "bundle",
  "name": "Seed Bundle",
  "category_id": "bundles",
  "category_name": "BUNDLES",
  "price": 5000,
  "grants": [
    { "id": "MY_MOD_RARE_SEED", "qty": 2 },
    { "id": "POTION", "qty": 5 }
  ]
}
```

Register a runtime price modifier:

```ruby
ReloadedMart.register_price_modifier(:my_mod_sale, priority: 50) do |entry, ctx|
  next [] unless ctx[:mode] == :buy
  next [] unless entry.tags.include?("my_mod")
  [{ :id => "my_mod_sale", :label => "Mod Sale", :type => "percent", :value => -20 }]
end
```

Listen for purchases:

```ruby
Reloaded::Events.on(:reloaded_mart_purchase_completed, :my_mod) do |ctx|
  ctx[:entries].each do |entry|
    # entry[:id], entry[:kind], entry[:quantity], entry[:price]
  end
end
```

See `Reloaded/Documentation/ReloadedMart.md` for the complete schema, events,
transaction behavior, and vanilla mart wrapper notes.

## Per-Mod Settings

Mods can define editable settings in:

```text
Mods/<mod folder>/Settings.json
```

Player values are stored in the active profile, not in the mod folder.
Players can edit these values from `Options -> Mods -> Mod Settings`, or from
the installed mod's `Settings` action in the Mod Manager.

Use `Reloaded::ModSettings` at runtime:

```ruby
difficulty = Reloaded::ModSettings.get("example_mod", "difficulty", "Normal")
Reloaded::ModSettings.set("example_mod", "difficulty", "Hard")
```

Supported setting types are `toggle`, `enum`, `slider`, `number`,
`category_header`, and `spacer`.

See `Reloaded/Documentation/System.md` for the full mod settings reference.

## Browser Sources

The Mod Browser backend reads downloadable mod indexes from GitHub-hosted
`index.json` files. The built-in source is:

```text
https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded-Mods/main/index.json
```

Mods and published profiles listed in browser indexes can be downloaded by
profile imports and the in-game Browser page. Reloaded does not require local
Browser or Publish folders for public source data.

The protected `Spritepacks` browser entry reads its download list from the
public GitHub copy first:

```text
https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/main/Reloaded/Spritepacks.json
```

If the online fetch fails, it falls back to the shipped local file:

```text
Reloaded/Spritepacks.json
```

`full: true` marks the Full Spritepack and keeps it at the top. `updated_at`
uses `MM-DD-YY HH:MM:SS` and is the preferred newest-first sort value for
normal packs. `latest: true` marks the newest non-full pack for the `Latest`
submenu. Other packs appear under `All Files`, sorted newest-first by
`updated_at`, then by `version` or the number in the name. Each entry needs a
`name` and `url`; optional `extract_to` overrides the default game-root
extraction target for that pack.

See `Reloaded/Documentation/Manager.md` for the source and index formats.

## Publishing

Publishing uses the external Modders Tools script:

```text
Modders Tools/Publish to GitHub.bat
```

In-game, use:

```text
Mod Manager -> Tools -> Publish
```

The external script selects and validates the mod or profile, then does the
GitHub work before pushing.

## UI Hint Text

Use this format for Reloaded UI hint text:

```text
Action (input)
```

The normal order is:

```text
Confirm (C) Back (B) ActionInput (A) SpecialInput (Z) Others
```

Only include actions that are relevant to the current screen.
When `Input::ACTION` opens a page menu, label it as `Menu (A)`.

## Mod Folder Structure

Mods use this layout:

```text
Mods/
  example_mod/
    mod.json
    Scripts/
    Graphics/
    Audio/
    Fonts/
    Settings.json
    Documentation/
```

Required:

- `mod.json`

Optional:

- `Scripts/` - Ruby scripts loaded in alphabetical order.
- `Graphics/` - Graphics assets resolved at runtime.
- `Audio/` - Audio assets resolved at runtime.
- `Fonts/` - Font assets reserved for runtime resolution.
- `Settings.json` - Editable per-mod settings schema.
- `Changelog.txt` or `changelog.txt` - local changelog shown by the installed
  mod `View Changelog` action when no `changelogurl` is set.
- `Documentation/` - Mod author documentation.

## ModDev

`ModDev/` is a developer override folder.

When ModDev is enabled, Reloaded also scans:

```text
ModDev/
  example_mod/
    mod.json
```

If the same mod `id` exists in both `Mods/` and `ModDev/`, the `ModDev/`
version is used and the `Mods/` version is skipped.

ModDev can be changed from the in-game options menu under:

```text
Options -> Mods -> ModDev
```

The setting is stored in:

```text
Reloaded/Settings.txt
moddev=On
```

Changing it applies on the next mod scan or restart.

## Profiles

Profiles are named mod setups stored in:

```text
Mods/Reloaded/Profiles/
```

The active profile is selected by:

```text
Reloaded/Settings.txt
active_profile=Default
```

Profiles control:

- enabled mods,
- disabled mods,
- player-preferred load order,
- profile-scoped per-mod settings.

Profiles do not control `ModDev`, `Logging Mode`, or Reloaded visual options.

Example:

```json
{
  "id": "default",
  "name": "Default",
  "version": 1,
  "enabled_mods": ["example_mod"],
  "disabled_mods": [],
  "load_order": ["example_mod"],
  "mod_settings": {},
  "notes": "Default Reloaded mod profile."
}
```

Dependencies still load before dependents, even if `load_order` places them
later. Missing profile mods log warnings.

Useful profile API examples:

```ruby
Reloaded::Profiles.create("Testing")
Reloaded::Profiles.activate("Testing")
Reloaded::Profiles.enable_mod("example_mod")
Reloaded::Profiles.set_load_order(["library_mod", "example_mod"])
Reloaded::Profiles.set_mod_setting("example_mod", "difficulty", "Hard")
Reloaded::Profiles.export_profile("Testing", "Mods/Reloaded/Testing.json")
```

See `Reloaded/Documentation/Manager.md` for the full profile reference.

## Core And Modules

`Reloaded/Core/` contains framework systems that other Reloaded code depends on:
logging, settings, events, patches, save data, assets, profiles, mod loading,
and options.

`Reloaded/Modules/` is for Reloaded-owned feature systems that load after Core
is ready. Good examples are gameplay systems, optional UI replacements, or
feature modules that use the Core APIs.

Mods should not be placed in `Reloaded/Modules/`. External mods belong in
`Mods/<mod folder>/` or `ModDev/<mod folder>/`.

## Mod Manager Backend API

The Mod Manager exposes read-only helper methods for UI screens and debug
tooling.

```ruby
Reloaded::ModManager.mod_ids
Reloaded::ModManager.mod_rows
Reloaded::ModManager.mod_row("example_mod")
Reloaded::ModManager.mod_status("example_mod")
Reloaded::ModManager.dependency_status("example_mod")
Reloaded::ModManager.incompatibility_status("example_mod")
Reloaded::ModManager.profile_summary
```

`mod_rows` returns display-ready hashes with mod metadata, profile enabled
state, validation warnings/errors, dependency status, incompatibility status,
system tags, source folder, loaded state, and script count.

Common status values:

- `:enabled`
- `:disabled`
- `:missing_dependency`
- `:conflict`
- `:broken`
- `:invalid`
- `:missing`

## Mod Manager UI

The in-game Mod Manager UI is available from:

```text
Options -> Mods -> Mod Manager
```

Current UI features:

- installed mod list,
- active profile summary,
- search,
- filters for enabled, disabled, dependency issues, and conflicts,
- right-side mod details,
- dependency and incompatibility details,
- enable/disable through the active profile,
- load order mode with pick-up/place controls,
- installed mod update, changelog, settings, and uninstall actions,
- Profiles footer page for profile management and profile code import/export,
- Browser footer page for mod/profile downloads from the GitHub index,
- Tools footer page for logs, backups, modder tools, publishing, and admin-only
  index editing,
- restart-required exit warning for mod load changes,
- keyboard/controller and mouse hover/click support.

Changing profile state from the UI updates the active profile immediately and
refreshes mod metadata. Changes that affect the loaded mod set or load order
show a restart-required popup when leaving the full Mod Manager. Ruby scripts
are not hot-loaded or unloaded while the game is running, so script changes
should still be treated as restart-required.

## Modder Tools

The Mod Manager Tools page includes local utilities for mod development and
debugging:

```text
Mod Manager -> Tools
```

Log Files:

- `View Log.txt`
- `View Mods.txt`
- `View Coop.txt`
- `View LatestBugReport.txt`
- `Clear Logs`
- `Export`

Viewing a log opens the file directly from `Reloaded/Logging/`. Export uploads
the selected log to `paste.rs` and copies the returned URL to the clipboard.
`LatestBugReport.txt` is created automatically if it does not already exist.
Clear Logs empties all Reloaded log files for a fresh troubleshooting run.

Backup Mods:

- `All Mods`
- `Select Mods`

Backups are written as timestamped `.zip` files under:

```text
ModsBackup/
```

Backups use the bundled `REQUIRED_BY_INSTALLER_UPDATER/7z.exe`. The profile
folder `Mods/Reloaded/` is not included in mod backups.

Tools menu order:

- `Admin Tools` when local admin files are present
- `Template Generator`
- `Manifest Validator/Fixer`
- `Log Files`
- `Backup Mods`
- `Publish`

The manifest validator scans `Mods/` and enabled `ModDev/` folders and reports
missing or invalid manifest fields. The fixer only applies safe structural
defaults, such as missing `id`, `name`, `version`, `authors`, `dependencies`,
`tags`, `game`, `incompatible`, `changelogurl`, and
`minimum_reloaded_version`. It does not rewrite mod code.

The template generator can create:

- a starter mod folder with `mod.json`, `Scripts/`, assets folders,
  `Settings.json`, `Changelog.txt`, and documentation,
- a starter profile under `Mods/Reloaded/Profiles/` with blank publish-safe
  changelog metadata.

The backend API is:

```ruby
Reloaded::ModderTools.open_log("Log.txt")
Reloaded::ModderTools.export_log("Mods.txt")
Reloaded::ModderTools.backup_all_mods
Reloaded::ModderTools.validate_manifests
Reloaded::ModderTools.create_mod_template("My Mod")
Reloaded::ModderTools.create_profile_template("My Profile")
```


## Foundation Test Mod

`Mods/Foundation Test Mod/` is the permanent Reloaded regression test mod. It
replaces the old throwaway Example Mod and should stay small, stable, and easy
to inspect.

It intentionally covers:

- manifest loading through `mod.json`,
- per-mod settings through `Settings.json`,
- script loading through `Scripts/`,
- data patch coverage through `DataPatches/`,
- asset indexing through `Graphics/`,
- local changelog viewing through `Changelog.txt`,
- dependency shape documentation in `Documentation/dependency_example.json`.

Gameplay checks included by default:

- Route 101 classic `Land` and `LandDay` encounters are patched to Treecko.
- The first Hoenn rival fight is patched by script because it is not normal
  trainer data.
## Mod Manifest

Each mod must include `mod.json`:

```json
{
  "id": "example_mod",
  "game": "hoenn",
  "name": "Example Mod",
  "version": "1.0.0",
  "authors": ["Stonewall"],
  "description": "Example Reloaded mod.",
  "minimum_reloaded_version": "1.0.0",
  "dependencies": [],
  "incompatible": [],
  "tags": ["mod", "gameplay"],
  "changelogurl": "https://example.com/example_mod_changelog.txt"
}
```

Rules:

- `id` must use lowercase letters, numbers, and underscores.
- `id` is the stable identifier Reloaded uses for profiles, dependencies,
  browser entries, and published filenames.
- `game` must be `hoenn`. Empty values or other games such as
  `infinitefusion` are blocked so KIF/Infinite Fusion mods do not load in this
  fork.
- The mod folder name does not need to match `id`.
- `version` and `minimum_reloaded_version` use `Major.Minor.Patch`.
- `authors`, `dependencies`, and `tags` are arrays.
- `enabled` is legacy metadata; active profiles decide whether a mod loads.
- `changelogurl` is optional and should point to a raw text changelog if used.
  Mods can instead include a local `Changelog.txt`/`changelog.txt` in their mod
  folder.
- Dependencies load before mods that depend on them. Dependency `version`
  values are minimum required versions, not exact locks.
- If a dependency is missing, disabled in the active profile, or installed below
  the required version, Reloaded skips the dependent mod and reports the exact
  reason in the dependency details/logs.
- Browser downloads install dependency chains before the selected mod when the
  required dependency entries exist in the GitHub index.

`load_after`, `load_before`, `priority`, `type`, `scripts`, and
`minimum_base_version` are not part of the current manifest format.

## Mod Tags

Editable tag arrays live at the top of:

```text
Reloaded/Core/005_ModManager.rb
```

Author tags are grouped into role and content tags. System tags are assigned by
Reloaded or the Mod Manager.

Unknown author tags log warnings rather than blocking a mod.

Special entries are admin-controlled browser/index metadata. Mod authors cannot
grant this placement through normal `mod.json` tags. `Special Entry`,
and `Featured` are reserved admin labels; if they appear in normal mod tags,
Reloaded ignores them as display tags and logs a warning.

The current special-entry metadata is:

- `featured`: curated/admin-highlighted entry. Shows above special entries.
- `special_entry`: generic admin-highlighted entry shown above normal rows.

## Script Loading

Reloaded loads every Ruby file in:

```text
Mods/example_mod/Scripts/**/*.rb
```

Files load alphabetically, so mod authors should name ordered scripts like:

```text
001_Main.rb
002_Items.rb
003_Events.rb
```

Mods without a `Scripts/` folder can still provide metadata and assets.

## Asset Loading

Mod assets are not copied into base game folders.

Reloaded scans active mods and resolves assets at runtime:

```text
Mods/example_mod/Graphics/Pictures/foo.png
Mods/example_mod/Audio/BGM/song.ogg
```

When the game asks for:

```text
Graphics/Pictures/foo
Audio/BGM/song
```

Reloaded checks active mod assets first, then falls back to vanilla files.

The first resolver patches common helper paths:

- `RPG::Cache.load_bitmap`
- `RPG::Cache.load_bitmap_path`
- `AnimatedBitmap.new`
- `pbResolveBitmap`
- `pbBitmapName`
- `FileTest.image_exist?`
- `FileTest.audio_exist?`
- `Audio.bgm_play`
- `Audio.me_play`
- `Audio.bgs_play`
- `Audio.se_play`

Reloaded does not globally patch `Bitmap.new` yet.

## Planned Documentation Sections

These sections should be added as the systems are created:

- dependency rules,
- broader custom content registration,
- compatibility guidelines.
