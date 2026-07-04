#======================================================
# Reloaded Mod Settings
# Author: Stonewall
#======================================================
# Profile-backed runtime settings API for Reloaded mods.
#
# Responsibilities:
#   - Read mod setting definitions discovered by the Mod Manager.
#   - Resolve default values from each mod's Settings.json schema.
#   - Store player values inside the active Mod Manager profile.
#   - Provide runtime helper methods for mods to read and write settings.
#   - Log setting changes and schema issues through Reloaded logging.
#
#======================================================

module Reloaded
  module ModSettings
    SUPPORTED_TYPES = [
      "toggle",
      "enum",
      "slider",
      "number",
      "category_header",
      "spacer"
    ].freeze

    @booted = false
    @definitions = {}

    class << self
      def boot
        refresh
        @booted = true
        Reloaded::Log.info("Loaded settings schemas for #{@definitions.length} mod(s)", :mods) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Mod Settings boot failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def refresh
        @definitions = {}
        return @definitions unless defined?(Reloaded::ModManager)
        Reloaded::ModManager.mod_ids.each do |mod_id|
          defs = normalize_definitions(Reloaded::ModManager.settings_defs(mod_id))
          @definitions[normalize_mod_id(mod_id)] = defs unless defs.empty?
        end
        @definitions
      rescue Exception => e
        Reloaded::Log.exception("Mod Settings refresh failed", e, channel: :mods) if defined?(Reloaded::Log)
        @definitions
      end

      def definitions(mod_id = nil)
        refresh if @definitions.nil? || @definitions.empty?
        return @definitions.dup if mod_id.nil?
        Array(@definitions[normalize_mod_id(mod_id)]).map { |entry| entry.dup }
      end

      def definition(mod_id, key)
        definitions(mod_id).find { |entry| entry["key"].to_s == key.to_s }
      end

      def has_settings?(mod_id)
        !definitions(mod_id).empty?
      end

      def defaults(mod_id)
        values = {}
        definitions(mod_id).each do |setting|
          next if non_value_type?(setting["type"])
          values[setting["key"]] = default_for(setting)
        end
        values
      end

      def values(mod_id)
        id = normalize_mod_id(mod_id)
        base = defaults(id)
        base.merge(stored_values(id).select { |key, _value| base.has_key?(key.to_s) })
      end

      def get(mod_id, key, fallback = nil)
        id = normalize_mod_id(mod_id)
        setting = definition(id, key)
        default = setting ? default_for(setting) : fallback
        stored = stored_values(id)
        stored.has_key?(key.to_s) ? stored[key.to_s] : default
      end

      def set(mod_id, key, value)
        id = normalize_mod_id(mod_id)
        setting = definition(id, key)
        raise "Unknown setting #{key} for #{id}" unless setting
        raise "Cannot set non-value setting #{key}" if non_value_type?(setting["type"])
        normalized = normalize_value(setting, value)
        return normalized if get(id, key) == normalized
        Reloaded::Profiles.set_mod_setting(id, key.to_s, normalized) if defined?(Reloaded::Profiles)
        Reloaded::Log.debug("Set #{id}.#{key}=#{normalized}", :mods) if defined?(Reloaded::Log)
        normalized
      end

      def reset(mod_id, key = nil)
        id = normalize_mod_id(mod_id)
        if key
          Reloaded::Profiles.delete_mod_setting(id, key.to_s) if defined?(Reloaded::Profiles)
          Reloaded::Log.info("Reset #{id}.#{key} to default", :mods) if defined?(Reloaded::Log)
          get(id, key)
        else
          Reloaded::Profiles.delete_mod_settings(id) if defined?(Reloaded::Profiles)
          Reloaded::Log.info("Reset all settings for #{id} to defaults", :mods) if defined?(Reloaded::Log)
          values(id)
        end
      end

      def reset_all
        return false unless defined?(Reloaded::Profiles)
        Reloaded::Profiles.delete_mod_settings
        Reloaded::Log.info("Reset all profile mod settings to defaults", :mods) if defined?(Reloaded::Log)
        true
      end

      def stale_keys(mod_id)
        id = normalize_mod_id(mod_id)
        valid = defaults(id).keys
        stored_values(id).keys.reject { |key| valid.include?(key.to_s) }
      end

      def prune_stale(mod_id = nil)
        return [] unless defined?(Reloaded::Profiles)
        removed = []
        ids = mod_id ? [normalize_mod_id(mod_id)] : Reloaded::Profiles.mod_settings.keys.map { |key| normalize_mod_id(key) }
        ids.each do |id|
          next if id.empty?
          stale_keys(id).each do |key|
            if Reloaded::Profiles.delete_mod_setting(id, key)
              removed << "#{id}.#{key}"
            end
          end
        end
        Reloaded::Log.info("Pruned stale mod settings: #{removed.join(", ")}", :mods) if defined?(Reloaded::Log) && !removed.empty?
        removed
      end

      def restart_required?(mod_id, key = nil)
        defs = definitions(mod_id)
        defs = defs.select { |entry| entry["key"].to_s == key.to_s } if key
        defs.any? { |entry| entry["restart_required"] }
      end

      def profile_values(mod_id)
        stored_values(mod_id)
      end

      private

      def normalize_definitions(defs)
        Array(defs).map { |entry| normalize_definition(entry) }.compact
      end

      def normalize_definition(entry)
        return nil unless entry.is_a?(Hash)
        type = entry["type"].to_s.downcase
        key = entry["key"].to_s.strip
        return nil if key.empty?
        unless SUPPORTED_TYPES.include?(type)
          Reloaded::Log.warning("Unsupported setting type #{type} for #{key}", :mods) if defined?(Reloaded::Log)
          return nil
        end
        entry.merge(
          "key" => key,
          "type" => type,
          "default" => normalize_value(entry, entry["default"]),
          "restart_required" => truthy?(entry["restart_required"])
        )
      rescue Exception => e
        Reloaded::Log.warning("Invalid setting definition #{entry.inspect}: #{e.message}", :mods) if defined?(Reloaded::Log)
        nil
      end

      def stored_values(mod_id)
        return {} unless defined?(Reloaded::Profiles)
        Reloaded::Profiles.mod_settings_for(normalize_mod_id(mod_id))
      rescue
        {}
      end

      def default_for(setting)
        normalize_value(setting, setting["default"])
      end

      def normalize_value(setting, value)
        case setting["type"].to_s
        when "toggle"
          truthy?(value)
        when "enum"
          options = Array(setting["options"]).map(&:to_s)
          candidate = value.to_s
          options.empty? || options.include?(candidate) ? candidate : options.first
        when "slider", "number"
          min = setting["min"].nil? ? 0 : setting["min"].to_i
          max = setting["max"].nil? ? 100 : setting["max"].to_i
          number = value.nil? ? min : value.to_i
          [[number, min].max, max].min
        else
          value
        end
      end

      def non_value_type?(type)
        ["category_header", "spacer"].include?(type.to_s)
      end

      def truthy?(value)
        case value.to_s.strip.downcase
        when "1", "true", "on", "yes", "enabled", "enable" then true
        else false
        end
      end

      def normalize_mod_id(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "")
      end
    end
  end
end
