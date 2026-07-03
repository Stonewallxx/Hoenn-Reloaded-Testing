#======================================================
# Reloaded Data Patch Species
# Author: Stonewall
#======================================================
# Runtime data patch targets for species data.
#
# Responsibilities:
#   - Register species core and ability data patch targets.
#   - Apply patched core fields to existing GameData::Species entries.
#   - Apply patched level-up, tutor, and egg learnsets.
#   - Apply patched evolution arrays and rebuild generated prevolution entries.
#   - Apply patched normal and hidden ability arrays.
#   - Refresh targets after GameData.load_all refreshes base species data.
#   - Restore Reloaded-managed species fields before each rebuild.
#   - Keep forms reserved for later bridge files.
#
#======================================================

module Reloaded
  module DataPatchSpecies
    CORE_TARGET = "species.core".freeze
    LEARNSET_TARGET = "species.learnsets".freeze
    EVOLUTION_TARGET = "species.evolutions".freeze
    ABILITY_TARGET = "species.abilities".freeze

    CORE_FIELDS = [
      "name",
      "form_name",
      "category",
      "pokedex_entry",
      "pokedex_form",
      "type1",
      "type2",
      "base_stats",
      "evs",
      "base_exp",
      "growth_rate",
      "gender_ratio",
      "catch_rate",
      "happiness",
      "wild_item_common",
      "wild_item_uncommon",
      "wild_item_rare",
      "egg_groups",
      "hatch_steps",
      "incense",
      "height",
      "weight",
      "color",
      "shape",
      "habitat",
      "generation"
    ].freeze

    LEARNSET_FIELDS = [
      "moves",
      "add_moves",
      "tutor_moves",
      "add_tutor_moves",
      "egg_moves",
      "add_egg_moves"
    ].freeze

    EVOLUTION_FIELDS = [
      "evolutions",
      "add_evolutions"
    ].freeze

    @base_core_entries = {}
    @base_learnset_entries = {}
    @base_evolution_entries = {}
    @base_ability_entries = {}
    @managed_core_species = []
    @managed_learnset_species = []
    @managed_evolution_species = []
    @managed_ability_species = []

    class << self
      def install
        install_text_fallbacks
        register_target
        register_events
        register_patch_point
        Reloaded::Log.info("Installed Reloaded species data patch bridge", :mods) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Species data patch bridge install failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def register_target
        return unless defined?(Reloaded::DataPatches)
        refresh_base_entries
        Reloaded::DataPatches.register_target(
          CORE_TARGET,
          @base_core_entries,
          owner: :reloaded,
          description: "Runtime species core data patch target.",
          defer_missing_entries: true
        )
        Reloaded::DataPatches.register_target(
          LEARNSET_TARGET,
          @base_learnset_entries,
          owner: :reloaded,
          description: "Runtime species learnset data patch target.",
          defer_missing_entries: true
        )
        Reloaded::DataPatches.register_target(
          EVOLUTION_TARGET,
          @base_evolution_entries,
          owner: :reloaded,
          description: "Runtime species evolution data patch target.",
          defer_missing_entries: true
        )
        Reloaded::DataPatches.register_target(
          ABILITY_TARGET,
          @base_ability_entries,
          owner: :reloaded,
          description: "Runtime species ability list data patch target.",
          defer_missing_entries: true
        )
      end

      def apply_all
        return false unless defined?(GameData::Species)
        return true if @base_core_entries.empty? && @base_learnset_entries.empty? && @base_evolution_entries.empty? && @base_ability_entries.empty?
        restore_managed_entries
        core_count = apply_core_patches
        learnset_count = apply_learnset_patches
        evolution_count = apply_evolution_patches
        ability_count = apply_ability_patches
        rebuild_prevolution_entries if evolution_count > 0
        log_applied("core", core_count) if core_count > 0
        log_applied("learnset", learnset_count) if learnset_count > 0
        log_applied("evolution", evolution_count) if evolution_count > 0
        log_applied("ability", ability_count) if ability_count > 0
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to apply species data patches", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      private

      def apply_core_patches
        touched_ids = patched_species_ids(CORE_TARGET)
        applied = 0
        touched_ids.each do |id|
          raw_data = Reloaded::DataPatches.entry(CORE_TARGET, id)
          applied += 1 if apply_core_entry(id, raw_data)
        end
        applied
      end

      def apply_learnset_patches
        touched_ids = patched_species_ids(LEARNSET_TARGET)
        applied = 0
        touched_ids.each do |id|
          raw_data = Reloaded::DataPatches.entry(LEARNSET_TARGET, id)
          applied += 1 if apply_learnset_entry(id, raw_data)
        end
        applied
      end

      def apply_ability_patches
        touched_ids = patched_species_ids(ABILITY_TARGET)
        applied = 0
        touched_ids.each do |id|
          raw_data = Reloaded::DataPatches.entry(ABILITY_TARGET, id)
          applied += 1 if apply_ability_entry(id, raw_data)
        end
        applied
      end

      def apply_evolution_patches
        touched_ids = patched_species_ids(EVOLUTION_TARGET)
        applied = 0
        touched_ids.each do |id|
          raw_data = Reloaded::DataPatches.entry(EVOLUTION_TARGET, id)
          applied += 1 if apply_evolution_entry(id, raw_data)
        end
        applied
      end

      def refresh_base_entries
        @base_core_entries = {}
        @base_learnset_entries = {}
        @base_evolution_entries = {}
        @base_ability_entries = {}
        return unless defined?(GameData::Species)
        GameData::Species::DATA.each do |key, species|
          next if key.is_a?(Integer)
          next unless species.is_a?(GameData::Species)
          entry_id = normalize_entry_id(key)
          @base_core_entries[entry_id] = species_core_to_hash(species)
          @base_learnset_entries[entry_id] = species_learnset_to_hash(species)
          @base_evolution_entries[entry_id] = species_evolutions_to_hash(species)
          @base_ability_entries[entry_id] = species_abilities_to_hash(species)
        end
        @base_core_entries
      end

      def species_core_to_hash(species)
        {
          "name" => species.real_name,
          "form_name" => species.real_form_name,
          "category" => species.real_category,
          "pokedex_entry" => species.real_pokedex_entry,
          "pokedex_form" => species.pokedex_form,
          "type1" => species.type1.to_s,
          "type2" => species.type2.to_s,
          "base_stats" => stat_hash_to_strings(species.base_stats),
          "evs" => stat_hash_to_strings(species.evs),
          "base_exp" => species.base_exp,
          "growth_rate" => species.growth_rate.to_s,
          "gender_ratio" => species.gender_ratio.to_s,
          "catch_rate" => species.catch_rate,
          "happiness" => species.happiness,
          "wild_item_common" => species.wild_item_common ? species.wild_item_common.to_s : nil,
          "wild_item_uncommon" => species.wild_item_uncommon ? species.wild_item_uncommon.to_s : nil,
          "wild_item_rare" => species.wild_item_rare ? species.wild_item_rare.to_s : nil,
          "egg_groups" => Array(species.egg_groups).map(&:to_s),
          "hatch_steps" => species.hatch_steps,
          "incense" => species.incense ? species.incense.to_s : nil,
          "height" => species.height,
          "weight" => species.weight,
          "color" => species.color.to_s,
          "shape" => species.shape.to_s,
          "habitat" => species.habitat.to_s,
          "generation" => species.generation
        }
      end

      def species_abilities_to_hash(species)
        {
          "abilities" => Array(species.abilities).map(&:to_s),
          "hidden_abilities" => Array(species.hidden_abilities).map(&:to_s)
        }
      end

      def species_learnset_to_hash(species)
        {
          "moves" => Array(species.moves).map { |entry| level_move_to_hash(entry) },
          "tutor_moves" => Array(species.tutor_moves).map(&:to_s),
          "egg_moves" => Array(species.egg_moves).map(&:to_s)
        }
      end

      def species_evolutions_to_hash(species)
        {
          "evolutions" => Array(species.evolutions).reject { |entry| entry[3] }.map { |entry| evolution_to_hash(entry) }
        }
      end

      def evolution_to_hash(entry)
        {
          "species" => entry[0].to_s,
          "method" => entry[1].to_s,
          "parameter" => evolution_parameter_to_data(entry[2])
        }
      rescue
        {}
      end

      def level_move_to_hash(entry)
        {
          "level" => entry[0].to_i,
          "move" => entry[1].to_s
        }
      rescue
        {
          "level" => 1,
          "move" => entry.to_s
        }
      end

      def restore_managed_entries
        return unless defined?(GameData::Species)
        Array(@managed_core_species).each do |species_id|
          species = GameData::Species.try_get(species_id) rescue nil
          base = @base_core_entries[normalize_entry_id(species_id)]
          next unless species && base
          set_core_fields(species, base)
        end
        Array(@managed_learnset_species).each do |species_id|
          species = GameData::Species.try_get(species_id) rescue nil
          base = @base_learnset_entries[normalize_entry_id(species_id)]
          next unless species && base
          set_learnset_fields(species, base)
        end
        Array(@managed_evolution_species).each do |species_id|
          species = GameData::Species.try_get(species_id) rescue nil
          base = @base_evolution_entries[normalize_entry_id(species_id)]
          next unless species && base
          set_evolution_fields(species, base)
        end
        Array(@managed_ability_species).each do |species_id|
          species = GameData::Species.try_get(species_id) rescue nil
          base = @base_ability_entries[normalize_entry_id(species_id)]
          next unless species && base
          set_ability_arrays(species, base)
        end
        @managed_core_species = []
        @managed_learnset_species = []
        @managed_evolution_species = []
        @managed_ability_species = []
        rebuild_prevolution_entries
      end

      def apply_core_entry(id, raw_data)
        species_id = normalize_symbol(id)
        species = GameData::Species.try_get(species_id) rescue nil
        unless species
          log_error("Species core patch #{species_id} cannot apply; species does not exist.")
          return false
        end
        data = normalize_core_data(species_id, raw_data)
        set_core_fields(species, data)
        species.instance_variable_set(:@reloaded_data_patch_core, true)
        @managed_core_species << species_id unless @managed_core_species.include?(species_id)
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to apply species core patch #{id}", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def apply_ability_entry(id, raw_data)
        species_id = normalize_symbol(id)
        species = GameData::Species.try_get(species_id) rescue nil
        unless species
          log_error("Species ability patch #{species_id} cannot apply; species does not exist.")
          return false
        end
        data = normalize_ability_data(species_id, raw_data)
        set_ability_arrays(species, data)
        @managed_ability_species << species_id unless @managed_ability_species.include?(species_id)
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to apply species ability patch #{id}", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def apply_learnset_entry(id, raw_data)
        species_id = normalize_symbol(id)
        species = GameData::Species.try_get(species_id) rescue nil
        unless species
          log_error("Species learnset patch #{species_id} cannot apply; species does not exist.")
          return false
        end
        data = normalize_learnset_data(species_id, raw_data)
        set_learnset_fields(species, data)
        @managed_learnset_species << species_id unless @managed_learnset_species.include?(species_id)
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to apply species learnset patch #{id}", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def apply_evolution_entry(id, raw_data)
        species_id = normalize_symbol(id)
        species = GameData::Species.try_get(species_id) rescue nil
        unless species
          log_error("Species evolution patch #{species_id} cannot apply; species does not exist.")
          return false
        end
        data = normalize_evolution_data(species_id, raw_data)
        set_evolution_fields(species, data)
        @managed_evolution_species << species_id unless @managed_evolution_species.include?(species_id)
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to apply species evolution patch #{id}", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def normalize_core_data(id, raw_data)
        raw = stringify_keys(raw_data.is_a?(Hash) ? raw_data : {})
        base = @base_core_entries[normalize_entry_id(id)] || {}
        data = {}
        CORE_FIELDS.each { |field| data[field] = raw.key?(field) ? raw[field] : base[field] }
        type1 = blank?(data["type1"]) ? "NORMAL" : data["type1"]
        type2 = blank?(data["type2"]) ? type1 : data["type2"]
        egg_groups = normalize_data_id_list("GameData::EggGroup", data["egg_groups"])
        egg_groups = [:Undiscovered] if egg_groups.empty?
          base_stats = raw.key?("base_stats") ? merge_stat_hash(base["base_stats"], raw["base_stats"]) : data["base_stats"]
          evs = raw.key?("evs") ? merge_stat_hash(base["evs"], raw["evs"]) : data["evs"]

          {
            "name" => blank?(data["name"]) ? id.to_s : data["name"].to_s,
            "form_name" => blank?(data["form_name"]) ? nil : data["form_name"].to_s,
            "category" => blank?(data["category"]) ? "???" : data["category"].to_s,
            "pokedex_entry" => blank?(data["pokedex_entry"]) ? "???" : data["pokedex_entry"].to_s,
            "pokedex_form" => data["pokedex_form"].to_i,
            "type1" => resolve_data_id("GameData::Type", type1, :NORMAL),
            "type2" => resolve_data_id("GameData::Type", type2, :NORMAL),
            "base_stats" => normalize_stat_hash(base_stats, 1),
            "evs" => normalize_stat_hash(evs, 0),
          "base_exp" => int_value(data["base_exp"], 100),
          "growth_rate" => resolve_data_id("GameData::GrowthRate", data["growth_rate"], :Medium),
          "gender_ratio" => resolve_data_id("GameData::GenderRatio", data["gender_ratio"], :Female50Percent),
          "catch_rate" => int_value(data["catch_rate"], 255),
          "happiness" => int_value(data["happiness"], 70),
          "wild_item_common" => resolve_data_id("GameData::Item", data["wild_item_common"], nil),
          "wild_item_uncommon" => resolve_data_id("GameData::Item", data["wild_item_uncommon"], nil),
          "wild_item_rare" => resolve_data_id("GameData::Item", data["wild_item_rare"], nil),
          "egg_groups" => egg_groups,
          "hatch_steps" => int_value(data["hatch_steps"], 1),
          "incense" => resolve_data_id("GameData::Item", data["incense"], nil),
          "height" => float_value(data["height"], 1.0),
          "weight" => float_value(data["weight"], 1.0),
          "color" => resolve_data_id("GameData::BodyColor", data["color"], :Red),
          "shape" => resolve_data_id("GameData::BodyShape", data["shape"], :Head),
          "habitat" => resolve_data_id("GameData::Habitat", data["habitat"], :None),
          "generation" => int_value(data["generation"], 0)
        }
      end

      def normalize_ability_data(id, raw_data)
        raw = stringify_keys(raw_data.is_a?(Hash) ? raw_data : {})
        base = @base_ability_entries[normalize_entry_id(id)] || {}
        {
          "abilities" => normalize_ability_list(raw.key?("abilities") ? raw["abilities"] : base["abilities"]),
          "hidden_abilities" => normalize_ability_list(raw.key?("hidden_abilities") ? raw["hidden_abilities"] : base["hidden_abilities"])
        }
      end

      def normalize_learnset_data(id, raw_data)
        raw = stringify_keys(raw_data.is_a?(Hash) ? raw_data : {})
        base = @base_learnset_entries[normalize_entry_id(id)] || {}
        data = {}
        LEARNSET_FIELDS.each { |field| data[field] = raw.key?(field) ? raw[field] : base[field] }
        moves = raw.key?("moves") ? normalize_level_moves(data["moves"]) : normalize_level_moves(base["moves"])
        moves = merge_level_moves(moves, normalize_level_moves(data["add_moves"]))
        tutor_moves = raw.key?("tutor_moves") ? normalize_move_list(data["tutor_moves"]) : normalize_move_list(base["tutor_moves"])
        tutor_moves = merge_move_lists(tutor_moves, normalize_move_list(data["add_tutor_moves"]))
        egg_moves = raw.key?("egg_moves") ? normalize_move_list(data["egg_moves"]) : normalize_move_list(base["egg_moves"])
        egg_moves = merge_move_lists(egg_moves, normalize_move_list(data["add_egg_moves"]))
        {
          "moves" => moves,
          "tutor_moves" => tutor_moves,
          "egg_moves" => egg_moves
        }
      end

      def normalize_evolution_data(id, raw_data)
        raw = stringify_keys(raw_data.is_a?(Hash) ? raw_data : {})
        base = @base_evolution_entries[normalize_entry_id(id)] || {}
        data = {}
        EVOLUTION_FIELDS.each { |field| data[field] = raw.key?(field) ? raw[field] : base[field] }
        evolutions = raw.key?("evolutions") ? normalize_evolutions(data["evolutions"]) : normalize_evolutions(base["evolutions"])
        evolutions = merge_evolutions(evolutions, normalize_evolutions(data["add_evolutions"]))
        {
          "evolutions" => evolutions
        }
      end

      def set_core_fields(species, data)
        species.instance_variable_set(:@real_name, data["name"])
        species.instance_variable_set(:@real_form_name, data["form_name"])
        species.instance_variable_set(:@real_category, data["category"])
        species.instance_variable_set(:@real_pokedex_entry, data["pokedex_entry"])
        species.instance_variable_set(:@pokedex_form, data["pokedex_form"])
        species.instance_variable_set(:@type1, data["type1"])
        species.instance_variable_set(:@type2, data["type2"])
        species.instance_variable_set(:@base_stats, data["base_stats"])
        species.instance_variable_set(:@evs, data["evs"])
        species.instance_variable_set(:@base_exp, data["base_exp"])
        species.instance_variable_set(:@growth_rate, data["growth_rate"])
        species.instance_variable_set(:@gender_ratio, data["gender_ratio"])
        species.instance_variable_set(:@catch_rate, data["catch_rate"])
        species.instance_variable_set(:@happiness, data["happiness"])
        species.instance_variable_set(:@wild_item_common, data["wild_item_common"])
        species.instance_variable_set(:@wild_item_uncommon, data["wild_item_uncommon"])
        species.instance_variable_set(:@wild_item_rare, data["wild_item_rare"])
        species.instance_variable_set(:@egg_groups, data["egg_groups"])
        species.instance_variable_set(:@hatch_steps, data["hatch_steps"])
        species.instance_variable_set(:@incense, data["incense"])
        species.instance_variable_set(:@height, data["height"])
        species.instance_variable_set(:@weight, data["weight"])
        species.instance_variable_set(:@color, data["color"])
        species.instance_variable_set(:@shape, data["shape"])
        species.instance_variable_set(:@habitat, data["habitat"])
        species.instance_variable_set(:@generation, data["generation"])
      end

      def set_learnset_fields(species, data)
        species.instance_variable_set(:@moves, normalize_level_moves(data["moves"]))
        species.instance_variable_set(:@tutor_moves, normalize_move_list(data["tutor_moves"]))
        species.instance_variable_set(:@egg_moves, normalize_move_list(data["egg_moves"]))
      end

      def set_evolution_fields(species, data)
        species.instance_variable_set(:@evolutions, normalize_evolutions(data["evolutions"]))
      end

      def set_ability_arrays(species, data)
        species.instance_variable_set(:@abilities, normalize_ability_list(data["abilities"]))
        species.instance_variable_set(:@hidden_abilities, normalize_ability_list(data["hidden_abilities"]))
      end

      def stat_hash_to_strings(hash)
        result = {}
        hash.each { |key, value| result[key.to_s] = value } if hash.respond_to?(:each)
        result
      end

      def normalize_stat_hash(value, minimum)
        raw = stringify_keys(value.is_a?(Hash) ? value : {})
        result = {}
        stat_ids.each do |stat|
          string_id = stat.to_s
          value = raw.key?(string_id) ? raw[string_id] : raw[string_id.downcase]
          amount = value.nil? ? minimum : value.to_i
          amount = minimum if amount < minimum
          result[stat] = amount
        end
        result
      end

      def merge_stat_hash(base, patch)
        merged = stringify_keys(base.is_a?(Hash) ? base : {})
        stringify_keys(patch.is_a?(Hash) ? patch : {}).each do |key, value|
          merged[key] = value
        end
        merged
      end

      def stat_ids
        ids = []
        if defined?(GameData::Stat)
          GameData::Stat.each_main { |stat| ids << stat.id }
        end
        ids.empty? ? [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED] : ids
      rescue
        [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]
      end

      def normalize_ability_list(value)
        Array(value).map { |ability| normalize_symbol(ability) }.reject { |ability| ability.to_s.empty? }
      end

      def normalize_level_moves(value)
        entries = []
        Array(value).each do |entry|
          normalized = normalize_level_move(entry)
          entries << normalized if normalized
        end
        entries.each_with_index.sort_by { |entry, index| [entry[0], index] }.map { |entry, _index| entry }
      end

      def normalize_level_move(entry)
        if entry.is_a?(Hash)
          raw = stringify_keys(entry)
          level = int_value(raw["level"], 1)
          move = raw["move"] || raw["id"]
        elsif entry.is_a?(Array)
          level = int_value(entry[0], 1)
          move = entry[1]
        else
          return nil
        end
        return nil if blank?(move)
        [level, normalize_symbol(move)]
      end

      def normalize_move_list(value)
        Array(value).map { |move| normalize_symbol(move) }.reject { |move| move.to_s.empty? }
      end

      def merge_level_moves(base, incoming)
        result = Array(base).map(&:dup)
        Array(incoming).each do |entry|
          next if result.any? { |existing| existing[0] == entry[0] && existing[1] == entry[1] }
          result << entry
        end
        result.each_with_index.sort_by { |entry, index| [entry[0], index] }.map { |entry, _index| entry }
      end

      def merge_move_lists(base, incoming)
        result = Array(base).dup
        Array(incoming).each { |move| result << move unless result.include?(move) }
        result
      end

      def normalize_evolutions(value)
        entries = []
        Array(value).each do |entry|
          normalized = normalize_evolution(entry)
          entries << normalized if normalized
        end
        entries
      end

      def normalize_evolution(entry)
        if entry.is_a?(Hash)
          raw = stringify_keys(entry)
          species = raw["species"] || raw["id"] || raw["target"]
          method = raw["method"] || raw["type"]
          parameter = raw.key?("parameter") ? raw["parameter"] : raw["param"]
          prevolution = raw.key?("prevolution") ? raw["prevolution"] : raw["is_prevolution"]
        elsif entry.is_a?(Array)
          species = entry[0]
          method = entry[1]
          parameter = entry[2]
          prevolution = entry[3]
        else
          return nil
        end
        return nil if blank?(species) || blank?(method)
        method_id = resolve_data_id("GameData::Evolution", method, :None)
        [normalize_symbol(species), method_id, normalize_evolution_parameter(method_id, parameter), !!prevolution]
      end

      def normalize_evolution_parameter(method, parameter)
        method_id = resolve_data_id("GameData::Evolution", method, :None)
        param_type = nil
        param_type = GameData::Evolution.get(method_id).parameter if defined?(GameData::Evolution)
        return nil if blank?(parameter)
        return integer_string?(parameter) ? parameter.to_i : normalize_symbol(parameter) if param_type.nil?
        return int_value(parameter, 0) if param_type == Integer
        normalize_evolution_parameter_id(param_type, parameter)
      rescue
        return nil if blank?(parameter)
        integer_string?(parameter) ? parameter.to_i : normalize_symbol(parameter)
      end

      def normalize_evolution_parameter_id(param_type, parameter)
        case param_type
        when :Item
          resolve_data_id("GameData::Item", parameter, nil)
        when :Move
          resolve_data_id("GameData::Move", parameter, nil)
        when :Species
          resolve_data_id("GameData::Species", parameter, nil)
        when :Type
          resolve_data_id("GameData::Type", parameter, nil)
        else
          normalize_symbol(parameter)
        end
      end

      def evolution_parameter_to_data(value)
        return nil if value.nil?
        value.is_a?(Symbol) ? value.to_s : value
      end

      def merge_evolutions(base, incoming)
        result = Array(base).map(&:dup)
        Array(incoming).each do |entry|
          next if result.any? { |existing| existing[0] == entry[0] && existing[1] == entry[1] && existing[2] == entry[2] && existing[3] == entry[3] }
          result << entry
        end
        result
      end

      def rebuild_prevolution_entries
        return unless defined?(GameData::Species)
        all_evos = {}
        GameData::Species.each do |species|
          current = Array(species.evolutions).reject { |entry| entry[3] }
          species.instance_variable_set(:@evolutions, current)
          current.each do |entry|
            all_evos[entry[0]] = [species.species, entry[1], entry[2], true] if !all_evos[entry[0]]
          end
        end
        GameData::Species.each do |species|
          prevolution = all_evos[species.species]
          species.evolutions.push(prevolution.clone) if prevolution
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to rebuild species prevolution entries", e, channel: :mods) if defined?(Reloaded::Log)
      end

      def normalize_symbol_list(value)
        Array(value).map { |entry| normalize_symbol(entry) }.reject { |entry| entry.to_s.empty? }
      end

      def normalize_data_id_list(class_name, value)
        Array(value).map { |entry| resolve_data_id(class_name, entry, nil) }.compact.reject { |entry| entry.to_s.empty? }
      end

      def resolve_data_id(class_name, value, default = nil)
        return default if blank?(value)
        klass = resolve_class(class_name)
        exact = value.is_a?(Symbol) ? value : value.to_s.to_sym
        return exact if klass && klass.const_defined?(:DATA) && klass::DATA.key?(exact)
        normalized_value = normalize_lookup_key(value)
        if klass && klass.const_defined?(:DATA)
          klass::DATA.keys.each do |key|
            next if key.is_a?(Integer)
            return key if normalize_lookup_key(key) == normalized_value
          end
        end
        normalize_symbol(value)
      rescue
        blank?(value) ? default : normalize_symbol(value)
      end

      def resolve_class(class_name)
        class_name.to_s.split("::").inject(Object) do |scope, name|
          return nil unless scope.const_defined?(name)
          scope.const_get(name)
        end
      rescue
        nil
      end

      def normalize_lookup_key(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "")
      end

      def int_value(value, default)
        return default if blank?(value)
        value.to_i
      end

      def float_value(value, default)
        return default if blank?(value)
        value.to_f
      end

      def integer_string?(value)
        value.to_s =~ /\A-?\d+\z/
      end

      def patched_species_ids(target)
        return [] unless defined?(Reloaded::DataPatches)
        Reloaded::DataPatches.applied(target).map { |patch| patch[:id] }.uniq
      rescue
        []
      end

      def stringify_keys(hash)
        result = {}
        hash.each { |key, value| result[key.to_s] = value }
        result
      rescue
        {}
      end

      def normalize_symbol(value)
        value.to_s.strip.upcase.gsub(/[^A-Z0-9_]+/, "_").to_sym
      end

      def normalize_entry_id(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_")
      end

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def register_events
        return unless defined?(Reloaded::Events)
        Reloaded::Events.on(:game_data_loaded, :species_data_patch_target_refresh, priority: 50) do |_context|
          Reloaded::DataPatchSpecies.register_target if defined?(Reloaded::DataPatchSpecies)
        end
        Reloaded::Events.on(:data_patches_loaded, :species_data_patch_bridge, priority: 100) do |_context|
          Reloaded::DataPatchSpecies.apply_all if defined?(Reloaded::DataPatchSpecies)
        end
      end

      def install_text_fallbacks
        return unless defined?(GameData::Species)
        return if GameData::Species.method_defined?(:reloaded_data_patch_species_name)

        GameData::Species.class_eval do
          alias_method :reloaded_data_patch_species_name, :name
          alias_method :reloaded_data_patch_species_form_name, :form_name
          alias_method :reloaded_data_patch_species_category, :category
          alias_method :reloaded_data_patch_species_pokedex_entry, :pokedex_entry

          def reloaded_data_patch_species_core?
            !!@reloaded_data_patch_core
          end

          def name
            return @real_name if reloaded_data_patch_species_core?
            reloaded_data_patch_species_name
          end

          def form_name
            return @real_form_name if reloaded_data_patch_species_core?
            reloaded_data_patch_species_form_name
          end

          def category
            return @real_category if reloaded_data_patch_species_core?
            reloaded_data_patch_species_category
          end

          def pokedex_entry
            return @real_pokedex_entry if reloaded_data_patch_species_core?
            reloaded_data_patch_species_pokedex_entry
          end
        end
      end

      def log_applied(kind, count)
        message = "Applied #{count} species #{kind} data patch entr#{count == 1 ? 'y' : 'ies'}"
        if defined?(Reloaded::Log)
          if Reloaded::Log.respond_to?(:info_once)
            Reloaded::Log.info_once(message, :mods, key: "species_#{kind}_data_patch_applied:#{count}")
          else
            Reloaded::Log.info(message, :mods)
          end
        end
      end

      def log_error(message)
        if defined?(Reloaded::Log)
          if Reloaded::Log.respond_to?(:error_once)
            Reloaded::Log.error_once(message, :mods, key: "species_ability_data_patch_error:#{message}")
          else
            Reloaded::Log.error(message, :mods)
          end
        end
      end

      def register_patch_point
        return unless defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          :species_data_patch_bridge,
          :target => "GameData::Species core data, learnsets, evolutions, and ability lists",
          :type => :runtime_data_bridge,
          :file => __FILE__,
          :owner => :reloaded,
          :priority => 100,
          :reason => "Applies Reloaded species data patches after enabled mods are scanned.",
          :recommended_fix => "Review Reloaded::DataPatchSpecies if patched species data fails to appear.",
          :conflict_group => "game_data_species"
        )
      end
    end
  end
end

Reloaded::DataPatchSpecies.install if defined?(Reloaded::DataPatchSpecies)
