#======================================================
# Reloaded Modding Documentation
# Author: Stonewall
#======================================================
# Living documentation for modding against Hoenn Reloaded.
#
# Responsibilities:
#   - Explain Reloaded systems intended for modding use.
#   - Record recommended modding patterns as systems are added.
#   - Point modders toward logging, events, patches, and future APIs.
#   - Keep compatibility notes in one central document.
#
#======================================================

This file is the main modder-facing reference for Hoenn Reloaded.

It should be updated whenever a Reloaded system gains a public API that modders
are expected to use.

## Current Status

Reloaded is still building its modding foundation. The current public systems
are:

- `Reloaded::Log`
- `Reloaded::Events`
- `Reloaded::Hooks` compatibility alias
- `Reloaded::Patches`

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

See `Reloaded/Documentation/Logging.md` for the full logging reference.

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

See `Reloaded/Documentation/Patches.md` for the full patches reference.

## Future Sections

These sections should be added as the systems are created:

- mod folder format,
- mod metadata format,
- dependency rules,
- load order rules,
- custom content registration,
- data patching,
- asset overrides,
- compatibility guidelines,
- in-game settings integration.
