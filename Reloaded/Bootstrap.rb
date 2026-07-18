#======================================================
# Reloaded Bootstrap
# Author: Stonewall
#======================================================
# Small startup layer loaded from Data/Scripts/999_Main/999_Main.rb.
#
# Responsibilities:
#   - Load the Reloaded version from Reloaded/Version.md.
#   - Load framework files from Reloaded/Core.
#   - Boot core runtime systems in a predictable order.
#   - Load feature/module files from Reloaded/Modules.
#   - Emit early lifecycle events for framework systems.
#   - Write basic bootstrap diagnostics through Reloaded::Log.
#
#======================================================

module Reloaded
  VERSION_ROOT = File.expand_path(File.dirname(__FILE__)) unless const_defined?(:VERSION_ROOT, false)
  VERSION_FILE = File.join(VERSION_ROOT, "Version.md") unless const_defined?(:VERSION_FILE, false)

  class << self
    def version
      value = File.exist?(VERSION_FILE) ? File.read(VERSION_FILE).to_s.strip : ""
      value.empty? ? "0.0.0" : value
    rescue
      "0.0.0"
    end

    def shutdown
      Bootstrap.shutdown
    end
  end

  module Bootstrap
    ROOT     = File.expand_path(File.dirname(__FILE__))
    LOG_DIR  = File.join(ROOT, "Logging")
    LOG_FILE = File.join(LOG_DIR, "Log.txt")
    VERSION_FILE = File.join(ROOT, "Version.md")
    LOAD_ORDER_FILE = File.join(ROOT, "LoadOrder.rb")
    REQUIRED_SYSTEMS = [
      ["Platform", :Platform],
      ["Systems", :Systems],
      ["Features", :Features],
      ["Validation", :Validation],
      ["Profiles", :Profiles],
      ["ModManager", :ModManager],
      ["ModSettings", :ModSettings],
      ["ProfileCodes", :ProfileCodes]
    ].freeze
    OPTIONAL_SYSTEMS = [
      ["TempCleanup", :TempCleanup],
      ["ModBrowser", :ModBrowser],
      ["Publisher", :Publisher]
    ].freeze

    class << self
      def boot
        return true if @status == :ready
        return false if @status == :running
        @status = :running
        @failures = []

        ensure_log_dir
        load_version
        log("Boot start")
        return fail_boot("LoadOrder.rb is unavailable or invalid") unless load_order_manifest
        return fail_boot("A required Core file failed to load") unless load_scope(:core, required: true)
        Reloaded::Log.boot_header if defined?(Reloaded::Log)
        emit(:bootstrap_loaded)
        return fail_boot("A required Core system failed to boot") unless boot_core_systems
        emit(:core_loaded)
        load_scope(:modules, required: false)
        emit(:modules_loaded)
        @status = @failures.empty? ? :ready : :degraded
        log("Boot complete")
        true
      rescue Exception => e
        @status = :failed
        @failures ||= []
        @failures << { :stage => :bootstrap, :error => e }
        log("Boot failed: #{e.class}: #{e}", "ERROR") rescue nil
        console("Boot failed: #{e.class}: #{e}", "ERROR") rescue nil
        console(Array(e.backtrace).map { |line| sanitize_path(line) }.join("\n"), "ERROR") rescue nil
        false
      end

      def status
        @status || :not_started
      end

      def ready?
        status == :ready || status == :degraded
      end

      def degraded?
        status == :degraded
      end

      def failures
        Array(@failures).dup
      end

      def shutdown
        return true if @shutting_down
        @shutting_down = true
        emit(:reloaded_shutdown)
        shutdown_system("Task", Reloaded::Task) if defined?(Reloaded::Task)
        shutdown_system("ModBrowser", Reloaded::ModBrowser) if defined?(Reloaded::ModBrowser)
        if defined?(ReloadedMart::Source)
          shutdown_system("ReloadedMart::Source", ReloadedMart::Source)
        end
        log("Reloaded shutdown complete", "DEBUG")
        true
      rescue Exception => e
        log("Reloaded shutdown failed: #{e.class}: #{e}", "WARNING") rescue nil
        false
      ensure
        @shutting_down = false
      end

      def ensure_log_dir
        Dir.mkdir(LOG_DIR) unless Dir.exist?(LOG_DIR)
      rescue
      end

      def timestamp
        Time.now.strftime("%H:%M:%S")
      end

      def log(message, level = "INFO")
        ensure_log_dir
        sanitized = sanitize_path(message)
        line = "[#{timestamp}] [#{level}] #{sanitized}"
        if defined?(Reloaded::Log)
          Reloaded::Log.write(:bootstrap, sanitized, level: level.downcase.to_sym)
        else
          File.open(LOG_FILE, "a") { |f| f.puts(line) } rescue nil
        end
        console(sanitized, level)
      end

      def load_folder(folder_name)
        folder = File.join(ROOT, folder_name)
        unless Dir.exist?(folder)
          log("Skipped missing folder: #{folder_name}")
          return
        end

        Dir[File.join(folder, "*.rb")].sort.each do |path|
          load_file(path)
        end
      end

      def load_order_manifest
        unless File.exist?(LOAD_ORDER_FILE)
          log("Missing required load manifest: LoadOrder.rb", "ERROR")
          return false
        end
        return false unless load_file(LOAD_ORDER_FILE)
        validate_load_order
      rescue Exception => e
        log("Load manifest failed: #{e.class}: #{e}", "ERROR")
        false
      end

      def load_scope(scope, required: true)
        unless defined?(Reloaded::LoadOrder)
          log("Load manifest unavailable for #{scope} scope", "ERROR")
          return false
        end
        succeeded = true
        Reloaded::LoadOrder.phases(scope).each do |phase|
          log("Loading #{phase[:id]} phase", "DEBUG")
          Array(phase[:files]).each do |relative|
            loaded = load_file(File.join(ROOT, relative))
            next if loaded
            succeeded = false
            record_failure(:file, relative)
            return false if required
          end
        end
        succeeded || !required
      rescue Exception => e
        log("Failed loading #{scope} scope: #{e.class}: #{e}", "ERROR")
        false
      end

      def validate_load_order
        return false unless defined?(Reloaded::LoadOrder)
        listed = Reloaded::LoadOrder.files
        valid = true
        duplicates = listed.group_by { |path| normalized_manifest_path(path) }.select { |_path, entries| entries.length > 1 }.keys
        duplicates.each do |path|
          valid = false
          log("Duplicate load manifest entry: #{path}", "ERROR")
        end
        listed.each do |relative|
          normalized = normalized_manifest_path(relative)
          if normalized.start_with?("/") || normalized.split("/").include?("..")
            valid = false
            log("Invalid load manifest path: #{relative}", "ERROR")
          elsif !File.exist?(File.join(ROOT, relative))
            valid = false
            log("Missing load manifest file: #{relative}", "ERROR")
          end
        end
        discovered = ["Core", "Modules"].inject([]) do |result, folder|
          result.concat(Dir[File.join(ROOT, folder, "**", "*.rb")].map { |path| relative_path(path) })
        end
        listed_keys = listed.map { |path| normalized_manifest_path(path) }
        discovered.each do |relative|
          log("Unlisted Reloaded Ruby file will not load: #{relative}", "WARNING") unless listed_keys.include?(normalized_manifest_path(relative))
        end
        valid
      rescue Exception => e
        log("Load manifest validation failed: #{e.class}: #{e}", "ERROR")
        false
      end

      def normalized_manifest_path(path)
        path.to_s.gsub("\\", "/").sub(/\A\.\//, "").downcase
      end

      def load_version
        Reloaded.send(:remove_const, :VERSION) if Reloaded.const_defined?(:VERSION, false)
        Reloaded.const_set(:VERSION, Reloaded.version)
      rescue
        Reloaded.send(:remove_const, :VERSION) if Reloaded.const_defined?(:VERSION, false)
        Reloaded.const_set(:VERSION, "0.0.0") unless Reloaded.const_defined?(:VERSION)
      end

      def boot_core_systems
        REQUIRED_SYSTEMS.each do |label, constant_name|
          system = Reloaded.const_get(constant_name) if Reloaded.const_defined?(constant_name, false)
          unless system
            record_failure(:system, label)
            log("Required system is missing: #{label}", "ERROR")
            return false
          end
          return false unless boot_system(label, system, required: true)
        end
        OPTIONAL_SYSTEMS.each do |label, constant_name|
          next unless Reloaded.const_defined?(constant_name, false)
          boot_system(label, Reloaded.const_get(constant_name), required: false)
        end
        true
      end

      def boot_system(label, system, required: false)
        return true unless system.respond_to?(:boot)
        result = system.boot
        if result
          log("Booted #{label}")
          true
        else
          record_failure(:system, label)
          log("#{required ? 'Required' : 'Optional'} system did not boot: #{label}", required ? "ERROR" : "WARNING")
          !required
        end
      rescue Exception => e
        record_failure(:system, label, e)
        log("Failed to boot #{label}: #{e.class}: #{e}", required ? "ERROR" : "WARNING")
        !required
      end

      def shutdown_system(label, system)
        return true unless system.respond_to?(:shutdown)
        result = system.shutdown
        log("Shutdown #{label}", "DEBUG") if result
        result
      rescue Exception => e
        log("Failed to shutdown #{label}: #{e.class}: #{e}", "WARNING")
        false
      end

      def fail_boot(reason)
        @status = :failed
        record_failure(:bootstrap, reason)
        log("Reloaded boot stopped: #{reason}", "FATAL")
        false
      end

      def record_failure(stage, subject, error = nil)
        @failures ||= []
        @failures << { :stage => stage, :subject => subject.to_s, :error => error }
      end

      def emit(event_name)
        if defined?(Reloaded::Events)
          Reloaded::Events.emit(event_name, {
            :event => event_name,
            :reloaded_version => Reloaded.version,
            :bootstrap_root => ROOT
          })
        elsif defined?(Reloaded::Hooks)
          Reloaded::Hooks.run(event_name)
        end
      end

      def load_file(path)
        load path
        log("Loaded #{relative_path(path)}", "DEBUG")
        true
      rescue Exception => e
        log("Error loading #{relative_path(path)}: #{e.class}: #{e}", "ERROR")
        console("Error loading #{relative_path(path)}: #{e.class}: #{e}", "ERROR") rescue nil
        console(Array(e.backtrace).first(5).map { |line| sanitize_path(line) }.join("\n"), "ERROR") rescue nil
        false
      end

      def relative_path(path)
        path.to_s.sub(ROOT + File::SEPARATOR, "").gsub("\\", "/")
      rescue
        path.to_s
      end

      def sanitize_path(value)
        text = value.to_s.gsub("\\", "/")
        root = ROOT.gsub("\\", "/")
        game_root = File.expand_path(File.join(ROOT, "..")).gsub("\\", "/")
        text = text.gsub(/#{Regexp.escape(game_root)}(?=\/|\z)/i, "")
        text = text.gsub(/#{Regexp.escape(root)}(?=\/|\z)/i, "/Reloaded")
        text
      rescue
        value.to_s
      end

      def console(message, level = "INFO")
        return unless ["ERROR", "WARNING", "WARN", "FATAL", "CRITICAL"].include?(level.to_s.upcase)
        puts("[Reloaded] #{sanitize_path(message)}") rescue nil
      end
    end
  end
end
