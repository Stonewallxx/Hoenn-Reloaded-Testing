#======================================================
# Reloaded Events Documentation
# Author: Stonewall
#======================================================
# Documents the public Reloaded::Events API.
#
# Responsibilities:
#   - Explain how to register event handlers.
#   - Explain how to emit notification events.
#   - Explain how to use decision events.
#   - List the initial lifecycle events.
#
#======================================================

`Reloaded::Events` is the public event layer for Reloaded framework code and
future mods. It does not replace specialized base game systems such as
`ItemHandlers`, `BattleHandlers`, or `SaveData.register`. Use those systems when
they are the correct fit. Use Reloaded events for broader lifecycle and
cross-system integration points.

## Register A Handler

```ruby
Reloaded::Events.on(:bootstrap_loaded, :my_feature, priority: 100) do |ctx|
  Reloaded::Bootstrap.log("My feature saw #{ctx[:event]}") rescue nil
end
```

- `event_name`: Symbol naming the event.
- `id`: Unique handler ID for this event. Registering the same ID again replaces
  the old handler.
- `priority`: Lower numbers run earlier.
- `ctx`: Hash passed to the handler.

## Emit An Event

```ruby
Reloaded::Events.emit(:item_received, {
  :item => item,
  :quantity => quantity
})
```

`emit` runs every handler registered for the event and returns the number of
handlers called.

## Decision Events

```ruby
result = Reloaded::Events.first_result(:mart_opening, {
  :stock => stock
})
```

`first_result` runs handlers in priority order and returns the first non-`nil`
value. Use this for intercept/decision points where one system may handle the
request.

## Remove A Handler

```ruby
Reloaded::Events.remove(:bootstrap_loaded, :my_feature)
```

## Initial Lifecycle Events

- `:bootstrap_loaded` - core files have loaded enough for the event system to
  exist.
- `:core_loaded` - all files in `Reloaded/Core` have been loaded.
- `:modules_loaded` - all files in `Reloaded/Modules` have been loaded.
- `:game_data_loaded` - base `GameData.load_all` finished and Reloaded is
  refreshing runtime data patch targets.
- `:data_patches_loaded` - enabled mod data patch files have been scanned and
  applied to Reloaded's runtime registry.
- `:mods_loaded` - the Mod Manager finished scanning and loading enabled mods.
- `:reloaded_save_loaded` - Reloaded's central save bucket was loaded.
- `:reloaded_save_saving` - Reloaded's central save bucket is about to save.

More events should be added only when a real base-game integration point is
needed. Any new base-file edit must also be documented in
`Reloaded/Documentation/VanillaChanges.md`.

## Gameplay Bridge Events

`Reloaded/Core/001a_EventBridges.rb` emits notification-only events around
common vanilla methods. These events do not alter vanilla results.

Item events:

- `:item_receive_started`
- `:item_received`

Context:

- `:method` - wrapped method name, usually `:pbReceiveItem`.
- `:args` - original method arguments.
- `:received` - after-event result, normally `true` or `false`.
- `:result` - same raw return value as `:received`.

Money events:

- `:money_change_started`
- `:money_changed`

Context:

- `:method` - wrapped method name, usually `:pbReceiveMoney`.
- `:args` - original method arguments. The first entry is the money delta.
- `:result` - raw return value.

Wild battle request events:

- `:wild_battle_requested`
- `:wild_battle_finished`

Context:

- `:method` - wrapped method name, usually `:pbWildBattle`.
- `:args` - original method arguments.
- `:player_won` - after-event result from `pbWildBattle`.
- `:result` - same raw return value as `:player_won`.

Trainer battle request events:

- `:trainer_battle_requested`
- `:trainer_battle_finished`

Context:

- `:method` - wrapped method name, usually `:pbTrainerBattle`.
- `:args` - original method arguments.
- `:player_won` - after-event result from `pbTrainerBattle`.
- `:result` - same raw return value as `:player_won`.

Battle lifecycle events:

- `:battle_started`
- `:battle_ended`

Context:

- `:battle` - active `PokeBattle_Battle` instance.
- `:wild` - whether the battle is a wild battle.
- `:trainer` - whether the battle is a trainer battle.
- `:decision` - battle decision on `:battle_ended`.

Map events:

- `:map_setup_started`
- `:map_setup_finished`
- `:player_transfer_started`
- `:player_transfer_finished`

Context:

- `:map_id` - map being set up, for map setup events.
- `:old_map_id` - previous map ID when known.
- `:new_map_id` - target/current map ID for transfer events.
- `:x`, `:y`, `:direction` - player transfer position data when known.
- `:game_map` - active `Game_Map` instance for map setup events.
- `:scene` - active `Scene_Map` instance for transfer events.

## Logging

Event registration and emission diagnostics are written through
`Reloaded::Log` when Developer Mode logging is active. Handler failures are
logged as event exceptions.
