#======================================================
# Reloaded Modder Tools
# Author: Stonewall
#======================================================
# Backend utilities for in-game Mod Manager tools.
#
# Responsibilities:
#   - Open and export Reloaded log files.
#   - Back up installed mod folders to ModsBackup/.
#   - Validate and safely repair mod manifests.
#   - Generate starter mod and profile templates.
#
#======================================================

begin
  require "json"
rescue Exception
end

begin
  require "net/http"
  require "uri"
rescue Exception
end

module Reloaded
  module ModderTools
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    MODS_DIR = File.join(GAME_ROOT, "Mods")
    MODDEV_DIR = File.join(GAME_ROOT, "ModDev")
    BACKUP_DIR = File.join(GAME_ROOT, "ModsBackup")
    SEVEN_Z = File.join(GAME_ROOT, "REQUIRED_BY_INSTALLER_UPDATER", "7z.exe")
    PASTE_URL = "https://paste.rs/"
    NETWORK_TIMEOUT_SECONDS = 8

    LOG_ENTRIES = [
      ["Log.txt", File.join(ROOT, "Logging", "Log.txt")],
      ["Mods.txt", File.join(ROOT, "Logging", "Mods.txt")],
      ["Coop.txt", File.join(ROOT, "Logging", "Coop.txt")],
      ["LatestBugReport.txt", File.join(ROOT, "Logging", "LatestBugReport.txt")]
    ].freeze

    class << self
      def log_entries
        LOG_ENTRIES.map { |label, path| { :label => label, :path => path } }
      end

      def log_entry(label)
        log_entries.find { |entry| entry[:label].to_s == label.to_s }
      end

      def display_path(path)
        sanitize_text(path)
      end

      def display_text(value)
        sanitize_text(value)
      end

      def open_log(label)
        entry = log_entry(label)
        raise "Unknown log file: #{label}" unless entry
        path = ensure_log_file(entry[:path])
        open_file(path)
      end

      def export_log(label)
        entry = log_entry(label)
        raise "Unknown log file: #{label}" unless entry
        path = ensure_log_file(entry[:path])
        text = File.read(path)
        raise "#{entry[:label]} is empty." if text.to_s.strip.empty?
        url = upload_to_paste(text)
        if defined?(Reloaded::ModManagerUI)
          Reloaded::ModManagerUI.clipboard_write(url)
        end
        Reloaded::Log.info("Exported #{entry[:label]} to #{url}", :mods) if defined?(Reloaded::Log)
        url
      end

      def clear_logs
        log_entries.each do |entry|
          path = entry[:path]
          ensure_directory(File.dirname(path))
          File.open(path, "w") { |_| }
        end
        true
      end

      def backupable_mod_rows
        rows = if defined?(Reloaded::ModManager)
                 Reloaded::ModManager.refresh_metadata rescue nil
                 Reloaded::ModManager.mod_rows
               else
                 []
               end
        rows.select { |row| backupable_folder?(row[:folder_path]) }
      rescue
        []
      end

      def backup_all_mods
        backup_mod_rows(backupable_mod_rows, "AllMods")
      end

      def backup_mod_rows(rows, label = "SelectedMods")
        selected = Array(rows).select { |row| backupable_folder?(row[:folder_path]) }
        raise "No mod folders were selected." if selected.empty?
        raise "7z.exe was not found in REQUIRED_BY_INSTALLER_UPDATER/." unless File.exist?(SEVEN_Z)
        ensure_directory(BACKUP_DIR)
        stamp = Time.now.strftime("%Y%m%d_%H%M%S")
        archive = File.join(BACKUP_DIR, "#{safe_filename(label)}_#{stamp}.zip")
        rel_paths = selected.map { |row| relative_game_path(row[:folder_path]) }.compact
        raise "No valid mod folders were selected." if rel_paths.empty?
        ok = Dir.chdir(GAME_ROOT) { system(SEVEN_Z, "a", "-tzip", archive, *rel_paths) }
        raise "Backup archive could not be created." unless ok && File.exist?(archive)
        Reloaded::Log.info("Created mod backup: #{relative_game_path(archive)}", :mods) if defined?(Reloaded::Log)
        archive
      end

      def manifest_targets
        dirs = [MODS_DIR]
        dirs << MODDEV_DIR if moddev_enabled?
        dirs.each_with_object([]) do |root, list|
          next unless Dir.exist?(root)
          Dir[File.join(root, "*")].sort.each do |folder|
            next unless File.directory?(folder)
            next if same_path?(folder, File.join(MODS_DIR, "Reloaded"))
            path = File.join(folder, "mod.json")
            list << manifest_target(folder, path, root)
          end
        end
      end

      def validate_manifests
        manifest_targets.map do |target|
          validate_manifest_target(target)
        end
      end

      def fix_manifest(target)
        path = target[:manifest_path]
        folder = target[:folder_path]
        data = {}
        if File.exist?(path)
          data = parse_json(File.read(path))
          raise "Manifest root must be a JSON object." unless data.is_a?(Hash)
        end
        defaults = manifest_defaults(folder)
        defaults.each do |key, value|
          data[key] = value if missing_manifest_value?(data[key])
        end
        data["authors"] = normalize_array(data["authors"], ["Unknown"])
        data["dependencies"] = normalize_array(data["dependencies"], [])
        data["tags"] = normalize_array(data["tags"], ["Mod"])
        data["incompatible"] = normalize_array(data["incompatible"], [])
        data["changelogurl"] = data["changelogurl"].to_s
        data["id"] = normalize_mod_id(data["id"])
        data["version"] = "1.0.0" unless valid_version?(data["version"])
        data["minimum_reloaded_version"] = reloaded_version unless valid_version?(data["minimum_reloaded_version"])
        ensure_directory(folder)
        File.open(path, "w") do |file|
          file.write(formatted_json(data))
          file.write("\n")
        end
        Reloaded::Log.info("Fixed manifest: #{relative_game_path(path)}", :mods) if defined?(Reloaded::Log)
        validate_manifest_target(manifest_target(folder, path, target[:root]))
      end

      def create_mod_template(name)
        mod_name = name.to_s.strip
        raise "Template name is required." if mod_name.empty?
        folder_name = safe_folder_name(mod_name)
        folder = unique_folder(File.join(MODS_DIR, folder_name))
        ensure_directory(folder)
        ["Scripts", "Graphics", "Audio", "Fonts", "Documentation"].each do |child|
          ensure_directory(File.join(folder, child))
        end
        id = normalize_mod_id(mod_name)
        manifest = manifest_defaults(folder).merge(
          "id" => id,
          "name" => mod_name,
          "description" => "A new Hoenn Reloaded mod.",
          "tags" => ["Mod"]
        )
        write_json(File.join(folder, "mod.json"), manifest)
        write_json(File.join(folder, "Settings.json"), template_settings)
        write_text(File.join(folder, "Scripts", "001_Main.rb"), template_script(id))
        write_text(File.join(folder, "Changelog.txt"), "1.0.0\n- Initial template.\n")
        write_text(File.join(folder, "Documentation", "README.md"), "# #{mod_name}\n\nMod documentation goes here.\n")
        Reloaded::Log.info("Created mod template: #{relative_game_path(folder)}", :mods) if defined?(Reloaded::Log)
        folder
      end

      def create_profile_template(name)
        profile_name = name.to_s.strip
        raise "Profile name is required." if profile_name.empty?
        if defined?(Reloaded::Profiles)
          profile = Reloaded::Profiles.create(profile_name, notes: "Profile template.")
          path = File.join(Reloaded::Profiles::PROFILE_ROOT, "#{safe_filename(profile["name"])}.json")
          Reloaded::Log.info("Created profile template: #{relative_game_path(path)}", :mods) if defined?(Reloaded::Log)
          path
        else
          folder = File.join(MODS_DIR, "Reloaded", "Profiles")
          ensure_directory(folder)
          path = File.join(folder, "#{safe_filename(profile_name)}.json")
          raise "Profile already exists: #{profile_name}" if File.exist?(path)
          write_json(path, {
            "id" => normalize_mod_id(profile_name),
            "name" => profile_name,
            "version" => 1,
            "enabled_mods" => [],
            "disabled_mods" => [],
            "load_order" => [],
            "mod_settings" => {},
            "notes" => "Profile template.",
            "changelogurl" => ""
          })
          path
        end
      end

      private

      def ensure_log_file(path)
        if File.basename(path).downcase == "latestbugreport.txt" && defined?(Reloaded::Log)
          Reloaded::Log.export_bug_report
          return path
        end
        ensure_directory(File.dirname(path))
        File.open(path, "a") { |_| } unless File.exist?(path)
        path
      end

      def open_file(path)
        normalized = File.expand_path(path)
        raise "File does not exist: #{relative_game_path(normalized)}" unless File.exist?(normalized)
        raise "Refusing to open a file outside the game folder." unless under_path?(normalized, GAME_ROOT)
        ok = system("cmd", "/c", "start", "", normalized)
        raise "Windows could not open #{File.basename(normalized)}." unless ok
        Reloaded::Log.info("Opened file: #{relative_game_path(normalized)}", :mods) if defined?(Reloaded::Log)
        true
      end

      def upload_to_paste(text)
        return upload_to_paste_with_httplite(text) if defined?(HTTPLite)
        return upload_to_paste_with_net_http(text) if defined?(Net::HTTP) && defined?(URI)
        raise "No HTTP upload backend is available in this runtime."
      end

      def upload_to_paste_with_httplite(text)
        content = sanitize_text(text)
        response = HTTPLite.post_body(
          PASTE_URL,
          content,
          "text/plain",
          {
            "User-Agent" => "HoennReloaded/1.0",
            "Content-Length" => content.bytesize.to_s
          }
        )
        status = response.is_a?(Hash) ? response[:status].to_i : 0
        raise "Paste upload failed with HTTP #{status}." unless [200, 201, 206].include?(status)
        url = response[:body].to_s.strip
        raise "Paste upload did not return a URL." if url.empty?
        url
      end

      def upload_to_paste_with_net_http(text)
        uri = URI.parse(PASTE_URL)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "text/plain; charset=utf-8"
        request.body = sanitize_text(text)
        response = Net::HTTP.start(
          uri.host,
          uri.port,
          :use_ssl => uri.scheme == "https",
          :open_timeout => NETWORK_TIMEOUT_SECONDS,
          :read_timeout => NETWORK_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end
        code = response.code.to_i
        raise "Paste upload failed with HTTP #{response.code}." unless code >= 200 && code < 300
        url = response.body.to_s.strip
        raise "Paste upload did not return a URL." if url.empty?
        url
      end

      def manifest_target(folder, path, root)
        {
          :folder_path => folder.gsub("\\", "/"),
          :manifest_path => path.gsub("\\", "/"),
          :root => root.gsub("\\", "/"),
          :source => same_path?(root, MODDEV_DIR) ? :moddev : :mods
        }
      end

      def validate_manifest_target(target)
        path = target[:manifest_path]
        result = target.dup
        result[:errors] = []
        result[:warnings] = []
        result[:fixed] = false
        unless File.exist?(path)
          result[:id] = normalize_mod_id(File.basename(target[:folder_path]))
          result[:name] = File.basename(target[:folder_path])
          result[:errors] << "Missing mod.json"
          return result
        end
        data = parse_json(File.read(path))
        unless data.is_a?(Hash)
          result[:errors] << "Manifest root must be a JSON object."
          return result
        end
        result[:id] = data["id"].to_s
        result[:name] = data["name"].to_s
        required_fields.each do |field|
          result[:errors] << "Missing required field: #{field}" if missing_required_field?(data, field)
        end
        result[:errors] << "id must use lowercase letters, numbers, and underscores" unless result[:id] =~ /\A[a-z0-9_]+\z/
        result[:errors] << "version must use Major.Minor.Patch" unless valid_version?(data["version"])
        result[:errors] << "minimum_reloaded_version must use Major.Minor.Patch" unless valid_version?(data["minimum_reloaded_version"])
        result[:errors] << "authors must be a non-empty array" unless data["authors"].is_a?(Array) && !data["authors"].empty?
        result[:errors] << "dependencies must be an array" unless data["dependencies"].is_a?(Array)
        result[:errors] << "tags must be an array" unless data["tags"].is_a?(Array)
        result[:errors] << wrong_game_message(data["game"]) unless normalize_game_id(data["game"]) == game_id
        result
      rescue Exception => e
        result ||= target.dup
        result[:errors] ||= []
        result[:warnings] ||= []
        result[:id] ||= normalize_mod_id(File.basename(target[:folder_path]))
        result[:name] ||= File.basename(target[:folder_path])
        result[:errors] << "Manifest could not be parsed: #{e.class}: #{e.message}"
        result
      end

      def manifest_defaults(folder)
        name = File.basename(folder).to_s.strip
        {
          "id" => normalize_mod_id(name),
          "game" => game_id,
          "name" => name.empty? ? "New Mod" : name,
          "version" => "1.0.0",
          "authors" => ["Unknown"],
          "description" => "",
          "minimum_reloaded_version" => reloaded_version,
          "dependencies" => [],
          "tags" => ["Mod"],
          "incompatible" => [],
          "changelogurl" => ""
        }
      end

      def template_settings
        {
          "settings" => [
            {
              "key" => "example_toggle",
              "type" => "toggle",
              "label" => "Example Toggle",
              "description" => "Example on/off setting.",
              "default" => true
            },
            {
              "key" => "example_mode",
              "type" => "enum",
              "label" => "Example Mode",
              "description" => "Example option list.",
              "default" => "Normal",
              "options" => ["Easy", "Normal", "Hard"]
            }
          ]
        }
      end

      def template_script(mod_id)
        <<-RUBY.gsub(/^ {8}/, "")
        #======================================================
        # Reloaded #{mod_id} Main
        # Author: Unknown
        #======================================================
        # Main script entry point for #{mod_id}.
        #
        # Responsibilities:
        #   - Register events, patches, and setup code for this mod.
        #
        #======================================================

        Reloaded::Log.mod("#{mod_id}", "Template script loaded") if defined?(Reloaded::Log)
        RUBY
      end

      def write_json(path, data)
        raise "JSON parser is not available" unless defined?(JSON)
        write_text(path, formatted_json(data) + "\n")
      end

      def write_text(path, text)
        ensure_directory(File.dirname(path))
        raise "File already exists: #{relative_game_path(path)}" if File.exist?(path)
        File.open(path, "w") { |file| file.write(text) }
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

      def required_fields
        if defined?(Reloaded::ModManager::REQUIRED_FIELDS)
          Reloaded::ModManager::REQUIRED_FIELDS
        else
          ["id", "game", "name", "version", "authors", "description", "minimum_reloaded_version", "dependencies", "tags"]
        end
      end

      def game_id
        defined?(Reloaded::ModManager::GAME_ID) ? Reloaded::ModManager::GAME_ID : "hoenn"
      end

      def normalize_game_id(value)
        value.to_s.strip.downcase
      end

      def wrong_game_message(value)
        game = value.to_s.strip
        detail = game.empty? ? "No game field was set." : "game is #{game.inspect}."
        "THIS MOD ISN'T MADE FOR THIS GAME! #{detail}"
      end

      def moddev_enabled?
        return Reloaded::Settings.bool("moddev", false) if defined?(Reloaded::Settings)
        false
      rescue
        false
      end

      def backupable_folder?(folder)
        return false if folder.to_s.empty?
        path = File.expand_path(folder)
        return false unless Dir.exist?(path)
        return false unless under_path?(path, MODS_DIR)
        return false if same_path?(path, File.join(MODS_DIR, "Reloaded"))
        true
      rescue
        false
      end

      def normalize_array(value, fallback)
        array = value.is_a?(Array) ? value : [value]
        array = array.compact.map { |entry| entry.to_s.strip }.reject { |entry| entry.empty? }
        array.empty? ? fallback : array
      end

      def normalize_mod_id(value)
        id = value.to_s.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "")
        id.empty? ? "new_mod" : id
      end

      def valid_version?(value)
        value.to_s =~ /\A\d+\.\d+\.\d+\z/
      end

      def reloaded_version
        version = Reloaded.version rescue nil
        valid_version?(version) ? version.to_s : "1.0.0"
      end

      def missing_manifest_value?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end

      def missing_required_field?(data, field)
        !data.respond_to?(:has_key?) || !data.has_key?(field)
      end

      def unique_folder(path)
        return path unless File.exist?(path)
        index = 2
        loop do
          candidate = "#{path} #{index}"
          return candidate unless File.exist?(candidate)
          index += 1
        end
      end

      def safe_folder_name(value)
        name = value.to_s.gsub(/[<>:"\/\\|?*]/, "").strip
        name.empty? ? "New Mod" : name
      end

      def safe_filename(value)
        name = value.to_s.gsub(/[<>:"\/\\|?*]/, "_").strip
        name.empty? ? "Reloaded" : name
      end

      def ensure_directory(path)
        return if path.to_s.empty? || Dir.exist?(path)
        parent = File.dirname(path)
        ensure_directory(parent) if parent && parent != path && !Dir.exist?(parent)
        Dir.mkdir(path) unless Dir.exist?(path)
      end

      def relative_game_path(path)
        expanded = File.expand_path(path).gsub("\\", "/")
        root = File.expand_path(GAME_ROOT).gsub("\\", "/")
        return expanded[root.length + 1..-1] if expanded.downcase.start_with?(root.downcase + "/")
        expanded
      rescue
        path.to_s
      end

      def under_path?(path, root)
        expanded = File.expand_path(path).gsub("\\", "/").downcase
        expanded_root = File.expand_path(root).gsub("\\", "/").downcase
        expanded == expanded_root || expanded.start_with?(expanded_root + "/")
      rescue
        false
      end

      def same_path?(left, right)
        File.expand_path(left).gsub("\\", "/").downcase == File.expand_path(right).gsub("\\", "/").downcase
      rescue
        false
      end

      def sanitize_text(value)
        return Reloaded::Log.sanitize(value) if defined?(Reloaded::Log)
        text = value.to_s.gsub("\\", "/")
        game_root = File.expand_path(GAME_ROOT).gsub("\\", "/")
        reloaded_root = File.expand_path(ROOT).gsub("\\", "/")
        [[game_root, ""], [reloaded_root, "/Reloaded"]].each do |root, replacement|
          text = text.gsub(/#{Regexp.escape(root)}(?=\/|\z)/i, replacement)
        end
        text
      rescue
        value.to_s
      end
    end
  end
end
