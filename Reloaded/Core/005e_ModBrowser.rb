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

begin
  require "net/http"
  require "uri"
rescue Exception
end

module Reloaded
  module ModBrowser
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    MODS_DIR = File.join(GAME_ROOT, "Mods")
    TOOL_DIR = File.join(GAME_ROOT, "Modders Tools")
    DEFAULT_GITHUB_INDEX_URL = "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded-Mods/main/index.json"
    CORE_ENTRY_ID = "hoenn_reloaded"
    SPRITEPACK_ENTRY_ID = "spritepacks"
    CORE_VERSION_URL = "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/main/Reloaded/Version.md"
    CORE_CHANGELOG_PATH = "Reloaded/Changelog.md"
    CORE_HOMEPAGE_URL = "https://github.com/Stonewallxx/Hoenn-Reloaded"
    SPRITEPACK_CONFIG_URL = "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/main/Reloaded/Spritepacks.json"
    SPRITEPACK_CONFIG_PATH = File.join(ROOT, "Spritepacks.json")
    SPRITEPACK_INSTALL_STATE_PATH = File.join(GAME_ROOT, "Mods", "Reloaded", "SpritepacksInstalled.json")
    NETWORK_TIMEOUT_SECONDS = 8

    SOURCE_VERSION = 1
    INDEX_VERSION = 1

    @sources = []
    @entries = {}
    @profile_entries = {}
    @source_statuses = {}
    @last_refresh_at = nil
    @last_remote_fetch_at = nil
    @last_refresh_remote = false
    @spritepack_config_cache = nil
    @spritepack_config_source = nil
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
        @spritepack_config_cache = nil
        @spritepack_config_source = nil
        @last_refresh_at = Time.now rescue nil
        @last_refresh_remote = fetch_remote
        @sources.each { |source| load_source_index(source, fetch_remote: fetch_remote) if truthy?(source["enabled"]) }
        register_core_entry(fetch_remote: fetch_remote)
        register_spritepack_entry(fetch_remote: fetch_remote)
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

      def core_entry
        @entries[CORE_ENTRY_ID] || build_core_entry
      end

      def spritepack_entry
        @entries[SPRITEPACK_ENTRY_ID] || build_spritepack_entry
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
        unless validate_install_roots(roots, archive_path)
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

      def spritepack_files(fetch_remote: false)
        files = normalize_spritepack_files(spritepack_config(fetch_remote: fetch_remote)["files"])
        files.empty? ? default_spritepack_files : files
      end

      def spritepack_latest_files
        full = spritepack_full_file
        latest = spritepack_latest_file
        [full, latest].compact.uniq { |file| file["id"].to_s }
      end

      def spritepack_all_files
        spritepack_files
      end

      def spritepack_full_file
        spritepack_files.find { |file| truthy?(file["full"]) } || spritepack_files.first
      end

      def spritepack_latest_file
        explicit = spritepack_files.find { |file| !truthy?(file["full"]) && truthy?(file["latest"]) }
        explicit || spritepack_files.find { |file| !truthy?(file["full"]) }
      end

      def download_spritepack(file)
        item = normalize_spritepack_file(file, 0)
        name = item["name"].to_s.empty? ? "Spritepack" : item["name"].to_s
        url = item["url"].to_s.strip
        return { :success => false, :status => :missing_url, :name => name } if url.empty?
        filename = "spritepack_#{safe_filename(item["id"].to_s.empty? ? name : item["id"])}_#{Time.now.to_i}#{spritepack_archive_extension(url)}"
        archive = File.join(temp_root, filename)
        log("Spritepack download requested: name=#{name} url=#{url} archive=#{relative_game_path(archive)}")
        unless download_file(url, archive, min_bytes: 1024, label: name)
          File.delete(archive) rescue nil
          log("Spritepack download failed: #{name} url=#{url}", :error)
          return { :success => false, :status => :download_failed, :name => name, :url => url }
        end
        destination = spritepack_extract_destination(item)
        log("Spritepack archive downloaded: name=#{name} bytes=#{File.size(archive) rescue 0} destination=#{relative_game_path(destination)}")
        unless extract_archive(archive, destination)
          File.delete(archive) rescue nil
          return { :success => false, :status => :extract_failed, :name => name, :url => url }
        end
        File.delete(archive) rescue nil
        record_spritepack_installed(item, destination)
        log("Installed spritepack #{name} to #{relative_game_path(destination)}")
        { :success => true, :status => :ok, :name => name, :destination => destination }
      rescue Exception => e
        File.delete(archive) rescue nil if archive
        Reloaded::Log.exception("Spritepack download failed", e, channel: :mods) if defined?(Reloaded::Log)
        { :success => false, :status => :error, :name => name.to_s, :error => e.message }
      end

      def mark_spritepack_installed(file, destination = nil)
        item = normalize_spritepack_file(file, 0)
        name = item["name"].to_s.empty? ? "Spritepack" : item["name"].to_s
        destination ||= spritepack_extract_destination(item)
        summary = {
          :success => true,
          :manual => true,
          :total => 0,
          :copied => 0,
          :skipped => 0,
          :failed => 0,
          :elapsed => 0.0
        }
        record_spritepack_installed(item, destination, summary)
        log("Marked spritepack installed manually: #{name} destination=#{relative_game_path(destination)}")
        { :success => true, :status => :ok, :name => name, :destination => destination, :manual => true }
      rescue Exception => e
        Reloaded::Log.exception("Could not mark spritepack installed", e, channel: :mods) if defined?(Reloaded::Log)
        { :success => false, :status => :error, :name => name.to_s, :error => e.message }
      end

      def spritepack_installed?(file)
        item = normalize_spritepack_file(file, 0)
        id = item["id"].to_s
        return false if id.empty?
        records = spritepack_install_records
        record = records[id]
        return true if spritepack_install_record_matches?(record, item)
        return false if truthy?(item["full"])
        installed_full = records.values.find { |candidate| truthy?(candidate["full"]) }
        spritepack_full_contains_pack?(installed_full, item)
      rescue
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
        if virtual_entry?(item)
          plan[:already_installed] << mod_id
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
        if normalize_mod_id(mod_id) == CORE_ENTRY_ID
          minimum = minimum_version.to_s
          return true if minimum.empty?
          return compare_versions(current_reloaded_version, minimum) >= 0
        end
        return false unless defined?(Reloaded::ModManager)
        row = Reloaded::ModManager.mod_row(mod_id)
        return false unless row
        minimum = minimum_version.to_s
        return true if minimum.empty?
        compare_versions(row[:version], minimum) >= 0
      rescue
        false
      end

      def virtual_entry?(entry)
        truthy?(entry["virtual"]) || truthy?(entry["protected"]) || truthy?(entry["core_entry"])
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

      def register_core_entry(fetch_remote: false)
        item = build_core_entry(fetch_remote: fetch_remote)
        @entries[item["id"]] = item
        @source_statuses["hoenn_reloaded"] ||= fetch_remote ? "cached" : "local"
      rescue Exception => e
        Reloaded::Log.exception("Failed to register Hoenn Reloaded browser entry", e, channel: :mods) if defined?(Reloaded::Log)
      end

      def register_spritepack_entry(fetch_remote: false)
        item = build_spritepack_entry(fetch_remote: fetch_remote)
        @entries[item["id"]] = item
        @source_statuses["spritepacks"] ||= @spritepack_config_source || "local"
      rescue Exception => e
        Reloaded::Log.exception("Failed to register Spritepacks browser entry", e, channel: :mods) if defined?(Reloaded::Log)
      end

      def build_core_entry(fetch_remote: false)
        current = current_reloaded_version
        latest = current
        if fetch_remote
          remote = fetch_url(CORE_VERSION_URL, cache_bust: true).to_s.strip
          version = remote[/\d+\.\d+\.\d+/]
          if version
            latest = version
            @source_statuses["hoenn_reloaded"] = "remote"
          end
        end
        {
          "id" => CORE_ENTRY_ID,
          "kind" => "mod",
          "name" => "Hoenn Reloaded",
          "version" => current,
          "latest_version" => latest,
          "authors" => ["Stonewall"],
          "description" => "The core Hoenn Reloaded framework, systems, and built-in features for this fork.",
          "tags" => ["Core"],
          "dependencies" => [],
          "download_url" => "",
          "versions" => [{
            "version" => latest,
            "download_url" => "",
            "reloaded_version" => current,
            "changelog" => "",
            "changelogurl" => CORE_CHANGELOG_PATH,
            "dependencies" => []
          }],
          "homepage_url" => CORE_HOMEPAGE_URL,
          "changelogurl" => CORE_CHANGELOG_PATH,
          "source_id" => "hoenn_reloaded",
          "featured" => true,
          "special_entry" => true,
          "virtual" => true,
          "protected" => true,
          "core_entry" => true
        }
      end

      def build_spritepack_entry(fetch_remote: false)
        config = spritepack_config(fetch_remote: fetch_remote)
        files = normalize_spritepack_files(config["files"])
        files = default_spritepack_files if files.empty?
        latest = spritepack_latest_file
        full = spritepack_full_file
        {
          "id" => SPRITEPACK_ENTRY_ID,
          "kind" => "mod",
          "name" => "Spritepacks",
          "version" => latest ? latest["name"].to_s : "",
          "latest_version" => latest ? latest["name"].to_s : "",
          "authors" => ["Hoenn Reloaded"],
          "description" => config["description"].to_s,
          "tags" => ["Spritepacks"],
          "dependencies" => [],
          "download_url" => "",
          "versions" => [],
          "homepage_url" => "",
          "changelogurl" => "",
          "source_id" => "spritepacks",
          "featured" => true,
          "special_entry" => true,
          "virtual" => true,
          "protected" => true,
          "spritepack_entry" => true,
          "spritepack_count" => files.length,
          "spritepack_full" => full,
          "spritepack_latest" => latest
        }
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
        copy["latest_version"] = selected["version"].to_s
        copy["download_url"] = selected["download_url"].to_s
        copy["versions"] = [selected]
        copy["dependencies"] = normalize_dependencies(selected["dependencies"])
        copy
      end

      def spritepack_config(fetch_remote: false)
        return @spritepack_config_cache if @spritepack_config_cache && (!fetch_remote || @spritepack_config_source == "remote")
        if fetch_remote
          remote = load_remote_spritepack_config
          return remote if remote
        end
        local = load_local_spritepack_config
        @spritepack_config_cache = local
        @spritepack_config_source = File.exist?(SPRITEPACK_CONFIG_PATH) ? "local" : "default"
        local
      rescue Exception => e
        log("Spritepack config could not be read: #{e.class}: #{e.message}", :warning)
        @spritepack_config_cache = default_spritepack_config
        @spritepack_config_source = "default"
        default_spritepack_config
      end

      def load_remote_spritepack_config
        raw = fetch_url(SPRITEPACK_CONFIG_URL, cache_bust: true).to_s
        return nil if raw.strip.empty?
        parsed = parse_json(raw)
        unless parsed.is_a?(Hash)
          log("Remote Spritepacks config was not a JSON object", :warning)
          return nil
        end
        @last_remote_fetch_at = Time.now rescue @last_remote_fetch_at
        @spritepack_config_cache = default_spritepack_config.merge(parsed)
        @spritepack_config_source = "remote"
        @spritepack_config_cache
      rescue Exception => e
        log("Remote Spritepacks config could not be read: #{e.class}: #{e.message}", :warning)
        nil
      end

      def load_local_spritepack_config
        return default_spritepack_config unless File.exist?(SPRITEPACK_CONFIG_PATH)
        parsed = parse_json(File.read(SPRITEPACK_CONFIG_PATH))
        parsed.is_a?(Hash) ? default_spritepack_config.merge(parsed) : default_spritepack_config
      end

      def default_spritepack_config
        {
          "description" => "Spritepacks for Hoenn Reloaded.\nIncludes Pokemon, trainer, overworld, and custom battler sprite files.",
          "extract_to" => ".",
          "files" => default_spritepack_files
        }
      end

      def default_spritepack_files
        [
          { "id" => "full", "name" => "Full Spritepack", "url" => "", "updated_at" => "", "full" => true, "latest" => true },
          { "id" => "latest", "name" => "Latest Spritepack", "url" => "", "updated_at" => "", "latest" => true }
        ]
      end

      def normalize_spritepack_files(value)
        Array(value).each_with_index.map { |file, index| normalize_spritepack_file(file, index) }.
          reject { |file| file["name"].to_s.empty? }.
          sort_by { |file| spritepack_sort_key(file) }
      end

      def normalize_spritepack_file(file, index)
        source = file.is_a?(Hash) ? file : {}
        name = source["name"].to_s.strip
        id = source["id"].to_s.strip
        id = normalize_mod_id(name.empty? ? "spritepack_#{index + 1}" : name) if id.empty?
        {
          "id" => id,
          "name" => name.empty? ? id : name,
          "url" => source["url"].to_s.strip,
          "full" => truthy?(source["full"]),
          "latest" => truthy?(source["latest"]),
          "updated_at" => source["updated_at"].to_s.empty? ? source["update_date"].to_s : source["updated_at"].to_s,
          "released_at" => source["released_at"].to_s,
          "version" => source["version"].to_s,
          "extract_to" => source["extract_to"].to_s,
          "_index" => index.to_i
        }
      end

      def spritepack_sort_key(file)
        return [0, 0, 0, 0] if truthy?(file["full"])
        updated = spritepack_date_sort_value(file["updated_at"])
        version = file["version"].to_s.empty? ? file["name"].to_s : file["version"].to_s
        parts = version_sort_key(version)
        return [1, -updated, -(parts[0] || 0), -(parts[1] || 0), -(parts[2] || 0), file["_index"].to_i] if updated > 0
        [1, -(parts[0] || 0), -(parts[1] || 0), -(parts[2] || 0), file["_index"].to_i]
      end

      def spritepack_date_sort_value(value)
        text = value.to_s.strip
        match = text.match(/\A(\d{1,2})-(\d{1,2})-(\d{2,4})(?:\s+(\d{1,2}):(\d{2}):(\d{2}))?\z/)
        return 0 unless match
        month = match[1].to_i
        day = match[2].to_i
        year = match[3].to_i
        hour = match[4].to_i
        minute = match[5].to_i
        second = match[6].to_i
        year += year >= 70 ? 1900 : 2000 if year < 100
        return 0 if month < 1 || month > 12 || day < 1 || day > 31
        return 0 if hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59
        (((year * 10_000 + month * 100 + day) * 100 + hour) * 100 + minute) * 100 + second
      end

      def spritepack_install_records
        return {} unless File.exist?(SPRITEPACK_INSTALL_STATE_PATH)
        data = parse_json_file(SPRITEPACK_INSTALL_STATE_PATH)
        files = data.is_a?(Hash) ? data["files"] : {}
        files.is_a?(Hash) ? files : {}
      rescue
        {}
      end

      def record_spritepack_installed(item, destination, import = nil)
        records = spritepack_install_records
        id = item["id"].to_s
        return if id.empty?
        import ||= {}
        records[id] = {
          "id" => id,
          "name" => item["name"].to_s,
          "url" => item["url"].to_s,
          "updated_at" => item["updated_at"].to_s,
          "full" => truthy?(item["full"]),
          "manual" => import[:manual] ? true : false,
          "files_total" => import[:total].to_i,
          "files_copied" => import[:copied].to_i,
          "files_skipped" => import[:skipped].to_i,
          "files_failed" => import[:failed].to_i,
          "import_elapsed_seconds" => format("%.2f", import[:elapsed].to_f),
          "installed_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S %z"),
          "destination" => relative_game_path(destination)
        }
        ensure_directory(File.dirname(SPRITEPACK_INSTALL_STATE_PATH))
        File.open(SPRITEPACK_INSTALL_STATE_PATH, "w") do |file|
          file.write(JSON.generate({ "version" => 1, "files" => records }))
        end
      rescue Exception => e
        log("Could not update Spritepack install state: #{e.class}: #{e.message}", :warning)
      end

      def spritepack_install_record_matches?(record, item)
        return false unless record
        record["url"].to_s == item["url"].to_s && record["updated_at"].to_s == item["updated_at"].to_s
      rescue
        false
      end

      def spritepack_full_contains_pack?(full_record, pack)
        return false unless full_record && pack
        numbers = spritepack_identity_numbers(pack)
        return false if numbers.empty?
        haystack = [
          full_record["name"],
          full_record["id"],
          full_record["version"],
          full_record["url"],
          full_record["updated_at"]
        ].map(&:to_s).join(" ")
        numbers.any? { |number| haystack.match?(/(?:\D|\A)#{Regexp.escape(number)}(?:\D|\z)/) }
      rescue
        false
      end

      def spritepack_identity_numbers(file)
        [file["version"], file["name"], file["id"], file["url"]].map(&:to_s).join(" ").scan(/\d+/).uniq
      rescue
        []
      end

      def spritepack_extract_destination(file)
        extract_to = file["extract_to"].to_s.strip
        extract_to = spritepack_config["extract_to"].to_s.strip if extract_to.empty?
        extract_to = "." if extract_to.empty?
        destination = File.expand_path(File.join(GAME_ROOT, extract_to))
        root = normalize_path(GAME_ROOT)
        target = normalize_path(destination)
        raise "Spritepack extract path is outside the game folder." unless target == root || target.start_with?(root + "/")
        ensure_directory(destination)
        destination
      end

      def spritepack_archive_extension(url)
        path = URI.parse(url.to_s).path rescue url.to_s
        ext = File.extname(path.to_s).downcase
        return ext if [".zip", ".rar", ".7z"].include?(ext)
        ".zip"
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

      def download_file(url, destination, min_bytes: 1, label: nil)
        File.delete(destination) rescue nil
        log("Download start: url=#{url} destination=#{relative_game_path(destination)} min_bytes=#{min_bytes}")
        begin
          pbDownloadToFile(url, destination)
        rescue Exception => e
          log("pbDownloadToFile failed for #{url}: #{e.class}: #{e}", :warning)
        end
        if valid_download?(destination, min_bytes)
          log("Download completed with pbDownloadToFile: #{relative_game_path(destination)} bytes=#{File.size(destination) rescue 0}")
          return true
        end
        pb_size = File.exist?(destination) ? File.size(destination).to_i : 0
        log("pbDownloadToFile did not produce a valid file for #{url}: exists=#{File.exist?(destination)} bytes=#{pb_size}", :warning)
        File.delete(destination) rescue nil
        ok = download_file_with_powershell(url, destination, min_bytes: min_bytes, label: label)
        return true if ok
        ok = download_file_with_http_lite(url, destination, min_bytes: min_bytes)
        return true if ok
        if defined?(Net::HTTP) && defined?(URI)
          ok = download_file_with_net_http(url, destination, min_bytes: min_bytes)
          return true if ok
        else
          log("Net::HTTP is not available for download fallback", :warning)
        end
        valid_download?(destination, min_bytes)
      rescue Exception => e
        Reloaded::Log.exception("Download command failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def download_file_with_powershell(url, destination, min_bytes: 1, label: nil)
        powershell = powershell_path
        unless powershell
          log("PowerShell downloader is not available", :warning)
          return false
        end
        ensure_directory(File.dirname(destination))
        script = File.join(temp_root, "download_#{Time.now.to_i}_#{rand(100000)}.ps1")
        error_file = "#{script}.error.txt"
        display = label.to_s.strip
        display = File.basename(destination.to_s) if display.empty?
        ps = [
          "$ErrorActionPreference = 'Stop'",
          "try {",
          "  $title = 'Downloading #{powershell_literal(display)}...'",
          "  try { $host.UI.RawUI.WindowTitle = $title } catch {}",
          "  Write-Host $title",
          "  Write-Host ''",
          "  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12",
          "  $wc = New-Object Net.WebClient",
          "  $wc.Headers['User-Agent'] = 'Hoenn Reloaded Mod Browser'",
          "  $wc.DownloadFile('#{powershell_literal(url)}', '#{powershell_literal(destination)}')",
          "  exit 0",
          "} catch {",
          "  [IO.File]::WriteAllText('#{powershell_literal(error_file)}', $_.Exception.ToString())",
          "  exit 1",
          "}"
        ].join("\n")
        File.open(script, "wb") { |file| file.write(ps) }
        log("PowerShell download request: #{url}")
        ok = system("\"#{powershell}\" -NoProfile -ExecutionPolicy Bypass -File \"#{script}\"")
        File.delete(script) rescue nil
        if !ok && File.exist?(error_file)
          log("PowerShell download error: #{File.read(error_file).to_s[0, 700]}", :error)
        end
        File.delete(error_file) rescue nil
        size = File.exist?(destination) ? File.size(destination).to_i : 0
        valid = ok && size >= min_bytes.to_i
        log("PowerShell download wrote #{relative_game_path(destination)} exit_ok=#{ok} bytes=#{size} ok=#{valid}")
        File.delete(destination) rescue nil unless valid
        valid
      rescue Exception => e
        File.delete(script) rescue nil if defined?(script) && script
        File.delete(error_file) rescue nil if defined?(error_file) && error_file
        log("PowerShell download failed for #{url}: #{e.class}: #{e.message}", :error)
        false
      end

      def powershell_path
        root = ENV["SystemRoot"].to_s
        candidates = []
        candidates << File.join(root, "System32", "WindowsPowerShell", "v1.0", "powershell.exe") unless root.empty?
        candidates << "powershell.exe"
        candidates.find { |path| path == "powershell.exe" || File.exist?(path) }
      end

      def powershell_literal(value)
        value.to_s.gsub("'", "''")
      end

      def download_file_with_http_lite(url, destination, min_bytes: 1, redirect_limit: 6)
        unless defined?(HTTPLite)
          log("HTTPLite is not available for download fallback", :warning)
          return false
        end
        current = url.to_s
        redirects = 0
        loop do
          log("HTTPLite download request: #{current}")
          response = HTTPLite.get(current, download_headers) rescue nil
          unless response.is_a?(Hash)
            log("HTTPLite download returned no response for #{current}", :warning)
            return false
          end
          status = response[:status].to_i
          log("HTTPLite download response: status=#{status} keys=#{response.keys.map(&:to_s).join(',')}")
          if [301, 302, 303, 307, 308].include?(status)
            location = http_response_location(response)
            log("HTTPLite download redirect #{status}: #{location}")
            return false if location.empty?
            redirects += 1
            if redirects > redirect_limit
              log("HTTPLite download exceeded redirect limit for #{url}", :error)
              return false
            end
            current = join_url(current, location)
            next
          end
          unless status == 200
            log("HTTPLite download failed for #{current}: HTTP #{status}", :warning)
            return false
          end
          body = response[:body].to_s
          ensure_directory(File.dirname(destination))
          File.open(destination, "wb") { |file| file.write(body) }
          size = File.exist?(destination) ? File.size(destination).to_i : 0
          ok = size >= min_bytes.to_i
          log("HTTPLite download wrote #{relative_game_path(destination)} bytes=#{size} ok=#{ok}")
          File.delete(destination) rescue nil unless ok
          return ok
        end
      rescue Exception => e
        log("HTTPLite download failed for #{url}: #{e.class}: #{e.message}", :error)
        false
      end

      def download_file_with_net_http(url, destination, min_bytes: 1, redirect_limit: 6)
        current = url.to_s
        redirects = 0
        loop do
          uri = URI.parse(current)
          request = Net::HTTP::Get.new(uri)
          request["Cache-Control"] = "no-cache"
          request["Pragma"] = "no-cache"
          request["User-Agent"] = "Hoenn Reloaded Mod Browser"
          log("Net::HTTP download request: #{current}")
          response = nil
          Net::HTTP.start(
            uri.host,
            uri.port,
            :use_ssl => uri.scheme == "https",
            :open_timeout => NETWORK_TIMEOUT_SECONDS,
            :read_timeout => NETWORK_TIMEOUT_SECONDS
          ) do |http|
            http.request(request) do |res|
              response = res
              code = res.code.to_i
              if code == 200
                ensure_directory(File.dirname(destination))
                File.open(destination, "wb") { |file| res.read_body { |chunk| file.write(chunk) } }
              end
            end
          end
          unless response
            log("Net::HTTP download returned no response for #{current}", :error)
            return false
          end
          code = response.code.to_i
          if [301, 302, 303, 307, 308].include?(code)
            location = response["location"].to_s
            log("Net::HTTP download redirect #{code}: #{location}")
            return false if location.empty?
            redirects += 1
            if redirects > redirect_limit
              log("Net::HTTP download exceeded redirect limit for #{url}", :error)
              return false
            end
            current = URI.join(current, location).to_s rescue location
            next
          end
          unless code == 200
            log("Net::HTTP download failed for #{current}: HTTP #{code}", :error)
            return false
          end
          size = File.exist?(destination) ? File.size(destination).to_i : 0
          ok = size >= min_bytes.to_i
          log("Net::HTTP download wrote #{relative_game_path(destination)} bytes=#{size} ok=#{ok}")
          return ok
        end
      rescue Exception => e
        log("Net::HTTP download failed for #{url}: #{e.class}: #{e.message}", :error)
        false
      end

      def download_headers
        {
          "Cache-Control" => "no-cache",
          "Proxy-Connection" => "Close",
          "Pragma" => "no-cache",
          "User-Agent" => "Hoenn Reloaded Mod Browser"
        }
      end

      def http_response_location(response)
        direct = response[:location] || response["location"] || response[:Location] || response["Location"]
        return direct.to_s if direct && !direct.to_s.empty?
        headers = response[:headers] || response["headers"] || response[:header] || response["header"]
        if headers.respond_to?(:[])
          value = headers[:location] || headers["location"] || headers[:Location] || headers["Location"]
          return value.to_s if value && !value.to_s.empty?
        end
        ""
      end

      def join_url(base, location)
        return URI.join(base, location).to_s if defined?(URI)
        return location if location.to_s =~ /\Ahttps?:\/\//i
        location
      rescue
        location.to_s
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
        return fetch_url_with_net_http(request_url) if defined?(Net::HTTP) && defined?(URI)
        nil
      end

      def fetch_url_with_net_http(url)
        uri = URI.parse(url.to_s)
        request = Net::HTTP::Get.new(uri)
        request["Cache-Control"] = "no-cache"
        request["Pragma"] = "no-cache"
        request["User-Agent"] = "Hoenn Reloaded Mod Browser"
        response = Net::HTTP.start(
          uri.host,
          uri.port,
          :use_ssl => uri.scheme == "https",
          :open_timeout => NETWORK_TIMEOUT_SECONDS,
          :read_timeout => NETWORK_TIMEOUT_SECONDS
        ) { |http| http.request(request) }
        response.code.to_i == 200 ? response.body.to_s : nil
      rescue Exception => e
        log("Net::HTTP fetch failed for #{url}: #{e.class}: #{e.message}", :warning)
        nil
      end

      def cache_busted_url(url)
        joiner = url.to_s.include?("?") ? "&" : "?"
        "#{url}#{joiner}rld_cache=#{Time.now.to_i}_#{rand(100000)}"
      end

      def extract_archive(archive_path, destination)
        sevenz = File.expand_path("./REQUIRED_BY_INSTALLER_UPDATER/7z.exe")
        started_at = Time.now
        log("Archive extraction start: archive=#{relative_game_path(archive_path)} bytes=#{File.size(archive_path) rescue 0} destination=#{relative_game_path(destination)} sevenz=#{relative_game_path(sevenz)}")
        ok = if File.exist?(sevenz)
             system("\"#{sevenz}\" x -y -mmt=on -bsp1 -bso1 \"-o#{destination}\" \"#{archive_path}\"")
             else
              log("Archive extraction failed: 7z.exe was not found", :error)
              false
             end
        elapsed = Time.now - started_at
        unless ok
          log("Archive extraction failed: archive=#{relative_game_path(archive_path)} destination=#{relative_game_path(destination)} elapsed=#{format('%.2f', elapsed)}s", :error)
          return false
        end
        log("Archive extraction succeeded: archive=#{relative_game_path(archive_path)} destination=#{relative_game_path(destination)} elapsed=#{format('%.2f', elapsed)}s")
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

      def validate_install_roots(roots, archive_path)
        errors = []
        Array(roots).each do |root|
          manifest_path = File.join(root, "mod.json")
          manifest = parse_json_file(manifest_path)
          unless manifest.is_a?(Hash)
            errors << "#{File.basename(root)}: Manifest root must be a JSON object."
            next
          end
          game = normalize_game_id(manifest["game"])
          next if game == target_game_id
          detail = game.empty? ? "No game field was set." : "game is #{game.inspect}."
          errors << "#{File.basename(root)}: THIS MOD ISN'T MADE FOR THIS GAME! #{detail}"
        rescue Exception => e
          errors << "#{File.basename(root)}: Manifest could not be parsed: #{e.class}: #{e.message}"
        end
        return true if errors.empty?
        errors.each { |error| log("Install rejected from #{File.basename(archive_path)}: #{error}", :critical) }
        false
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
        text = raw.to_s.sub("\xEF\xBB\xBF", "")
        begin
          stringify_json_keys(JSON.parse(text))
        rescue NameError => e
          raise unless e.message.to_s.include?("`null'")
          stringify_json_keys(JSON.parse(rewrite_json_null_literals(text)))
        end
      end

      def rewrite_json_null_literals(text)
        output = +""
        index = 0
        in_string = false
        escaped = false
        while index < text.length
          char = text[index]
          if in_string
            output << char
            if escaped
              escaped = false
            elsif char == "\\"
              escaped = true
            elsif char == "\""
              in_string = false
            end
            index += 1
            next
          end
          if char == "\""
            in_string = true
            output << char
            index += 1
            next
          end
          if text[index, 4] == "null" && json_literal_boundary?(text[index - 1]) && json_literal_boundary?(text[index + 4])
            output << "nil"
            index += 4
            next
          end
          output << char
          index += 1
        end
        output
      end

      def json_literal_boundary?(char)
        char.nil? || char !~ /[A-Za-z0-9_]/
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

      def normalize_game_id(value)
        value.to_s.strip.downcase
      end

      def target_game_id
        defined?(Reloaded::ModManager::GAME_ID) ? Reloaded::ModManager::GAME_ID : "hoenn"
      end

      def current_reloaded_version
        Reloaded.version rescue "0.0.0"
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

      def relative_game_path(path)
        root = normalize_path(File.expand_path(GAME_ROOT))
        target = normalize_path(File.expand_path(path.to_s))
        return "." if target == root
        return target[(root.length + 1)..-1] if target.start_with?(root + "/")
        File.basename(target)
      rescue
        File.basename(path.to_s)
      end

      def log(message, level = :info)
        return unless defined?(Reloaded::Log)
        Reloaded::Log.write(:mods, "[browser] #{message}", level: level)
      end
    end
  end
end
