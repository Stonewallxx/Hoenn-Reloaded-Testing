#======================================================
# Reloaded Mod Browser
# Author: Stonewall
#======================================================
# Backend source registry and downloader for Mod Manager browser features.
#
# Responsibilities:
#   - Read the official GitHub mod index into a searchable registry.
#   - Resolve missing mod IDs to downloadable index entries.
#   - Download and install mod archives into Mods/.
#   - Provide backend hooks for future Mod Browser UI pages.
#
#======================================================

begin
  require "json"
rescue Exception
end

module Reloaded
  module ModBrowser
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    MODS_DIR = File.join(GAME_ROOT, "Mods")
    TOOL_DIR = File.join(GAME_ROOT, "Modders Tools")
    DEFAULT_GITHUB_INDEX_URL = "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded-Mods/main/index.json"

    SOURCE_VERSION = 1
    INDEX_VERSION = 1

    @sources = []
    @entries = {}
    @profile_entries = {}
    @source_statuses = {}
    @last_refresh_at = nil
    @last_remote_fetch_at = nil
    @last_refresh_remote = false
    @booted = false

    class << self
      def boot
        return true if @booted
        @booted = true
        refresh(fetch_remote: false)
        Reloaded::Log.info("Mod Browser registry ready with #{@entries.length} entr#{@entries.length == 1 ? 'y' : 'ies'}", :mods) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Mod Browser boot failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def refresh(fetch_remote: false)
        @sources = load_sources
        @entries = {}
        @profile_entries = {}
        @source_statuses = {}
        @last_refresh_at = Time.now rescue nil
        @last_refresh_remote = fetch_remote
        @sources.each { |source| load_source_index(source, fetch_remote: fetch_remote) if truthy?(source["enabled"]) }
        @entries
      rescue Exception => e
        Reloaded::Log.exception("Mod Browser refresh failed", e, channel: :mods) if defined?(Reloaded::Log)
        @entries ||= {}
      end

      def sources
        @sources.dup
      end

      def entries
        @entries.dup
      end

      def profile_entries
        @profile_entries.dup
      end

      def sync_status
        {
          :last_refresh_at => @last_refresh_at,
          :last_remote_fetch_at => @last_remote_fetch_at,
          :remote => @last_refresh_remote,
          :sources => @source_statuses.dup,
          :mods => @entries.length,
          :profiles => @profile_entries.length
        }
      end

      def sync_status_text
        stamp = @last_remote_fetch_at || @last_refresh_at
        label = @last_remote_fetch_at ? "Synced" : "Cached"
        time = stamp ? stamp.strftime("%H:%M") : "--:--"
        "#{label} #{time}"
      rescue
        "Sync unknown"
      end

      def entry(mod_id)
        entry_for(mod_id)
      end

      def entry_for(mod_id, version = nil)
        item = @entries[normalize_mod_id(mod_id)]
        return nil unless item
        return item if version.to_s.strip.empty?
        with_version(item, version)
      end

      def profile_entry(profile_id)
        @profile_entries[normalize_mod_id(profile_id)]
      end

      def available_mod_ids
        @entries.keys.sort
      end

      def available_profile_ids
        @profile_entries.keys.sort
      end

      def resolve_mod_ids(mod_ids, fetch_remote: true, versions: {})
        refresh(fetch_remote: fetch_remote) if fetch_remote || @entries.empty?
        ids = normalize_string_array(mod_ids)
        version_map = normalize_version_map(versions)
        found = []
        missing = []
        ids.each do |id|
          item = entry_for(id, version_map[id])
          item ? found << item : missing << id
        end
        {
          :found => found,
          :missing => missing,
          :found_ids => found.map { |item| item["id"] },
          :missing_ids => missing
        }
      end

      def download_mods(mod_ids, enable: false, versions: {})
        plan = build_download_plan(mod_ids, versions: versions, fetch_remote: true)
        installed = []
        failed = plan[:missing].dup + plan[:version_mismatches].map { |entry| entry[:id] }
        no_download_url = []
        plan[:entries].each do |item|
          id = item["id"].to_s
          if item["download_url"].to_s.strip.empty?
            no_download_url << id
            failed << id
            log("No download URL configured for #{id}", :warning)
            next
          end
          if download_and_install(item)
            installed << id
          else
            failed << id
          end
        end
        Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
        if enable && defined?(Reloaded::Profiles)
          (installed + plan[:already_installed]).uniq.each { |id| Reloaded::Profiles.enable_mod(id) }
        end
        {
          :installed => installed.uniq,
          :failed => failed.uniq,
          :missing => plan[:missing].uniq,
          :already_installed => plan[:already_installed].uniq,
          :dependencies => plan[:dependencies].uniq,
          :requested => plan[:requested].uniq,
          :version_mismatches => plan[:version_mismatches],
          :no_download_url => no_download_url.uniq
        }
      end

      def build_download_plan(mod_ids, versions: {}, fetch_remote: true)
        refresh(fetch_remote: fetch_remote) if fetch_remote || @entries.empty?
        plan = {
          :entries => [],
          :requested => [],
          :dependencies => [],
          :missing => [],
          :already_installed => [],
          :version_mismatches => []
        }
        version_map = normalize_version_map(versions)
        visiting = {}
        visited = {}
        normalize_string_array(mod_ids).each do |id|
          collect_download_entry(id, version_map[id], nil, plan, visiting, visited, true)
        end
        plan[:missing].uniq!
        plan[:already_installed].uniq!
        plan[:requested].uniq!
        plan[:dependencies].uniq!
        plan
      end

      def import_published_profile(profile_id, download_missing: true, enable_missing: true, activate: true)
        refresh(fetch_remote: true) if @profile_entries.empty?
        item = profile_entry(profile_id)
        raise "Published profile not found: #{profile_id}" unless item
        raise "Profile code system is not available" unless defined?(Reloaded::ProfileCodes)
        code = profile_code_for(item)
        payload = Reloaded::ProfileCodes.decode(code)
        missing = Reloaded::ProfileCodes.missing_mod_ids(payload)
        installed = []
        failed = []
        if !missing.empty?
          unless download_missing
            return {
              :success => false,
              :profile => nil,
              :missing => missing,
              :installed => [],
              :failed => []
            }
          end
          versions = profile_version_map(item)
          result = download_mods(missing, enable: enable_missing, versions: versions)
          installed = Array(result[:installed])
          failed = Array(result[:failed])
          return {
            :success => false,
            :profile => nil,
            :missing_profile_mods => missing,
            :missing => Array(result[:missing]),
            :installed => installed,
            :failed => failed,
            :already_installed => Array(result[:already_installed]),
            :dependencies => Array(result[:dependencies]),
            :version_mismatches => Array(result[:version_mismatches]),
            :no_download_url => Array(result[:no_download_url])
          } unless failed.empty?
        end
        disable_ids = enable_missing ? [] : installed
        profile = Reloaded::ProfileCodes.import_code(code, activate: activate, disable_mod_ids: disable_ids)
        {
          :success => true,
          :profile => profile,
          :missing_profile_mods => missing,
          :missing => [],
          :installed => installed,
          :failed => failed,
          :already_installed => [],
          :dependencies => [],
          :no_download_url => []
        }
      end

      def download_and_install(entry)
        item = normalize_entry(entry, "manual")
        archive = download_entry(item)
        return false unless archive && File.exist?(archive)
        ok = install_archive(archive)
        File.delete(archive) rescue nil
        ok
      rescue Exception => e
        Reloaded::Log.exception("Failed to download/install #{entry["id"] rescue "unknown"}", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def install_archive(archive_path)
        return false unless File.exist?(archive_path)
        ensure_directory(MODS_DIR)
        staging = File.join(temp_root, "rld_install_#{Time.now.to_i}_#{rand(100000)}")
        backups = []
        ensure_directory(staging)
        unless extract_archive(archive_path, staging)
          delete_tree(staging)
          return false
        end
        roots = find_mod_roots(staging)
        if roots.empty?
          log("Archive did not contain any mod.json files: #{archive_path}", :error)
          delete_tree(staging)
          return false
        end
        roots.each { |root| install_mod_root(root, backups) }
        delete_tree(staging)
        cleanup_install_backups(backups)
        Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
        log("Installed #{roots.length} mod folder(s) from #{File.basename(archive_path)}")
        true
      rescue Exception => e
        Reloaded::Log.exception("Archive install failed", e, channel: :mods) if defined?(Reloaded::Log)
        restore_install_backups(backups) if backups
        delete_tree(staging) if staging
        false
      end

      def version_sort_key(version)
        parts = version.to_s.scan(/\d+/).map(&:to_i)
        [parts[0] || 0, parts[1] || 0, parts[2] || 0, version.to_s]
      end

      private

      def collect_download_entry(id, exact_version, minimum_version, plan, visiting, visited, requested)
        mod_id = normalize_mod_id(id)
        return if mod_id.empty?
        plan[requested ? :requested : :dependencies] << mod_id
        if !requested && installed_version_satisfies?(mod_id, minimum_version)
          plan[:already_installed] << mod_id
          return
        end
        key = "#{mod_id}@#{exact_version || minimum_version}"
        return if visited[key]
        if visiting[key]
          log("Dependency cycle found while planning download for #{mod_id}", :warning)
          return
        end
        visiting[key] = true
        item = if exact_version && !exact_version.to_s.empty?
                 entry_for(mod_id, exact_version)
               elsif minimum_version && !minimum_version.to_s.empty?
                 entry_for_minimum_version(mod_id, minimum_version)
               else
                 entry_for(mod_id)
               end
        if item.nil?
          if minimum_version && !minimum_version.to_s.empty? && @entries[mod_id]
            plan[:version_mismatches] << {
              :id => mod_id,
              :required_version => minimum_version.to_s,
              :available_version => @entries[mod_id]["latest_version"].to_s
            }
          else
            plan[:missing] << mod_id
          end
          visiting.delete(key)
          visited[key] = true
          return
        end
        Array(item["dependencies"]).each do |dependency|
          collect_download_entry(dependency["id"], nil, dependency["version"], plan, visiting, visited, false)
        end
        plan[:entries] << item unless plan[:entries].any? { |entry| entry["id"] == item["id"] }
        visiting.delete(key)
        visited[key] = true
      end

      def entry_for_minimum_version(mod_id, minimum_version)
        item = @entries[normalize_mod_id(mod_id)]
        return nil unless item
        minimum = minimum_version.to_s
        selected = Array(item["versions"]).find do |entry|
          !entry["version"].to_s.empty? && compare_versions(entry["version"], minimum) >= 0
        end
        selected ? with_version(item, selected["version"]) : nil
      end

      def installed_version_satisfies?(mod_id, minimum_version)
        return false unless defined?(Reloaded::ModManager)
        row = Reloaded::ModManager.mod_row(mod_id)
        return false unless row
        minimum = minimum_version.to_s
        return true if minimum.empty?
        compare_versions(row[:version], minimum) >= 0
      rescue
        false
      end

      def compare_versions(left, right)
        a = left.to_s.split(".").map(&:to_i)
        b = right.to_s.split(".").map(&:to_i)
        3.times do |i|
          result = (a[i] || 0) <=> (b[i] || 0)
          return result unless result == 0
        end
        0
      end

      def load_sources
        sources = [{
          "id" => "official",
          "name" => "Hoenn Reloaded Mods",
          "enabled" => true,
          "path" => "",
          "url" => DEFAULT_GITHUB_INDEX_URL,
          "file_path" => "built-in"
        }]
        optional_path = File.join(TOOL_DIR, "Sources.json")
        if File.exist?(optional_path)
          parsed = parse_json_file(optional_path)
          if parsed.is_a?(Hash)
            Array(parsed["sources"]).each do |source|
              next unless source.is_a?(Hash)
              sources << normalize_source(source, optional_path)
            end
          end
        end
        sources
      end

      def normalize_source(source, file_path)
        id = normalize_mod_id(source["id"] || source["name"] || File.basename(file_path, ".json"))
        {
          "id" => id.empty? ? "source" : id,
          "name" => source["name"].to_s.empty? ? id : source["name"].to_s,
          "enabled" => source.has_key?("enabled") ? truthy?(source["enabled"]) : true,
          "path" => source["path"].to_s,
          "url" => source["url"].to_s,
          "file_path" => file_path
        }
      end

      def load_source_index(source, fetch_remote: false)
        raw = nil
        if !source["path"].to_s.empty?
          path = expand_game_path(source["path"])
          if File.exist?(path)
            raw = File.read(path)
            @source_statuses[source["id"].to_s] = "local"
          end
        end
        if source["url"].to_s != ""
          if fetch_remote
            raw_remote = fetch_url(source["url"], cache_bust: true)
            if raw_remote && !raw_remote.empty?
              raw = raw_remote
              @last_remote_fetch_at = Time.now rescue @last_remote_fetch_at
              @source_statuses[source["id"].to_s] = "remote"
              log("Fetched browser source #{source["id"]}")
            end
          end
        end
        @source_statuses[source["id"].to_s] ||= raw.to_s.empty? ? "empty" : "cached"
        return if raw.nil? || raw.empty?
        register_index(parse_json(raw), source)
      rescue Exception => e
        @source_statuses[source["id"].to_s] = "error" rescue nil
        Reloaded::Log.exception("Failed to load browser source #{source["id"]}", e, channel: :mods) if defined?(Reloaded::Log)
      end

      def register_index(data, source)
        mods = if data.is_a?(Array)
                 data
               elsif data.is_a?(Hash)
                 data["mods"] || data["entries"] || data["value"] || []
               else
                 []
               end
        Array(mods).each do |entry|
          item = normalize_entry(entry, source["id"])
          next if item["id"].empty?
          @entries[item["id"]] = item
        end
        profiles = data.is_a?(Hash) ? (data["profiles"] || data["published_profiles"] || data["modpacks"] || []) : []
        Array(profiles).each do |entry|
          item = normalize_profile_entry(entry, source["id"])
          next if item["id"].empty?
          @profile_entries[item["id"]] = item
        end
      end

      def normalize_entry(entry, source_id)
        source = entry.is_a?(Hash) ? entry : {}
        id = normalize_mod_id(source["id"] || source["uid"])
        versions = normalize_versions(source)
        selected_version = selected_version_entry(source, versions)
        {
          "id" => id,
          "kind" => "mod",
          "name" => source["name"].to_s.empty? ? id : source["name"].to_s,
          "version" => selected_version["version"].to_s,
          "latest_version" => (source["latest_version"] || selected_version["version"]).to_s,
          "authors" => normalize_authors(source["authors"] || source["author"]),
          "description" => source["description"].is_a?(Array) ? source["description"].join("\n") : source["description"].to_s,
          "tags" => display_tags(source["tags"]),
          "dependencies" => normalize_dependencies(selected_version["dependencies"] || source["dependencies"]),
          "download_url" => selected_version["download_url"].to_s,
          "versions" => versions,
          "homepage_url" => source["homepage_url"].to_s,
          "changelogurl" => first_string(source["changelogurl"], source["changelog_url"], selected_version["changelogurl"], selected_version["changelog_url"]),
          "source_id" => source_id.to_s,
          "featured" => truthy?(source["featured"]),
          "special_entry" => truthy?(source["special_entry"] || source["special"])
        }
      end

      def normalize_profile_entry(entry, source_id)
        source = entry.is_a?(Hash) ? entry : {}
        id = normalize_mod_id(source["id"] || source["uid"] || source["profile_id"])
        mods = normalize_profile_mods(source["mods"])
        tags = (display_tags(source["tags"]) + profile_tags_from_mods(mods)).reject { |tag| tag_key(tag) == "profile" }.uniq
        tags.unshift("Profile")
        {
          "id" => id,
          "kind" => "profile",
          "name" => source["name"].to_s.empty? ? id : source["name"].to_s,
          "version" => source["version"].to_s,
          "authors" => normalize_authors(source["authors"] || source["author"]),
          "description" => source["description"].is_a?(Array) ? source["description"].join("\n") : source["description"].to_s,
          "tags" => tags,
          "mods" => mods,
          "profile_code" => source["profile_code"].to_s,
          "profile_url" => source["profile_url"].to_s.empty? ? source["url"].to_s : source["profile_url"].to_s,
          "reloaded_version" => source["reloaded_version"].to_s,
          "homepage_url" => source["homepage_url"].to_s,
          "changelogurl" => first_string(source["changelogurl"], source["changelog_url"]),
          "source_id" => source_id.to_s,
          "featured" => truthy?(source["featured"]),
          "special_entry" => truthy?(source["special_entry"] || source["special"])
        }
      end

      def with_version(item, version)
        wanted = version.to_s.strip
        selected = Array(item["versions"]).find { |entry| entry["version"].to_s == wanted }
        return nil unless selected
        copy = {}
        item.each { |key, value| copy[key] = value }
        copy["version"] = selected["version"].to_s
        copy["download_url"] = selected["download_url"].to_s
        copy["dependencies"] = normalize_dependencies(selected["dependencies"])
        copy
      end

      def download_entry(entry)
        url = entry["download_url"].to_s.strip
        return nil if url.empty?
        filename = "#{entry["id"]}_#{Time.now.to_i}.zip"
        path = File.join(temp_root, filename)
        if download_file(url, path, min_bytes: 128)
          log("Downloaded #{entry["id"]} to #{path}")
          path
        else
          File.delete(path) rescue nil
          log("Download failed for #{entry["id"]}", :error)
          nil
        end
      end

      def profile_code_for(entry)
        code = entry["profile_code"].to_s.strip
        return code unless code.empty?
        url = entry["profile_url"].to_s.strip
        raise "Published profile has no profile code or profile URL" if url.empty?
        raw = fetch_url(url).to_s.strip
        raise "Published profile URL returned no data" if raw.empty?
        return raw if raw[0, Reloaded::ProfileCodes::CODE_PREFIX.length] == Reloaded::ProfileCodes::CODE_PREFIX
        parsed = parse_json(raw)
        Reloaded::ProfileCodes.encode_payload(parsed)
      end

      def profile_version_map(entry)
        map = {}
        Array(entry["mods"]).each do |mod|
          id = normalize_mod_id(mod["id"])
          version = mod["version"].to_s
          map[id] = version unless id.empty? || version.empty?
        end
        map
      end

      def download_file(url, destination, min_bytes: 1)
        File.delete(destination) rescue nil
        begin
          pbDownloadToFile(url, destination)
        rescue Exception => e
          log("pbDownloadToFile failed for #{url}: #{e.class}: #{e}", :warning)
        end
        valid_download?(destination, min_bytes)
      rescue Exception => e
        Reloaded::Log.exception("Download command failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def fetch_url(url, cache_bust: false)
        request_url = cache_bust ? cache_busted_url(url) : url
        if defined?(HTTPLite)
          response = HTTPLite.get(request_url, {
            "Cache-Control" => "no-cache",
            "Proxy-Connection" => "Close",
            "Pragma" => "no-cache",
            "User-Agent" => "Hoenn Reloaded Mod Browser"
          }) rescue nil
          return response[:body].to_s if response.is_a?(Hash) && response[:status].to_i == 200
        end
        if defined?(pbDownloadToString)
          data = pbDownloadToString(request_url) rescue ""
          return data.to_s unless data.to_s.empty?
        end
        nil
      end

      def cache_busted_url(url)
        joiner = url.to_s.include?("?") ? "&" : "?"
        "#{url}#{joiner}rld_cache=#{Time.now.to_i}_#{rand(100000)}"
      end

      def extract_archive(archive_path, destination)
        sevenz = File.expand_path("./REQUIRED_BY_INSTALLER_UPDATER/7z.exe")
        ok = if File.exist?(sevenz)
             system("\"#{sevenz}\" x -y \"-o#{destination}\" \"#{archive_path}\"")
             else
              log("Archive extraction failed: 7z.exe was not found", :error)
              false
             end
        unless ok
          log("Archive extraction failed: #{archive_path}", :error)
          return false
        end
        true
      end

      def find_mod_roots(staging)
        manifests = find_files_named(staging, "mod.json")
        roots = manifests.map { |manifest| File.dirname(manifest) }
        roots.reject do |root|
          roots.any? { |other| root != other && normalize_path(root).start_with?(normalize_path(other) + "/") }
        end
      end

      def find_files_named(root, filename)
        found = []
        Dir[glob_path(root, "*")].each do |entry|
          if File.directory?(entry)
            found.concat(find_files_named(entry, filename))
          elsif File.basename(entry).downcase == filename.downcase
            found << entry
          end
        end
        found
      end

      def install_mod_root(root, backups = [])
        manifest = parse_json_file(File.join(root, "mod.json"))
        id = manifest.is_a?(Hash) ? normalize_mod_id(manifest["id"]) : ""
        id = normalize_mod_id(File.basename(root)) if id.empty?
        raise "Installed mod is missing an id" if id.empty?
        destination = installed_mod_folder(id) || File.join(MODS_DIR, install_folder_name(root, id))
        backups << prepare_install_backup(destination)
        ensure_directory(destination)
        copy_tree(root, destination)
        log("Installed mod #{id} to #{File.basename(destination)}")
        id
      end

      def prepare_install_backup(destination)
        entry = {
          :destination => destination,
          :backup => nil,
          :existed => File.directory?(destination)
        }
        return entry unless entry[:existed]
        backup = File.join(install_backup_root, "#{safe_filename(File.basename(destination))}_#{Time.now.to_i}_#{rand(100000)}")
        move_tree(destination, backup)
        entry[:backup] = backup
        log("Created install rollback backup for #{File.basename(destination)}")
        entry
      rescue Exception
        delete_tree(backup) if backup && File.directory?(backup)
        raise
      end

      def restore_install_backups(backups)
        Array(backups).reverse.each do |entry|
          destination = entry[:destination]
          delete_tree(destination) if File.directory?(destination)
          if entry[:existed] && entry[:backup] && File.directory?(entry[:backup])
            move_tree(entry[:backup], destination)
            log("Restored previous mod folder #{File.basename(destination)} after failed install", :warning)
          end
        end
      end

      def cleanup_install_backups(backups)
        Array(backups).each do |entry|
          delete_tree(entry[:backup]) if entry[:backup] && File.directory?(entry[:backup])
        end
        delete_tree(install_backup_root) if Dir.exist?(install_backup_root) && Dir[glob_path(install_backup_root, "*")].empty?
      end

      def move_tree(source, destination)
        ensure_directory(File.dirname(destination))
        File.rename(source, destination)
      rescue
        copy_tree(source, destination)
        delete_tree(source)
      end

      def install_backup_root
        File.join(MODS_DIR, ".ReloadedInstallBackups")
      end

      def installed_mod_folder(id)
        Dir[glob_path(MODS_DIR, "*", "mod.json")].each do |manifest_path|
          manifest = parse_json_file(manifest_path)
          next unless manifest.is_a?(Hash)
          return File.dirname(manifest_path) if normalize_mod_id(manifest["id"]) == id
        rescue
          next
        end
        nil
      end

      def install_folder_name(root, id)
        name = File.basename(root.to_s)
        return id if name.empty? || name.start_with?("rld_install_")
        name
      end

      def copy_tree(source, destination)
        ensure_directory(destination)
        Dir[glob_path(source, "*")].each do |entry|
          target = File.join(destination, File.basename(entry))
          if File.directory?(entry)
            copy_tree(entry, target)
          else
            ensure_directory(File.dirname(target))
            copy_file(entry, target)
          end
        end
      end

      def copy_file(source, destination)
        File.open(source, "rb") do |input|
          File.open(destination, "wb") do |output|
            while (chunk = input.read(8192))
              output.write(chunk)
            end
          end
        end
      end

      def delete_tree(path)
        return unless path && File.directory?(path)
        Dir[glob_path(path, "**", "*")].sort.reverse.each do |entry|
          File.directory?(entry) ? (Dir.rmdir(entry) rescue nil) : (File.delete(entry) rescue nil)
        end
        Dir.rmdir(path) rescue nil
      end

      def valid_download?(path, min_bytes = 1)
        File.exist?(path) && File.size(path).to_i >= min_bytes.to_i
      end

      def parse_json(raw)
        raise "JSON parser is not available" unless defined?(JSON)
        stringify_json_keys(JSON.parse(raw.to_s.sub("\xEF\xBB\xBF", "")))
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

      def parse_json_file(path)
        parse_json(File.read(path))
      end

      def normalize_dependencies(value)
        Array(value).map do |dep|
          if dep.is_a?(Hash)
            {
              "id" => normalize_mod_id(dep["id"] || dep["uid"]),
              "version" => (dep["version"] || dep["min_version"]).to_s
            }
          else
            {
              "id" => normalize_mod_id(dep),
              "version" => ""
            }
          end
        end.reject { |dep| dep["id"].empty? }
      end

      def normalize_versions(source)
        versions = []
        Array(source["versions"]).each do |entry|
          next unless entry.is_a?(Hash)
          version = entry["version"].to_s
          download_url = entry["download_url"].to_s.empty? ? entry["url"].to_s : entry["download_url"].to_s
          next if version.empty? && download_url.empty?
          versions << {
            "version" => version,
            "download_url" => download_url,
            "reloaded_version" => (entry["reloaded_version"] || entry["minimum_reloaded_version"]).to_s,
            "changelog" => entry["changelog"].to_s,
            "changelogurl" => first_string(entry["changelogurl"], entry["changelog_url"]),
            "dependencies" => normalize_dependencies(entry["dependencies"])
          }
        end
        if versions.empty?
          versions << {
            "version" => (source["version"] || source["latest_version"]).to_s,
            "download_url" => source["download_url"].to_s.empty? ? source["url"].to_s : source["download_url"].to_s,
            "reloaded_version" => (source["reloaded_version"] || source["minimum_reloaded_version"]).to_s,
            "changelog" => source["changelog"].to_s,
            "changelogurl" => first_string(source["changelogurl"], source["changelog_url"]),
            "dependencies" => normalize_dependencies(source["dependencies"])
          }
        end
        versions.sort_by { |entry| version_sort_key(entry["version"]) }.reverse
      end

      def first_string(*values)
        values.each do |value|
          text = value.to_s.strip
          return text unless text.empty?
        end
        ""
      end

      def selected_version_entry(source, versions)
        latest = source["latest_version"].to_s
        selected = versions.find { |entry| !latest.empty? && entry["version"].to_s == latest }
        selected || versions.find { |entry| entry["version"].to_s == source["version"].to_s } || versions.first || {}
      end

      def normalize_profile_mods(value)
        Array(value).map do |mod|
          if mod.is_a?(Hash)
            {
              "id" => normalize_mod_id(mod["id"] || mod["uid"]),
              "version" => mod["version"].to_s
            }
          else
            {
              "id" => normalize_mod_id(mod),
              "version" => ""
            }
          end
        end.reject { |mod| mod["id"].empty? }
      end

      def profile_tags_from_mods(mods)
        Array(mods).flat_map do |mod|
          entry = @entries[normalize_mod_id(mod["id"])]
          entry ? Array(entry["tags"]) : []
        end
      rescue
        []
      end

      def normalize_version_map(value)
        return {} unless value.is_a?(Hash)
        value.each_with_object({}) do |(key, version), memo|
          id = normalize_mod_id(key)
          memo[id] = version.to_s unless id.empty? || version.to_s.empty?
        end
      end

      def normalize_authors(value)
        if value.is_a?(Array)
          value.map { |author| author.to_s }
        else
          value.to_s.empty? ? [] : [value.to_s]
        end
      end

      def normalize_mod_id(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "")
      end

      def normalize_string_array(value)
        Array(value).map { |entry| normalize_mod_id(entry) }.reject { |entry| entry.empty? }.uniq
      end

      def display_tags(value)
        Array(value).map { |tag| tag.to_s }.reject { |tag| reserved_admin_tag?(tag) }
      end

      def reserved_admin_tag?(tag)
        ["specialentry", "special", "featured"].include?(tag_key(tag))
      end

      def tag_key(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
      end

      def truthy?(value)
        return value if value == true || value == false
        ["1", "true", "yes", "on", "enabled"].include?(value.to_s.strip.downcase)
      end

      def ensure_directory(path)
        target = path.to_s
        return if target.empty? || Dir.exist?(target)
        parent = File.dirname(target)
        ensure_directory(parent) if parent && parent != target && !Dir.exist?(parent)
        Dir.mkdir(target) unless Dir.exist?(target)
      end

      def glob_path(*parts)
        File.join(*parts).gsub("\\", "/")
      end

      def normalize_path(path)
        path.to_s.gsub("\\", "/")
      end

      def expand_game_path(path)
        value = path.to_s
        File.expand_path(value)
      end

      def temp_root
        root = ENV["TEMP"] || ENV["TMP"] || "."
        path = File.join(root, "HoennReloaded")
        ensure_directory(path)
        path
      end

      def safe_filename(value)
        value.to_s.gsub(/[^a-zA-Z0-9_\-]+/, "_")
      end

      def log(message, level = :info)
        return unless defined?(Reloaded::Log)
        Reloaded::Log.write(:mods, "[browser] #{message}", level: level)
      end
    end
  end
end
