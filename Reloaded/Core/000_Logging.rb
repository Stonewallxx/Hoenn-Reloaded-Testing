#======================================================
# Reloaded Logging
# Author: Stonewall
#======================================================
# Central logging system for the Hoenn Reloaded fork.
#
# Responsibilities:
#   - Create and manage Reloaded/Logging log files.
#   - Write framework, mod, and co-op log messages.
#   - Support Player and Developer log modes.
#   - Write structured [REPORT] blocks for failures.
#   - Keep logging failures from crashing the game.
#
#======================================================

begin
  require "json"
rescue Exception
end

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

    AVAILABLE_MODES = [:player, :developer].freeze

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

    SEVERE_LOG_MARKERS = ["[ERROR]", "[Critical]", "[FATAL]"].freeze
    BUG_REPORT_SEVERE_LEVELS = [:error, :critical, :fatal].freeze
    BUG_REPORT_DUPLICATE_WINDOW_SECONDS = 3.0

    BUG_REPORT_COUNT_MARKERS = {
      :warning => "[Warning]",
      :error => "[ERROR]",
      :critical => "[Critical]",
      :fatal => "[FATAL]"
    }.freeze

    BUG_REPORT_LOG_SOURCES = [
      [MAIN_LOG, "Log.txt"],
      [MODS_LOG, "Mods.txt"],
      [COOP_LOG, "Coop.txt"]
    ].freeze

    @counts = Hash.new(0)
    @mode = nil
    @once_keys = {}
    @bug_report_exporting = false
    @bug_report_refresh_suppressed = false
    @last_bug_report_signature = nil
    @last_bug_report_at = 0.0

    class << self
      def mode
        @mode ||= read_mode
      end

      def mode=(value)
        @mode = normalize_mode(value)
      end

      def set_mode(value, persist: true)
        previous_mode = mode
        self.mode = value
        Reloaded::Settings.set("logging_mode", mode_label) if persist && defined?(Reloaded::Settings)
        info("Log Mode changed to #{mode_label}", :framework) if previous_mode != mode
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
        false
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
        refresh_bug_report_for_failure(line, normalized_level)
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
        first_line = nil
        @bug_report_refresh_suppressed = true
        begin
          first_line = write(channel, "#{message}: #{error.class}: #{error}", level: normalized_level)
          short_backtrace(error).each { |line| write(channel, "  #{line}", level: normalized_level) }
        ensure
          @bug_report_refresh_suppressed = false
        end
        refresh_bug_report_for_failure(first_line, normalized_level) if first_line
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

      def export_bug_report(extra_fields = {}, log_export = true)
        ensure_dirs
        @bug_report_exporting = true
        lines = []
        lines << "[BUG REPORT]"
        lines << "Game Title: #{game_title}"
        lines << "Base Version: #{base_version}"
        lines << "Reloaded Version: #{reloaded_version}"
        lines << "Log Mode: #{mode_label}"
        lines << "Timestamp: #{Time.now}"
        lines << "Operating System: #{operating_system}"
        lines << "Debug Mode: #{debug_mode_label}"
        lines << "ModDev: #{moddev_label}"
        extra_fields.each { |key, value| lines << "#{labelize(key)}: #{sanitize_text(value)}" }
        lines << ""
        lines << "[MOD STATE]"
        lines.concat(mod_state_lines)
        lines << ""
        lines << "[COUNTS]"
        report_counts = bug_report_log_counts
        [:warning, :error, :critical, :fatal].each do |level|
          lines << "#{LEVEL_LABELS[level]}: #{report_counts[level]}"
        end
        lines << ""
        lines << "[ERRORS / CRITICAL / FATAL]"
        lines.concat(extract_severe_log_lines)
        lines << ""
        lines << "[REPORTS]"
        lines.concat(extract_report_blocks)
        lines << "[/BUG REPORT]"
        File.open(BUG_REPORT, "w") { |f| f.puts(sanitize_text(lines.join("\n"))) }
        info("Bug report exported: #{BUG_REPORT}", :framework) if log_export
        BUG_REPORT
      rescue
        nil
      ensure
        @bug_report_exporting = false
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
        when "bug", "bug_report", "bug_report_mode" then :developer
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

      def refresh_bug_report_for_failure(line, level)
        return unless BUG_REPORT_SEVERE_LEVELS.include?(level)
        return if @bug_report_exporting
        return if @bug_report_refresh_suppressed
        now = Time.now.to_f
        signature = sanitize_text(line).sub(/\A\[\d{2}:\d{2}:\d{2}\]\s*/, "")
        if signature == @last_bug_report_signature &&
           (now - @last_bug_report_at) < BUG_REPORT_DUPLICATE_WINDOW_SECONDS
          return
        end
        @last_bug_report_signature = signature
        @last_bug_report_at = now
        export_bug_report({}, false)
      rescue
        nil
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
        temp_roots = [ENV["TEMP"], ENV["TMP"]].compact.map { |path| File.expand_path(path).gsub("\\", "/") }.uniq
        replacements = [[game_root, ""], [reloaded_root, "/Reloaded"]]
        temp_roots.each { |root| replacements << [root, "/Temp"] }
        replacements.each do |root, replacement|
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
        version = (Reloaded.version rescue nil).to_s.strip
        return version unless version.empty?
        path = File.join(ROOT, "Version.md")
        version = File.exist?(path) ? File.read(path).to_s.strip : ""
        return version unless version.empty?
        "unknown"
      rescue
        "unknown"
      end

      def operating_system
        os = (ENV["OS"] rescue nil).to_s.strip
        platform = (RUBY_PLATFORM rescue "").to_s.strip
        host = (RbConfig::CONFIG["host_os"] rescue "").to_s.strip
        probe = [os, platform, host, os_release_text].join(" ").downcase
        return "Steam Deck" if steam_deck_environment?(probe)
        return "Windows" if probe =~ /windows|mswin|mingw|cygwin/
        return "Linux" if probe.include?("linux")
        "Other"
      rescue
        "Other"
      end

      def os_release_text
        path = "/etc/os-release"
        File.exist?(path) ? File.read(path).to_s : ""
      rescue
        ""
      end

      def steam_deck_environment?(probe)
        return true if ["SteamDeck", "STEAM_DECK", "SteamOS"].any? { |key| truthy_setting?(ENV[key]) rescue false }
        probe.include?("steamos") || probe.include?("steam deck") || probe.include?("valve")
      rescue
        false
      end

      def debug_mode_label
        (defined?($DEBUG) && $DEBUG) ? "ON" : "OFF"
      rescue
        "OFF"
      end

      def moddev_label
        enabled = if defined?(Reloaded::ModManager)
                    Reloaded::ModManager.moddev_enabled?
                  elsif defined?(Reloaded::Settings)
                    Reloaded::Settings.bool("moddev", false)
                  else
                    truthy_setting?(settings_value("moddev", "Off"))
                  end
        enabled ? "ON" : "OFF"
      rescue
        "OFF"
      end

      def mod_state_lines
        lines = []
        lines << "Active Profile: #{active_profile_label}"
        lines << "Enabled Mods:"
        enabled_mod_lines.each { |line| lines << line }
        lines << "Disabled Mods:"
        disabled_mod_lines.each { |line| lines << line }
        lines << ""
        lines << "[MODS FOLDER]"
        lines.concat(folder_manifest_lines(File.join(GAME_ROOT, "Mods")))
        lines << ""
        lines << "[MODDEV FOLDER]"
        lines.concat(folder_manifest_lines(File.join(GAME_ROOT, "ModDev")))
        lines
      rescue
        ["Could not extract mod state."]
      end

      def active_profile_label
        return Reloaded::Profiles.active_name if defined?(Reloaded::Profiles)
        return Reloaded::ModManager.profile_summary[:name] if defined?(Reloaded::ModManager)
        settings_value("active_profile", "None")
      rescue
        "unknown"
      end

      def enabled_mod_lines
        rows = if defined?(Reloaded::ModManager)
                 Reloaded::ModManager.mod_rows
               else
                 []
               end
        return fallback_enabled_mod_lines if rows.empty?
        enabled = rows.select { |row| row[:enabled] || row[:profile_enabled] }
        mod_row_lines(enabled)
      rescue
        ["- Could not extract enabled mods."]
      end

      def disabled_mod_lines
        rows = if defined?(Reloaded::ModManager)
                 Reloaded::ModManager.mod_rows
               else
                 []
               end
        return fallback_disabled_mod_lines if rows.empty?
        disabled = rows.select { |row| !row[:enabled] || row[:profile_disabled] }
        mod_row_lines(disabled)
      rescue
        ["- Could not extract disabled mods."]
      end

      def mod_row_lines(rows)
        return ["- None"] if rows.empty?
        order = mod_load_order
        rows.sort_by do |row|
          id = row[:id].to_s
          index = order.index(id)
          [index || 9999, row[:name].to_s.downcase, id]
        end.map.with_index(1) do |row, index|
          id = row[:id].to_s
          name = row[:name].to_s.empty? ? id : row[:name].to_s
          version = row[:version].to_s.empty? ? "unknown" : row[:version].to_s
          source = row[:moddev] ? "ModDev" : "Mods"
          "#{index}. #{name} (#{id}) v#{version} - #{source}"
        end
      end

      def mod_load_order
        return Reloaded::Profiles.load_order if defined?(Reloaded::Profiles)
        normalize_report_array(active_profile_data["load_order"])
      rescue
        []
      end

      def fallback_enabled_mod_lines
        profile = active_profile_data
        fallback_mod_id_lines(normalize_report_array(profile["enabled_mods"]))
      rescue
        ["- Could not extract enabled mods."]
      end

      def fallback_disabled_mod_lines
        profile = active_profile_data
        fallback_mod_id_lines(normalize_report_array(profile["disabled_mods"]))
      rescue
        ["- Could not extract disabled mods."]
      end

      def fallback_mod_id_lines(ids)
        return ["- None"] if ids.empty?
        order = normalize_report_array(active_profile_data["load_order"])
        manifests = manifest_index_by_id
        ids.sort_by do |id|
          index = order.index(id)
          [index || 9999, id]
        end.map.with_index(1) do |id, index|
          entry = manifests[id] || {}
          name = entry["name"].to_s.empty? ? id : entry["name"].to_s
          version = entry["version"].to_s.empty? ? "unknown" : entry["version"].to_s
          source = entry["source"].to_s.empty? ? "unknown" : entry["source"].to_s
          "#{index}. #{name} (#{id}) v#{version} - #{source}"
        end
      rescue
        ["- Could not extract mods."]
      end

      def active_profile_data
        name = active_profile_label
        path = File.join(GAME_ROOT, "Mods", "Reloaded", "Profiles", "#{safe_profile_filename(name)}.json")
        return parse_manifest_json(path) if File.exist?(path)
        {}
      rescue
        {}
      end

      def safe_profile_filename(name)
        name.to_s.gsub(/[\\\/:\*\?"<>\|]/, "_")
      end

      def settings_value(key, fallback = "")
        path = File.join(ROOT, "Settings.txt")
        return fallback unless File.exist?(path)
        prefix = "#{key}="
        line = File.readlines(path).find { |value| value.to_s.strip.start_with?(prefix) }
        return fallback unless line
        line.split("=", 2)[1].to_s.strip
      rescue
        fallback
      end

      def truthy_setting?(value)
        ["1", "true", "yes", "on", "enabled"].include?(value.to_s.strip.downcase)
      end

      def normalize_report_array(value)
        Array(value).map { |item| item.to_s.strip }.reject { |item| item.empty? }.uniq
      end

      def manifest_index_by_id
        index = {}
        [
          [File.join(GAME_ROOT, "Mods"), "Mods"],
          [File.join(GAME_ROOT, "ModDev"), "ModDev"]
        ].each do |root, source|
          next unless Dir.exist?(root)
          Dir.entries(root).sort.each do |folder_name|
            next if folder_name == "." || folder_name == ".."
            manifest = File.join(root, folder_name, "mod.json")
            next unless File.exist?(manifest)
            data = parse_manifest_json(manifest)
            id = data["id"].to_s
            next if id.empty?
            data = data.dup
            data["source"] = source
            index[id] = data
          end
        end
        index
      rescue
        {}
      end

      def folder_manifest_lines(folder)
        path = File.expand_path(folder.to_s)
        return ["Folder not found: #{sanitize_text(path)}"] unless Dir.exist?(path)
        folders = Dir.entries(path).sort.select do |name|
          next false if name == "." || name == ".."
          next false if report_folder_excluded?(path, name)
          File.directory?(File.join(path, name))
        end
        return ["No folders found."] if folders.empty?
        folders.map { |name| folder_manifest_line(path, name) }
      rescue
        ["Could not list folder: #{sanitize_text(folder)}"]
      end

      def folder_manifest_line(root, folder_name)
        folder = File.join(root, folder_name)
        manifest = File.join(folder, "mod.json")
        return "- #{folder_name}: no mod.json" unless File.exist?(manifest)
        data = parse_manifest_json(manifest)
        id = data["id"].to_s
        name = data["name"].to_s
        version = data["version"].to_s
        game = data["game"].to_s
        parts = []
        parts << "id=#{id.empty? ? "missing" : id}"
        parts << "name=#{name.empty? ? "missing" : name}"
        parts << "version=#{version.empty? ? "missing" : version}"
        parts << "game=#{game.empty? ? "missing" : game}"
        "- #{folder_name}: #{parts.join(", ")}"
      rescue Exception => e
        "- #{folder_name}: unreadable mod.json (#{sanitize_text(e.message)})"
      end

      def report_folder_excluded?(root, folder_name)
        mods_root = File.expand_path(File.join(GAME_ROOT, "Mods"))
        return false unless File.expand_path(root.to_s).casecmp(mods_root).zero?
        return true if folder_name.to_s.downcase == "reloaded"
        return true if folder_name.to_s.downcase == ".reloadedpendingdelete"
        File.exist?(File.join(root, folder_name, soft_uninstall_marker_name))
      rescue
        false
      end

      def soft_uninstall_marker_name
        if defined?(Reloaded::ModManager::UNINSTALLED_MARKER)
          Reloaded::ModManager::UNINSTALLED_MARKER
        else
          ".ReloadedUninstalled"
        end
      end

      def parse_manifest_json(path)
        raise "JSON parser is not available" unless defined?(JSON)
        data = JSON.parse(File.read(path))
        data.is_a?(Hash) ? data : {}
      end

      def extract_report_blocks
        return ["No Log.txt found."] unless File.exist?(MAIN_LOG)
        text = File.read(MAIN_LOG)
        reports = text.scan(/\[REPORT\].*?\[\/REPORT\]/m)
        return ["No structured Reloaded::Log.report blocks found. Errors above were collected from current logs."] if reports.empty?
        reports.flat_map { |report| report.split(/\r?\n/) + [""] }
      rescue
        ["Could not extract reports."]
      end

      def extract_severe_log_lines
        found = []
        index = {}
        bug_report_log_sources.each do |path, label|
          File.readlines(path).each do |line|
            text = sanitize_text(line).strip
            next if text.empty?
            next unless SEVERE_LOG_MARKERS.any? { |marker| text.include?(marker) }
            key = "#{label}|#{text}"
            if index.has_key?(key)
              found[index[key]][:count] += 1
            else
              index[key] = found.length
              found << { :label => label, :text => text, :count => 1 }
            end
          end
        end
        return ["No Error/Critical/Fatal log lines found."] if found.empty?
        found.map do |row|
          suffix = row[:count] > 1 ? " (x#{row[:count]})" : ""
          "#{row[:label]}: #{row[:text]}#{suffix}"
        end
      rescue
        ["Could not extract Error/Critical/Fatal log lines."]
      end

      def bug_report_log_counts
        counts = Hash.new(0)
        bug_report_log_sources.each do |path, _label|
          File.readlines(path).each do |line|
            text = sanitize_text(line)
            BUG_REPORT_COUNT_MARKERS.each do |level, marker|
              counts[level] += 1 if text.include?(marker)
            end
          end
        end
        counts
      rescue
        @counts
      end

      def bug_report_log_sources
        return [[MAIN_LOG, "Log.txt"]] if File.exist?(MAIN_LOG)
        BUG_REPORT_LOG_SOURCES.select { |path, _label| File.exist?(path) }
      end
    end
  end
end
