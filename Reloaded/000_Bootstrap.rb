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
  module Bootstrap
    ROOT     = File.expand_path(File.dirname(__FILE__))
    LOG_DIR  = File.join(ROOT, "Logging")
    LOG_FILE = File.join(LOG_DIR, "Log.txt")
    VERSION_FILE = File.join(ROOT, "Version.md")

    class << self
      def boot
        return if @booted
        @booted = true

        ensure_log_dir
        load_version
        log("Boot start")
        load_folder("Core")
        Reloaded::Log.boot_header if defined?(Reloaded::Log)
        emit(:bootstrap_loaded)
        boot_core_systems
        emit(:core_loaded)
        load_folder("Modules")
        emit(:modules_loaded)
        log("Boot complete")
      rescue Exception => e
        log("Boot failed: #{e.class}: #{e}", "ERROR") rescue nil
        puts("[Reloaded] Boot failed: #{e.class}: #{e}") rescue nil
        puts(e.backtrace.join("\n")) rescue nil
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
        line = "[#{timestamp}] [#{level}] #{message}"
        if defined?(Reloaded::Log)
          Reloaded::Log.write(:bootstrap, message, level: level.downcase.to_sym)
        else
          File.open(LOG_FILE, "a") { |f| f.puts(line) } rescue nil
        end
        puts("[Reloaded] #{message}") rescue nil
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

      def load_version
        version = if File.exist?(VERSION_FILE)
                    File.read(VERSION_FILE).to_s.strip
                  else
                    "0.0.0"
                  end
        Reloaded.const_set(:VERSION, version) unless Reloaded.const_defined?(:VERSION)
      rescue
        Reloaded.const_set(:VERSION, "0.0.0") unless Reloaded.const_defined?(:VERSION)
      end

      def boot_core_systems
        boot_system("Profiles", Reloaded::Profiles) if defined?(Reloaded::Profiles)
        boot_system("ModManager", Reloaded::ModManager) if defined?(Reloaded::ModManager)
        boot_system("ModSettings", Reloaded::ModSettings) if defined?(Reloaded::ModSettings)
        boot_system("ProfileCodes", Reloaded::ProfileCodes) if defined?(Reloaded::ProfileCodes)
        boot_system("ModBrowser", Reloaded::ModBrowser) if defined?(Reloaded::ModBrowser)
        boot_system("Publisher", Reloaded::Publisher) if defined?(Reloaded::Publisher)
      end

      def boot_system(label, system)
        return true unless system.respond_to?(:boot)
        result = system.boot
        log("Booted #{label}") if result
        result
      rescue Exception => e
        log("Failed to boot #{label}: #{e.class}: #{e}", "ERROR")
        false
      end

      def emit(event_name)
        if defined?(Reloaded::Events)
          Reloaded::Events.emit(event_name, {
            :event => event_name,
            :reloaded_version => (Reloaded::VERSION rescue nil),
            :bootstrap_root => ROOT
          })
        elsif defined?(Reloaded::Hooks)
          Reloaded::Hooks.run(event_name)
        end
      end

      def load_file(path)
        load path
        log("Loaded #{relative_path(path)}")
      rescue Exception => e
        log("Error loading #{relative_path(path)}: #{e.class}: #{e}", "ERROR")
        puts("[Reloaded] Error loading #{path}: #{e.class}: #{e}") rescue nil
        puts(e.backtrace.first(5).join("\n")) rescue nil
      end

      def relative_path(path)
        path.to_s.sub(ROOT + File::SEPARATOR, "").gsub("\\", "/")
      rescue
        path.to_s
      end
    end
  end
end
