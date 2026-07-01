#======================================================
# Reloaded Save Data Documentation
# Author: Stonewall
#======================================================
# Documents the Reloaded save bucket for systems and mods.
#
# Responsibilities:
#   - Explain where Reloaded/mod save data is stored.
#   - Explain the public Reloaded::SaveData API.
#   - Explain namespacing rules for mods and systems.
#   - Record safety rules for save-compatible values.
#
#======================================================

`Reloaded::SaveData` gives Reloaded systems and mods one central save bucket.

The base game save file receives one Reloaded entry:

```ruby
:reloaded
```

Mods should store their data inside that bucket instead of adding fields to
vanilla objects like `$Trainer`, `$PokemonGlobal`, `$PokemonSystem`, or map
metadata.

## Structure

Reloaded stores data in this shape:

```ruby
{
  :schema_version => 1,
  :systems => {},
  :mods => {},
  :metadata => {}
}
```

`systems` is for Reloaded framework systems.

`mods` is for mod data.

## Mod Use

```ruby
Reloaded::SaveData.set(:example_mod, :quest_started, true)
Reloaded::SaveData.get(:example_mod, :quest_started, false)
Reloaded::SaveData.has?(:example_mod, :quest_started)
Reloaded::SaveData.delete(:example_mod, :quest_started)
```

You can also work with your whole mod namespace:

```ruby
save = Reloaded::SaveData.mod(:example_mod)
save["quest_stage"] = 2
save["chosen_partner"] = :TREECKO
```

## Reloaded System Use

Reloaded framework systems should use the `:systems` section:

```ruby
Reloaded::SaveData.set(:logging, :last_mode, "Developer", section: :systems)
Reloaded::SaveData.get(:logging, :last_mode, "Player", section: :systems)
```

or:

```ruby
save = Reloaded::SaveData.system(:logging)
save["last_mode"] = "Developer"
```

## Save Safety

Values must be compatible with Ruby `Marshal.dump`, because the base game save
system writes the save file with Marshal.

Safe values usually include:

- strings,
- numbers,
- symbols,
- booleans,
- arrays,
- hashes,
- simple save-compatible game objects.

Avoid storing:

- windows,
- sprites,
- bitmaps,
- viewports,
- procs/lambdas,
- open files,
- temporary scene objects.

`Reloaded::SaveData.set` rejects values that cannot be marshaled and logs a
warning through the `:save_data` log channel.

## Events

Reloaded emits these events:

- `:reloaded_save_loaded`
- `:reloaded_save_saving`

Both receive:

```ruby
{
  :data => Reloaded::SaveData.data
}
```

## Compatibility Notes

The Reloaded save bucket is registered without a hard class requirement so old
saves that do not have `:reloaded` data yet are not treated as corrupt.

If a save has no Reloaded bucket, a new empty bucket is created when the save is
loaded or when a new game starts.
