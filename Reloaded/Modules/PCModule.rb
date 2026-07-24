#======================================================
# Reloaded PC Module
# Author: Stonewall
#======================================================
# Pokemon Storage access module for the Reloaded Pause Menu.
#
# Responsibilities:
#   - Register the REPM PC module.
#   - Store the PC module OFF/ON setting through PokemonSystem.
#   - Restrict access on configured blocked map IDs.
#   - Open the existing Pokemon Storage screen without replacing PC behavior.
#
#======================================================

module Reloaded
  module PCModuleFeature
    class << self
      def install
        install_pokemon_system_settings
        register_option
        Reloaded::Log.info("Installed PC Module", :modules) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("PC Module install failed", e, channel: :modules) if defined?(Reloaded::Log)
        false
      end

      def install_pokemon_system_settings
        return unless defined?(PokemonSystem)
        PokemonSystem.class_eval do
          def hr_pc_module
            @hr_pc_module.nil? ? 1 : @hr_pc_module.to_i
          end

          def hr_pc_module=(value)
            @hr_pc_module = value.to_i
          end
        end
      end

      def register_option
        return unless defined?(Reloaded::Options) && Reloaded::Options.respond_to?(:register_category_option)
        Reloaded::Options.register_category_option("GAMEPLAY", :pc_module, priority: 10) do |_scene|
          [EnumOption.new(
            _INTL("PC Module"),
            [_INTL("Off"), _INTL("On")],
            proc { ReloadedPCModule.enabled? ? 1 : 0 },
            proc { |value| $PokemonSystem.hr_pc_module = value.to_i if $PokemonSystem },
            _INTL("Controls whether the REPM PC entry can open Pokemon Storage outside configured blocked maps.")
          )]
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to register PC Module option", e, channel: :options) if defined?(Reloaded::Log)
      end
    end
  end
end

Reloaded::PCModuleFeature.install if defined?(Reloaded::PCModuleFeature)

module ReloadedPCModule
  # Add map IDs here if REPM PC access should be blocked somewhere later.
  BLOCKED_MAP_IDS = [].freeze

  class << self
    def enabled?
      ($PokemonSystem.hr_pc_module rescue 1).to_i == 1
    end

    def current_map_id
      $game_map ? $game_map.map_id.to_i : 0
    rescue
      0
    end

    def blocked_map?
      BLOCKED_MAP_IDS.include?(current_map_id)
    end

    def storage_ready?
      defined?(PokemonStorageScene) &&
        defined?(PokemonStorageScreen) &&
        defined?($PokemonStorage) &&
        $PokemonStorage
    end

    def map_transfer_pending?
      return false unless $game_temp
      return true if $game_temp.respond_to?(:player_transferring) && $game_temp.player_transferring
      if $game_temp.respond_to?(:player_new_map_id)
        new_map_id = ($game_temp.player_new_map_id rescue 0).to_i
        return true if new_map_id > 0 && new_map_id != current_map_id
      end
      false
    rescue
      false
    end

    def event_or_transition_busy?
      return true if map_transfer_pending?
      return true if defined?(pbMapInterpreterRunning?) && pbMapInterpreterRunning?
      return true if $game_temp && ($game_temp.respond_to?(:message_window_showing) && $game_temp.message_window_showing)
      return true if $game_player && ($game_player.respond_to?(:move_route_forcing) && $game_player.move_route_forcing)
      false
    rescue
      true
    end

    def available?
      return false unless enabled?
      return false unless storage_ready?
      return false if blocked_map?
      return false if event_or_transition_busy?
      return false if $game_temp && ($game_temp.respond_to?(:menu_calling) && $game_temp.menu_calling)
      true
    rescue
      false
    end

    def lock_reason
      return _INTL("PC Module is turned off.") unless enabled?
      return _INTL("Pokemon Storage is not available yet.") unless storage_ready?
      return _INTL("The PC cannot be used on this map.") if blocked_map?
      return _INTL("The PC cannot be used right now.") if event_or_transition_busy?
      _INTL("The PC cannot be used right now.")
    rescue
      "The PC cannot be used right now."
    end

    def open
      unless available?
        pbMessage(lock_reason) rescue nil
        return
      end
      Reloaded::Log.info("Opening REPM PC storage from map #{current_map_id}", :modules) if defined?(Reloaded::Log)
      pbFadeOutIn do
        scene = PokemonStorageScene.new
        screen = PokemonStorageScreen.new(scene, $PokemonStorage)
        screen.pbStartScreen(0)
      end
      pbUpdateSceneMap rescue nil
    rescue Exception => e
      Reloaded::Log.exception("Failed to open REPM PC storage", e, channel: :modules) if defined?(Reloaded::Log)
      pbMessage(_INTL("The PC cannot be used right now.")) rescue nil
    end
  end
end

if defined?(ReloadedPauseMenu)
  ReloadedPauseMenu.register_module(
    :PC,
    label: "PC",
    handler: proc { ReloadedPCModule.open },
    icon: "Reloaded/Graphics/ReloadedMenu/PC",
    condition: proc { ReloadedPCModule.available? },
    lock_reason: proc { ReloadedPCModule.lock_reason }
  )
end
