#======================================================
# Reloaded Temporary File Cleanup
# Author: Stonewall
#======================================================
# Conservatively removes abandoned files owned by Reloaded. Installed content,
# local fallbacks, and caches registered for the current session are excluded.
#======================================================

begin
  require "fileutils"
  require "find"
rescue Exception
end

module Reloaded
  module TempCleanup
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    ABANDONED_AGE = 24 * 60 * 60
    REMOTE_CACHE_MAX_AGE = 90 * 24 * 60 * 60
    REMOTE_CACHE_MAX_BYTES = 64 * 1024 * 1024
    SPRITE_CACHE_MAX_AGE = 30 * 24 * 60 * 60
    SPRITE_CACHE_MAX_BYTES = 2 * 1024 * 1024 * 1024

    DOWNLOAD_SCRIPT_PATTERN = /\Arld_download_\d+_\d+\.ps1(?:\.error\.txt)?\z/i
    DOWNLOADED_ARCHIVE_PATTERN = /\A(?:spritepack_[a-z0-9_-]+_\d+\.(?:zip|rar|7z)|[a-z0-9_-]+_\d+\.zip)\z/i
    INSTALL_DIRECTORY_PATTERN = /\Arld_install_\d+_\d+\z/i
    WINDOWS_PUBLISH_DIRECTORY_PATTERN = /\AHoenn-Reloaded-Mods-[a-z0-9_-]+\z/i
    PROTON_PUBLISH_DIRECTORY_PATTERN = /\Ahoenn-reloaded-publisher\.[a-z0-9_-]+\z/i
    PUBLISH_PAYLOAD_PATTERN = /\A(?:SpritepacksPublish|ReloadedMartPublish)_[a-z0-9_-]+\.json\z/i
    REMOTE_CACHE_PATTERN = /\A[a-z0-9_]+\.json\z/i
    REMOTE_COMPANION_PATTERN = /\A[a-z0-9_]+\.json\.(?:tmp|bak)\z/i

    @booted = false
    @ran = false
    @last_summary = nil

    class << self
      def boot
        return true if @booted
        if defined?(Reloaded::Events)
          Reloaded::Events.on(
            :modules_loaded,
            :cleanup_abandoned_reloaded_files,
            :priority => 25,
            :owner => :reloaded
          ) { |_context| run }
        else
          run
        end
        @booted = true
        true
      rescue Exception => e
        log_exception("Temporary cleanup could not start", e)
        false
      end

      def run(options = {})
        return duplicate_summary(@last_summary) if @ran && !options[:force]
        summary = new_summary
        now = options[:now].is_a?(Time) ? options[:now] : Time.now
        cleanup_runtime_files(now, summary)
        cleanup_publishing_files(now, summary)
        cleanup_remote_data(now, summary)
        cleanup_sprite_pack_cache(now, summary)
        @ran = true
        @last_summary = summary
        log_summary(summary) unless options[:log] == false
        duplicate_summary(summary)
      rescue Exception => e
        summary ||= new_summary
        summary[:failures] += 1
        @ran = true
        @last_summary = summary
        log_exception("Temporary cleanup failed", e)
        duplicate_summary(summary)
      end

      def last_summary
        duplicate_summary(@last_summary || new_summary)
      end

      private

      def cleanup_runtime_files(now, summary)
        root = Reloaded::Platform.temporary_directory
        cleanup_runtime_root(root, now, summary)
      rescue Exception
        summary[:failures] += 1
      end

      def cleanup_runtime_root(root, now, summary)
        root = File.expand_path(root.to_s)
        return summary unless Dir.exist?(root)

        Dir.entries(root).each do |name|
          next if name == "." || name == ".."
          path = File.join(root, name)
          next unless Dir.exist?(path) && !File.symlink?(path)
          recognized = name == "ManagerEditorCheckout" || name =~ INSTALL_DIRECTORY_PATTERN
          remove_directory(path, root, summary) if recognized && stale_path?(path, ABANDONED_AGE, now)
        end

        Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).each do |path|
          next unless File.file?(path) || File.symlink?(path)
          name = File.basename(path)
          top_level = File.dirname(path_key(path)) == path_key(root)
          recognized = name.downcase.end_with?(".part") || name.downcase.end_with?(".previous")
          recognized ||= top_level && (name =~ DOWNLOAD_SCRIPT_PATTERN || name =~ DOWNLOADED_ARCHIVE_PATTERN)
          remove_file(path, root, summary) if recognized && stale_path?(path, ABANDONED_AGE, now)
        end
        summary
      end

      def cleanup_publishing_files(now, summary)
        runtime_root = File.expand_path(Reloaded::Platform.temporary_directory)
        parent = File.dirname(runtime_root)

        windows_root = File.join(parent, "HoennReloadedPublisher")
        if Dir.exist?(windows_root) && safe_child?(windows_root, parent)
          Dir.entries(windows_root).each do |name|
            next unless name =~ WINDOWS_PUBLISH_DIRECTORY_PATTERN
            path = File.join(windows_root, name)
            next unless Dir.exist?(path) && !File.symlink?(path)
            remove_directory(path, windows_root, summary) if stale_path?(path, ABANDONED_AGE, now)
          end
          remove_empty_directory(windows_root, parent, summary)
        end

        Dir.entries(parent).each do |name|
          next if name == "." || name == ".."
          path = File.join(parent, name)
          if name =~ PROTON_PUBLISH_DIRECTORY_PATTERN && Dir.exist?(path) && !File.symlink?(path)
            remove_directory(path, parent, summary) if stale_path?(path, ABANDONED_AGE, now)
          elsif name =~ PUBLISH_PAYLOAD_PATTERN && (File.file?(path) || File.symlink?(path))
            remove_file(path, parent, summary) if stale_path?(path, ABANDONED_AGE, now)
          end
        end
      rescue Exception
        summary[:failures] += 1
      end

      def cleanup_remote_data(now, summary)
        return unless defined?(Reloaded::RemoteData)
        protected_paths = if Reloaded::RemoteData.respond_to?(:registered_cache_paths)
                            Reloaded::RemoteData.registered_cache_paths
                          else
                            []
                          end
        protected_paths.each do |path|
          temporary = "#{path}.tmp"
          next unless File.file?(temporary) || File.symlink?(temporary)
          remove_file(temporary, GAME_ROOT, summary) if stale_path?(temporary, ABANDONED_AGE, now)
        end
        prune_remote_cache(
          Reloaded::RemoteData::CACHE_ROOT,
          protected_paths,
          now,
          summary,
          REMOTE_CACHE_MAX_AGE,
          REMOTE_CACHE_MAX_BYTES
        )
      rescue Exception
        summary[:failures] += 1
      end

      def cleanup_sprite_pack_cache(now, summary)
        root = if defined?(Reloaded::SpritePacks)
                 Reloaded::SpritePacks::CACHE_ROOT
               else
                 File.join(GAME_ROOT, "Reloaded", "Cache", "SpritePacks")
               end
        root = File.expand_path(root.to_s)
        return summary unless Dir.exist?(root)

        Dir[File.join(root, "**", "*.part")].each do |path|
          next unless File.file?(path) || File.symlink?(path)
          remove_file(path, root, summary) if stale_path?(path, ABANDONED_AGE, now)
        end

        files = Dir[File.join(root, "**", "*.png")].select { |path| File.file?(path) }
        files.each do |path|
          next unless stale_path?(path, SPRITE_CACHE_MAX_AGE, now)
          if remove_file(path, root, summary)
            summary[:sprite_cache_files] += 1
          end
        end

        files = Dir[File.join(root, "**", "*.png")].select { |path| File.file?(path) }
        total_bytes = files.inject(0) { |total, path| total + safe_file_size(path) }
        files.sort_by { |path| safe_mtime(path) }.each do |path|
          break if total_bytes <= SPRITE_CACHE_MAX_BYTES
          size = safe_file_size(path)
          if remove_file(path, root, summary)
            summary[:sprite_cache_files] += 1
            total_bytes -= size
          end
        end
        remove_empty_cache_directories(root)
        summary
      rescue Exception
        summary[:failures] += 1
      end

      def remove_empty_cache_directories(root)
        directories = Dir[File.join(root, "**", "*")].select { |path| Dir.exist?(path) && !File.symlink?(path) }
        directories.sort_by { |path| -path.length }.each do |path|
          next unless safe_child?(path, root)
          Dir.rmdir(path) if Dir.entries(path).length == 2
        end
      rescue
      end

      def prune_remote_cache(root, protected_paths, now, summary, max_age = REMOTE_CACHE_MAX_AGE,
                             max_bytes = REMOTE_CACHE_MAX_BYTES)
        root = File.expand_path(root.to_s)
        return summary unless Dir.exist?(root)
        protected = Array(protected_paths).map { |path| path_key(File.expand_path(path.to_s)) }
        cache_files = Dir[File.join(root, "*.json")].select do |path|
          File.file?(path) && File.basename(path) =~ REMOTE_CACHE_PATTERN
        end

        cache_files.each do |path|
          next if protected.include?(path_key(path))
          next unless stale_path?(path, max_age, now)
          remove_cache_family(path, root, summary)
        end

        remove_orphaned_cache_companions(root, protected, now, summary)
        cache_files = Dir[File.join(root, "*.json")].select do |path|
          File.file?(path) && File.basename(path) =~ REMOTE_CACHE_PATTERN
        end
        total_bytes = cache_files.inject(0) { |total, path| total + safe_file_size(path) }
        candidates = cache_files.reject { |path| protected.include?(path_key(path)) }
        candidates.sort_by! { |path| safe_mtime(path) }
        candidates.each do |path|
          break if total_bytes <= max_bytes.to_i
          size = safe_file_size(path)
          remove_cache_family(path, root, summary)
          total_bytes -= size unless File.exist?(path)
        end
        summary
      end

      def remove_orphaned_cache_companions(root, protected, now, summary)
        Dir[File.join(root, "*.json.{tmp,bak}")].each do |path|
          next unless File.file?(path) || File.symlink?(path)
          next unless File.basename(path) =~ REMOTE_COMPANION_PATTERN
          base = path.sub(/\.(?:tmp|bak)\z/i, "")
          next if protected.include?(path_key(base))
          next if File.file?(base)
          remove_file(path, root, summary) if stale_path?(path, ABANDONED_AGE, now)
        end
      end

      def remove_cache_family(path, root, summary)
        remove_file(path, root, summary)
        ["#{path}.tmp", "#{path}.bak"].each do |companion|
          remove_file(companion, root, summary) if File.file?(companion) || File.symlink?(companion)
        end
        summary[:cache_files] += 1 unless File.exist?(path)
      end

      def stale_path?(path, age, now)
        cutoff = now.to_f - age.to_i
        return false if safe_mtime(path) > cutoff
        return true unless Dir.exist?(path) && !File.symlink?(path)
        Find.find(path) do |entry|
          next if entry == path
          if File.symlink?(entry)
            Find.prune if File.directory?(entry)
            next
          end
          return false if safe_mtime(entry) > cutoff
        end
        true
      rescue Exception
        false
      end

      def remove_file(path, allowed_root, summary)
        return false unless safe_child?(path, allowed_root)
        size = safe_file_size(path)
        File.delete(path)
        summary[:files] += 1
        summary[:bytes] += size
        true
      rescue Exception
        summary[:failures] += 1
        false
      end

      def remove_directory(path, allowed_root, summary)
        return false unless safe_child?(path, allowed_root)
        return false if File.symlink?(path)
        FileUtils.rm_rf(path)
        return false if File.exist?(path)
        summary[:directories] += 1
        true
      rescue Exception
        summary[:failures] += 1
        false
      end

      def remove_empty_directory(path, allowed_root, summary)
        return unless safe_child?(path, allowed_root)
        return unless Dir.exist?(path) && !File.symlink?(path)
        return unless Dir.entries(path).length == 2
        Dir.rmdir(path)
        summary[:directories] += 1
      rescue Exception
        summary[:failures] += 1
      end

      def safe_child?(path, root)
        expanded_candidate = File.expand_path(path.to_s)
        expanded_root = File.expand_path(root.to_s)
        candidate = path_key(expanded_candidate)
        allowed = path_key(expanded_root)
        return false if candidate == allowed || !candidate.start_with?(allowed + "/")

        cursor = File.dirname(expanded_candidate)
        while path_key(cursor) != allowed
          return false if File.symlink?(cursor)
          parent = File.dirname(cursor)
          return false if parent == cursor
          cursor = parent
        end
        true
      rescue
        false
      end

      def path_key(path)
        value = path.to_s.gsub("\\", "/").sub(/\/+\z/, "")
        File::ALT_SEPARATOR == "\\" ? value.downcase : value
      end

      def safe_file_size(path)
        File.lstat(path).size.to_i
      rescue
        0
      end

      def safe_mtime(path)
        File.lstat(path).mtime.to_f
      rescue
        Time.now.to_f
      end

      def new_summary
        {
          :files => 0,
          :directories => 0,
          :cache_files => 0,
          :sprite_cache_files => 0,
          :bytes => 0,
          :failures => 0
        }
      end

      def duplicate_summary(summary)
        (summary || new_summary).dup
      end

      def log_summary(summary)
        removed = summary[:files].to_i + summary[:directories].to_i
        if summary[:failures].to_i > 0
          message = "Temporary cleanup removed #{removed} entries with #{summary[:failures]} skipped failures."
          Reloaded::Log.warning(message, :framework) if defined?(Reloaded::Log)
        elsif removed > 0
          message = "Temporary cleanup removed #{removed} abandoned entries, including #{summary[:cache_files]} cache files."
          Reloaded::Log.info(message, :framework) if defined?(Reloaded::Log)
        elsif defined?(Reloaded::Log)
          Reloaded::Log.debug("Temporary cleanup found no abandoned entries.", :framework)
        end
      end

      def log_exception(message, error)
        if defined?(Reloaded::Log)
          Reloaded::Log.exception(message, error, :channel => :framework, :level => :warning)
        end
      rescue
      end
    end
  end
end
