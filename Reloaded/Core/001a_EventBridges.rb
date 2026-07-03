#======================================================
# Reloaded Event Bridges
# Author: Stonewall
#======================================================
# Runtime bridge points from common base-game methods into Reloaded::Events.
#
# Responsibilities:
#   - Emit Reloaded events around common modding targets.
#   - Keep base-game method wrapping isolated from the generic event registry.
#   - Provide notification-only bridge points that do not alter vanilla results.
#   - Register bridge patch metadata with Reloaded::Patches.
#
#======================================================

module Reloaded
  module EventBridges
    GLOBAL_METHOD_BRIDGES = [
      {
        :method => :pbReceiveItem,
        :before => :item_receive_started,
        :after => :item_received,
        :result_key => :received
      },
      {
        :method => :pbReceiveMoney,
        :before => :money_change_started,
        :after => :money_changed,
        :result_key => :result
      },
      {
        :method => :pbWildBattle,
        :before => :wild_battle_requested,
        :after => :wild_battle_finished,
        :result_key => :player_won
      },
      {
        :method => :pbTrainerBattle,
        :before => :trainer_battle_requested,
        :after => :trainer_battle_finished,
        :result_key => :player_won
      }
    ].freeze

    class << self
      def install
        install_global_method_bridges
        install_battle_lifecycle_bridge
        install_map_bridge
        register_patch_point
        Reloaded::Log.info("Installed Reloaded event bridge points", :events) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Reloaded event bridge install failed", e, channel: :events) if defined?(Reloaded::Log)
        false
      end

      def emit(event_name, context = {})
        return 0 unless defined?(Reloaded::Events)
        Reloaded::Events.emit(event_name, context)
      rescue Exception => e
        Reloaded::Log.exception("Reloaded bridge event #{event_name} failed", e, channel: :events) if defined?(Reloaded::Log)
        0
      end

      private

      def install_global_method_bridges
        GLOBAL_METHOD_BRIDGES.each { |config| install_global_method_bridge(config) }
      end

      def install_global_method_bridge(config)
        method_name = config[:method]
        return false unless Object.private_method_defined?(method_name) || Object.method_defined?(method_name)
        alias_name = :"reloaded_event_bridge_#{method_name}"
        return true if Object.private_method_defined?(alias_name) || Object.method_defined?(alias_name)
        was_private = Object.private_method_defined?(method_name)

        Object.class_eval do
          alias_method alias_name, method_name
          define_method(method_name) do |*args, &block|
            if defined?(Reloaded::EventBridges)
              Reloaded::EventBridges.emit(config[:before], {
                :method => method_name,
                :args => args
              })
            end
            result = send(alias_name, *args, &block)
            if defined?(Reloaded::EventBridges)
              Reloaded::EventBridges.emit(config[:after], {
                :method => method_name,
                :args => args,
                config[:result_key] => result,
                :result => result
              })
            end
            result
          end
          private method_name if was_private
        end
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to install event bridge for #{method_name}", e, channel: :events) if defined?(Reloaded::Log)
        false
      end

      def install_battle_lifecycle_bridge
        return false unless defined?(PokeBattle_Battle)
        return true if PokeBattle_Battle.method_defined?(:reloaded_event_bridge_pbStartBattle)
        PokeBattle_Battle.class_eval do
          alias_method :reloaded_event_bridge_pbStartBattle, :pbStartBattle

          def pbStartBattle(*args, &block)
            Reloaded::EventBridges.emit(:battle_started, {
              :battle => self,
              :wild => wildBattle?,
              :trainer => trainerBattle?
            }) if defined?(Reloaded::EventBridges)
            reloaded_event_bridge_pbStartBattle(*args, &block)
          end
        end

        return true if PokeBattle_Battle.method_defined?(:reloaded_event_bridge_pbEndOfBattle)
        PokeBattle_Battle.class_eval do
          alias_method :reloaded_event_bridge_pbEndOfBattle, :pbEndOfBattle

          def pbEndOfBattle(*args, &block)
            result = reloaded_event_bridge_pbEndOfBattle(*args, &block)
            Reloaded::EventBridges.emit(:battle_ended, {
              :battle => self,
              :decision => (@decision rescue nil),
              :wild => wildBattle?,
              :trainer => trainerBattle?
            }) if defined?(Reloaded::EventBridges)
            result
          end
        end
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to install battle lifecycle event bridge", e, channel: :events) if defined?(Reloaded::Log)
        false
      end

      def install_map_bridge
        install_game_map_setup_bridge
        install_scene_map_transfer_bridge
      end

      def install_game_map_setup_bridge
        return false unless defined?(Game_Map)
        return true if Game_Map.method_defined?(:reloaded_event_bridge_setup)
        Game_Map.class_eval do
          alias_method :reloaded_event_bridge_setup, :setup

          def setup(map_id, *args, &block)
            old_map_id = (@map_id rescue nil)
            Reloaded::EventBridges.emit(:map_setup_started, {
              :map_id => map_id,
              :old_map_id => old_map_id,
              :game_map => self
            }) if defined?(Reloaded::EventBridges)
            result = reloaded_event_bridge_setup(map_id, *args, &block)
            Reloaded::EventBridges.emit(:map_setup_finished, {
              :map_id => @map_id,
              :old_map_id => old_map_id,
              :game_map => self
            }) if defined?(Reloaded::EventBridges)
            result
          end
        end
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to install map setup event bridge", e, channel: :events) if defined?(Reloaded::Log)
        false
      end

      def install_scene_map_transfer_bridge
        return false unless defined?(Scene_Map)
        return true if Scene_Map.method_defined?(:reloaded_event_bridge_transfer_player)
        Scene_Map.class_eval do
          alias_method :reloaded_event_bridge_transfer_player, :transfer_player

          def transfer_player(*args, &block)
            old_map_id = ($game_map.map_id rescue nil)
            new_map_id = ($game_temp.player_new_map_id rescue nil)
            Reloaded::EventBridges.emit(:player_transfer_started, {
              :old_map_id => old_map_id,
              :new_map_id => new_map_id,
              :x => ($game_temp.player_new_x rescue nil),
              :y => ($game_temp.player_new_y rescue nil),
              :direction => ($game_temp.player_new_direction rescue nil),
              :scene => self
            }) if defined?(Reloaded::EventBridges)
            result = reloaded_event_bridge_transfer_player(*args, &block)
            Reloaded::EventBridges.emit(:player_transfer_finished, {
              :old_map_id => old_map_id,
              :new_map_id => ($game_map.map_id rescue new_map_id),
              :x => ($game_player.x rescue nil),
              :y => ($game_player.y rescue nil),
              :direction => ($game_player.direction rescue nil),
              :scene => self
            }) if defined?(Reloaded::EventBridges)
            result
          end
        end
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to install player transfer event bridge", e, channel: :events) if defined?(Reloaded::Log)
        false
      end

      def register_patch_point
        return unless defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          :event_bridge_points,
          :target => "Common base-game gameplay methods",
          :type => :runtime_method_bridge,
          :file => __FILE__,
          :owner => :reloaded,
          :priority => 100,
          :reason => "Emits Reloaded::Events around common modding integration points.",
          :recommended_fix => "Review Reloaded::EventBridges if gameplay bridge events fail to emit.",
          :conflict_group => "event_bridges"
        )
      end
    end
  end
end

Reloaded::EventBridges.install if defined?(Reloaded::EventBridges)
