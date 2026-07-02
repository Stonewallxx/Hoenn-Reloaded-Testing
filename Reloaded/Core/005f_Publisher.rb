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

      def launch_tool
        raise "Publisher batch file is missing: #{PUBLISH_BAT}" unless available?
        system("start \"\" \"#{PUBLISH_BAT.gsub("/", "\\")}\"")
      end
    end
  end
end
