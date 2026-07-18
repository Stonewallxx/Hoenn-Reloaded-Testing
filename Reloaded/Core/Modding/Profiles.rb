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
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    PROFILE_ROOT = File.join(GAME_ROOT, "Mods", "Reloaded", "Profiles")
    DEFAULT_PROFILE_NAME = "Default"
    PROFILE_VERSION = 1

    @active_profile = nil
    @booted = false

    class << self
      def boot
        return true if @booted
        ensure_profile_root
        ensure_default_profile
        load_active_profile
        @booted = true
        Reloaded::Log.info("Loaded active mod profile: #{active_name}", :mods) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        @booted = false
        Reloaded::Log.exception("Profile boot failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def list
        ensure_profile_root
        ensure_default_profile
        Dir[File.join(PROFILE_ROOT, "*.json")].sort.map do |path|
          load_profile(File.basename(path, ".json"))
        end
      end

      def names
        list.map { |profile| profile["name"] }
      end

      def exists?(name)
        File.exist?(profile_path(name))
      end

      def create(name, notes: "", activate: false)
        normalized = normalize_profile_name(name)
        raise "Profile already exists: #{normalized}" if exists?(normalized)
        profile = default_profile.merge(
          "id" => normalize_mod_id(normalized),
          "name" => normalized,
          "notes" => notes.to_s
        )
        saved = write_profile(profile)
        log_change("Created mod profile: #{normalized}")
        set_active(normalized) if activate
        saved
      end

      def duplicate(source_name, new_name, activate: false)
        source = load_profile(source_name)
        normalized = normalize_profile_name(new_name)
        raise "Profile already exists: #{normalized}" if exists?(normalized)
        copy = normalize_profile(source, normalized)
        copy["id"] = normalize_mod_id(normalized)
        copy["name"] = normalized
        copy["notes"] = "Copied from #{source["name"]}."
        saved = write_profile(copy)
        log_change("Duplicated mod profile #{source["name"]} as #{normalized}")
        set_active(normalized) if activate
        saved
      end

      def delete(name)
        normalized = normalize_profile_name(name)
        raise "Cannot delete the default profile" if same_profile?(normalized, DEFAULT_PROFILE_NAME)
        path = profile_path(normalized)
        raise "Profile does not exist: #{normalized}" unless File.exist?(path)
        File.delete(path)
        set_active(DEFAULT_PROFILE_NAME) if same_profile?(active_name, normalized)
        log_change("Deleted mod profile: #{normalized}")
        true
      end

      def rename(old_name, new_name)
        old_normalized = normalize_profile_name(old_name)
        new_normalized = normalize_profile_name(new_name)
        raise "Cannot rename the default profile" if same_profile?(old_normalized, DEFAULT_PROFILE_NAME)
        raise "Profile does not exist: #{old_normalized}" unless exists?(old_normalized)
        raise "Profile already exists: #{new_normalized}" if exists?(new_normalized)
        profile = load_profile(old_normalized)
        old_path = profile_path(old_normalized)
        profile["id"] = normalize_mod_id(new_normalized)
        profile["name"] = new_normalized
        saved = write_profile(profile)
        File.delete(old_path) if File.exist?(old_path)
        set_active(new_normalized) if same_profile?(active_name, old_normalized)
        log_change("Renamed mod profile #{old_normalized} to #{new_normalized}")
        saved
      end

      def activate(name)
        normalized = normalize_profile_name(name)
        raise "Profile does not exist: #{normalized}" unless exists?(normalized)
        profile = set_active(normalized)
        log_change("Activated mod profile: #{normalized}")
        profile
      end

      def import_profile(path, activate: false, overwrite: false)
        source_path = path.to_s
        raise "Profile import path is required" if source_path.empty?
        raise "Profile import file does not exist: #{source_path}" unless File.exist?(source_path)
        data = parse_json(File.read(source_path))
        fallback_name = File.basename(source_path, ".json")
        saved = import_data(data, fallback_name: fallback_name, activate: activate, overwrite: overwrite)
        saved
      end

      def import_data(data, fallback_name: DEFAULT_PROFILE_NAME, activate: false, overwrite: false)
        profile = normalize_profile(data, fallback_name)
        if exists?(profile["name"]) && !overwrite
          raise "Profile already exists: #{profile["name"]}"
        end
        saved = write_profile(profile)
        set_active(saved["name"]) if activate || same_profile?(active_name, saved["name"])
        log_change("Imported mod profile #{saved["name"]}")
        saved
      end

      def export_profile(name, destination_path)
        profile = load_profile(name)
        destination = destination_path.to_s
        raise "Profile export path is required" if destination.empty?
        ensure_directory(File.dirname(destination))
        File.open(destination, "w") do |file|
          file.write(json_text(profile))
          file.write("\n")
        end
        log_change("Exported mod profile #{profile["name"]} to #{destination}")
        destination
      end

      def save_active!
        @active_profile = write_profile(active)
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

      def active(reload: false)
        if reload || @active_profile.nil? || !same_profile?(@active_profile["name"], active_name)
          load_active_profile
        end
        @active_profile
      end

      def refresh!
        load_active_profile
      end

      def enabled_mod_ids
        profile_enabled_mod_ids(active)
      end

      def disabled_mod_ids
        profile_disabled_mod_ids(active)
      end

      def load_order
        normalize_string_array(active["load_order"])
      end

      def mod_settings
        active["mod_settings"].is_a?(Hash) ? active["mod_settings"] : {}
      end

      def mod_settings_for(mod_id)
        id = normalize_mod_id(mod_id)
        settings = mod_settings[id]
        settings.is_a?(Hash) ? settings : {}
      end

      def mod_setting(mod_id, key, default = nil)
        settings = mod_settings_for(mod_id)
        settings.has_key?(key.to_s) ? settings[key.to_s] : default
      end

      def set_mod_setting(mod_id, key, value)
        id = normalize_mod_id(mod_id)
        raise "Mod id is required" if id.empty?
        profile = active
        profile["mod_settings"] = mod_settings
        profile["mod_settings"][id] = mod_settings_for(id)
        profile["mod_settings"][id][key.to_s] = value
        save_active!
        log_change("Updated setting #{key} for #{id} in profile #{active_name}")
        value
      end

      def delete_mod_setting(mod_id, key)
        id = normalize_mod_id(mod_id)
        settings = mod_settings_for(id)
        return false unless settings.has_key?(key.to_s)
        settings.delete(key.to_s)
        active["mod_settings"][id] = settings
        active["mod_settings"].delete(id) if settings.empty?
        save_active!
        log_change("Deleted setting #{key} for #{id} in profile #{active_name}")
        true
      end

      def delete_mod_settings(mod_id = nil)
        profile = active
        profile["mod_settings"] = mod_settings
        if mod_id
          id = normalize_mod_id(mod_id)
          return false unless profile["mod_settings"].has_key?(id)
          profile["mod_settings"].delete(id)
          log_change("Deleted all settings for #{id} in profile #{active_name}")
        else
          return false if profile["mod_settings"].empty?
          profile["mod_settings"] = {}
          log_change("Deleted all mod settings in profile #{active_name}")
        end
        save_active!
        true
      end

      def enabled?(mod_id)
        id = normalize_mod_id(mod_id)
        profile = active
        disabled = profile_disabled_mod_ids(profile)
        enabled = profile_enabled_mod_ids(profile)
        return false if disabled.include?(id)
        enabled.include?(id)
      end

      def enable_mod(mod_id)
        set_mod_enabled(mod_id, true)
      end

      def disable_mod(mod_id)
        set_mod_enabled(mod_id, false)
      end

      def set_mod_enabled(mod_id, enabled)
        id = normalize_mod_id(mod_id)
        raise "Mod id is required" if id.empty?
        profile = active
        enabled_mods = profile_enabled_mod_ids(profile)
        disabled_mods = profile_disabled_mod_ids(profile)
        if enabled
          enabled_mods = (enabled_mods + [id]).uniq
          disabled_mods.delete(id)
          append_to_load_order(profile, id)
        else
          disabled_mods = (disabled_mods + [id]).uniq
          enabled_mods.delete(id)
        end
        profile["enabled_mods"] = enabled_mods
        profile["disabled_mods"] = disabled_mods
        @active_profile = write_profile(profile)
        log_change("#{enabled ? 'Enabled' : 'Disabled'} #{id} in profile #{active_name}")
        @active_profile
      end

      def set_enabled_mods(mod_ids)
        active["enabled_mods"] = normalize_string_array(mod_ids)
        active["disabled_mods"] = disabled_mod_ids - active["enabled_mods"]
        active["enabled_mods"].each { |id| append_to_load_order(active, id) }
        save_active!
      end

      def set_disabled_mods(mod_ids)
        active["disabled_mods"] = normalize_string_array(mod_ids)
        active["enabled_mods"] = enabled_mod_ids - active["disabled_mods"]
        save_active!
      end

      def set_load_order(mod_ids)
        active["load_order"] = normalize_string_array(mod_ids)
        save_active!
      end

      def move_mod(mod_id, delta)
        id = normalize_mod_id(mod_id)
        raise "Mod id is required" if id.empty?
        order = load_order
        order << id unless order.include?(id)
        old_index = order.index(id)
        new_index = [[old_index + delta.to_i, 0].max, order.length - 1].min
        return active if old_index == new_index
        order.delete_at(old_index)
        order.insert(new_index, id)
        set_load_order(order)
      end

      def remove_mod(mod_id)
        id = normalize_mod_id(mod_id)
        profile = active
        profile["enabled_mods"] = enabled_mod_ids - [id]
        profile["disabled_mods"] = disabled_mod_ids - [id]
        profile["load_order"] = load_order - [id]
        profile["mod_settings"] = mod_settings
        profile["mod_settings"].delete(id)
        save_active!
        log_change("Removed #{id} references from profile #{active_name}")
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

      def profile_enabled_mod_ids(profile)
        normalize_string_array(profile && profile["enabled_mods"])
      end

      def profile_disabled_mod_ids(profile)
        normalize_string_array(profile && profile["disabled_mods"])
      end

      def profile_load_order(profile)
        normalize_string_array(profile && profile["load_order"])
      end

      def summary(name = nil)
        profile = name ? load_profile(name) : active
        {
          :id => profile["id"],
          :name => profile["name"],
          :enabled_mods => profile_enabled_mod_ids(profile).length,
          :disabled_mods => profile_disabled_mod_ids(profile).length,
          :load_order => profile_load_order(profile).length,
          :mod_settings => profile["mod_settings"].is_a?(Hash) ? profile["mod_settings"].keys.length : 0,
          :active => same_profile?(profile["name"], active_name)
        }
      end

      def ensure_profile_root
        ensure_directory(PROFILE_ROOT)
      end

      def ensure_default_profile
        path = profile_path(DEFAULT_PROFILE_NAME)
        return if File.exist?(path)
        write_profile(default_profile)
        Reloaded::Log.info("Created default mod profile at #{path}", :mods) if defined?(Reloaded::Log)
      end

      def load_active_profile
        @active_profile = load_profile(active_name)
        if defined?(Reloaded::Log)
          enabled = normalize_string_array(@active_profile["enabled_mods"]).join(",")
          disabled = normalize_string_array(@active_profile["disabled_mods"]).join(",")
          message = "Loaded active profile #{active_name} from #{PROFILE_ROOT} enabled=#{enabled} disabled=#{disabled}"
          if Reloaded::Log.respond_to?(:debug_once)
            Reloaded::Log.debug_once(message, :mods, key: "profile_loaded:#{active_name}:#{enabled}:#{disabled}")
          else
            Reloaded::Log.debug(message, :mods)
          end
        end
        @active_profile
      end

      def load_profile(name)
        ensure_profile_root
        normalized = normalize_profile_name(name)
        path = profile_path(normalized)
        unless File.exist?(path)
          Reloaded::Log.warning("Profile file missing: #{path}", :mods) if defined?(Reloaded::Log)
          return default_profile.merge("name" => normalized)
        end
        data = parse_json(File.read(path))
        if defined?(Reloaded::Log) && data.respond_to?(:keys)
          message = "Profile #{normalized} keys=#{data.keys.join(",")}"
          if Reloaded::Log.respond_to?(:debug_once)
            Reloaded::Log.debug_once(message, :mods, key: "profile_keys:#{normalized}:#{data.keys.join(",")}")
          else
            Reloaded::Log.debug(message, :mods)
          end
        end
        normalize_profile(data, normalized)
      rescue Exception => e
        Reloaded::Log.exception("Failed to load mod profile #{name}", e, channel: :mods) if defined?(Reloaded::Log)
        default_profile.merge("name" => normalize_profile_name(name))
      end

      def write_profile(profile)
        ensure_profile_root
        data = normalize_profile(profile, profile["name"] || DEFAULT_PROFILE_NAME)
        path = profile_path(data["name"])
        File.open(path, "w") do |file|
          file.write(json_text(data))
          file.write("\n")
        end
        if defined?(Reloaded::Log)
          enabled = profile_enabled_mod_ids(data).join(",")
          disabled = profile_disabled_mod_ids(data).join(",")
          Reloaded::Log.debug("Saved profile #{data["name"]} to #{path} enabled=#{enabled} disabled=#{disabled}", :mods)
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
          "notes" => "Default Reloaded mod profile.",
          "changelogurl" => ""
        }
      end

      private

      def json_text(data)
        formatted_json(data)
      end

      def formatted_json(value, indent = 0)
        pad = "  " * indent
        child_pad = "  " * (indent + 1)
        case value
        when Hash
          return "{}" if value.empty?
          lines = value.map do |key, child|
            "#{child_pad}#{JSON.generate(key.to_s)}: #{formatted_json(child, indent + 1)}"
          end
          "{\n#{lines.join(",\n")}\n#{pad}}"
        when Array
          return "[]" if value.empty?
          if value.all? { |child| scalar_json?(child) }
            "[#{value.map { |child| JSON.generate(child) }.join(", ")}]"
          else
            lines = value.map { |child| "#{child_pad}#{formatted_json(child, indent + 1)}" }
            "[\n#{lines.join(",\n")}\n#{pad}]"
          end
        else
          JSON.generate(value)
        end
      end

      def scalar_json?(value)
        value.nil? || value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
      end

      def parse_json(raw)
        raise "JSON parser is not available" unless defined?(JSON)
        stringify_json_keys(JSON.parse(raw))
      end

      def stringify_json_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, child), memo|
            memo[key.to_s] = stringify_json_keys(child)
          end
        when Array
          value.map { |child| stringify_json_keys(child) }
        else
          value
        end
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
          "notes" => source["notes"].to_s,
          "changelogurl" => source["changelogurl"].to_s
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

      def ensure_directory(path)
        target = path.to_s
        return if target.empty? || Dir.exist?(target)
        parent = File.dirname(target)
        ensure_directory(parent) if parent && parent != target && !Dir.exist?(parent)
        Dir.mkdir(target) unless Dir.exist?(target)
      end

      def append_to_load_order(profile, mod_id)
        order = normalize_string_array(profile["load_order"])
        order << mod_id unless order.include?(mod_id)
        profile["load_order"] = order
      end

      def same_profile?(left, right)
        normalize_profile_name(left).downcase == normalize_profile_name(right).downcase
      end

      def log_change(message)
        Reloaded::Log.info(message, :mods) if defined?(Reloaded::Log)
      end
    end
  end
end
