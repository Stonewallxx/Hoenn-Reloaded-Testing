#======================================================
# Reloaded Sprite Import
# Author: Stonewall
#======================================================
# Sorts player-provided PNGs from the Sprite Import inbox into the normal
# loose override folders. Large batches use Reloaded::ProgressWindow.
#======================================================

module Reloaded
  module SpriteImport
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    DEFAULT_INBOX = File.join(GAME_ROOT, "Graphics", "CustomBattlers", "Sprite Import")
    DEFAULT_INDEXED = File.join(GAME_ROOT, "Graphics", "CustomBattlers", "local_sprites", "indexed")
    DEFAULT_BASE = File.join(GAME_ROOT, "Graphics", "CustomBattlers", "local_sprites", "BaseSprites")
    PROGRESS_THRESHOLD = 20
    REPORT_INTERVAL = 10
    PNG_SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10].freeze

    class << self
      def import
        ensure_directory(inbox_root)
        files = import_files
        return empty_summary if files.empty?
        summary = run_operation(
          :sprite_import,
          files,
          _INTL("Importing Sprites"),
          _INTL("Sorting sprites...")
        ) do |entries, task|
          import_files_batch(entries, task)
        end
        log_summary("Sprite import completed", summary)
        summary
      rescue Exception => e
        log_exception("Sprite import failed", e)
        empty_summary.merge(:failed => 1)
      end

      def replace_conflicts(conflicts)
        entries = Array(conflicts && conflicts.to_a)
        return empty_summary if entries.empty?
        summary = run_operation(
          :sprite_import_replace,
          entries,
          _INTL("Replacing Sprites"),
          _INTL("Applying replacements...")
        ) do |pairs, task|
          replace_files_batch(pairs, task)
        end
        log_summary("Sprite replacements completed", summary)
        summary
      rescue Exception => e
        log_exception("Sprite replacement failed", e)
        empty_summary.merge(:failed => Array(conflicts).length)
      end

      def classify_filename(filename)
        name = File.basename(filename.to_s)
        return nil unless name =~ /\.png\z/i
        stem = name.sub(/\.png\z/i, "")
        if stem =~ /\A(\d+)([a-z]*)\z/i
          return {
            :type => :BASE,
            :head_id => Regexp.last_match(1).to_i,
            :body_id => 0,
            :alt_letter => Regexp.last_match(2).to_s.downcase,
            :filename => name
          }
        end
        if stem =~ /\A(\d+)\.(\d+)([a-z]*)\z/i
          return {
            :type => :CUSTOM,
            :head_id => Regexp.last_match(1).to_i,
            :body_id => Regexp.last_match(2).to_i,
            :alt_letter => Regexp.last_match(3).to_s.downcase,
            :filename => name
          }
        end
        if stem =~ /\A(\d+)(?:\.\d+){2,}[a-z]*\z/i
          return {
            :type => :SPECIAL,
            :head_id => Regexp.last_match(1).to_i,
            :body_id => nil,
            :alt_letter => "",
            :filename => name
          }
        end
        nil
      rescue
        nil
      end

      def packed_conflict?(record)
        return false unless record && defined?(Reloaded::SpritePacks)
        return false unless [:BASE, :CUSTOM].include?(record[:type])
        alt = record[:alt_letter].to_s
        return false if alt.length > 1
        Reloaded::SpritePacks.entry?(
          record[:type],
          record[:head_id],
          record[:body_id],
          alt
        )
      rescue
        false
      end

      private

      def import_files
        Dir.entries(inbox_root).each_with_object([]) do |name, result|
          next if name == "." || name == ".."
          next unless File.extname(name).downcase == ".png"
          path = File.join(inbox_root, name)
          result << path if File.file?(path)
        end.sort_by { |path| File.basename(path).downcase }
      rescue
        []
      end

      def import_files_batch(files, task)
        summary = empty_summary
        total = files.length
        directories = {}
        files.each_with_index do |source, index|
          task.checkpoint! if task
          begin
            record = classify_filename(source)
            unless record && valid_png?(source)
              summary[:invalid] += 1
              next
            end
            destination = destination_for(record)
            ensure_directory_once(File.dirname(destination), directories)
            if File.file?(destination) || packed_conflict?(record)
              summary[:conflicts][source] = destination
            else
              File.rename(source, destination)
              summary[:imported] += 1
            end
          rescue Exception
            summary[:failed] += 1
          ensure
            report_progress(task, index + 1, total, _INTL("Sorting {1} of {2}", index + 1, total))
          end
        end
        summary
      end

      def replace_files_batch(pairs, task)
        summary = empty_summary
        total = pairs.length
        directories = {}
        pairs.each_with_index do |pair, index|
          task.checkpoint! if task
          source, destination = pair
          begin
            unless File.file?(source)
              summary[:failed] += 1
              next
            end
            ensure_directory_once(File.dirname(destination), directories)
            replace_file(source, destination)
            summary[:imported] += 1
          rescue Exception
            summary[:failed] += 1
          ensure
            report_progress(task, index + 1, total, _INTL("Replacing {1} of {2}", index + 1, total))
          end
        end
        summary
      end

      def run_operation(key, entries, title, stage, &worker)
        if entries.length >= PROGRESS_THRESHOLD && progress_available?
          outcome = Reloaded::ProgressWindow.run(
            key,
            {
              :title => title,
              :stage => stage,
              :mode => :determinate,
              :cancellable => false,
              :minimum_visible_time => 0.2,
              :task => {
                :owner => :sprite_import,
                :duplicate => :reject,
                :history => true
              }
            }
          ) do |task|
            worker.call(entries, task)
          end
          return outcome.value if outcome && outcome.success? && outcome.value.is_a?(Hash)
          return empty_summary.merge(:failed => entries.length)
        end
        worker.call(entries, nil)
      end

      def progress_available?
        defined?(Reloaded::Task) &&
          Reloaded::Task.supported? &&
          defined?(Reloaded::ProgressWindow)
      rescue
        false
      end

      def report_progress(task, current, total, stage)
        return unless task
        return unless current == total || current == 1 || (current % REPORT_INTERVAL).zero?
        task.report_ratio(current, total, stage)
      rescue
      end

      def destination_for(record)
        if record[:type] == :BASE
          File.join(base_root, record[:filename])
        else
          File.join(indexed_root, record[:head_id].to_s, record[:filename])
        end
      end

      def replace_file(source, destination)
        backup = nil
        if File.file?(destination)
          backup = "#{destination}.sprite_import_backup"
          File.delete(backup) if File.file?(backup)
          File.rename(destination, backup)
        end
        File.rename(source, destination)
        File.delete(backup) if backup && File.file?(backup)
        true
      rescue
        if backup && File.file?(backup) && !File.file?(destination)
          File.rename(backup, destination) rescue nil
        end
        raise
      end

      def valid_png?(path)
        File.open(path, "rb") do |file|
          signature = file.read(8)
          signature && signature.unpack("C*") == PNG_SIGNATURE
        end
      rescue
        false
      end

      def ensure_directory_once(path, cache)
        key = path_key(path)
        return if cache[key]
        ensure_directory(path)
        cache[key] = true
      end

      def ensure_directory(path)
        return if Dir.exist?(path)
        parent = File.dirname(path)
        ensure_directory(parent) if parent && parent != path && !Dir.exist?(parent)
        Dir.mkdir(path)
      end

      def inbox_root
        settings_path(:CUSTOM_SPRITES_TO_IMPORT_FOLDER, DEFAULT_INBOX)
      end

      def indexed_root
        settings_path(:CUSTOM_BATTLERS_FOLDER_INDEXED, DEFAULT_INDEXED)
      end

      def base_root
        settings_path(:CUSTOM_BASE_SPRITE_FOLDER, DEFAULT_BASE)
      end

      def settings_path(name, fallback)
        value = defined?(Settings) && Settings.const_defined?(name) ? Settings.const_get(name).to_s : ""
        return fallback if value.empty?
        File.expand_path(value, GAME_ROOT)
      rescue
        fallback
      end

      def path_key(path)
        value = File.expand_path(path.to_s).tr("\\", "/")
        File::ALT_SEPARATOR == "\\" ? value.downcase : value
      end

      def empty_summary
        {
          :imported => 0,
          :conflicts => {},
          :invalid => 0,
          :failed => 0
        }
      end

      def log_summary(label, summary)
        return unless defined?(Reloaded::Log)
        Reloaded::Log.info(
          "#{label}: imported=#{summary[:imported].to_i}, conflicts=#{summary[:conflicts].length}, " \
          "invalid=#{summary[:invalid].to_i}, failed=#{summary[:failed].to_i}",
          :assets
        )
      rescue
      end

      def log_exception(label, error)
        Reloaded::Log.exception(label, error, channel: :assets) if defined?(Reloaded::Log)
      rescue
      end
    end
  end
end
