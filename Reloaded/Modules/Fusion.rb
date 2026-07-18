#======================================================
# Reloaded Fusion
# Author: Stonewall
#======================================================
# Shared fusion helpers for Reloaded systems.
#
# Responsibilities:
#   - Provide a configurable fusion type list for future fusion systems.
#   - Report the current fusion type label for UI surfaces.
#   - Keep current fusions classified as Splicer until new systems exist.
#
#======================================================

module ReloadedFusion
  NON_FUSION_LABEL = "N/A"
  DEFAULT_FUSION_TYPE = :splicer

  FUSION_TYPES = {
    :splicer => {
      :label => "Splicer"
    }
  }.freeze

  class << self
    def fusion?(pokemon)
      return false unless pokemon
      return pokemon.isFusion? if pokemon.respond_to?(:isFusion?)
      species_data = pokemon.species_data if pokemon.respond_to?(:species_data)
      return species_data.is_fusion if species_data && species_data.respond_to?(:is_fusion)
      false
    rescue
      false
    end

    def fusion_type_id(pokemon)
      return nil unless fusion?(pokemon)
      stored = stored_fusion_type(pokemon)
      return stored if stored && FUSION_TYPES[stored]
      DEFAULT_FUSION_TYPE
    rescue
      DEFAULT_FUSION_TYPE
    end

    def fusion_type_label(pokemon)
      type_id = fusion_type_id(pokemon)
      return NON_FUSION_LABEL unless type_id
      type_data = FUSION_TYPES[type_id] || FUSION_TYPES[DEFAULT_FUSION_TYPE]
      type_data[:label].to_s
    rescue
      NON_FUSION_LABEL
    end

    def set_fusion_type(pokemon, type_id)
      return false unless pokemon
      normalized = normalize_type_id(type_id)
      return false unless FUSION_TYPES[normalized]
      pokemon.instance_variable_set(:@reloaded_fusion_type, normalized)
      true
    rescue
      false
    end

    def stored_fusion_type(pokemon)
      value = pokemon.reloaded_fusion_type if pokemon.respond_to?(:reloaded_fusion_type)
      value = pokemon.instance_variable_get(:@reloaded_fusion_type) if !value && pokemon.instance_variable_defined?(:@reloaded_fusion_type)
      normalize_type_id(value)
    rescue
      nil
    end

    def normalize_type_id(type_id)
      return nil if type_id.nil?
      type_id.to_s.strip.downcase.to_sym
    rescue
      nil
    end
  end
end

if defined?(Pokemon)
  class Pokemon
    attr_accessor :reloaded_fusion_type unless method_defined?(:reloaded_fusion_type)
  end
end

Reloaded::Log.info("Installed Reloaded Fusion helpers", :modules) if defined?(Reloaded::Log)

if defined?(PokemonFusionScene) && PokemonFusionScene.method_defined?(:pbFusionScreen) &&
   !PokemonFusionScene.method_defined?(:reloaded_distribution_original_pbFusionScreen)
  PokemonFusionScene.class_eval do
    alias_method :reloaded_distribution_original_pbFusionScreen, :pbFusionScreen

    def pbFusionScreen(*args)
      body_locked = defined?(Reloaded::PokemonDistribution) && !Reloaded::PokemonDistribution.tradeable?(@pokemon1)
      head_locked = defined?(Reloaded::PokemonDistribution) && !Reloaded::PokemonDistribution.tradeable?(@pokemon2)
      body_reason = @pokemon1.reloaded_trade_lock_reason.to_s if body_locked && @pokemon1.respond_to?(:reloaded_trade_lock_reason)
      head_reason = @pokemon2.reloaded_trade_lock_reason.to_s if head_locked && @pokemon2.respond_to?(:reloaded_trade_lock_reason)
      head_types = Array(@pokemon2.reloaded_reward_types).compact if @pokemon2 && @pokemon2.respond_to?(:reloaded_reward_types)
      head_policy = @pokemon2.reloaded_custom_type_policy if @pokemon2 && @pokemon2.respond_to?(:reloaded_custom_type_policy)
      result = reloaded_distribution_original_pbFusionScreen(*args)
      if @pokemon1 && (body_locked || head_locked)
        @pokemon1.reloaded_untradeable = true if @pokemon1.respond_to?(:reloaded_untradeable=)
        reason = body_reason.to_s.empty? ? head_reason : body_reason
        @pokemon1.reloaded_trade_lock_reason = reason if @pokemon1.respond_to?(:reloaded_trade_lock_reason=)
      end
      if @pokemon1 && Array(@pokemon1.reloaded_reward_types).empty? && !head_types.to_a.empty? &&
         head_policy.is_a?(Hash) && head_policy[:fusion] == :preserve
        @pokemon1.reloaded_reward_types = head_types.dup
        @pokemon1.reloaded_custom_type_policy = head_policy.dup if @pokemon1.respond_to?(:reloaded_custom_type_policy=)
      end
      result
    end
  end
end
