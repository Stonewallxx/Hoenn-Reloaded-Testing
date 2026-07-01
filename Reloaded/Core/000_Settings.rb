#======================================================
# Reloaded Settings
# Author: Stonewall
#======================================================
# Central file-backed settings for the Hoenn Reloaded fork.
#
# Responsibilities:
#   - Read and write Reloaded/Settings.txt.
#   - Provide simple typed helpers for Reloaded systems.
#   - Keep global Reloaded settings out of one-off files.
#
#======================================================

module Reloaded
  module Settings
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), ".."))
    SETTINGS_FILE = File.join(ROOT, "Settings.txt")

    DEFAULTS = {
      "logging_mode" => "Developer",
      "moddev" => "Off",
      "active_profile" => "Default"
    }.freeze

    @values = nil

    class << self
      def get(key, default = nil)
        load!
        normalized = normalize_key(key)
        @values.has_key?(normalized) ? @values[normalized] : default
      end

      def set(key, value, persist: true)
        load!
        @values[normalize_key(key)] = value.to_s
        save! if persist
        value
      rescue Exception => e
        Reloaded::Log.exception("Failed to set Reloaded setting #{key}", e, channel: :framework) if defined?(Reloaded::Log)
        value
      end

      def bool(key, default = false)
        value = get(key, default ? "On" : "Off")
        truthy?(value)
      end

      def set_bool(key, value, persist: true)
        set(key, truthy?(value) ? "On" : "Off", persist: persist)
        truthy?(value)
      end

      def all
        load!
        @values.dup
      end

      def reload!
        @values = nil
        load!
      end

      def load!
        return @values if @values
        @values = DEFAULTS.dup
        read_file if File.exist?(SETTINGS_FILE)
        @values
      rescue Exception => e
        Reloaded::Log.exception("Failed to load Reloaded settings", e, channel: :framework) if defined?(Reloaded::Log)
        @values ||= DEFAULTS.dup
      end

      def save!
        load!
        File.open(SETTINGS_FILE, "w") do |file|
          file.puts "# Reloaded Settings"
          file.puts "# Format: key=value"
          @values.keys.sort.each { |key| file.puts "#{key}=#{@values[key]}" }
        end
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to save Reloaded settings", e, channel: :framework) if defined?(Reloaded::Log)
        false
      end

      private

      def read_file
        File.readlines(SETTINGS_FILE).each do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.start_with?("#")
          key, value = stripped.split("=", 2)
          next if key.nil? || value.nil?
          @values[normalize_key(key)] = value.strip
        end
      end

      def normalize_key(key)
        key.to_s.strip.downcase
      end

      def truthy?(value)
        case value.to_s.strip.downcase
        when "1", "true", "on", "yes", "enabled", "enable" then true
        else false
        end
      end
    end
  end
end
