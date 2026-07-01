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

More events should be added only when a real base-game integration point is
needed. Any new base-file edit must also be documented in
`Reloaded/Documentation/VanillaChanges.md`.

## Logging

Event registration and emission diagnostics are written through
`Reloaded::Log` when Developer Mode logging is active. Handler failures are
logged as event exceptions.
