#==============================================================================
# Hoenn Reloaded Bootstrap
#==============================================================================
# Small startup layer loaded from Data/Scripts/999_Main/999_Main.rb.
# Keep this file focused on framework loading only; feature code belongs in
# Reloaded/Core or Reloaded/Modules.
#==============================================================================

module Reloaded
  VERSION = "0.1.0" unless const_defined?(:VERSION)

  module Bootstrap
    ROOT     = File.expand_path(File.dirname(__FILE__))
    LOG_DIR  = File.join(ROOT, "Logging")
    LOG_FILE = File.join(LOG_DIR, "bootstrap.log")

    class << self
      def boot
        return if @booted
        @booted = true

        ensure_log_dir
        log("Boot start")
        load_folder("Core")
        Reloaded::Hooks.run(:bootstrap_loaded) if defined?(Reloaded::Hooks)
        load_folder("Modules")
        Reloaded::Hooks.run(:modules_loaded) if defined?(Reloaded::Hooks)
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
        File.open(LOG_FILE, "a") { |f| f.puts(line) } rescue nil
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
