#======================================================
# Reloaded Publisher
# Author: Stonewall
#======================================================
# In-game bridge to the external GitHub publisher tool.
#
# Responsibilities:
#   - Locate the Modders Tools GitHub publisher.
#   - Launch the publisher from the Mod Manager Tools menu.
#   - Keep selection, validation, packaging, and GitHub upload in the .bat tool.
#   - Avoid pending request files or local publish folders.
#
#======================================================

module Reloaded
  module Publisher
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    TOOL_DIR = File.join(GAME_ROOT, "Modders Tools")
    PUBLISH_BAT = File.join(TOOL_DIR, "Publish to GitHub.bat")

    @booted = false

    class << self
      def boot
        return true if @booted
        @booted = true
        Reloaded::Log.info("Publisher launcher ready", :mods) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Publisher boot failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def available?
        File.exist?(PUBLISH_BAT)
      end

      def status_text
        return "Publisher ready." if available?
        return "Publisher folder is missing: #{display_path(TOOL_DIR)}" unless Dir.exist?(TOOL_DIR)
        "Publisher batch file is missing: #{display_path(PUBLISH_BAT)}"
      end

      def launch_tool
        raise status_text unless available?
        command = "cmd /c start \"\" /D \"#{windows_path(TOOL_DIR)}\" \"#{windows_path(PUBLISH_BAT)}\""
        ok = system(command)
        raise "Windows could not launch the publisher tool." unless ok
        Reloaded::Log.info("Publisher tool launched from #{display_path(PUBLISH_BAT)}", :mods) if defined?(Reloaded::Log)
        true
      end

      private

      def windows_path(path)
        path.to_s.gsub("/", "\\")
      end

      def display_path(path)
        root = GAME_ROOT.to_s.gsub("\\", "/")
        value = path.to_s.gsub("\\", "/")
        value.sub(root, "")
      end
    end
  end
end
