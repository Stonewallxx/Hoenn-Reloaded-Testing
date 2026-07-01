#======================================================
# Reloaded Logging Documentation
# Author: Stonewall
#======================================================
# Documents the public Reloaded::Log API and log file layout.
#
# Responsibilities:
#   - Explain the Reloaded log files.
#   - Explain log levels and modes.
#   - Explain report blocks.
#   - Record the project rule for logging new systems.
#
#======================================================

Reloaded logs are stored in `Reloaded/Logging/`.

## Log Files

- `Log.txt` - Main Reloaded framework/fork log.
- `Mods.txt` - Mod-related logging and mod author output.
- `Coop.txt` - Multiplayer/co-op logging.
- `Reports/` - Reserved folder for future exported reports.

## Log Levels

- `[DEBUG]` - Developer-only diagnostic detail.
- `[INFO]` - Normal status.
- `[Warning]` - Minor issue; the system or mod can continue.
- `[ERROR]` - Unexpected failure that was handled if possible.
- `[Critical]` - Major issue; the mod/system cannot continue.
- `[FATAL]` - Startup or game-critical failure.

## Log Modes

Set `Reloaded/LogMode.txt` to one of these values:

- `Player` - Shorter, readable logs focused on fixes.
- `Developer` - Detailed technical logging. Default while the fork is early.
- `Bug Report` - Compact report-focused mode for exported diagnostics.

The default tracked value is:

```text
Developer
```

Code can change the mode with:

```ruby
Reloaded::Log.set_mode("Player")
Reloaded::Log.set_mode("Developer")
Reloaded::Log.set_mode("Bug Report")
```

`Developer` mode writes debug messages. `Player` and `Bug Report` modes skip
debug messages.

## Basic Use

```ruby
Reloaded::Log.info("Boot start", :bootstrap)
Reloaded::Log.warning("Optional module missing", :framework)
Reloaded::Log.critical("Mod cannot load", :mods)
Reloaded::Log.mod("example_mod", "Loaded settings")
Reloaded::Log.coop("Session started")
```

## Exceptions

```ruby
Reloaded::Log.exception("Event handler failed", error, channel: :events)
```

## Failure Reports

```ruby
Reloaded::Log.report(
  :type => "Mod Load Failure",
  :mod_id => "example_mod",
  :mod_name => "Example Mod",
  :version => "1.0.0",
  :level => :critical,
  :file_path => "Mods/example_mod/main.rb",
  :dependency_status => "Missing core_utils >= 1.2.0",
  :recommended_fix => "Install core_utils or disable Example Mod.",
  :error => error
)
```

Reports are written inside `Log.txt` with `[REPORT]` and `[/REPORT]` tags.

## Bug Report Export

```ruby
Reloaded::Log.export_bug_report
```

This writes `Reloaded/Logging/LatestBugReport.txt` with version information,
current warning/error counts, and the latest report blocks from `Log.txt`.

Generated log files are ignored by Git. Only the logging system, documentation,
`LogMode.txt`, and logging-folder ignore files should be tracked.

## Project Rule

Any new Reloaded-created file, or any system we substantially change, should
include appropriate logging. At minimum, log:

- startup/load success,
- validation warnings,
- recoverable errors,
- critical failures,
- final status when the system performs multi-step work.
