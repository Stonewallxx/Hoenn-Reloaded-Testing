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
  :conflict_group => "mart_buy_screen",
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

- either patch explicitly lists the other in `:metadata => { :conflicts_with => [...] }`,
- either patch uses `:replace`,
- either patch uses `:asset_override`,
- both patches use the same `:conflict_group`,
- both patches use the same type and same priority,
- both patches are order-sensitive and share the same priority.

`:replace` and `:asset_override` conflicts are logged as critical because only
one replacement can usually win cleanly.

Same-type/same-priority conflicts are logged as warnings because load order may
matter and should be reviewed.

`:event_bridge` patches are stackable by default. Use them when possible if a
system is only exposing a vanilla behavior as a Reloaded event.

## Conflict Metadata

Optional fields can make conflict reports more accurate:

```ruby
Reloaded::Patches.register(
  :example_patch,
  :target => "SomeClass#some_method",
  :type => :wrap,
  :owner => :example_mod,
  :priority => 100,
  :conflict_group => "some_method_ui_flow",
  :allow_multiple => false,
  :severity => :warning,
  :metadata => {
    :compatible_with => ["other_mod/known_safe_patch"],
    :conflicts_with => ["other_mod/known_conflicting_patch"]
  }
)
```

- `:conflict_group` marks patches that compete for the same broader behavior
  even if their raw target strings differ.
- `:allow_multiple` tells the registry not to conflict this patch with other
  patches on the same target.
- `:severity` can raise an order-sensitive conflict to `:critical`.
- `:compatible_with` suppresses a known safe pair.
- `:conflicts_with` forces a known unsafe pair to conflict.

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
Reloaded::Patches.targets
Reloaded::Patches.target_summary("PokemonMartScreen#pbBuyScreen")
Reloaded::Patches.grouped_by_target
```

## Project Rule

Any Reloaded system that substantially changes vanilla behavior should register
its patch point. This gives future modders and bug reports a clear map of what
Reloaded touched.
