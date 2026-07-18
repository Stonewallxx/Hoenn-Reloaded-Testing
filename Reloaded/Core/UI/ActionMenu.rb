#======================================================
# Reloaded Action Menu API
#======================================================
# Defines state-aware commands while delegating all drawing and modal input
# handling to Reloaded::PopupWindow.
#======================================================

module Reloaded
  module API
    module ActionMenu
      BACK_ID = :back
      INTERNAL_OPTIONS = [
        :start_id, :remember_key, :back_label, :list_state,
        :on_back, :refresh_after_action, :close_on_error
      ].freeze

      class << self
        def open(title, commands, context = nil, options = {})
          run(title, commands, context, options, true)
        end

        def choose(title, commands, context = nil, options = {})
          run(title, commands, context, options, false)
        end

        def clear_remembered(key = nil)
          if key.nil?
            @remembered = {}
          else
            remembered.delete(key)
          end
          true
        rescue
          false
        end

        private

        def run(title, commands, context, options, execute)
          context = {} if context.nil?
          options = copy_hash(options)
          selected_id = starting_id(options)
          loop do
            prepared = prepare_commands(commands, context)
            return handle_back(context, options) if prepared.empty?
            selected_id = prepared.first[:id] unless prepared.any? { |command| command[:id] == selected_id }
            rows = popup_rows(prepared, options)
            start_index = rows.index { |row| row[:value] == selected_id } || 0
            result = Reloaded::PopupWindow.choice(
              evaluate(title, context, nil).to_s,
              rows,
              popup_options(options).merge(:add_back => false, :start_index => start_index)
            )
            return handle_back(context, options) if back_result?(result)
            command = prepared.find { |entry| entry[:id] == result }
            next unless command
            selected_id = command[:id]
            remember(options[:remember_key], selected_id)
            return selected_id unless execute
            next unless confirm_command?(command, context)
            callback_ok = execute_command(command, context)
            next unless callback_ok || options[:close_on_error]
            keep_open = command[:close_on_run] == false || options[:refresh_after_action] == true
            return selected_id unless keep_open
          end
        ensure
          release_parent_list(options)
        end

        def prepare_commands(commands, context)
          rows = []
          ids = {}
          Array(commands).each_with_index do |source, index|
            command = normalize_command(source, index)
            next unless truthy?(command[:visible], context, command, true)
            id = command[:id]
            if id == BACK_ID
              log_warning("ActionMenu ignored command using reserved ID :back")
              next
            end
            if ids[id]
              log_warning("ActionMenu ignored duplicate command ID #{id.inspect}")
              next
            end
            ids[id] = true
            command[:label] = evaluate(command[:label], context, command).to_s
            next if command[:label].empty?
            command[:enabled_now] = truthy?(command[:enabled], context, command, true)
            command[:disabled_reason_now] = evaluate(command[:disabled_reason], context, command).to_s
            command[:disabled_reason_now] = _INTL("This action is unavailable.") if command[:disabled_reason_now].empty?
            rows << command
          end
          rows
        rescue Exception => e
          log_exception("ActionMenu command preparation failed", e)
          []
        end

        def normalize_command(source, index)
          unless source.is_a?(Hash)
            return {
              :id => index,
              :label => source.to_s,
              :visible => true,
              :enabled => true,
              :disabled_reason => nil,
              :callback => nil,
              :confirm => nil,
              :close_on_run => true
            }
          end
          id = fetch(source, :id)
          id = index if id.nil?
          {
            :id => id,
            :label => fetch(source, :label) || fetch(source, :text) || fetch(source, :name) || id.to_s,
            :visible => source.key?(:visible) || source.key?("visible") ? fetch(source, :visible) : true,
            :enabled => source.key?(:enabled) || source.key?("enabled") ? fetch(source, :enabled) : true,
            :disabled_reason => fetch(source, :disabled_reason) || fetch(source, :reason),
            :callback => fetch(source, :callback) || fetch(source, :proc) || fetch(source, :action),
            :confirm => fetch(source, :confirm),
            :close_on_run => source.key?(:close_on_run) || source.key?("close_on_run") ? fetch(source, :close_on_run) : true,
            :color => fetch(source, :color),
            :align => fetch(source, :align),
            :source => source
          }
        end

        def popup_rows(commands, options)
          rows = commands.map do |command|
            {
              :label => command[:label],
              :value => command[:id],
              :disabled => !command[:enabled_now],
              :disabled_reason => command[:disabled_reason_now],
              :selectable => true,
              :color => command[:color],
              :align => command[:align]
            }
          end
          if options.key?(:add_back) ? options[:add_back] : true
            rows << {
              :label => (options[:back_label] || _INTL("Back")).to_s,
              :value => BACK_ID,
              :back => true,
              :selectable => true
            }
          end
          rows
        end

        def popup_options(options)
          result = copy_hash(options)
          INTERNAL_OPTIONS.each { |key| result.delete(key) }
          result.delete(:add_back)
          result
        end

        def confirm_command?(command, context)
          confirmation = evaluate(command[:confirm], context, command)
          return true if confirmation.nil? || confirmation == false || confirmation.to_s.empty?
          text = confirmation == true ? _INTL("Are you sure?") : confirmation.to_s
          Reloaded.confirm(text, :default => true)
        rescue
          false
        end

        def execute_command(command, context)
          callback = command[:callback]
          return true unless callback.respond_to?(:call)
          call_value(callback, context, command)
          true
        rescue Exception => e
          log_exception("ActionMenu command #{command[:id].inspect} failed", e)
          if Reloaded.respond_to?(:toast_error)
            Reloaded.toast_error(_INTL("That action failed."))
          elsif Reloaded.respond_to?(:message)
            Reloaded.message(_INTL("That action failed."), :theme => :error)
          end
          false
        end

        def handle_back(context, options)
          callback = options[:on_back]
          call_value(callback, context, nil) if callback.respond_to?(:call)
          BACK_ID
        rescue Exception => e
          log_exception("ActionMenu Back callback failed", e)
          BACK_ID
        end

        def starting_id(options)
          return options[:start_id] if options.key?(:start_id)
          key = options[:remember_key]
          key.nil? ? nil : remembered[key]
        rescue
          nil
        end

        def remember(key, id)
          remembered[key] = id unless key.nil?
        rescue
        end

        def remembered
          @remembered ||= {}
        end

        def release_parent_list(options)
          state = options[:list_state] rescue nil
          state.dialog_closed! if state && state.respond_to?(:dialog_closed!)
        rescue
        end

        def back_result?(value)
          value == BACK_ID || value == -1 || value.nil?
        end

        def truthy?(value, context, command, default)
          return default if value.nil?
          result = evaluate(value, context, command)
          !!result
        end

        def evaluate(value, context, command)
          value.respond_to?(:call) ? call_value(value, context, command) : value
        end

        def call_value(callable, context, command)
          arity = callable.arity rescue 0
          return callable.call if arity == 0
          return callable.call(context) if arity == 1
          callable.call(context, command)
        end

        def fetch(hash, key)
          hash.key?(key) ? hash[key] : hash[key.to_s]
        rescue
          nil
        end

        def copy_hash(hash)
          result = {}
          (hash || {}).each { |key, value| result[key] = value }
          result
        rescue
          {}
        end

        def log_warning(message)
          Reloaded::Log.warning(message, :api) if defined?(Reloaded::Log)
        rescue
        end

        def log_exception(message, error)
          if defined?(Reloaded::Log)
            Reloaded::Log.error("#{message}: #{error.class}: #{error}", :api)
            Reloaded::Log.debug(Array(error.backtrace).first(6).join("\n"), :api) rescue nil
          end
        rescue
        end
      end
    end
  end

  ActionMenu = API::ActionMenu unless const_defined?(:ActionMenu, false)

  class << self
    def action_menu(title, commands, context = nil, options = {})
      ActionMenu.open(title, commands, context, options)
    end

    def choose_action(title, commands, context = nil, options = {})
      ActionMenu.choose(title, commands, context, options)
    end
  end
end
