#======================================================
# Reloaded Repository Tools
# Author: Stonewall
#======================================================
# In-game bridge to the fixed-action GitHub release tools.
#======================================================

module Reloaded
  module Publisher
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    TOOLS_DIR = File.join(GAME_ROOT, "ModDev", "Tools")
    ACTIONS = [:publish, :update, :delete].freeze
    KINDS = [:mod, :profile].freeze

    @booted = false

    class << self
      def boot
        return true if @booted
        Reloaded::Log.info("Repository tool launchers ready", :mods) if defined?(Reloaded::Log)
        @booted = true
        true
      rescue Exception => e
        @booted = false
        Reloaded::Log.exception("Repository tool launcher boot failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def available?(action = :publish)
        !tool_path(action).nil?
      end

      def status_text(action = :publish)
        label = action_label(action)
        return "#{label} tool ready." if available?(action)
        return "Repository tools are unavailable on this platform." unless desktop_tools?
        "Repository tool is missing: #{display_path(expected_tool_path(action))}"
      rescue Exception => e
        "Repository tool is unavailable: #{e.message}"
      end

      def launch_tool(action: :publish, kind: :mod)
        action = normalize_action(action)
        kind = normalize_kind(kind)
        raise status_text(action) unless available?(action)
        path = tool_path(action)
        arguments = [kind.to_s]
        Reloaded::Platform.launch_script(path, File.dirname(path), arguments)
        if defined?(Reloaded::Log)
          Reloaded::Log.info("Launched #{action} #{kind} tool from #{display_path(path)}", :mods)
        end
        true
      end

      def launch_async(action: :publish, kind: :mod, on_success: nil, on_failure: nil, notify: nil)
        raise "Background tasks are unavailable." unless defined?(Reloaded::Task)
        action = normalize_action(action)
        kind = normalize_kind(kind)
        raise status_text(action) unless available?(action)
        label = action_label(action)
        Reloaded::Task.start("repository_#{action}_#{kind}", {
          :owner => :publisher,
          :duplicate => :reject,
          :on_success => on_success,
          :on_failure => on_failure,
          :notify => notify.nil? ? {
            :success => "#{label} tool opened in a separate window.",
            :failure => "Could not open the #{label.downcase} tool."
          } : notify
        }) do |task|
          task.report(0.1, "Opening #{label.downcase} tool")
          result = launch_tool(:action => action, :kind => kind)
          task.report(1.0, "#{label} tool opened")
          result
        end
      end

      def tool_path(action = :publish)
        return nil unless desktop_tools?
        path = expected_tool_path(action)
        File.exist?(path) ? path : nil
      end

      def expected_tool_path(action = :publish)
        action = normalize_action(action)
        folder = proton? ? "Proton" : "Windows"
        extension = proton? ? ".sh" : ".bat"
        File.join(TOOLS_DIR, folder, "#{action_label(action)}#{extension}")
      end

      def desktop_tools?
        !defined?(Reloaded::Platform) || Reloaded::Platform.desktop_tools?
      end

      private

      def normalize_action(value)
        action = value.to_s.strip.downcase.to_sym
        raise "Unknown repository action: #{value}" unless ACTIONS.include?(action)
        action
      end

      def normalize_kind(value)
        kind = value.to_s.strip.downcase.to_sym
        raise "Unknown repository content type: #{value}" unless KINDS.include?(kind)
        kind
      end

      def action_label(action)
        normalize_action(action).to_s.capitalize
      end

      def proton?
        defined?(Reloaded::Platform) && Reloaded::Platform.id == :proton
      end

      def display_path(path)
        root = GAME_ROOT.to_s.gsub("\\", "/")
        value = path.to_s.gsub("\\", "/")
        value.sub(root, "")
      end
    end
  end
end
