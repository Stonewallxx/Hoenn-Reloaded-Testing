#======================================================
# Reloaded Patches Documentation
# Author: Stonewall
#======================================================
# Documents the Reloaded::Patches registry and conflict logger.
#
# Responsibilities:
#   - Explain what a patch means in Reloaded.
#   - Explain patch types and conflict detection.
#   - Show how Reloaded systems and future mods should register changes.
#   - Record how patch conflicts are logged.
#
#======================================================

`Reloaded::Patches` is a registry for anything that changes, wraps, replaces,
bridges, or overrides base-game behavior.

This first version does not automatically modify game code. It records patch
points and logs conflicts so Reloaded can explain what changed and why.

## Basic Use

```ruby
Reloaded::Patches.register(
  :mart_ui_override,
  :target => "PokemonMartScreen#pbBuyScreen",
  :type => :wrap,
  :file => __FILE__,
  :owner => :reloaded,
  :priority => 100,
  :reason => "Route marts through Reloaded's custom mart UI.",
  :recommended_fix => "Disable one mart UI patch or move the change to an event hook."
)
```

## Patch Types

- `:wrap` - Runs code around an existing method or behavior.
- `:replace` - Replaces an existing method, behavior, file, or value.
- `:append` - Adds behavior after an existing flow.
- `:prepend` - Adds behavior before an existing flow.
- `:alias` - Uses alias-based method extension.
- `:event_bridge` - Connects vanilla behavior to a Reloaded event.
- `:data_patch` - Changes structured game data.
- `:asset_override` - Overrides a file or asset.

## Conflict Rules

The registry marks a conflict when multiple patches target the same method,
data file, or asset and at least one of these is true:

- either patch uses `:replace`,
- either patch uses `:asset_override`,
- both patches use the same type and same priority.

`:replace` and `:asset_override` conflicts are logged as critical because only
one replacement can usually win cleanly.

Same-type/same-priority conflicts are logged as warnings because load order may
matter and should be reviewed.

## Log Output

Patch registrations are logged in developer mode through the `:patches` channel.

Conflicts are written to `Reloaded/Logging/Log.txt` and also create a `[REPORT]`
block with:

- target,
- patch owners and IDs,
- patch types,
- priorities,
- source files,
- reasons,
- recommended fix.

## Querying

```ruby
Reloaded::Patches.registered
Reloaded::Patches.registered("PokemonMartScreen#pbBuyScreen")
Reloaded::Patches.conflicts
Reloaded::Patches.conflict?("PokemonMartScreen#pbBuyScreen")
Reloaded::Patches.summary
Reloaded::Patches.write_summary
```

## Project Rule

Any Reloaded system that substantially changes vanilla behavior should register
its patch point. This gives future modders and bug reports a clear map of what
Reloaded touched.
