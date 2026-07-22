#======================================================
# Reloaded Expanded Dex
# Author: Stonewall
#======================================================
# Loads the compact, generated Expanded Dex bundle after vanilla GameData.
#======================================================

module Reloaded
  module ExpandedDex
    FORMAT_VERSION = 1
    DATA_PATH = File.expand_path("../../Data/ExpandedDex/ExpandedDex.dat", __dir__).freeze

    @bundle = nil
    @installed = false
    @last_counts = nil

    class << self
      def install
        return true if @installed
        @bundle = load_bundle
        return false unless @bundle
        configure_species_limits
        register_events
        register_patch_point
        inject_all if game_data_ready?
        @installed = true
        true
      rescue Exception => e
        log_exception("Expanded Dex install failed", e)
        false
      end

      def available?
        !@bundle.nil?
      end

      def first_species_id
        (@bundle && @bundle[:first_expanded_id]).to_i
      end

      def max_species_id
        (@bundle && @bundle[:max_species_id]).to_i
      end

      def species_count
        Array(@bundle && @bundle[:species]).length
      end

      def inject_all
        return false unless @bundle && game_data_ready?
        counts = {
          :moves => inject_records(GameData::Move, @bundle[:moves], :move),
          :abilities => inject_records(GameData::Ability, @bundle[:abilities], :ability),
          :species => inject_species
        }
        counts[:triples] = rebase_triple_fusions
        @last_counts = counts
        log_once(
          "Loaded Expanded Dex: #{counts[:species]} species, " \
          "#{counts[:moves]} moves, #{counts[:abilities]} abilities",
          "expanded_dex_loaded:#{counts.values.join(':')}"
        )
        true
      rescue Exception => e
        log_exception("Expanded Dex injection failed", e)
        false
      end

      def last_counts
        @last_counts ? @last_counts.dup : nil
      end

      private

      def load_bundle
        raise "Expanded Dex data is missing: #{DATA_PATH}" unless File.file?(DATA_PATH)
        raw = File.open(DATA_PATH, "rb") { |file| file.read }
        bundle = Marshal.load(raw)
        raise "Expanded Dex data must be a Hash." unless bundle.is_a?(Hash)
        unless bundle[:format_version].to_i == FORMAT_VERSION
          raise "Unsupported Expanded Dex format #{bundle[:format_version].inspect}."
        end
        raise "Expanded Dex species data is empty." if Array(bundle[:species]).empty?
        unless bundle[:base_max_id].to_i == 576 && bundle[:first_expanded_id].to_i == 577
          raise "Expanded Dex ID boundary is invalid."
        end
        bundle
      end

      def configure_species_limits
        maximum = max_species_id
        raise "Expanded Dex maximum species ID is invalid." if maximum < first_species_id

        @old_triple_base = ::Settings::ZAPMOLCUNO_NB
        replace_constant(::Settings, :NB_POKEMON, maximum)
        replace_constant(Object, :NB_POKEMON, maximum)
        replace_constant(Object, :CONST_NB_POKE, maximum)

        triple_base = maximum * maximum + maximum + 1
        replace_constant(::Settings, :ZAPMOLCUNO_NB, triple_base)
        replace_constant(Object, :ZAPMOLCUNO_NB, triple_base)
      end

      def replace_constant(owner, name, value)
        owner.send(:remove_const, name) if owner.const_defined?(name, false)
        owner.const_set(name, value)
      end

      def register_events
        return unless defined?(Reloaded::Events)
        Reloaded::Events.on(:game_data_loaded, :expanded_dex_inject, :priority => 10) do |_context|
          Reloaded::ExpandedDex.inject_all
        end
      end

      def inject_records(registry, rows, kind)
        count = 0
        Array(rows).each do |raw|
          row = deep_copy(raw)
          symbol = row[:id]
          number = row[:id_number].to_i
          existing = registry.try_get(symbol) rescue nil
          next if existing

          numbered = registry::DATA[number] rescue nil
          if numbered && numbered.respond_to?(:id) && numbered.id != symbol
            log_error("Expanded Dex #{kind} ID #{number} is already used by #{numbered.id}; skipped #{symbol}.")
            next
          end

          registry.register(row)
          entry = registry.try_get(symbol) rescue nil
          entry.instance_variable_set(:@reloaded_data_patch, true) if entry
          count += 1
        end
        count
      end

      def inject_species
        count = 0
        Array(@bundle[:species]).each do |raw|
          row = deep_copy(raw)
          symbol = row[:id]
          number = row[:id_number].to_i
          existing = GameData::Species::DATA[symbol]
          if existing
            if existing.id_number != number
              log_error("Expanded Dex species #{symbol} expected ID #{number}, but ID #{existing.id_number} is already registered.")
            end
            next
          end

          numbered = GameData::Species::DATA[number]
          if numbered && numbered.respond_to?(:id) && numbered.id != symbol
            log_error("Expanded Dex species ID #{number} is already used by #{numbered.id}; skipped #{symbol}.")
            next
          end

          GameData::Species.register(row)
          entry = GameData::Species::DATA[symbol]
          entry.instance_variable_set(:@reloaded_data_patch_core, true) if entry
          count += 1
        end
        count
      end

      def rebase_triple_fusions
        old_base = @old_triple_base.to_i
        new_base = ::Settings::ZAPMOLCUNO_NB.to_i
        return 0 if old_base <= 0 || old_base == new_base

        triples = GameData::Species::DATA.values.uniq.select do |species|
          species.is_a?(GameData::Species) &&
            species.id_number >= old_base &&
            species.id_number < new_base
        end
        triples.each do |species|
          old_id = species.id_number
          new_id = new_base + (old_id - old_base)
          row = species_to_hash(species, new_id)
          GameData::Species.register(row)
          replacement = GameData::Species::DATA[species.id]
          replacement.instance_variable_set(:@reloaded_data_patch_core, true) if replacement
          GameData::Species::DATA.delete(old_id)
        end
        triples.length
      end

      def species_to_hash(species, id_number)
        {
          :id => species.id,
          :id_number => id_number,
          :species => species.species,
          :form => species.form,
          :name => species.real_name,
          :form_name => species.real_form_name,
          :category => species.real_category,
          :pokedex_entry => species.real_pokedex_entry,
          :pokedex_form => species.pokedex_form,
          :type1 => species.type1,
          :type2 => species.type2,
          :base_stats => deep_copy(species.base_stats),
          :evs => deep_copy(species.evs),
          :base_exp => species.base_exp,
          :growth_rate => species.growth_rate,
          :gender_ratio => species.gender_ratio,
          :catch_rate => species.catch_rate,
          :happiness => species.happiness,
          :moves => deep_copy(species.moves),
          :tutor_moves => deep_copy(species.tutor_moves),
          :egg_moves => deep_copy(species.egg_moves),
          :abilities => deep_copy(species.abilities),
          :hidden_abilities => deep_copy(species.hidden_abilities),
          :wild_item_common => species.wild_item_common,
          :wild_item_uncommon => species.wild_item_uncommon,
          :wild_item_rare => species.wild_item_rare,
          :egg_groups => deep_copy(species.egg_groups),
          :hatch_steps => species.hatch_steps,
          :incense => species.incense,
          :evolutions => deep_copy(species.evolutions),
          :height => species.height,
          :weight => species.weight,
          :color => species.color,
          :shape => species.shape,
          :habitat => species.habitat,
          :generation => species.generation,
          :mega_stone => species.mega_stone,
          :mega_move => species.mega_move,
          :unmega_form => species.unmega_form,
          :mega_message => species.mega_message,
          :back_sprite_x => species.back_sprite_x,
          :back_sprite_y => species.back_sprite_y,
          :front_sprite_x => species.front_sprite_x,
          :front_sprite_y => species.front_sprite_y,
          :front_sprite_altitude => species.front_sprite_altitude,
          :shadow_x => species.shadow_x,
          :shadow_size => species.shadow_size
        }
      end

      def game_data_ready?
        defined?(GameData::Species) &&
          defined?(GameData::Move) &&
          defined?(GameData::Ability) &&
          !GameData::Species::DATA.empty?
      end

      def deep_copy(value)
        Marshal.load(Marshal.dump(value))
      end

      def log_once(message, key)
        return unless defined?(Reloaded::Log)
        if Reloaded::Log.respond_to?(:info_once)
          Reloaded::Log.info_once(message, :framework, :key => key)
        else
          Reloaded::Log.info(message, :framework)
        end
      end

      def log_error(message)
        return unless defined?(Reloaded::Log)
        Reloaded::Log.error(message, :framework)
      end

      def log_exception(message, error)
        return unless defined?(Reloaded::Log)
        Reloaded::Log.exception(message, error, :channel => :framework)
      end

      def register_patch_point
        return unless defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          :expanded_dex_registry,
          :target => "GameData::Move, GameData::Ability, and GameData::Species",
          :type => :runtime_data_bridge,
          :file => __FILE__,
          :owner => :reloaded,
          :priority => 10,
          :reason => "Loads compiled Expanded Dex records after vanilla GameData.",
          :recommended_fix => "Rebuild Reloaded/Data/ExpandedDex with the Expanded Dex Builder.",
          :conflict_group => "game_data_expanded_dex"
        )
      end
    end
  end
end

Reloaded::ExpandedDex.install if defined?(Reloaded::ExpandedDex)
