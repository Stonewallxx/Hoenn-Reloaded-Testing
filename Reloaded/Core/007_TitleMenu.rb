#======================================================
# Reloaded Title Menu
# Author: Stonewall
#======================================================
# Adds Reloaded title-screen entries to the base load menu.
#
# Responsibilities:
#   - Add Mod Manager to the title menu above Options.
#   - Open the in-game Reloaded Mod Manager from the title screen.
#   - Register the title menu replacement with the Reloaded patch logger.
#
#======================================================

module Reloaded
  module TitleMenu
    MOD_MANAGER_LABEL = "Mod Manager".freeze

    class << self
      def open_mod_manager
        if defined?(Reloaded::ModManagerUI)
          Reloaded::Log.info("Opening Mod Manager from title menu", :mods) if defined?(Reloaded::Log)
          Reloaded::ModManagerUI.open
        else
          pbMessage("Mod Manager is not available.") rescue nil
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to open title Mod Manager", e, channel: :mods) if defined?(Reloaded::Log)
        pbMessage("Mod Manager failed to open.") rescue nil
      end
    end
  end
end

if defined?(PokemonLoadScreen)
  class PokemonLoadScreen
    def pbStartLoadScreen
      updateHttpSettingsFile
      updateCustomDexFile
      newer_version = find_newer_available_version
      if newer_version
        pbMessage(_INTL("Version {1} is now available! Please use the game's installer to download the newest version. Check the Discord for more information.", newer_version))
      end

      if Settings::STARTUP_MESSAGES_KANTO != "" && Settings::KANTO
        pbMessage(_INTL(Settings::STARTUP_MESSAGES_KANTO))
      end
      if Settings::STARTUP_MESSAGES_HOENN != "" && Settings::HOENN
        pbMessage(_INTL(Settings::STARTUP_MESSAGES_HOENN))
      end

      if $game_temp.unimportedSprites && $game_temp.unimportedSprites.size > 0
        handleReplaceExistingSprites()
      end
      if $game_temp.nb_imported_sprites && $game_temp.nb_imported_sprites > 0
        pbMessage(_INTL("{1} new custom sprites were imported into the game", $game_temp.nb_imported_sprites.to_s))
      end
      checkEnableSpritesDownload

      $game_temp.nb_imported_sprites = nil
      copyKeybindings()
      save_file_list = SaveData::AUTO_SLOTS + SaveData::MANUAL_SLOTS
      first_time = true
      loop do
        if @selected_file
          @save_data = load_save_file(SaveData.get_full_path(@selected_file))
        else
          @save_data = {}
        end

      commands = []
      cmd_continue     = -1
      cmd_new_game     = -1
      cmd_options      = -1
      cmd_mod_manager  = -1
      cmd_language     = -1
      cmd_mystery_gift = -1
      cmd_debug        = -1
      cmd_quit         = -1
      show_continue = !@save_data.empty?
      new_game_plus = show_continue && (@save_data[:player].new_game_plus_unlocked || $DEBUG)

      if show_continue
        commands[cmd_continue = commands.length] = "#{@selected_file}"
        commands[cmd_mystery_gift = commands.length] = _INTL("Mystery Gift")
      end

      commands[cmd_new_game = commands.length] = _INTL("New Game")
      if new_game_plus
        commands[cmd_new_game_plus = commands.length] = _INTL("New Game +")
      end
      commands[cmd_mod_manager = commands.length] = _INTL(Reloaded::TitleMenu::MOD_MANAGER_LABEL)
      commands[cmd_options = commands.length] = _INTL("Options")
      commands[cmd_language = commands.length] = _INTL("Language") if Settings::LANGUAGES[Settings::GAME_ID].length >= 2

      cmd_links = {}

      if Settings::HOENN && new_game_plus && !Settings::FEEDBACK_FORM_URL.empty?
        cmd_links[commands.length] = Settings::FEEDBACK_FORM_URL
        commands[commands.length] = _INTL("Game Feedback Form")
      end

      Settings::MAIN_MENU_LINKS.each do |key, value|
        cmd_links[commands.length] = value
        commands[commands.length] = _INTL(key)
      end

      commands[cmd_savefile = commands.length] = _INTL("Savefile management") if show_continue
      commands[cmd_debug = commands.length] = _INTL("Debug") if $DEBUG
      commands[cmd_quit = commands.length] = _INTL("Quit Game")
      cmd_left = -3
      cmd_right = -2

      map_id = show_continue ? @save_data[:map_factory].map.map_id : 0
      @scene.pbStartScene(commands, show_continue, @save_data[:player],
                          @save_data[:frame_count] || 0, map_id)
      @scene.pbSetParty(@save_data[:player]) if show_continue
      if first_time
        @scene.pbStartScene2
        pbBGMPlay("pokemon_go_map") if Settings::HOENN
        first_time = false
      else
        @scene.pbUpdate
      end
      loop do
        command = @scene.pbChoose(commands, cmd_continue)
        pbPlayDecisionSE if command != cmd_quit

        case command
        when cmd_continue
          @scene.pbEndScene
          Game.load(@save_data)
          $game_switches[SWITCH_V5_1] = true
          check_for_spritepack_update()
          ensureCorrectDifficulty()
          setGameMode()
          initialize_alt_sprite_substitutions()
          $PokemonGlobal.autogen_sprites_cache = {}
          preload_party(@save_data[:player])
          return
        when cmd_new_game
          @scene.pbEndScene
          Game.start_new(new_game_plus)
          initialize_alt_sprite_substitutions()
          @save_data[:player].new_game_plus_unlocked = new_game_plus if @save_data[:player]
          return
        when cmd_new_game_plus
          @scene.pbEndScene
          Game.start_new(true, @save_data[:bag], @save_data[:storage_system], @save_data[:player])
          initialize_alt_sprite_substitutions()
          @save_data[:player].new_game_plus_unlocked = true
          return
        when cmd_mystery_gift
          pbFadeOutIn { pbDownloadMysteryGift(@save_data[:player]) }
        when cmd_mod_manager
          pbFadeOutIn { Reloaded::TitleMenu.open_mod_manager }
        when cmd_options
          pbFadeOutIn do
            scene = PokemonGameOption_Scene.new
            screen = PokemonOptionScreen.new(scene)
            screen.pbStartScreen(true)
          end
        when cmd_language
          @scene.pbEndScene
          $PokemonSystem.language = pbChooseLanguage
          MessageConfig.pbResetSystemFontName
          pbLoadMessages('Data/' + Settings::LANGUAGES[Settings::GAME_ID][$PokemonSystem.language][1])
          if show_continue
            @save_data[:pokemon_system] = $PokemonSystem
            File.open(SaveData.get_full_path(@selected_file), 'wb') { |file| Marshal.dump(@save_data, file) }
          end
          $scene = pbCallTitle
          return
        when cmd_savefile
          save_data_to_load = savefileOptions(SaveData.get_full_path(@selected_file))
          if save_data_to_load
            @scene.pbEndScene
            Game.load(save_data_to_load)
            return
          end
        when cmd_debug
          pbFadeOutIn { pbDebugMenu(false) }
        when cmd_quit
          pbPlayCloseMenuSE
          @scene.pbEndScene
          $scene = nil
          return
        when cmd_left
          @scene.pbCloseScene
          @selected_file = SaveData.get_prev_slot(save_file_list, @selected_file)
          break
        when cmd_right
          @scene.pbCloseScene
          @selected_file = SaveData.get_next_slot(save_file_list, @selected_file)
          break
        else
          if cmd_links.key?(command)
            openUrlInBrowser(cmd_links[command])
          else
            pbPlayBuzzerSE
          end
        end
      end
      end
    end
  end

  Reloaded::Patches.register(
    :title_menu_mod_manager,
    target: "PokemonLoadScreen#pbStartLoadScreen",
    type: :replace,
    file: "Reloaded/Core/007_TitleMenu.rb",
    reason: "Adds Mod Manager above Options in the title menu while preserving title command indexes.",
    recommended_fix: "Recompare with base PokemonLoadScreen#pbStartLoadScreen after title menu updates."
  ) if defined?(Reloaded::Patches)
end
