#======================================================
# Reloaded Logging
# Author: Stonewall
#======================================================
# Central logging system for the Hoenn Reloaded fork.
#
# Responsibilities:
#   - Create and manage Reloaded/Logging log files.
#   - Write framework, mod, and co-op log messages.
#   - Support Player, Developer, and Bug Report log modes.
#   - Write structured [REPORT] blocks for failures.
#   - Keep logging failures from crashing the game.
#
#======================================================

module Reloaded
  module Log
    ROOT          = File.expand_path(File.join(File.dirname(__FILE__), ".."))
    GAME_ROOT     = File.expand_path(File.join(ROOT, ".."))
    LOG_DIR       = File.join(ROOT, "Logging")
    REPORT_DIR    = File.join(LOG_DIR, "Reports")
    MAIN_LOG      = File.join(LOG_DIR, "Log.txt")
    MODS_LOG      = File.join(LOG_DIR, "Mods.txt")
    COOP_LOG      = File.join(LOG_DIR, "Coop.txt")
    BUG_REPORT    = File.join(LOG_DIR, "LatestBugReport.txt")

    AVAILABLE_MODES = [:player, :developer, :bug_report].freeze

    CHANNEL_FILES = {
      :main => MAIN_LOG,
      :framework => MAIN_LOG,
      :bootstrap => MAIN_LOG,
      :events => MAIN_LOG,
      :patches => MAIN_LOG,
      :save_data => MAIN_LOG,
      :assets => MAIN_LOG,
      :options => MAIN_LOG,
      :mods => MODS_LOG,
      :coop => COOP_LOG
    }.freeze

    LEVEL_LABELS = {
      :debug => "DEBUG",
      :info => "INFO",
      :warning => "Warning",
      :error => "ERROR",
      :critical => "Critical",
      :fatal => "FATAL"
    }.freeze

    @counts = Hash.new(0)
    @mode = nil
    @once_keys = {}

    class << self
      def mode
        @mode ||= read_mode
      end

      def mode=(value)
        @mode = normalize_mode(value)
      end

      def set_mode(value, persist: true)
        self.mode = value
        Reloaded::Settings.set("logging_mode", mode_label) if persist && defined?(Reloaded::Settings)
        info("Log Mode changed to #{mode_label}", :framework)
        mode
      end

      def mode_label
        mode.to_s.split("_").map { |part| part[0, 1].upcase + part[1..-1].to_s }.join(" ")
      end

      def developer?
        mode == :developer
      end

      def player?
        mode == :player
      end

      def bug_report?
        mode == :bug_report
      end

      def debug(message, channel = :framework)
        return unless developer?
        write(channel, message, level: :debug)
      end

      def info(message, channel = :framework)
        write(channel, message, level: :info)
      end

      def warning(message, channel = :framework)
        write(channel, message, level: :warning)
      end

      def error(message, channel = :framework)
        write(channel, message, level: :error)
      end

      def critical(message, channel = :framework)
        write(channel, message, level: :critical)
      end

      def fatal(message, channel = :framework)
        write(channel, message, level: :fatal)
      end

      def mod(mod_id, message, level: :info)
        label = mod_id.to_s.empty? ? "unknown_mod" : mod_id.to_s
        write(:mods, "[#{label}] #{message}", level: level)
      end

      def coop(message, level: :info)
        write(:coop, message, level: level)
      end

      def write(channel, message, level: :info)
        ensure_dirs
        normalized_level = normalize_level(level)
        return nil unless write_level?(normalized_level)
        @counts[normalized_level] += 1
        line = format_line(channel, message, normalized_level)
        append(channel_file(channel), line)
        append(MAIN_LOG, line) if [:mods, :coop].include?(channel.to_sym)
        line
      rescue
        nil
      end

      def write_once(channel, message, level: :info, key: nil)
        normalized_level = normalize_level(level)
        once_key = key || [channel.to_s, normalized_level.to_s, sanitize_text(message)].join("|")
        return nil if @once_keys[once_key]
        @once_keys[once_key] = true
        write(channel, message, level: normalized_level)
      rescue
        nil
      end

      def debug_once(message, channel = :framework, key: nil)
        return unless developer?
        write_once(channel, message, level: :debug, key: key)
      end

      def info_once(message, channel = :framework, key: nil)
        write_once(channel, message, level: :info, key: key)
      end

      def warning_once(message, channel = :framework, key: nil)
        write_once(channel, message, level: :warning, key: key)
      end

      def error_once(message, channel = :framework, key: nil)
        write_once(channel, message, level: :error, key: key)
      end

      def critical_once(message, channel = :framework, key: nil)
        write_once(channel, message, level: :critical, key: key)
      end

      def exception(message, error, channel: :framework, level: :error)
        normalized_level = normalize_level(level)
        write(channel, "#{message}: #{error.class}: #{error}", level: normalized_level)
        short_backtrace(error).each { |line| write(channel, "  #{line}", level: normalized_level) }
      rescue
        nil
      end

      def report(fields = {})
        ensure_dirs
        type = fields[:type] || fields["type"] || "Failure"
        level = normalize_level(fields[:level] || fields["level"] || :critical)
        lines = []
        lines << "[REPORT]"
        lines << "Type: #{type}"
        append_field(lines, fields, :mod_id, "Mod ID")
        append_field(lines, fields, :mod_name, "Mod Name")
        append_field(lines, fields, :version, "Version")
        lines << "Error Type: [#{LEVEL_LABELS[level]}]"
        append_field(lines, fields, :file_path, "File Path")
        append_field(lines, fields, :dependency_status, "Dependency Status")
        append_field(lines, fields, :recommended_fix, "Recommended Fix")
        if fields[:stack_trace] || fields["stack_trace"]
          lines << "Stack Trace:"
          Array(fields[:stack_trace] || fields["stack_trace"]).each { |line| lines << "  #{sanitize_text(line)}" }
        elsif fields[:error] || fields["error"]
          err = fields[:error] || fields["error"]
          lines << "Stack Trace:"
          short_backtrace(err).each { |line| lines << "  #{line}" }
        end
        lines << "[/REPORT]"
        append(MAIN_LOG, lines.join("\n"))
        write(:main, "Report written: #{type}", level: level)
      rescue
        nil
      end

      def summary(fields = {})
        lines = []
        lines << "[SUMMARY]"
        fields.each { |key, value| lines << "#{labelize(key)}: #{value}" }
        lines << "Warnings: #{@counts[:warning]}"
        lines << "Errors: #{@counts[:error]}"
        lines << "Critical: #{@counts[:critical]}"
        lines << "Fatal: #{@counts[:fatal]}"
        lines << "[/SUMMARY]"
        append(MAIN_LOG, lines.join("\n"))
      rescue
        nil
      end

      def export_bug_report(extra_fields = {})
        ensure_dirs
        lines = []
        lines << "[BUG REPORT]"
        lines << "Game Title: #{game_title}"
        lines << "Base Version: #{base_version}"
        lines << "Reloaded Version: #{reloaded_version}"
        lines << "Log Mode: #{mode_label}"
        lines << "Timestamp: #{Time.now}"
        extra_fields.each { |key, value| lines << "#{labelize(key)}: #{sanitize_text(value)}" }
        lines << ""
        lines << "[COUNTS]"
        [:warning, :error, :critical, :fatal].each do |level|
          lines << "#{LEVEL_LABELS[level]}: #{@counts[level]}"
        end
        lines << ""
        lines << "[RECENT REPORTS]"
        lines.concat(extract_recent_reports)
        lines << "[/BUG REPORT]"
        File.open(BUG_REPORT, "w") { |f| f.puts(sanitize_text(lines.join("\n"))) }
        info("Bug report exported: #{BUG_REPORT}", :framework)
        BUG_REPORT
      rescue
        nil
      end

      def boot_header
        info("Game Title: #{game_title}", :bootstrap)
        info("Base Version: #{base_version}", :bootstrap)
        info("Reloaded Version: #{reloaded_version}", :bootstrap)
        info("Log Mode: #{mode_label}", :bootstrap)
        info("Timestamp: #{Time.now}", :bootstrap)
      rescue
        nil
      end

      def counts
        @counts.dup
      end

      def reset_counts
        @counts = Hash.new(0)
      end

      def reset_once_keys
        @once_keys = {}
      end

      def sanitize(value)
        sanitize_text(value)
      end

      private

      def ensure_dirs
        Dir.mkdir(LOG_DIR) unless Dir.exist?(LOG_DIR)
        Dir.mkdir(REPORT_DIR) unless Dir.exist?(REPORT_DIR)
      rescue
      end

      def read_mode
        return normalize_mode(Reloaded::Settings.get("logging_mode", "Developer")) if defined?(Reloaded::Settings)
        :developer
      rescue
        :developer
      end

      def normalize_mode(value)
        case value.to_s.strip.downcase.gsub("-", "_").gsub(" ", "_")
        when "player", "player_mode" then :player
        when "bug", "bug_report", "bug_report_mode" then :bug_report
        else :developer
        end
      end

      def write_level?(level)
        return false if level == :debug && !developer?
        true
      end

      def normalize_level(level)
        key = level.to_s.strip.downcase.to_sym
        LEVEL_LABELS.key?(key) ? key : :info
      end

      def channel_file(channel)
        CHANNEL_FILES[channel.to_sym] || MAIN_LOG
      rescue
        MAIN_LOG
      end

      def format_line(channel, message, level)
        "[#{timestamp}] [#{LEVEL_LABELS[level]}] [#{channel}] #{sanitize_text(message)}"
      end

      def timestamp
        Time.now.strftime("%H:%M:%S")
      end

      def append(path, text)
        File.open(path, "a") { |f| f.puts(sanitize_text(text)) }
      rescue
      end

      def short_backtrace(error)
        (error.backtrace || []).first(8).map { |line| sanitize_text(line) }
      rescue
        []
      end

      def append_field(lines, fields, key, label)
        value = fields[key] || fields[key.to_s]
        lines << "#{label}: #{sanitize_text(value)}" unless value.nil? || value.to_s.empty?
      end

      def sanitize_text(value)
        text = value.to_s.gsub("\\", "/")
        game_root = File.expand_path(GAME_ROOT).gsub("\\", "/")
        reloaded_root = File.expand_path(ROOT).gsub("\\", "/")
        [[game_root, ""], [reloaded_root, "/Reloaded"]].each do |root, replacement|
          next if root.empty?
          text = text.gsub(/#{Regexp.escape(root)}(?=\/|\z)/i, replacement)
        end
        text
      rescue
        value.to_s
      end

      def labelize(key)
        key.to_s.split("_").map { |part| part[0, 1].upcase + part[1..-1].to_s }.join(" ")
      end

      def game_title
        if File.exist?("Game.ini")
          line = File.read("Game.ini").split(/\r?\n/).find { |l| l =~ /^Title=/ }
          return line.split("=", 2)[1] if line
        end
        "unknown"
      rescue
        "unknown"
      end

      def base_version
        path = File.join(ROOT, "BaseVersion.md")
        File.exist?(path) ? File.read(path).to_s.strip : "unknown"
      rescue
        "unknown"
      end

      def reloaded_version
        Reloaded::VERSION rescue "unknown"
      end

      def extract_recent_reports
        return ["No Log.txt found."] unless File.exist?(MAIN_LOG)
        text = File.read(MAIN_LOG)
        reports = text.scan(/\[REPORT\].*?\[\/REPORT\]/m).last(3)
        return ["No reports found."] if reports.empty?
        reports.flat_map { |report| report.split(/\r?\n/) + [""] }
      rescue
        ["Could not extract reports."]
      end
    end
  end
end
