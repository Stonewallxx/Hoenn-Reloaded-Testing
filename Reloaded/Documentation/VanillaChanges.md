# Hoenn Reloaded - Vanilla File Change Log

This file tracks every intentional edit made to base game files outside the
Reloaded folder. When a new base game update is imported, use this log to check
which custom fork changes must be preserved or re-applied.

## Rules

- Record every base file edit made outside `Reloaded/`, `Mods/`, or other
  custom-only folders.
- Keep each entry small and specific.
- Include the file path, reason, anchor location, and a short reapply check.
- Prefer foundation/platform edits here. Feature code should live in Reloaded
  modules whenever practical.

---

## CHANGE 001 - Reloaded Bootstrap Hook

**File:** `Data/Scripts/999_Main/999_Main.rb`

**Function:** `mainFunctionDebug`

**Insert after:** `PluginManager.runPlugins`

**Insert before:** `Compiler.main`

**Reason:** Loads the Hoenn Reloaded framework during startup while leaving the
base game boot flow intact. The real loader code lives in
`Reloaded/000_Bootstrap.rb`.

**Code:**

```ruby
    begin
      _reloaded_bootstrap = File.expand_path("./Reloaded/000_Bootstrap.rb")
      if File.exist?(_reloaded_bootstrap)
        load _reloaded_bootstrap
        Reloaded::Bootstrap.boot if defined?(Reloaded::Bootstrap)
      end
    rescue Exception => e
      puts "[Reloaded] Bootstrap error: #{e.class}: #{e}" rescue nil
      puts e.backtrace.join("\n") rescue nil
    end
```

**Reapply/check after base update:**

1. Open `Data/Scripts/999_Main/999_Main.rb`.
2. Find `PluginManager.runPlugins`.
3. Confirm the bootstrap block appears immediately after it.
4. Confirm `Compiler.main` still appears after the bootstrap block.
