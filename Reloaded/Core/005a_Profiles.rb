#======================================================
# Reloaded Profiles
# Author: Stonewall
#======================================================
# File-backed Mod Manager profiles.
#
# Responsibilities:
#   - Store and load profiles from Mods/Reloaded/Profiles.
#   - Track the active profile through Reloaded settings.
#   - Provide enabled mod and load order data to the Mod Manager.
#   - Create a default profile when none exists.
#
#======================================================

begin
  require "json"
rescue Exception
end

module Reloaded
  module Profiles
    PROFILE_ROOT = File.expand_path("./Mods/Reloaded/Profiles")
    DEFAULT_PROFILE_NAME = "Default"
    PROFILE_VERSION = 1

    @active_profile = nil
    @booted = false

    class << self
      def boot
        return true if @booted
        @booted = true
        ensure_profile_root
        ensure_default_profile
        load_active_profile
        Reloaded::Log.info("Loaded active mod profile: #{active_name}", :mods) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Profile boot failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def active_name
        name = if defined?(Reloaded::Settings)
                 Reloaded::Settings.get("active_profile", DEFAULT_PROFILE_NAME)
               else
                 DEFAULT_PROFILE_NAME
               end
        normalize_profile_name(name)
      end

      def set_active(name, persist: true)
        normalized = normalize_profile_name(name)
        Reloaded::Settings.set("active_profile", normalized, persist: persist) if defined?(Reloaded::Settings)
        @active_profile = load_profile(normalized)
      end

      def active
        @active_profile ||= load_active_profile
      end

      def enabled_mod_ids
        normalize_string_array(active["enabled_mods"])
      end

      def disabled_mod_ids
        normalize_string_array(active["disabled_mods"])
      end

      def load_order
        normalize_string_array(active["load_order"])
      end

      def mod_settings
        active["mod_settings"].is_a?(Hash) ? active["mod_settings"] : {}
      end

      def enabled?(mod_id)
        id = normalize_mod_id(mod_id)
        return false if disabled_mod_ids.include?(id)
        enabled_mod_ids.include?(id)
      end

      def ordered_mod_ids(available_ids)
        available = normalize_string_array(available_ids)
        ordered = load_order.select { |id| available.include?(id) }
        ordered + (available - ordered).sort
      end

      def missing_mod_ids(available_ids)
        available = normalize_string_array(available_ids)
        referenced = (enabled_mod_ids + disabled_mod_ids + load_order).uniq
        referenced - available
      end

      def ensure_profile_root
        FileUtils.mkdir_p(PROFILE_ROOT) if defined?(FileUtils)
        Dir.mkdir(File.expand_path("./Mods")) unless Dir.exist?(File.expand_path("./Mods"))
        Dir.mkdir(File.expand_path("./Mods/Reloaded")) unless Dir.exist?(File.expand_path("./Mods/Reloaded"))
        Dir.mkdir(PROFILE_ROOT) unless Dir.exist?(PROFILE_ROOT)
      end

      def ensure_default_profile
        path = profile_path(DEFAULT_PROFILE_NAME)
        return if File.exist?(path)
        write_profile(default_profile)
        Reloaded::Log.info("Created default mod profile at #{path}", :mods) if defined?(Reloaded::Log)
      end

      def load_active_profile
        @active_profile = load_profile(active_name)
      end

      def load_profile(name)
        ensure_profile_root
        normalized = normalize_profile_name(name)
        path = profile_path(normalized)
        return default_profile.merge("name" => normalized) unless File.exist?(path)
        data = parse_json(File.read(path))
        normalize_profile(data, normalized)
      rescue Exception => e
        Reloaded::Log.exception("Failed to load mod profile #{name}", e, channel: :mods) if defined?(Reloaded::Log)
        default_profile.merge("name" => normalize_profile_name(name))
      end

      def write_profile(profile)
        ensure_profile_root
        data = normalize_profile(profile, profile["name"] || DEFAULT_PROFILE_NAME)
        File.open(profile_path(data["name"]), "w") do |file|
          file.write(JSON.pretty_generate(data))
          file.write("\n")
        end
        data
      end

      def default_profile
        {
          "id" => "default",
          "name" => DEFAULT_PROFILE_NAME,
          "version" => PROFILE_VERSION,
          "enabled_mods" => [],
          "disabled_mods" => [],
          "load_order" => [],
          "mod_settings" => {},
          "notes" => "Default Reloaded mod profile."
        }
      end

      private

      def parse_json(raw)
        raise "JSON parser is not available" unless defined?(JSON)
        JSON.parse(raw)
      end

      def normalize_profile(data, fallback_name)
        source = data.is_a?(Hash) ? data : {}
        {
          "id" => normalize_mod_id(source["id"] || fallback_name),
          "name" => normalize_profile_name(source["name"] || fallback_name),
          "version" => (source["version"] || PROFILE_VERSION).to_i,
          "enabled_mods" => normalize_string_array(source["enabled_mods"]),
          "disabled_mods" => normalize_string_array(source["disabled_mods"]),
          "load_order" => normalize_string_array(source["load_order"]),
          "mod_settings" => source["mod_settings"].is_a?(Hash) ? source["mod_settings"] : {},
          "notes" => source["notes"].to_s
        }
      end

      def profile_path(name)
        File.join(PROFILE_ROOT, "#{safe_filename(name)}.json")
      end

      def normalize_profile_name(name)
        value = name.to_s.strip
        value.empty? ? DEFAULT_PROFILE_NAME : value
      end

      def safe_filename(name)
        normalize_profile_name(name).gsub(/[\\\/:\*\?"<>\|]/, "_")
      end

      def normalize_mod_id(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "")
      end

      def normalize_string_array(value)
        return [] unless value.is_a?(Array)
        value.map { |entry| normalize_mod_id(entry) }.reject { |entry| entry.empty? }.uniq
      end
    end
  end
end
