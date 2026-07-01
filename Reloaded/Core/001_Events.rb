#======================================================
# Reloaded Events
# Author: Stonewall
#======================================================
# General event registry for fork/framework systems.
#
# Responsibilities:
#   - Register event handlers by event name and handler ID.
#   - Emit notification events to all registered handlers.
#   - Run decision events and return the first non-nil result.
#   - Remove handlers when they are no longer needed.
#   - Preserve Reloaded::Hooks as a compatibility alias.
#
#======================================================

module Reloaded
  module Events
    @events = {}

    class << self
      def on(event_name, id = nil, priority_arg = nil, priority: 100, &block)
        return false unless block
        event = event_name.to_sym
        @events[event] ||= []
        handler_id = (id || "handler_#{@events[event].length + 1}").to_sym
        priority_value = priority_arg.nil? ? priority : priority_arg
        @events[event].reject! { |entry| entry[:id] == handler_id }
        @events[event] << {
          :id => handler_id,
          :priority => priority_value.to_i,
          :block => block
        }
        @events[event].sort_by! { |entry| [entry[:priority], entry[:id].to_s] }
        Reloaded::Log.debug("Registered #{event}/#{handler_id} priority=#{priority_value}", :events) if defined?(Reloaded::Log)
        true
      end

      def emit(event_name, context = {})
        event = event_name.to_sym
        ctx = normalize_context(event, context)
        entries = @events[event] || []
        Reloaded::Log.debug("Emitting #{event} to #{entries.length} handler(s)", :events) if defined?(Reloaded::Log)
        entries.each do |entry|
          begin
            entry[:block].call(ctx)
          rescue Exception => e
            log_error(event, entry[:id], e)
          end
        end
        entries.length
      end

      def first_result(event_name, context = {})
        event = event_name.to_sym
        ctx = normalize_context(event, context)
        entries = @events[event] || []
        entries.each do |entry|
          begin
            result = entry[:block].call(ctx)
            return result unless result.nil?
          rescue Exception => e
            log_error(event, entry[:id], e)
          end
        end
        nil
      end

      def remove(event_name, id)
        event = event_name.to_sym
        return false unless @events[event]
        before = @events[event].length
        @events[event].reject! { |entry| entry[:id] == id.to_sym }
        removed = before != @events[event].length
        Reloaded::Log.debug("Removed #{event}/#{id}", :events) if removed && defined?(Reloaded::Log)
        removed
      end

      def handlers(event_name = nil)
        return @events if event_name.nil?
        @events[event_name.to_sym] || []
      end

      def registered(event_name = nil)
        handlers(event_name)
      end

      def clear(event_name = nil)
        if event_name
          @events.delete(event_name.to_sym)
        else
          @events.clear
        end
      end

      def run(event_name, *args)
        context = args.length == 1 && args[0].is_a?(Hash) ? args[0] : { :args => args }
        emit(event_name, context)
      end

      private

      def normalize_context(event, context)
        ctx = context.is_a?(Hash) ? context.dup : { :value => context }
        ctx[:event] ||= event
        ctx
      end

      def log_error(event, id, error)
        if defined?(Reloaded::Log)
          Reloaded::Log.exception("Event #{event}/#{id} failed", error, channel: :events)
        elsif defined?(Reloaded::Bootstrap)
          Reloaded::Bootstrap.log(
            "Hook #{event}/#{id} failed: #{error.class}: #{error}",
            "ERROR"
          ) rescue nil
        end
      end
    end
  end

  Hooks = Events unless const_defined?(:Hooks)
end
