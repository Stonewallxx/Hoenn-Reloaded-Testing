#==============================================================================
# Hoenn Reloaded Hooks
#==============================================================================
# Lightweight event registry for fork/framework systems.
#
# Example:
#   Reloaded::Hooks.on(:bootstrap_loaded, :my_feature) { ... }
#   Reloaded::Hooks.run(:bootstrap_loaded)
#==============================================================================

module Reloaded
  module Hooks
    @events = {}

    class << self
      def on(event_name, id = nil, priority = 100, &block)
        return false unless block
        event = event_name.to_sym
        @events[event] ||= []
        hook_id = id || "hook_#{@events[event].length + 1}"
        @events[event].reject! { |entry| entry[:id] == hook_id }
        @events[event] << {
          :id => hook_id,
          :priority => priority.to_i,
          :block => block
        }
        @events[event].sort_by! { |entry| [entry[:priority], entry[:id].to_s] }
        true
      end

      def run(event_name, *args)
        event = event_name.to_sym
        entries = @events[event] || []
        entries.each do |entry|
          begin
            entry[:block].call(*args)
          rescue Exception => e
            log_error(event, entry[:id], e)
          end
        end
        entries.length
      end

      def registered(event_name = nil)
        return @events if event_name.nil?
        @events[event_name.to_sym] || []
      end

      def clear(event_name = nil)
        if event_name
          @events.delete(event_name.to_sym)
        else
          @events.clear
        end
      end

      private

      def log_error(event, id, error)
        if defined?(Reloaded::Bootstrap)
          Reloaded::Bootstrap.log(
            "Hook #{event}/#{id} failed: #{error.class}: #{error}",
            "ERROR"
          ) rescue nil
        end
      end
    end
  end
end
