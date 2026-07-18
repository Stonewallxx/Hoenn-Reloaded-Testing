#======================================================
# Reloaded Save Protection
# Author: Stonewall
#======================================================
# Slot-aware rolling backups and safer save-file replacement.
#======================================================

module Reloaded
  module SaveProtection
    COPY_CHUNK_SIZE = 64 * 1024
    SOURCE_TRACK_LIMIT = 32
    @save_sources = {}
    @migration_backups = {}

    class << self
      def install
        install_source_tracker
        install_save_writer
        install_backup_writer
        register_patch_points
        true
      rescue Exception => e
        Reloaded::Log.exception("Save protection installation failed", e, channel: :save_data) if defined?(Reloaded::Log)
        false
      end

      def track_save_source(save_data, file_path)
        return save_data unless save_data.is_a?(Hash)
        bucket = save_data[:reloaded] || save_data["reloaded"]
        return save_data unless bucket.is_a?(Hash)
        source = File.expand_path(file_path.to_s)
        @save_sources[bucket.object_id] = source
        trim_save_sources
        save_data
      rescue Exception => e
        Reloaded::Log.exception("Save source tracking failed", e, channel: :save_data) if defined?(Reloaded::Log)
        save_data
      end

      def backup_before_migration(bucket, from:, to:)
        source = @save_sources.delete(bucket.object_id)
        return { :status => :not_applicable } if source.to_s.empty? || !File.file?(source)
        key = migration_backup_key(source, from, to)
        return { :status => :already_created } if @migration_backups[key]
        slot = File.basename(source, File.extname(source))
        unless backup_savefile(source, slot)
          return { :status => :failed, :source => source }
        end
        @migration_backups[key] = true
        Reloaded::Log.info(
          "Created pre-migration save backup slot=#{safe_slot_name(slot)} schema=#{from.to_i}->#{to.to_i}",
          :save_data
        ) if defined?(Reloaded::Log)
        { :status => :created, :source => source }
      rescue Exception => e
        Reloaded::Log.exception("Pre-migration save backup failed", e, channel: :save_data) if defined?(Reloaded::Log)
        { :status => :failed, :source => source, :error => e }
      end

      def save_to_file(file_path)
        target = File.expand_path(file_path.to_s)
        temporary = "#{target}.reloaded.tmp"
        delete_file(temporary)
        save_data = ::SaveData.compile_save_hash
        File.open(temporary, "wb") do |file|
          Marshal.dump(save_data, file)
          file.flush
          file.fsync if file.respond_to?(:fsync)
        end
        replace_file(temporary, target)
        true
      rescue Exception
        delete_file(temporary) if temporary
        raise
      end

      def backup_savefile(save_path, slot)
        source = File.expand_path(save_path.to_s)
        return true unless File.file?(source)
        slot_name = safe_slot_name(slot)
        root = File.join(File.dirname(source), "backups")
        destination_root = File.join(root, slot_name)
        ensure_directory(root)
        ensure_directory(destination_root)
        destination = unique_backup_path(destination_root, slot_name)
        copy_file(source, destination)
        unless File.size(source) == File.size(destination)
          delete_file(destination)
          raise "Backup verification failed for slot #{slot_name}."
        end
        prune_backups(destination_root)
        true
      rescue Exception => e
        Reloaded::Log.exception("Save backup failed for slot #{safe_slot_name(slot)}", e, channel: :save_data) if defined?(Reloaded::Log)
        false
      end

      private

      def install_source_tracker
        return unless defined?(::SaveData) && ::SaveData.respond_to?(:read_from_file)
        singleton = class << ::SaveData; self; end
        return if singleton.method_defined?(:reloaded_save_protection_read_from_file)
        singleton.class_eval do
          alias_method :reloaded_save_protection_read_from_file, :read_from_file
          define_method(:read_from_file) do |path|
            save_data = reloaded_save_protection_read_from_file(path)
            Reloaded::SaveProtection.track_save_source(save_data, path)
          end
        end
      end

      def install_save_writer
        return unless defined?(::SaveData) && ::SaveData.respond_to?(:compile_save_hash)
        singleton = class << ::SaveData; self; end
        return if singleton.method_defined?(:reloaded_original_save_to_file)
        if ::SaveData.respond_to?(:save_to_file)
          singleton.class_eval { alias_method :reloaded_original_save_to_file, :save_to_file }
        end
        singleton.class_eval { define_method(:save_to_file) { |path| Reloaded::SaveProtection.save_to_file(path) } }
      end

      def install_backup_writer
        return unless defined?(::Game) && ::Game.respond_to?(:backup_savefile)
        singleton = class << ::Game; self; end
        return if singleton.method_defined?(:reloaded_original_backup_savefile)
        singleton.class_eval do
          alias_method :reloaded_original_backup_savefile, :backup_savefile
          define_method(:backup_savefile) do |path, slot|
            Reloaded::SaveProtection.backup_savefile(path, slot)
          end
        end
      end

      def replace_file(temporary, target)
        unless File.exist?(target)
          File.rename(temporary, target)
          return
        end
        if posix_replace?
          File.rename(temporary, target)
          return
        end
        previous = "#{target}.reloaded.previous"
        delete_file(previous)
        File.rename(target, previous)
        begin
          File.rename(temporary, target)
          delete_file(previous)
        rescue Exception
          File.rename(previous, target) if File.file?(previous) && !File.file?(target)
          raise
        end
      end

      def posix_replace?
        defined?(Reloaded::Platform) && Reloaded::Platform.joiplay?
      rescue
        false
      end

      def copy_file(source, destination)
        File.open(source, "rb") do |input|
          File.open(destination, "wb") do |output|
            while (chunk = input.read(COPY_CHUNK_SIZE))
              output.write(chunk)
            end
            output.flush
            output.fsync if output.respond_to?(:fsync)
          end
        end
      end

      def prune_backups(root)
        limit = defined?(Settings::SAVEFILE_NB_BACKUPS) ? Settings::SAVEFILE_NB_BACKUPS.to_i : 10
        limit = 1 if limit < 1
        backups = directory_files(root, ".rxdata").sort_by do |path|
          [(File.mtime(path).to_f rescue 0.0), File.basename(path)]
        end
        backups.first([backups.length - limit, 0].max).each { |path| delete_file(path) }
      rescue Exception => e
        Reloaded::Log.exception("Save backup pruning failed", e, channel: :save_data) if defined?(Reloaded::Log)
      end

      def unique_backup_path(root, slot_name)
        timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
        base = File.join(root, "#{slot_name}_#{timestamp}")
        candidate = "#{base}.rxdata"
        index = 2
        while File.exist?(candidate)
          candidate = "#{base}_#{index}.rxdata"
          index += 1
        end
        candidate
      end

      def safe_slot_name(slot)
        value = File.basename(slot.to_s).gsub(/[^A-Za-z0-9_-]+/, "_")
        value.empty? ? "Save" : value
      rescue
        "Save"
      end

      def migration_backup_key(source, from, to)
        modified = File.mtime(source).to_f rescue 0.0
        [source.to_s.downcase, modified, from.to_i, to.to_i]
      end

      def trim_save_sources
        overflow = @save_sources.length - SOURCE_TRACK_LIMIT
        return if overflow <= 0
        @save_sources.keys.first(overflow).each { |key| @save_sources.delete(key) }
      end

      def ensure_directory(path)
        Dir.mkdir(path) unless Dir.exist?(path)
      end

      def directory_files(root, extension)
        return [] unless Dir.exist?(root)
        Dir.entries(root).each_with_object([]) do |name, files|
          next if name == "." || name == ".."
          path = File.join(root, name)
          files << path if File.file?(path) && name.downcase.end_with?(extension.downcase)
        end
      end

      def delete_file(path)
        File.delete(path) if path && File.file?(path)
      rescue
        nil
      end

      def register_patch_points
        return unless defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          :reloaded_safe_save_writer,
          :target => "SaveData.save_to_file",
          :type => :wrap,
          :file => __FILE__,
          :owner => :reloaded,
          :reason => "Writes save data through a verified temporary file before replacement."
        )
        Reloaded::Patches.register(
          :reloaded_slot_backups,
          :target => "Game.backup_savefile",
          :type => :wrap,
          :file => __FILE__,
          :owner => :reloaded,
          :reason => "Hardens slot-aware rolling save backups."
        )
        Reloaded::Patches.register(
          :reloaded_save_source_tracker,
          :target => "SaveData.read_from_file",
          :type => :wrap,
          :file => __FILE__,
          :owner => :reloaded,
          :reason => "Associates the loaded Reloaded save bucket with its source slot for pre-migration backups."
        )
      end
    end
  end
end

Reloaded::SaveProtection.install if defined?(Reloaded::SaveProtection)
