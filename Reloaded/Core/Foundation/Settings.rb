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
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    SETTINGS_FILE = File.join(ROOT, "Settings.txt")

    DEFAULTS = {
      "logging_mode" => "Developer",
      "moddev" => "Off",
      "active_profile" => "Default",
      "platform_override" => "Auto"
    }.freeze
    ENUM_VALUES = {
      "logging_mode" => { "player" => "Player", "developer" => "Developer" },
      "moddev" => { "off" => "Off", "on" => "On" },
      "platform_override" => {
        "auto" => "Auto",
        "windows" => "Windows",
        "proton" => "Proton",
        "joiplay" => "JoiPlay"
      }
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
        normalized = normalize_key(key)
        next_value = normalize_value(normalized, value)
        changed = @values[normalized] != next_value
        @values[normalized] = next_value
        save! if persist && changed
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
        temp_file = "#{SETTINGS_FILE}.tmp"
        File.open(temp_file, "w") do |file|
          file.puts "# Reloaded Settings"
          file.puts "# Format: key=value"
          @values.keys.sort.each { |key| file.puts "#{key}=#{@values[key]}" }
        end
        begin
          File.rename(temp_file, SETTINGS_FILE)
        rescue SystemCallError
          backup_file = "#{SETTINGS_FILE}.bak"
          File.delete(backup_file) if File.exist?(backup_file)
          File.rename(SETTINGS_FILE, backup_file) if File.exist?(SETTINGS_FILE)
          begin
            File.rename(temp_file, SETTINGS_FILE)
            File.delete(backup_file) if File.exist?(backup_file)
          rescue Exception
            File.rename(backup_file, SETTINGS_FILE) if File.exist?(backup_file) && !File.exist?(SETTINGS_FILE)
            raise
          end
        end
        true
      rescue Exception => e
        File.delete(temp_file) rescue nil if defined?(temp_file) && temp_file
        Reloaded::Log.exception("Failed to save Reloaded settings", e, channel: :framework) if defined?(Reloaded::Log)
        false
      end

      private

      def read_file
        File.readlines(SETTINGS_FILE).each_with_index do |line, index|
          stripped = line.strip
          next if stripped.empty? || stripped.start_with?("#")
          key, value = stripped.split("=", 2)
          if key.nil? || value.nil? || normalize_key(key).empty?
            log_invalid_line(index + 1)
            next
          end
          normalized_key = normalize_key(key)
          @values[normalized_key] = normalize_value(normalized_key, value)
        end
      end

      def normalize_key(key)
        key.to_s.strip.downcase
      end

      def normalize_value(key, value)
        text = value.to_s.strip
        if ENUM_VALUES.has_key?(key)
          normalized = ENUM_VALUES[key][text.downcase]
          return normalized if normalized
          log_invalid_value(key, text)
          return DEFAULTS[key]
        end
        if key == "active_profile"
          return text unless text.empty?
          log_invalid_value(key, text)
          return DEFAULTS[key]
        end
        text
      end

      def log_invalid_line(line_number)
        return unless defined?(Reloaded::Log)
        message = "Ignored malformed Settings.txt line #{line_number}"
        if Reloaded::Log.respond_to?(:warning_once)
          Reloaded::Log.warning_once(message, :framework, key: "settings_line:#{line_number}")
        else
          Reloaded::Log.warning(message, :framework)
        end
      end

      def log_invalid_value(key, value)
        return unless defined?(Reloaded::Log)
        message = "Invalid Reloaded setting #{key}=#{value.inspect}; using #{DEFAULTS[key].inspect}"
        if Reloaded::Log.respond_to?(:warning_once)
          Reloaded::Log.warning_once(message, :framework, key: "settings_value:#{key}:#{value}")
        else
          Reloaded::Log.warning(message, :framework)
        end
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
