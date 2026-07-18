#======================================================
# Reloaded Save Data
# Author: Stonewall
#======================================================
# Central save bucket for Reloaded systems and mods.
#
# Responsibilities:
#   - Register one Reloaded save entry with the base SaveData system.
#   - Give mods a namespaced place to store persistent data.
#   - Keep Reloaded save data away from random vanilla object fields.
#   - Validate stored values before they are written to the save file.
#
#======================================================

module Reloaded
  module SaveData
    SAVE_KEY = :reloaded
    SCHEMA_VERSION = 1

    @data = nil
    @registered = false
    @write_blocked = false
    @write_block_reason = nil
    @original_bucket = nil

    class << self
      def data
        @data ||= empty_bucket
      end

      def empty_bucket
        {
          :schema_version => SCHEMA_VERSION,
          :systems => {},
          :mods => {},
          :metadata => initial_metadata
        }
      end

      def load(value)
        reset_write_protection
        source_version = bucket_schema_version(value)
        if source_version < SCHEMA_VERSION
          emit(:reloaded_save_migration_started, :from => source_version, :to => SCHEMA_VERSION)
          backup = if defined?(Reloaded::SaveProtection)
                     Reloaded::SaveProtection.backup_before_migration(
                       value,
                       :from => source_version,
                       :to => SCHEMA_VERSION
                     )
                   else
                     { :status => :not_applicable }
                   end
          if backup[:status] == :failed
            block_writes(value, :migration_backup_failed)
            @data = normalize_bucket(value)
            error = backup[:error] || RuntimeError.new("The save could not be backed up before migration.")
            Reloaded::Log.exception("Reloaded save migration backup failed", error, channel: :save_data) if defined?(Reloaded::Log)
            emit(:reloaded_save_migration_failed, :from => source_version, :to => SCHEMA_VERSION, :error => error)
            warn_incompatible_save(
              "Reloaded could not back up this save before updating it. Reloaded data will not be overwritten during this session."
            )
            return @data
          end
        end
        migration = if defined?(Reloaded::SaveMigrations)
                      Reloaded::SaveMigrations.migrate(value, SCHEMA_VERSION)
                    else
                      { :status => :current, :bucket => value, :applied => [], :mod_failures => [] }
                    end
        if migration[:status] == :newer
          block_writes(value, :newer_schema)
          @data = normalize_bucket(value)
          warn_incompatible_save(
            "This save was created by a newer Hoenn Reloaded version. Update Hoenn Reloaded before saving again."
          )
        elsif migration[:status] == :failed
          block_writes(value, :migration_failed)
          @data = normalize_bucket(value)
          error = migration[:error] || RuntimeError.new("Unknown migration failure")
          Reloaded::Log.exception("Reloaded save migration failed", error, channel: :save_data) if defined?(Reloaded::Log)
          emit(:reloaded_save_migration_failed, :from => source_version, :to => SCHEMA_VERSION, :error => error)
          warn_incompatible_save(
            "Reloaded save data could not be updated. Reloaded data will not be overwritten during this session."
          )
        else
          @data = normalize_bucket(migration[:bucket])
          log_migration_result(migration)
        end
        Reloaded::Log.debug("Loaded Reloaded save bucket", :save_data) if defined?(Reloaded::Log)
        emit(:reloaded_save_loaded, :data => @data)
        @data
      rescue Exception => e
        Reloaded::Log.exception("Reloaded save bucket failed to load", e, channel: :save_data) if defined?(Reloaded::Log)
        @data = empty_bucket
      end

      def dump
        if write_blocked?
          Reloaded::Log.warning_once(
            "Preserved Reloaded save bucket because writes are blocked (#{@write_block_reason}).",
            :save_data,
            key: "reloaded_save_write_blocked:#{@write_block_reason}"
          ) if defined?(Reloaded::Log)
          return deep_copy(@original_bucket)
        end
        @data = normalize_bucket(@data)
        refresh_metadata!
        emit(:reloaded_save_saving, :data => @data)
        Reloaded::Log.debug("Dumped Reloaded save bucket", :save_data) if defined?(Reloaded::Log)
        @data
      rescue Exception => e
        Reloaded::Log.exception("Reloaded save bucket failed to dump", e, channel: :save_data) if defined?(Reloaded::Log)
        empty_bucket
      end

      def namespace(owner, section: :mods)
        owner_key = normalize_owner(owner)
        section_hash(section)[owner_key] ||= {}
      end

      def system(system_id)
        namespace(system_id, section: :systems)
      end

      def mod(mod_id)
        namespace(mod_id, section: :mods)
      end

      def metadata
        deep_copy(metadata_hash)
      end

      def metadata_value(key, default = nil)
        value = metadata_hash[normalize_key(key)]
        value.nil? ? default : deep_copy(value)
      end

      def created_with_version
        metadata_value(:created_with_version, "0.0.0")
      end

      def last_saved_with_version
        metadata_value(:last_saved_with_version, "0.0.0")
      end

      def refresh_metadata!
        current = metadata_hash
        current["game"] = game_id
        current["created_at"] = timestamp if current["created_at"].to_s.empty?
        if current["created_with_version"].to_s.empty?
          current["created_with_version"] = reloaded_version
        end
        current["updated_at"] = timestamp
        current["last_saved_with_version"] = reloaded_version
        current["base_version"] = base_version
        current["platform"] = platform_label
        current["active_profile"] = active_profile_name
        current["enabled_mods"] = enabled_mod_snapshot
        metadata
      rescue Exception => e
        Reloaded::Log.exception("Reloaded save metadata refresh failed", e, channel: :save_data) if defined?(Reloaded::Log)
        metadata
      end

      def get(owner, key, default = nil, section: :mods)
        bucket = namespace(owner, section: section)
        normalized_key = normalize_key(key)
        return bucket[normalized_key] if bucket.has_key?(normalized_key)
        default
      end

      def set(owner, key, value, section: :mods)
        unless marshalable?(value)
          Reloaded::Log.warning(
            "Rejected non-saveable value for #{section}/#{owner}/#{key} (#{value.class})",
            :save_data
          ) if defined?(Reloaded::Log)
          return false
        end
        namespace(owner, section: section)[normalize_key(key)] = value
        true
      end

      def delete(owner, key = nil, section: :mods)
        if key.nil?
          section_hash(section).delete(normalize_owner(owner))
        else
          namespace(owner, section: section).delete(normalize_key(key))
        end
      end

      def has?(owner, key, section: :mods)
        namespace(owner, section: section).has_key?(normalize_key(key))
      end

      def clear(owner = nil, section: :mods)
        if owner.nil?
          section_hash(section).clear
        else
          delete(owner, section: section)
        end
      end

      def registered?
        @registered
      end

      def write_blocked?
        !!@write_blocked
      end

      def write_block_reason
        @write_block_reason
      end

      def new_game_bucket
        reset_write_protection
        @data = empty_bucket
      end

      def register_with_base_save_data
        return false unless defined?(::SaveData)
        return true if @registered
        ::SaveData.register(SAVE_KEY) do
          save_value { Reloaded::SaveData.dump }
          load_value { |value| Reloaded::SaveData.load(value) }
          new_game_value { Reloaded::SaveData.new_game_bucket }
        end
        @registered = true
        register_patch_point
        Reloaded::Log.info("Registered Reloaded save bucket", :save_data) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Reloaded save bucket registration failed", e, channel: :save_data) if defined?(Reloaded::Log)
        false
      end

      private

      def section_hash(section)
        bucket = data
        section_key = normalize_section(section)
        bucket[section_key] ||= {}
      end

      def normalize_bucket(value)
        source = value.is_a?(Hash) ? value : {}
        {
          :schema_version => SCHEMA_VERSION,
          :systems => normalize_section_hash(source[:systems] || source["systems"]),
          :mods => normalize_section_hash(source[:mods] || source["mods"]),
          :metadata => normalize_metadata(source[:metadata] || source["metadata"])
        }
      end

      def bucket_schema_version(value)
        return 0 unless value.is_a?(Hash)
        (value[:schema_version] || value["schema_version"] || 0).to_i
      end

      def reset_write_protection
        @write_blocked = false
        @write_block_reason = nil
        @original_bucket = nil
      end

      def block_writes(value, reason)
        @write_blocked = true
        @write_block_reason = reason.to_sym
        @original_bucket = deep_copy(value.is_a?(Hash) ? value : {})
      end

      def log_migration_result(result)
        applied = Array(result[:applied])
        unless applied.empty?
          Reloaded::Log.info_once(
            "Migrated Reloaded save schema: #{applied.join(', ')}",
            :save_data,
            key: "reloaded_save_migrated:#{applied.join(':')}"
          ) if defined?(Reloaded::Log)
          emit(:reloaded_save_migrated, :from => result[:from], :to => result[:to], :migrations => applied)
        end
        Array(result[:mod_failures]).each do |failure|
          error = failure[:error] || RuntimeError.new(failure[:message].to_s)
          owner = failure[:owner].to_s
          Reloaded::Log.exception("Save migration failed for mod #{owner}", error, channel: :mods) if defined?(Reloaded::Log)
          emit(:reloaded_save_migration_failed, :owner => owner, :error => error)
        end
      end

      def warn_incompatible_save(message)
        if Reloaded.respond_to?(:message)
          Reloaded.message(message.to_s, :theme => :warning)
        elsif defined?(Kernel) && Kernel.respond_to?(:pbMessage)
          Kernel.pbMessage(message.to_s)
        end
      rescue Exception => e
        Reloaded::Log.exception("Save compatibility warning failed", e, channel: :save_data) if defined?(Reloaded::Log)
      end

      def normalize_metadata(value)
        normalized = initial_metadata
        return normalized unless value.is_a?(Hash)
        value.each do |key, entry|
          next unless marshalable?(entry)
          normalized[normalize_key(key)] = entry
        end
        normalized
      end

      def normalize_section_hash(value)
        return {} unless value.is_a?(Hash)
        normalized = {}
        value.each do |owner, owner_data|
          next unless owner_data.is_a?(Hash)
          normalized[normalize_owner(owner)] = normalize_value_hash(owner_data)
        end
        normalized
      end

      def normalize_value_hash(value)
        normalized = {}
        value.each { |key, entry| normalized[normalize_key(key)] = entry } if value.is_a?(Hash)
        normalized
      end

      def normalize_owner(owner)
        owner.to_s.strip.downcase
      end

      def normalize_key(key)
        key.to_s
      end

      def normalize_section(section)
        section.to_s == "systems" ? :systems : :mods
      end

      def metadata_hash
        data[:metadata] ||= initial_metadata
      end

      def initial_metadata
        now = timestamp
        version = reloaded_version
        {
          "game" => game_id,
          "created_at" => now,
          "updated_at" => now,
          "created_with_version" => version,
          "last_saved_with_version" => version,
          "base_version" => base_version,
          "platform" => platform_label,
          "active_profile" => active_profile_name,
          "enabled_mods" => enabled_mod_snapshot
        }
      end

      def timestamp
        Time.now.strftime("%Y-%m-%d %H:%M:%S")
      rescue
        ""
      end

      def reloaded_version
        defined?(Reloaded::Versioning) ? Reloaded::Versioning.current : (Reloaded.version rescue "0.0.0")
      end

      def base_version
        defined?(Reloaded::Versioning) ? Reloaded::Versioning.base : "0.0.0"
      end

      def game_id
        if defined?(Reloaded::ModManager) && Reloaded::ModManager.const_defined?(:GAME_ID)
          Reloaded::ModManager::GAME_ID.to_s
        else
          "hoenn"
        end
      rescue
        "hoenn"
      end

      def platform_label
        defined?(Reloaded::Platform) ? Reloaded::Platform.label.to_s : "Other"
      rescue
        "Other"
      end

      def active_profile_name
        if defined?(Reloaded::Profiles) && Reloaded::Profiles.respond_to?(:active_name)
          Reloaded::Profiles.active_name.to_s
        elsif defined?(Reloaded::Settings)
          Reloaded::Settings.get("active_profile", "Default").to_s
        else
          "Default"
        end
      rescue
        "Default"
      end

      def enabled_mod_snapshot
        return [] unless defined?(Reloaded::ModManager) && Reloaded::ModManager.respond_to?(:active_mods)
        Reloaded::ModManager.active_mods.map do |mod|
          next unless mod.is_a?(Hash)
          id = mod[:id] || mod["id"]
          version = mod[:version] || mod["version"]
          next if id.to_s.empty?
          { "id" => id.to_s, "version" => version.to_s }
        end.compact
      rescue
        []
      end

      def deep_copy(value)
        Marshal.load(Marshal.dump(value))
      rescue
        value
      end

      def marshalable?(value)
        Marshal.dump(value)
        true
      rescue
        false
      end

      def emit(event_name, context)
        Reloaded::Events.emit(event_name, context) if defined?(Reloaded::Events)
      rescue Exception => e
        Reloaded::Log.exception("Reloaded save event #{event_name} failed", e, channel: :save_data) if defined?(Reloaded::Log)
      end

      def register_patch_point
        return unless defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          :reloaded_save_bucket,
          :target => "SaveData.register(:reloaded)",
          :type => :data_patch,
          :file => __FILE__,
          :owner => :reloaded,
          :priority => 100,
          :reason => "Adds one central save bucket for Reloaded systems and mods.",
          :recommended_fix => "Only one system should register the :reloaded save key.",
          :conflict_group => "save_data_key:reloaded"
        )
      end
    end
  end
end

Reloaded::SaveData.register_with_base_save_data if defined?(Reloaded::SaveData)
