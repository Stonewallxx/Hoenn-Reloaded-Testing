#======================================================
# Reloaded Save Data
# Author: Stonewall
#======================================================
# Central save bucket for Reloaded systems and mods.
#
# Responsibilities:
#   - Register one Reloaded save entry with the base SaveData system.
#   - Give mods a namespaced place to store persistent data.
#   - Keep Reloaded save data away from random vanilla object fields.
#   - Validate stored values before they are written to the save file.
#
#======================================================

module Reloaded
  module SaveData
    SAVE_KEY = :reloaded
    SCHEMA_VERSION = 1

    @data = nil
    @registered = false

    class << self
      def data
        @data ||= empty_bucket
      end

      def empty_bucket
        {
          :schema_version => SCHEMA_VERSION,
          :systems => {},
          :mods => {},
          :metadata => {}
        }
      end

      def load(value)
        @data = normalize_bucket(value)
        Reloaded::Log.debug("Loaded Reloaded save bucket", :save_data) if defined?(Reloaded::Log)
        emit(:reloaded_save_loaded, :data => @data)
        @data
      rescue Exception => e
        Reloaded::Log.exception("Reloaded save bucket failed to load", e, channel: :save_data) if defined?(Reloaded::Log)
        @data = empty_bucket
      end

      def dump
        @data = normalize_bucket(@data)
        emit(:reloaded_save_saving, :data => @data)
        Reloaded::Log.debug("Dumped Reloaded save bucket", :save_data) if defined?(Reloaded::Log)
        @data
      rescue Exception => e
        Reloaded::Log.exception("Reloaded save bucket failed to dump", e, channel: :save_data) if defined?(Reloaded::Log)
        empty_bucket
      end

      def namespace(owner, section: :mods)
        owner_key = normalize_owner(owner)
        section_hash(section)[owner_key] ||= {}
      end

      def system(system_id)
        namespace(system_id, section: :systems)
      end

      def mod(mod_id)
        namespace(mod_id, section: :mods)
      end

      def get(owner, key, default = nil, section: :mods)
        bucket = namespace(owner, section: section)
        normalized_key = normalize_key(key)
        return bucket[normalized_key] if bucket.has_key?(normalized_key)
        default
      end

      def set(owner, key, value, section: :mods)
        unless marshalable?(value)
          Reloaded::Log.warning(
            "Rejected non-saveable value for #{section}/#{owner}/#{key} (#{value.class})",
            :save_data
          ) if defined?(Reloaded::Log)
          return false
        end
        namespace(owner, section: section)[normalize_key(key)] = value
        true
      end

      def delete(owner, key = nil, section: :mods)
        if key.nil?
          section_hash(section).delete(normalize_owner(owner))
        else
          namespace(owner, section: section).delete(normalize_key(key))
        end
      end

      def has?(owner, key, section: :mods)
        namespace(owner, section: section).has_key?(normalize_key(key))
      end

      def clear(owner = nil, section: :mods)
        if owner.nil?
          section_hash(section).clear
        else
          delete(owner, section: section)
        end
      end

      def registered?
        @registered
      end

      def register_with_base_save_data
        return false unless defined?(::SaveData)
        return true if @registered
        ::SaveData.register(SAVE_KEY) do
          save_value { Reloaded::SaveData.dump }
          load_value { |value| Reloaded::SaveData.load(value) }
          new_game_value { Reloaded::SaveData.empty_bucket }
        end
        @registered = true
        register_patch_point
        Reloaded::Log.info("Registered Reloaded save bucket", :save_data) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Reloaded save bucket registration failed", e, channel: :save_data) if defined?(Reloaded::Log)
        false
      end

      private

      def section_hash(section)
        bucket = data
        section_key = normalize_section(section)
        bucket[section_key] ||= {}
      end

      def normalize_bucket(value)
        source = value.is_a?(Hash) ? value : {}
        {
          :schema_version => SCHEMA_VERSION,
          :systems => normalize_section_hash(source[:systems] || source["systems"]),
          :mods => normalize_section_hash(source[:mods] || source["mods"]),
          :metadata => normalize_section_hash(source[:metadata] || source["metadata"])
        }
      end

      def normalize_section_hash(value)
        return {} unless value.is_a?(Hash)
        normalized = {}
        value.each do |owner, owner_data|
          next unless owner_data.is_a?(Hash)
          normalized[normalize_owner(owner)] = normalize_value_hash(owner_data)
        end
        normalized
      end

      def normalize_value_hash(value)
        normalized = {}
        value.each { |key, entry| normalized[normalize_key(key)] = entry } if value.is_a?(Hash)
        normalized
      end

      def normalize_owner(owner)
        owner.to_s.strip.downcase
      end

      def normalize_key(key)
        key.to_s
      end

      def normalize_section(section)
        section.to_s == "systems" ? :systems : :mods
      end

      def marshalable?(value)
        Marshal.dump(value)
        true
      rescue
        false
      end

      def emit(event_name, context)
        Reloaded::Events.emit(event_name, context) if defined?(Reloaded::Events)
      rescue Exception => e
        Reloaded::Log.exception("Reloaded save event #{event_name} failed", e, channel: :save_data) if defined?(Reloaded::Log)
      end

      def register_patch_point
        return unless defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          :reloaded_save_bucket,
          :target => "SaveData.register(:reloaded)",
          :type => :data_patch,
          :file => __FILE__,
          :owner => :reloaded,
          :priority => 100,
          :reason => "Adds one central save bucket for Reloaded systems and mods.",
          :recommended_fix => "Only one system should register the :reloaded save key.",
          :conflict_group => "save_data_key:reloaded"
        )
      end
    end
  end
end

Reloaded::SaveData.register_with_base_save_data if defined?(Reloaded::SaveData)
