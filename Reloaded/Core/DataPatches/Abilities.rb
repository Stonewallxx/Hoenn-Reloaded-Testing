#======================================================
# Reloaded Data Patch Abilities
# Author: Stonewall
#======================================================
# Direct runtime data patch target for base-game ability data.
#
# Responsibilities:
#   - Register the ability data patch target.
#   - Apply patched ability entries to GameData::Ability::DATA.
#   - Refresh the ability target after GameData.load_all refreshes base data.
#   - Restore Reloaded-managed ability entries before each rebuild.
#   - Provide safe text fallbacks for modded ability names and descriptions.
#   - Register the ability data patch bridge with Reloaded::Patches.
#
#======================================================

module Reloaded
  module DataPatchAbilities
    TARGET = "abilities".freeze

    ABILITY_FIELDS = [
      "id",
      "id_number",
      "name",
      "description"
    ].freeze

    @base_entries = {}
    @managed_symbols = []
    @managed_numbers = []

    class << self
      def install
        install_text_fallbacks
        register_target
        register_events
        register_patch_point
        Reloaded::Log.info("Installed Reloaded ability data patch bridge", :mods) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Ability data patch bridge install failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def register_target
        return unless defined?(Reloaded::DataPatches)
        refresh_base_entries
        Reloaded::DataPatches.register_target(
          TARGET,
          @base_entries,
          owner: :reloaded,
          description: "Runtime ability data patch target."
        )
      end

      def apply_all
        return false unless defined?(GameData::Ability)
        return true unless game_data_ready?
        restore_managed_entries
        touched_ids = patched_ability_ids
        applied = 0
        touched_ids.each do |id|
          raw_data = Reloaded::DataPatches.entry(TARGET, id)
          applied += 1 if apply_entry(id, raw_data)
        end
        log_applied(applied) if applied > 0
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to apply ability data patches", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      private

      def refresh_base_entries
        @base_entries = {}
        return unless defined?(GameData::Ability)
        GameData::Ability::DATA.each do |key, ability|
          next if key.is_a?(Integer)
          next unless ability.is_a?(GameData::Ability)
          @base_entries[key.to_s] = ability_to_hash(ability)
        end
        @base_entries
      end

      def ability_to_hash(ability)
        {
          "id" => ability.id.to_s,
          "id_number" => ability.id_number,
          "name" => ability.real_name,
          "description" => ability.real_description
        }
      end

      def restore_managed_entries
        return unless defined?(GameData::Ability)
        Array(@managed_numbers).each { |key| GameData::Ability::DATA.delete(key) }
        Array(@managed_symbols).each do |key|
          if @base_entries.key?(key.to_s)
            restore_base_entry(key.to_s)
          else
            GameData::Ability::DATA.delete(key)
          end
        end
        @managed_symbols = []
        @managed_numbers = []
      end

      def restore_base_entry(id)
        data = normalize_data(id, @base_entries[id])
        ability = GameData::Ability.new(data)
        GameData::Ability::DATA[data[:id]] = ability
        GameData::Ability::DATA[data[:id_number]] = ability
      end

      def apply_entry(id, raw_data)
        data = normalize_data(id, raw_data)
        return false unless validate_data(data)
        id_symbol = data[:id]
        id_number = data[:id_number]
        existing_number_owner = GameData::Ability::DATA[id_number]
        if existing_number_owner && existing_number_owner.id != id_symbol && !managed_number?(id_number)
          log_error("Ability patch #{id_symbol} cannot use id_number #{id_number}; it already belongs to #{existing_number_owner.id}.")
          return false
        end

        ability = GameData::Ability.new(data)
        ability.instance_variable_set(:@reloaded_data_patch, true)
        GameData::Ability::DATA[id_symbol] = ability
        GameData::Ability::DATA[id_number] = ability
        @managed_symbols << id_symbol unless @managed_symbols.include?(id_symbol)
        @managed_numbers << id_number unless @managed_numbers.include?(id_number)
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to apply ability patch #{id}", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def normalize_data(id, raw_data)
        raw = stringify_keys(raw_data.is_a?(Hash) ? raw_data : {})
        base = base_entry(id)
        data = {}
        ABILITY_FIELDS.each { |field| data[field] = raw.key?(field) ? raw[field] : base[field] }
        data["id"] = id if blank?(data["id"])
        data["id_number"] = next_id_number if blank?(data["id_number"])
        data["name"] = data["id"].to_s if blank?(data["name"])
        data["description"] = "???" if blank?(data["description"])

        {
          :id => normalize_symbol(data["id"]),
          :id_number => data["id_number"].to_i,
          :name => data["name"].to_s,
          :description => data["description"].to_s
        }
      end

      def validate_data(data)
        unless data[:id_number].is_a?(Integer) && data[:id_number] > 0
          log_error("Ability patch #{data[:id]} has invalid id_number #{data[:id_number].inspect}.")
          return false
        end
        if blank?(data[:name])
          log_error("Ability patch #{data[:id]} has an empty name.")
          return false
        end
        true
      end

      def base_entry(id)
        key = normalize_symbol(id).to_s
        @base_entries[key] || {}
      end

      def next_id_number
        keys = []
        GameData::Ability::DATA.each_key { |key| keys << key if key.is_a?(Integer) }
        value = keys.empty? ? 1 : keys.max + 1
        value += 1 while GameData::Ability::DATA.key?(value)
        value
      end

      def patched_ability_ids
        return [] unless defined?(Reloaded::DataPatches)
        Reloaded::DataPatches.applied(TARGET).map { |patch| patch[:id] }.uniq
      rescue
        []
      end

      def managed_number?(key)
        @managed_numbers.include?(key)
      end

      def normalize_symbol(value)
        value.to_s.strip.upcase.gsub(/[^A-Z0-9_]+/, "_").to_sym
      end

      def stringify_keys(hash)
        result = {}
        hash.each { |key, value| result[key.to_s] = value }
        result
      rescue
        {}
      end

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def game_data_ready?
        defined?(GameData::Ability) &&
          GameData::Ability.const_defined?(:DATA) &&
          !GameData::Ability::DATA.empty?
      rescue
        false
      end

      def log_applied(count)
        message = "Applied #{count} ability data patch entr#{count == 1 ? 'y' : 'ies'}"
        if defined?(Reloaded::Log)
          if Reloaded::Log.respond_to?(:info_once)
            Reloaded::Log.info_once(message, :mods, key: "ability_data_patch_applied:#{count}")
          else
            Reloaded::Log.info(message, :mods)
          end
        end
      end

      def log_error(message)
        if defined?(Reloaded::Log)
          if Reloaded::Log.respond_to?(:error_once)
            Reloaded::Log.error_once(message, :mods, key: "ability_data_patch_error:#{message}")
          else
            Reloaded::Log.error(message, :mods)
          end
        end
      end

      def register_events
        return unless defined?(Reloaded::Events)
        Reloaded::Events.on(:game_data_loaded, :ability_data_patch_target_refresh, priority: 50) do |_context|
          Reloaded::DataPatchAbilities.register_target if defined?(Reloaded::DataPatchAbilities)
        end
        Reloaded::Events.on(:data_patches_loaded, :ability_data_patch_bridge, priority: 100) do |_context|
          Reloaded::DataPatchAbilities.apply_all if defined?(Reloaded::DataPatchAbilities)
        end
      end

      def install_text_fallbacks
        return unless defined?(GameData::Ability)
        return if GameData::Ability.method_defined?(:reloaded_data_patch_ability_name)

        GameData::Ability.class_eval do
          alias_method :reloaded_data_patch_ability_name, :name
          alias_method :reloaded_data_patch_ability_description, :description

          def reloaded_data_patch_ability?
            !!@reloaded_data_patch
          end

          def name
            return @real_name if reloaded_data_patch_ability?
            reloaded_data_patch_ability_name
          end

          def description
            return @real_description if reloaded_data_patch_ability?
            reloaded_data_patch_ability_description
          end
        end
      end

      def register_patch_point
        return unless defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          :ability_data_patch_bridge,
          :target => "GameData::Ability::DATA",
          :type => :runtime_data_bridge,
          :file => __FILE__,
          :owner => :reloaded,
          :priority => 100,
          :reason => "Applies Reloaded ability data patches after enabled mods are scanned.",
          :recommended_fix => "Review Reloaded::DataPatchAbilities if patched abilities fail to appear.",
          :conflict_group => "game_data_abilities"
        )
      end
    end
  end
end

Reloaded::DataPatchAbilities.install if defined?(Reloaded::DataPatchAbilities)
