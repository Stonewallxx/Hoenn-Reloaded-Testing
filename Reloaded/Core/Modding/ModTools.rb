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
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    MODS_DIR = File.join(GAME_ROOT, "Mods")
    MODDEV_DIR = File.join(GAME_ROOT, "ModDev")
    BACKUP_DIR = File.join(GAME_ROOT, "ModsBackup")
    PASTE_URL = "https://paste.rs/"
    NETWORK_TIMEOUT_SECONDS = 8
    MAX_TEXT_EXPORT_BYTES = 5 * 1024 * 1024

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
        Reloaded::FileActions.display_path(path)
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
        export_file(path, entry[:label])
      end

      def export_file(path, label = nil)
        normalized = Reloaded::FileActions.resolve(path, :type => :file)
        name = label.to_s.strip
        name = File.basename(normalized) if name.empty?
        name = Reloaded::FileActions.sanitize(name)
        raise "#{name} is too large to export." if File.size(normalized).to_i > MAX_TEXT_EXPORT_BYTES
        text = File.read(normalized)
        raise "#{name} is empty." if text.to_s.strip.empty?
        raise "#{name} is not a text file." if text.include?("\0")
        url = upload_to_paste(text)
        Reloaded::FileActions.copy(url)
        Reloaded::Log.info("Exported #{name} to #{url}", :mods) if defined?(Reloaded::Log)
        url
      end

      def export_log_async(label, on_success: nil, on_failure: nil, notify: nil)
        entry = log_entry(label)
        raise "Unknown log file: #{label}" unless entry
        path = ensure_log_file(entry[:path])
        export_file_async(path, entry[:label], :on_success => on_success, :on_failure => on_failure, :notify => notify)
      end

      def export_file_async(path, label = nil, on_success: nil, on_failure: nil, notify: nil)
        raise "Background tasks are unavailable." unless defined?(Reloaded::Task)
        normalized = Reloaded::FileActions.resolve(path, :type => :file)
        name = label.to_s.strip
        name = File.basename(normalized) if name.empty?
        name = Reloaded::FileActions.sanitize(name)
        Reloaded::Task.start("file_export_#{safe_filename(name)}", {
          :owner => :diagnostics,
          :duplicate => :reuse,
          :timeout => 30,
          :on_success => proc do |outcome|
            Reloaded::FileActions.copy(outcome.value)
            Reloaded::Log.info("Exported #{name}", :mods) if defined?(Reloaded::Log)
            on_success.call(outcome) if on_success.respond_to?(:call)
          end,
          :on_failure => on_failure,
          :notify => notify.nil? ? {
            :success => "#{name} exported and copied to the clipboard.",
            :failure => "Could not export #{name}."
          } : notify
        }) do |task|
          task.report(0.1, "Reading #{name}")
          text = read_export_text(normalized, name)
          task.checkpoint!
          task.report(0.25, "Uploading #{name}")
          url = upload_to_paste(text)
          task.report(1.0, "Export complete")
          url
        end
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
        ensure_directory(BACKUP_DIR)
        stamp = Time.now.strftime("%Y%m%d_%H%M%S")
        archive = File.join(BACKUP_DIR, "#{safe_filename(label)}_#{stamp}.zip")
        rel_paths = selected.map { |row| relative_game_path(row[:folder_path]) }.compact
        raise "No valid mod folders were selected." if rel_paths.empty?
        ok = Reloaded::Platform.create_zip(archive, rel_paths, GAME_ROOT)
        raise "Backup archive could not be created." unless ok && File.exist?(archive)
        Reloaded::Log.info("Created mod backup: #{relative_game_path(archive)}", :mods) if defined?(Reloaded::Log)
        archive
      end

      def backup_all_mods_async(on_success: nil, on_failure: nil, notify: nil)
        backup_mod_rows_async(backupable_mod_rows, "AllMods", :on_success => on_success, :on_failure => on_failure, :notify => notify)
      end

      def backup_mod_rows_async(rows, label = "SelectedMods", on_success: nil, on_failure: nil, notify: nil)
        raise "Background tasks are unavailable." unless defined?(Reloaded::Task)
        selected = Array(rows).map(&:dup)
        Reloaded::Task.start("mod_backup_#{safe_filename(label)}", {
          :owner => :mod_archives,
          :duplicate => :reject,
          :on_success => on_success,
          :on_failure => on_failure,
          :notify => notify.nil? ? {
            :success => "Mod backup created.",
            :failure => "Mod backup failed."
          } : notify
        }) do |task|
          task.checkpoint!
          task.report(0.05, "Preparing backup")
          archive = backup_mod_rows(selected, label)
          task.checkpoint!
          task.report(1.0, "Backup complete")
          archive
        end
      end

      def manifest_targets
        dirs = [MODS_DIR]
        dirs << MODDEV_DIR if moddev_enabled?
        targets = dirs.each_with_object([]) do |root, list|
          next unless Dir.exist?(root)
          Dir[File.join(root, "*")].sort.each do |folder|
            next unless File.directory?(folder)
            next if same_path?(folder, File.join(MODS_DIR, "Reloaded"))
            next if same_path?(root, MODDEV_DIR) && ["foundation checks", "tools"].include?(File.basename(folder).downcase)
            path = File.join(folder, "mod.json")
            list << manifest_target(folder, path, root)
          end
        end
        return targets unless moddev_enabled?
        moddev_ids = targets.select { |target| target[:source] == :moddev }
                             .map { |target| manifest_target_id(target) }
                             .reject { |id| id.empty? }
                             .uniq
        targets.reject do |target|
          target[:source] == :mods && moddev_ids.include?(manifest_target_id(target))
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
        data["required_features"] = normalize_array(data["required_features"], [])
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
        folder = unique_folder(File.join(MODDEV_DIR, folder_name))
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
        write_text(File.join(folder, "Documentation", "README.md"), template_readme(mod_name, id))
        write_text(File.join(folder, "Documentation", "APIExamples.rb"), template_api_examples(id))
        Reloaded::Log.info("Created mod template: #{relative_game_path(folder)}", :mods) if defined?(Reloaded::Log)
        folder
      end

      def profile_targets
        return [] unless defined?(Reloaded::Profiles)
        Reloaded::Profiles.list.map do |profile|
          {
            :id => profile["id"].to_s,
            :name => profile["name"].to_s,
            :profile => profile
          }
        end
      rescue Exception => e
        Reloaded::Log.exception("Could not list profile validation targets", e, channel: :mods) if defined?(Reloaded::Log)
        []
      end

      def validate_profiles
        available = available_profile_mod_ids
        profile_targets.map do |target|
          profile = target[:profile]
          result = target.dup
          result[:errors] = []
          result[:warnings] = []
          id = profile["id"].to_s
          name = profile["name"].to_s
          result[:errors] << "Profile name is required." if name.strip.empty?
          result[:errors] << "id must use lowercase letters, numbers, and underscores" unless id =~ /\A[a-z0-9_]+\z/
          enabled = normalize_array(profile["enabled_mods"], [])
          disabled = normalize_array(profile["disabled_mods"], [])
          order = normalize_array(profile["load_order"], [])
          overlap = enabled & disabled
          result[:errors] << "Mods cannot be both enabled and disabled: #{overlap.join(', ')}" unless overlap.empty?
          duplicated = order.group_by { |mod_id| mod_id }.select { |_mod_id, rows| rows.length > 1 }.keys
          result[:errors] << "Load order contains duplicates: #{duplicated.join(', ')}" unless duplicated.empty?
          missing_order = enabled - order
          result[:warnings] << "Enabled mods missing from load order: #{missing_order.join(', ')}" unless missing_order.empty?
          referenced = (enabled + disabled + order).uniq
          missing = referenced.reject { |mod_id| available.include?(normalize_mod_id(mod_id)) }
          result[:errors] << "Referenced mods are not installed or published: #{missing.join(', ')}" unless missing.empty?
          result
        end
      end

      def create_profile_template(name, mod_ids = [])
        raise "Reloaded profiles are unavailable." unless defined?(Reloaded::Profiles)
        profile = Reloaded::Profiles.create(name, :activate => false)
        ids = Array(mod_ids).map { |value| normalize_mod_id(value) }.reject { |value| value.empty? }.uniq
        profile["enabled_mods"] = ids
        profile["disabled_mods"] = []
        profile["load_order"] = ids
        Reloaded::Profiles.write_profile(profile)
      end

      private

      def available_profile_mod_ids
        ids = []
        ids.concat(Reloaded::ModManager.mod_ids) if defined?(Reloaded::ModManager)
        ids.map { |value| normalize_mod_id(value) }.reject { |value| value.empty? }.uniq
      rescue
        []
      end

      def read_export_text(path, name)
        raise "#{name} is too large to export." if File.size(path).to_i > MAX_TEXT_EXPORT_BYTES
        text = File.read(path)
        raise "#{name} is empty." if text.to_s.strip.empty?
        raise "#{name} is not a text file." if text.include?("\0")
        text
      end

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
        Reloaded::FileActions.open_file(path)
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

      def manifest_target_id(target)
        path = target[:manifest_path].to_s
        if File.exist?(path)
          data = parse_json(File.read(path))
          id = normalize_mod_id(data["id"]) if data.is_a?(Hash)
          return id unless id.to_s.empty?
        end
        normalize_mod_id(File.basename(target[:folder_path].to_s))
      rescue
        normalize_mod_id(File.basename(target[:folder_path].to_s))
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
        result[:errors] << "required_features must be an array" if data.has_key?("required_features") && !data["required_features"].is_a?(Array)
        if data["required_features"].is_a?(Array) && defined?(Reloaded::Features)
          data["required_features"].each do |feature_id|
            result[:errors] << "Unknown required feature: #{feature_id}" unless Reloaded::Features.registered?(feature_id)
          end
        end
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
          "required_features" => [],
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

      def template_readme(mod_name, mod_id)
        <<-MARKDOWN.gsub(/^ {8}/, "")
        # #{mod_name}

        Starter Hoenn Reloaded mod with ID `#{mod_id}`.

        ## Structure

        - `Scripts/` contains Ruby files loaded in alphabetical order.
        - `Graphics/`, `Audio/`, and `Fonts/` contain optional asset overrides.
        - `Settings.json` declares player-configurable mod settings.
        - `Documentation/APIExamples.rb` contains syntax-checkable examples. It
          is documentation only and is not loaded by the game.

        ## API Stability

        Use APIs documented in `Reloaded/Documentation/Modding.md`. Stable
        contracts are supported integration points:

        ```ruby
        Reloaded::API.public?(:events)
        Reloaded::API.public?(:rewards)
        Reloaded::API.contract(:download)
        ```

        Do not call methods marked `private`, test overrides, scene classes,
        adapters, mutable registries, or constants documented as internal.
        `compatibility` contracts exist for older mods; new code should use the
        documented replacement. `developer` contracts are for local tools and
        are not guaranteed to exist in player packages.

        Copy only the examples your mod needs into `Scripts/`. Replace example
        URLs, paths, IDs, checksums, and reward data before shipping.
        MARKDOWN
      end

      def template_api_examples(mod_id)
        <<-RUBY.gsub(/^ {8}/, "")
        # Documentation-only examples. This file is outside Scripts/ and is not
        # loaded by Hoenn Reloaded. Copy only the methods your mod needs.

        module ReloadedTemplateExamples
          MOD_ID = :#{mod_id}

          def self.open_form
            Reloaded::Form.open(
              "Example Editor",
              [
                { :id => "name", :label => "Name", :type => :text, :required => true },
                { :id => "count", :label => "Count", :type => :number, :min => 1, :max => 99 }
              ],
              { "name" => "Example", "count" => 1 }
            )
          end

          def self.register_remote_data
            Reloaded::RemoteData.register(
              :#{mod_id}_catalog,
              :owner => MOD_ID,
              :format => :json,
              :url => "https://example.com/catalog.json",
              :local_path => "Mods/Example Mod/catalog.json",
              :validator => proc { |value| value.is_a?(Hash) }
            )
          end

          def self.refresh_remote_data
            Reloaded::Task.start(
              :#{mod_id}_refresh,
              :owner => MOD_ID,
              :duplicate => :reuse
            ) do |task|
              result = Reloaded::RemoteData.fetch(:#{mod_id}_catalog, :force => true)
              task.fail!(result.error_message, result.error_code) unless result.ok?
              result.value
            end
          end

          def self.download_archive(url, destination)
            Reloaded::Download.start(
              url,
              destination,
              :label => "Example Download",
              :expected_bytes => 12_345_678,
              :sha256 => ("0" * 64), # Replace with the published file hash.
              :task_options => { :owner => MOD_ID, :duplicate => :reuse }
            )
          end

          def self.extract_archive(archive, destination, task = nil)
            Reloaded::Archive.extract(
              archive,
              destination,
              :overwrite => :fail,
              :task => task,
              :verify => true
            )
          end

          def self.grant_item
            Reloaded.grant_reward(
              { "type" => "item", "item" => "POTION", "quantity" => 1 },
              :source => MOD_ID
            )
          end
        end
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
        Reloaded::Versioning.valid?(value)
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
        Reloaded::FileActions.display_path(path)
      rescue
        File.basename(path.to_s)
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

  module Diagnostics
    class << self
      def log_entries; ModderTools.log_entries; end
      def log_entry(label); ModderTools.log_entry(label); end
      def display_path(path); ModderTools.display_path(path); end
      def display_text(value); ModderTools.display_text(value); end
      def open_log(label); ModderTools.open_log(label); end
      def export_log(label); ModderTools.export_log(label); end
      def export_file(path, label = nil); ModderTools.export_file(path, label); end
      def export_log_async(label, **options); ModderTools.export_log_async(label, **options); end
      def export_file_async(path, label = nil, **options); ModderTools.export_file_async(path, label, **options); end
      def clear_logs; ModderTools.clear_logs; end
    end
  end

  module ModArchives
    class << self
      def backupable_mod_rows; ModderTools.backupable_mod_rows; end
      def backup_all_mods; ModderTools.backup_all_mods; end
      def backup_mod_rows(rows, label = "SelectedMods"); ModderTools.backup_mod_rows(rows, label); end
      def backup_all_mods_async(**options); ModderTools.backup_all_mods_async(**options); end
      def backup_mod_rows_async(rows, label = "SelectedMods", **options); ModderTools.backup_mod_rows_async(rows, label, **options); end
    end
  end

  module ModDevelopment
    class << self
      def manifest_targets; ModderTools.manifest_targets; end
      def validate_manifests; ModderTools.validate_manifests; end
      def fix_manifest(target); ModderTools.fix_manifest(target); end
      def create_mod_template(name); ModderTools.create_mod_template(name); end
      def profile_targets; ModderTools.profile_targets; end
      def validate_profiles; ModderTools.validate_profiles; end
      def create_profile_template(name, mod_ids = []); ModderTools.create_profile_template(name, mod_ids); end
    end
  end
end
