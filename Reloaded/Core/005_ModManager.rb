#======================================================
# Reloaded Mod Manager
# Author: Stonewall
#======================================================
# Mod discovery, validation, dependency ordering, and script loading.
#
# Responsibilities:
#   - Scan Mods/ and optional ModDev/ folders for mod.json manifests.
#   - Validate manifest data and author/system tags.
#   - Build dependency-safe load order for enabled mods.
#   - Load mod Scripts/**/*.rb files in alphabetical order.
#   - Feed active mod folders into the Reloaded asset resolver.
#
#======================================================

begin
  require "json"
rescue Exception
end

module Reloaded
  module ModManager
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), ".."))
    MODS_DIR = File.expand_path("./Mods")
    MODDEV_DIR = File.expand_path("./ModDev")

    DEFAULT_MODDEV_ENABLED = false

    AUTHOR_TAGS = {
      :role => [
        "modpack",
        "mod",
        "patch",
        "library"
      ],
      :content => [
        "gameplay",
        "ui",
        "graphics",
        "audio",
        "overhaul",
        "balance",
        "quality_of_life",
        "story",
        "maps",
        "pokemon",
        "items",
        "abilities",
        "moves",
        "multiplayer"
      ]
    }.freeze

    SYSTEM_TAGS = [
      "outdated",
      "broken",
      "missing_dependency",
      "conflict",
      "disabled",
      "moddev",
      "invalid"
    ].freeze

    REQUIRED_FIELDS = [
      "id",
      "name",
      "version",
      "authors",
      "description",
      "minimum_reloaded_version",
      "dependencies",
      "tags"
    ].freeze

    @candidates = []
    @mods = {}
    @active_mods = []
    @invalid_mods = []
    @loaded_mods = []
    @skipped_mods = []
    @script_count = 0
    @booted = false
    @moddev_enabled = nil
    @active_profile = nil

    class << self
      def boot
        return true if @booted
        @booted = true
        scan
        validate
        build_load_order
        Reloaded::Assets.rebuild(@active_mods) if defined?(Reloaded::Assets)
        load_active_mods
        emit(:mods_loaded, :mods => @loaded_mods, :skipped => @skipped_mods)
        write_summary
        true
      rescue Exception => e
        Reloaded::Log.exception("Mod Manager boot failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def refresh_metadata
        scan
        validate
        build_load_order
        Reloaded::Assets.rebuild(@active_mods) if defined?(Reloaded::Assets)
        write_summary
        true
      rescue Exception => e
        Reloaded::Log.exception("Mod Manager metadata refresh failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def candidates
        @candidates.dup
      end

      def mods
        @mods.dup
      end

      def active_mods
        @active_mods.dup
      end

      def loaded_mods
        @loaded_mods.dup
      end

      def skipped_mods
        @skipped_mods.dup
      end

      def invalid_mods
        @invalid_mods.dup
      end

      def tags
        AUTHOR_TAGS
      end

      def system_tags
        SYSTEM_TAGS
      end

      def mod_ids
        @mods.keys.sort
      end

      def mod_rows
        @mods.values.map { |mod| build_mod_row(mod) }.sort_by do |row|
          [row[:name].to_s.downcase, row[:id].to_s]
        end
      end

      def mod_row(mod_id)
        mod = @mods[normalize_mod_id(mod_id)]
        mod ? build_mod_row(mod) : nil
      end

      def dependency_status(mod_id)
        mod = @mods[normalize_mod_id(mod_id)]
        return [] unless mod
        mod[:dependencies].map { |dependency| dependency_status_entry(mod, dependency) }
      end

      def incompatibility_status(mod_id)
        id = normalize_mod_id(mod_id)
        mod = @mods[id]
        return [] unless mod
        direct = normalize_string_array(mod[:incompatible])
        reverse = @mods.values.select { |other| normalize_string_array(other[:incompatible]).include?(id) }.map { |other| other[:id] }
        (direct + reverse).uniq.sort.map do |other_id|
          other = @mods[other_id]
          {
            :id => other_id,
            :name => other ? other[:name] : other_id,
            :installed => !other.nil?,
            :enabled => other ? !!other[:enabled] : false,
            :status => other && other[:enabled] ? :conflict : :ok
          }
        end
      end

      def profile_summary
        base = if defined?(Reloaded::Profiles)
                 Reloaded::Profiles.summary
               else
                 {
                   :id => "none",
                   :name => "None",
                   :enabled_mods => 0,
                   :disabled_mods => 0,
                   :load_order => 0,
                   :mod_settings => 0,
                   :active => false
                 }
               end
        missing = defined?(Reloaded::Profiles) ? Reloaded::Profiles.missing_mod_ids(@mods.keys) : []
        base.merge(
          :available_mods => @mods.length,
          :active_mods => @active_mods.length,
          :loaded_mods => @loaded_mods.length,
          :skipped_mods => @skipped_mods.length,
          :invalid_mods => @invalid_mods.length,
          :missing_mods => missing,
          :moddev_enabled => moddev_enabled?
        )
      end

      def mod_status(mod_id)
        mod = @mods[normalize_mod_id(mod_id)]
        return :missing unless mod
        return :invalid unless Array(mod[:errors]).empty?
        return :broken if Array(mod[:system_tags]).include?("broken")
        return :conflict if Array(mod[:system_tags]).include?("conflict")
        return :missing_dependency if Array(mod[:system_tags]).include?("missing_dependency")
        return :disabled unless mod[:enabled]
        :enabled
      end

      def moddev_enabled?
        @moddev_enabled = read_moddev_enabled if @moddev_enabled.nil?
        @moddev_enabled
      end

      def set_moddev_enabled(value, persist: true)
        next_value = truthy?(value)
        previous_value = @moddev_enabled.nil? ? read_moddev_enabled : @moddev_enabled
        @moddev_enabled = next_value
        changed = previous_value != @moddev_enabled
        Reloaded::Settings.set_bool("moddev", @moddev_enabled, persist: persist) if changed && persist && defined?(Reloaded::Settings)
        if changed && defined?(Reloaded::Log)
          Reloaded::Log.info("ModDev #{moddev_enabled? ? 'enabled' : 'disabled'}", :mods)
        end
        @moddev_enabled
      end

      def scan
        reset
        scan_folder(MODS_DIR, :mods)
        scan_folder(MODDEV_DIR, :moddev) if moddev_enabled?
        Reloaded::Log.info("Scanned #{@candidates.length} mod candidate(s)", :mods) if defined?(Reloaded::Log)
        @candidates
      end

      def validate
        @candidates.each do |candidate|
          errors = validate_candidate(candidate)
          candidate[:errors] = errors
          if errors.empty?
            register_valid_candidate(candidate)
          else
            candidate[:system_tags] << "invalid"
            @invalid_mods << candidate
            log_invalid(candidate)
          end
        end
        validate_disabled_mods
        validate_incompatibilities
        @mods
      end

      def build_load_order
        ordered = []
        visiting = {}
        visited = {}
        ordered_ids.each { |id| visit_mod(id, ordered, visiting, visited) }
        @active_mods = ordered.select { |mod| mod[:enabled] && mod[:errors].empty? }
        @active_mods
      end

      def load_active_mods
        @active_mods.each { |mod| load_mod_scripts(mod) }
      end

      private

      def read_moddev_enabled
        return Reloaded::Settings.bool("moddev", DEFAULT_MODDEV_ENABLED) if defined?(Reloaded::Settings)
        DEFAULT_MODDEV_ENABLED
      rescue
        DEFAULT_MODDEV_ENABLED
      end

      def build_mod_row(mod)
        id = mod[:id].to_s
        {
          :id => id,
          :name => mod[:name].to_s,
          :version => mod[:version].to_s,
          :authors => Array(mod[:authors]).map(&:to_s),
          :description => mod[:description].to_s,
          :source => mod[:source],
          :folder_path => mod[:folder_path],
          :manifest_path => mod[:manifest_path],
          :enabled => !!mod[:enabled],
          :profile_enabled => profile_enabled?(id),
          :profile_disabled => profile_disabled?(id),
          :loaded => loaded_mod_id?(id),
          :status => mod_status(id),
          :tags => normalize_string_array(mod[:tags]),
          :system_tags => normalize_string_array(mod[:system_tags]),
          :dependencies => dependency_status(id),
          :incompatibilities => incompatibility_status(id),
          :warnings => Array(mod[:warnings]).map(&:to_s),
          :errors => Array(mod[:errors]).map(&:to_s),
          :scripts_loaded => scripts_loaded_for(id),
          :moddev => mod[:source] == :moddev
        }
      end

      def dependency_status_entry(mod, dependency)
        dep_id = dependency[:id].to_s.downcase
        required = dependency[:version].to_s
        required = nil if required.empty?
        dep_mod = @mods[dep_id]
        status = if dep_mod.nil?
                   :missing
                 elsif !dep_mod[:enabled]
                   :disabled
                 elsif required && compare_versions(dep_mod[:version], required) < 0
                   :version_mismatch
                 else
                   :ok
                 end
        {
          :id => dep_id,
          :name => dep_mod ? dep_mod[:name] : dep_id,
          :required_version => required,
          :installed_version => dep_mod ? dep_mod[:version] : nil,
          :installed => !dep_mod.nil?,
          :enabled => dep_mod ? !!dep_mod[:enabled] : false,
          :status => status
        }
      end

      def profile_enabled?(mod_id)
        defined?(Reloaded::Profiles) ? Reloaded::Profiles.enabled_mod_ids.include?(normalize_mod_id(mod_id)) : false
      end

      def profile_disabled?(mod_id)
        defined?(Reloaded::Profiles) ? Reloaded::Profiles.disabled_mod_ids.include?(normalize_mod_id(mod_id)) : false
      end

      def loaded_mod_id?(mod_id)
        @loaded_mods.any? { |mod| mod[:id].to_s == normalize_mod_id(mod_id) }
      end

      def scripts_loaded_for(mod_id)
        loaded = @loaded_mods.find { |mod| mod[:id].to_s == normalize_mod_id(mod_id) }
        loaded ? loaded[:scripts_loaded].to_i : 0
      end

      def truthy?(value)
        case value.to_s.strip.downcase
        when "1", "true", "on", "yes", "enabled", "enable" then true
        else false
        end
      end

      def reset
        @candidates = []
        @mods = {}
        @active_mods = []
        @invalid_mods = []
        @loaded_mods = []
        @skipped_mods = []
        @script_count = 0
        @active_profile = defined?(Reloaded::Profiles) ? Reloaded::Profiles.active : nil
      end

      def scan_folder(root, source)
        return unless Dir.exist?(root)
        Dir[File.join(root, "*", "mod.json")].sort.each do |manifest_path|
          candidate = read_manifest(manifest_path, root, source)
          @candidates << candidate if candidate
        end
      end

      def read_manifest(manifest_path, root, source)
        raw = File.read(manifest_path)
        data = parse_json(raw)
        folder_path = File.dirname(manifest_path)
        {
          :id => data["id"].to_s,
          :name => data["name"].to_s,
          :version => data["version"].to_s,
          :authors => data["authors"],
          :description => data["description"].to_s,
          :minimum_reloaded_version => data["minimum_reloaded_version"].to_s,
          :dependencies => normalize_dependencies(data["dependencies"]),
          :incompatible => normalize_string_array(data["incompatible"]),
          :tags => normalize_string_array(data["tags"]),
          :system_tags => [],
          :enabled => data.has_key?("enabled") ? !!data["enabled"] : true,
          :manifest_enabled => data.has_key?("enabled") ? !!data["enabled"] : true,
          :manifest => data,
          :manifest_path => manifest_path.gsub("\\", "/"),
          :folder_path => folder_path.gsub("\\", "/"),
          :folder_name => File.basename(folder_path),
          :source => source,
          :root => root.gsub("\\", "/"),
          :errors => [],
          :warnings => []
        }
      rescue Exception => e
        candidate = {
          :id => File.basename(File.dirname(manifest_path)).downcase,
          :name => File.basename(File.dirname(manifest_path)),
          :manifest_path => manifest_path.gsub("\\", "/"),
          :folder_path => File.dirname(manifest_path).gsub("\\", "/"),
          :source => source,
          :errors => ["Manifest could not be parsed: #{e.class}: #{e}"],
          :warnings => [],
          :system_tags => ["invalid"],
          :enabled => false
        }
        @invalid_mods << candidate
        log_invalid(candidate)
        nil
      end

      def parse_json(raw)
        raise "JSON parser is not available" unless defined?(JSON)
        JSON.parse(raw)
      end

      def validate_candidate(candidate)
        errors = []
        REQUIRED_FIELDS.each do |field|
          value = candidate[:manifest][field] rescue nil
          errors << "Missing required field: #{field}" if value.nil?
        end
        errors << "id must use lowercase letters, numbers, and underscores" unless candidate[:id] =~ /\A[a-z0-9_]+\z/
        errors << "version must use Major.Minor.Patch" unless valid_version?(candidate[:version])
        errors << "minimum_reloaded_version must use Major.Minor.Patch" unless valid_version?(candidate[:minimum_reloaded_version])
        errors << "authors must be a non-empty array" unless candidate[:authors].is_a?(Array) && !candidate[:authors].empty?
        errors << "dependencies must be an array" unless candidate[:dependencies].is_a?(Array)
        errors << "tags must be an array" unless candidate[:tags].is_a?(Array)
        errors << "folder name should match id" unless candidate[:folder_name].to_s.downcase == candidate[:id]
        if valid_version?(candidate[:minimum_reloaded_version]) && compare_versions(reloaded_version, candidate[:minimum_reloaded_version]) < 0
          errors << "Requires Reloaded #{candidate[:minimum_reloaded_version]} or newer"
          candidate[:system_tags] << "outdated"
        end
        validate_tags(candidate)
        validate_optional_folders(candidate)
        errors
      end

      def validate_tags(candidate)
        allowed = (AUTHOR_TAGS.values.flatten + SYSTEM_TAGS).uniq
        candidate[:tags].each do |tag|
          candidate[:warnings] << "Unknown tag: #{tag}" unless allowed.include?(tag)
        end
      end

      def validate_optional_folders(candidate)
        ["Settings.json"].each do |file|
          next unless File.exist?(File.join(candidate[:folder_path], file))
          candidate[:warnings] << "#{file} is reserved for future Mod Manager settings support"
        end
      end

      def register_valid_candidate(candidate)
        candidate[:system_tags] << "moddev" if candidate[:source] == :moddev
        existing = @mods[candidate[:id]]
        if existing && existing[:source] == :mods && candidate[:source] == :moddev
          @mods[candidate[:id]] = candidate
          @skipped_mods << skip_entry(existing, "Overridden by ModDev version")
          Reloaded::Log.info("ModDev override: #{candidate[:id]} from #{candidate[:folder_path]}", :mods) if defined?(Reloaded::Log)
        elsif existing
          candidate[:system_tags] << "conflict"
          @skipped_mods << skip_entry(candidate, "Duplicate mod id already registered")
          Reloaded::Log.warning("Duplicate mod id skipped: #{candidate[:id]} at #{candidate[:folder_path]}", :mods) if defined?(Reloaded::Log)
        else
          @mods[candidate[:id]] = candidate
        end
      end

      def validate_disabled_mods
        apply_profile_state
        @mods.each_value do |mod|
          next if mod[:enabled]
          @skipped_mods << skip_entry(mod, "Disabled")
        end
      end

      def apply_profile_state
        if defined?(Reloaded::Profiles)
          missing = Reloaded::Profiles.missing_mod_ids(@mods.keys)
          missing.each do |id|
            Reloaded::Log.warning("Active profile references missing mod: #{id}", :mods) if defined?(Reloaded::Log)
          end
          @mods.each_value do |mod|
            mod[:enabled] = Reloaded::Profiles.enabled?(mod[:id])
            mod[:system_tags] << "disabled" unless mod[:enabled] || mod[:system_tags].include?("disabled")
          end
        else
          @mods.each_value do |mod|
            mod[:system_tags] << "disabled" unless mod[:enabled] || mod[:system_tags].include?("disabled")
          end
        end
      end

      def validate_incompatibilities
        @mods.each_value do |mod|
          next unless mod[:enabled]
          mod[:incompatible].each do |other_id|
            other = @mods[other_id]
            next unless other && other[:enabled]
            mod[:system_tags] << "conflict"
            other[:system_tags] << "conflict"
            @skipped_mods << skip_entry(mod, "Incompatible with #{other_id}")
            mod[:enabled] = false
            Reloaded::Log.critical("Mod #{mod[:id]} skipped: incompatible with #{other_id}", :mods) if defined?(Reloaded::Log)
          end
        end
      end

      def visit_mod(id, ordered, visiting, visited)
        return if visited[id]
        mod = @mods[id]
        return unless mod
        if visiting[id]
          mod[:system_tags] << "conflict"
          mod[:enabled] = false
          @skipped_mods << skip_entry(mod, "Dependency cycle detected")
          Reloaded::Log.critical("Dependency cycle detected at #{id}", :mods) if defined?(Reloaded::Log)
          return
        end
        visiting[id] = true
        mod[:dependencies].each do |dependency|
          dep_id = dependency[:id]
          dep_mod = @mods[dep_id]
          if dep_mod.nil?
            mark_missing_dependency(mod, dep_id)
            next
          end
          unless dep_mod[:enabled]
            mark_missing_dependency(mod, "#{dep_id} (disabled)")
            next
          end
          if dependency[:version] && compare_versions(dep_mod[:version], dependency[:version]) < 0
            mark_missing_dependency(mod, "#{dep_id} >= #{dependency[:version]}")
            next
          end
          visit_mod(dep_id, ordered, visiting, visited)
        end
        visiting.delete(id)
        visited[id] = true
        ordered << mod unless ordered.include?(mod)
      end

      def mark_missing_dependency(mod, dependency)
        mod[:system_tags] << "missing_dependency"
        mod[:enabled] = false
        @skipped_mods << skip_entry(mod, "Missing dependency: #{dependency}")
        Reloaded::Log.critical("Mod #{mod[:id]} skipped: missing dependency #{dependency}", :mods) if defined?(Reloaded::Log)
      end

      def load_mod_scripts(mod)
        scripts = Dir[File.join(mod[:folder_path], "Scripts", "**", "*.rb")].sort
        if scripts.empty?
          @loaded_mods << mod.merge(:scripts_loaded => 0)
          Reloaded::Log.mod(mod[:id], "Loaded metadata/assets only")
          return true
        end
        previous = Thread.current[:reloaded_mod_id]
        Thread.current[:reloaded_mod_id] = mod[:id]
        current_script = nil
        begin
          scripts.each do |script|
            current_script = script
            load script
            @script_count += 1
            Reloaded::Log.mod(mod[:id], "Loaded script #{relative_to_mod(mod, script)}")
          end
          @loaded_mods << mod.merge(:scripts_loaded => scripts.length)
          true
        rescue Exception => e
          mod[:system_tags] << "broken"
          @skipped_mods << skip_entry(mod, "Script failed: #{relative_to_mod(mod, current_script)}")
          Reloaded::Log.exception("Mod #{mod[:id]} script failed: #{current_script}", e, channel: :mods) if defined?(Reloaded::Log)
          Reloaded::Log.report(
            :type => "Mod Script Failure",
            :mod_id => mod[:id],
            :mod_name => mod[:name],
            :version => mod[:version],
            :level => :critical,
            :file_path => current_script,
            :dependency_status => "Dependencies loaded before script execution.",
            :recommended_fix => "Fix the script error or disable #{mod[:name]}.",
            :error => e
          ) if defined?(Reloaded::Log)
          false
        ensure
          Thread.current[:reloaded_mod_id] = previous
        end
      end

      def write_summary
        Reloaded::Log.summary(
          :mod_candidates => @candidates.length,
          :valid_mods => @mods.length,
          :active_mods => @active_mods.length,
          :loaded_mods => @loaded_mods.length,
          :skipped_mods => @skipped_mods.length,
          :scripts_loaded => @script_count,
          :active_profile => active_profile_name,
          :moddev_enabled => moddev_enabled?
        ) if defined?(Reloaded::Log)
      end

      def log_invalid(candidate)
        Array(candidate[:errors]).each do |error|
          Reloaded::Log.critical("Invalid mod #{candidate[:manifest_path]}: #{error}", :mods) if defined?(Reloaded::Log)
        end
      end

      def skip_entry(mod, reason)
        {
          :id => mod[:id],
          :name => mod[:name],
          :reason => reason,
          :source => mod[:source],
          :folder_path => mod[:folder_path]
        }
      end

      def normalize_dependencies(value)
        return [] if value.nil? || !value.is_a?(Array)
        value.map do |entry|
          if entry.is_a?(Hash)
            {
              :id => (entry["id"] || entry["mod_id"] || entry["uid"]).to_s,
              :version => (entry["version"] || entry["minimum_version"] || entry["min_version"])
            }
          else
            { :id => entry.to_s, :version => nil }
          end
        end.reject { |entry| entry[:id].empty? }
      end

      def normalize_string_array(value)
        return [] if value.nil? || !value.is_a?(Array)
        value.map { |entry| entry.to_s.strip.downcase }.reject { |entry| entry.empty? }
      end

      def normalize_mod_id(value)
        value.to_s.strip.downcase
      end

      def valid_version?(version)
        version.to_s =~ /\A\d+\.\d+\.\d+\z/
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

      def reloaded_version
        Reloaded::VERSION rescue "0.0.0"
      end

      def relative_to_mod(mod, path)
        path.to_s.gsub("\\", "/").sub(mod[:folder_path].to_s + "/", "")
      end

      def emit(event_name, context)
        Reloaded::Events.emit(event_name, context) if defined?(Reloaded::Events)
      rescue Exception => e
        Reloaded::Log.exception("Mod Manager event #{event_name} failed", e, channel: :mods) if defined?(Reloaded::Log)
      end

      def ordered_ids
        if defined?(Reloaded::Profiles)
          Reloaded::Profiles.ordered_mod_ids(@mods.keys)
        else
          @mods.keys.sort
        end
      end

      def active_profile_name
        defined?(Reloaded::Profiles) ? Reloaded::Profiles.active_name : "None"
      end
    end
  end
end
