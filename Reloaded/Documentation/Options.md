#======================================================
# Reloaded Options Documentation
# Author: Stonewall
#======================================================
# Documents the Reloaded options framework.
#
# Responsibilities:
#   - Explain reusable option row types.
#   - Explain Reloaded option theme settings.
#   - Record how the options scene is patched.
#   - Guide future options menu and Mod Manager settings work.
#
#======================================================

`Reloaded::Options` extends the base game options system without editing the
vanilla options file.

This layer adds reusable controls, rendering behavior, and a consolidated
collapsible category layout for the main Options menu.

## Stored Settings

Generic Reloaded option UI settings are stored on `$PokemonSystem` so they are
saved with the normal save file:

```ruby
$PokemonSystem.reloaded_option_theme
$PokemonSystem.reloaded_category_theme
$PokemonSystem.reloaded_cursor_theme
$PokemonSystem.reloaded_options_cursor_theme
$PokemonSystem.reloaded_small_text
```

`reloaded_small_text` controls the global small text toggle.

`reloaded_speech_follows_menu` controls whether speech/dialogue windows use the
selected menu frame.

Reloaded option defaults:

- `Menu Frame`: `RLD Transparent Dark`
- `Speech Follows Menu`: `On`
- `Global Small Text`: `On`
- `Options Cursor Color`: `White`

## Theme Data

Themes live in:

```ruby
Reloaded::Options::COLOR_THEMES
Reloaded::Options::CURSOR_THEMES
```

Use:

```ruby
Reloaded::Options.theme_names
Reloaded::Options.cursor_theme_names
```

for option rows that let players choose themes.

## Menu Frames

Reloaded adds menu frames from:

```text
Reloaded/Graphics/Windowskins/
```

Each `.png` file in that folder is used as a menu frame option. The Reloaded
menu frame option does not list vanilla `Settings::MENU_WINDOWSKINS` entries.

Dark-themed Reloaded frames are detected by filename:

- names ending in `a`, such as `RLD Choice 1a.png`,
- `default_transparent.png`,
- `default_opaque.png`.

Reloaded does not edit `Settings::MENU_WINDOWSKINS`. Instead,
`Reloaded::Options.menu_frame_path(index)` resolves indexes only against
`Reloaded/Graphics/Windowskins/`.

The consolidated Options menu receives:

- `Global Small Text`
- `Menu Frame`
- `Speech Follows Menu`
- `Mod Manager`
- `ModDev`
- `Logging Mode`

## Consolidated Categories

The main Options menu is reorganized into collapsible categories:

- `RELOADED`
- `VISUALS & UI`
- `GAMEPLAY`
- `ECONOMY`, shown when economy options exist
- `CHALLENGE`
- `SYSTEM`
- `MODS`
- `DEVELOPER`
- `OTHER`, only if an unknown option is left over

`RELOADED` is first in the category order, but it is hidden while it has no
options. The old button hub is replaced with one flat menu. Existing base game
option objects are moved into these groups without replacing their original
getters/setters where possible.

Each category starts collapsed. Selecting a category header expands or collapses
that section.

Categories with no options are hidden automatically. `ECONOMY` is part of the
category order now, but it will not appear until economy options are added.

`VISUALS & UI` currently contains:

- `UI Color`
- `Category Color`
- `Cursor Color`
- `Options Cursor Color`
- `Global Small Text`
- `Menu Frame`
- `Speech Frame`
- `Speech Follows Menu`
- base visual/sprite options

`Cursor Color` currently applies to:

- the base Bag item list cursor
- the base Mart item list cursor

It does not apply globally to every command window yet.

The Options menu uses a pulsing full-row selection box instead of the vanilla
arrow. `Options Cursor Color` controls this selection box and defaults to white.

When the selected `Menu Frame` is not dark, Reloaded forces readable dark text
for the Options menu and base Pause menu command window. If `Options Cursor
Color` is set to `White` while using a non-dark frame, Reloaded changes it to
`Black` so the cursor remains visible.

Future Reloaded UI screens should use `ReloadedDrawHelper#reloaded_cursor_fill`,
`ReloadedDrawHelper#reloaded_cursor_border`, and
`ReloadedDrawHelper#reloaded_draw_selection_box` when drawing configurable
selection highlights.

Hint text should use the format `Action (input)`. The normal order is:
`Confirm (C) Back (B) ActionInput (A) SpecialInput (Z) Others`.

`MODS` currently contains:

- `Mod Manager` - opens the in-game Reloaded Mod Manager UI.
- `ModDev` - toggles scanning `ModDev/` on the next mod scan or restart.
  Persists as `moddev=On/Off` in `Reloaded/Settings.txt`.

`DEVELOPER` currently contains:

- `Logging Mode` - writes `logging_mode=...` to `Reloaded/Settings.txt`
  through `Reloaded::Log`.

When `Speech Follows Menu` is On, dialogue boxes use the selected menu frame.

The option screen refreshes its visible skins while cycling these options:

- `Menu Frame` updates the title and options windows immediately.
- `Speech Frame` updates the description textbox through the base options flow.
- `Speech Follows Menu` reapplies the description textbox skin immediately.

## Option Types

### `CategoryHeader`

Non-interactive centered section label.

```ruby
CategoryHeader.new("SYSTEM", "Audio, text, and screen options.")
```

### `CollapsibleHeader`

Interactive section label. Pressing confirm toggles collapsed/expanded state.

```ruby
CollapsibleHeader.new("VISUALS & UI", "Appearance settings.", collapsed: true)
```

### `TextDisplayOption`

Read-only row with dynamic text on the right.

```ruby
TextDisplayOption.new("Active Profile", proc { "Default" })
```

### `ActionButton`

Button row that activates only on confirm/use, not left/right.

```ruby
ActionButton.new("Reset", proc { reset_options })
```

### `LockableEnumOption`

Enum row that can block value changes while locked.

```ruby
LockableEnumOption.new(
  "Example",
  ["Off", "On"],
  proc { 0 },
  proc { |v| nil },
  proc { true },
  "Locked option example.",
  locked_label: "Locked"
)
```

### `HiddenOption`

Invisible state row that participates in option get/set behavior.

### `Spacer`

Invisible empty row for spacing.

## Window Patch

`Window_ReloadedOption` replaces the base option window through
`PokemonOption_Scene#initOptionsWindow`.

It adds:

- themed option text,
- themed category headers,
- centered action buttons,
- cycling enum arrows,
- corrected slider drawing,
- support for hidden/spacer/header rows,
- support for long description scrolling,
- removal of the vanilla `+32` height overshoot.

## Slider Fix

Reloaded changes `SliderOption#next` and `SliderOption#prev` to operate on the
actual value. This supports negative ranges and custom intervals correctly.

## Future Work

- Add Mod Manager profile/settings controls.
