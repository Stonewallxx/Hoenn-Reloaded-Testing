#======================================================
# Reloaded Developer Time Changer
# Author: Stonewall
#======================================================
# Adds a removable Developer option for quickly changing in-game time.
#
# Responsibilities:
#   - Register a Developer category time selector through Reloaded::Options.
#   - Register a Developer test battle action for the Example Mod trainer patch.
#   - Jump the game clock to common time-of-day test points.
#   - Refresh day/night tone after changing time.
#   - Keep the feature isolated so it can be removed by deleting this file.
#
#======================================================

module Reloaded
  module DeveloperTimeChanger
    OPTIONS = [
      { :name => "Morning",   :hour => 6,  :minute => 0 },
      { :name => "Day",       :hour => 12, :minute => 0 },
      { :name => "Afternoon", :hour => 14, :minute => 0 },
      { :name => "Evening",   :hour => 18, :minute => 0 },
      { :name => "Night",     :hour => 22, :minute => 0 }
    ].freeze

    class << self
      def register_option
        return false unless defined?(Reloaded::Options) && Reloaded::Options.respond_to?(:register_category_option)
        Reloaded::Options.register_category_option("DEVELOPER", :developer_time_changer, priority: 60) do |_scene|
          option
        end
        Reloaded::Options.register_category_option("DEVELOPER", :example_trainer_battle, priority: 70) do |_scene|
          test_trainer_option
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to register Developer test options", e, channel: :options) if defined?(Reloaded::Log)
        false
      end

      def option
        return nil unless defined?(EnumOption)
        EnumOption.new(
          _INTL("Time Changer"),
          OPTIONS.map { |entry| _INTL(entry[:name]) },
          proc { current_index },
          proc { |value| set_time(value) },
          _INTL("Quickly changes the in-game time for testing time-based systems.")
        )
      end

      def test_trainer_option
        return nil unless defined?(ActionButton)
        ActionButton.new(
          _INTL("Test Reloaded Trainer"),
          proc { start_test_trainer_battle },
          _INTL("Starts a test battle against the Example Mod trainer patch.")
        )
      end

      def start_test_trainer_battle
        unless trainer_available?
          pbMessage(_INTL("Reloaded Example trainer is not loaded.")) rescue nil
          return false
        end
        Reloaded::Log.info("Starting Reloaded Example trainer test battle", :options) if defined?(Reloaded::Log)
        pbTrainerBattle(:YOUNGSTER, "Reloaded Example", nil, false, 0, true)
      rescue Exception => e
        Reloaded::Log.exception("Reloaded Example trainer test battle failed", e, channel: :options) if defined?(Reloaded::Log)
        pbMessage(_INTL("Could not start Reloaded Example trainer battle.")) rescue nil
        false
      end

      def current_index
        now = pbGetTimeNow rescue Time.now
        hour = now.hour.to_i
        return index_for(:night) if hour >= 20 || hour < 5
        return index_for(:morning) if hour >= 5 && hour < 10
        return index_for(:afternoon) if hour >= 14 && hour < 17
        return index_for(:evening) if hour >= 17 && hour < 20
        index_for(:day)
      rescue
        index_for(:day)
      end

      def set_time(value)
        index = clamp_index(value)
        return current_index if index == current_index
        entry = OPTIONS[index]
        return current_index unless entry
        set_clock_to(entry)
        refresh_after_change
        log_time_change(entry)
        current_index
      rescue Exception => e
        Reloaded::Log.exception("Developer Time Changer failed", e, channel: :options) if defined?(Reloaded::Log)
        current_index
      end

      private

      def trainer_available?
        return false unless defined?(GameData::Trainer)
        GameData::Trainer.exists?(:YOUNGSTER, "Reloaded Example", 0)
      rescue
        false
      end

      def clamp_index(value)
        [[value.to_i, 0].max, OPTIONS.length - 1].min
      end

      def index_for(name)
        OPTIONS.index { |entry| entry[:name].downcase.to_sym == name } || 0
      end

      def set_clock_to(entry)
        return set_clock_with_unreal_time(entry) if defined?(UnrealTime) && $PokemonGlobal
        Reloaded::Log.warning("UnrealTime is unavailable; Time Changer could not change time", :options) if defined?(Reloaded::Log)
      end

      def set_clock_with_unreal_time(entry)
        now = pbGetTimeNow
        current_seconds = now.hour.to_i * 3600 + now.min.to_i * 60 + now.sec.to_i
        target_seconds = entry[:hour].to_i * 3600 + entry[:minute].to_i * 60
        seconds_to_add = target_seconds - current_seconds
        seconds_to_add += 86_400 if seconds_to_add < 0
        frame_rate = defined?(Graphics) && Graphics.respond_to?(:frame_rate) ? Graphics.frame_rate.to_f : 60.0
        proportion = UnrealTime.respond_to?(:proportion) ? UnrealTime.proportion.to_f : UnrealTime::PROPORTION.to_f
        proportion = 1.0 if proportion <= 0.0
        frames_to_add = (seconds_to_add.to_f * frame_rate / proportion).round
        $PokemonGlobal.newFrameCount ||= 0
        $PokemonGlobal.newFrameCount += frames_to_add
      end

      def refresh_after_change
        PBDayNight.sheduleToneRefresh if defined?(PBDayNight) && PBDayNight.respond_to?(:sheduleToneRefresh)
        $game_map.need_refresh = true if defined?($game_map) && $game_map && $game_map.respond_to?(:need_refresh=)
        $PokemonEncounters.setup($game_map.map_id) if defined?($PokemonEncounters) && $PokemonEncounters && defined?($game_map) && $game_map && $game_map.respond_to?(:map_id)
      rescue Exception => e
        Reloaded::Log.exception("Developer Time Changer refresh failed", e, channel: :options) if defined?(Reloaded::Log)
      end

      def log_time_change(entry)
        return unless defined?(Reloaded::Log)
        now = pbGetTimeNow rescue nil
        actual = now ? now.strftime("%H:%M") : format("%02d:%02d", entry[:hour], entry[:minute])
        Reloaded::Log.info("Developer Time Changer set time to #{entry[:name]} (#{actual})", :options)
      end
    end
  end
end

Reloaded::DeveloperTimeChanger.register_option if defined?(Reloaded::DeveloperTimeChanger)
