#======================================================
# Reloaded Publisher
# Author: Stonewall
#======================================================
# In-game bridge to the external GitHub publisher tool.
#
# Responsibilities:
#   - Locate the platform-specific ModDev GitHub publisher.
#   - Launch the publisher from the Mod Manager Tools menu.
#   - Keep selection, validation, packaging, and GitHub upload in the .bat tool.
#   - Avoid pending request files or local publish folders.
#
#======================================================

module Reloaded
  module Publisher
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    MODDEV_DIR = File.join(GAME_ROOT, "ModDev")

    @booted = false

    class << self
      def boot
        return true if @booted
        Reloaded::Log.info("Publisher launcher ready", :mods) if defined?(Reloaded::Log)
        @booted = true
        true
      rescue Exception => e
        @booted = false
        Reloaded::Log.exception("Publisher boot failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def available?
        !tool_path.nil?
      end

      def status_text
        return "Publisher ready." if available?
        return "Publisher tools are unavailable on this platform." unless desktop_tools?
        "Publisher file is missing: #{display_path(expected_tool_path)}"
      end

      def launch_tool
        raise status_text unless available?
        path = tool_path
        raise status_text unless path
        Reloaded::Platform.launch_script(path, File.dirname(path))
        Reloaded::Log.info("Publisher tool launched from #{display_path(path)}", :mods) if defined?(Reloaded::Log)
        true
      end

      def launch_async(on_success: nil, on_failure: nil, notify: nil)
        raise "Background tasks are unavailable." unless defined?(Reloaded::Task)
        raise status_text unless available?
        Reloaded::Task.start(:publisher_launch, {
          :owner => :publisher,
          :duplicate => :reject,
          :on_success => on_success,
          :on_failure => on_failure,
          :notify => notify.nil? ? {
            :success => "Publisher opened in a separate window.",
            :failure => "Could not open the publisher."
          } : notify
        }) do |task|
          task.report(0.1, "Opening publisher")
          result = launch_tool
          task.report(1.0, "Publisher opened")
          result
        end
      end

      def tool_path
        return nil unless desktop_tools?
        path = expected_tool_path
        File.exist?(path) ? path : nil
      end

      def expected_tool_path
        if defined?(Reloaded::Platform) && Reloaded::Platform.id == :proton
          File.join(MODDEV_DIR, "Proton", "Publish to GitHub.sh")
        else
          File.join(MODDEV_DIR, "Windows", "Publish to GitHub.bat")
        end
      end

      def desktop_tools?
        !defined?(Reloaded::Platform) || Reloaded::Platform.desktop_tools?
      end

      private

      def display_path(path)
        root = GAME_ROOT.to_s.gsub("\\", "/")
        value = path.to_s.gsub("\\", "/")
        value.sub(root, "")
      end
    end
  end
end
