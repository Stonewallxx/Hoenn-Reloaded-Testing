#======================================================
# Reloaded Options
# Author: Stonewall
#======================================================
# Reusable options framework for Hoenn Reloaded.
#
# Responsibilities:
#   - Add Reloaded option themes and option UI settings.
#   - Add reusable option row types for future menus.
#   - Improve option drawing, sliders, headers, and action rows.
#   - Patch the existing options scene without editing vanilla files.
#   - Support the global small text toggle.
#   - Add Reloaded menu frames and speech-follows-menu support.
#
#======================================================

module Reloaded
  module Options
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    WINDOWSKIN_DIR = File.join(ROOT, "Graphics", "Windowskins")
    WINDOWSKIN_LOGICAL_DIR = "Reloaded/Graphics/Windowskins"

    COLOR_THEMES = [
      { :id => :purple, :name => "Purple", :base => Color.new(168, 128, 228), :shadow => Color.new(64, 44, 84) },
      { :id => :blue,   :name => "Blue",   :base => Color.new(88, 176, 248),  :shadow => Color.new(32, 64, 96) },
      { :id => :green,  :name => "Green",  :base => Color.new(50, 205, 50),   :shadow => Color.new(20, 100, 20) },
      { :id => :red,    :name => "Red",    :base => Color.new(240, 120, 120), :shadow => Color.new(92, 44, 44) },
      { :id => :orange, :name => "Orange", :base => Color.new(248, 168, 88),  :shadow => Color.new(96, 64, 32) },
      { :id => :cyan,   :name => "Cyan",   :base => Color.new(88, 224, 224),  :shadow => Color.new(32, 84, 84) },
      { :id => :pink,   :name => "Pink",   :base => Color.new(248, 136, 192), :shadow => Color.new(96, 52, 72) },
      { :id => :yellow, :name => "Yellow", :base => Color.new(240, 224, 88),  :shadow => Color.new(92, 84, 32) },
      { :id => :white,  :name => "White",  :base => Color.new(248, 248, 248), :shadow => Color.new(72, 80, 88) },
      { :id => :black,  :name => "Black",  :base => Color.new(80, 80, 88),    :shadow => Color.new(160, 160, 168) }
    ].freeze

    CURSOR_THEMES = [
      { :id => :blue,   :name => "Blue",   :fill => Color.new(100, 160, 220, 160), :border => Color.new(60, 120, 180, 220) },
      { :id => :purple, :name => "Purple", :fill => Color.new(160, 120, 220, 160), :border => Color.new(100, 60, 170, 220) },
      { :id => :green,  :name => "Green",  :fill => Color.new(80, 200, 100, 160),  :border => Color.new(40, 140, 60, 220) },
      { :id => :red,    :name => "Red",    :fill => Color.new(220, 100, 100, 160), :border => Color.new(170, 50, 50, 220) },
      { :id => :orange, :name => "Orange", :fill => Color.new(220, 160, 80, 160),  :border => Color.new(170, 110, 30, 220) },
      { :id => :cyan,   :name => "Cyan",   :fill => Color.new(80, 220, 220, 160),  :border => Color.new(30, 160, 160, 220) },
      { :id => :pink,   :name => "Pink",   :fill => Color.new(220, 120, 180, 160), :border => Color.new(160, 60, 120, 220) },
      { :id => :yellow, :name => "Yellow", :fill => Color.new(220, 210, 80, 160),  :border => Color.new(160, 150, 30, 220) },
      { :id => :white,  :name => "White",  :fill => Color.new(220, 220, 220, 160), :border => Color.new(160, 160, 160, 220) },
      { :id => :black,  :name => "Black",  :fill => Color.new(60, 60, 70, 160),    :border => Color.new(30, 30, 40, 220) }
    ].freeze

    DEFAULT_OPTION_THEME = 0
    DEFAULT_CATEGORY_THEME = 3
    DEFAULT_CURSOR_THEME = 0
    DEFAULT_OPTIONS_CURSOR_THEME = 8
    DEFAULT_SMALL_TEXT = 1
    DEFAULT_MENU_FRAME = "default_transparent"
    DEFAULT_SPEECH_FOLLOWS_MENU = true
    DEFAULTS_VERSION = 2
    LOG_MODE_VALUES = [:player, :developer].freeze
    LOG_MODE_NAMES = ["Player", "Developer"].freeze
    PLATFORM_OVERRIDE_VALUES = [:auto, :windows, :proton, :joiplay].freeze
    PLATFORM_OVERRIDE_NAMES = ["Auto", "Windows", "Proton", "JoiPlay"].freeze

    @category_extensions = Hash.new { |hash, key| hash[key] = [] }

    class << self
      def install
        return true if @installed
        install_pokemon_system_settings
        install_small_text_patch
        install_message_config_patch
        install_menu_text_color_patch
        install_system_options_patch
        install_bag_and_mart_cursor_patches
        register_patch_point
        @installed = true
        Reloaded::Log.info("Installed Reloaded options framework", :options) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        @installed = false
        Reloaded::Log.exception("Reloaded options framework install failed", e, channel: :options) if defined?(Reloaded::Log)
        false
      end

      def theme(index)
        COLOR_THEMES[index.to_i] || COLOR_THEMES[DEFAULT_OPTION_THEME]
      end

      def cursor_theme(index)
        CURSOR_THEMES[index.to_i] || CURSOR_THEMES[DEFAULT_CURSOR_THEME]
      end

      def theme_names
        COLOR_THEMES.map { |entry| entry[:name] }
      end

      def cursor_theme_names
        CURSOR_THEMES.map { |entry| entry[:name] }
      end

      def cursor_theme_index(id)
        index = CURSOR_THEMES.index { |entry| entry[:id] == id }
        index || DEFAULT_CURSOR_THEME
      end

      def reloaded_menu_frames
        return [] unless Dir.exist?(WINDOWSKIN_DIR)
        Dir[File.join(WINDOWSKIN_DIR, "*.png")].sort_by { |path| natural_sort_key(File.basename(path)) }.map do |path|
          basename = File.basename(path, ".png")
          {
            :name => basename,
            :label => windowskin_label(basename),
            :path => "#{WINDOWSKIN_LOGICAL_DIR}/#{basename}",
            :dark => dark_windowskin?(basename)
          }
        end
      rescue
        []
      end

      def menu_frame_names
        reloaded_menu_frames.map { |entry| entry[:label] }
      end

      def menu_frame_count
        menu_frame_names.length
      end

      def default_menu_frame_index
        index = reloaded_menu_frames.index { |entry| entry[:name].to_s.downcase == DEFAULT_MENU_FRAME }
        index || 0
      end

      def current_menu_frame_index
        $PokemonSystem.apply_reloaded_option_defaults! if $PokemonSystem && $PokemonSystem.respond_to?(:apply_reloaded_option_defaults!)
        clamp_menu_frame_index($PokemonSystem ? $PokemonSystem.frame : default_menu_frame_index)
      rescue
        default_menu_frame_index
      end

      def current_menu_frame_dark?
        entry = reloaded_menu_frames[current_menu_frame_index]
        return true unless entry
        entry[:dark] ? true : false
      rescue
        true
      end

      def readable_text_colors
        if current_menu_frame_dark?
          [Color.new(248, 248, 248), Color.new(72, 80, 88)]
        else
          [Color.new(48, 48, 48), Color.new(224, 224, 224)]
        end
      end

      def popup_message(text)
        if defined?(Reloaded) && Reloaded.respond_to?(:message)
          Reloaded.message(text.to_s)
        elsif defined?(pbMessage)
          pbMessage(text.to_s)
        end
      rescue
        pbMessage(text.to_s) rescue nil
      end

      def theme_text_colors(index)
        selected = theme(index)
        if !current_menu_frame_dark? && selected[:id] == :white
          return readable_text_colors
        end
        [selected[:base], selected[:shadow]]
      rescue
        readable_text_colors
      end

      def ensure_options_cursor_contrast!
        return unless $PokemonSystem && $PokemonSystem.respond_to?(:reloaded_options_cursor_theme)
        return if current_menu_frame_dark?
        white = cursor_theme_index(:white)
        black = cursor_theme_index(:black)
        $PokemonSystem.reloaded_options_cursor_theme = black if $PokemonSystem.reloaded_options_cursor_theme.to_i == white
      rescue
        nil
      end

      def effective_options_cursor_theme_index
        ensure_options_cursor_contrast!
        ($PokemonSystem.reloaded_options_cursor_theme rescue DEFAULT_OPTIONS_CURSOR_THEME).to_i
      end

      def apply_menu_frame_text_colors(window)
        return unless window
        base, shadow = readable_text_colors
        window.instance_variable_set(:@baseColor, base)
        window.instance_variable_set(:@shadowColor, shadow)
        window.instance_variable_set(:@nameBaseColor, base) if window.instance_variable_defined?(:@nameBaseColor)
        window.instance_variable_set(:@nameShadowColor, shadow) if window.instance_variable_defined?(:@nameShadowColor)
        window.instance_variable_set(:@selBaseColor, base) if window.instance_variable_defined?(:@selBaseColor)
        window.instance_variable_set(:@selShadowColor, shadow) if window.instance_variable_defined?(:@selShadowColor)
      rescue
        nil
      end

      def menu_frame_path(index)
        idx = clamp_menu_frame_index(index)
        entry = reloaded_menu_frames[idx]
        return entry[:path] if entry
        Reloaded::Log.warning("No Reloaded menu frames were found in #{WINDOWSKIN_DIR}", :options) if defined?(Reloaded::Log)
        ""
      end

      def clamp_menu_frame_index(index)
        max = [menu_frame_count - 1, 0].max
        [[index.to_i, 0].max, max].min
      end

      def set_menu_frame(index)
        return unless $PokemonSystem
        frame_index = clamp_menu_frame_index(index)
        if $PokemonSystem.frame.to_i == frame_index
          apply_speech_frame
          return
        end
        $PokemonSystem.frame = frame_index
        ensure_options_cursor_contrast!
        MessageConfig.pbSetSystemFrame(menu_frame_path($PokemonSystem.frame)) if defined?(MessageConfig)
        apply_speech_frame
      rescue Exception => e
        Reloaded::Log.exception("Failed to set menu frame", e, channel: :options) if defined?(Reloaded::Log)
      end

      def speech_follows_menu?
        ($PokemonSystem && $PokemonSystem.reloaded_speech_follows_menu) ? true : false
      rescue
        false
      end

      def apply_speech_frame
        return unless defined?(MessageConfig) && $PokemonSystem
        if speech_follows_menu?
          MessageConfig.pbSetSpeechFrame(menu_frame_path(current_menu_frame_index))
        else
          MessageConfig.pbSetSpeechFrame(vanilla_speech_frame_path($PokemonSystem.textskin))
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to apply speech frame", e, channel: :options) if defined?(Reloaded::Log)
      end

      def refresh_option_scene_skins(scene)
        return unless scene && defined?(MessageConfig)
        apply_speech_frame if speech_follows_menu?
        sprites = scene.instance_variable_get(:@sprites) rescue nil
        return unless sprites
        system_skin = MessageConfig.pbGetSystemFrame rescue menu_frame_path($PokemonSystem.frame)
        speech_skin = MessageConfig.pbGetSpeechFrame rescue vanilla_speech_frame_path($PokemonSystem.textskin)
        ["title", "option"].each do |key|
          next unless sprites[key] && sprites[key].respond_to?(:setSkin)
          sprites[key].setSkin(system_skin)
          if key == "option" && sprites[key].respond_to?(:apply_theme)
            sprites[key].apply_theme
          else
            apply_menu_frame_text_colors(sprites[key])
          end
          sprites[key].refresh if sprites[key].respond_to?(:refresh)
        end
        if sprites["textbox"] && sprites["textbox"].respond_to?(:setSkin)
          sprites["textbox"].setSkin(speech_skin)
          apply_menu_frame_text_colors(sprites["textbox"])
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to refresh option scene skins", e, channel: :options) if defined?(Reloaded::Log)
      end

      def refresh_option_scene_fonts(scene)
        return unless scene
        sprites = scene.instance_variable_get(:@sprites) rescue nil
        return unless sprites
        sprites.each_value do |sprite|
          next unless sprite && sprite.respond_to?(:contents) && sprite.contents
          pbSetSystemFont(sprite.contents) rescue nil
          sprite.refresh if sprite.respond_to?(:refresh)
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to refresh option scene fonts", e, channel: :options) if defined?(Reloaded::Log)
      end

      def vanilla_speech_frame_path(index)
        skins = defined?(Settings::SPEECH_WINDOWSKINS) ? Settings::SPEECH_WINDOWSKINS : []
        idx = [[index.to_i, 0].max, [skins.length - 1, 0].max].min
        "Graphics/Windowskins/" + skins[idx].to_s
      end

      private

      def natural_sort_key(value)
        value.to_s.downcase.split(/(\d+)/).map { |part| part =~ /\A\d+\z/ ? part.to_i : part }
      end

      def vanilla_windowskin_label(name)
        name.to_s.split(/[_\s]+/).map { |part| part[0, 1].to_s.upcase + part[1..-1].to_s }.join(" ")
      end

      def windowskin_label(basename)
        case basename
        when /\A(?:RLD|HR) Choice (\d+)a\z/i
          "RLD #{$1} Dark"
        when /\A(?:RLD|HR) Choice (\d+)\z/i
          "RLD #{$1}"
        when /\Adefault_transparent\z/i
          "RLD Transparent Dark"
        when /\Adefault_opaque\z/i
          "RLD Opaque Dark"
        else
          label = vanilla_windowskin_label(basename)
          dark_windowskin?(basename) ? "#{label} Dark" : label
        end
      end

      def dark_windowskin?(basename)
        lower = basename.to_s.downcase
        return true if ["default_transparent", "default_opaque"].include?(lower)
        lower =~ /a\z/ ? true : false
      end

      def install_pokemon_system_settings
        return unless defined?(PokemonSystem)
        PokemonSystem.class_eval do
          def reloaded_option_theme
            @reloaded_option_theme.nil? ? Reloaded::Options::DEFAULT_OPTION_THEME : @reloaded_option_theme
          end

          def reloaded_option_theme=(value)
            @reloaded_option_theme = value.to_i
          end

          def reloaded_category_theme
            @reloaded_category_theme.nil? ? Reloaded::Options::DEFAULT_CATEGORY_THEME : @reloaded_category_theme
          end

          def reloaded_category_theme=(value)
            @reloaded_category_theme = value.to_i
          end

          def reloaded_cursor_theme
            @reloaded_cursor_theme.nil? ? Reloaded::Options::DEFAULT_CURSOR_THEME : @reloaded_cursor_theme
          end

          def reloaded_cursor_theme=(value)
            @reloaded_cursor_theme = value.to_i
          end

          def reloaded_options_cursor_theme
            @reloaded_options_cursor_theme.nil? ? Reloaded::Options::DEFAULT_OPTIONS_CURSOR_THEME : @reloaded_options_cursor_theme
          end

          def reloaded_options_cursor_theme=(value)
            @reloaded_options_cursor_theme = value.to_i
          end

          def reloaded_small_text
            apply_reloaded_option_defaults!
            @reloaded_small_text.nil? ? Reloaded::Options::DEFAULT_SMALL_TEXT : @reloaded_small_text
          end

          def reloaded_small_text=(value)
            @reloaded_small_text = value.to_i
          end

          def reloaded_speech_follows_menu
            apply_reloaded_option_defaults!
            @reloaded_speech_follows_menu.nil? ? Reloaded::Options::DEFAULT_SPEECH_FOLLOWS_MENU : @reloaded_speech_follows_menu
          end

          def reloaded_speech_follows_menu=(value)
            @reloaded_speech_follows_menu = value ? true : false
          end

          def reloaded_options_defaults_version
            @reloaded_options_defaults_version || 0
          end

          def apply_reloaded_option_defaults!
            old_defaults_version = reloaded_options_defaults_version
            return if old_defaults_version >= Reloaded::Options::DEFAULTS_VERSION
            @frame = Reloaded::Options.default_menu_frame_index
            @reloaded_speech_follows_menu = Reloaded::Options::DEFAULT_SPEECH_FOLLOWS_MENU
            @reloaded_options_cursor_theme = Reloaded::Options::DEFAULT_OPTIONS_CURSOR_THEME if @reloaded_options_cursor_theme.nil?
            @reloaded_small_text = Reloaded::Options::DEFAULT_SMALL_TEXT if @reloaded_small_text.nil? || old_defaults_version < 2
            @reloaded_options_defaults_version = Reloaded::Options::DEFAULTS_VERSION
          end

          unless method_defined?(:reloaded_options_initialize)
            alias_method :reloaded_options_initialize, :initialize
            def initialize
              reloaded_options_initialize
              @reloaded_option_theme = Reloaded::Options::DEFAULT_OPTION_THEME
              @reloaded_category_theme = Reloaded::Options::DEFAULT_CATEGORY_THEME
              @reloaded_cursor_theme = Reloaded::Options::DEFAULT_CURSOR_THEME
              @reloaded_options_cursor_theme = Reloaded::Options::DEFAULT_OPTIONS_CURSOR_THEME
              @reloaded_small_text = Reloaded::Options::DEFAULT_SMALL_TEXT
              @frame = Reloaded::Options.default_menu_frame_index
              @reloaded_speech_follows_menu = Reloaded::Options::DEFAULT_SPEECH_FOLLOWS_MENU
              @reloaded_options_defaults_version = Reloaded::Options::DEFAULTS_VERSION
            end
          end
        end
      end

      def install_small_text_patch
        Object.class_eval do
          next unless method_defined?(:pbSetSystemFont) || private_method_defined?(:pbSetSystemFont)
          next if method_defined?(:reloaded_options_pbSetSystemFont) || private_method_defined?(:reloaded_options_pbSetSystemFont)
          alias_method :reloaded_options_pbSetSystemFont, :pbSetSystemFont
          def pbSetSystemFont(bitmap)
            if (($PokemonSystem.reloaded_small_text rescue 0).to_i == 1) && respond_to?(:pbSetSmallFont, true)
              pbSetSmallFont(bitmap)
            else
              reloaded_options_pbSetSystemFont(bitmap)
            end
          end
          private :pbSetSystemFont
        end
      end

      def install_message_config_patch
        return unless defined?(MessageConfig)
        class << MessageConfig
          unless method_defined?(:reloaded_options_pbDefaultSystemFrame)
            alias_method :reloaded_options_pbDefaultSystemFrame, :pbDefaultSystemFrame
            def pbDefaultSystemFrame
              if $PokemonSystem && defined?(Reloaded::Options)
                return pbResolveBitmap(Reloaded::Options.menu_frame_path(Reloaded::Options.current_menu_frame_index)) || ""
              end
              reloaded_options_pbDefaultSystemFrame
            end
          end

          unless method_defined?(:reloaded_options_pbDefaultSpeechFrame)
            alias_method :reloaded_options_pbDefaultSpeechFrame, :pbDefaultSpeechFrame
            def pbDefaultSpeechFrame
              if $PokemonSystem && defined?(Reloaded::Options) && Reloaded::Options.speech_follows_menu?
                return pbResolveBitmap(Reloaded::Options.menu_frame_path(Reloaded::Options.current_menu_frame_index)) || ""
              end
              reloaded_options_pbDefaultSpeechFrame
            end
          end
        end
      end

      def install_menu_text_color_patch
        patch_pause_menu_text_color if defined?(Window_PauseMenuCommand)
      end

      def patch_pause_menu_text_color
        Window_PauseMenuCommand.class_eval do
          include ReloadedDrawHelper

          unless method_defined?(:reloaded_options_refresh)
            alias_method :reloaded_options_refresh, :refresh

            def refresh
              Reloaded::Options.apply_menu_frame_text_colors(self) if defined?(Reloaded::Options)
              reloaded_options_refresh
            end
          end

        end
      end

      def install_system_options_patch
        return unless defined?(PokemonGameOption_Scene)
        PokemonGameOption_Scene.class_eval do
          unless method_defined?(:reloaded_options_pbGetOptions)
            alias_method :reloaded_options_pbGetOptions, :pbGetOptions
            def pbGetOptions(inloadscreen = false)
              Reloaded::Options.consolidated_game_options(self, inloadscreen)
            end
          end
        end
      end

      public

      def consolidated_game_options(scene, inloadscreen = false)
        scene.instance_variable_set(:@current_game_mode, getTrainersDataMode) rescue nil
        master = build_consolidated_master(scene, inloadscreen)
        setup_collapsible_callbacks(scene, master)
        scene.instance_variable_set(:@reloaded_options_master, master)
        visible_consolidated_options(master)
      end

      def register_category_option(category, option_id, priority: 100, &block)
        key = category_key(category)
        return false if key.empty? || option_id.to_s.empty? || !block
        @category_extensions[key].delete_if { |entry| entry[:id] == option_id.to_sym }
        @category_extensions[key] << {
          :id => option_id.to_sym,
          :priority => priority.to_i,
          :block => block
        }
        Reloaded::Log.debug("Registered options extension #{key}/#{option_id}", :options) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to register options extension #{category}/#{option_id}", e, channel: :options) if defined?(Reloaded::Log)
        false
      end

      def build_consolidated_master(scene, inloadscreen = false)
        system = source_options(SystemOptionsScene, inloadscreen)
        gameplay = source_options(GameplayOptionsScene, inloadscreen)
        visuals = source_options(SpriteOptionsScene, inloadscreen)
        challenge = source_options(ChallengeOptionsScene, inloadscreen)

        master = []
        append_collapsible(master, "RELOADED", reloaded_options(scene))
        append_collapsible(master, "VISUALS & UI",
          [
            option_theme_option(scene),
            category_theme_option(scene),
            cursor_theme_option(scene),
            options_cursor_theme_option(scene),
            small_text_option(scene),
            menu_frame_option(scene),
            speech_frame_option(take_option(system, "Speech Frame")),
            speech_follows_menu_option(scene)
          ].compact +
          take_options(visuals, [
            "Fusion Icons",
            "Battle Type Icons",
            "Battle Animations",
            "Battle Movement",
            "Random Sprites",
            "Joke Sprites",
            "Custom Eggs",
            "Autogen dex entries",
            "Autogen Dex Entries"
          ])
        )
        append_collapsible(master, "GAMEPLAY",
          take_options(gameplay, [
            "Difficulty",
            "Default Movement",
            "Overworld Encounters",
            "Battle type",
            "Battle Type",
            "Battle Style",
            "Prompt Nicknames",
            "Quick HMs",
            "Trainers"
          ]) + take_options(challenge, ["Battle Style"])
        )
        append_collapsible(master, "ECONOMY", economy_options(scene))
        append_collapsible(master, "CHALLENGE",
          take_options(challenge, [
            "Level caps",
            "Level Caps",
            "No reviving",
            "No Reviving",
            "No heals (battles)",
            "No Heals (Battle)",
            "No heals (overworld)",
            "No Heals (Overworld)",
            "No Pokecenters",
            "No Pokécenters"
          ])
        )
        append_collapsible(master, "SYSTEM",
          category_extension_options("SYSTEM", scene) +
          take_options(system, [
            "Music Volume",
            "SE Volume",
            "Text Speed",
            "Text Entry",
            "Screen Size",
            "Autosave",
            "Download data",
            "Download Data",
            "Device"
          ]) + take_options(gameplay, [
            "Speed-up type",
            "Speed-up Type",
            "Speed-up (Overworld)",
            "Speed-up (Battles)"
          ]) + take_options(visuals, [
            "Autogen dex entries",
            "Autogen Dex Entries"
          ])
        )
        append_collapsible(master, "MODS", [
          mod_manager_option,
          mod_settings_option,
          moddev_option
        ] + category_extension_options("MODS", scene))
        append_collapsible(master, "DEVELOPER", [admin_tools_option, foundation_inspector_option, logging_mode_option, platform_override_option] + category_extension_options("DEVELOPER", scene))
        leftovers = system + gameplay + visuals + challenge
        append_collapsible(master, "OTHER", leftovers) unless leftovers.empty?
        master
      end

      def source_options(scene_class, inloadscreen = false)
        return [] unless defined?(scene_class) && scene_class
        scene_class.new.pbGetOptions(inloadscreen)
      rescue Exception => e
        Reloaded::Log.exception("Failed to read #{scene_class} options", e, channel: :options) if defined?(Reloaded::Log)
        []
      end

      def append_collapsible(target, label, options, collapsed: true)
        rows = Array(options).compact
        return if rows.empty?
        target << CollapsibleHeader.new(_INTL(label), category_description(label), collapsed: collapsed)
        target.concat(rows)
      end

      def category_extension_options(category, scene)
        key = category_key(category)
        @category_extensions[key].sort_by { |entry| [entry[:priority], entry[:id].to_s] }.flat_map do |entry|
          Array(entry[:block].call(scene)).compact
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to build options extensions for #{category}", e, channel: :options) if defined?(Reloaded::Log)
        []
      end

      def category_key(category)
        category.to_s.strip.upcase
      end

      def economy_options(_scene)
        []
      end

      def reloaded_options(scene)
        category_extension_options("RELOADED", scene)
      end

      def setup_collapsible_callbacks(scene, master)
        master.each do |option|
          next unless option.is_a?(CollapsibleHeader)
          option.toggle_proc = proc { rebuild_visible_options(scene) }
        end
      end

      def visible_consolidated_options(master)
        visible = []
        collapsed = false
        Array(master).each do |option|
          if option.is_a?(CollapsibleHeader)
            collapsed = option.collapsed
            visible << option
          elsif !collapsed
            visible << option
          end
        end
        visible
      end

      def rebuild_visible_options(scene)
        return unless scene
        sprites = scene.instance_variable_get(:@sprites) rescue nil
        master = scene.instance_variable_get(:@reloaded_options_master) rescue nil
        return unless sprites && sprites["option"] && master
        visible = visible_consolidated_options(master)
        scene.instance_variable_set(:@PokemonOptions, visible)
        window = sprites["option"]
        window.instance_variable_set(:@options, visible)
        window.instance_variable_set(:@optvalues, Array.new(visible.length, 0))
        window.index = [[window.index, visible.length].min, 0].max
        visible.each_with_index do |option, index|
          window.setValueNoRefresh(index, (option.get || 0)) rescue window.setValueNoRefresh(index, 0)
        end
        window.refresh
      rescue Exception => e
        Reloaded::Log.exception("Failed to rebuild visible consolidated options", e, channel: :options) if defined?(Reloaded::Log)
      end

      def take_options(source, names)
        picked = []
        names.each do |name|
          index = source.index { |option| option_name?(option, name) }
          picked << source.delete_at(index) if index
        end
        picked
      end

      def take_option(source, name)
        take_options(source, [name]).first
      end

      def option_name?(option, name)
        return false unless option.respond_to?(:name)
        normalize_option_name(option.name) == normalize_option_name(_INTL(name))
      end

      def normalize_option_name(name)
        name.to_s.downcase.gsub(/[éÃ©]/, "e").gsub(/[^a-z0-9]+/, " ").strip
      end

      def category_description(label)
        case label
        when "RELOADED"
          _INTL("Hoenn Reloaded framework information.")
        when "VISUALS & UI"
          _INTL("Window frames, colors, battle visuals, and sprite settings.")
        when "GAMEPLAY"
          _INTL("Difficulty, movement, and battle rule settings.")
        when "ECONOMY"
          _INTL("Mart and money settings.")
        when "CHALLENGE"
          _INTL("Self-imposed restrictions for extra difficulty.")
        when "SYSTEM"
          _INTL("Audio, text, screen, and performance settings.")
        when "MODS"
          _INTL("Mod loading and development settings.")
        when "DEVELOPER"
          _INTL("Diagnostics and debugging settings.")
        else
          _INTL("Additional options.")
        end
      end

      def option_theme_option(scene)
        EnumOption.new(
          _INTL("UI Color"),
          theme_names.map { |name| _INTL(name) },
          proc { ($PokemonSystem.reloaded_option_theme rescue DEFAULT_OPTION_THEME).to_i },
          proc { |value|
            next_value = value.to_i
            next if ($PokemonSystem.reloaded_option_theme rescue DEFAULT_OPTION_THEME).to_i == next_value
            $PokemonSystem.reloaded_option_theme = value
            option_window = scene.instance_variable_get(:@sprites)["option"] rescue nil
            option_window.apply_theme if option_window && option_window.respond_to?(:apply_theme)
          },
          _INTL("Color theme for option menus and UI text.")
        )
      end

      def category_theme_option(scene)
        EnumOption.new(
          _INTL("Category Color"),
          theme_names.map { |name| _INTL(name) },
          proc { ($PokemonSystem.reloaded_category_theme rescue DEFAULT_CATEGORY_THEME).to_i },
          proc { |value|
            next_value = value.to_i
            next if ($PokemonSystem.reloaded_category_theme rescue DEFAULT_CATEGORY_THEME).to_i == next_value
            $PokemonSystem.reloaded_category_theme = value
            option_window = scene.instance_variable_get(:@sprites)["option"] rescue nil
            option_window.refresh if option_window
          },
          _INTL("Color theme used for category headers.")
        )
      end

      def cursor_theme_option(scene)
        EnumOption.new(
          _INTL("Cursor Color"),
          cursor_theme_names.map { |name| _INTL(name) },
          proc { ($PokemonSystem.reloaded_cursor_theme rescue DEFAULT_CURSOR_THEME).to_i },
          proc { |value|
            next_value = value.to_i
            next if ($PokemonSystem.reloaded_cursor_theme rescue DEFAULT_CURSOR_THEME).to_i == next_value
            $PokemonSystem.reloaded_cursor_theme = value
            option_window = scene.instance_variable_get(:@sprites)["option"] rescue nil
            option_window.refresh if option_window
          },
          _INTL("Color of the selection cursor in the Bag and Marts.")
        )
      end

      def options_cursor_theme_option(scene)
        EnumOption.new(
          _INTL("Options Cursor Color"),
          cursor_theme_names.map { |name| _INTL(name) },
          proc { effective_options_cursor_theme_index },
          proc { |value|
            next_value = value.to_i
            next if effective_options_cursor_theme_index == next_value
            $PokemonSystem.reloaded_options_cursor_theme = value
            ensure_options_cursor_contrast!
            option_window = scene.instance_variable_get(:@sprites)["option"] rescue nil
            option_window.refresh if option_window
          },
          _INTL("Color of the pulsing selection box in the Options menu.")
        )
      end

      def logging_mode_index
        return 1 unless defined?(Reloaded::Log)
        index = LOG_MODE_VALUES.index(Reloaded::Log.mode)
        index || 1
      rescue
        1
      end

      def logging_mode_option
        EnumOption.new(
          _INTL("Logging Mode"),
          LOG_MODE_NAMES.map { |name| _INTL(name) },
          proc { logging_mode_index },
          proc { |value|
            next_mode = LOG_MODE_VALUES[value.to_i] || :developer
            Reloaded::Log.set_mode(next_mode) if defined?(Reloaded::Log) && Reloaded::Log.mode != next_mode
          },
          _INTL("Controls how much detail Reloaded writes to its log files.")
        )
      end

      def platform_override_option
        return nil unless defined?(Reloaded::Platform) && Reloaded::Platform.developer_override_available?
        EnumOption.new(
          _INTL("Platform Override"),
          PLATFORM_OVERRIDE_NAMES.map { |name| _INTL(name) },
          proc {
            index = PLATFORM_OVERRIDE_VALUES.index(Reloaded::Platform.override)
            index || 0
          },
          proc { |value|
            next unless Reloaded::Platform.developer_override_available?
            selected = PLATFORM_OVERRIDE_VALUES[value.to_i] || :auto
            next if Reloaded::Platform.override == selected
            Reloaded::Platform.set_override(selected)
          },
          _INTL("Developer-only platform simulation for capability and visibility testing. Auto uses the detected platform.")
        )
      end

      def foundation_inspector_option
        return nil unless developer_tools_enabled?
        ActionButton.new(
          _INTL("Foundation Inspector"),
          proc {
            if defined?(Reloaded::FoundationInspector)
              Reloaded::FoundationInspector.open
            else
              Reloaded::Options.popup_message(_INTL("The Foundation Inspector is not loaded."))
            end
          },
          _INTL("Inspect Reloaded systems, save migrations, features, hooks, and validators.")
        )
      end

      def developer_tools_enabled?
        return true if defined?($DEBUG) && $DEBUG
        defined?(Reloaded::ModManager) && Reloaded::ModManager.moddev_enabled?
      rescue
        false
      end

      def moddev_option
        return nil if defined?(Reloaded::Platform) && !Reloaded::Platform.supports?(:moddev_tools)
        EnumOption.new(
          _INTL("ModDev"),
          [_INTL("Off"), _INTL("On")],
          proc { (defined?(Reloaded::ModManager) && Reloaded::ModManager.moddev_enabled?) ? 1 : 0 },
          proc { |value|
            next unless defined?(Reloaded::ModManager)
            enabled = value.to_i == 1
            next if Reloaded::ModManager.moddev_enabled? == enabled
            Reloaded::ModManager.set_moddev_enabled(enabled)
          },
          _INTL("When On, Reloaded scans ModDev/ and lets it override matching Mods/ entries.\nChanges apply on the next mod scan or restart.")
        )
      end

      def admin_tools_option
        return nil if defined?(Reloaded::Platform) && !Reloaded::Platform.supports?(:admin_tools)
        return nil unless admin_tools_unlocked?
        ActionButton.new(
          _INTL("Admin Tools"),
          proc {
            if defined?(Reloaded::ModManagerUI) && Reloaded::ModManagerUI.respond_to?(:open_admin_tools)
              Reloaded::ModManagerUI.open_admin_tools
            else
              Reloaded::Options.popup_message(_INTL("Admin Tools are not loaded."))
            end
          },
          _INTL("Open local admin-only Reloaded editors.")
        )
      end

      def admin_tools_unlocked?
        root = File.expand_path("./Admin Tools")
        key = File.join(root, "Admin.txt")
        manager = File.join(root, "Manager Editor", "ManagerEditor.rb")
        mart = File.join(root, "Reloaded Mart Editor", "ReloadedMartEditor.rb")
        File.exist?(key) && (File.exist?(manager) || File.exist?(mart))
      rescue
        false
      end

      def mod_manager_option
        ActionButton.new(
          _INTL("Mod Manager"),
          proc {
            if defined?(Reloaded::ModManagerUI)
              Reloaded::ModManagerUI.open
            else
              Reloaded::Options.popup_message(_INTL("The Reloaded Mod Manager UI is not loaded."))
            end
          },
          _INTL("Open the Reloaded Mod Manager.")
        )
      end

      def mod_settings_option
        ActionButton.new(
          _INTL("Mod Settings"),
          proc {
            if defined?(Reloaded::ModSettingsUI)
              restart_required = Reloaded::ModSettingsUI.open
              Reloaded::Options.popup_message(_INTL("Changes have been made.\nRestart Required")) if restart_required
            else
              Reloaded::Options.popup_message(_INTL("The Reloaded Mod Settings UI is not loaded."))
            end
          },
          _INTL("Open settings pages exposed by installed Reloaded mods.")
        )
      end

      def small_text_option(scene)
        EnumOption.new(
          _INTL("Global Small Text"),
          [_INTL("Off"), _INTL("On")],
          proc { ($PokemonSystem.reloaded_small_text rescue DEFAULT_SMALL_TEXT).to_i },
          proc { |value|
            next_value = value.to_i
            next if ($PokemonSystem.reloaded_small_text rescue DEFAULT_SMALL_TEXT).to_i == next_value
            $PokemonSystem.reloaded_small_text = value
            refresh_option_scene_fonts(scene)
          },
          _INTL("Uses the small system font globally.")
        )
      end

      def menu_frame_option(scene)
        EnumOption.new(
          _INTL("Menu Frame"),
          menu_frame_names,
          proc { current_menu_frame_index },
          proc { |value|
            next if current_menu_frame_index == clamp_menu_frame_index(value)
            set_menu_frame(value)
            refresh_option_scene_skins(scene)
          },
          _INTL("Window border used for menus and option screens.\nUses frames from Reloaded/Graphics/Windowskins.")
        )
      end

      def speech_frame_option(source_option)
        return nil unless source_option
        LockableNumberOption.new(
          _INTL("Speech Frame"),
          source_option.optstart,
          source_option.optend,
          proc { source_option.get rescue ($PokemonSystem.textskin rescue 0) },
          proc { |value|
            next if speech_follows_menu?
            source_option.set(value) if source_option.respond_to?(:set)
          },
          proc { speech_follows_menu? },
          _INTL("Speech/dialogue window border.\nTurn Speech Follows Menu Off to edit this separately."),
          locked_label: _INTL("Uses Menu"),
          locked_popup: proc {
            pbPlayBuzzerSE rescue nil
            Reloaded::Options.popup_message(_INTL("Speech Frame follows Menu Frame right now."))
          }
        )
      end

      def speech_follows_menu_option(scene)
        EnumOption.new(
          _INTL("Speech Follows Menu"),
          [_INTL("Off"), _INTL("On")],
          proc { speech_follows_menu? ? 1 : 0 },
          proc { |value|
            enabled = value.to_i == 1
            if speech_follows_menu? == enabled
              apply_speech_frame if enabled
              next
            end
            $PokemonSystem.reloaded_speech_follows_menu = enabled
            apply_speech_frame
            refresh_option_scene_skins(scene)
          },
          _INTL("When On, speech/dialogue boxes use the selected menu frame.")
        )
      end

      def install_bag_and_mart_cursor_patches
        patch_bag_cursor if defined?(Window_PokemonBag)
        patch_mart_cursor if defined?(Window_PokemonMart)
        Reloaded::Log.info("Installed Reloaded bag/mart cursor color patches", :options) if defined?(Reloaded::Log)
      end

      def patch_bag_cursor
        Window_PokemonBag.class_eval do
          include ReloadedDrawHelper

          unless method_defined?(:reloaded_options_drawCursor)
            alias_method :reloaded_options_drawCursor, :drawCursor

            def drawCursor(_index, _rect)
              nil
            end
          end

          unless method_defined?(:reloaded_options_update_cursor_rect)
            alias_method :reloaded_options_update_cursor_rect, :update_cursor_rect

            def update_cursor_rect
              return self.cursor_rect.empty if @index < 0
              row = @index / @column_max
              new_top_row = row - ((page_row_max - 1) / 2).floor
              new_top_row = [[new_top_row, row_max - page_row_max].min, 0].max
              self.top_row = new_top_row if top_row != new_top_row
              self.cursor_rect.empty
              refresh unless @reloaded_options_refreshing
            end
          end

          unless method_defined?(:reloaded_options_refresh)
            alias_method :reloaded_options_refresh, :refresh

            def refresh
              @reloaded_options_refreshing = true
              reloaded_options_refresh
            ensure
              @reloaded_options_refreshing = false
            end
          end

          unless method_defined?(:reloaded_options_drawItem)
            alias_method :reloaded_options_drawItem, :drawItem

            def drawItem(index, _count, rect)
              if self.index == index
                reloaded_draw_rounded_rect(
                  self.contents,
                  rect.x + 2,
                  rect.y + 7,
                  rect.width - 4,
                  rect.height - 4,
                  ReloadedDrawHelper::CURSOR_RADIUS,
                  reloaded_cursor_fill,
                  reloaded_cursor_border
                )
              end
              pbSetSmallFont(self.contents)
              textpos = []
              rect = Rect.new(rect.x + 16, rect.y + 4, rect.width - 16, rect.height)
              thispocket = @bag.pockets[@pocket]
              if index == self.itemCount - 1
                closeBase = @baseColor
                closeShadow = @shadowColor
                closeBase, closeShadow = closeShadow, closeBase if isDarkMode
                textpos.push([_INTL("CLOSE BAG"), rect.x, rect.y - 2, false, closeBase, closeShadow])
              else
                item = @filterlist ? thispocket[@filterlist[@pocket][index]][0] : thispocket[index][0]
                baseColor = @baseColor
                shadowColor = @shadowColor
                baseColor, shadowColor = shadowColor, baseColor if isDarkMode
                if @sorting && index == self.index
                  baseColor = Color.new(224, 0, 0)
                  shadowColor = Color.new(248, 144, 144)
                end
                textpos.push([@adapter.getDisplayName(item), rect.x, rect.y - 2, false, baseColor, shadowColor])
                if GameData::Item.get(item).is_important?
                  if @bag.pbIsRegistered?(item)
                    pbDrawImagePositions(self.contents, [
                      ["Graphics/Pictures/Bag/icon_register", rect.x + rect.width - 72, rect.y + 5, 0, 0, -1, 24]
                    ])
                  elsif pbCanRegisterItem?(item)
                    pbDrawImagePositions(self.contents, [
                      ["Graphics/Pictures/Bag/icon_register", rect.x + rect.width - 72, rect.y + 5, 0, 24, -1, 24]
                    ])
                  end
                else
                  qty = @filterlist ? thispocket[@filterlist[@pocket][index]][1] : thispocket[index][1]
                  qtytext = _ISPRINTF("x{1: 3d}", qty)
                  xQty = rect.x + rect.width - self.contents.text_size(qtytext).width - 16
                  textpos.push([qtytext, xQty, rect.y - 2, false, baseColor, shadowColor])
                end
              end
              pbDrawTextPositions(self.contents, textpos)
            end
          end
        end
      end

      def patch_mart_cursor
        Window_PokemonMart.class_eval do
          include ReloadedDrawHelper

          unless method_defined?(:reloaded_options_drawCursor)
            alias_method :reloaded_options_drawCursor, :drawCursor

            def drawCursor(index, rect)
              if self.index == index
                reloaded_draw_rounded_rect(
                  self.contents,
                  rect.x + 19,
                  rect.y + 2,
                  rect.width - 25,
                  rect.height - 4,
                  ReloadedDrawHelper::CURSOR_RADIUS,
                  reloaded_cursor_fill,
                  reloaded_cursor_border
                )
              end
              rect.x += 16
              rect.width -= 16
              rect
            end
          end

          unless method_defined?(:reloaded_options_update_cursor_rect)
            alias_method :reloaded_options_update_cursor_rect, :update_cursor_rect

            def update_cursor_rect
              return self.cursor_rect.empty if @index < 0
              row = @index / @column_max
              new_top_row = row - ((page_row_max - 1) / 2).floor
              new_top_row = [[new_top_row, row_max - page_row_max].min, 0].max
              self.top_row = new_top_row if top_row != new_top_row
              self.cursor_rect.empty
              refresh unless @reloaded_options_refreshing
            end
          end

          unless method_defined?(:reloaded_options_refresh)
            alias_method :reloaded_options_refresh, :refresh

            def refresh
              @reloaded_options_refreshing = true
              reloaded_options_refresh
            ensure
              @reloaded_options_refreshing = false
            end
          end
        end
      end

      private

      def register_patch_point
        return unless defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          :options_framework,
          :target => "PokemonGameOption_Scene/PokemonOption_Scene/Window_PokemonOption/PokemonSystem/Window_PokemonBag/Window_PokemonMart",
          :type => :wrap,
          :file => __FILE__,
          :owner => :reloaded,
          :priority => 100,
          :reason => "Adds Reloaded option row types, themes, small text, frame options, consolidated categories, option window improvements, and themed bag/mart cursors.",
          :recommended_fix => "Review Reloaded::Options if the options menu fails to draw or save settings.",
          :conflict_group => "options_scene_framework"
        )
      end
    end
  end
end

module ReloadedDrawHelper
  CURSOR_RADIUS = 4

  def reloaded_cursor_fill
    theme = Reloaded::Options.cursor_theme(($PokemonSystem.reloaded_cursor_theme rescue 0))
    theme[:fill]
  end

  def reloaded_cursor_border
    theme = Reloaded::Options.cursor_theme(($PokemonSystem.reloaded_cursor_theme rescue 0))
    theme[:border]
  end

  def reloaded_options_cursor_fill
    theme = Reloaded::Options.cursor_theme(Reloaded::Options.effective_options_cursor_theme_index)
    theme[:fill]
  end

  def reloaded_options_cursor_border
    theme = Reloaded::Options.cursor_theme(Reloaded::Options.effective_options_cursor_theme_index)
    theme[:border]
  end

  def reloaded_with_alpha(color, alpha)
    Color.new(color.red, color.green, color.blue, alpha)
  rescue
    Color.new(255, 255, 255, alpha)
  end

  def reloaded_draw_rounded_rect(bitmap, x, y, width, height, radius, fill, border = nil)
    radius = [radius, width / 2, height / 2].min
    bitmap.fill_rect(x + radius, y, width - radius * 2, height, fill)
    bitmap.fill_rect(x, y + radius, radius, height - radius * 2, fill)
    bitmap.fill_rect(x + width - radius, y + radius, radius, height - radius * 2, fill)
    reloaded_quarter_circle(bitmap, x + radius, y + radius, radius, fill, :top_left)
    reloaded_quarter_circle(bitmap, x + width - radius - 1, y + radius, radius, fill, :top_right)
    reloaded_quarter_circle(bitmap, x + radius, y + height - radius - 1, radius, fill, :bottom_left)
    reloaded_quarter_circle(bitmap, x + width - radius - 1, y + height - radius - 1, radius, fill, :bottom_right)
    return unless border
    bitmap.fill_rect(x + radius, y, width - radius * 2, 2, border)
    bitmap.fill_rect(x + radius, y + height - 2, width - radius * 2, 2, border)
    bitmap.fill_rect(x, y + radius, 2, height - radius * 2, border)
    bitmap.fill_rect(x + width - 2, y + radius, 2, height - radius * 2, border)
  end

  def reloaded_draw_selection_box(bitmap, x, y, width, height, fill, border = nil)
    bitmap.fill_rect(x, y, width, height, fill)
    return unless border
    bitmap.fill_rect(x, y, width, 1, border)
    bitmap.fill_rect(x, y + height - 1, width, 1, border)
    bitmap.fill_rect(x, y, 1, height, border)
    bitmap.fill_rect(x + width - 1, y, 1, height, border)
  end

  def reloaded_quarter_circle(bitmap, center_x, center_y, radius, color, corner)
    (0..radius).each do |dx|
      (0..radius).each do |dy|
        next unless dx * dx + dy * dy <= radius * radius
        px = center_x + ([:top_right, :bottom_right].include?(corner) ? dx : -dx)
        py = center_y + ([:bottom_left, :bottom_right].include?(corner) ? dy : -dy)
        bitmap.fill_rect(px, py, 1, 1, color)
      end
    end
  end
end

if defined?(Option)
  class TextDisplayOption < Option
    include PropertyMixin
    attr_reader :name

    def initialize(name, value_proc, description = "")
      super(description)
      @name = name
      @value_proc = value_proc
    end

    def non_interactive?
      true
    end

    def get
      0
    end

    def set(_value); end

    def values
      [current_text]
    end

    def next(current)
      current
    end

    def prev(current)
      current
    end

    def current_text
      (@value_proc.call rescue "").to_s
    end
  end

  class LockableEnumOption < EnumOption
    def initialize(name, options, getProc, setProc, lock_proc, description = "", locked_label: "Locked", locked_popup: nil)
      super(name, options, getProc, setProc, description)
      @lock_proc = lock_proc
      @locked_label = locked_label
      @locked_popup = locked_popup
    end

    def locked?
      (@lock_proc.call rescue false) ? true : false
    end

    def on_locked_attempt(attempted_value)
      if @locked_popup
        @locked_popup.call rescue nil
      elsif @setProc
        @setProc.call(attempted_value) rescue nil
      end
    end

    def values
      locked? ? [@locked_label] : super
    end

    def next(current)
      locked? ? current : super
    end

    def prev(current)
      locked? ? current : super
    end
  end

  class ConditionalEnumOption < EnumOption
    def initialize(name, options, getProc, setProc, disabled_proc, description = "", disabled_label: "Disabled")
      super(name, options, getProc, setProc, description)
      @disabled_proc = disabled_proc
      @disabled_label = disabled_label
    end

    def disabled?
      (@disabled_proc.call rescue false) ? true : false
    end

    def disabled_label
      value = @disabled_label.respond_to?(:call) ? @disabled_label.call : @disabled_label
      value.to_s
    rescue
      "Disabled"
    end

    def set(value)
      super(value) unless disabled?
    end

    def next(current)
      disabled? ? current : super
    end

    def prev(current)
      disabled? ? current : super
    end
  end

  class LockableNumberOption < NumberOption
    attr_reader :locked_label

    def initialize(name, optstart, optend, getProc, setProc, lock_proc, description = "", locked_label: "Locked", locked_popup: nil)
      super(name, optstart, optend, getProc, setProc, description)
      @lock_proc = lock_proc
      @locked_label = locked_label
      @locked_popup = locked_popup
    end

    def locked?
      (@lock_proc.call rescue false) ? true : false
    end

    def on_locked_attempt(_attempted_value = nil)
      if @locked_popup
        @locked_popup.call rescue nil
      end
    end

    def next(current)
      if locked?
        on_locked_attempt(current)
        return current
      end
      super
    end

    def prev(current)
      if locked?
        on_locked_attempt(current)
        return current
      end
      super
    end
  end

  class ActionButton < Option
    include PropertyMixin
    attr_reader :name

    def initialize(name, action_proc, description = "")
      super(description)
      @name = name
      @action_proc = action_proc
    end

    def get
      0
    end

    def set(_value); end

    def activate
      @action_proc.call if @action_proc
    end

    def next(current)
      current
    end

    def prev(current)
      current
    end

    def values
      [""]
    end
  end

  class HiddenOption < Option
    include PropertyMixin
    attr_reader :name

    def initialize(name, getProc, setProc)
      super("")
      @name = name
      @getProc = getProc
      @setProc = setProc
    end

    def non_interactive?
      true
    end

    def values
      [""]
    end

    def next(current)
      current
    end

    def prev(current)
      current
    end
  end

  class Spacer < Option
    attr_reader :name

    def initialize
      super("")
      @name = ""
    end

    def non_interactive?
      true
    end

    def get
      0
    end

    def set(_value); end

    def values
      [""]
    end

    def next(current)
      current
    end

    def prev(current)
      current
    end
  end

  class CategoryHeader < Option
    attr_reader :name

    def initialize(name, description = "")
      super(description)
      @name = name
    end

    def non_interactive?
      true
    end

    def get
      0
    end

    def set(_value); end

    def values
      [""]
    end

    def next(current)
      current
    end

    def prev(current)
      current
    end

    def format(_value)
      "--- #{@name} ---"
    end
  end

  class CollapsibleHeader < CategoryHeader
    attr_reader :collapsed
    attr_accessor :toggle_proc

    def initialize(name, description = "", collapsed: false)
      super(name, description)
      @collapsed = collapsed
      @toggle_proc = nil
    end

    def non_interactive?
      false
    end

    def toggle
      @collapsed = !@collapsed
      @toggle_proc.call if @toggle_proc
    end

    def display_name
      @collapsed ? "+ #{@name} +" : "- #{@name} -"
    end
  end
end

if defined?(SliderOption)
  class SliderOption
    def next(current)
      value = current + @optinterval
      value = @optend if value > @optend
      value
    end

    def prev(current)
      value = current - @optinterval
      value = @optstart if value < @optstart
      value
    end
  end

  class ConditionalSliderOption < SliderOption
    def initialize(name, optstart, optend, optinterval, getProc, setProc, disabled_proc, description = "", disabled_label: "Disabled")
      super(name, optstart, optend, optinterval, getProc, setProc, description)
      @disabled_proc = disabled_proc
      @disabled_label = disabled_label
    end

    def disabled?
      (@disabled_proc.call rescue false) ? true : false
    end

    def disabled_label
      value = @disabled_label.respond_to?(:call) ? @disabled_label.call : @disabled_label
      value.to_s
    rescue
      "Disabled"
    end

    def set(value)
      super(value) unless disabled?
    end

    def next(current)
      disabled? ? current : super
    end

    def prev(current)
      disabled? ? current : super
    end
  end
end

if defined?(Window_PokemonOption)
  class Window_ReloadedOption < Window_PokemonOption
    include ReloadedDrawHelper

    LABEL_FRAC = 9
    ROW_FRAC = 20

    def initialize(options, x, y, width, height)
      super(options, x, y, width, height)
      pbSetSystemFont(self.contents) if self.contents
      apply_theme
    end

    def nameBaseColor=(value)
      @nameBaseColor = value
      apply_theme
    end

    def nameShadowColor=(value)
      @nameShadowColor = value
      apply_theme
    end

    def apply_theme
      base, shadow = Reloaded::Options.theme_text_colors(($PokemonSystem.reloaded_option_theme rescue 0))
      @baseColor = base
      @shadowColor = shadow
      @nameBaseColor = base
      @nameShadowColor = shadow
      @selBaseColor = base
      @selShadowColor = shadow
      refresh rescue nil
    end

    def update
      old_index = self.index
      @mustUpdateOptions = false

      if self.active && self.index < @options.length
        option = @options[self.index]
        if option.is_a?(LockableEnumOption) && option.locked?
          if Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
            attempted = Input.trigger?(Input::RIGHT) ? option.values.length - 1 : 0
            option.on_locked_attempt(attempted)
            refresh
            return
          end
        end
      end

      super
      move_off_non_interactive(old_index)

      if self.active && self.index < @options.length
        option = @options[self.index]
        if option.is_a?(CollapsibleHeader) && Input.trigger?(Input::USE)
          option.toggle
          refresh
          return
        end
        if option.respond_to?(:non_interactive?) && option.non_interactive?
          refresh
          return
        end
        if option.is_a?(ActionButton) && Input.trigger?(Input::USE)
          option.activate
          @mustUpdateOptions = true
          refresh
        end
      end

      refresh if self.active && ((Graphics.frame_count rescue 0) % 4 == 0)
    end

    def drawCursor(index, rect)
      if self.index == index
        fill_base = reloaded_options_cursor_fill
        border_base = reloaded_options_cursor_border
        pulse = Math.sin((Graphics.frame_count rescue 0) * Math::PI / 20.0) * 0.5 + 0.5
        fill_alpha = [[fill_base.alpha.to_i - 35 + (pulse * 45).to_i, 220].min, 70].max
        border_alpha = [[border_base.alpha.to_i - 20 + (pulse * 30).to_i, 245].min, 110].max
        fill = reloaded_with_alpha(fill_base, fill_alpha)
        border = reloaded_with_alpha(border_base, border_alpha)
        reloaded_draw_rounded_rect(self.contents, rect.x + 4, rect.y - 1,
          rect.width - 8, rect.height - 4, 4, fill, border)
      end
      Rect.new(rect.x + 16, rect.y, rect.width - 16, rect.height)
    end

    def drawItem(index, count, rect)
      return if dont_draw_item(index)
      if index == @options.length
        rect = drawCursor(index, rect)
        pbDrawShadowText(self.contents, rect.x, rect.y, rect.width, rect.height,
                         _INTL("Confirm"), Color.new(248, 248, 248), Color.new(72, 80, 88))
        return
      end
      return if index > @options.length
      option = @options[index]
      return unless option

      case option
      when HiddenOption, Spacer
        return
      when CollapsibleHeader
        draw_collapsible_header(option, index, rect)
      when CategoryHeader
        draw_category_header(option, index, rect)
      when TextDisplayOption
        draw_text_display(option, index, rect)
      when ActionButton
        draw_action_button(option, index, rect)
      when EnumOption
        draw_enum(option, index, rect)
      when NumberOption
        draw_number(option, index, rect)
      when SliderOption
        draw_slider(option, index, rect)
      else
        super(index, count, rect)
      end
    end

    private

    def move_off_non_interactive(old_index)
      return unless self.active && self.index < @options.length
      option = @options[self.index]
      return unless option.respond_to?(:non_interactive?) && option.non_interactive?
      direction = self.index >= old_index ? 1 : -1
      direction = 1 if direction == 0
      candidate = self.index
      @options.length.times do
        candidate += direction
        break if candidate < 0 || candidate >= @options.length
        next_option = @options[candidate]
        next if next_option.respond_to?(:non_interactive?) && next_option.non_interactive?
        self.index = candidate
        @selected_position = self[self.index]
        @mustUpdateDescription = true
        return
      end
    rescue
      nil
    end

    def label_width(rect)
      rect.width * LABEL_FRAC / ROW_FRAC
    end

    def option_display_value(option, index)
      return self[index] unless option.respond_to?(:current_value)
      value = option.current_value rescue self[index]
      setValueNoRefresh(index, value) if value
      value
    end

    def category_colors
      Reloaded::Options.theme_text_colors(($PokemonSystem.reloaded_category_theme rescue 0))
    end

    def draw_centered_label(label, index, rect, base, shadow)
      rect = drawCursor(index, rect)
      text_width = self.contents.text_size(label).width rescue rect.width
      x = rect.x + [(rect.width - text_width) / 2, 0].max
      pbDrawShadowText(self.contents, x, rect.y, rect.width, rect.height, label, base, shadow)
    end

    def draw_category_header(option, index, rect)
      base, shadow = category_colors
      draw_centered_label(option.format(0), index, rect, base, shadow)
    end

    def draw_collapsible_header(option, index, rect)
      base, shadow = category_colors
      draw_centered_label(option.display_name, index, rect, base, shadow)
    end

    def draw_text_display(option, index, rect)
      rect = drawCursor(index, rect)
      label_w = label_width(rect)
      pbDrawShadowText(self.contents, rect.x, rect.y, label_w, rect.height,
                       option.name, @nameBaseColor, @nameShadowColor)
      pbDrawShadowText(self.contents, rect.x + label_w, rect.y, rect.width - label_w, rect.height,
                       option.current_text, self.baseColor, self.shadowColor)
    end

    def draw_action_button(option, index, rect)
      draw_centered_label("[ #{option.name} ]", index, rect, @selBaseColor, @selShadowColor)
    end

    def draw_number(option, index, rect)
      rect = drawCursor(index, rect)
      label_w = label_width(rect)
      pbDrawShadowText(self.contents, rect.x, rect.y, label_w, rect.height,
                       option.name, @nameBaseColor, @nameShadowColor)
      if option.respond_to?(:locked?) && option.locked?
        draw_cycling_value(option.locked_label.to_s, true, true, rect, label_w)
        return
      end
      value = option.optstart + (option_display_value(option, index) || 0).to_i
      total = option.optend - option.optstart + 1
      draw_cycling_value("#{value}/#{total}", value <= option.optstart, value >= option.optend, rect, label_w)
    end

    def draw_enum(option, index, rect)
      rect = drawCursor(index, rect)
      label_w = label_width(rect)
      if disabled_option?(option)
        draw_disabled_option(option, rect, label_w)
        return
      end
      pbDrawShadowText(self.contents, rect.x, rect.y, label_w, rect.height,
                       option.name, @nameBaseColor, @nameShadowColor)
      return if option.values.nil? || option.values.empty?
      current = [[(option_display_value(option, index) || 0).to_i, 0].max, option.values.length - 1].min
      draw_cycling_value(option.values[current].to_s, current <= 0, current >= option.values.length - 1, rect, label_w)
    end

    def draw_cycling_value(value, at_min, at_max, rect, label_w)
      area_x = rect.x + label_w
      area_w = rect.width - label_w
      arrow_w = self.contents.text_size("<").width
      value_w = self.contents.text_size(value).width
      gap = 6
      display_w = arrow_w + gap + value_w + gap + arrow_w
      start_x = area_x + [(area_w - display_w) / 2, 0].max
      pbDrawShadowText(self.contents, start_x, rect.y, arrow_w + gap, rect.height,
                       "<", @selBaseColor, @selShadowColor) unless at_min
      pbDrawShadowText(self.contents, start_x + arrow_w + gap, rect.y, value_w + 4, rect.height,
                       value, @selBaseColor, @selShadowColor)
      pbDrawShadowText(self.contents, start_x + arrow_w + gap + value_w + gap, rect.y, arrow_w + 4, rect.height,
                       ">", @selBaseColor, @selShadowColor) unless at_max
    end

    def draw_slider(option, index, rect)
      rect = drawCursor(index, rect)
      label_w = label_width(rect)
      if disabled_option?(option)
        draw_disabled_option(option, rect, label_w)
        return
      end
      pbDrawShadowText(self.contents, rect.x, rect.y, label_w, rect.height,
                       option.name, @nameBaseColor, @nameShadowColor)
      actual = (option_display_value(option, index) || 0).to_f
      min_v = option.optstart.to_f
      max_v = option.optend.to_f
      range = max_v - min_v
      range = 1.0 if range == 0.0
      pct = [[(actual - min_v) / range, 0.0].max, 1.0].min
      widest_abs = [min_v.abs, max_v.abs].max.to_i
      widest_text = min_v < 0 ? "-#{widest_abs}" : widest_abs.to_s
      value_w = self.contents.text_size(widest_text).width + 4
      area_x = rect.x + label_w
      bar_len = [(rect.width - label_w) - value_w - 14, 60].max
      bar_y = rect.y - 2 + rect.height / 2
      slider_base, slider_shadow = Reloaded::Options.readable_text_colors
      self.contents.fill_rect(area_x, bar_y, bar_len, 4, slider_base)
      tick_x = area_x + ((bar_len - 8) * pct).round
      self.contents.fill_rect(tick_x, rect.y - 8 + rect.height / 2, 8, 16, slider_base)
      pbDrawShadowText(self.contents, area_x + bar_len + 6, rect.y, value_w + 4, rect.height,
                       actual.to_i.to_s, @selBaseColor, @selShadowColor)
    end

    def disabled_option?(option)
      option.respond_to?(:disabled?) && option.disabled?
    rescue
      false
    end

    def draw_disabled_option(option, rect, label_w)
      base = reloaded_with_alpha(@nameBaseColor, 115)
      value_base = reloaded_with_alpha(@selBaseColor, 115)
      shadow = Color.new(0, 0, 0, 0)
      pbDrawShadowText(self.contents, rect.x, rect.y, label_w, rect.height,
                       option.name, base, shadow)
      value = option.respond_to?(:disabled_label) ? option.disabled_label.to_s : _INTL("Disabled")
      area_x = rect.x + label_w
      area_w = rect.width - label_w
      value_w = self.contents.text_size(value).width rescue area_w
      value_x = area_x + [(area_w - value_w) / 2, 0].max
      pbDrawShadowText(self.contents, value_x, rect.y, value_w + 4, rect.height,
                       value, value_base, shadow)
    end
  end
end

if defined?(PokemonOption_Scene)
  class PokemonOption_Scene
    unless method_defined?(:reloaded_options_initOptionsWindow)
      alias_method :reloaded_options_initOptionsWindow, :initOptionsWindow
      def initOptionsWindow
        width = Graphics.width
        reloaded_options_center_title
        height = Graphics.height - @sprites["title"].height - @sprites["textbox"].height
        pbSetSystemFont(@sprites["textbox"].contents) if @sprites["textbox"]
        window = Window_ReloadedOption.new(@PokemonOptions, 0, @sprites["title"].height, width, height)
        window.viewport = @viewport
        window.visible = true
        window
      end
    end

    unless method_defined?(:reloaded_options_updateDescription)
      alias_method :reloaded_options_updateDescription, :updateDescription
      def updateDescription(index)
        index ||= 0
        row_changed = (@reloaded_desc_index != index)
        @reloaded_desc_index = index
        if row_changed
          @reloaded_desc_frame = 0
          @reloaded_desc_line = 0
        end
        begin
          horizontal_position = @sprites["option"].selected_position rescue 0
          description = @PokemonOptions[index].description
          description = description[horizontal_position] if description.is_a?(Array)
          description = getDefaultDescription if !description || description == ""
          lines = description.to_s.split("\n")
          @sprites["textbox"].text = lines.length > 2 ? lines[0, 2].join("\n") : description.to_s if row_changed
        rescue
          @sprites["textbox"].text = getDefaultDescription if row_changed
        end
      end
    end

    unless method_defined?(:reloaded_options_pbUpdate)
      alias_method :reloaded_options_pbUpdate, :pbUpdate
      def pbUpdate
        pbUpdateSpriteHash(@sprites)
        reloaded_options_center_title
        if @sprites["option"].mustUpdateDescription
          updateDescription(@sprites["option"].index)
          @sprites["option"].descriptionUpdated
        else
          reloaded_tick_description_scroll
        end
      end
    end

    unless method_defined?(:reloaded_options_pbEndScene)
      alias_method :reloaded_options_pbEndScene, :pbEndScene
      def pbEndScene
        reloaded_options_pbEndScene
        Reloaded::Options.apply_speech_frame if defined?(Reloaded::Options) && Reloaded::Options.speech_follows_menu?
      end
    end

    def reloaded_options_center_title
      title = @sprites["title"] rescue nil
      return unless title && title.respond_to?(:contents) && title.contents
      title.text = "" if title.respond_to?(:text=)
      bitmap = title.contents
      bitmap.clear
      pbSetSystemFont(bitmap)
      base, _shadow = Reloaded::Options.readable_text_colors rescue [Color.new(255, 255, 255), Color.new(0, 0, 0, 0)]
      pbDrawTextPositions(bitmap, [[_INTL("Options"), bitmap.width / 2, 2, 2, base, Color.new(0, 0, 0, 0)]])
    rescue
    end

    def reloaded_tick_description_scroll
      return unless @sprites["textbox"] && @sprites["option"] && @PokemonOptions
      index = @sprites["option"].index rescue nil
      return unless index
      description = @PokemonOptions[index].description rescue nil
      return unless description.is_a?(String)
      lines = description.split("\n")
      return if lines.length <= 2
      @reloaded_desc_index ||= index
      @reloaded_desc_frame ||= 0
      @reloaded_desc_line ||= 0
      if @reloaded_desc_index != index
        @reloaded_desc_index = index
        @reloaded_desc_frame = 0
        @reloaded_desc_line = 0
      end
      @reloaded_desc_frame += 1
      pause_top = 120
      pause_bottom = 120
      per_line = 90
      max_line = lines.length - 2
      cycle = pause_top + max_line * per_line + pause_bottom
      position = @reloaded_desc_frame % cycle
      new_line = if position < pause_top
                   0
                 elsif position >= pause_top + max_line * per_line
                   max_line
                 else
                   ((position - pause_top) / per_line).to_i
                 end
      return if new_line == @reloaded_desc_line
      @reloaded_desc_line = new_line
      @sprites["textbox"].text = lines[new_line, 2].join("\n")
    end
  end
end

Reloaded::Options.install if defined?(Reloaded::Options)

