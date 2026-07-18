#======================================================
# Reloaded Feature Flags
# Author: Stonewall
#======================================================
# Structural feature gates with global, save, and session scopes.
#======================================================

module Reloaded
  module Features
    CLASSIFICATIONS = [:stable, :experimental, :debug_only, :internal].freeze
    SAVE_SYSTEM = :features
    @features = {}
    @session_overrides = {}

    class << self
      def boot
        true
      end

      def register(id, config = nil, override: false, **keywords)
        key = normalize_id(id)
        raise ArgumentError, "Feature ID is empty." if key.to_s.empty?
        raise "Feature already registered: #{key}" if @features.key?(key) && !override
        source = config.is_a?(Hash) ? config.dup : {}
        source.merge!(keywords) unless keywords.empty?
        classification = normalize_id(source[:classification] || source["classification"] || :stable)
        raise "Unknown feature classification: #{classification}" unless CLASSIFICATIONS.include?(classification)
        has_default = source.key?(:default) || source.key?("default")
        default_value = has_default ? (source.key?(:default) ? source[:default] : source["default"]) : classification == :stable
        @features[key] = {
          :id => key,
          :name => (source[:name] || source["name"] || titleize(key)).to_s,
          :description => (source[:description] || source["description"] || "").to_s,
          :owner => normalize_id(source[:owner] || source["owner"] || :reloaded),
          :default => truthy?(default_value),
          :classification => classification,
          :required_systems => normalize_ids(source[:required_systems] || source["required_systems"]),
          :required_capabilities => normalize_ids(source[:required_capabilities] || source["required_capabilities"])
        }
        feature(key)
      rescue Exception => e
        Reloaded::Log.exception("Feature registration failed for #{id}", e, channel: :framework) if defined?(Reloaded::Log)
        nil
      end

      def registered?(id)
        @features.key?(normalize_id(id))
      end

      def enabled?(id)
        key = normalize_id(id)
        entry = @features[key]
        return false unless entry
        return @session_overrides[key] if @session_overrides.key?(key)
        save_value = save_override(key)
        return save_value unless save_value.nil?
        global_value = global_override(key)
        return global_value unless global_value.nil?
        entry[:default]
      end

      def available?(id, options = {})
        entry = @features[normalize_id(id)]
        return false unless entry
        return false if entry[:classification] == :debug_only && !developer?
        return false unless entry[:required_capabilities].all? { |capability| defined?(Reloaded::Platform) && Reloaded::Platform.supports?(capability) }
        unless options[:ignore_systems]
          return false unless entry[:required_systems].all? { |system_id| defined?(Reloaded::Systems) && Reloaded::Systems.available?(system_id) }
        end
        true
      rescue
        false
      end

      def active?(id, options = {})
        enabled?(id) && available?(id, options)
      end

      def reason(id)
        key = normalize_id(id)
        entry = @features[key]
        return "Feature is not registered" unless entry
        return "Feature is disabled" unless enabled?(key)
        return "Feature is debug-only" if entry[:classification] == :debug_only && !developer?
        missing_capability = entry[:required_capabilities].find { |capability| !defined?(Reloaded::Platform) || !Reloaded::Platform.supports?(capability) }
        return "Platform capability #{missing_capability} is unavailable" if missing_capability
        missing_system = entry[:required_systems].find { |system_id| !defined?(Reloaded::Systems) || !Reloaded::Systems.available?(system_id) }
        return "Required system #{missing_system} is unavailable" if missing_system
        "Active"
      end

      def enable(id, scope: :session)
        set_override(id, true, scope)
      end

      def disable(id, scope: :session)
        set_override(id, false, scope)
      end

      def reset(id, scope: :session)
        key = require_feature(id)
        case scope.to_sym
        when :session then @session_overrides.delete(key)
        when :save
          Reloaded::SaveData.delete(SAVE_SYSTEM, key, :section => :systems) if defined?(Reloaded::SaveData)
        when :global
          Reloaded::Settings.set(global_key(key), "Default") if defined?(Reloaded::Settings)
        else
          raise ArgumentError, "Unknown feature scope: #{scope}"
        end
        active?(key)
      end

      def feature(id)
        entry = @features[normalize_id(id)]
        return nil unless entry
        copy = entry.each_with_object({}) do |(key, value), result|
          result[key] = value.is_a?(Array) ? value.dup : value
        end
        copy.merge(:enabled => enabled?(entry[:id]), :available => available?(entry[:id]), :active => active?(entry[:id]), :reason => reason(entry[:id]))
      end

      def features
        @features.keys.sort_by(&:to_s).map { |id| feature(id) }
      end

      def debug_only?(id)
        entry = @features[normalize_id(id)]
        !!entry && entry[:classification] == :debug_only
      end

      private

      def set_override(id, value, scope)
        key = require_feature(id)
        case scope.to_sym
        when :session then @session_overrides[key] = !!value
        when :save
          raise "Reloaded save data is unavailable." unless defined?(Reloaded::SaveData)
          Reloaded::SaveData.set(SAVE_SYSTEM, key, !!value, :section => :systems)
        when :global
          raise "Reloaded settings are unavailable." unless defined?(Reloaded::Settings)
          Reloaded::Settings.set(global_key(key), value ? "On" : "Off")
        else
          raise ArgumentError, "Unknown feature scope: #{scope}"
        end
        active?(key)
      end

      def require_feature(id)
        key = normalize_id(id)
        raise "Feature is not registered: #{key}" unless @features.key?(key)
        key
      end

      def save_override(key)
        return nil unless defined?(Reloaded::SaveData)
        value = Reloaded::SaveData.get(SAVE_SYSTEM, key, nil, :section => :systems)
        value.nil? ? nil : !!value
      rescue
        nil
      end

      def global_override(key)
        return nil unless defined?(Reloaded::Settings)
        value = Reloaded::Settings.get(global_key(key), "Default").to_s.strip.downcase
        return true if ["on", "true", "1", "yes", "enabled"].include?(value)
        return false if ["off", "false", "0", "no", "disabled"].include?(value)
        nil
      rescue
        nil
      end

      def global_key(key)
        "feature.#{key}"
      end

      def developer?
        return true if defined?($DEBUG) && $DEBUG
        defined?(Reloaded::ModManager) && Reloaded::ModManager.moddev_enabled?
      rescue
        false
      end

      def normalize_ids(values)
        Array(values).map { |value| normalize_id(value) }.reject { |value| value.to_s.empty? }.uniq
      end

      def normalize_id(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "").to_sym
      end

      def truthy?(value)
        value == true || ["1", "true", "on", "yes", "enabled"].include?(value.to_s.strip.downcase)
      end

      def titleize(value)
        value.to_s.split("_").map { |part| part[0, 1].upcase + part[1..-1].to_s }.join(" ")
      end
    end

    STABLE_FEATURES = {
      :modded_content => [:mod_manager],
      :pause_menu => [:save_data],
      :tm_vault => [:save_data],
      :reloaded_mart => [:save_data, :events, :assets],
      :overworld_menu => [:save_data],
      :pc_module => [:save_data],
      :poke_vial => [:save_data],
      :iv_boundaries => [:save_data],
      :reloaded_ui => [],
      :hidden_power => [],
      :fusion_support => [],
      :reloaded_bag => [:save_data]
    }.freeze

    STABLE_FEATURES.each do |id, required_systems|
      register(id, :default => true, :classification => :stable, :required_systems => required_systems)
    end
    register(:debug_validation, :default => true, :classification => :debug_only)
  end
end
