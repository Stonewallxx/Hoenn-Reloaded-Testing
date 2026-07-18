#======================================================
# Reloaded Hidden Power
# Author: Stonewall
#======================================================
# Randomizes Hidden Power type per generated Pokemon.
#
# Responsibilities:
#   - Assign new Pokemon a stored Hidden Power type.
#   - Keep the type pool aligned with the base Hidden Power type list.
#   - Backfill older Pokemon when Hidden Power is checked.
#   - Leave Hidden Power power calculation to the base game.
#
#======================================================

module ReloadedHiddenPower
  EXCLUDED_TYPES = [:NORMAL, :SHADOW].freeze
  HIDDEN_POWER_TYPES = [
    :FIGHTING,
    :FLYING,
    :POISON,
    :GROUND,
    :ROCK,
    :BUG,
    :GHOST,
    :STEEL,
    :FIRE,
    :WATER,
    :GRASS,
    :ELECTRIC,
    :PSYCHIC,
    :ICE,
    :DRAGON,
    :DARK,
    :FAIRY
  ].freeze

  class << self
    def type_pool
      configured_pool = []
      HIDDEN_POWER_TYPES.each do |type_id|
        next unless GameData::Type.exists?(type_id)
        type_data = GameData::Type.get(type_id)
        next if type_data.pseudo_type
        next if EXCLUDED_TYPES.include?(type_data.id)
        configured_pool << type_data.id
      end
      return configured_pool if !configured_pool.empty?
      fallback_type_pool
    rescue
      []
    end

    def fallback_type_pool
      pool = []
      GameData::Type.each do |type_data|
        next if type_data.pseudo_type
        next if EXCLUDED_TYPES.include?(type_data.id)
        pool << type_data.id
      end
      pool.sort { |a, b| GameData::Type.get(a).id_number <=> GameData::Type.get(b).id_number }
    rescue
      []
    end

    def random_type
      pool = type_pool
      return nil if pool.empty?
      pool[rand(pool.length)]
    end

    def ensure_type(pokemon)
      target = stored_type_target(pokemon)
      return nil unless target
      current = target.hiddenPowerType rescue nil
      return current if current
      chosen = random_type
      target.hiddenPower = chosen if chosen && target.respond_to?(:hiddenPower=)
      chosen
    rescue
      nil
    end

    def stored_type_target(value)
      return nil unless value
      return value if value.respond_to?(:hiddenPowerType)
      battler_pokemon = value.pokemon if value.respond_to?(:pokemon)
      return battler_pokemon if battler_pokemon && battler_pokemon.respond_to?(:hiddenPowerType)
      nil
    rescue
      nil
    end
  end
end

if defined?(Pokemon)
  class Pokemon
    unless method_defined?(:reloaded_hidden_power_initialize)
      alias_method :reloaded_hidden_power_initialize, :initialize

      def initialize(species, level, owner = $Trainer, withMoves = true, recheck_form = true)
        reloaded_hidden_power_initialize(species, level, owner, withMoves, recheck_form)
        ReloadedHiddenPower.ensure_type(self)
      end
    end
  end
end

if Object.private_method_defined?(:pbHiddenPower) || Object.method_defined?(:pbHiddenPower)
  class Object
    unless private_method_defined?(:reloaded_hidden_power_pbHiddenPower) || method_defined?(:reloaded_hidden_power_pbHiddenPower)
      alias_method :reloaded_hidden_power_pbHiddenPower, :pbHiddenPower

      def pbHiddenPower(pkmn, forcedType = nil)
        forcedType ||= ReloadedHiddenPower.ensure_type(pkmn)
        reloaded_hidden_power_pbHiddenPower(pkmn, forcedType)
      end

      private :pbHiddenPower
    end
  end
end

Reloaded::Log.info("Installed Reloaded Hidden Power random type assignment", :modules) if defined?(Reloaded::Log)
