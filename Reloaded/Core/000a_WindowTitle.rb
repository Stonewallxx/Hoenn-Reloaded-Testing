#======================================================
# Reloaded Window Title
# Author: Stonewall
#======================================================
# Keeps the game window title aligned with the Reloaded fork version.
#
# Responsibilities:
#   - Build the Hoenn Reloaded window title from Reloaded::VERSION.
#   - Apply the title through the base game's mkxp window title helper.
#   - Log title update failures without blocking startup.
#
#======================================================

module Reloaded
  module WindowTitle
    PREFIX = "Hoenn Reloaded".freeze

    class << self
      def title
        version = defined?(Reloaded::VERSION) ? Reloaded::VERSION.to_s.strip : ""
        version.empty? ? PREFIX : "#{PREFIX} #{version}"
      end

      def apply
        if defined?(pbSetWindowText)
          pbSetWindowText(title)
          Reloaded::Log.debug_once("Window title set to #{title}", :framework, key: "window_title_set") if defined?(Reloaded::Log) && Reloaded::Log.respond_to?(:debug_once)
          return true
        end
        false
      rescue Exception => e
        Reloaded::Log.exception("Failed to set Reloaded window title", e, channel: :framework) if defined?(Reloaded::Log)
        false
      end
    end
  end
end

Reloaded::WindowTitle.apply if defined?(Reloaded::WindowTitle)
