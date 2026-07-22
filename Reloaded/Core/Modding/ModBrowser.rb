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
  require "uri"
rescue Exception
end

module Reloaded
  module ModBrowser
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    MODS_DIR = File.join(GAME_ROOT, "Mods")
    TOOL_DIR = File.join(GAME_ROOT, "ModDev")
    DEFAULT_GITHUB_INDEX_URL = "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded-Mods/main/index.json"
    CORE_ENTRY_ID = "hoenn_reloaded"
    SPRITEPACK_ENTRY_ID = "spritepacks"
    CORE_VERSION_URL = "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/main/Reloaded/Version.md"
    CORE_VERSION_API_URL = "https://api.github.com/repos/Stonewallxx/Hoenn-Reloaded/contents/Reloaded/Version.md?ref=main"
    CORE_VERSION_SOURCES = [
      { :label => "public raw Version.md", :url => CORE_VERSION_URL, :headers => {} },
      { :label => "public GitHub API Version.md", :url => CORE_VERSION_API_URL, :headers => { "Accept" => "application/vnd.github.raw" } }
    ].freeze
    CORE_CHANGELOG_PATH = "Reloaded/Changelog.md"
    CORE_HOMEPAGE_URL = "https://github.com/Stonewallxx/Hoenn-Reloaded"
    SPRITEPACK_CONFIG_URL = "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/main/Reloaded/Spritepacks.json"
    SPRITEPACK_CONFIG_PATH = File.join(ROOT, "Spritepacks.json")
    SPRITEPACK_INSTALL_STATE_PATH = File.join(GAME_ROOT, "Mods", "Reloaded", "SpritepacksInstalled.json")
    SPRITEPACK_FULL_MANIFEST_PATH = File.join(GAME_ROOT, "Graphics", "SpritePacks", "manifest.json")
    CORE_VERSION_REMOTE_ID = :hoenn_reloaded_version
    SPRITEPACK_REMOTE_ID = :hoenn_reloaded_spritepacks
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
    @refresh_task = nil
    @refresh_completion = nil
    @refresh_success_callbacks = []
    @refresh_failure_callbacks = []
    @booted = false

    class << self
      def boot
        return true if @booted
        refresh(fetch_remote: false)
        @booted = true
        Reloaded::Log.info("Mod Browser registry ready with #{@entries.length} entr#{@entries.length == 1 ? 'y' : 'ies'}", :mods) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        @booted = false
        Reloaded::Log.exception("Mod Browser boot failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def refresh(fetch_remote: false)
        fetch_remote = false if defined?(Reloaded::Platform) && !Reloaded::Platform.supports?(:downloads)
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

      def start_remote_refresh(on_success: nil, on_failure: nil)
        return false if defined?(Reloaded::Platform) && !Reloaded::Platform.supports?(:downloads)
        return false unless defined?(Reloaded::Task)
        @refresh_success_callbacks << on_success if on_success.respond_to?(:call)
        @refresh_failure_callbacks << on_failure if on_failure.respond_to?(:call)
        return true if @refresh_task && @refresh_task.running?
        sources = load_sources
        remote_sources = sources.select { |source| truthy?(source["enabled"]) }.map do |source|
          [source, register_remote_source(source)]
        end
        ensure_core_remote_source
        ensure_spritepack_remote_source
        @refresh_completion = nil
        @refresh_task = Reloaded::Task.start(:mod_browser_refresh, {
          :owner => :mod_browser,
          :duplicate => :reuse,
          :timeout => 45,
          :on_success => proc do |outcome|
            apply_remote_refresh(outcome.value)
            @refresh_completion = true
            run_refresh_callbacks(@refresh_success_callbacks, outcome)
          end,
          :on_failure => proc do |outcome|
            @refresh_completion = false
            log("Remote browser refresh failed: #{outcome.error_message}", :warning)
            run_refresh_callbacks(@refresh_failure_callbacks, outcome)
          end,
          :on_cancel => proc do |outcome|
            @refresh_completion = false
            run_refresh_callbacks(@refresh_failure_callbacks, outcome)
          end
        }) do |task|
          fetched = []
          total = remote_sources.length + 2
          remote_sources.each_with_index do |pair, index|
            task.checkpoint!
            fetched << [pair[0], Reloaded::RemoteData.fetch(pair[1], :force => true)]
            task.report((index + 1).to_f / total, "Browser sources")
          end
          task.checkpoint!
          core = core_version_result(Reloaded::RemoteData.fetch(CORE_VERSION_REMOTE_ID, :force => true))
          task.report((remote_sources.length + 1).to_f / total, "Reloaded version")
          task.checkpoint!
          spritepacks = Reloaded::RemoteData.fetch(SPRITEPACK_REMOTE_ID, :force => true)
          task.report(1.0, "Spritepacks")
          { :sources => sources, :indexes => fetched, :core => core, :spritepacks => spritepacks }
        end
        true
      rescue Exception => e
        Reloaded::Log.exception("Mod Browser remote refresh failed to start", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def finish_remote_refresh
        return nil unless @refresh_task
        return nil if @refresh_task.running?
        result = @refresh_completion
        @refresh_task = nil
        @refresh_completion = nil
        result
      rescue Exception => e
        @refresh_task = nil
        @refresh_completion = nil
        Reloaded::Log.exception("Mod Browser remote refresh failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def remote_refresh_running?
        !!(@refresh_task && @refresh_task.running?)
      rescue
        false
      end

      def shutdown
        @refresh_task.cancel if @refresh_task && @refresh_task.running?
        @refresh_task = nil
        @refresh_completion = nil
        @refresh_success_callbacks.clear
        @refresh_failure_callbacks.clear
        true
      rescue Exception => e
        Reloaded::Log.exception("Mod Browser shutdown failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
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

      def published_profile_code(profile_id)
        item = profile_entry(profile_id)
        raise "Published profile not found: #{profile_id}" unless item
        profile_code_for(item)
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
        raise "Mod Browser downloads are unavailable on this platform." if defined?(Reloaded::Platform) && !Reloaded::Platform.supports?(:browser_downloads)
        plan = build_download_plan(mod_ids, versions: versions, fetch_remote: true)
        result = perform_download_plan(plan)
        apply_download_result(result, enable)
        result
      end

      def download_mods_async(mod_ids, enable: false, versions: {}, on_success: nil, on_failure: nil, notify: nil)
        raise "Background tasks are unavailable." unless defined?(Reloaded::Task)
        raise "Mod Browser downloads are unavailable on this platform." if defined?(Reloaded::Platform) && !Reloaded::Platform.supports?(:browser_downloads)
        plan = build_download_plan(mod_ids, versions: versions, fetch_remote: false)
        ids = normalize_string_array(mod_ids)
        Reloaded::Task.start("mod_download_#{ids.sort.join('_')}", {
          :owner => :mod_browser,
          :duplicate => :reuse,
          :on_success => proc do |outcome|
            apply_download_result(outcome.value, enable)
            on_success.call(outcome) if on_success.respond_to?(:call)
          end,
          :on_failure => on_failure,
          :notify => notify.nil? ? {
            :success => "Mod download complete.",
            :failure => "Mod download failed.",
            :success_theme => :success,
            :failure_theme => :error
          } : notify
        }) do |task|
          perform_download_plan(plan, task)
        end
      end

      def perform_download_plan(plan, task = nil)
        installed = []
        failed = plan[:missing].dup + plan[:version_mismatches].map { |entry| entry[:id] }
        no_download_url = []
        entries = Array(plan[:entries])
        entries.each_with_index do |item, index|
          task.checkpoint! if task
          id = item["id"].to_s
          task.report(index.to_f / [entries.length, 1].max, "Downloading #{id}") if task
          if item["download_url"].to_s.strip.empty?
            no_download_url << id
            failed << id
            log("No download URL configured for #{id}", :warning)
            next
          end
          low = index.to_f / [entries.length, 1].max
          high = (index + 1).to_f / [entries.length, 1].max
          if download_and_install(item, refresh: false, task: task, progress_range: [low, high])
            installed << id
          else
            failed << id
          end
          task.report((index + 1).to_f / [entries.length, 1].max, "Installing #{id}") if task
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

      def apply_download_result(result, enable)
        Reloaded::Task.assert_main_thread! if defined?(Reloaded::Task)
        Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
        if enable && defined?(Reloaded::Profiles)
          (Array(result[:installed]) + Array(result[:already_installed])).uniq.each { |id| Reloaded::Profiles.enable_mod(id) }
        end
        result
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

      def download_and_install(entry, refresh: true, task: nil, progress_range: [0.0, 1.0])
        item = normalize_entry(entry, "manual")
        low = progress_range[0].to_f
        high = progress_range[1].to_f
        span = [high - low, 0.0].max
        download_end = low + span * 0.55
        extract_end = low + span * 0.90
        archive = download_entry(item, task: task, progress_range: [low, download_end])
        return false unless archive && File.exist?(archive)
        task.checkpoint! if task
        ok = install_archive(
          archive,
          refresh: refresh,
          task: task,
          progress_range: [download_end, extract_end]
        )
        File.delete(archive) rescue nil
        task.report(high, "Installed #{item["name"]}") if task && ok
        task.checkpoint! if task
        ok
      rescue Reloaded::Task::Cancelled
        File.delete(archive) rescue nil if archive
        raise
      rescue Exception => e
        Reloaded::Log.exception("Failed to download/install #{entry["id"] rescue "unknown"}", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def install_archive(archive_path, refresh: true, task: nil, progress_range: [0.55, 0.90])
        return false unless File.exist?(archive_path)
        ensure_directory(MODS_DIR)
        staging = File.join(temp_root, "rld_install_#{Time.now.to_i}_#{rand(100000)}")
        backups = []
        ensure_directory(staging)
        task.checkpoint! if task
        task.report(nil, "Extracting mod archive") if task
        unless extract_archive(
          archive_path,
          staging,
          :task => task,
          :overwrite => :fail,
          :progress_range => progress_range
        )
          delete_tree(staging)
          return false
        end
        task.checkpoint! if task
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
        roots.each_with_index do |root, index|
          task.checkpoint! if task
          task.report(nil, "Installing #{File.basename(root)}") if task
          install_mod_root(root, backups)
        end
        delete_tree(staging)
        cleanup_install_backups(backups)
        Reloaded::ModManager.refresh_metadata if refresh && defined?(Reloaded::ModManager)
        log("Installed #{roots.length} mod folder(s) from #{File.basename(archive_path)}")
        true
      rescue Reloaded::Task::Cancelled
        restore_install_backups(backups) if backups
        delete_tree(staging) if staging
        raise
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
        result = perform_spritepack_download(file, nil)
        if result[:success]
          record_spritepack_installed(result[:item], result[:destination])
          result.delete(:item)
        end
        result
      end

      def download_spritepack_async(file, on_success: nil, on_failure: nil, notify: nil)
        raise "Background tasks are unavailable." unless defined?(Reloaded::Task)
        item = normalize_spritepack_file(file, 0)
        Reloaded::Task.start("spritepack_download_#{item['id']}", {
          :owner => :mod_browser,
          :duplicate => :reuse,
          :on_success => proc do |outcome|
            result = outcome.value
            if result[:success]
              record_spritepack_installed(result[:item], result[:destination])
              result.delete(:item)
            end
            on_success.call(outcome) if on_success.respond_to?(:call)
          end,
          :on_failure => on_failure,
          :notify => notify.nil? ? {
            :success => "Spritepack download complete.",
            :failure => "Spritepack download failed.",
            :success_theme => :success,
            :failure_theme => :error
          } : notify
        }) do |task|
          result = perform_spritepack_download(item, task)
          task.fail!(result[:error] || "Spritepack download failed.", result[:status] || :download_failed) unless result[:success]
          result
        end
      end

      def perform_spritepack_download(file, task = nil)
        return { :success => false, :status => :unsupported, :name => "Spritepack" } if defined?(Reloaded::Platform) && !Reloaded::Platform.supports?(:browser_downloads)
        item = normalize_spritepack_file(file, 0)
        name = item["name"].to_s.empty? ? "Spritepack" : item["name"].to_s
        parts = Array(item["parts"])
        return perform_split_spritepack_download(item, parts, task) unless parts.empty?
        components = Array(item["components"])
        return perform_component_spritepack_download(item, components, task) unless components.empty?
        url = item["url"].to_s.strip
        return { :success => false, :status => :missing_url, :name => name } if url.empty?
        filename = "spritepack_#{safe_filename(item["id"].to_s.empty? ? name : item["id"])}_#{Time.now.to_i}#{spritepack_archive_extension(url)}"
        archive = File.join(temp_root, filename)
        log("Spritepack download requested: name=#{name} url=#{url} archive=#{relative_game_path(archive)}")
        task.report(0.05, "Downloading #{name}") if task
        result = Reloaded::Download.fetch(
          url,
          archive,
          :task => task,
          :label => name,
          :min_bytes => 1024,
          :expected_bytes => item["size"],
          :sha256 => item["sha256"],
          :resume => true,
          :progress_range => [0.05, 0.68]
        )
        unless result.success?
          File.delete(archive) rescue nil
          log("Spritepack download failed: #{name} code=#{result.error_code} reason=#{result.error_message}", :error)
          return { :success => false, :status => result.error_code || :download_failed, :name => name, :url => url }
        end
        destination = spritepack_extract_destination(item)
        task.checkpoint! if task
        task.report(0.7, "Extracting #{name}") if task
        log("Spritepack archive downloaded: name=#{name} bytes=#{File.size(archive) rescue 0} destination=#{relative_game_path(destination)}")
        unless extract_archive(
          archive,
          destination,
          :task => task,
          :overwrite => :overwrite,
          :progress_range => [0.7, 0.98]
        )
          File.delete(archive) rescue nil
          return { :success => false, :status => :extract_failed, :name => name, :url => url }
        end
        File.delete(archive) rescue nil
        Reloaded::SpritePacks.clear_index if defined?(Reloaded::SpritePacks)
        log("Installed spritepack #{name} to #{relative_game_path(destination)}")
        task.report(1.0, "Installed #{name}") if task
        { :success => true, :status => :ok, :name => name, :destination => destination, :item => item }
      rescue Reloaded::Task::Cancelled
        File.delete(archive) rescue nil if archive
        raise
      rescue Exception => e
        File.delete(archive) rescue nil if archive
        Reloaded::Log.exception("Spritepack download failed", e, channel: :mods) if defined?(Reloaded::Log)
        { :success => false, :status => :error, :name => name.to_s, :error => e.message }
      end

      def perform_split_spritepack_download(item, parts, task = nil)
        name = item["name"].to_s.empty? ? "Spritepack" : item["name"].to_s
        archives = []
        cleanup_archives = false
        total = parts.length
        raise "Split Spritepack has no archive parts." if total <= 0
        expected_prefix = nil
        parts.each_with_index do |part, index|
          task.checkpoint! if task
          url = part["url"].to_s.strip
          raise "Spritepack part #{index + 1} has no download URL." if url.empty?
          source_name = part["file"].to_s.strip
          source_name = File.basename(URI.parse(url).path.to_s) if source_name.empty?
          source_name = File.basename(source_name)
          match = source_name.match(/\A(.+\.(?:zip|rar|7z))\.(\d{3})\z/i)
          raise "Spritepack part #{index + 1} has an invalid numbered filename." unless match
          expected_prefix ||= match[1].downcase
          raise "Spritepack parts do not belong to the same archive." unless expected_prefix == match[1].downcase
          raise "Spritepack parts are not in sequential order." unless match[2].to_i == index + 1
          filename = "spritepack_#{safe_filename(item['id'])}_#{source_name}"
          archive = File.join(temp_root, filename)
          segment_start = 0.05 + (index.to_f / total.to_f) * 0.63
          segment_end = 0.05 + ((index + 1).to_f / total.to_f) * 0.63
          result = Reloaded::Download.fetch(
            url,
            archive,
            :task => task,
            :label => "#{name} part #{index + 1}/#{total}",
            :min_bytes => 1,
            :expected_bytes => part["size"],
            :sha256 => part["sha256"],
            :resume => true,
            :progress_range => [segment_start, segment_end]
          )
          unless result.success?
            raise "Part #{index + 1}/#{total}: #{result.error_message}"
          end
          archives << archive
        end
        destination = spritepack_extract_destination(item)
        task.checkpoint! if task
        task.report(0.7, "Extracting #{name}") if task
        log("Split Spritepack downloaded: name=#{name} parts=#{archives.length} destination=#{relative_game_path(destination)}")
        extracted = extract_archive(
          archives.first,
          destination,
          :task => task,
          :overwrite => :overwrite,
          :progress_range => [0.7, 0.98]
        )
        raise "The verified Spritepack parts could not be extracted." unless extracted
        Reloaded::SpritePacks.clear_index if defined?(Reloaded::SpritePacks)
        task.report(1.0, "Installed #{name}") if task
        cleanup_archives = true
        {
          :success => true,
          :status => :ok,
          :name => name,
          :destination => destination,
          :parts => archives.length,
          :item => item
        }
      rescue Reloaded::Task::Cancelled
        raise
      rescue Exception => e
        Reloaded::Log.exception("Split Spritepack download failed", e, channel: :mods) if defined?(Reloaded::Log)
        { :success => false, :status => :error, :name => name.to_s, :error => e.message }
      ensure
        Array(archives).each { |archive| File.delete(archive) rescue nil } if cleanup_archives
      end

      def perform_component_spritepack_download(item, components, task = nil)
        name = item["name"].to_s.empty? ? "Spritepack" : item["name"].to_s
        installed = []
        total = components.length
        components.each_with_index do |component, index|
          task.checkpoint! if task
          component_name = component["name"].to_s
          component_name = component["id"].to_s if component_name.empty?
          component_name = "Component #{index + 1}" if component_name.empty?
          url = component["url"].to_s.strip
          if url.empty?
            return {
              :success => false,
              :status => :missing_url,
              :name => name,
              :error => "#{component_name} has no download URL.",
              :installed_components => installed
            }
          end
          segment_start = 0.04 + (index.to_f / total.to_f) * 0.92
          segment_end = 0.04 + ((index + 1).to_f / total.to_f) * 0.92
          download_end = segment_start + (segment_end - segment_start) * 0.68
          filename = "spritepack_#{safe_filename(item['id'])}_#{safe_filename(component['id'])}_#{Time.now.to_i}#{spritepack_archive_extension(url)}"
          archive = File.join(temp_root, filename)
          task.report(segment_start, "Downloading #{component_name}") if task
          result = Reloaded::Download.fetch(
            url,
            archive,
            :task => task,
            :label => component_name,
            :min_bytes => 1024,
            :expected_bytes => component["size"],
            :sha256 => component["sha256"],
            :resume => true,
            :progress_range => [segment_start, download_end]
          )
          unless result.success?
            File.delete(archive) rescue nil
            return {
              :success => false,
              :status => result.error_code || :download_failed,
              :name => name,
              :error => "#{component_name}: #{result.error_message}",
              :installed_components => installed
            }
          end
          destination = spritepack_extract_destination(component)
          task.report(download_end, "Installing #{component_name}") if task
          extracted = extract_archive(
            archive,
            destination,
            :task => task,
            :overwrite => :overwrite,
            :progress_range => [download_end, segment_end]
          )
          File.delete(archive) rescue nil
          unless extracted
            return {
              :success => false,
              :status => :extract_failed,
              :name => name,
              :error => "#{component_name} could not be extracted.",
              :installed_components => installed
            }
          end
          installed << component["id"].to_s
          log("Installed Spritepack component #{component_name} (#{index + 1}/#{total})")
        end
        Reloaded::SpritePacks.clear_index if defined?(Reloaded::SpritePacks)
        task.report(1.0, "Installed #{name}") if task
        {
          :success => true,
          :status => :ok,
          :name => name,
          :destination => GAME_ROOT,
          :components => installed,
          :item => item
        }
      rescue Reloaded::Task::Cancelled
        File.delete(archive) rescue nil if defined?(archive) && archive
        raise
      rescue Exception => e
        File.delete(archive) rescue nil if defined?(archive) && archive
        Reloaded::Log.exception("Component Spritepack download failed", e, channel: :mods) if defined?(Reloaded::Log)
        {
          :success => false,
          :status => :error,
          :name => name.to_s,
          :error => e.message,
          :installed_components => installed || []
        }
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
        if truthy?(item["full"])
          return spritepack_full_status(item)[:state] == :installed
        end
        records = spritepack_install_records
        record = records[id]
        return true if spritepack_install_record_matches?(record, item)
        spritepack_monthly_included_in_full?(item)
      rescue
        false
      end

      def spritepack_full_status(file = nil)
        item = normalize_spritepack_file(file || spritepack_full_file, 0)
        expected_build_id = item["build_id"].to_s
        result = {
          :state => :repair_needed,
          :label => "Repair Needed",
          :expected_build_id => expected_build_id,
          :installed_build_id => "",
          :reason => "The Full Spritepack manifest is missing."
        }
        return result unless File.file?(SPRITEPACK_FULL_MANIFEST_PATH)

        manifest = parse_json_file(SPRITEPACK_FULL_MANIFEST_PATH)
        unless spritepack_full_manifest_valid?(manifest)
          result[:reason] = "The Full Spritepack manifest or a component manifest is invalid."
          return result
        end

        installed_build_id = manifest["build_id"].to_s
        result[:installed_build_id] = installed_build_id
        result[:includes_updates_through] = manifest["includes_updates_through"].to_s
        if expected_build_id.empty? || installed_build_id == expected_build_id
          result[:state] = :installed
          result[:label] = "Installed"
          result[:reason] = ""
        else
          result[:state] = :update_available
          result[:label] = "Update Available"
          result[:reason] = "A newer Full Spritepack is available."
        end
        result
      rescue Exception => e
        {
          :state => :repair_needed,
          :label => "Repair Needed",
          :expected_build_id => (item && item["build_id"].to_s) || "",
          :installed_build_id => "",
          :reason => "The Full Spritepack manifest could not be read."
        }
      end

      def spritepack_status
        full = spritepack_full_file
        latest = spritepack_latest_file
        full_status = spritepack_full_status(full)
        latest_installed = latest ? spritepack_installed?(latest) : false
        state = full_status[:state]
        label = full_status[:label]
        if state == :installed
          if latest && !latest_installed
            state = :monthly_available
            label = "Monthly Update"
          else
            state = :up_to_date
            label = "Up to Date"
          end
        end
        full_status.merge(
          :state => state,
          :label => label,
          :full_state => full_status[:state],
          :full => full,
          :latest => latest,
          :latest_installed => latest_installed,
          :monthly_available => !!(latest && !latest_installed)
        )
      rescue
        {
          :state => :repair_needed,
          :label => "Repair Needed",
          :expected_build_id => "",
          :installed_build_id => "",
          :full_state => :repair_needed,
          :full => nil,
          :latest => nil,
          :latest_installed => false,
          :monthly_available => false
        }
      end

      def version_sort_key(version)
        parts = Reloaded::Versioning.parts(version)
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
        Reloaded::Versioning.compare(left, right)
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
        remote_id = register_remote_source(source)
        result = fetch_remote ? Reloaded::RemoteData.fetch(remote_id, :force => true) : Reloaded::RemoteData.load(remote_id)
        @source_statuses[source["id"].to_s] = remote_result_label(result)
        return unless result.ok?
        if result.remote_confirmed?
          @last_remote_fetch_at = Time.now rescue @last_remote_fetch_at
          log("Fetched browser source #{source["id"]}")
        end
        register_index(result.value, source)
      rescue Exception => e
        @source_statuses[source["id"].to_s] = "error" rescue nil
        Reloaded::Log.exception("Failed to load browser source #{source["id"]}", e, channel: :mods) if defined?(Reloaded::Log)
      end

      def register_remote_source(source)
        identity = [source["id"], source["url"], source["path"]].join("|")
        remote_id = Reloaded::RemoteData.key_for(:mod_browser_index, identity)
        local_path = source["path"].to_s.empty? ? nil : expand_game_path(source["path"])
        Reloaded::RemoteData.register(remote_id, {
          :owner => :mod_browser,
          :format => :json,
          :url => source["url"].to_s,
          :local_path => local_path,
          :timeout => NETWORK_TIMEOUT_SECONDS,
          :validator => proc { |value| browser_index_valid?(value) }
        })
        remote_id
      end

      def apply_remote_refresh(snapshot)
        Reloaded::Task.assert_main_thread! if defined?(Reloaded::Task)
        data = snapshot.is_a?(Hash) ? snapshot : {}
        @sources = Array(data[:sources])
        @entries = {}
        @profile_entries = {}
        @source_statuses = {}
        @spritepack_config_cache = nil
        @spritepack_config_source = nil
        @last_refresh_at = Time.now rescue nil
        @last_refresh_remote = true
        Array(data[:indexes]).each do |pair|
          source, result = pair
          next unless source.is_a?(Hash)
          @source_statuses[source["id"].to_s] = remote_result_label(result)
          next unless result && result.ok?
          @last_remote_fetch_at = Time.now rescue @last_remote_fetch_at if result.remote_confirmed?
          register_index(result.value, source)
        end
        spritepacks = data[:spritepacks]
        if spritepacks && spritepacks.ok?
          @spritepack_config_cache = default_spritepack_config.merge(spritepacks.value)
          @spritepack_config_source = remote_result_label(spritepacks)
          @last_remote_fetch_at = Time.now rescue @last_remote_fetch_at if spritepacks.remote_confirmed?
        end
        register_core_entry(fetch_remote: true, remote_result: data[:core])
        register_spritepack_entry(fetch_remote: false)
        @entries
      end

      def run_refresh_callbacks(callbacks, outcome)
        selected = Array(callbacks).dup
        callbacks.clear
        selected.each { |callback| callback.call(outcome) rescue nil }
      end

      def browser_index_valid?(data)
        return true if data.is_a?(Array)
        return false unless data.is_a?(Hash)
        ["mods", "entries", "value", "profiles", "published_profiles", "modpacks"].any? do |key|
          data[key].is_a?(Array)
        end
      rescue
        false
      end

      def remote_result_label(result)
        return "error" unless result && result.ok?
        case result.source
        when :remote then "remote"
        when :cache then "cached"
        when :local then "local"
        else "empty"
        end
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

      def register_core_entry(fetch_remote: false, remote_result: nil)
        item = build_core_entry(fetch_remote: fetch_remote, remote_result: remote_result)
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

      def build_core_entry(fetch_remote: false, remote_result: nil)
        current = current_reloaded_version
        latest = current
        update_check_status = fetch_remote ? "failed" : "local"
        update_check_failed = false
        update_check_error = ""
        if fetch_remote
          result = remote_result || fetch_core_version
          if result[:version]
            version = result[:version]
            latest = version
            update_check_status = "remote"
            @source_statuses["hoenn_reloaded"] = "remote"
            log("Hoenn Reloaded update check: current=v#{current} latest=v#{latest} source=#{result[:label]}")
          else
            update_check_failed = true
            update_check_error = result[:error].to_s
            @source_statuses["hoenn_reloaded"] = "failed"
            detail = update_check_error.empty? ? "no response" : update_check_error
            log("Hoenn Reloaded update check failed: current=v#{current} #{detail}", :warning)
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
          "core_entry" => true,
          "update_check_status" => update_check_status,
          "update_check_failed" => update_check_failed,
          "update_check_error" => update_check_error
        }
      end

      def fetch_core_version
        ensure_core_remote_source
        core_version_result(Reloaded::RemoteData.fetch(CORE_VERSION_REMOTE_ID))
      rescue Exception => e
        { :version => nil, :label => "", :error => e.message.to_s }
      end

      def ensure_core_remote_source
        Reloaded::RemoteData.register(CORE_VERSION_REMOTE_ID, {
          :owner => :mod_browser,
          :format => :text,
          :urls => CORE_VERSION_SOURCES,
          :local_path => File.join(ROOT, "Version.md"),
          :timeout => NETWORK_TIMEOUT_SECONDS,
          :validator => proc { |text| !!parse_version_text(text) }
        })
      end

      def core_version_result(result)
        if result.ok? && result.remote_confirmed?
          return {
            :version => parse_version_text(result.value),
            :label => result.url_label,
            :error => ""
          }
        end
        detail = result.error_message.to_s
        detail = result.error_code.to_s if detail.empty? && result.error_code
        detail = "remote version was not confirmed" if detail.empty?
        { :version => nil, :label => result.url_label.to_s, :error => detail }
      rescue Exception => e
        { :version => nil, :label => "", :error => e.message.to_s }
      end

      def parse_version_text(text)
        value = text.to_s[/\bv?(\d+\.\d+\.\d+)\b/i, 1]
        value && !value.empty? ? value : nil
      end

      def build_spritepack_entry(fetch_remote: false)
        config = spritepack_config(fetch_remote: fetch_remote)
        files = normalize_spritepack_files(config["files"])
        files = default_spritepack_files if files.empty?
        latest = spritepack_latest_file
        full = spritepack_full_file
        display_version = if full
                            full["build_id"].to_s.empty? ? full["name"].to_s : full["build_id"].to_s
                          else
                            ""
                          end
        {
          "id" => SPRITEPACK_ENTRY_ID,
          "kind" => "mod",
          "name" => "Spritepacks",
          "version" => display_version,
          "latest_version" => display_version,
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
          "sha256" => first_string(selected_version["sha256"], selected_version["checksum"], source["sha256"], source["checksum"]),
          "size" => positive_download_size(selected_version["size"] || selected_version["bytes"] || source["size"] || source["bytes"]),
          "versions" => versions,
          "homepage_url" => source["homepage_url"].to_s,
          "changelogurl" => first_string(source["changelogurl"], source["changelog_url"], selected_version["changelogurl"], selected_version["changelog_url"]),
          "release_url" => source["release_url"].to_s,
          "publisher_login" => source["publisher_login"].to_s,
          "published_at" => source["published_at"].to_s,
          "updated_at" => source["updated_at"].to_s,
          "source_id" => source_id.to_s,
          "featured" => truthy?(source["featured"]),
          "special_entry" => truthy?(source["special_entry"] || source["special"])
        }
      end

      def normalize_profile_entry(entry, source_id)
        source = entry.is_a?(Hash) ? entry : {}
        id = normalize_mod_id(source["id"] || source["uid"] || source["profile_id"])
        versions = normalize_profile_versions(source)
        selected_version = selected_version_entry(source, versions)
        mods = normalize_profile_mods(selected_version["mods"] || source["mods"])
        tags = (display_tags(source["tags"]) + profile_tags_from_mods(mods)).reject { |tag| tag_key(tag) == "profile" }.uniq
        tags.unshift("Profile")
        {
          "id" => id,
          "kind" => "profile",
          "name" => source["name"].to_s.empty? ? id : source["name"].to_s,
          "version" => selected_version["version"].to_s,
          "latest_version" => (source["latest_version"] || selected_version["version"]).to_s,
          "authors" => normalize_authors(source["authors"] || source["author"]),
          "description" => source["description"].is_a?(Array) ? source["description"].join("\n") : source["description"].to_s,
          "tags" => tags,
          "mods" => mods,
          "profile_code" => selected_version["profile_code"].to_s.empty? ? source["profile_code"].to_s : selected_version["profile_code"].to_s,
          "profile_url" => first_string(selected_version["profile_url"], source["profile_url"], source["url"]),
          "sha256" => first_string(selected_version["sha256"], source["sha256"], source["checksum"]),
          "size" => positive_download_size(selected_version["size"] || source["size"] || source["bytes"]),
          "versions" => versions,
          "reloaded_version" => first_string(selected_version["reloaded_version"], source["reloaded_version"]),
          "homepage_url" => source["homepage_url"].to_s,
          "changelogurl" => first_string(source["changelogurl"], source["changelog_url"]),
          "release_url" => source["release_url"].to_s,
          "publisher_login" => source["publisher_login"].to_s,
          "published_at" => source["published_at"].to_s,
          "updated_at" => source["updated_at"].to_s,
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
        copy["sha256"] = selected["sha256"].to_s
        copy["size"] = selected["size"].to_i
        copy["versions"] = [selected]
        copy["dependencies"] = normalize_dependencies(selected["dependencies"])
        copy
      end

      def spritepack_config(fetch_remote: false)
        return @spritepack_config_cache if @spritepack_config_cache && (!fetch_remote || @spritepack_config_source == "remote")
        ensure_spritepack_remote_source
        result = fetch_remote ? Reloaded::RemoteData.fetch(SPRITEPACK_REMOTE_ID, :force => true) : Reloaded::RemoteData.load(SPRITEPACK_REMOTE_ID)
        unless result.ok?
          @spritepack_config_cache = default_spritepack_config
          @spritepack_config_source = "default"
          return @spritepack_config_cache
        end
        @last_remote_fetch_at = Time.now rescue @last_remote_fetch_at if result.remote_confirmed?
        @spritepack_config_cache = default_spritepack_config.merge(result.value)
        @spritepack_config_source = remote_result_label(result)
        @spritepack_config_cache
      rescue Exception => e
        log("Spritepack config could not be read: #{e.class}: #{e.message}", :warning)
        @spritepack_config_cache = default_spritepack_config
        @spritepack_config_source = "default"
        default_spritepack_config
      end

      def ensure_spritepack_remote_source
        Reloaded::RemoteData.register(SPRITEPACK_REMOTE_ID, {
          :owner => :mod_browser,
          :format => :json,
          :url => SPRITEPACK_CONFIG_URL,
          :local_path => SPRITEPACK_CONFIG_PATH,
          :timeout => NETWORK_TIMEOUT_SECONDS,
          :validator => proc { |value| value.is_a?(Hash) && value["files"].is_a?(Array) }
        })
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
          { "id" => "latest", "name" => "Latest Spritepack Update", "url" => "", "updated_at" => "", "monthly" => true, "latest" => true }
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
          "build_id" => source["build_id"].to_s.strip,
          "full" => truthy?(source["full"]),
          "monthly" => truthy?(source["monthly"]) || source["type"].to_s.downcase == "monthly",
          "latest" => truthy?(source["latest"]),
          "updated_at" => source["updated_at"].to_s.empty? ? source["update_date"].to_s : source["updated_at"].to_s,
          "released_at" => source["released_at"].to_s,
          "version" => source["version"].to_s,
          "extract_to" => source["extract_to"].to_s,
          "sha256" => first_string(source["sha256"], source["checksum"]),
          "size" => positive_download_size(source["size"] || source["bytes"]),
          "parts" => normalize_spritepack_parts(source["parts"]),
          "components" => normalize_spritepack_components(source["components"]),
          "_index" => index.to_i
        }
      end

      def normalize_spritepack_parts(value)
        Array(value).each_with_index.map do |part, index|
          source = part.is_a?(Hash) ? part : {}
          {
            "file" => source["file"].to_s.strip,
            "url" => source["url"].to_s.strip,
            "sha256" => first_string(source["sha256"], source["checksum"]),
            "size" => positive_download_size(source["size"] || source["bytes"]),
            "_index" => index.to_i
          }
        end
      end

      def normalize_spritepack_components(value)
        Array(value).each_with_index.map do |component, index|
          source = component.is_a?(Hash) ? component : {}
          id = normalize_mod_id(source["id"].to_s)
          id = "component_#{index + 1}" if id.empty?
          {
            "id" => id,
            "name" => source["name"].to_s.strip.empty? ? id : source["name"].to_s.strip,
            "component" => source["component"].to_s.strip.downcase,
            "url" => source["url"].to_s.strip,
            "extract_to" => source["extract_to"].to_s,
            "sha256" => first_string(source["sha256"], source["checksum"]),
            "size" => positive_download_size(source["size"] || source["bytes"])
          }
        end
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
          "build_id" => item["build_id"].to_s,
          "parts" => Array(item["parts"]),
          "components" => Array(item["components"]),
          "updated_at" => item["updated_at"].to_s,
          "full" => truthy?(item["full"]),
          "monthly" => truthy?(item["monthly"]),
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
        expected_build_id = item["build_id"].to_s
        recorded_build_id = record["build_id"].to_s
        return recorded_build_id == expected_build_id unless expected_build_id.empty? || recorded_build_id.empty?
        return false unless record["updated_at"].to_s == item["updated_at"].to_s
        parts = Array(item["parts"])
        return part_signature(record["parts"]) == part_signature(parts) unless parts.empty?
        components = Array(item["components"])
        if components.empty?
          record["url"].to_s == item["url"].to_s
        else
          component_signature(record["components"]) == component_signature(components)
        end
      rescue
        false
      end

      def part_signature(value)
        Array(value).map do |part|
          [
            part["file"].to_s,
            part["url"].to_s,
            part["sha256"].to_s,
            part["size"].to_i
          ].join("|")
        end
      end

      def component_signature(value)
        Array(value).map do |component|
          [
            component["id"].to_s,
            component["url"].to_s,
            component["sha256"].to_s,
            component["size"].to_i
          ].join("|")
        end.sort
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

      def spritepack_full_manifest_valid?(manifest)
        return false unless manifest.is_a?(Hash)
        return false if manifest["build_id"].to_s.empty?
        components = Array(manifest["components"])
        return false if components.empty?
        root = File.expand_path(File.dirname(SPRITEPACK_FULL_MANIFEST_PATH))
        components.all? do |component|
          next false unless component.is_a?(Hash)
          relative = component["path"].to_s.tr("\\", "/")
          next false unless spritepack_manifest_relative_path?(relative)
          path = File.expand_path(File.join(root, *relative.split("/")))
          normalized_root = normalize_path(root)
          normalized_path = normalize_path(path)
          (normalized_path == normalized_root || normalized_path.start_with?(normalized_root + "/")) && File.file?(path)
        end
      rescue
        false
      end

      def spritepack_manifest_relative_path?(value)
        return false if value.empty? || value.start_with?("/") || value =~ /\A[A-Za-z]:/
        parts = value.split("/")
        return false if parts.any? { |part| part.empty? || part == "." || part == ".." }
        value.downcase.end_with?("/manifest.json")
      end

      def spritepack_monthly_included_in_full?(item)
        return false unless item && !truthy?(item["full"])
        status = spritepack_full_status
        return false unless status[:state] == :installed
        cutoff = status[:includes_updates_through].to_s
        updated = item["updated_at"].to_s
        return false if cutoff.empty? || updated.empty?
        updated_value = spritepack_timestamp_sort_value(updated)
        cutoff_value = spritepack_timestamp_sort_value(cutoff)
        return false if updated_value <= 0 || cutoff_value <= 0
        updated_value <= cutoff_value
      rescue
        false
      end

      def spritepack_timestamp_sort_value(value)
        text = value.to_s.strip
        iso = text.match(/\A(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})/)
        if iso
          return (((((iso[1].to_i * 100 + iso[2].to_i) * 100 + iso[3].to_i) * 100 + iso[4].to_i) * 100 + iso[5].to_i) * 100 + iso[6].to_i)
        end
        spritepack_date_sort_value(text)
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

      def download_entry(entry, task: nil, progress_range: [0.0, 0.55])
        url = entry["download_url"].to_s.strip
        return nil if url.empty?
        filename = "#{entry["id"]}_#{Time.now.to_i}.zip"
        path = File.join(temp_root, filename)
        result = Reloaded::Download.fetch(
          url,
          path,
          :task => task,
          :label => entry["name"],
          :min_bytes => 128,
          :expected_bytes => entry["size"],
          :sha256 => entry["sha256"],
          :progress_range => progress_range
        )
        if result.success?
          log("Downloaded #{entry["id"]} to #{relative_game_path(path)}")
          path
        else
          File.delete(path) rescue nil
          log("Download failed for #{entry["id"]}: code=#{result.error_code} reason=#{result.error_message}", :error)
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

      def fetch_url(url, cache_bust: false)
        fetch_url_with_headers(url, {}, cache_bust: cache_bust)
      end

      def fetch_url_with_headers(url, headers = {}, cache_bust: false)
        result = Reloaded::RemoteData.fetch_text(url, {
          :owner => :mod_browser,
          :headers => headers || {},
          :timeout => NETWORK_TIMEOUT_SECONDS,
          :force => cache_bust
        })
        result.ok? ? result.value.to_s : nil
      end

      def summarize_remote_response(text)
        clean = text.to_s.gsub(/\s+/, " ").strip
        clean = clean[0, 80].to_s
        clean.empty? ? "(blank)" : "(#{clean})"
      rescue
        "(unreadable response)"
      end

      def extract_archive(archive_path, destination, options = {})
        started_at = Time.now
        log("Archive extraction start: archive=#{relative_game_path(archive_path)} bytes=#{File.size(archive_path) rescue 0} destination=#{relative_game_path(destination)}")
        unless defined?(Reloaded::Archive)
          log("Archive extraction failed: shared Archive API is unavailable", :error)
          return false
        end
        result = Reloaded::Archive.extract(archive_path, destination, options)
        elapsed = Time.now - started_at
        unless result.success?
          log("Archive extraction failed: archive=#{relative_game_path(archive_path)} destination=#{relative_game_path(destination)} code=#{result.error_code} reason=#{result.error_message} elapsed=#{format('%.2f', elapsed)}s", :error)
          return false
        end
        log("Archive extraction succeeded: archive=#{relative_game_path(archive_path)} destination=#{relative_game_path(destination)} entries=#{result.entry_count} bytes=#{result.expanded_bytes} elapsed=#{format('%.2f', elapsed)}s")
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
            "sha256" => first_string(entry["sha256"], entry["checksum"]),
            "size" => positive_download_size(entry["size"] || entry["bytes"]),
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
            "sha256" => first_string(source["sha256"], source["checksum"]),
            "size" => positive_download_size(source["size"] || source["bytes"]),
            "reloaded_version" => (source["reloaded_version"] || source["minimum_reloaded_version"]).to_s,
            "changelog" => source["changelog"].to_s,
            "changelogurl" => first_string(source["changelogurl"], source["changelog_url"]),
            "dependencies" => normalize_dependencies(source["dependencies"])
          }
        end
        versions.sort_by { |entry| version_sort_key(entry["version"]) }.reverse
      end

      def normalize_profile_versions(source)
        versions = []
        Array(source["versions"]).each do |entry|
          next unless entry.is_a?(Hash)
          version = entry["version"].to_s
          profile_url = first_string(entry["profile_url"], entry["download_url"], entry["url"])
          next if version.empty? && profile_url.empty?
          versions << {
            "version" => version,
            "profile_url" => profile_url,
            "profile_code" => entry["profile_code"].to_s,
            "sha256" => first_string(entry["sha256"], entry["checksum"]),
            "size" => positive_download_size(entry["size"] || entry["bytes"]),
            "reloaded_version" => (entry["reloaded_version"] || entry["minimum_reloaded_version"]).to_s,
            "mods" => normalize_profile_mods(entry["mods"])
          }
        end
        if versions.empty?
          versions << {
            "version" => (source["version"] || source["latest_version"]).to_s,
            "profile_url" => first_string(source["profile_url"], source["download_url"], source["url"]),
            "profile_code" => source["profile_code"].to_s,
            "sha256" => first_string(source["sha256"], source["checksum"]),
            "size" => positive_download_size(source["size"] || source["bytes"]),
            "reloaded_version" => (source["reloaded_version"] || source["minimum_reloaded_version"]).to_s,
            "mods" => normalize_profile_mods(source["mods"])
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

      def positive_download_size(value)
        size = value.to_i
        size > 0 ? size : 0
      rescue
        0
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
        return Reloaded::Platform.temporary_directory if defined?(Reloaded::Platform)
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
