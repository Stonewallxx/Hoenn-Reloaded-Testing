#======================================================
# Reloaded Form API
# Author: Stonewall
#======================================================
# Shared full-screen field editor for Reloaded systems, Admin Tools, and mods.
# Values are edited in an isolated draft and committed only after validation.
#======================================================

module Reloaded
  module API
    module Form
      SCREEN_W = 512
      SCREEN_H = 384
      TITLE_H = 30
      FOOTER_H = 27
      CONTENT_Y = TITLE_H
      CONTENT_H = SCREEN_H - TITLE_H - FOOTER_H
      GAP = 6
      LEFT_X = 5
      LEFT_W = 250
      RIGHT_X = LEFT_X + LEFT_W + GAP
      RIGHT_W = SCREEN_W - RIGHT_X - 5
      ROW_H = 28
      LIST_PAD = 7
      SCROLLBAR_W = 5

      SUPPORTED_TYPES = [
        :text, :multiline, :number, :toggle, :enum, :list,
        :game_data, :custom, :readonly, :header
      ].freeze

      class << self
        def open(title, fields, values = {}, options = {})
          PopupWindow.with_modal do
            Scene.new(title, fields, values, normalize_options(options)).main
          end
        rescue Exception => e
          log_exception("Form failed", e)
          warning(_INTL("That editor could not be opened."))
          nil
        end

        alias edit open

        def normalize_options(options)
          result = {}
          (options || {}).each do |key, value|
            normalized = key.to_sym rescue key
            result[normalized] = value
          end
          result[:theme] = (result[:theme] || :hr).to_sym rescue :hr
          result[:theme] = :hr unless PopupWindow::THEMES[result[:theme]]
          result[:controls] = true unless result.key?(:controls)
          result[:confirm_save] = !!result[:confirm_save]
          result[:save_label] = (result[:save_label] || _INTL("Save")).to_s
          result[:back_label] = (result[:back_label] || _INTL("Back")).to_s
          result[:unsaved_label] = (result[:unsaved_label] || _INTL("Unsaved")).to_s
          result[:saved_label] = (result[:saved_label] || _INTL("Saved")).to_s
          result[:z] = (result[:z] || 999_999_998).to_i
          result
        end

        def normalize_fields(fields)
          Array(fields).each_with_index.map do |source, index|
            normalize_field(source, index)
          end.compact
        end

        def normalize_field(source, index)
          return nil unless source.is_a?(Hash)
          field = {}
          source.each do |key, value|
            normalized = key.to_sym rescue key
            field[normalized] = value
          end
          id = field[:id] || field[:key] || "field_#{index}"
          type = (field[:type] || (field[:header] ? :header : :text)).to_sym rescue :text
          type = :text unless SUPPORTED_TYPES.include?(type)
          field[:id] = id
          field[:key] = field.key?(:key) ? field[:key] : id
          field[:type] = type
          field[:label] = (field[:label] || humanize(id)).to_s
          field[:description] = field[:description].to_s
          field[:required] = !!field[:required]
          field[:multiple] = !!(field[:multiple] || field[:multi_select])
          field[:enabled] = true unless field.key?(:enabled)
          field[:visible] = true unless field.key?(:visible)
          field
        rescue Exception => e
          log_exception("Form field #{index} could not be normalized", e)
          nil
        end

        def humanize(value)
          value.to_s.gsub(/[_-]+/, " ").split.map { |part| part.capitalize }.join(" ")
        end

        def deep_copy(value)
          case value
          when Hash
            copy = {}
            value.each { |key, item| copy[key] = deep_copy(item) }
            copy
          when Array
            value.map { |item| deep_copy(item) }
          when String
            value.dup
          else
            value
          end
        rescue
          value
        end

        def warning(text)
          if Reloaded.respond_to?(:toast_warning)
            Reloaded.toast_warning(text.to_s)
          elsif Reloaded.respond_to?(:message)
            Reloaded.message(text.to_s, :theme => :warning)
          end
        rescue
        end

        def error(text)
          if Reloaded.respond_to?(:toast_error)
            Reloaded.toast_error(text.to_s)
          elsif Reloaded.respond_to?(:message)
            Reloaded.message(text.to_s, :theme => :error)
          end
        rescue
        end

        def log_exception(message, error)
          if defined?(Reloaded::Log)
            Reloaded::Log.exception(message, error, :channel => :api)
          elsif defined?(Reloaded::PopupWindow)
            Reloaded::PopupWindow.log_exception(message, error)
          end
        rescue
        end
      end

      class Scene
        def initialize(title, fields, values, options)
          @title = title.to_s
          @all_fields = Form.normalize_fields(fields)
          @options = options
          @theme = PopupWindow::THEMES[@options[:theme]] || PopupWindow::THEMES[:hr]
          @original = Form.deep_copy(values.is_a?(Hash) ? values : {})
          @draft = Form.deep_copy(@original)
          apply_defaults
          @original = Form.deep_copy(@draft)
          @fields = []
          @list_state = nil
          @selected = 0
          @scroll = 0
          @errors = {}
          @warnings = {}
          @result = nil
          @running = false
          @sprites = {}
        end

        def main
          setup
          @running = true
          while @running
            Graphics.update
            Input.update
            update
            draw if pulse_redraw?
          end
          @result
        ensure
          dispose
          drain_input
        end

        def setup
          @viewport = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
          @viewport.z = @options[:z]
          @sprites["background"] = Sprite.new(@viewport)
          @sprites["background"].bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
          @sprites["form"] = Sprite.new(@viewport)
          @sprites["form"].bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
          @sprites["form"].z = 1
          rebuild_fields(:first)
          draw
        end

        def dispose
          @sprites.each_value do |sprite|
            sprite.bitmap.dispose rescue nil
            sprite.dispose rescue nil
          end
          @viewport.dispose rescue nil
        end

        def apply_defaults
          @all_fields.each do |field|
            next if field[:type] == :header
            next if has_field_value?(field)
            write_value(field, Form.deep_copy(field[:default])) if field.key?(:default)
          end
        end

        def rebuild_fields(preserve = :id)
          old_id = selected_field ? selected_field[:id] : nil
          @fields = @all_fields.select { |field| visible?(field) }
          visible_rows = [(CONTENT_H - LIST_PAD * 2) / ROW_H, 1].max
          if @list_state
            @list_state.visible_rows = visible_rows
            @list_state.replace_rows(@fields, :preserve => preserve)
            @list_state.select_id(old_id) if preserve == :id && !old_id.nil?
          else
            @list_state = Reloaded::ListState.new(
              :rows => @fields,
              :visible_rows => visible_rows,
              :row_id => proc { |field, _index| field[:id] },
              :header => proc { |field, _index| field[:type] == :header },
              :disabled => proc { |field, _index| !enabled?(field) },
              :disabled_reason => proc { |field, _index| disabled_reason(field) },
              :focus_disabled => true,
              :wrap => true,
              :jump_wrap => true,
              :jump_size => 3,
              :horizontal => :jump,
              :remember => !!@options[:remember],
              :memory_key => @options[:memory_key],
              :initial_index => @options[:initial_index]
            )
          end
          sync_state
        end

        def update
          if controls_triggered?
            show_controls
            return
          end
          if save_triggered?
            attempt_save
            return
          end
          if mouse_right_triggered?
            request_back
            return
          end
          mouse_result = update_mouse
          return if mouse_result == :handled
          event = @list_state.update_input(:mouse => false)
          handle_event(event)
        end

        def handle_event(event)
          return unless event
          old_selected = @selected
          sync_state
          case event.type
          when :activate
            edit_field(event.row || selected_field)
          when :disabled
            show_disabled(event.row || selected_field)
          when :back
            request_back
          end
          if old_selected != @selected
            pbPlayCursorSE rescue nil
            draw
          end
        end

        def update_mouse
          position = Reloaded::MouseInput.active_position rescue nil
          return :continue unless position.is_a?(Array)
          mx = position[0].to_i
          my = position[1].to_i
          if controls_clicked?(mx, my)
            show_controls
            return :handled
          end
          event = @list_state.update_input(
            :commands => false,
            :mouse_index => proc { |x, y| mouse_field_index(x, y) }
          )
          return :continue if event.nil? || event.none?
          handle_event(event)
          :handled
        rescue Exception => e
          Form.log_exception("Form mouse input failed", e)
          :continue
        end

        def mouse_field_index(x, y)
          return nil if x < LEFT_X || x >= LEFT_X + LEFT_W
          return nil if y < CONTENT_Y + LIST_PAD || y >= CONTENT_Y + CONTENT_H - LIST_PAD
          index = @scroll + ((y - CONTENT_Y - LIST_PAD) / ROW_H)
          index >= 0 && index < @fields.length ? index : nil
        end

        def edit_field(field)
          return unless field
          return show_disabled(field) unless enabled?(field)
          old_value = Form.deep_copy(value_for(field))
          new_value = @list_state.with_dialog { field_editor_value(field, old_value) }
          return if new_value.equal?(CancelValue)
          return if values_equal?(old_value, new_value)
          write_value(field, Form.deep_copy(new_value))
          run_on_change(field, old_value, new_value)
          validate_field(field)
          rebuild_fields(:id)
          pbPlayDecisionSE rescue nil
          draw
        rescue Exception => e
          Form.log_exception("Form field #{field && field[:id]} failed", e)
          Form.error(_INTL("That field could not be edited."))
          @list_state.dialog_closed! if @list_state
          draw
        end

        CancelValue = Object.new

        def field_editor_value(field, current)
          case field[:type]
          when :text
            text_value(field, current, false)
          when :multiline
            text_value(field, current, true)
          when :number
            number_value(field, current)
          when :toggle
            !truthy?(current)
          when :enum
            enum_value(field, current)
          when :list
            list_value(field, current)
          when :game_data
            game_data_value(field, current)
          when :custom
            custom_value(field, current)
          else
            CancelValue
          end
        end

        def text_value(field, current, multiline)
          return CancelValue unless defined?(Reloaded::TextInput)
          options = copy_options(field[:input_options])
          options[:initial] = current.to_s
          options[:description] = field[:description] unless field[:description].empty?
          value = multiline ? Reloaded::TextInput.multiline(field[:label], options) : Reloaded::TextInput.open(field[:label], options)
          value.nil? ? CancelValue : normalize_value(field, value)
        end

        def number_value(field, current)
          if field[:allow_nil] && defined?(Reloaded::ActionMenu)
            action = Reloaded::ActionMenu.choose(
              field[:label],
              [
                { :id => :number, :label => _INTL("Set Number") },
                { :id => :clear, :label => _INTL("Clear Value") }
              ],
              nil,
              :start_id => current.nil? ? :clear : :number
            )
            return CancelValue if action == :back
            return nil if action == :clear
          end
          if field[:decimal]
            return decimal_value(field, current)
          end
          return CancelValue unless defined?(Reloaded::NumberPicker)
          options = copy_options(field[:picker_options])
          options[:initial] = current.nil? ? (field[:min] || 0) : current.to_i
          options[:min] = field[:min] if field.key?(:min)
          options[:max] = field[:max] if field.key?(:max)
          options[:step] = field[:step] if field.key?(:step)
          options[:large_step] = field[:large_step] if field.key?(:large_step)
          value = Reloaded::NumberPicker.open(field[:label], options)
          value.nil? ? CancelValue : normalize_value(field, value)
        end

        def decimal_value(field, current)
          return CancelValue unless defined?(Reloaded::TextInput)
          value = Reloaded::TextInput.open(field[:label], :initial => current.to_s)
          return CancelValue if value.nil?
          text = value.to_s.strip
          return nil if text.empty? && field[:allow_nil]
          unless text =~ /\A-?\d+(\.\d+)?\z/
            Form.warning(_INTL("{1} needs a valid number.", field[:label]))
            return CancelValue
          end
          normalize_value(field, text.to_f)
        end

        def enum_value(field, current)
          return CancelValue unless defined?(Reloaded::ListPicker)
          rows = choice_rows(field)
          result = Reloaded::ListPicker.popup(
            field[:label], rows,
            :start_value => current,
            :details => rows.any? { |row| !row[:detail].to_s.empty? },
            :add_back => true,
            :controls => true,
            :memory_key => field[:memory_key]
          )
          result.nil? ? CancelValue : normalize_value(field, result)
        end

        def list_value(field, current)
          choices = choice_rows(field)
          if !choices.empty? && defined?(Reloaded::ListPicker)
            result = Reloaded::ListPicker.fullscreen(
              field[:label], choices,
              :multi_select => true,
              :start_values => Array(current),
              :search => field.key?(:search) ? !!field[:search] : choices.length > 12,
              :details => choices.any? { |row| !row[:detail].to_s.empty? },
              :add_back => true,
              :controls => true,
              :memory_key => field[:memory_key]
            )
            return result.nil? ? CancelValue : normalize_value(field, result)
          end
          return CancelValue unless defined?(Reloaded::TextInput)
          value = Reloaded::TextInput.multiline(
            field[:label],
            :initial => Array(current).map(&:to_s).join(", "),
            :description => field[:description]
          )
          return CancelValue if value.nil?
          normalize_value(field, value.to_s.split(/[,\n]/).map { |part| part.strip }.reject(&:empty?))
        end

        def game_data_value(field, current)
          return CancelValue unless defined?(Reloaded::GameDataPicker)
          kind = field[:game_data] || field[:kind] || :item
          options = copy_options(field[:picker_options])
          options[:layout] = :fullscreen
          options[:search] = true unless options.key?(:search)
          options[:details] = true unless options.key?(:details)
          options[:memory_key] ||= field[:memory_key] || [:form_game_data, kind]
          if field[:multiple]
            options[:multi_select] = true
            options[:start_values] = Array(current).map { |value| game_data_id(value) }
          else
            options[:start_value] = game_data_id(current) unless current.nil?
          end
          result = Reloaded::GameDataPicker.pick(kind, field[:label], options)
          result.nil? ? CancelValue : normalize_value(field, result)
        end

        def custom_value(field, current)
          callback = field[:editor] || field[:edit]
          return CancelValue unless callback.respond_to?(:call)
          result = call_callback(callback, current, @draft, field, @options[:context])
          result.nil? && !field[:allow_nil] ? CancelValue : normalize_value(field, result)
        end

        def choice_rows(field)
          source = field[:choices]
          source = call_callback(source, @draft, field, @options[:context]) if source.respond_to?(:call)
          rows = []
          if source.is_a?(Hash)
            source.each { |value, label| rows << { :label => label.to_s, :value => value } }
          else
            Array(source).each do |entry|
              if entry.is_a?(Hash)
                value = entry.key?(:value) ? entry[:value] : entry["value"]
                label = entry[:label] || entry["label"] || entry[:name] || entry["name"] || value
                rows << {
                  :label => label.to_s,
                  :value => value,
                  :detail => entry[:detail] || entry["detail"] || entry[:description] || entry["description"],
                  :disabled => entry[:disabled] || entry["disabled"],
                  :disabled_reason => entry[:disabled_reason] || entry["disabled_reason"]
                }
              elsif entry.is_a?(Array)
                rows << { :label => entry[1].nil? ? entry[0].to_s : entry[1].to_s, :value => entry[0], :detail => entry[2] }
              else
                rows << { :label => Form.humanize(entry), :value => entry }
              end
            end
          end
          rows
        rescue Exception => e
          Form.log_exception("Form choices failed", e)
          []
        end

        def attempt_save
          errors, warnings = validate_all
          unless errors.empty?
            select_validation_field(errors.keys.first)
            Form.warning(errors.values.first)
            draw
            return false
          end
          if !warnings.empty? && !confirm_warnings(warnings)
            draw
            return false
          end
          if @options[:confirm_save]
            confirmed = @list_state.with_dialog { Reloaded.confirm(_INTL("Save these changes?"), :default => true) }
            return false unless confirmed
          end
          result = Form.deep_copy(@draft)
          callback = @options[:on_save]
          if callback.respond_to?(:call)
            callback_result = call_callback(callback, result, @options[:context], self)
            if callback_result == false || callback_result.is_a?(String)
              Form.error(callback_result.is_a?(String) ? callback_result : _INTL("The changes could not be saved."))
              @list_state.dialog_closed!
              draw
              return false
            end
          end
          @result = result
          @running = false
          pbPlayDecisionSE rescue nil
          true
        rescue Exception => e
          Form.log_exception("Form save failed", e)
          Form.error(_INTL("The changes could not be saved."))
          @list_state.dialog_closed! if @list_state
          false
        end

        def request_back
          unless dirty?
            @running = false
            pbPlayCancelSE rescue nil
            return
          end
          commands = [
            { :id => :save, :label => @options[:save_label] },
            { :id => :discard, :label => _INTL("Discard Changes"), :color => PopupWindow::RED },
            { :id => :cancel, :label => _INTL("Keep Editing") }
          ]
          choice = @list_state.with_dialog do
            Reloaded::ActionMenu.choose(_INTL("Unsaved changes"), commands, nil, :add_back => false, :start_id => :cancel)
          end
          case choice
          when :save
            attempt_save
          when :discard
            @result = nil
            @running = false
            pbPlayCancelSE rescue nil
          end
          draw if @running
        rescue Exception => e
          Form.log_exception("Form Back handling failed", e)
          @list_state.dialog_closed! if @list_state
        end

        def validate_all
          @errors = {}
          @warnings = {}
          @fields.each { |field| validate_field(field) unless field[:type] == :header }
          validate_form_callback
          [@errors, @warnings]
        end

        def validate_field(field)
          key = field[:id]
          @errors.delete(key)
          @warnings.delete(key)
          return true unless visible?(field)
          value = value_for(field)
          if field[:required] && blank?(value)
            @errors[key] = _INTL("{1} is required.", field[:label])
            return false
          end
          unless blank?(value)
            if field.key?(:min) && numeric?(value) && value.to_f < field[:min].to_f
              @errors[key] = _INTL("{1} must be at least {2}.", field[:label], field[:min])
            elsif field.key?(:max) && numeric?(value) && value.to_f > field[:max].to_f
              @errors[key] = _INTL("{1} cannot exceed {2}.", field[:label], field[:max])
            elsif field[:pattern].is_a?(Regexp) && value.to_s !~ field[:pattern]
              @errors[key] = field[:pattern_message].to_s.empty? ? _INTL("{1} has an invalid format.", field[:label]) : field[:pattern_message].to_s
            end
          end
          validator = field[:validate] || field[:validator]
          apply_validation_result(key, call_callback(validator, value, @draft, field, @options[:context])) if validator.respond_to?(:call)
          !@errors.key?(key)
        rescue Exception => e
          Form.log_exception("Form validation failed for #{key}", e)
          @errors[key] = _INTL("{1} could not be validated.", field[:label])
          false
        end

        def validate_form_callback
          callback = @options[:validate] || @options[:validator]
          return unless callback.respond_to?(:call)
          result = call_callback(callback, @draft, @options[:context], self)
          if result.is_a?(Hash) && !(result.key?(:level) || result.key?("level") || result.key?(:message) || result.key?("message"))
            result.each { |key, value| apply_validation_result(key, value) }
          elsif result.is_a?(Array)
            result.each { |value| apply_validation_result(:__form__, value) }
          else
            apply_validation_result(:__form__, result)
          end
        rescue Exception => e
          Form.log_exception("Form-level validation failed", e)
          @errors[:__form__] = _INTL("The form could not be validated.")
        end

        def apply_validation_result(key, result)
          return if result.nil? || result == true
          level = :error
          message = nil
          if result.is_a?(Hash)
            level = (result[:level] || result["level"] || :error).to_sym rescue :error
            message = result[:message] || result["message"]
          elsif result == false
            message = _INTL("This value is invalid.")
          else
            message = result.to_s
          end
          return if message.to_s.empty?
          if level == :warning
            @warnings[key] = message.to_s
          else
            @errors[key] = message.to_s
          end
        end

        def confirm_warnings(warnings)
          text = warnings.values.uniq.first(3).join("\n")
          text += "\n" + _INTL("Save anyway?")
          @list_state.with_dialog { Reloaded.confirm(text, :default => false) }
        rescue
          false
        end

        def select_validation_field(id)
          return if id == :__form__
          @list_state.select_id(id)
          sync_state
        end

        def draw
          draw_background
          bitmap = @sprites["form"].bitmap
          bitmap.clear
          draw_title(bitmap)
          draw_panels(bitmap)
          draw_fields(bitmap)
          draw_details(bitmap)
          draw_footer(bitmap)
        end

        def draw_background
          bitmap = @sprites["background"].bitmap
          bitmap.clear
          bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, Color.new(4, 9, 18))
        end

        def draw_title(bitmap)
          bitmap.fill_rect(0, 0, SCREEN_W, TITLE_H, Color.new(10, 20, 38, 245))
          bitmap.fill_rect(0, TITLE_H - 1, SCREEN_W, 1, @theme[:border])
          set_font(bitmap, 20)
          plain_text(bitmap, 10, 1, SCREEN_W - 20, TITLE_H, @title, @theme[:title], 1)
          set_font(bitmap, 12)
          status = dirty? ? @options[:unsaved_label] : @options[:saved_label]
          color = dirty? ? PopupWindow::ORANGE : PopupWindow::GREEN
          plain_text(bitmap, SCREEN_W - 95, 5, 84, 18, status, color, 2)
        end

        def draw_panels(bitmap)
          panel = Color.new(8, 17, 32, 235)
          PopupWindow.draw_rounded_rect(bitmap, LEFT_X, CONTENT_Y + 4, LEFT_W, CONTENT_H - 8, 4, @theme[:border])
          PopupWindow.draw_rounded_rect(bitmap, LEFT_X + 1, CONTENT_Y + 5, LEFT_W - 2, CONTENT_H - 10, 3, panel)
          PopupWindow.draw_rounded_rect(bitmap, RIGHT_X, CONTENT_Y + 4, RIGHT_W, CONTENT_H - 8, 4, @theme[:border])
          PopupWindow.draw_rounded_rect(bitmap, RIGHT_X + 1, CONTENT_Y + 5, RIGHT_W - 2, CONTENT_H - 10, 3, panel)
        end

        def draw_fields(bitmap)
          visible = @fields[@scroll, visible_row_count] || []
          visible.each_with_index do |field, local_index|
            index = @scroll + local_index
            y = CONTENT_Y + LIST_PAD + local_index * ROW_H
            if field[:type] == :header
              set_font(bitmap, 14)
              plain_text(bitmap, LEFT_X + 10, y - 4, LEFT_W - 20, ROW_H, field[:label], @theme[:title], 1)
              next
            end
            selected = index == @selected
            draw_selection(bitmap, LEFT_X + 6, y + 2, LEFT_W - 17, ROW_H - 4) if selected
            enabled = enabled?(field)
            color = enabled ? (selected ? PopupWindow::WHITE : PopupWindow::GRAY) : PopupWindow::DIM
            value_color = validation_color(field) || (enabled ? @theme[:title] : PopupWindow::DIM)
            set_font(bitmap, 14)
            plain_text(bitmap, LEFT_X + 12, y - 4, 116, ROW_H, fit_text(bitmap, field[:label], 112), color, 0)
            plain_text(bitmap, LEFT_X + 130, y - 4, LEFT_W - 146, ROW_H, fit_text(bitmap, display_value(field), LEFT_W - 150), value_color, 2)
          end
          draw_scrollbar(bitmap)
        end

        def draw_details(bitmap)
          field = selected_field
          return unless field
          x = RIGHT_X + 12
          width = RIGHT_W - 24
          y = CONTENT_Y + 10
          set_font(bitmap, 18)
          plain_text(bitmap, x, y - 4, width, 24, field[:label], @theme[:title], 0)
          y += 26
          set_font(bitmap, 13)
          description = field[:description]
          description = _INTL("No description is available for this field.") if description.empty?
          wrap_lines(bitmap, description, width).each do |line|
            break if y > CONTENT_Y + CONTENT_H - 90
            plain_text(bitmap, x, y - 4, width, 19, line, PopupWindow::GRAY, 0)
            y += 18
          end
          y += 8
          set_font(bitmap, 13)
          plain_text(bitmap, x, y - 4, 62, 20, _INTL("Value"), PopupWindow::DIM, 0)
          value_lines = wrap_lines(bitmap, detail_value(field), width - 4).first(5)
          value_lines.each do |line|
            y += 18
            plain_text(bitmap, x, y - 4, width, 20, line, PopupWindow::WHITE, 0)
          end
          message = @errors[field[:id]] || @warnings[field[:id]]
          if message
            y = [y + 28, CONTENT_Y + CONTENT_H - 62].min
            color = @errors[field[:id]] ? PopupWindow::RED : PopupWindow::GOLD
            wrap_lines(bitmap, message, width).first(2).each do |line|
              plain_text(bitmap, x, y - 4, width, 19, line, color, 0)
              y += 18
            end
          elsif !enabled?(field)
            y = [y + 28, CONTENT_Y + CONTENT_H - 44].min
            plain_text(bitmap, x, y - 4, width, 20, disabled_reason(field), PopupWindow::GOLD, 0)
          end
        end

        def draw_footer(bitmap)
          y = SCREEN_H - FOOTER_H
          bitmap.fill_rect(0, y, SCREEN_W, FOOTER_H, Color.new(8, 14, 28, 245))
          bitmap.fill_rect(0, y, SCREEN_W, 1, @theme[:border])
          set_font(bitmap, 12)
          status = dirty? ? @options[:unsaved_label] : @options[:saved_label]
          plain_text(bitmap, 10, y + 1, 100, FOOTER_H, status, dirty? ? PopupWindow::ORANGE : PopupWindow::GREEN, 0)
          if @options[:controls] && defined?(Reloaded::HintText)
            Reloaded::HintText.draw_footer(bitmap, [], 345, y, 160, :size => 14, :height => FOOTER_H)
          end
        end

        def show_controls
          return unless defined?(Reloaded::HintText)
          entries = [
            Reloaded::HintText.confirm("Edit"),
            Reloaded::HintText.back,
            Reloaded::HintText.action("Save"),
            Reloaded::HintText.other("Jump 3", :page)
          ]
          @list_state.with_dialog { Reloaded::HintText.open_popup("Controls", entries) }
          draw
        rescue Exception => e
          Form.log_exception("Form controls failed", e)
        end

        def show_disabled(field)
          pbPlayBuzzerSE rescue nil
          @list_state.with_dialog { Form.warning(disabled_reason(field)) }
          draw
        end

        def visible?(field)
          condition(field[:visible], true, field)
        end

        def enabled?(field)
          return false if [:readonly, :header].include?(field[:type])
          condition(field[:enabled], true, field)
        end

        def condition(value, default, field)
          return default if value.nil?
          value.respond_to?(:call) ? !!call_callback(value, @draft, field, @options[:context]) : !!value
        rescue
          default
        end

        def disabled_reason(field)
          value = field[:disabled_reason]
          value = call_callback(value, @draft, field, @options[:context]) if value.respond_to?(:call)
          text = value.to_s
          text.empty? ? _INTL("This field cannot be edited.") : text
        rescue
          _INTL("This field cannot be edited.")
        end

        def run_on_change(field, old_value, new_value)
          callback = field[:on_change] || @options[:on_change]
          call_callback(callback, @draft, field, old_value, new_value, @options[:context]) if callback.respond_to?(:call)
        rescue Exception => e
          Form.log_exception("Form change callback failed", e)
        end

        def normalize_value(field, value)
          callback = field[:normalize]
          callback.respond_to?(:call) ? call_callback(callback, value, @draft, field, @options[:context]) : value
        rescue Exception => e
          Form.log_exception("Form value normalization failed", e)
          value
        end

        def value_for(field)
          key = value_key(field)
          @draft[key]
        end

        def write_value(field, value)
          @draft[value_key(field)] = value
        end

        def has_field_value?(field)
          keys_for(field).any? { |key| @draft.has_key?(key) }
        end

        def value_key(field)
          keys_for(field).find { |key| @draft.has_key?(key) } || field[:key]
        end

        def keys_for(field)
          key = field[:key]
          alternate = key.is_a?(String) ? (key.to_sym rescue key) : key.to_s
          [key, alternate].uniq
        end

        def display_value(field)
          value = value_for(field)
          return truthy?(value) ? _INTL("ON") : _INTL("OFF") if field[:type] == :toggle
          return _INTL("Not set") if blank?(value)
          if value.is_a?(Array)
            return _INTL("{1} selected", value.length) if value.length > 2
            return value.map { |entry| choice_label(field, entry) }.join(", ")
          end
          choice_label(field, value)
        end

        def detail_value(field)
          value = value_for(field)
          return _INTL("Not set") if blank?(value)
          value.is_a?(Array) ? value.map { |entry| choice_label(field, entry) }.join(", ") : choice_label(field, value)
        end

        def choice_label(field, value)
          row = choice_rows(field).find { |candidate| candidate[:value] == value }
          row ? row[:label].to_s : value.to_s
        rescue
          value.to_s
        end

        def validation_color(field)
          return PopupWindow::RED if @errors.key?(field[:id])
          return PopupWindow::GOLD if @warnings.key?(field[:id])
          nil
        end

        def selected_field
          @fields[@selected]
        end

        def sync_state
          @selected = @list_state.index || 0
          @scroll = @list_state.scroll
        end

        def dirty?
          !values_equal?(@draft, @original)
        end

        def values_equal?(left, right)
          left == right
        rescue
          false
        end

        def blank?(value)
          value.nil? || (value.respond_to?(:empty?) && value.empty?) || value.to_s.strip.empty?
        rescue
          value.nil?
        end

        def numeric?(value)
          value.is_a?(Numeric) || value.to_s =~ /\A-?\d+(\.\d+)?\z/
        rescue
          false
        end

        def truthy?(value)
          value == true || value.to_s.downcase == "true" || value.to_s == "1" || value.to_s.downcase == "on"
        end

        def game_data_id(value)
          return nil if value.nil? || value.to_s.empty?
          value.is_a?(Symbol) ? value : (value.to_s.to_sym rescue value)
        end

        def call_callback(callback, *arguments)
          return callback unless callback.respond_to?(:call)
          arity = callback.arity rescue -1
          return callback.call if arity == 0
          return callback.call(*arguments) if arity < 0
          callback.call(*arguments.first(arity))
        end

        def copy_options(value)
          result = {}
          (value || {}).each do |key, item|
            normalized = key.to_sym rescue key
            result[normalized] = item
          end
          result
        rescue
          {}
        end

        def visible_row_count
          [(CONTENT_H - LIST_PAD * 2) / ROW_H, 1].max
        end

        def draw_scrollbar(bitmap)
          return if @fields.length <= visible_row_count
          x = LEFT_X + LEFT_W - SCROLLBAR_W - 5
          y = CONTENT_Y + LIST_PAD + 4
          height = visible_row_count * ROW_H - 8
          bitmap.fill_rect(x, y, SCROLLBAR_W, height, Color.new(24, 50, 82, 180))
          thumb_h = [[height * visible_row_count / @fields.length, 12].max, height].min
          max_scroll = [@fields.length - visible_row_count, 1].max
          thumb_y = y + ((height - thumb_h) * @scroll / max_scroll)
          bitmap.fill_rect(x, thumb_y, SCROLLBAR_W, thumb_h, @theme[:title])
        rescue
        end

        def draw_selection(bitmap, x, y, width, height)
          theme = if defined?(Reloaded::Options) && Reloaded::Options.respond_to?(:cursor_theme)
                    Reloaded::Options.cursor_theme(($PokemonSystem.reloaded_cursor_theme rescue 0))
                  else
                    {}
                  end
          base = theme[:fill] || Color.new(100, 160, 220, 160)
          border = theme[:border] || Color.new(60, 120, 180, 220)
          pulse = Math.sin((Graphics.frame_count rescue 0) * Math::PI / 20.0) * 0.5 + 0.5
          alpha = [[base.alpha.to_i + (pulse * 55).to_i, 255].min, 80].max
          fill = Color.new(base.red, base.green, base.blue, alpha)
          PopupWindow.draw_rounded_rect(bitmap, x, y, width, height, 4, border)
          PopupWindow.draw_rounded_rect(bitmap, x + 1, y + 1, width - 2, height - 2, 3, fill)
        rescue
        end

        def set_font(bitmap, size)
          pbSetSmallFont(bitmap) rescue pbSetSystemFont(bitmap)
          bitmap.font.size = size rescue nil
        end

        def plain_text(bitmap, x, y, width, height, text, color, align = 0)
          draw_x = x
          draw_align = 0
          if align == 1
            draw_x = x + width / 2
            draw_align = 2
          elsif align == 2
            draw_x = x + width
            draw_align = 1
          end
          pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y, draw_align, color, PopupWindow::TRANSPARENT]])
        rescue
        end

        def fit_text(bitmap, text, width)
          value = text.to_s
          return value if bitmap.text_size(value).width <= width
          suffix = "..."
          value = value[0...-1].to_s while !value.empty? && bitmap.text_size(value + suffix).width > width
          value + suffix
        rescue
          text.to_s
        end

        def wrap_lines(bitmap, text, width)
          output = []
          text.to_s.gsub("\r", "").split("\n", -1).each do |paragraph|
            words = paragraph.split(/\s+/)
            if words.empty?
              output << ""
              next
            end
            line = ""
            words.each do |word|
              candidate = line.empty? ? word : "#{line} #{word}"
              if !line.empty? && bitmap.text_size(candidate).width > width
                output << line
                line = word
              else
                line = candidate
              end
            end
            output << line unless line.empty?
          end
          output.empty? ? [""] : output
        rescue
          [text.to_s]
        end

        def pulse_redraw?
          (Graphics.frame_count rescue 0) % 4 == 0
        end

        def save_triggered?
          defined?(Input) && Input.const_defined?(:ACTION) && Input.trigger?(Input::ACTION)
        rescue
          false
        end

        def controls_triggered?
          @options[:controls] && defined?(Reloaded::HintText) && Reloaded::HintText.triggered?
        rescue
          false
        end

        def controls_clicked?(x, y)
          return false unless @options[:controls] && defined?(Reloaded::HintText)
          return false unless mouse_left_triggered?
          Reloaded::HintText.controls_at?(
            @sprites["form"].bitmap,
            x,
            y,
            345,
            SCREEN_H - FOOTER_H,
            160,
            :size => 14,
            :height => FOOTER_H
          )
        rescue
          false
        end

        def mouse_left_triggered?
          defined?(Input) && Input.const_defined?(:MOUSELEFT) && Input.trigger?(Input::MOUSELEFT)
        rescue
          false
        end

        def mouse_right_triggered?
          defined?(Input) && Input.const_defined?(:MOUSERIGHT) && Input.trigger?(Input::MOUSERIGHT)
        rescue
          false
        end

        def drain_input
          2.times do
            Graphics.update rescue nil
            Input.update rescue nil
          end
        rescue
        end
      end
    end
  end

  Form = API::Form unless const_defined?(:Form, false)

  class << self
    def form(title, fields, values = {}, options = {})
      Form.open(title, fields, values, options)
    end
  end
end
