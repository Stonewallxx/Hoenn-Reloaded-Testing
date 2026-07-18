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
    @contracts = {}
    @sequence = 0
    @failures = {}
    @disabled_handlers = {}
    FAILURE_LIMIT = 3

    class << self
      def define(event_name, config = nil, override: false, **keywords)
        event = event_name.to_sym
        raise "Event contract already defined: #{event}" if @contracts.key?(event) && !override
        source = config.is_a?(Hash) ? config.dup : {}
        source.merge!(keywords) unless keywords.empty?
        mode = (source[:mode] || source["mode"] || :notification).to_sym
        raise "Unknown event mode: #{mode}" unless [:notification, :decision].include?(mode)
        @contracts[event] = {
          :event => event,
          :mode => mode,
          :owner => (source[:owner] || source["owner"] || :reloaded).to_sym,
          :description => (source[:description] || source["description"] || "").to_s,
          :required_context => normalize_keys(source[:required_context] || source["required_context"]),
          :optional_context => normalize_keys(source[:optional_context] || source["optional_context"])
        }
        contract(event)
      rescue Exception => e
        Reloaded::Log.exception("Event contract registration failed for #{event_name}", e, channel: :events) if defined?(Reloaded::Log)
        nil
      end

      def on(event_name, id = nil, priority_arg = nil, priority: 100, owner: nil, requires: nil, &block)
        return false unless block
        event = event_name.to_sym
        warn_unknown_event(event, :handler)
        @events[event] ||= []
        @sequence += 1
        handler_id = (id || "handler_#{@sequence}").to_sym
        priority_value = priority_arg.nil? ? priority : priority_arg
        @events[event].reject! { |entry| entry[:id] == handler_id }
        clear_failure_state(event, handler_id)
        @events[event] << {
          :event => event,
          :id => handler_id,
          :priority => priority_value.to_i,
          :owner => (owner || current_owner).to_sym,
          :requires => normalize_requirements(requires),
          :block => block
        }
        @events[event].sort_by! { |entry| [entry[:priority], entry[:id].to_s] }
        Reloaded::Log.debug("Registered #{event}/#{handler_id} priority=#{priority_value}", :events) if defined?(Reloaded::Log)
        true
      end

      def emit(event_name, context = {})
        event = event_name.to_sym
        warn_unknown_event(event, :emit)
        ctx = normalize_context(event, context)
        validate_context(event, ctx)
        entries = Array(@events[event]).dup
        Reloaded::Log.debug("Emitting #{event} to #{entries.length} handler(s)", :events) if defined?(Reloaded::Log)
        called = 0
        entries.each do |entry|
          next unless handler_available?(entry)
          begin
            entry[:block].call(ctx)
            called += 1
          rescue Exception => e
            log_error(event, entry[:id], e)
          end
        end
        called
      end

      def first_result(event_name, context = {})
        event = event_name.to_sym
        warn_unknown_event(event, :decision)
        ctx = normalize_context(event, context)
        validate_context(event, ctx)
        entries = Array(@events[event]).dup
        entries.each do |entry|
          next unless handler_available?(entry)
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
        return @events.each_with_object({}) { |(event, entries), copy| copy[event] = entries.map(&:dup) } if event_name.nil?
        Array(@events[event_name.to_sym]).map(&:dup)
      end

      def disabled_handlers
        @disabled_handlers.keys.sort_by { |key| [key[0].to_s, key[1].to_s] }.map do |key|
          {
            :event => key[0],
            :id => key[1],
            :failures => @failures[key].to_i,
            :reason => @disabled_handlers[key]
          }
        end
      end

      def registered(event_name = nil)
        handlers(event_name)
      end

      def register(event_name, id = nil, priority_arg = nil, priority: 100, owner: nil, requires: nil, &block)
        on(event_name, id, priority_arg, :priority => priority, :owner => owner, :requires => requires, &block)
      end

      def contract(event_name)
        entry = @contracts[event_name.to_sym]
        entry ? copy_contract(entry) : nil
      rescue
        nil
      end

      def contracts
        @contracts.keys.sort_by(&:to_s).map { |event| contract(event) }
      end

      def validate
        findings = []
        @events.each do |event, entries|
          unless @contracts.key?(event)
            findings << { :severity => :warning, :code => :undocumented_event, :event => event, :message => "Event #{event} has handlers but no contract." }
          end
          duplicate_ids = entries.group_by { |entry| entry[:id] }.select { |_id, rows| rows.length > 1 }.keys
          duplicate_ids.each do |id|
            findings << { :severity => :error, :code => :duplicate_handler, :event => event, :message => "Event #{event} has duplicate handler #{id}." }
          end
        end
        disabled_handlers.each do |entry|
          findings << {
            :severity => :error,
            :code => :disabled_handler,
            :event => entry[:event],
            :message => "Event #{entry[:event]} handler #{entry[:id]} was disabled after #{entry[:failures]} failures."
          }
        end
        findings
      end

      def clear(event_name = nil)
        if event_name
          event = event_name.to_sym
          @events.delete(event)
          clear_event_failure_state(event)
        else
          @events.clear
          @failures.clear
          @disabled_handlers.clear
        end
      end

      def run(event_name, *args)
        context = args.length == 1 && args[0].is_a?(Hash) ? args[0] : { :args => args }
        emit(event_name, context)
      end

      private

      def copy_contract(entry)
        copy = entry.dup
        copy[:required_context] = entry[:required_context].dup
        copy[:optional_context] = entry[:optional_context].dup
        copy
      end

      def normalize_keys(values)
        Array(values).map { |value| value.to_sym }.uniq
      end

      def normalize_requirements(value)
        source = value.is_a?(Hash) ? value : {}
        {
          :systems => normalize_keys(source[:systems] || source["systems"]),
          :features => normalize_keys(source[:features] || source["features"])
        }
      end

      def current_owner
        mod_id = Thread.current[:reloaded_mod_id] rescue nil
        mod_id.to_s.empty? ? :reloaded : mod_id
      end

      def handler_available?(entry)
        event = entry[:event]
        return false if event && @disabled_handlers.key?([event, entry[:id]])
        requirements = entry[:requires] || {}
        systems_ok = Array(requirements[:systems]).all? do |id|
          defined?(Reloaded::Systems) && Reloaded::Systems.active?(id)
        end
        features_ok = Array(requirements[:features]).all? do |id|
          defined?(Reloaded::Features) && Reloaded::Features.active?(id)
        end
        systems_ok && features_ok
      rescue
        false
      end

      def validate_context(event, context)
        entry = @contracts[event]
        return true unless entry
        missing = entry[:required_context].reject { |key| context.key?(key) }
        return true if missing.empty?
        if defined?(Reloaded::Log)
          Reloaded::Log.warning_once(
            "Event #{event} context is missing: #{missing.join(', ')}",
            :events,
            key: "event_context_missing:#{event}:#{missing.sort.join(':')}"
          )
        end
        false
      end

      def warn_unknown_event(event, usage)
        return if @contracts.key?(event)
        Reloaded::Log.debug_once(
          "Undocumented event #{event} used for #{usage}.",
          :events,
          key: "undocumented_event:#{event}:#{usage}"
        ) if defined?(Reloaded::Log)
      end

      def normalize_context(event, context)
        ctx = context.is_a?(Hash) ? context.dup : { :value => context }
        ctx[:event] ||= event
        ctx
      end

      def log_error(event, id, error)
        key = [event, id]
        @failures[key] = @failures[key].to_i + 1
        if defined?(Reloaded::Log)
          Reloaded::Log.exception("Event #{event}/#{id} failed", error, channel: :events)
        elsif defined?(Reloaded::Bootstrap)
          Reloaded::Bootstrap.log(
            "Hook #{event}/#{id} failed: #{error.class}: #{error}",
            "ERROR"
          ) rescue nil
        end
        return unless @failures[key] >= FAILURE_LIMIT
        @disabled_handlers[key] = "Repeated handler failures"
        if defined?(Reloaded::Log)
          Reloaded::Log.error_once(
            "Disabled event handler #{event}/#{id} after #{@failures[key]} failures.",
            :events,
            key: "event_handler_disabled:#{event}:#{id}"
          )
        end
      end

      def clear_failure_state(event, id)
        key = [event.to_sym, id.to_sym]
        @failures.delete(key)
        @disabled_handlers.delete(key)
      end

      def clear_event_failure_state(event)
        @failures.keys.select { |key| key[0] == event }.each { |key| @failures.delete(key) }
        @disabled_handlers.keys.select { |key| key[0] == event }.each { |key| @disabled_handlers.delete(key) }
      end
    end
  end

  Hooks = Events unless const_defined?(:Hooks)
end

{
  :bootstrap_loaded => [:notification, []],
  :core_loaded => [:notification, []],
  :modules_loaded => [:notification, []],
  :game_data_loaded => [:notification, []],
  :data_patches_loaded => [:notification, []],
  :mods_loaded => [:notification, [:mods, :skipped]],
  :reloaded_shutdown => [:notification, []],
  :reloaded_save_loaded => [:notification, [:data]],
  :reloaded_save_saving => [:notification, [:data]],
  :reloaded_save_migration_started => [:notification, [:from, :to]],
  :reloaded_save_migrated => [:notification, [:from, :to, :migrations]],
  :reloaded_save_migration_failed => [:notification, [:error]],
  :item_receive_started => [:notification, [:method, :args]],
  :item_received => [:notification, [:method, :args, :received, :result]],
  :money_change_started => [:notification, [:method, :args]],
  :money_changed => [:notification, [:method, :args, :result]],
  :reward_grant_requested => [:decision, [:reward, :source, :context]],
  :reward_granted => [:notification, [:reward, :source, :context, :result]],
  :reward_grant_failed => [:notification, [:reward, :source, :context, :result]],
  :wild_battle_requested => [:notification, [:method, :args]],
  :wild_battle_finished => [:notification, [:method, :args, :player_won, :result]],
  :trainer_battle_requested => [:notification, [:method, :args]],
  :trainer_battle_finished => [:notification, [:method, :args, :player_won, :result]],
  :battle_started => [:notification, [:battle, :wild, :trainer]],
  :battle_ended => [:notification, [:battle, :decision, :wild, :trainer]],
  :map_setup_started => [:notification, [:map_id, :game_map]],
  :map_setup_finished => [:notification, [:map_id, :game_map]],
  :player_transfer_started => [:notification, [:new_map_id, :scene]],
  :player_transfer_finished => [:notification, [:new_map_id, :scene]],
  :tm_vault_move_registered => [:notification, [:move, :source]],
  :tm_vault_opened => [:notification, [:move_count]],
  :tm_vault_move_taught => [:notification, [:move, :pokemon]],
  :reloaded_mart_catalog_loaded => [:notification, []],
  :reloaded_mart_catalog_failed => [:notification, []],
  :reloaded_mart_purchase_validated => [:notification, []],
  :reloaded_mart_purchase_completed => [:notification, []],
  :reloaded_mart_purchase_failed => [:notification, []],
  :reloaded_mart_sale_completed => [:notification, []],
  :reloaded_mart_sale_failed => [:notification, []],
  :reloaded_mart_stock_changed => [:notification, []]
}.each do |event_name, definition|
  Reloaded::Events.define(event_name, :mode => definition[0], :required_context => definition[1])
end
