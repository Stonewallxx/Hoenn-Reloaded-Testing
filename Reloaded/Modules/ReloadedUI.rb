#======================================================
# Reloaded UI
# Author: Stonewall
#======================================================
# Focused UI replacements and additions for Reloaded systems.
#
# Responsibilities:
#   - Provide a custom Pokemon Summary stats page.
#   - Use Reloaded-owned graphics where available.
#   - Keep base summary pages untouched unless a Reloaded page is active.
#
#======================================================

module ReloadedUI
  module SummaryFeature
    DEFAULT_SUMMARY_MODE = 1
    DEFAULT_BAG_MODE = 0
    DEFAULT_HINT_TEXTS = 1
    DEFAULT_BIG_ICONS = 0
    SUMMARY_MODE_NAMES = ["Standard", "Reloaded"].freeze
    BAG_MODE_NAMES = ["Standard", "Reloaded"].freeze
    HINT_TEXT_NAMES = ["Off", "On"].freeze
    BIG_ICON_NAMES = ["Off", "On"].freeze

    class << self
      def install
        install_pokemon_system_setting
        register_option
      rescue Exception => e
        Reloaded::Log.exception("Failed to install Reloaded Summary options", e, channel: :options) if defined?(Reloaded::Log)
      end

      def reloaded?
        summary_mode == 1
      rescue
        true
      end

      def reloaded_bag?
        bag_mode == 1
      rescue
        false
      end

      def summary_mode
        ($PokemonSystem.reloaded_summary_mode rescue DEFAULT_SUMMARY_MODE).to_i == 1 ? 1 : 0
      rescue
        DEFAULT_SUMMARY_MODE
      end

      def bag_mode
        ($PokemonSystem.reloaded_bag_mode rescue DEFAULT_BAG_MODE).to_i == 1 ? 1 : 0
      rescue
        DEFAULT_BAG_MODE
      end

      def hint_texts_mode
        ($PokemonSystem.reloaded_hint_texts rescue DEFAULT_HINT_TEXTS).to_i == 1 ? 1 : 0
      rescue
        DEFAULT_HINT_TEXTS
      end

      def big_icons_mode
        ($PokemonSystem.reloaded_big_icons rescue DEFAULT_BIG_ICONS).to_i == 1 ? 1 : 0
      rescue
        DEFAULT_BIG_ICONS
      end

      def big_icons?
        big_icons_mode == 1
      rescue
        false
      end

      def open_options
        return unless defined?(ReloadedUI::OptionsScene)
        pbFadeOutIn do
          scene = ReloadedUI::OptionsScene.new
          screen = PokemonOptionScreen.new(scene)
          screen.pbStartScreen
        end
      rescue Exception => e
        Reloaded::Log.exception("Reloaded UI options failed", e, channel: :options) if defined?(Reloaded::Log)
        Kernel.pbMessage(_INTL("Reloaded UI options are unavailable right now.")) rescue nil
      end

      def install_pokemon_system_setting
        return unless defined?(PokemonSystem)
        PokemonSystem.class_eval do
          def reloaded_summary_mode
            @reloaded_summary_mode.nil? ? ReloadedUI::SummaryFeature::DEFAULT_SUMMARY_MODE : @reloaded_summary_mode
          end

          def reloaded_summary_mode=(value)
            @reloaded_summary_mode = value.to_i == 1 ? 1 : 0
          end

          def reloaded_bag_mode
            @reloaded_bag_mode.nil? ? ReloadedUI::SummaryFeature::DEFAULT_BAG_MODE : @reloaded_bag_mode
          end

          def reloaded_bag_mode=(value)
            @reloaded_bag_mode = value.to_i == 1 ? 1 : 0
          end

          def reloaded_hint_texts
            @reloaded_hint_texts.nil? ? ReloadedUI::SummaryFeature::DEFAULT_HINT_TEXTS : @reloaded_hint_texts
          end

          def reloaded_hint_texts=(value)
            @reloaded_hint_texts = value.to_i == 1 ? 1 : 0
          end

          def reloaded_big_icons
            @reloaded_big_icons.nil? ? ReloadedUI::SummaryFeature::DEFAULT_BIG_ICONS : @reloaded_big_icons
          end

          def reloaded_big_icons=(value)
            @reloaded_big_icons = value.to_i == 1 ? 1 : 0
          end

        end
      end

      def register_option
        return unless defined?(Reloaded::Options) && Reloaded::Options.respond_to?(:register_category_option)
        Reloaded::Options.register_category_option("VISUALS & UI", :reloaded_ui_options, priority: 0) do |_scene|
          [ActionButton.new(
            _INTL("Reloaded UI"),
            proc { open_options },
            _INTL("Open Reloaded UI options.")
          )]
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to register Reloaded Summary option", e, channel: :options) if defined?(Reloaded::Log)
      end
    end
  end

  class OptionsScene < PokemonOption_Scene
    def initUIElements
      super
      @sprites["title"].text = _INTL("Reloaded UI") rescue nil
    end

    def pbGetOptions(_inloadscreen = false)
      options = []
      if defined?(Reloaded::PauseMenuFeature)
        options << Reloaded::PauseMenuFeature.option_row
      end
      if defined?(Reloaded::OverworldMenuFeature)
        options << Reloaded::OverworldMenuFeature.option_row
      end
      options.concat([
        EnumOption.new(
          _INTL("Reloaded Summary"),
          SummaryFeature::SUMMARY_MODE_NAMES.map { |name| _INTL(name) },
          proc { SummaryFeature.summary_mode },
          proc { |value|
            next unless $PokemonSystem
            next_value = value.to_i == 1 ? 1 : 0
            next if SummaryFeature.summary_mode == next_value
            $PokemonSystem.reloaded_summary_mode = next_value
          },
          _INTL("Standard: Uses the base Pokemon Summary stats page.\nReloaded: Uses the Reloaded STATS page.")
        ),
        EnumOption.new(
          _INTL("Reloaded Bag"),
          SummaryFeature::BAG_MODE_NAMES.map { |name| _INTL(name) },
          proc { SummaryFeature.bag_mode },
          proc { |value|
            next unless $PokemonSystem
            next_value = value.to_i == 1 ? 1 : 0
            next if SummaryFeature.bag_mode == next_value
            $PokemonSystem.reloaded_bag_mode = next_value
          },
          _INTL("Standard: Uses the base Bag.\nReloaded: Uses the Reloaded Bag when available.")
        ),
        EnumOption.new(
          _INTL("Big Icons"),
          SummaryFeature::BIG_ICON_NAMES.map { |name| _INTL(name) },
          proc { SummaryFeature.big_icons_mode },
          proc { |value|
            next unless $PokemonSystem
            next_value = value.to_i == 1 ? 1 : 0
            next if SummaryFeature.big_icons_mode == next_value
            $PokemonSystem.reloaded_big_icons = next_value
          },
          _INTL("Replaces Pokemon icons with larger fitted full sprites.")
        ),
        EnumOption.new(
          _INTL("Hint Texts"),
          SummaryFeature::HINT_TEXT_NAMES.map { |name| _INTL(name) },
          proc { SummaryFeature.hint_texts_mode },
          proc { |value|
            next unless $PokemonSystem
            next_value = value.to_i == 1 ? 1 : 0
            next if SummaryFeature.hint_texts_mode == next_value
            $PokemonSystem.reloaded_hint_texts = next_value
          },
          _INTL("Shows or hides Reloaded hint text rows.")
        )
      ])
      options.compact
    end
  end

  module BigIcons
    STANDARD_SIZE = 64
    BIG_SIZE = 96
    EGG_SIZE = 64

    class << self
      def enabled?
        ReloadedUI::SummaryFeature.big_icons?
      rescue
        false
      end

      def build(pokemon, duplicate_frame = false)
        return nil unless enabled? && pokemon
        source = nil
        output = nil
        source = GameData::Species.sprite_bitmap_from_pokemon(pokemon)
        return nil unless source && source.bitmap
        source_bitmap = source.bitmap
        target_size = pokemon.egg? ? EGG_SIZE : BIG_SIZE
        source_width = source_bitmap.width
        source_height = source_bitmap.height
        return nil if source_width <= 0 || source_height <= 0
        scale = [target_size.to_f / source_width, target_size.to_f / source_height].min
        draw_width = [(source_width * scale).round, 1].max
        draw_height = [(source_height * scale).round, 1].max
        frame_count = duplicate_frame ? 2 : 1
        output = Bitmap.new(target_size * frame_count, target_size)
        source_rect = Rect.new(0, 0, source_width, source_height)
        frame_count.times do |frame|
          x = (target_size - draw_width) / 2 + (frame * target_size)
          y = (target_size - draw_height) / 2
          output.stretch_blt(
            Rect.new(x, y, draw_width, draw_height),
            source_bitmap,
            source_rect
          )
        end
        wrapped = AnimatedBitmap.from_bitmap(output)
        output = nil
        wrapped
      rescue Exception => e
        report_failure(pokemon, e)
        nil
      ensure
        source.dispose if source
        output.dispose if output && !output.disposed?
      end

      def horizontal_offset(pokemon, origin = nil)
        return 0 unless pokemon && !pokemon.egg?
        if defined?(PictureOrigin)
          centered = [PictureOrigin::Top, PictureOrigin::Center, PictureOrigin::Bottom]
          return 0 if centered.include?(origin)
        end
        -((BIG_SIZE - STANDARD_SIZE) / 2)
      rescue
        -16
      end

      def storage_offset(pokemon)
        return 0 unless pokemon && !pokemon.egg?
        -((BIG_SIZE - STANDARD_SIZE) / 2)
      rescue
        -16
      end

      private

      def report_failure(pokemon, error)
        @reported_failures ||= {}
        key = pokemon.species rescue :unknown
        return if @reported_failures[key]
        @reported_failures[key] = true
        if defined?(Reloaded::Log)
          Reloaded::Log.exception("Big Icons could not render #{key}", error, channel: :modules)
        end
      rescue
        nil
      end
    end
  end

  module PokemonStatsPage
    ENABLED = true
    SCREEN_W = 512
    SCREEN_H = 384
    FOOTER_H = 22
    FOOTER_Y = SCREEN_H - FOOTER_H
    BACKGROUND_PATH = "Reloaded/Graphics/Backgrounds/statsbackground"
    BG_KEY = "reloaded_ui_stats_bg"
    POKEMON_KEY = "reloaded_ui_stats_pokemon"
    OVERLAY_KEY = "reloaded_ui_stats_overlay"
    CUSTOM_KEYS = [BG_KEY, POKEMON_KEY, OVERLAY_KEY].freeze
    POKEMON_SPRITE_MAX_W = 190
    POKEMON_SPRITE_MAX_H = 150
    STAT_ORDER = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED].freeze
    STAT_LABELS = {
      :HP => "HP",
      :ATTACK => "Attack",
      :DEFENSE => "Defense",
      :SPECIAL_ATTACK => "Sp. Atk",
      :SPECIAL_DEFENSE => "Sp. Def",
      :SPEED => "Speed"
    }.freeze

    BG = Color.new(8, 14, 28)
    FOOTER_BG = Color.new(10, 12, 30, 128)
    PANEL = Color.new(12, 27, 48)
    PANEL_ALT = Color.new(15, 34, 61)
    BORDER = Color.new(74, 139, 204)
    LINE = Color.new(42, 82, 128)
    WHITE = Color.new(238, 246, 255)
    SHADOW = Color.new(36, 44, 62)
    DIM = Color.new(142, 166, 190)
    BLUE = Color.new(92, 182, 255)
    GREEN = Color.new(68, 220, 120)
    RED = Color.new(248, 88, 72)
    YELLOW = Color.new(242, 210, 86)
    PINK = Color.new(255, 126, 186)
    PURPLE = Color.new(178, 132, 244)
    CYAN = Color.new(80, 218, 230)
    NO_SHADOW = Color.new(0, 0, 0, 0)

    class << self
      def draw(scene, page)
        return false unless ENABLED
        return false unless ReloadedUI::SummaryFeature.reloaded?
        return false unless page == 3
        return false unless scene && scene.instance_variable_get(:@pokemon)
        pokemon = scene.instance_variable_get(:@pokemon)
        return false if pokemon.egg?
        sprites = scene.instance_variable_get(:@sprites)
        return false unless sprites
        ensure_sprites(scene, sprites, pokemon)
        hide_base_sprites(sprites)
        draw_background(sprites)
        draw_pokemon_sprite(sprites, pokemon)
        overlay = sprites[OVERLAY_KEY].bitmap
        overlay.clear
        draw_header(overlay, pokemon)
        draw_hidden_power_panel(overlay, pokemon)
        draw_stats_panel(overlay, pokemon)
        draw_ability_panel(overlay, pokemon, scene)
        draw_weakness_panel(overlay, pokemon, scene)
        draw_footer(overlay, pokemon, scene)
        set_custom_visible(sprites, true)
        scene.instance_variable_set(:@reloaded_ui_stats_active, true)
        true
      rescue Exception => e
        Reloaded::Log.exception("ReloadedUI stats page draw failed", e, channel: :modules) if defined?(Reloaded::Log)
        false
      end

      def hide(scene)
        sprites = scene.instance_variable_get(:@sprites)
        return unless sprites
        set_custom_visible(sprites, false)
        restore_base_sprites(sprites, scene.instance_variable_get(:@pokemon))
        scene.instance_variable_set(:@reloaded_ui_stats_active, false)
      rescue
      end

      def ensure_sprites(scene, sprites, pokemon)
        viewport = scene.instance_variable_get(:@viewport)
        if !valid_sprite?(sprites[BG_KEY])
          sprites[BG_KEY] = BitmapSprite.new(SCREEN_W, SCREEN_H, viewport)
          set_sprite_z(sprites[BG_KEY], 20)
        end
        if !valid_pokemon_sprite?(sprites[POKEMON_KEY])
          sprites[POKEMON_KEY].dispose if valid_sprite?(sprites[POKEMON_KEY])
          sprites[POKEMON_KEY] = PokemonSprite.new(viewport)
          sprites[POKEMON_KEY].setOffset(PictureOrigin::Center)
          set_sprite_z(sprites[POKEMON_KEY], 23)
        end
        if !valid_sprite?(sprites[OVERLAY_KEY])
          sprites[OVERLAY_KEY] = BitmapSprite.new(SCREEN_W, SCREEN_H, viewport)
          pbSetSystemFont(sprites[OVERLAY_KEY].bitmap)
          set_sprite_z(sprites[OVERLAY_KEY], 22)
        end
        scene.instance_variable_set(:@reloaded_ui_ability_index, 0) unless scene.instance_variable_defined?(:@reloaded_ui_ability_index)
        set_custom_visible(sprites, false)
      end

      def valid_sprite?(sprite)
        sprite && !(sprite.disposed? rescue false)
      rescue
        false
      end

      def valid_pokemon_sprite?(sprite)
        valid_sprite?(sprite) && sprite.is_a?(PokemonSprite)
      rescue
        false
      end

      def set_sprite_z(sprite, value)
        sprite.z = value if sprite && sprite.respond_to?(:z=)
      rescue
      end

      def set_custom_visible(sprites, visible)
        CUSTOM_KEYS.each do |key|
          next unless sprites[key] && sprites[key].respond_to?(:visible=)
          sprites[key].visible = visible
        end
      rescue
      end

      def hide_base_sprites(sprites)
        sprites.each do |key, sprite|
          next if CUSTOM_KEYS.include?(key)
          next unless sprite && sprite.respond_to?(:visible=)
          sprite.visible = false
        end
      rescue
      end

      def restore_base_sprites(sprites, pokemon)
        return unless sprites
        if sprites["background"] && sprites["background"].respond_to?(:visible=)
          sprites["background"].visible = true
        end
        if sprites["overlay"] && sprites["overlay"].respond_to?(:visible=)
          sprites["overlay"].visible = true
        end
        if sprites["pokemon"] && sprites["pokemon"].respond_to?(:visible=)
          sprites["pokemon"].visible = true
        end
        if sprites["itemicon"] && sprites["itemicon"].respond_to?(:visible=)
          sprites["itemicon"].visible = true
          sprites["itemicon"].item = pokemon.item_id if pokemon && sprites["itemicon"].respond_to?(:item=)
        end
        ["pokeicon", "movepresel", "movesel", "ribbonpresel", "ribbonsel", "uparrow", "downarrow",
         "markingbg", "markingoverlay", "markingsel", "messagebox"].each do |key|
          sprites[key].visible = false if sprites[key] && sprites[key].respond_to?(:visible=)
        end
      rescue
      end

      def draw_background(sprites)
        bitmap = sprites[BG_KEY].bitmap
        bitmap.clear
        if pbResolveBitmap(BACKGROUND_PATH)
          draw_bitmap_scaled(bitmap, BACKGROUND_PATH, 0, 0, SCREEN_W, SCREEN_H)
        else
          bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, BG)
        end
      end

      def draw_pokemon_sprite(sprites, pokemon)
        sprite = sprites[POKEMON_KEY]
        return unless sprite
        sprite.setPokemonBitmap(pokemon) if sprite.respond_to?(:setPokemonBitmap)
        sprite.x = SCREEN_W / 2
        sprite.y = 58
        zoom = pokemon_sprite_zoom(sprite)
        sprite.zoom_x = zoom
        sprite.zoom_y = zoom
      end

      def pokemon_sprite_zoom(sprite)
        return 1.0 unless sprite && sprite.bitmap
        width = sprite.bitmap.width.to_f
        height = sprite.bitmap.height.to_f
        return 1.0 if width <= 0 || height <= 0
        zoom = [POKEMON_SPRITE_MAX_W / width, POKEMON_SPRITE_MAX_H / height, 1.0].min
        [zoom, 0.35].max
      rescue
        1.0
      end

      def draw_header(bitmap, pokemon)
        draw_panel(bitmap, 8, 8, 168, 90)
        draw_text(bitmap, [["POKEMON", 60, 5, 0, BLUE, NO_SHADOW]], 25)
        draw_text(bitmap, [
          [pokemon.name.to_s, 20, 28, 0, WHITE, NO_SHADOW],
          [gender_text(pokemon), 164, 28, 1, gender_color(pokemon), NO_SHADOW]
        ], 22)
        draw_text(bitmap, [["Lv. #{pokemon.level}", 20, 46, 0, WHITE, NO_SHADOW]], 22)
        draw_type_icons(bitmap, pokemon, 17, 73, false)
      rescue
      end

      def draw_hidden_power_panel(bitmap, pokemon)
        x = 336
        y = 8
        w = 168
        h = 90
        draw_panel(bitmap, x, y, w, h)
        draw_text(bitmap, [["ADDITIONAL", x + (w / 2), y - 3, 2, BLUE, NO_SHADOW]], 25)
        type_id, _power = hidden_power_data(pokemon)
        draw_text(bitmap, [["Hidden Power", x + 12, y + 20, 0, WHITE, NO_SHADOW]], 22)
        draw_type_icon(bitmap, type_id, x + w - 28, y + 28, true) if type_id
        draw_text(bitmap, [
          ["Friendship", x + 12, y + 38, 0, WHITE, NO_SHADOW],
          [pokemon.happiness.to_i.to_s, x + w - 10, y + 38, 1, PINK, NO_SHADOW],
          ["Fuse-Type", x + 12, y + 58, 0, WHITE, NO_SHADOW],
          [fusion_type_text(pokemon), x + w - 10, y + 58, 1, CYAN, NO_SHADOW]
        ], 22)
      rescue
      end

      def draw_stats_panel(bitmap, pokemon)
        x = 8
        y = 104
        w = 312
        h = 250
        draw_panel(bitmap, x, y, w, h)
        draw_text(bitmap, [["STATS", x + (w / 2) + 5, y - 3, 2, BLUE, NO_SHADOW]], 25)
        draw_text(bitmap, [
          ["BASE", x + 130, y + 29, 1, WHITE, NO_SHADOW],
          ["IV", x + 185, y + 29, 1, PURPLE, NO_SHADOW],
          ["EV", x + 231, y + 29, 1, GREEN, NO_SHADOW],
          ["BST", x + 286, y + 29, 1, CYAN, NO_SHADOW]
        ], 26)
        raised, lowered = nature_changes(pokemon)
        rows = []
        STAT_ORDER.each_with_index do |stat, index|
          row_y = y + 54 + index * 27
          row_y -= 2 if stat == :SPEED
          label_y = row_y - 1
          number_y = (stat == :HP) ? row_y - 1 : row_y
          current_value_y = (stat == :HP) ? number_y - 2 : number_y
          value_color = WHITE
          label_color = WHITE
          marker = ""
          if stat == raised
            value_color = GREEN
            label_color = GREEN
            marker = "+"
          elsif stat == lowered
            value_color = RED
            label_color = RED
            marker = "-"
          end
          rows << [STAT_LABELS[stat], x + 13, label_y, 0, label_color, NO_SHADOW]
          rows << [marker, x + 97, number_y, 1, value_color, NO_SHADOW] if !marker.empty?
          rows << [current_stat_text(pokemon, stat), x + 130, current_value_y, 1, value_color, NO_SHADOW]
          rows << [pokemon.iv[stat].to_i.to_s, x + 185, number_y, 1, PURPLE, NO_SHADOW]
          rows << [pokemon.ev[stat].to_i.to_s, x + 231, number_y, 1, GREEN, NO_SHADOW]
          rows << [base_stat(pokemon, stat).to_s, x + 286, number_y, 1, CYAN, NO_SHADOW]
          bitmap.fill_rect(x + 12, row_y + 28, w - 24, 1, LINE) if index < STAT_ORDER.length - 1
        end
        draw_text(bitmap, rows, 24)
        draw_text(bitmap, [
          ["TOTAL", x + 18, y + 214, 0, DIM, NO_SHADOW],
          [iv_total(pokemon).to_s, x + 185, y + 214, 1, PURPLE, NO_SHADOW],
          [ev_total(pokemon).to_s, x + 231, y + 214, 1, GREEN, NO_SHADOW],
          [base_stat_total(pokemon).to_s, x + 286, y + 214, 1, YELLOW, NO_SHADOW]
        ], 26)
      rescue
      end

      def draw_ability_panel(bitmap, pokemon, scene)
        x = 328
        y = 104
        w = 176
        h = 158
        draw_panel(bitmap, x, y, w, h)
        ability_id = displayed_ability_id(pokemon, scene)
        ability = ability_id ? GameData::Ability.try_get(ability_id) : nil
        name = ability ? ability.name : "Unknown"
        desc = ability ? ability.description.to_s : "No ability data."
        draw_text(bitmap, [["ABILITY", x + (w / 2), y - 3, 2, BLUE, NO_SHADOW]], 25)
        draw_text(bitmap, [[trim_text(bitmap, name, w - 24), x + 12, y + 23, 0, WHITE, NO_SHADOW]], 20)
        draw_wrapped_text(bitmap, desc, x + 12, y + 50, w - 24, DIM, 5)
        draw_text(bitmap, [[ability_position_text(pokemon, scene), x + (w / 2), y + h - 30, 2, DIM, NO_SHADOW]], 23)
      rescue
      end

      def draw_weakness_panel(bitmap, pokemon, scene)
        x = 328
        y = 270
        w = 176
        h = 84
        draw_panel(bitmap, x, y, w, h)
        draw_text(bitmap, [["WEAKNESS", x + (w / 2), y - 3, 2, BLUE, NO_SHADOW]], 25)
        groups = weakness_groups(pokemon, displayed_ability_id(pokemon, scene))
        row_y = y + 23
        if !groups[:four].empty?
          draw_weakness_row(bitmap, "4x", groups[:four], x + 8, row_y, w - 28, 1)
          row_y += 21
        end
        draw_weakness_row(bitmap, "2x", groups[:two], x + 8, row_y, w - 28, 2) if !groups[:two].empty?
      rescue
      end

      def draw_footer(bitmap, pokemon, scene)
        pbSetSmallFont(bitmap)
        bitmap.font.size = 17
        entries = hint_entries(pokemon, scene)
        if defined?(Reloaded::HintText)
          Reloaded::HintText.draw_footer(bitmap, entries, 0, FOOTER_Y - 3, SCREEN_W, :size => 17, :color => WHITE, :height => SCREEN_H - FOOTER_Y)
        else
          action_label = available_abilities(pokemon).length > 1 ? "Switch Ability" : "Cry"
          hint = scene.instance_variable_get(:@inbattle) ? "Back (B)   #{action_label} (A)" : "Menu (C)   Back (B)   #{action_label} (A)"
          pbDrawTextPositions(bitmap, [[hint, SCREEN_W / 2, FOOTER_Y - 3, 2, WHITE, NO_SHADOW]])
        end
      rescue
      end

      def hint_entries(pokemon, scene)
        action_label = available_abilities(pokemon).length > 1 ? "Switch Ability" : "Cry"
        entries = [Reloaded::HintText.back, Reloaded::HintText.action(action_label)]
        entries.unshift(Reloaded::HintText.confirm("Menu")) unless scene.instance_variable_get(:@inbattle)
        entries
      rescue
        []
      end

      def show_hint_popup(scene)
        return false unless defined?(Reloaded::HintText)
        pokemon = scene.instance_variable_get(:@pokemon)
        return false unless pokemon
        pbPlayDecisionSE rescue nil
        Reloaded::HintText.open_popup("Pokemon Stats Hints", hint_entries(pokemon, scene))
        true
      rescue
        false
      end

      def controls_mouse_clicked?(scene)
        return false unless defined?(Reloaded::HintText)
        return false unless (Input.trigger?(Input::MOUSELEFT) rescue false)
        pos = Reloaded::MouseInput.active_position rescue nil
        return false unless pos.is_a?(Array)
        sprites = scene.instance_variable_get(:@sprites)
        overlay = sprites[OVERLAY_KEY].bitmap rescue nil
        return false unless overlay
        Reloaded::HintText.controls_at?(overlay, pos[0], pos[1], 0, FOOTER_Y - 3, SCREEN_W, :size => 17, :height => SCREEN_H - FOOTER_Y)
      rescue
        false
      end

      def redraw_footer(scene)
        sprites = scene.instance_variable_get(:@sprites)
        overlay = sprites[OVERLAY_KEY].bitmap rescue nil
        pokemon = scene.instance_variable_get(:@pokemon)
        return false unless overlay && pokemon
        overlay.clear_rect(0, FOOTER_Y - 3, SCREEN_W, SCREEN_H - FOOTER_Y + 3)
        draw_footer(overlay, pokemon, scene)
        true
      rescue
        false
      end

      def draw_panel(bitmap, x, y, width, height)
        bitmap.fill_rect(x, y, width, height, PANEL)
        bitmap.fill_rect(x, y, width, 1, BORDER)
        bitmap.fill_rect(x, y + height - 1, width, 1, BORDER)
        bitmap.fill_rect(x, y, 1, height, BORDER)
        bitmap.fill_rect(x + width - 1, y, 1, height, BORDER)
        bitmap.fill_rect(x + 1, y + 1, width - 2, 24, PANEL_ALT) if height > 38
      end

      def draw_text(bitmap, entries, size)
        pbSetSystemFont(bitmap)
        bitmap.font.size = size
        pbDrawTextPositions(bitmap, entries)
      rescue
      end

      def draw_type_icons(bitmap, pokemon, x, y, small)
        types = [pokemon.type1, pokemon.type2].compact.uniq
        spacing = small ? 22 : 52
        types.each_with_index do |type_id, index|
          draw_type_icon(bitmap, type_id, x + index * spacing, y, small)
        end
      rescue
      end

      def draw_weakness_row(bitmap, label, types, x, y, width, max_rows = 1)
        return if types.empty?
        draw_text(bitmap, [[label, x, y - 2, 0, YELLOW, NO_SHADOW]], 16)
        icon_x = x + 30
        max_icons = 6 * [max_rows, 1].max
        visible_types = types.first(max_icons)
        visible_types.each_with_index do |type_id, index|
          row = index / 6
          column = index % 6
          draw_type_icon(bitmap, type_id, icon_x + column * 20, y + 4 + row * 18, true)
        end
        overflow = types.length - visible_types.length
        return if overflow <= 0
        overflow_x = icon_x + [visible_types.length, 6].min * 20 + 2
        overflow_y = y - 2 + ((visible_types.length - 1) / 6) * 18
        draw_text(bitmap, [["+#{overflow}", overflow_x, overflow_y, 0, DIM, NO_SHADOW]], 16)
      end

      def draw_type_icon(bitmap, type_id, x, y, small)
        style = small ? :symbol : :badge
        Reloaded::TypeIcons.draw(
          bitmap, type_id, x, y, style,
          small ? 18 : 47, small ? 18 : 20
        )
      rescue
      end

      def draw_bitmap_scaled(bitmap, path, x, y, width, height)
        bmp = AnimatedBitmap.new(path)
        src = Rect.new(0, 0, bmp.bitmap.width, bmp.bitmap.height)
        dest = Rect.new(x, y, width, height)
        bitmap.stretch_blt(dest, bmp.bitmap, src)
        bmp.dispose
      rescue
        bmp.dispose if bmp rescue nil
      end

      def hidden_power_data(pokemon)
        return [nil, nil] unless pokemon
        forced_type = ReloadedHiddenPower.ensure_type(pokemon) if defined?(ReloadedHiddenPower)
        forced_type ||= pokemon.hiddenPowerType rescue nil
        return pbHiddenPower(pokemon, forced_type) if defined?(pbHiddenPower)
        [forced_type, 60]
      rescue
        [nil, nil]
      end

      def iv_total(pokemon)
        STAT_ORDER.inject(0) { |sum, stat| sum + pokemon.iv[stat].to_i }
      rescue
        0
      end

      def ev_total(pokemon)
        STAT_ORDER.inject(0) { |sum, stat| sum + pokemon.ev[stat].to_i }
      rescue
        0
      end

      def fusion_type_text(pokemon)
        return ReloadedFusion.fusion_type_label(pokemon) if defined?(ReloadedFusion)
        return "Splicer" if pokemon.respond_to?(:isFusion?) && pokemon.isFusion?
        "N/A"
      rescue
        "N/A"
      end

      def available_abilities(pokemon)
        ids = actual_ability_ids(pokemon)
        current = pokemon.ability_id rescue nil
        ids << current if ids.empty? && current
        ids.map { |id| normalize_ability_id(id) }.compact.uniq
      rescue
        current ? [current] : []
      end

      def actual_ability_ids(pokemon)
        ids = []
        [:reloaded_ability_ids, :actual_ability_ids, :ability_ids].each do |method_name|
          next unless pokemon.respond_to?(method_name)
          values = pokemon.send(method_name) rescue nil
          ids.concat(Array(values)) if values
        end
        [:@reloaded_ability_ids, :@actual_ability_ids, :@ability_ids].each do |ivar|
          next unless pokemon.instance_variable_defined?(ivar)
          values = pokemon.instance_variable_get(ivar) rescue nil
          ids.concat(Array(values)) if values
        end
        ids
      rescue
        []
      end

      def normalize_ability_id(value)
        value = value[0] if value.is_a?(Array)
        return value.id if value.respond_to?(:id)
        GameData::Ability.get(value).id
      rescue
        nil
      end

      def gender_text(pokemon)
        return "♂" if pokemon.male?
        return "♀" if pokemon.female?
        ""
      rescue
        ""
      end

      def gender_color(pokemon)
        return Color.new(92, 182, 255) if pokemon.male?
        return Color.new(248, 88, 142) if pokemon.female?
        DIM
      rescue
        DIM
      end

      def displayed_ability_id(pokemon, scene)
        abilities = available_abilities(pokemon)
        return pokemon.ability_id if abilities.empty?
        index = scene.instance_variable_get(:@reloaded_ui_ability_index).to_i rescue 0
        abilities[index % abilities.length]
      rescue
        pokemon.ability_id rescue nil
      end

      def ability_position_text(pokemon, scene)
        abilities = available_abilities(pokemon)
        return "0/0" if abilities.empty?
        index = scene.instance_variable_get(:@reloaded_ui_ability_index).to_i rescue 0
        "#{(index % abilities.length) + 1}/#{abilities.length}"
      rescue
        "1/1"
      end

      def cycle_ability(scene)
        return false unless ReloadedUI::SummaryFeature.reloaded?
        pokemon = scene.instance_variable_get(:@pokemon)
        abilities = available_abilities(pokemon)
        return false if abilities.length <= 1
        index = scene.instance_variable_get(:@reloaded_ui_ability_index).to_i rescue 0
        scene.instance_variable_set(:@reloaded_ui_ability_index, (index + 1) % abilities.length)
        true
      rescue
        false
      end

      def weakness_groups(pokemon, ability_id)
        two = []
        four = []
        GameData::Type.each do |type_data|
          next if type_data.pseudo_type
          eff = Effectiveness.calculate(type_data.id, pokemon.type1, pokemon.type2)
          eff = apply_ability_effectiveness(type_data.id, eff, ability_id)
          four << type_data.id if eff >= Effectiveness::EXTREMELY_EFFECTIVE
          two << type_data.id if eff > Effectiveness::NORMAL_EFFECTIVE && eff < Effectiveness::EXTREMELY_EFFECTIVE
        end
        { :two => two, :four => four }
      rescue
        { :two => [], :four => [] }
      end

      def apply_ability_effectiveness(type_id, effectiveness, ability_id)
        case ability_id
        when :VOLTABSORB, :LIGHTNINGROD, :MOTORDRIVE
          return Effectiveness::INEFFECTIVE if type_id == :ELECTRIC
        when :WATERABSORB, :STORMDRAIN, :DRYSKIN
          return Effectiveness::INEFFECTIVE if type_id == :WATER
        when :FLASHFIRE
          return Effectiveness::INEFFECTIVE if type_id == :FIRE
        when :SAPSIPPER
          return Effectiveness::INEFFECTIVE if type_id == :GRASS
        when :LEVITATE
          return Effectiveness::INEFFECTIVE if type_id == :GROUND
        when :THICKFAT
          return [effectiveness / 2, Effectiveness::INEFFECTIVE].max if type_id == :FIRE || type_id == :ICE
        when :HEATPROOF, :WATERBUBBLE
          return [effectiveness / 2, Effectiveness::INEFFECTIVE].max if type_id == :FIRE
        when :WONDERGUARD
          return Effectiveness::INEFFECTIVE if effectiveness <= Effectiveness::NORMAL_EFFECTIVE
        end
        effectiveness
      rescue
        effectiveness
      end

      def nature_changes(pokemon)
        raised = nil
        lowered = nil
        return [raised, lowered] if pokemon.shadowPokemon? && pokemon.heartStage <= 3
        nature = pokemon.nature_for_stats
        nature.stat_changes.each do |change|
          raised = change[0] if change[1] > 0
          lowered = change[0] if change[1] < 0
        end
        [raised, lowered]
      rescue
        [nil, nil]
      end

      def current_stat_text(pokemon, stat)
        case stat
        when :HP then "#{pokemon.hp}/#{pokemon.totalhp}"
        when :ATTACK then pokemon.attack.to_i.to_s
        when :DEFENSE then pokemon.defense.to_i.to_s
        when :SPECIAL_ATTACK then pokemon.spatk.to_i.to_s
        when :SPECIAL_DEFENSE then pokemon.spdef.to_i.to_s
        when :SPEED then pokemon.speed.to_i.to_s
        else "0"
        end
      rescue
        "0"
      end

      def base_stat(pokemon, stat)
        pokemon.baseStats[stat].to_i
      rescue
        0
      end

      def base_stat_total(pokemon)
        STAT_ORDER.inject(0) { |sum, stat| sum + base_stat(pokemon, stat) }
      rescue
        0
      end

      def draw_wrapped_text(bitmap, text, x, y, width, color, max_lines)
        pbSetSmallFont(bitmap)
        bitmap.font.size = 16
        lines = wrap_text(bitmap, text, width, max_lines)
        lines.each_with_index do |line, index|
          pbDrawTextPositions(bitmap, [[line, x, y + index * 16, 0, color, NO_SHADOW]])
        end
      rescue
      end

      def wrap_text(bitmap, text, width, max_lines)
        words = text.to_s.split(/\s+/)
        lines = []
        line = ""
        words.each do |word|
          test = line.empty? ? word : "#{line} #{word}"
          if bitmap.text_size(test).width <= width
            line = test
          else
            lines << line unless line.empty?
            line = word
            break if lines.length >= max_lines
          end
        end
        lines << line if !line.empty? && lines.length < max_lines
        lines
      rescue
        [text.to_s]
      end

      def trim_text(bitmap, text, width)
        value = text.to_s
        return value if bitmap.text_size(value).width <= width
        while value.length > 3 && bitmap.text_size("#{value}...").width > width
          value = value[0...-1]
        end
        "#{value}..."
      rescue
        text.to_s
      end
    end
  end
end

ReloadedUI::SummaryFeature.install if defined?(ReloadedUI::SummaryFeature)

if defined?(PokemonIconSprite)
  class PokemonIconSprite
    unless method_defined?(:reloaded_big_icons_native_pokemon_set)
      alias_method :reloaded_big_icons_native_pokemon_set, :pokemon=
      alias_method :reloaded_big_icons_native_set_offset, :setOffset

      def pokemon=(value)
        @reloaded_big_icon_active = false
        unless ReloadedUI::BigIcons.enabled? && value
          result = reloaded_big_icons_native_pokemon_set(value)
          self.x = @logical_x unless @logical_x.nil?
          self.y = @logical_y unless @logical_y.nil?
          return result
        end
        full_sprite = ReloadedUI::BigIcons.build(value, true)
        unless full_sprite
          result = reloaded_big_icons_native_pokemon_set(value)
          self.x = @logical_x unless @logical_x.nil?
          self.y = @logical_y unless @logical_y.nil?
          return result
        end
        @pokemon = value
        @animBitmap.dispose if @animBitmap
        @animBitmap = full_sprite
        self.bitmap = @animBitmap.bitmap
        self.src_rect.width = @animBitmap.height
        self.src_rect.height = @animBitmap.height
        @numFrames = [@animBitmap.width / @animBitmap.height, 1].max
        @currentFrame = 0
        @counter = 0
        @reloaded_big_icon_active = true
        changeOrigin
        self.x = @logical_x unless @logical_x.nil?
        self.y = @logical_y unless @logical_y.nil?
        value
      end

      def x=(value)
        @logical_x = value
        offset = @adjusted_x || 0
        if @reloaded_big_icon_active
          offset += ReloadedUI::BigIcons.horizontal_offset(@pokemon, @offset)
        end
        super(@logical_x + offset)
      end

      def y=(value)
        @logical_y = value
        super(@logical_y + (@adjusted_y || 0))
      end

      def setOffset(offset = PictureOrigin::Center)
        reloaded_big_icons_native_set_offset(offset)
        self.x = @logical_x unless @logical_x.nil?
        self.y = @logical_y unless @logical_y.nil?
      end
    end
  end
end

if defined?(PokemonBoxIcon)
  class PokemonBoxIcon
    unless method_defined?(:reloaded_big_icons_native_initialize)
      alias_method :reloaded_big_icons_native_initialize, :initialize
      alias_method :reloaded_big_icons_native_refresh, :refresh

      def initialize(*args)
        @reloaded_big_icon_offset_x = 0
        @reloaded_big_icon_offset_y = 0
        @reloaded_big_icon_logical_x = 0
        @reloaded_big_icon_logical_y = 0
        reloaded_big_icons_native_initialize(*args)
      end

      def x
        @reloaded_big_icon_logical_x
      end

      def y
        @reloaded_big_icon_logical_y
      end

      def x=(value)
        @reloaded_big_icon_logical_x = value
        super(value + (@reloaded_big_icon_offset_x || 0))
      end

      def y=(value)
        @reloaded_big_icon_logical_y = value
        super(value + (@reloaded_big_icon_offset_y || 0))
      end

      def refresh(*args)
        unless ReloadedUI::BigIcons.enabled? && @pokemon
          @reloaded_big_icon_offset_x = 0
          @reloaded_big_icon_offset_y = 0
          result = reloaded_big_icons_native_refresh(*args)
          self.x = @reloaded_big_icon_logical_x
          self.y = @reloaded_big_icon_logical_y
          return result
        end
        full_sprite = ReloadedUI::BigIcons.build(@pokemon)
        unless full_sprite
          @reloaded_big_icon_offset_x = 0
          @reloaded_big_icon_offset_y = 0
          result = reloaded_big_icons_native_refresh(*args)
          self.x = @reloaded_big_icon_logical_x
          self.y = @reloaded_big_icon_logical_y
          return result
        end
        offset = ReloadedUI::BigIcons.storage_offset(@pokemon)
        @reloaded_big_icon_offset_x = offset
        @reloaded_big_icon_offset_y = offset
        setBitmapDirectly(full_sprite)
        self.src_rect = Rect.new(0, 0, self.bitmap.width, self.bitmap.height)
        self.visible = true
        self.x = @reloaded_big_icon_logical_x
        self.y = @reloaded_big_icon_logical_y
        true
      end
    end
  end
end

if defined?(PokemonSummary_Scene)
  class PokemonSummary_Scene
    unless method_defined?(:reloaded_ui_drawPage)
      alias_method :reloaded_ui_drawPage, :drawPage
      def drawPage(page)
        if ReloadedUI::PokemonStatsPage.draw(self, page)
          return
        end
        ReloadedUI::PokemonStatsPage.hide(self)
        reloaded_ui_drawPage(page)
      end
    end

    unless method_defined?(:reloaded_ui_pbScene)
      alias_method :reloaded_ui_pbScene, :pbScene
      def pbScene
        @pokemon.play_cry
        loop do
          Graphics.update
          Input.update
          pbUpdate
          ReloadedUI::PokemonStatsPage.redraw_footer(self) if @page == 3 && ((Graphics.frame_count rescue 0) % 4) == 0
          dorefresh = false
          if @page == 3 && defined?(Reloaded::HintText) && Reloaded::HintText.triggered?
            ReloadedUI::PokemonStatsPage.show_hint_popup(self)
            dorefresh = true
          elsif @page == 3 && ReloadedUI::PokemonStatsPage.controls_mouse_clicked?(self)
            ReloadedUI::PokemonStatsPage.show_hint_popup(self)
            dorefresh = true
          elsif Input.trigger?(Input::ACTION)
            if @page == 3 && ReloadedUI::PokemonStatsPage.cycle_ability(self)
              pbPlayDecisionSE
              dorefresh = true
            else
              pbSEStop
              @pokemon.play_cry
            end
          elsif Input.trigger?(Input::BACK)
            pbPlayCloseMenuSE
            break
          elsif Input.trigger?(Input::USE)
            if @page == 4
              pbPlayDecisionSE
              pbMoveSelection
              dorefresh = true
            elsif @page == 5
              @page -= 1
              pbPlayDecisionSE
            elsif !@inbattle
              pbPlayDecisionSE
              dorefresh = pbOptions
            end
          elsif Input.trigger?(Input::UP) && @partyindex > 0
            oldindex = @partyindex
            pbGoToPrevious
            if @partyindex != oldindex
              pbChangePokemon
              @ribbonOffset = 0
              @reloaded_ui_ability_index = 0
              dorefresh = true
            end
          elsif Input.trigger?(Input::DOWN)
            if @partyindex < @party.length - 1
              oldindex = @partyindex
              pbGoToNext
              if @partyindex != oldindex
                pbChangePokemon
                @ribbonOffset = 0
                @reloaded_ui_ability_index = 0
                dorefresh = true
              end
            end
          elsif Input.trigger?(Input::LEFT) && !@pokemon.egg?
            oldpage = @page
            @page -= 1
            @page = 1 if @page < 1
            @page = 5 if @page > 5
            if @page != oldpage
              pbSEPlay("GUI summary change page")
              @ribbonOffset = 0
              dorefresh = true
            end
          elsif Input.trigger?(Input::RIGHT) && !@pokemon.egg?
            if @page == 4 && (!$Trainer.has_pokedex || !@is_player)
              pbSEPlay("GUI sel buzzer")
            else
              oldpage = @page
              @page += 1
              @page = 1 if @page < 1
              @page = 5 if @page > 5
              if @page != oldpage
                pbSEPlay("GUI summary change page")
                @ribbonOffset = 0
                dorefresh = true
              end
            end
          end
          drawPage(@page) if dorefresh
        end
        return @partyindex
      end
    end

  end

  Reloaded::Log.info("Installed ReloadedUI Pokemon stats page", :modules) if defined?(Reloaded::Log)
end
