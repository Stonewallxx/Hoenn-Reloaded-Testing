#======================================================
# Reloaded List State
# Author: Stonewall
#======================================================
# Shared selection, scrolling, cursor memory, and input handling for custom
# Reloaded list scenes. Rendering and scene actions remain caller-owned.
#======================================================

module Reloaded
  module API
    module ListState
      DEFAULT_JUMP_SIZE = 3
      HORIZONTAL_MODES = [:jump, :external, :disabled].freeze
      PRESERVE_MODES = [:id, :index, :first, :remembered].freeze
      NO_ROWS = Object.new

      class Event
        attr_reader :type, :index, :previous_index, :row, :row_id,
                    :source, :reason, :direction

        def initialize(values = {})
          @type = (values[:type] || :none).to_sym
          @index = values[:index]
          @previous_index = values[:previous_index]
          @row = values[:row]
          @row_id = values[:row_id]
          @source = (values[:source] || :none).to_sym
          @reason = values[:reason].to_s
          @direction = values[:direction]
        end

        def none?; @type == :none; end
        def moved?; @type == :moved; end
        def activate?; @type == :activate; end
        def disabled?; @type == :disabled; end
        def back?; @type == :back; end
        def external?; @type == :left || @type == :right; end
        def changed?; moved?; end
      end

      class << self
        def new(options = {})
          State.new(options)
        end

        def remember(key, snapshot)
          return false if key.nil? || !snapshot.is_a?(Hash)
          memory[memory_key(key)] = copy_snapshot(snapshot)
          true
        rescue
          false
        end

        def recall(key)
          return nil if key.nil?
          value = memory[memory_key(key)]
          value ? copy_snapshot(value) : nil
        rescue
          nil
        end

        def forget(key)
          return false if key.nil?
          !memory.delete(memory_key(key)).nil?
        rescue
          false
        end

        def clear_memory(owner = nil)
          if owner.nil?
            memory.clear
          else
            prefix = memory_key(owner)
            memory.delete_if { |key, _value| key == prefix || key.start_with?("#{prefix}|") }
          end
          true
        rescue
          false
        end

        def memory_snapshot
          result = {}
          memory.each { |key, value| result[key] = copy_snapshot(value) }
          result
        rescue
          {}
        end

        private

        def memory
          @memory ||= {}
        end

        def memory_key(value)
          if value.is_a?(Array)
            value.map { |part| memory_key(part) }.join("|")
          elsif value.is_a?(Hash)
            value.keys.sort_by { |key| key.to_s }.map { |key| "#{memory_key(key)}=#{memory_key(value[key])}" }.join("|")
          else
            "#{value.class}:#{value}"
          end
        end

        def copy_snapshot(value)
          {
            :row_id => value[:row_id],
            :index => value[:index].nil? ? nil : value[:index].to_i,
            :scroll => value[:scroll].to_i
          }
        end
      end

      class State
        attr_reader :index, :scroll, :rows, :last_input_source

        def initialize(options = {})
          @options = normalize_options(options)
          @rows = resolve_rows(@options[:rows])
          @index = nil
          @scroll = [@options[:scroll].to_i, 0].max
          @last_input_source = :none
          @input_blocked = false
          @blocked_frame = -1
          restore_initial_selection
          ensure_visible!
          remember! if @options[:remember]
        end

        def selected_index; @index; end
        def selected_row; valid_index?(@index) ? @rows[@index] : nil; end
        alias row selected_row

        def selected_id
          value = selected_row
          value.nil? ? nil : row_id(value, @index)
        end

        def empty?
          focusable_indices.empty?
        end

        def length; @rows.length; end
        alias size length

        def visible_rows
          value = resolve_option(@options[:visible_rows])
          [value.to_i, 1].max
        rescue
          1
        end

        def visible_rows=(value)
          @options[:visible_rows] = value
          ensure_visible!
        end

        def visible_range
          @scroll...[[@scroll + visible_rows, @rows.length].min, @scroll].max
        end

        def jump_size
          [@options[:jump_size].to_i, 1].max
        end

        def horizontal_mode
          @options[:horizontal]
        end

        def replace_rows(value = NO_ROWS, options = {})
          preserve = normalize_preserve(options[:preserve] || :id)
          old_id = selected_id
          old_index = @index
          @rows = resolve_rows(value.equal?(NO_ROWS) ? @options[:rows] : value)
          @options[:rows] = value unless value.equal?(NO_ROWS)
          target = case preserve
                   when :id then index_for_id(old_id)
                   when :index then nearest_focusable_index(old_index)
                   when :remembered then remembered_index
                   else first_focusable_index
                   end
          target = nearest_focusable_index(old_index) if target.nil? && preserve == :id
          target = first_focusable_index if target.nil?
          @index = target
          ensure_visible!
          remember! if @options[:remember]
          self
        end
        alias refresh replace_rows

        def select_index(value, source = :programmatic)
          target = nearest_focusable_index(value)
          return none_event(source) if target.nil?
          apply_selection(target, source)
        end

        def select_id(value, source = :programmatic)
          target = index_for_id(value)
          return none_event(source) if target.nil?
          apply_selection(target, source)
        end

        def move(amount, source = :command, wrap = @options[:wrap])
          indices = focusable_indices
          return none_event(source) if indices.empty?
          previous = @index
          current_position = indices.index(@index) || 0
          target_position = current_position + amount.to_i
          if wrap
            target_position %= indices.length
          else
            target_position = [[target_position, 0].max, indices.length - 1].min
          end
          apply_selection(indices[target_position], source, previous)
        end

        def move_up(source = :command); move(-1, source); end
        def move_down(source = :command); move(1, source); end
        def jump_up(source = :command); move(-jump_size, source, @options[:jump_wrap]); end
        def jump_down(source = :command); move(jump_size, source, @options[:jump_wrap]); end

        def activate(source = :command, index = @index)
          return none_event(source) unless valid_index?(index)
          index = index.to_i
          value = @rows[index]
          return none_event(source) if header?(value, index)
          if disabled?(value, index)
            return event(:disabled, source, @index, index, value, disabled_reason(value, index))
          end
          return none_event(source) unless selectable?(value, index)
          event(:activate, source, @index, index, value)
        end

        def back(source = :command)
          event(:back, source, @index, @index, selected_row)
        end

        def update_input(options = {})
          return blocked_event if @input_blocked
          if option_enabled?(options, :mouse, true)
            mouse_event = update_mouse(options)
            return mouse_event unless mouse_event.none?
          end
          return none_event unless option_enabled?(options, :commands, true)

          return move_up(:command) if input_repeat?(:UP)
          return move_down(:command) if input_repeat?(:DOWN)
          if input_repeat?(:LEFT)
            return horizontal_event(:left)
          elsif input_repeat?(:RIGHT)
            return horizontal_event(:right)
          end
          return activate(:command) if option_enabled?(options, :accept, true) && input_trigger?(:USE)
          return back(:command) if option_enabled?(options, :back, true) && input_trigger?(:BACK)
          none_event
        rescue Exception => e
          log_exception("ListState input failed", e)
          none_event
        end

        def dialog_closed!
          @input_blocked = true
          @blocked_frame = current_frame
          self
        end

        def with_dialog
          yield
        ensure
          dialog_closed!
        end

        def input_blocked?; !!@input_blocked; end

        def remember!
          return false unless @options[:memory_key]
          ListState.remember(@options[:memory_key], snapshot)
        end

        def restore!
          target = remembered_index
          return false if target.nil?
          @index = target
          memory = ListState.recall(@options[:memory_key])
          @scroll = memory[:scroll].to_i if memory
          ensure_visible!
          true
        end

        def forget!
          ListState.forget(@options[:memory_key])
        end

        def snapshot
          { :row_id => selected_id, :index => @index, :scroll => @scroll }
        end

        def ensure_visible!
          if @index.nil?
            @scroll = 0
            return self
          end
          @scroll = @index if @index < @scroll
          @scroll = @index - visible_rows + 1 if @index >= @scroll + visible_rows
          @scroll = [[@scroll, 0].max, max_scroll].min
          self
        end

        def focusable?(value, index = nil)
          return false if value.nil? || header?(value, index)
          custom = callback_value(@options[:selectable], value, index)
          return false if custom == false
          return false if disabled?(value, index) && !@options[:focus_disabled]
          true
        rescue
          false
        end

        def selectable?(value, index = nil)
          focusable?(value, index) && !disabled?(value, index)
        end

        def disabled?(value, index = nil)
          custom = callback_value(@options[:disabled], value, index)
          return !!custom unless custom.nil?
          !!hash_value(value, :disabled)
        rescue
          false
        end

        def header?(value, index = nil)
          custom = callback_value(@options[:header], value, index)
          return !!custom unless custom.nil?
          !!(hash_value(value, :header) || hash_value(value, :section))
        rescue
          false
        end

        def disabled_reason(value, index = nil)
          custom = callback_value(@options[:disabled_reason], value, index)
          custom = hash_value(value, :disabled_reason) if custom.nil?
          custom.to_s
        rescue
          ""
        end

        private

        def normalize_options(options)
          source = options.is_a?(Hash) ? options.dup : {}
          horizontal = (source[:horizontal] || :jump).to_sym rescue :jump
          horizontal = :jump unless HORIZONTAL_MODES.include?(horizontal)
          {
            :rows => source[:rows] || [],
            :visible_rows => source[:visible_rows] || 1,
            :row_id => source[:row_id],
            :header => source[:header],
            :disabled => source[:disabled],
            :disabled_reason => source[:disabled_reason],
            :selectable => source[:selectable],
            :focus_disabled => source.key?(:focus_disabled) ? !!source[:focus_disabled] : true,
            :wrap => source.key?(:wrap) ? !!source[:wrap] : true,
            :jump_wrap => source.key?(:jump_wrap) ? !!source[:jump_wrap] : (source.key?(:wrap) ? !!source[:wrap] : true),
            :jump_size => [source.fetch(:jump_size, DEFAULT_JUMP_SIZE).to_i, 1].max,
            :horizontal => horizontal,
            :remember => !!source[:remember],
            :memory_key => source[:memory_key] || source[:key],
            :initial_index => source[:initial_index],
            :initial_id => source[:initial_id],
            :scroll => source[:scroll] || 0,
            :wheel => (source[:wheel] || :selection).to_sym
          }
        end

        def restore_initial_selection
          target = index_for_id(@options[:initial_id]) unless @options[:initial_id].nil?
          target ||= remembered_index if @options[:remember]
          target ||= nearest_focusable_index(@options[:initial_index]) unless @options[:initial_index].nil?
          target ||= first_focusable_index
          @index = target
        end

        def remembered_index
          memory = ListState.recall(@options[:memory_key])
          return nil unless memory
          target = index_for_id(memory[:row_id]) unless memory[:row_id].nil?
          target ||= nearest_focusable_index(memory[:index])
          target
        end

        def update_mouse(options)
          return none_event unless defined?(Reloaded::MouseInput)
          position = Reloaded::MouseInput.active_position rescue nil
          return none_event unless position.is_a?(Array)
          resolver = options[:mouse_index]
          return none_event unless resolver.respond_to?(:call)
          target = resolver.call(position[0], position[1])
          wheel = mouse_wheel_delta
          if wheel != 0 && @options[:wheel] == :selection
            return none_event(:mouse) unless valid_index?(target)
            return wheel > 0 ? move_up(:mouse) : move_down(:mouse)
          end
          return none_event unless valid_index?(target)
          value = @rows[target]
          clicked = input_trigger?(:MOUSELEFT)
          if focusable?(value, target)
            moved = apply_selection(target, :mouse)
            return activate(:mouse, target) if clicked && option_enabled?(options, :mouse_activate, true)
            return moved
          end
          if clicked && option_enabled?(options, :mouse_activate, true) && disabled?(value, target)
            return activate(:mouse, target)
          end
          none_event(:mouse)
        rescue Exception => e
          log_exception("ListState mouse input failed", e)
          none_event(:mouse)
        end

        def horizontal_event(direction)
          case @options[:horizontal]
          when :jump
            direction == :left ? jump_up(:command) : jump_down(:command)
          when :external
            event(direction, :command, @index, @index, selected_row, "", direction)
          else
            none_event(:command)
          end
        end

        def blocked_event
          return none_event(:blocked) if current_frame <= @blocked_frame
          return none_event(:blocked) unless input_neutral?
          @input_blocked = false
          none_event(:blocked)
        end

        def input_neutral?
          names = [:USE, :BACK, :ACTION, :SPECIAL, :UP, :DOWN, :LEFT, :RIGHT, :MOUSELEFT, :MOUSERIGHT]
          names.none? do |name|
            next false unless defined?(Input) && Input.const_defined?(name)
            Input.press?(Input.const_get(name)) rescue false
          end
        rescue
          true
        end

        def mouse_wheel_delta
          value = Input.scroll_v.to_i rescue 0
          return 1 if value > 0
          return -1 if value < 0
          return 1 if input_repeat?(:SCROLLUP)
          return -1 if input_repeat?(:SCROLLDOWN)
          0
        rescue
          0
        end

        def apply_selection(target, source, previous = @index)
          return none_event(source) if target.nil? || target == previous
          @index = target
          @last_input_source = source.to_sym rescue :programmatic
          ensure_visible!
          remember! if @options[:remember]
          event(:moved, source, previous, @index, selected_row)
        end

        def event(type, source, previous, current, value, reason = "", direction = nil)
          Event.new(
            :type => type,
            :index => current,
            :previous_index => previous,
            :row => value,
            :row_id => value.nil? ? nil : row_id(value, current),
            :source => source,
            :reason => reason,
            :direction => direction
          )
        end

        def none_event(source = :none)
          event(:none, source, @index, @index, selected_row)
        end

        def row_id(value, index)
          custom = callback_value(@options[:row_id], value, index)
          return custom unless custom.nil?
          hash_value(value, :id) || hash_value(value, :value) || value
        rescue
          value
        end

        def index_for_id(value)
          return nil if value.nil?
          @rows.each_index.find { |index| focusable?(@rows[index], index) && row_id(@rows[index], index) == value }
        end

        def nearest_focusable_index(value)
          indices = focusable_indices
          return nil if indices.empty?
          target = value.nil? ? indices.first : value.to_i
          indices.min_by { |index| [(index - target).abs, index] }
        end

        def first_focusable_index
          focusable_indices.first
        end

        def focusable_indices
          @rows.each_index.select { |index| focusable?(@rows[index], index) }
        end

        def valid_index?(value)
          value.is_a?(Integer) && value >= 0 && value < @rows.length
        rescue
          false
        end

        def max_scroll
          [@rows.length - visible_rows, 0].max
        end

        def resolve_rows(value)
          resolved = value.respond_to?(:call) ? value.call : value
          Array(resolved).compact
        rescue Exception => e
          log_exception("ListState row provider failed", e)
          []
        end

        def resolve_option(value)
          value.respond_to?(:call) ? value.call : value
        end

        def callback_value(callback, value, index)
          return nil unless callback.respond_to?(:call)
          callback.arity == 1 ? callback.call(value) : callback.call(value, index)
        end

        def hash_value(value, key)
          return nil unless value.is_a?(Hash)
          value.key?(key) ? value[key] : value[key.to_s]
        end

        def normalize_preserve(value)
          mode = value.to_sym rescue :id
          PRESERVE_MODES.include?(mode) ? mode : :id
        end

        def option_enabled?(options, key, default)
          options.key?(key) ? !!options[key] : default
        end

        def input_repeat?(name)
          return false unless defined?(Input) && Input.const_defined?(name)
          Input.repeat?(Input.const_get(name)) rescue false
        end

        def input_trigger?(name)
          return false unless defined?(Input) && Input.const_defined?(name)
          Input.trigger?(Input.const_get(name)) rescue false
        end

        def current_frame
          Graphics.frame_count.to_i rescue 0
        end

        def log_exception(message, error)
          if defined?(Reloaded::Log)
            Reloaded::Log.exception(message, error, :channel => :framework)
          elsif defined?(Reloaded::PopupWindow)
            Reloaded::PopupWindow.log_exception(message, error)
          end
        rescue
        end
      end
    end
  end

  ListState = API::ListState unless const_defined?(:ListState, false)
end
