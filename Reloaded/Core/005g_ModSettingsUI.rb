#======================================================
# Reloaded Mod Settings UI
# Author: Stonewall
#======================================================
# Options-scene UI for editing per-mod settings.
#
# Responsibilities:
#   - List installed mods that expose Reloaded settings.
#   - Build Options menu controls from each mod's Settings.json schema.
#   - Save setting changes through the profile-backed ModSettings API.
#   - Report whether changed settings require a game restart.
#
#======================================================

module Reloaded
  module ModSettingsUI
    @restart_required = false

    class << self
      attr_reader :restart_required

      def open(mod_id = nil)
        @restart_required = false
        return false unless ui_available?
        if mod_id
          open_mod(mod_id)
        else
          open_picker
        end
        @restart_required
      rescue Exception => e
        Reloaded::Log.exception("Mod Settings UI failed", e, channel: :mods) if defined?(Reloaded::Log)
        pbMessage(_INTL("The Mod Settings menu could not be opened.")) rescue nil
        @restart_required
      end

      def mark_restart_required
        @restart_required = true
      end

      def ui_available?
        defined?(PokemonOption_Scene) && defined?(PokemonOptionScreen) && defined?(Reloaded::ModSettings)
      end

      def mods_with_settings
        Reloaded::ModSettings.refresh if defined?(Reloaded::ModSettings)
        rows = defined?(Reloaded::ModManager) ? Reloaded::ModManager.mod_rows : []
        rows.select { |row| Reloaded::ModSettings.has_settings?(row[:id]) }
      rescue
        []
      end

      def mod_name(mod_id)
        row = defined?(Reloaded::ModManager) ? Reloaded::ModManager.mod_row(mod_id) : nil
        row ? row[:name].to_s : mod_id.to_s
      rescue
        mod_id.to_s
      end

      def open_picker
        scene = ModSettingsPickerScene.new
        PokemonOptionScreen.new(scene).pbStartScreen
      end

      def open_mod(mod_id)
        scene = ModSettingsScene.new(mod_id)
        PokemonOptionScreen.new(scene).pbStartScreen
      end

      def setting_label(setting)
        text = setting["label"].to_s.strip
        text.empty? ? setting["key"].to_s : text
      end

      def setting_description(setting)
        setting["description"].to_s
      end
    end
  end
end

if defined?(PokemonOption_Scene) && defined?(Reloaded::ModSettingsUI)
  module ModSettingsPromptLayer
    def mod_settings_message(text, *args)
      mod_settings_overlay(_INTL(text, *args), nil)
    end

    def mod_settings_confirm(text, *args)
      mod_settings_overlay(_INTL(text, *args), [_INTL("Yes"), _INTL("No")]) == 0
    end

    def mod_settings_overlay(text, choices = nil)
      viewport = @viewport || Viewport.new(0, 0, Graphics.width, Graphics.height)
      owns_viewport = !@viewport
      dim = Sprite.new(viewport)
      dim.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      dim.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 120))
      dim.z = 100_500

      lines = text.to_s.split("\n")
      line_h = 24
      pad = 16
      box_w = [Graphics.width - 48, 420].min
      box_h = pad * 2 + lines.length * line_h + (choices ? 34 : 26)
      box_x = (Graphics.width - box_w) / 2
      box_y = (Graphics.height - box_h) / 2
      selected = 0

      box = Sprite.new(viewport)
      box.bitmap = Bitmap.new(box_w, box_h)
      box.x = box_x
      box.y = box_y
      box.z = 100_501

      redraw = proc do
        bitmap = box.bitmap
        bitmap.clear
        bitmap.fill_rect(0, 0, box_w, box_h, Color.new(12, 28, 50))
        bitmap.fill_rect(0, 0, box_w, 1, Color.new(80, 150, 220))
        bitmap.fill_rect(0, box_h - 1, box_w, 1, Color.new(80, 150, 220))
        bitmap.fill_rect(0, 0, 1, box_h, Color.new(80, 150, 220))
        bitmap.fill_rect(box_w - 1, 0, 1, box_h, Color.new(80, 150, 220))
        pbSetSystemFont(bitmap) rescue nil
        bitmap.font.size = 18 rescue nil
        y = pad
        lines.each do |line|
          pbDrawShadowText(bitmap, pad, y, box_w - pad * 2, line_h, line, Color.new(248, 248, 248), Color.new(5, 10, 22))
          y += line_h
        end
        y += 4
        if choices
          choices.each_with_index do |choice, index|
            x = box_w / 2 - 72 + index * 84
            fill = index == selected ? Color.new(23, 78, 125) : Color.new(10, 24, 43)
            bitmap.fill_rect(x, y, 72, 22, fill)
            pbDrawShadowText(bitmap, x, y + 1, 72, 18, choice, Color.new(248, 248, 248), Color.new(5, 10, 22), 1)
          end
        else
          pbDrawShadowText(bitmap, 0, y, box_w, 18, "[OK]", Color.new(174, 198, 220), Color.new(5, 10, 22), 1)
        end
      end

      redraw.call
      loop do
        Graphics.update
        Input.update
        if choices
          if Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
            selected = 1 - selected
            redraw.call
          elsif Input.trigger?(Input::USE) || Input.trigger?(Input::C)
            return selected
          elsif Input.trigger?(Input::BACK) || Input.trigger?(Input::B)
            return choices.length - 1
          end
        else
          return 0 if Input.trigger?(Input::USE) || Input.trigger?(Input::C) || Input.trigger?(Input::BACK) || Input.trigger?(Input::B)
        end
      end
    ensure
      box.bitmap.dispose rescue nil
      box.dispose rescue nil
      dim.bitmap.dispose rescue nil
      dim.dispose rescue nil
      viewport.dispose rescue nil if owns_viewport
    end
  end

  class ModSettingsPickerScene < PokemonOption_Scene
    include ModSettingsPromptLayer

    def pbStartScene(inloadscreen = false)
      super
      apply_mod_settings_viewport
    end

    def initUIElements
      super
      @sprites["title"].text = _INTL("Mod Settings") rescue nil
    end

    def apply_mod_settings_viewport
      return unless @viewport && @sprites
      @viewport.z = 100_120
      ["title", "textbox", "option"].each do |key|
        next unless @sprites[key]
        @sprites[key].viewport = @viewport rescue nil
        @sprites[key].z = 100_121 rescue nil
      end
    end

    def pbGetOptions(_inloadscreen = false)
      rows = Reloaded::ModSettingsUI.mods_with_settings
      if rows.empty?
        return [
          TextDisplayOption.new(_INTL("No Mod Settings"), proc { _INTL("None") }, _INTL("No installed mods currently expose settings.")),
          reset_all_button
        ]
      end
      options = rows.map do |row|
        mod_id = row[:id]
        ActionButton.new(
          _INTL(row[:name].to_s),
          proc {
            pbFadeOutIn { Reloaded::ModSettingsUI.open_mod(mod_id) }
          },
          _INTL("Open settings for {1}.", row[:name].to_s)
        )
      end
      options << Spacer.new if defined?(Spacer)
      options << prune_stale_button
      options << reset_all_button
      options
    end

    def prune_stale_button
      ActionButton.new(
        _INTL("Clean Stale Settings"),
        proc {
          if mod_settings_confirm("Clean stale mod setting values from the active profile?")
            removed = Reloaded::ModSettings.prune_stale
            if removed.empty?
              mod_settings_message("No stale mod settings were found.")
            else
              mod_settings_message("Removed {1} stale setting(s).", removed.length)
            end
          end
        },
        _INTL("Remove profile setting values whose mod setting definitions no longer exist.")
      )
    end

    def reset_all_button
      ActionButton.new(
        _INTL("Reset All Mod Settings"),
        proc {
          if confirm_reset_all?
            Reloaded::ModSettings.reset_all
            Reloaded::ModSettingsUI.mark_restart_required
            mod_settings_message("All mod settings were reset.")
          end
        },
        _INTL("Reset every mod setting stored in the active profile.")
      )
    end

    def confirm_reset_all?
      mod_settings_confirm("Reset all mod settings in the active profile?")
    end
  end

  class ModSettingsScene < PokemonOption_Scene
    include ModSettingsPromptLayer

    def initialize(mod_id)
      super()
      @mod_id = mod_id.to_s
      @settings_master = []
      @reset_option = nil
    end

    def pbStartScene(inloadscreen = false)
      super
      apply_mod_settings_viewport
    end

    def initUIElements
      super
      @sprites["title"].text = _INTL(Reloaded::ModSettingsUI.mod_name(@mod_id)) rescue nil
    end

    def pbGetOptions(_inloadscreen = false)
      @settings_master = []
      Reloaded::ModSettings.definitions(@mod_id).each do |setting|
        option = build_setting_option(setting)
        @settings_master << option if option
      end
      @settings_master << Spacer.new if defined?(Spacer) && !@settings_master.empty?
      @reset_option = reset_button
      @settings_master << @reset_option
      setup_collapsible_callbacks
      visible_options
    end

    private

    def build_setting_option(setting)
      case setting["type"].to_s
      when "category_header"
        CollapsibleHeader.new(
          _INTL(Reloaded::ModSettingsUI.setting_label(setting)),
          _INTL(Reloaded::ModSettingsUI.setting_description(setting)),
          collapsed: true
        )
      when "spacer"
        Spacer.new
      when "toggle"
        toggle_option(setting)
      when "enum"
        enum_option(setting)
      when "slider"
        slider_option(setting)
      when "number"
        number_option(setting)
      else
        nil
      end
    end

    def setup_collapsible_callbacks
      @settings_master.each do |option|
        next unless option.is_a?(CollapsibleHeader)
        option.toggle_proc = proc { rebuild_visible_options }
      end
    end

    def visible_options
      visible = []
      collapsed = false
      @settings_master.each do |option|
        if option.is_a?(CollapsibleHeader)
          collapsed = option.collapsed
          visible << option
        elsif option.equal?(@reset_option)
          visible << option
        elsif !collapsed
          visible << option
        end
      end
      visible
    end

    def rebuild_visible_options
      visible = visible_options
      @PokemonOptions = visible
      option_window = @sprites["option"] rescue nil
      return unless option_window
      option_window.instance_variable_set(:@options, visible)
      option_window.instance_variable_set(:@optvalues, Array.new(visible.length, 0))
      option_window.index = [[option_window.index, visible.length].min, 0].max
      visible.each_with_index do |option, index|
        option_window.setValueNoRefresh(index, (option.get || 0)) rescue option_window.setValueNoRefresh(index, 0)
      end
      option_window.refresh
    end

    def apply_mod_settings_viewport
      return unless @viewport && @sprites
      @viewport.z = 100_120
      ["title", "textbox", "option"].each do |key|
        next unless @sprites[key]
        @sprites[key].viewport = @viewport rescue nil
        @sprites[key].z = 100_121 rescue nil
      end
    end

    def toggle_option(setting)
      key = setting["key"].to_s
      EnumOption.new(
        _INTL(Reloaded::ModSettingsUI.setting_label(setting)),
        [_INTL("Off"), _INTL("On")],
        proc { Reloaded::ModSettings.get(@mod_id, key) ? 1 : 0 },
        proc { |value| set_setting(setting, value.to_i == 1) },
        _INTL(Reloaded::ModSettingsUI.setting_description(setting))
      )
    end

    def enum_option(setting)
      key = setting["key"].to_s
      values = Array(setting["options"]).map(&:to_s)
      values = [Reloaded::ModSettings.get(@mod_id, key).to_s] if values.empty?
      EnumOption.new(
        _INTL(Reloaded::ModSettingsUI.setting_label(setting)),
        values.map { |value| _INTL(value) },
        proc {
          index = values.index(Reloaded::ModSettings.get(@mod_id, key).to_s)
          index || 0
        },
        proc { |value| set_setting(setting, values[value.to_i] || values.first) },
        _INTL(Reloaded::ModSettingsUI.setting_description(setting))
      )
    end

    def slider_option(setting)
      key = setting["key"].to_s
      min = setting["min"].nil? ? 0 : setting["min"].to_i
      max = setting["max"].nil? ? 100 : setting["max"].to_i
      step = setting["step"].nil? ? 1 : setting["step"].to_i
      step = 1 if step <= 0
      SliderOption.new(
        _INTL(Reloaded::ModSettingsUI.setting_label(setting)),
        min,
        max,
        step,
        proc { Reloaded::ModSettings.get(@mod_id, key).to_i - min },
        proc { |value| set_setting(setting, value.to_i + min) },
        _INTL(Reloaded::ModSettingsUI.setting_description(setting))
      )
    end

    def number_option(setting)
      key = setting["key"].to_s
      min = setting["min"].nil? ? 0 : setting["min"].to_i
      max = setting["max"].nil? ? 100 : setting["max"].to_i
      NumberOption.new(
        _INTL(Reloaded::ModSettingsUI.setting_label(setting)),
        min,
        max,
        proc { Reloaded::ModSettings.get(@mod_id, key).to_i - min },
        proc { |value| set_setting(setting, value.to_i + min) },
        _INTL(Reloaded::ModSettingsUI.setting_description(setting))
      )
    end

    def reset_button
      ActionButton.new(
        _INTL("Reset Settings"),
        proc {
          if confirm_reset?
            Reloaded::ModSettings.reset(@mod_id)
            Reloaded::ModSettingsUI.mark_restart_required if Reloaded::ModSettings.restart_required?(@mod_id)
            refresh_options_window
          end
        },
        _INTL("Reset all settings for this mod back to their defaults.")
      )
    end

    def confirm_reset?
      mod_settings_confirm("Reset this mod's settings to default?")
    end

    def set_setting(setting, value)
      key = setting["key"].to_s
      old_value = Reloaded::ModSettings.get(@mod_id, key)
      Reloaded::ModSettings.set(@mod_id, key, value)
      if old_value != Reloaded::ModSettings.get(@mod_id, key) && Reloaded::ModSettings.restart_required?(@mod_id, key)
        Reloaded::ModSettingsUI.mark_restart_required
      end
    end

    def refresh_options_window
      option_window = @sprites["option"] rescue nil
      return unless option_window
      for i in 0...@PokemonOptions.length
        option_window.setValueNoRefresh(i, (@PokemonOptions[i].get || 0))
      end
      option_window.refresh
    end
  end
end
