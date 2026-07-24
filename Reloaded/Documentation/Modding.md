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
- `Reloaded::Platform`
- `Reloaded::Download`
- `Reloaded::Archive`
- `Reloaded::FileActions`
- `Reloaded::RemoteData`
- `Reloaded::Task`
- `Reloaded::ProgressWindow`
- `Reloaded::Rewards`
- `Reloaded::Diagnostics`
- `Reloaded::ModArchives`
- `Reloaded::ModDevelopment`
- `Reloaded::ModderTools`
- `Reloaded::Profiles`
- `Reloaded::ModSettings`
- `Reloaded::Options`
- `Reloaded::PopupWindow`
- `Reloaded::ActionMenu`
- `Reloaded::TextInput`
- `Reloaded::ListState`
- `Reloaded::ListPicker`
- `Reloaded::GameDataPicker`
- `Reloaded::NumberPicker`
- `Reloaded::Form`
- `Reloaded::HintText`
- `Reloaded::InputBindings`
- `Reloaded::Toast`
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

## API Contracts

Reloaded APIs are classified so mods can distinguish supported integration
points from compatibility and development surfaces:

- `stable` - supported public APIs intended for mods.
- `compatibility` - retained aliases or older surfaces; prefer the replacement.
- `developer` - diagnostics, publishing, archives, and development tools.
- `internal` - implementation details with no compatibility promise.

Inspect a contract without loading or calling the target system:

```ruby
Reloaded::API.contract(:events)
Reloaded::API.public?(:events)
Reloaded::API.available?(:events)
Reloaded::API.contracts
```

Contract hashes returned to callers are copies and cannot mutate the registry.
Compatibility code can emit a once-per-session developer warning without
showing a player popup:

```ruby
Reloaded.deprecate("Reloaded::Hooks", :replacement => "Reloaded::Events")
```

`Reloaded::Hooks` and `Reloaded::ModderTools` remain available for existing
mods. New integrations should use their listed replacements.

## Systems And Feature Flags

Most content mods do not need to register a system. Register one when a mod
provides a substantial reusable subsystem with dependencies, save data, or
public integration points:

```ruby
Reloaded.register_system(
  :example_quests,
  :name => "Example Quests",
  :owner => :example_mod,
  :required_systems => [:save_data, :events],
  :save_keys => [:example_mod]
)
```

Check an optional Reloaded integration with one call:

```ruby
if Reloaded::Systems.active?(:poke_vial)
  # Integrate with the PokeVial API.
else
  Reloaded::Log.mod("example_mod", Reloaded::Systems.reason(:poke_vial))
end
```

Mods with unfinished or optional structural subsystems can register feature
flags:

```ruby
Reloaded::Features.register(
  :example_advanced_quests,
  :name => "Advanced Quests",
  :owner => :example_mod,
  :default => false,
  :classification => :experimental
)

return unless Reloaded::Features.active?(:example_advanced_quests)
```

Ordinary player preferences should remain normal Options settings. Feature
flags are intended for structural availability, staged development, platform
restrictions, and safe mod requirements.

Official system and feature IDs can be inspected through:

```ruby
Reloaded::Systems.systems
Reloaded::Features.features
```

See `Reloaded/Documentation/System.md` for the complete registration fields,
states, classifications, and override scopes.

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

## Mod Validation

Mods can register diagnostics without editing foundation files:

```ruby
Reloaded::Validation.register(
  :example_mod_assets,
  :owner => :example_mod,
  :category => :assets,
  :phase => :developer
) do
  next [] if pbResolveBitmap("Graphics/Pictures/example_icon")
  {
    :severity => :warning,
    :code => :missing_example_icon,
    :message => "Example Mod icon is missing.",
    :recommended_fix => "Reinstall Example Mod."
  }
end
```

Validators return `nil`, `true`, a finding hash, or an array of finding hashes.
Supported phases are `boot`, `modules_loaded`, `game_data_loaded`,
`save_loaded`, `developer`, and `release`. Validator exceptions are isolated
and reported rather than stopping the game.

Background validation keeps findings in memory and sends serious results to
the bug report without continuously writing a separate validation file.
`Reloaded::Validation.refresh_report` reruns the non-release checks and writes
`Reloaded/Logging/ValidationReport.txt` when a detailed report is needed.

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

Save metadata can be inspected for diagnostics and compatibility reporting:

```ruby
metadata = Reloaded::SaveData.metadata
saved_with = Reloaded::SaveData.last_saved_with_version
```

The returned metadata is a defensive copy. Mods should not use metadata as
their own storage area; use the mod namespace APIs instead.

### Mod Save Migrations

When a mod changes the shape of its saved data, register sequential namespace
migrations before the selected game is loaded:

```ruby
Reloaded::SaveMigrations.register_mod(
  :example_mod,
  :from => 0,
  :to => 1
) do |data|
  data["enabled"] = true unless data.key?("enabled")
  data
end
```

Each step must advance by one version. Reloaded stores the resulting version as
`_schema_version` in that mod's namespace. Migration blocks may mutate and
return the supplied hash, or return a replacement hash.

Do not migrate another mod's namespace or base-game save objects through this
API. A failed mod migration preserves the original namespace, logs the failure,
and allows unrelated migrations to continue.

When the selected save requires a Reloaded schema migration, Reloaded creates
and verifies a rolling backup of the source slot before running the migration.
If the backup fails, the migration is cancelled and Reloaded save writes are
blocked for that session.

Do not add random fields to vanilla save objects for mod data unless there is no
Reloaded API that can handle the use case.

See `Reloaded/Documentation/System.md` for the full save data reference.

## Action Menu API

Use `Reloaded::ActionMenu` for state-aware command menus. It delegates drawing,
scrolling, mouse handling, Back behavior, and modal input consumption to
`Reloaded::PopupWindow`.

```ruby
commands = [
  {
    :id => :use,
    :label => "Use",
    :enabled => proc { |context| context[:usable] },
    :disabled_reason => "This item cannot be used here.",
    :callback => proc { |context| context[:scene].use_item }
  },
  {
    :id => :discard,
    :label => "Discard",
    :visible => proc { |context| !context[:key_item] },
    :confirm => "Throw this item away?",
    :callback => proc { |context| context[:scene].discard_item }
  }
]

selected = Reloaded::ActionMenu.open(
  "Item Actions",
  commands,
  { :scene => self, :usable => true, :key_item => false },
  :remember_key => :example_item_actions,
  :list_state => @list_state
)
```

Each command requires a unique `:id` other than the reserved `:back` ID and
supports `:label`, `:visible`,
`:enabled`, `:disabled_reason`, `:callback`, `:confirm`, `:close_on_run`,
`:color`, and `:align`. Labels and state values may be static or callable.
Callables can accept no arguments, the supplied context, or the context and
normalized command.

Disabled commands remain navigable but dimmed. Activating one plays the denial
sound, displays its reason, and returns to the same row. Hidden commands are not
shown. Back returns `:back` and never invokes a command callback.

`Reloaded::ActionMenu.open` executes the selected callback.
`Reloaded::ActionMenu.choose` only returns the selected command ID, which is
useful when an existing scene must preserve its own dispatch logic. Pass
`:close_on_run => false` on a command to reevaluate and reopen the menu after
its callback. Options include `:start_id`, `:remember_key`, `:add_back`,
`:back_label`, `:list_state`, `:on_back`, and normal PopupWindow presentation
options.

Short aliases are available as `Reloaded.action_menu` and
`Reloaded.choose_action`.

## Popup Window API

Use `Reloaded::PopupWindow` when a mod needs a Reloaded-styled popup instead of
copying UI code.

```ruby
Reloaded::PopupWindow.message("Settings saved.")
```

Short aliases are also available for simple mod scripts and event calls:

```ruby
Reloaded.message("Settings saved.")

if Reloaded.confirm("Use this?")
  # do work
end

choice = Reloaded.choice("Choose a reward", ["Potion", "Rare Candy", "Back"])
Reloaded.toast("Downloaded.")
```

The same short helpers are also exposed under `Reloaded::Confirm` for modders
who prefer a grouped namespace:

```ruby
Reloaded::Confirm.message("Settings saved.")
Reloaded::Confirm.confirm("Use this?")
Reloaded::Confirm.choice("Choose a reward", ["Potion", "Rare Candy", "Back"])
Reloaded::Confirm.toast("Downloaded.")
```

Confirm popups return `true` or `false`.

```ruby
if Reloaded::PopupWindow.confirm("Enable this feature?")
  # apply setting
end
```

Choice popups return the selected value, or `-1` if the player backs out.

```ruby
choice = Reloaded::PopupWindow.choice("Choose a reward", [
  "Potion",
  "Rare Candy",
  { :label => "Unavailable", :disabled => true },
  { :label => "Back", :value => -1, :back => true }
])
```

Section headers are centered and cannot be selected.

```ruby
Reloaded::PopupWindow.choice("Spritepacks", [
  { :label => "Latest", :header => true },
  { :label => "Full Spritepack", :value => :full },
  { :label => "Latest Pack", :value => :latest },
  { :label => "All Files", :header => true },
  { :label => "Back", :value => -1, :back => true }
])
```

Command popups can run procs safely. Failures are logged and shown as a Reloaded
error popup instead of being silently swallowed.

```ruby
Reloaded::PopupWindow.command("Tools", [
  ["Open Folder", proc { MyMod.open_folder }],
  { :label => "Back", :value => -1, :back => true }
])
```

Async popups can be shown while work happens, then updated or closed.

```ruby
popup = Reloaded::PopupWindow.async("Fetching data...")
begin
  # do work
  popup.update("Installing files...") if popup
ensure
  popup.close if popup
end
```

Theme examples:

```ruby
Reloaded::PopupWindow.message("Saved.", :theme => :success)
Reloaded::PopupWindow.message("Check this before continuing.", :theme => :warning)
Reloaded::PopupWindow.message("Download failed.", :theme => :error)
```

Supported themes are `:hr`, `:success`, `:warning`, and `:error`.

## Text Input API

Use `Reloaded::TextInput` when a mod needs player/admin text entry without
copying a custom input loop.

```ruby
name = Reloaded::TextInput.open("Name", :initial => "New Entry")
```

Short aliases are available for common input types:

```ruby
name = Reloaded.text_input("Name", :initial => "New Entry")
notes = Reloaded.multiline_input("Description", :initial => "")
code = Reloaded.code_input("Access Code", :max_length => 32)
url = Reloaded.url_input("Download URL", :initial => "")
```

Text inputs use the HR popup style, wrap text inside the input field, and scroll
vertically when the content is longer than the visible area. Mouse wheel and
right-stick scrolling are supported where the current input backend exposes
them.

Controls:

- `Enter` confirms.
- `Esc` cancels.
- `Shift+Enter` inserts a new line in multiline mode.
- `Ctrl+A` selects all.
- `Ctrl+C` copies.
- `Ctrl+V` pastes.
- `Ctrl+X` cuts.

Validation failures should return a message from the validator. The field stays
open and shows the message as a warning toast.

```ruby
url = Reloaded.text_input(
  "Download URL",
  :initial => "",
  :size => :large,
  :validator => proc { |value|
    value =~ /\Ahttps?:\/\//i || "Enter a valid URL."
  }
)
```

## List State API

Use `Reloaded::ListState` inside a custom scene when the scene owns its own
layout but needs standard Reloaded list behavior. It does not draw anything or
run scene actions.

```ruby
state = Reloaded::ListState.new(
  :rows => rows,
  :visible_rows => 10,
  :row_id => proc { |row, _index| row[:id] },
  :disabled => proc { |row, _index| row[:locked] },
  :disabled_reason => proc { |row, _index| row[:locked_reason] },
  :horizontal => :jump,
  :remember => true,
  :memory_key => [:my_mod, :reward_list]
)

event = state.update_input(
  :mouse_index => proc { |mouse_x, mouse_y| row_at(mouse_x, mouse_y, state.scroll) }
)
case event.type
when :moved   then redraw_list
when :activate then use_row(event.row)
when :disabled then Reloaded.toast_warning(event.reason)
when :back    then close_scene
end
```

The state owns one-row Up/Down movement, three-row Left/Right jumps, selection,
scrolling, stable row IDs, headers, disabled rows, active-only mouse input, and
session-only cursor memory. Use `:horizontal => :external` when Left/Right
belongs to the scene, such as changing Bag or Mart pockets. Use
`:horizontal => :disabled` when the scene handles those inputs before the list.

Call `replace_rows(new_rows, :preserve => :id)` after filtering or refreshing.
Call `dialog_closed!`, or wrap a modal call with `with_dialog`, so the input
that closes a popup cannot activate the background list. Disabled rows remain
focusable by default and produce a `:disabled` event; set
`:focus_disabled => false` to skip them entirely.

`Reloaded::ListState` complements `Reloaded::ListPicker`: use ListPicker for a
complete shared selector and ListState for a scene-specific layout.

## List Picker API

Use `Reloaded::ListPicker` for shared HR-style list selection instead of
building a scene-specific command window.

```ruby
item = Reloaded::ListPicker.open(
  "Choose an Item",
  rows,
  :layout => :popup,
  :search => true,
  :wrap => true,
  :start_value => :POTION
)
```

`Reloaded.list_picker` is the short alias. `Reloaded::ListPicker.popup` and
`Reloaded::ListPicker.fullscreen` select a layout directly. A single-select
picker returns the selected row value, or `nil` when Back is chosen or pressed.

Rows can be strings, `[label, value, status, detail]` arrays, or hashes:

```ruby
rows = [
  { :label => "Medicine", :header => true },
  {
    :label => "Potion",
    :value => :POTION,
    :status => "x12",
    :detail => "Restores HP.",
    :search_text => "medicine healing potion"
  },
  {
    :label => "Max Potion",
    :value => :MAXPOTION,
    :disabled => true,
    :disabled_reason => "You do not own this item."
  }
]
```

Supported behavior includes:

- Non-selectable section headers and disabled rows.
- A Back row plus Back-input cancellation without background input bleed.
- Optional `:start_on_back => true` for selectors that should open on Back.
- One-row Up/Down movement and three-row Left/Right jumps.
- Optional top/bottom wrapping.
- Click-only search with Clear, stable cursor restoration, and matched-header
  filtering.
- Mouse hover, click selection, wheel scrolling, and a proportional scrollbar.
- Shared `Controls (Y)` footer access through `Reloaded::HintText`; button
  mappings are shown in the Controls toast instead of being laid out in the
  footer.
- Fixed-height wrapped rows or ellipsis for long labels.
- Optional right-aligned status text, row colors, details, footer status, and
  final selection validation.
- Stable selection during filtering and live provider refreshes.

Full-screen pickers can show a right-side details panel. Popup pickers place the
optional details panel below the list.

```ruby
choice = Reloaded::ListPicker.fullscreen(
  "Choose a Reward",
  rows,
  :details => true,
  :footer_status => "Rare rewards only",
  :on_highlight => proc { |row| reward_description(row[:value]) }
)
```

Multi-select mode adds a Done row and returns an array. Back still returns
`nil`.

```ruby
selected = Reloaded::ListPicker.open(
  "Affected Entries",
  rows,
  :multi_select => true,
  :start_values => [:POTION, :ANTIDOTE],
  :done_label => "Apply"
)
```

For a live list, pass a proc and enable refresh. Providers should be fast and
side-effect free because they may be called more than once.

```ruby
Reloaded::ListPicker.open(
  "Downloads",
  proc { build_download_rows },
  :live_refresh => true,
  :refresh_interval => 30
)
```

Icons, badges, reordering, and nested/tree rows are intentionally outside the
current List Picker contract.

Reloaded mouse-aware UI uses `Reloaded::MouseInput.active_position`. It only
returns a position on frames where the mouse moved, clicked, or scrolled, and
keyboard/controller commands take priority. A stationary cursor therefore
cannot override the current list selection.

## Game Data Picker API

Use `Reloaded::GameDataPicker` when an editor or ModDev tool needs a canonical
game-data ID. It builds searchable ListPicker rows from the live registries and
returns the selected ID rather than display text.

```ruby
item_id = Reloaded::GameDataPicker.item(
  "Catalog Item",
  :start_value => :SUPERPOTION
)

species_ids = Reloaded::GameDataPicker.species(
  "Gift Pokemon",
  :multi_select => true,
  :start_values => [:TREECKO, :TORCHIC, :MUDKIP]
)
```

Available selectors are `item`, `species`/`pokemon`, `move`, `ability`, `type`,
`map`, and `trainer_class`/`trainer_type`. The generic entry point is
`Reloaded::GameDataPicker.pick(kind, title, options)`, with the short alias
`Reloaded.pick_game_data`.

Rows include the localized name, canonical internal ID, numeric ID when one is
available, search aliases, and useful record details. Maps use the live
`MapInfos.rxdata` data because they are not stored in the same registry shape.
Back returns `nil`; multi-select returns an array of canonical IDs.

Options include `:start_value`, `:start_values`, `:filter`, `:include`,
`:exclude`, `:disabled`, `:disabled_reason`, `:sort`, `:multi_select`,
`:layout`, `:search`, `:details`, `:include_placeholders`, and `:return`.
Set `:return => :data` to receive the selected GameData record instead of its
ID. Filter and row-state procs receive the record and canonical ID.

```ruby
move_id = Reloaded::GameDataPicker.move(
  "Damaging Move",
  :filter => proc { |move| move.base_damage.to_i > 0 },
  :exclude => [:STRUGGLE]
)
```

The picker only selects data. It does not grant rewards, mutate registries, or
apply Data Patches.

## Number Picker API

Use `Reloaded::NumberPicker` for quantity and integer selection. Cancel returns
`nil`, allowing zero to remain a valid editor value.

```ruby
quantity = Reloaded::NumberPicker.quantity(
  "Potion",
  :min => 1,
  :max => 99,
  :initial => 1,
  :value_prefix => "x",
  :allow_max_shortcut => true
)
```

`Reloaded::NumberPicker.open` uses the Kanto Reloaded digit picker for generic
editor values:

- `Left/Right` selects a digit.
- `Up/Down` changes only the selected digit.
- Inactive digits are dim and the selected digit pulses white.
- Every digit in the configured range remains visible.
- The first Confirm moves selection to `OK`; Confirm on `OK` submits the value.
- Left or Right from `OK` returns to the digit row.

The mouse wheel changes the selected digit. Clicking a digit selects it,
clicking `OK` submits, and right-click cancels. Generic editor values are
nonnegative, matching the Kanto Reloaded picker.

`Reloaded::NumberPicker.quantity` retains the original Reloaded quantity popup
used by the Mart and Bag. In that popup, `Up/Down` uses `:step`,
`Left/Right` uses `:large_step`, `:wrap` controls endpoint wrapping, and
`:allow_max_shortcut => true` lets Action jump to the maximum. Unit-price and
total-price previews remain available there.

Generic `open` supports `:min`, `:max`, `:initial`, `:digits`, `:label`,
`:value_prefix`, `:width`, `:theme`, `:show_dim`, `:z`, and `:on_change`.
Quantity pickers additionally support `:value_suffix`, `:preview`,
`:preview_color`, `:validator`, and the step options above.

`Reloaded::NumberPicker.confirm` uses the same title, item, quantity,
unit-price, and total layout with `Yes/No` rows. The quantity picker keeps its
cursor on `OK`; the confirmation variant keeps it only on `Yes/No`.

`Reloaded.number_picker` and `Reloaded.quantity_picker` are short aliases.

## Form API

Use `Reloaded::Form` for full-screen editors that need several typed fields,
field descriptions, validation, dirty-state tracking, and safe save/discard
behavior. Form edits an isolated draft and returns the saved hash. Back returns
`nil`; the source hash is never modified directly.

```ruby
result = Reloaded::Form.open(
  "Reward Editor",
  [
    {
      :id => "name",
      :label => "Name",
      :type => :text,
      :required => true,
      :description => "Display name for this reward."
    },
    {
      :id => "item",
      :label => "Item",
      :type => :game_data,
      :game_data => :item,
      :required => true
    },
    {
      :id => "quantity",
      :label => "Quantity",
      :type => :number,
      :min => 1,
      :max => 9999,
      :step => 1,
      :large_step => 10
    },
    {
      :id => "enabled",
      :label => "Enabled",
      :type => :toggle,
      :default => true
    }
  ],
  { "name" => "Potion Pack", "item" => "POTION", "quantity" => 5 }
)
```

Supported field types are `:text`, `:multiline`, `:number`, `:toggle`,
`:enum`, `:list`, `:game_data`, `:custom`, `:readonly`, and `:header`.
Common properties include `:default`, `:required`, `:description`, `:min`,
`:max`, `:step`, `:large_step`, `:choices`, `:visible`, `:enabled`,
`:disabled_reason`, `:empty_label`, `:normalize`, `:validate`, and
`:on_change`. Use `:empty_label` for a meaningful blank-state label such as
`"Unlimited"` while retaining `nil` in the returned data.

Conditions and callbacks receive the current draft. Field validation may return
`true`, an error string, or `{ :level => :warning, :message => "..." }`.
Form-level `:validate`, `:on_change`, and `:on_save` callbacks are supplied in
the options hash. `:on_save` runs on the main thread and may return `false` or
an error string to keep the form open.

Enums use `Reloaded::ListPicker`, GameData fields use
`Reloaded::GameDataPicker`, and numbers use `Reloaded::NumberPicker`.
Up/Down moves one field and Left/Right moves three. Confirm edits, Action saves,
Back handles dirty confirmation, and Y opens the Controls Toast. The short
alias is `Reloaded.form(title, fields, values, options)`.

## File Actions API

Use `Reloaded::FileActions` instead of launching files, folders, or clipboard
operations directly. Relative paths resolve from the game folder. Absolute
paths are allowed only when they resolve inside the game folder; outside paths,
including paths reached through a symlink or junction, are refused.

```ruby
Reloaded::FileActions.open_folder("Mods")
Reloaded::FileActions.open_file("Reloaded/Changelog.md")
Reloaded::FileActions.open("Reloaded/Logging/Log.txt")

Reloaded::FileActions.copy("Text copied by my mod")
text = Reloaded::FileActions.read_clipboard
```

Online text-file and log exports use the existing diagnostics uploader and
copy the returned URL to the clipboard:

```ruby
url = Reloaded::FileActions.export_log("LatestBugReport.txt")
url = Reloaded::FileActions.export_file("Reloaded/Logging/Mods.txt")
```

`export_file` is for non-empty text files up to 5 MB, not binary archives or
images.
Desktop file, clipboard, and export actions should be hidden unless the
corresponding `Reloaded::Platform.supports?` capability is available.

For safe display and logging, never show a resolved absolute path. Use:

```ruby
path = Reloaded::FileActions.resolve("Mods/My Mod/mod.json", :type => :file)
Reloaded::FileActions.inside_game?(path, :must_exist => true)
Reloaded::FileActions.display_path(path)
Reloaded::FileActions.sanitize(error.message)
```

`display_path` returns a game-relative path for in-game files and only the
basename for refused outside paths. File action errors contain sanitized paths.

## Remote Data API

Use `Reloaded::RemoteData` for small remote text or JSON sources that need a
validated last-known-good cache and an optional shipped local fallback. It is
used by the Mod Browser, Spritepacks, Reloaded Mart catalog, Hoenn Reloaded
version checks, remote changelogs, and published profile text.

Register a named source owned by your mod, then fetch it:

```ruby
Reloaded::RemoteData.register(
  :example_catalog,
  :owner => :example_mod,
  :format => :json,
  :url => "https://example.com/catalog.json",
  :local_path => "Mods/Example Mod/catalog.json",
  :timeout => 8,
  :retries => 1,
  :ttl => 3600,
  :validator => proc { |value| value.is_a?(Hash) && value["entries"].is_a?(Array) }
)

result = Reloaded::RemoteData.fetch(:example_catalog)
entries = result.value["entries"] if result.ok?
```

The retrieval order is remote, validated cache, then local fallback. A failed,
oversized, malformed, or validator-rejected response never replaces the good
cache. `load` reads only cache/local data and never starts a network request:

```ruby
result = Reloaded::RemoteData.load(:example_catalog)
```

`Result` exposes `ok?`, `value`, `body`, `source`, `status`, `fetched_at`,
`loaded_at`, `cache_age`, `stale?`, `fallback?`, `remote_confirmed?`,
`http_status`, `attempts`, `error_code`, `error_message`, `source_id`, and
`url_label`. A cache returned after a failed remote attempt has
`fallback? == true`. A `304 Not Modified` cache result has
`remote_confirmed? == true`.

For one-off text or JSON, use:

```ruby
text_result = Reloaded::RemoteData.fetch_text("https://example.com/notes.txt")
json_result = Reloaded::RemoteData.fetch_json("https://example.com/data.json")
```

RemoteData accepts HTTPS only, refuses cache/local paths outside the game
folder, follows bounded HTTPS redirects, applies response-size limits, and
sanitizes logged errors. Windows and Proton support remote retrieval. JoiPlay
uses existing cache/local fallbacks without attempting a network request.

RemoteData is synchronous. Use `Reloaded::Task` when a fetch must not block the
rendering loop. Do not use RemoteData for mod archives, spritepack archives,
images, or other large binary files; use `Reloaded::Download` for those.

## Download API

Use `Reloaded::Download` for large HTTPS files. It streams into a
same-directory `.part` file, applies configured size and SHA-256 checks, and
only then atomically promotes the completed file to its destination. Files of
at least 24 MiB use up to three simultaneous byte-range connections when the
server supports them. Unsupported range requests automatically fall back to
the existing single streaming connection. The three-connection limit is shared
across the whole process, not granted independently to every active task.

```ruby
result = Reloaded::Download.fetch(
  download_url,
  archive_path,
  :task => task,
  :label => "Example Mod",
  :min_bytes => 128,
  :expected_bytes => 12_345_678,
  :sha256 => "64 lowercase or uppercase hexadecimal characters",
  :progress_range => [0.0, 0.6]
)

task.fail!(result.error_message, result.error_code) unless result.success?
```

`expected_bytes` and `sha256` are optional. When supplied, both must match
before the destination is replaced. `max_bytes`, `open_timeout`,
`read_timeout`, `redirect_limit`, `retries`, custom `headers`, and a `label`
may also be supplied. `connections` can lower the multipart connection count
from its default and maximum of 3. Redirects remain HTTPS and sensitive
headers are removed when the origin changes.

`Result` exposes `success?`/`ok?`, `status`, `error_code`, `error_message`,
sanitized `url`, `final_url`, and `destination`, plus `bytes`,
`expected_bytes`, `sha256`, `duration`, `attempts`, `transport`, `http_status`,
and safe response `headers`.

For a standalone background download, use:

```ruby
handle = Reloaded::Download.start(
  download_url,
  archive_path,
  :label => "Example Mod",
  :task_options => { :owner => :example_mod, :duplicate => :reuse }
)
Reloaded::ProgressWindow.show(handle, :title => "Downloading", :cancellable => true)
```

Downloads are restricted to the game folder and Reloaded's system temporary
folder. Failed, cancelled, oversized, incomplete, or invalid downloads remove
their `.part` files and preserve any valid existing destination. Windows and
Proton use streaming HTTPS with a platform fallback. JoiPlay does not expose
remote downloads.

PowerShell fallback workers set their terminal title from the sanitized
download label. Spritepack workers therefore identify the Full or monthly pack
and numbered part currently being downloaded if the host displays their window.

Pass `:resume => true` only for large immutable downloads with an expected size
and preferably SHA-256. Interrupted network/transport failures preserve the
`.part` file and its `.part.meta.json` range state for a byte-range retry.
Multipart workers write directly into assigned offsets in one preallocated
file. ETag/Last-Modified changes, invalid range boundaries, and validation
failures discard the partial. Full and monthly Spritepack archives enable this
automatically.

## Archive API

Use `Reloaded::Archive` to inspect or extract ZIP, RAR, and 7Z files. It lists
and validates every archive entry before extraction, rejects absolute and
parent-directory paths, links, encrypted entries, duplicate paths, Windows
device names, excessive entry sizes/counts, and unsafe compression ratios.
Generic 7-Zip listings are written to a temporary output file and parsed
incrementally instead of being held as one large in-memory string. Verified
Full Spritepack installs use their own manifest-backed staging path because
some embedded game runtimes do not reliably expose 7-Zip listing output.

```ruby
result = Reloaded::Archive.extract(
  archive_path,
  destination,
  :overwrite => :fail,
  :task => task,
  :progress_range => [0.25, 0.9],
  :verify => true
)

task.fail!(result.error_message, result.error_code) unless result.success?
```

`overwrite` accepts `:fail`, `:skip`, or `:overwrite`. Prefer `:fail` for a new
staging folder. Use `:overwrite` only for an intentional update flow such as a
Spritepack replacing existing sprite files. `verify` checks that every listed
file exists afterward and should be reserved for smaller archives where the
additional file-system pass is worthwhile.

`inspect_archive(path)` performs the same safety preflight without extracting.
Both methods return `Reloaded::Archive::Result`, exposing `success?`/`ok?`,
`status`, `error_code`, `error_message`, `entry_count`, `expanded_bytes`,
`packed_bytes`, sanitized `archive`/`destination` labels, `duration`, and
`warnings`. Pass `:include_entries => true` only when the caller needs the
validated entry rows.

Archive sources and destinations are limited to the game folder and Reloaded's
system temporary folder. Errors and logs never expose full machine paths.
Extraction uses the bundled 7-Zip adapter on Windows and Proton. JoiPlay does
not expose archive extraction; Android users install archive contents manually.
Run extraction inside `Reloaded::Task` and display `Reloaded::ProgressWindow`
for user-started operations. Worker code must not modify game UI or game state.

## Spritepack API

`Reloaded::SpritePacks` reads AFI-compatible SPAK v2 per-head packs without
extracting a whole head. Normal loose files and active mod assets always keep
priority.

```ruby
path = Reloaded::SpritePacks.materialize_entry(:CUSTOM, 25, 133, "a")
bitmap = AnimatedBitmap.new(path) if path

entries = Reloaded::SpritePacks.entries(:CUSTOM, 25)
packed = Reloaded::SpritePacks.entry?(:CUSTOM, 25, 133, "a")
alts = Reloaded::SpritePacks.available_alt_letters(:CUSTOM, 25, 133)
health = Reloaded::SpritePacks.pack_health
verified = Reloaded::SpritePacks.verify_component(:expanded)
update = Reloaded::SpritePacks.verify_update("2026-08")
layers = Reloaded::SpritePacks.installed_updates
```

Supported entry types are `:CUSTOM`, `:AUTOGEN`, and `:BASE`. `materialize`
also accepts a `PIFSprite`. Materialized paths point into the disposable
Reloaded cache, are returned relative to the game root for engine bitmap
compatibility, and must not be saved as permanent mod data. Mods should still
ship ordinary `Graphics` overrides unless they are intentionally publishing a
large per-head Spritepack component. `available_alt_letters` returns only the
variants present in installed pack layers for one head/body pair.

Packed entries pass through the same extractor scaling as loose sprites. When
the engine generates a shiny image from a packed entry, Reloaded rejects a
fully transparent generated cache and keeps a visible runtime recolor instead.

Monthly update layers load newest-first above Full Base and Expanded. Base has
higher priority than Expanded within each layer. No packed layer overrides a
loose file or active mod asset. Verification is explicit because hashing a
multi-gigabyte install during every boot would be inappropriate.

## Sprite Import API

Players place manually supplied PNGs in
`Graphics/CustomBattlers/Sprite Import`. `Reloaded::SpriteImport.import`
validates and sorts them into the loose Base or indexed custom-sprite folders.
Large batches display `Reloaded::ProgressWindow` where background tasks are
supported. The returned summary contains `:imported`, `:conflicts`, `:invalid`,
and `:failed`.

```ruby
summary = Reloaded::SpriteImport.import
record = Reloaded::SpriteImport.classify_filename("25.133a.png")
```

Mods should normally install their own `Graphics` overrides rather than place
files in the player import inbox.

## Background Task API

Use `Reloaded::Task` for network, archive, export, publisher-launch, or other
blocking I/O. A worker block may perform I/O and computation only. It must not
change scenes, draw UI, write save/profile state, use the clipboard, or mutate
live game registries. Apply those changes from callbacks, which Task delivers
on the game thread after popup and held-input state is clear.

```ruby
handle = Reloaded::Task.start(
  :example_catalog_refresh,
  :owner => :example_mod,
  :duplicate => :reuse,
  :timeout => 30,
  :on_success => proc do |outcome|
    ExampleCatalog.replace(outcome.value)
    Reloaded.toast_success("Catalog updated.")
  end,
  :on_failure => proc do |outcome|
    Reloaded.toast_error("Catalog failed: #{outcome.error_message}")
  end
) do |task|
  task.report(0.1, "Fetching")
  result = Reloaded::RemoteData.fetch(:example_catalog, :force => true)
  task.fail!(result.error_message, result.error_code) unless result.ok?
  task.checkpoint!
  task.report(1.0, "Ready")
  result.value
end
```

Duplicate policies are `:reuse`, `:reject`, and `:queue`. Cancellation is
cooperative: long workers should call `task.checkpoint!` between stages.
`handle.state`, `handle.running?`, `handle.complete?`, `handle.cancel`,
`handle.progress`, `handle.stage`, and `handle.outcome` expose task state.
Outcomes provide `success?`, `failed?`, `cancelled?`, the returned `value`,
error details, timestamps, duration, progress, and stage.

For optional built-in completion notices, pass `:notify` with `:success`,
`:failure`, and optional `:mode => :auto`. Callbacks still own all game-state
changes. Windows and Proton support background tasks; JoiPlay keeps these
desktop/network actions hidden.

## Progress Window API

Use `Reloaded::ProgressWindow` for explicit user-started work that should keep
the current scene visible while preventing background input. It uses the HR
popup style, supports determinate or indeterminate progress, and can offer
cooperative cancellation.

```ruby
handle = Reloaded::Task.start(
  :example_export,
  :owner => :example_mod,
  :on_success => proc { |_outcome| Reloaded.toast_success("Export complete.") },
  :on_failure => proc { |outcome| Reloaded.toast_error(outcome.error_message) },
  :on_cancel => proc { |_outcome| Reloaded.toast_warning("Export cancelled.") }
) do |task|
  task.report_ratio(1, 3, "Collecting files")
  task.checkpoint!
  task.indeterminate!("Writing archive")
  path = ExampleExporter.write_archive
  task.checkpoint!
  task.report(1.0, "Complete")
  path
end

outcome = Reloaded::ProgressWindow.show(
  handle,
  :title => "Exporting Example",
  :cancellable => true,
  :cancel_prompt => "Cancel this export?"
)
```

`:mode` accepts `:auto`, `:determinate`, or `:indeterminate`. In `:auto`, a
reported numeric value draws a percentage and a missing value draws the
animated indeterminate bar. Other options include `:stage`, `:width`,
`:minimum_visible_time`, `:show_dim`, `:confirm_cancel`, `:cancel_text`, and
`:cancelling_text`. `Reloaded::ProgressWindow.run(key, options) { |task| ... }`
is a convenience wrapper that starts and displays one task.

Cancellation never kills a worker thread. Workers must call `task.checkpoint!`
between meaningful stages; an external downloader, archive tool, or publisher
may take time to return before cancellation can finish. The window closes only
after the task is ready and held input is clear, then Task delivers callbacks
and Toasts on the game thread. Start the task and show its window from the
owning scene. Do not open a ProgressWindow from inside that task's callback.

Use ProgressWindow for explicit downloads, extraction, imports, exports,
backups, and publishing. Keep passive Mod Browser/Mart refreshes on normal
`Reloaded::Task` plus Toast notifications so opening those scenes never waits
on a modal window.

## Rewards API

Use `Reloaded::Rewards` to grant items, currencies, Pokemon, unlocks, and
registered system/mod rewards through one validated path. Reloaded Mart,
custom Mystery Gifts, event scripts, and mods use the same registry.

```ruby
result = Reloaded.grant_reward(
  { :type => :item, :id => :POTION, :quantity => 3 },
  :source => :my_event
)

result = Reloaded.grant_rewards([
  { :type => :money, :amount => 5000 },
  { :type => :pokevial_charge, :quantity => 1 }
], :source => :my_mod)
```

`grant_reward` returns a `Reloaded::Rewards::Result`. Check `ok?`, `code`,
`message`, `reward`, `receipt`, and `details`. `grant_rewards` preflights the
whole batch, grants in registered priority order, and rolls already-applied
rewards back in reverse order if a later grant fails.

Item rewards are delivered to the Bag when the full quantity fits. If it does
not, the full reward is sent to PC Item Storage instead. A batch fails
preflight before changing player state when neither destination can hold an
item reward; one reward is never split between both destinations.

Built-in and Reloaded module reward types are:

- `:item` - requires `:id`/`:item_id` and optional `:quantity`.
- `:money` - requires a positive `:amount`.
- `:currency` - requires `:currency` and a positive `:amount`. Built-ins are
  `:money`, `:coins`, `:battle_points`, `:quest_points`, and
  `:cosmetics_money` (Glimmer Coins).
- `:pokemon` - requires `:species`; supports fallback species, level, quantity,
  party/storage delivery, eggs, forms, shiny state, gender, nature, ability,
  held item, moves, exact or ranged IVs, EVs, happiness, Poke Ball, nickname,
  custom typings, OT/origin data, distribution identity/version, duplicate
  policy, evolution policy, and an optional trade lock.
- `:tm_vault` - requires `:move` and permanently adds it to the TM Vault.
- `:outfit` - requires `:category` (`:clothes`, `:hat`, or `:hairstyle`) and
  `:outfit_id`.
- `:feature_unlock` - requires the ID of an explicitly registered Reloaded
  feature that is not already enabled.
- `:group` - requires `:grants`, an array of rewards that must all validate and
  grant atomically. Group rollback runs in reverse order when a child fails.
- `:choice` - requires `:options`, an array of reward payloads. The player
  selects one currently valid option.
- `:random` - requires `:rewards`, an array of reward payloads. Entries can
  use relative `:weight` values or percentages through `:percentage` or
  `:chance`. Percentage entries must all use percentages totaling exactly 100.
  Only currently valid entries can be rolled.
- `:pokevial_charge` - grants one or more charges.
- `:pokevial_refill` - restores all missing charges.
- `:pokevial_max_uses` - raises the unlocked maximum to `:max_uses`.
- `:iv_boundary_boost` - grants a temporary IV Boundary rule.
- `:iv_boundary_force_next` - queues a rule for matching new Pokemon.

Pokemon rewards default to `:delivery => :either`, which fills the party first
and then the first available Pokemon Storage Box. Use `:party` or `:storage` to
require one destination.
Setting `:shiny => true` marks both shiny components so unfused and fused
reward Pokemon use the engine's generated shiny coloration with packed sprites.
Custom typings accept one or two type IDs and are saved on that Pokemon. Battle
logic and Reloaded UI both read the stored types.

```ruby
Reloaded.grant_reward({
  :type => :pokemon,
  :species => :RALTS,
  :level => 12,
  :types => [:PSYCHIC, :FAIRY],
  :nature => :MODEST,
  :moves => [:CONFUSION, :DISARMINGVOICE],
  :distribution_id => "my_mod:ralts:1",
  :distribution_version => 1,
  :duplicate_policy => :reject,
  :untradeable => true,
  :trade_lock_reason => "This event Pokemon cannot be traded.",
  :delivery => :either
}, :source => :my_event)
```

Use `:egg => true` for an egg. Explicit `:ivs` and `:evs` are hashes keyed by
main stat IDs and override the generated values. If they are omitted, normal
generation applies, including the IV Boundaries system. Pokemon granted with
`:source => :reloaded_mart` are the exception: Reloaded Mart distributions
always bypass player IV Boundaries and use only their configured IV payload or
normal unconstrained generation.

`duplicate_policy` accepts `:allow`, `:reject`, or `:replace` and requires a
stable `distribution_id` unless it is `:allow`. `evolution_policy` accepts
`:allow` or `:block`. An untradeable distribution also requires a stable ID;
the restriction follows fusions and is enforced by normal trades, NPC trades,
and Wonder Trade.

Choice and weighted-random rewards can contain any registered reward type,
including other groups up to eight levels deep:

```ruby
{
  :type => :choice,
  :prompt => "Choose your prize",
  :options => [
    { :type => :item, :id => :RARECANDY, :quantity => 3 },
    { :type => :currency, :currency => :battle_points, :amount => 20 }
  ]
}

{
  :type => :group,
  :name => "Supply Drop",
  :grants => [
    { :type => :item, :id => :POTION, :quantity => 5 },
    { :type => :currency, :currency => :battle_points, :amount => 10 }
  ]
}

{
  :type => :random,
  :rewards => [
    { :type => :item, :id => :NUGGET, :chance => 80 },
    { :type => :pokemon, :species => :EEVEE, :level => 10, :chance => 20 }
  ]
}
```

Percentage values are converted to the same internal weighted-roll path. Do
not mix percentage fields and `:weight` within one random reward. If unavailable
entries are filtered out, their percentages are removed and the remaining
values are treated proportionally.

Mods can add a currency without creating another reward handler:

```ruby
Reloaded::Rewards.register_currency(
  :my_tokens,
  :owner => :my_mod,
  :name => "Tokens",
  :getter => proc { MyMod.tokens },
  :setter => proc { |value| MyMod.tokens = value },
  :max => 999
)
```

Register a mod reward type with a globally unique snake-case ID. The active
mod ID is used as owner automatically while the Mod Manager loads a mod, but an
explicit owner is recommended in reusable code:

```ruby
Reloaded::Rewards.register(
  :my_mod_tokens,
  :owner => :my_mod,
  :aliases => [:legacy_my_tokens],
  :validate => proc { |reward, context|
    reward[:quantity].to_i > 0
  },
  :grant => proc { |reward, context|
    before = MyMod.tokens
    MyMod.tokens += reward[:quantity].to_i
    Reloaded::Rewards.success(
      :reward => reward,
      :details => { :receipt_data => { :before => before } }
    )
  },
  :rollback => proc { |receipt, context|
    MyMod.tokens = receipt.data[:before]
    true
  },
  :describe => proc { |reward|
    "my_mod_tokens quantity=#{reward[:quantity]}"
  }
)
```

Handlers may also provide `:normalize`, `:expand`, `:finalize`, `:label`, and
`:message`. `normalize` converts compatibility payloads, `expand` controls
bundle quantity behavior, `finalize` performs non-reversible side effects only
after an atomic batch succeeds, `label` supplies player-facing Mart text, and
`message` supplies Mystery Gift presentation text. Reloaded Mart also defers
finalizers until the complete purchase transaction succeeds.

Duplicate type IDs and aliases are rejected unless framework code explicitly
uses `override: true`. Registrations are rebuilt each boot and are not saved.
Use `registered?`, `type`, and `types` for read-only inspection.

Normal reward handlers should not open UI directly. The caller owns Mart,
Mystery Gift, event-dialogue, or silent presentation. `:choice` is the one
built-in exception because choosing its leaf reward is part of granting it.
Use `context[:source]` for source-specific behavior and logging.

## Toast API

Use `Reloaded::Toast` for short HR-style status messages. Toasts default to an
`OK` row with the HR cursor so confirm input is consumed by the toast. Choice
and row toasts support mouse hover, click selection, and wheel scrolling.
Custom OK toasts support clicking OK, and automatic toasts can be dismissed by
clicking their panel.

```ruby
Reloaded::Toast.show("Saved.")
Reloaded::Toast.ok("Browser updated.")
Reloaded::Toast.success("Downloaded.")
Reloaded::Toast.warning("No updates found.")
Reloaded::Toast.error("Download failed.")
```

Auto mode is available for non-blocking timed status messages. Auto toasts need
the owning scene to call `Reloaded::Toast.update` during its update loop.

```ruby
Reloaded::Toast.show("Saved.", :mode => :auto, :duration => 90)
Reloaded::Toast.update
```

Custom toast bodies can render directly into the HR toast panel. The block gets
the popup bitmap and a usable body rectangle.

```ruby
Reloaded::Toast.custom("Controls", :body_height => 96) do |bitmap, rect|
  pbDrawTextPositions(bitmap, [["Custom body", rect[:x], rect[:y], 0,
    Color.new(248, 248, 248), Color.new(0, 0, 0, 0)]])
end
```

## Hint Text API

Use `Reloaded::HintText` for Reloaded-owned footer/help rows instead of
hand-formatting each scene.

```ruby
entries = [
  Reloaded::HintText.confirm("Use"),
  Reloaded::HintText.back,
  Reloaded::HintText.action("Favorite"),
  Reloaded::HintText.special("Refresh"),
  Reloaded::HintText.other("Sort", :sort)
]

hint = Reloaded::HintText.format(entries)
```

Formatted hints use `Action (input)` labels, separate entries with ` | `, and
sort entries in this order: Confirm, Back, Action, Special, Others. Input labels
come from the game's global `keybindings.mkxp1` file. Controller bindings are
shown while a controller is connected; otherwise keyboard bindings are shown.
`Hint Texts` defaults to `On` and can hide Reloaded-owned hint rows.

To draw directly:

```ruby
Reloaded::HintText.draw(bitmap, entries, 8, 360, 496)
```

For scene footers, prefer the compact footer helper. It shows a clickable
`Controls (Y)` button at the right of the footer and lets active scene modes
appear as short status text. Do not add it to directional footer focus.
`HintText.triggered?` opens the Controls popup from `Input::Y`.

```ruby
statuses = [Reloaded::HintText.status("Quick-Buy Mode", Color.new(80, 240, 120))]
Reloaded::HintText.draw_footer(
  bitmap, entries, 8, 360, 496,
  :statuses => statuses
)
Reloaded::HintText.open_popup("Mart Hints", entries, :statuses => statuses) if Reloaded::HintText.triggered?
```

Short aliases are also available:

```ruby
Reloaded.hint_text(entries)
Reloaded.draw_hint_text(bitmap, entries, 8, 360, 496)
Reloaded.draw_hint_footer(bitmap, entries, 8, 360, 496)
Reloaded.open_hint_popup("Hints", entries)
```

## Input Bindings API

`Reloaded::InputBindings` is a read-only presentation helper. It reads the
game's active global `keybindings.mkxp1` and never changes or intercepts input.

```ruby
confirm_label = Reloaded::InputBindings.label(:confirm)
sort_label = Reloaded::InputBindings.label(:sort)
```

Supported action IDs are `:confirm`, `:back`, `:action`, `:special`, `:sort`,
`:quick`, `:menu`, `:left`, `:right`, `:page`, and `:pocket`.
Use the normal base `Input.trigger?`, `Input.press?`, and `Input.repeat?`
methods for behavior.

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
Reloaded/Modules/PauseMenu.rb
```

The active pause menu is controlled by the `Pause Menu` option under
`VISUALS & UI -> Reloaded UI`:

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
`PauseMenu.rb`:

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
Reloaded/Modules/OverworldMenu.rb
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
Reloaded/Modules/IVBoundaries.rb
```

Players can set IV boundaries for newly generated player-side Pokemon through
the Reloaded options menu. This applies to new wild Pokemon, gifts, static
encounters, and Eggs. Existing party/box Pokemon are not changed.

The options submenu includes presets, custom Min/Max IV sliders, and a preview
action. If Max IV is below 31, perfect IVs are treated like any other
out-of-range value and rerolled inside the active range.

Hard difficulty forces the player minimum IV boundary to `0`. Players may
still leave IV Boundaries off or lower the maximum for a neutral or more
restrictive challenge, but presets that guarantee beneficial minimum IVs are
unavailable. Explicit authored Pokemon rewards and temporary earned IV rewards
retain their own configured behavior.

Trainer IV boundaries are not player-editable. They are controlled by difficulty
rules and trainer-class config in `IVBoundaries.rb`:

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

Event scripts and mods can grant the same payloads directly:

```ruby
Reloaded.grant_reward(
  { :type => :iv_boundary_boost, :scope => :wild, :floor_bonus => 5, :duration_minutes => 10 },
  :source => :my_event
)
```

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
Reloaded/Modules/PokeVial.rb
```

Mods and Reloaded systems should grant charges, refills, and unlocks through
the shared Rewards API:

```ruby
Reloaded.grant_reward({ :type => :pokevial_charge, :quantity => 2 }, :source => :my_mod)
Reloaded.grant_reward({ :type => :pokevial_refill }, :source => :my_mod)
Reloaded.grant_reward({ :type => :pokevial_max_uses, :max_uses => 4 }, :source => :my_mod)
```

The lower-level PokeVial script methods remain available for direct feature
control:

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
switch/variable progression rules in `PokeVial.rb`.

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

PokeVial use is rejected without consuming a charge when no party Pokemon needs
the selected healing mode. Full Heal checks HP, status, and PP; HP Only checks HP.

PokeCenter refills use the formula
`missing charges x (500 + badges x 100 + party size x 50)`. Hard difficulty
charges 125% of that result, forces Progressive Uses on, and fixes the enabled
cooldown at 10 real minutes. Players can choose `Ask`, `Automatic`, or `Never`
for PokeCenter refills; `Ask` is the default. Refill callbacks receive the
calculated total in `ctx[:cost]`.

When Progressive Uses is enabled, badge progression raises the current maximum.
Each newly unlocked slot is immediately filled, and a delayed success Toast is
shown once the player is safely back in the overworld. Future or otherwise
invalid saved cooldown timestamps are clamped before cooldown time is calculated.

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

Optional progression config lives in `PokeVial.rb`:

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

Optional per-map denial text also lives in `PokeVial.rb`:

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
Reloaded/Modules/TMVault.rb
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

The `TM Vault` button at the top of the `GAMEPLAY` category opens a submenu:

```text
TM Vault: Off / PokeNav
Egg Moves: Off / On
```

`TM Vault` controls PokeNav visibility. Default value: `PokeNav`.

`Egg Moves` controls whether the vault's Relearn Moves mode includes egg
moves. Default value: `On`.

Relearn Moves respects the same Name, Type, Category, Recent, and Level Learned
sorting modes as the main vault. Level Learned uses the selected Pokemon's
learnset, with initial moves first, followed by earlier-to-later level-up moves,
remembered non-level moves, and egg moves. Egg moves are marked with an egg
icon in the Relearn list.

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
TMVault.sort_mode          # => 0 Name, 1 Type, 2 Category, 3 Recent, 4 Level Learned
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
Reloaded/Modules/ReloadedMart/Backend.rb
Reloaded/Modules/ReloadedMart/UI.rb
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

`full: true` marks the one Full Spritepack and keeps it at the top.
`monthly: true` identifies a monthly overlay. `updated_at` uses
`MM-DD-YY HH:MM:SS` and is the preferred newest-first sort value.
`latest: true` marks the newest monthly update for the `Latest` submenu. Other
updates appear under `All Files`, sorted newest-first by `updated_at`, then by
`version` or the number in the name. Each entry needs a `name` and `url`;
optional `extract_to` overrides the default game-root extraction target.

See `Reloaded/Documentation/Manager.md` for the source and index formats.

## Publishing

Publishing uses the matching external fixed-action tool:

```text
ModDev/Tools/Windows/Publish.bat
ModDev/Tools/Windows/Update.bat
ModDev/Tools/Windows/Delete.bat
ModDev/Tools/Proton/Publish.sh
ModDev/Tools/Proton/Update.sh
ModDev/Tools/Proton/Delete.sh
```

In-game, use:

```text
Mod Manager -> Tools -> Mod Tools
```

Publish selects a local Mod or Profile. It creates the first persistent release
for a new ID or adds/replaces a version asset for an existing owned ID. Update
is a separate metadata-only tool: it lists owned online entries and edits their
display name, authors, description, tags, changelog URL, and homepage URL. It
does not read local content, package files, or upload release assets.

The tools do not clone or cache the repository. Publishing another version,
Update, and Delete enforce the `publisher_login` recorded by the first publish,
with a repository-owner override for maintenance.

## Reloaded Bag Autosort

Reloaded Bag custom list order can be exported/imported from:

```text
Mods/Reloaded/ReloadedBagAutosort.txt
```

Format:

```text
[POCKET 1]
POTION
POKEVIAL_CHARGE
POKEVIAL_REFILL
```

Each pocket block uses item IDs, one per line. Missing valid items are appended
automatically when the list is loaded, so mods can ship partial pocket order
snippets without needing to list every item.

## UI Hint Text

Prefer `Reloaded::HintText` for Reloaded UI hint text. When writing a literal
hint, use this format:

```text
Action (input)
```

The normal order is:

```text
Confirm (C) | Back (B) | Action (A) | Special (Z) | Others
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

- `Mod Tools`
- `Create` -> `Mod` or `Profile`
- `Update` -> owned online `Mod` or `Profile` -> edit public listing metadata
- `Publish` -> local `Mod` or `Profile` -> create, add, or replace a version
- `Delete` -> `Mod` or `Profile`
- `Validate` -> `Mod` or `Profile`
- `ModDev` -> `Off` or `On`
- `Backup Mods`
- `Log Files`
- `Admin Tools` when private local admin files are present

The manifest validator scans `Mods/` and enabled `ModDev/` folders and reports
missing or invalid manifest fields. The fixer only applies safe structural
defaults, such as missing `id`, `name`, `version`, `authors`, `dependencies`,
`tags`, `game`, `incompatible`, `changelogurl`, and
`minimum_reloaded_version`. It does not rewrite mod code.

The template generator can create:

- a starter mod folder under `ModDev/` with `mod.json`, `Scripts/`, asset
  folders, `Settings.json`, `Changelog.txt`, and documentation;
- a syntax-checkable `Documentation/APIExamples.rb` with compact Form,
  RemoteData, Task, Download, Archive, and Rewards examples.

The examples file is outside `Scripts/` and is never loaded by the game.
Copy only the integrations a mod needs into its own script files. Generated
documentation also explains API contract classifications. Only documented
`stable` APIs are compatibility commitments. Private methods, transport/test
overrides, scene implementations, adapters, and mutable internal registries
must not be used by released mods.

Profile templates can be empty or seeded from currently installed Mods.

The backend API is:

```ruby
Reloaded::Diagnostics.open_log("Log.txt")
Reloaded::Diagnostics.export_log("Mods.txt")
Reloaded::ModArchives.backup_all_mods
Reloaded::ModDevelopment.validate_manifests
Reloaded::ModDevelopment.create_mod_template("My Mod")
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
  "required_features": [],
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
- `required_features` is an optional array of registered Reloaded feature IDs.
  If a required feature is unknown, unavailable, or disabled when mods are
  validated, the Mod Manager skips the mod and reports the reason.
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
Reloaded/Core/Modding/ModManager.rb
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
