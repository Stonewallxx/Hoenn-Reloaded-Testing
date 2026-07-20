#======================================================
# Reloaded Number Picker
# Author: Stonewall
#======================================================
# Shared HR-style quantity and integer selection for Reloaded systems and mods.
#======================================================

module Reloaded
  module API
    module NumberPicker
      DEFAULT_STEP = 1
      DEFAULT_LARGE_STEP = 10
      ROW_H = 20
      CHOICE_H = 22
      SLOT_GAP = 0
      SLOT_HEIGHT = 20
      MIN_SLOT_WIDTH = 12
      MAX_SLOT_WIDTH = 18
      PANEL_HEIGHT = 114
      OK_HEIGHT = 22

      class << self
        def open(title, options = {})
          normalized = normalize_digit_options(options)
          return digit_fallback(title, normalized) unless graphics_available?
          PopupWindow.with_modal do
            DigitScene.new(title, normalized).main
          end
        rescue Exception => e
          PopupWindow.log_exception("NumberPicker failed", e) if defined?(PopupWindow)
          nil
        ensure
          drain_digit_input
        end

        def quantity(title, options = {})
          opts = options.merge(:min => options.key?(:min) ? options[:min] : 1)
          opts[:value_prefix] = "x" unless opts.key?(:value_prefix)
          opts[:show_max_label] = true unless opts.key?(:show_max_label)
          open_quantity(title, opts)
        end

        def open_quantity(title, options = {})
          PopupWindow.with_modal do
            PickerScene.new(title, normalize_options(options)).main
          end
        rescue Exception => e
          PopupWindow.log_exception("NumberPicker quantity failed", e) if defined?(PopupWindow)
          nil
        end

        def currency(title, options = {})
          open_quantity(title, options.merge(:show_unit_price => true))
        end

        def confirm(title, options = {})
          PopupWindow.with_modal do
            ConfirmationScene.new(title, normalize_options(options)).main
          end
        rescue Exception => e
          PopupWindow.log_exception("NumberPicker confirmation failed", e) if defined?(PopupWindow)
          false
        end

        def normalize_digit_options(options)
          source = options.is_a?(Hash) ? options : {}
          values = {}
          source.each do |key, value|
            normalized_key = key.to_sym rescue key
            values[normalized_key] = value
          end

          minimum = values.key?(:min) ? values[:min].to_i : 0
          maximum = values.key?(:max) ? values[:max].to_i : 100
          minimum, maximum = maximum, minimum if maximum < minimum
          minimum = [minimum, 0].max
          maximum = [maximum, minimum].max
          initial = values.key?(:initial) ? values[:initial].to_i : minimum
          initial = [[initial, minimum].max, maximum].min
          required_digits = [minimum.to_s.length, maximum.to_s.length, 1].max
          requested_digits = values[:digits].to_i
          digits = [requested_digits, required_digits].max
          digits = required_digits if digits <= 0

          {
            :min => minimum,
            :max => maximum,
            :initial => initial,
            :digits => digits,
            :label => values[:label].to_s,
            :value_prefix => values[:value_prefix].to_s,
            :width => (values[:width] || 340).to_i,
            :theme => normalize_theme(values[:theme]),
            :show_dim => values.key?(:show_dim) ? !!values[:show_dim] : true,
            :z => (values[:z] || 999_999_999).to_i,
            :on_change => values[:on_change]
          }
        end

        def normalize_options(options)
          opts = {}
          (options || {}).each do |key, value|
            normalized_key = key.to_sym rescue key
            opts[normalized_key] = value
          end
          min = opts.key?(:min) ? opts[:min].to_i : 0
          max = opts.key?(:max) ? opts[:max].to_i : 100
          min, max = max, min if max < min
          opts[:min] = min
          opts[:max] = max
          opts[:step] = positive_step(opts[:step], DEFAULT_STEP)
          opts[:large_step] = positive_step(opts[:large_step], DEFAULT_LARGE_STEP)
          opts[:initial] = [[(opts.key?(:initial) ? opts[:initial] : min).to_i, min].max, max].min
          opts[:wrap] = true unless opts.key?(:wrap)
          opts[:show_max_label] = !!opts[:show_max_label]
          opts[:show_unit_price] = !!opts[:show_unit_price]
          opts[:allow_max_shortcut] = !!opts[:allow_max_shortcut]
          opts[:value_prefix] = opts[:value_prefix].to_s
          opts[:value_suffix] = opts[:value_suffix].to_s
          opts[:label] = opts[:label].to_s
          opts[:free_label] = (opts[:free_label] || _INTL("FREE")).to_s
          opts[:theme] = (opts[:theme] || :hr).to_sym rescue :hr
          opts[:theme] = :hr unless PopupWindow::THEMES[opts[:theme]]
          opts[:show_dim] = true unless opts.key?(:show_dim)
          opts[:z] = (opts[:z] || 999_999_999).to_i
          opts[:width] = opts[:width] || 340
          opts
        end

        def positive_step(value, fallback)
          amount = value.to_i
          amount > 0 ? amount : fallback
        rescue
          fallback
        end

        def normalize_theme(value)
          key = (value || :hr).to_sym rescue :hr
          PopupWindow::THEMES.key?(key) ? key : :hr
        rescue
          :hr
        end

        def graphics_available?
          defined?(Graphics) && defined?(Input) && defined?(Viewport) &&
            defined?(Sprite) && defined?(Bitmap)
        end

        def digit_fallback(title, options)
          return options[:initial] unless defined?(ChooseNumberParams)
          receiver = Object.new
          return options[:initial] unless receiver.respond_to?(:pbMessageChooseNumber, true)
          params = ChooseNumberParams.new
          params.setRange(options[:min], options[:max])
          params.setDefaultValue(options[:initial])
          cancel_value = options[:min] - 1
          params.setCancelValue(cancel_value)
          result = receiver.__send__(:pbMessageChooseNumber, title.to_s, params)
          result == cancel_value ? nil : result
        rescue
          options[:initial]
        end

        def drain_digit_input
          2.times { Input.update rescue nil }
          30.times do
            held = (Input.press?(Input::USE) rescue false) ||
                   (Input.press?(Input::BACK) rescue false) ||
                   (Input.const_defined?(:MOUSELEFT) &&
                    (Input.press?(Input.const_get(:MOUSELEFT)) rescue false))
            break unless held
            Graphics.update rescue nil
            Input.update rescue nil
          end
        rescue
          nil
        end
      end

      # Position-for-position and behavior-for-behavior port of Kanto Reloaded's
      # generic editor number picker. Quantity and confirmation popups use the
      # separate PickerScene below.
      class DigitScene
        include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

        def initialize(title, options)
          @title = title.to_s
          @options = options
          @theme = PopupWindow::THEMES[@options[:theme]] || PopupWindow::THEMES[:hr]
          @slot_count = @options[:digits]
          @digits = value_to_digits(@options[:initial])
          @index = @slot_count - 1
          @error = nil
        end

        def main
          setup
          notify_change
          draw
          update_loop
        ensure
          dispose
        end

        private

        def setup
          calculate_layout
          @viewport = Viewport.new(0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          @viewport.z = @options[:z]
          @dim_sprite = Sprite.new(@viewport)
          @dim_sprite.bitmap = Bitmap.new(PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          if @options[:show_dim]
            @dim_sprite.bitmap.fill_rect(
              0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H,
              PopupWindow::DIM_BG
            )
          end
          @sprite = Sprite.new(@viewport)
          @sprite.bitmap = Bitmap.new(@width, @height)
          @sprite.x = (PopupWindow::SCREEN_W - @width) / 2
          @sprite.y = (PopupWindow::SCREEN_H - @height) / 2
          @sprite.z = @viewport.z
        end

        def calculate_layout
          measure = Bitmap.new(1, 1)
          pbSetSmallFont(measure) if defined?(pbSetSmallFont)
          title_width = (measure.text_size(@title).width rescue PopupWindow::MIN_W) +
                        PopupWindow::PAD * 2 + PopupWindow::TEXT_SAFETY_PAD
          label = display_label
          label_width = (measure.text_size(label).width rescue 0) +
                        PopupWindow::PAD * 2 + PopupWindow::TEXT_SAFETY_PAD
          @slot_width = [(measure.text_size("0").width rescue MIN_SLOT_WIDTH), 1].max
          @prefix_width = @options[:value_prefix].empty? ? 0 :
                          (measure.text_size(@options[:value_prefix]).width rescue 0)
          measure.dispose rescue nil
          desired_width = [@options[:width], title_width, label_width].max
          @width = [[desired_width, PopupWindow::MIN_W].max,
                    PopupWindow::MAX_W].min
          calculate_digit_positions
          @slots_y = 48
          @ok_y = 82
          @height = PANEL_HEIGHT
        end

        def calculate_digit_positions
          @digit_xs = Array.new(@slot_count)
          cursor = @width - 14
          (@slot_count - 1).downto(0) do |index|
            cursor -= @slot_width
            @digit_xs[index] = cursor
          end
          @prefix_x = cursor - @prefix_width
        end

        def update_loop
          loop do
            Graphics.update
            Input.update

            mouse_result = update_mouse
            return mouse_result unless mouse_result == :continue

            if trigger?(:BACK)
              pbPlayCancelSE rescue nil
              return nil
            elsif repeat?(:LEFT)
              move_selection(-1)
            elsif repeat?(:RIGHT)
              move_selection(1)
            elsif repeat?(:UP)
              adjust_selected_digit(1) if digit_selected?
            elsif repeat?(:DOWN)
              adjust_selected_digit(-1) if digit_selected?
            elsif trigger?(:USE)
              result = confirm_selection
              return result unless result == :continue
            end
            draw if ((Graphics.frame_count rescue 0) % 4).zero?
          end
        end

        def update_mouse
          if input_triggered?(:MOUSERIGHT)
            pbPlayCancelSE rescue nil
            return nil
          end

          position = Reloaded::MouseInput.active_position rescue nil
          return :continue unless position
          local_x = position[0].to_i - @sprite.x
          local_y = position[1].to_i - @sprite.y
          hit = hit_test(local_x, local_y)
          if !hit.nil? && hit != @index
            @index = hit
            pbPlayCursorSE rescue nil
            draw
          end

          wheel = wheel_delta
          if wheel != 0 && digit_selected? && hit == @index
            adjust_selected_digit(wheel > 0 ? 1 : -1)
          end

          return :continue unless mouse_triggered?
          return :continue if hit.nil?
          return submit if hit == @slot_count
          :continue
        rescue
          :continue
        end

        def hit_test(x, y)
          if y >= @slots_y - 4 && y < @slots_y + SLOT_HEIGHT
            @slot_count.times do |index|
              slot_x = @digit_xs[index]
              return index if x >= slot_x && x < slot_x + @slot_width
            end
          end
          if x >= 12 && x < @width - 12 && y >= @ok_y && y < @ok_y + OK_HEIGHT
            return @slot_count
          end
          nil
        end

        def move_selection(amount)
          if digit_selected?
            @index = (@index + amount.to_i) % @slot_count
          else
            @index = amount.to_i < 0 ? @slot_count - 1 : 0
          end
          @error = nil
          pbPlayCursorSE rescue nil
          draw
        end

        def adjust_selected_digit(amount)
          @digits[@index] = (@digits[@index] + amount.to_i) % 10
          @error = nil
          pbPlayCursorSE rescue nil
          notify_change
          draw
        end

        def confirm_selection
          if digit_selected?
            @index = @slot_count
            pbPlayCursorSE rescue nil
            draw
            return :continue
          end
          submit
        end

        def submit
          value = current_value
          unless valid_value?(value)
            @error = _INTL(
              "Choose a value from {1} to {2}.",
              @options[:min],
              @options[:max]
            )
            pbPlayBuzzerSE rescue nil
            draw
            return :continue
          end
          pbPlayDecisionSE rescue nil
          value
        end

        def valid_value?(value)
          value >= @options[:min] && value <= @options[:max]
        end

        def digit_selected?
          @index >= 0 && @index < @slot_count
        end

        def current_value
          @digits.inject(0) { |value, digit| value * 10 + digit.to_i }
        end

        def value_to_digits(value)
          text = value.to_i.to_s.rjust(@slot_count, "0")
          text[-@slot_count, @slot_count].chars.map { |character| character.to_i }
        end

        def formatted_value
          current_value.to_i.to_s_formatted
        rescue StandardError
          current_value.to_i.to_s
        end

        def display_label
          value = @options[:label].to_s
          value.empty? ? _INTL("Value") : value
        end

        def notify_change
          callback = @options[:on_change]
          callback.call(current_value) if callback.respond_to?(:call)
        rescue Exception => e
          PopupWindow.log_exception("NumberPicker callback failed", e) if defined?(PopupWindow)
        end

        def draw
          bitmap = @sprite.bitmap
          bitmap.clear
          pbSetSmallFont(bitmap) if defined?(pbSetSmallFont)
          PopupWindow.draw_panel(bitmap, @width, @height, @theme, self)
          plain_text(
            bitmap, 14, 3, @width - 28, 20,
            @title, @theme[:text] || PopupWindow::WHITE, 0
          )
          draw_label(bitmap)
          draw_digit_slots(bitmap)
          bitmap.fill_rect(
            14, 74, @width - 28, 1,
            @theme[:border] || PopupWindow::DIM
          )
          draw_ok_row(bitmap)
        end

        def draw_label(bitmap)
          color = @error ? PopupWindow::RED :
                  (@theme[:text] || PopupWindow::WHITE)
          plain_text(
            bitmap, 14, 25, @width - 28, 20,
            @error || display_label, color, 0
          )
        end

        def draw_digit_slots(bitmap)
          dim = @theme[:dim] || PopupWindow::DIM
          unless @options[:value_prefix].empty?
            plain_text(
              bitmap, @prefix_x, @slots_y, @prefix_width, SLOT_HEIGHT,
              @options[:value_prefix], dim, 0
            )
          end
          @digits.each_with_index do |digit, index|
            x = @digit_xs[index]
            color = index == @index ? pulsing_digit_color : dim
            plain_text(
              bitmap, x, @slots_y, @slot_width, SLOT_HEIGHT,
              digit.to_s, color, 0
            )
          end
        end

        def pulsing_digit_color
          pulse = Math.sin(
            (Graphics.frame_count rescue 0) * Math::PI / 20.0
          ) * 0.5 + 0.5
          value = 175 + (pulse * 80).to_i
          Color.new(value, value, value)
        rescue
          PopupWindow::WHITE
        end

        def draw_ok_row(bitmap)
          selected = @index == @slot_count
          if selected
            draw_rounded_rect(
              bitmap, 12, @ok_y, @width - 24, OK_HEIGHT, 4,
              pulsing_cursor_fill
            )
          end
          plain_text(
            bitmap, 20, @ok_y - 6, @width - 40, OK_HEIGHT,
            _INTL("OK"),
            selected ? PopupWindow::WHITE : PopupWindow::GRAY,
            0
          )
        end

        def pulsing_cursor_fill
          base, _border = cursor_colors
          pulse = Math.sin((Graphics.frame_count rescue 0) * Math::PI / 20.0) * 0.5 + 0.5
          alpha = [[base.alpha.to_i + (pulse * 55).to_i, 255].min, 80].max
          Color.new(base.red, base.green, base.blue, alpha)
        rescue
          Color.new(100, 160, 220, 180)
        end

        def cursor_border
          _fill, border = cursor_colors
          border
        end

        def cursor_colors
          if respond_to?(:reloaded_cursor_fill) && respond_to?(:reloaded_cursor_border)
            return [reloaded_cursor_fill, reloaded_cursor_border]
          end
          [Color.new(100, 160, 220, 160), Color.new(60, 120, 180, 220)]
        rescue
          [Color.new(100, 160, 220, 160), Color.new(60, 120, 180, 220)]
        end

        def input_triggered?(name)
          Input.const_defined?(name) && Input.trigger?(Input.const_get(name))
        rescue
          false
        end

        def trigger?(name)
          input_triggered?(name)
        end

        def repeat?(name)
          Input.const_defined?(name) && Input.repeat?(Input.const_get(name))
        rescue
          false
        end

        def wheel_delta
          return Input.scroll_v.to_i if Input.respond_to?(:scroll_v)
          return -1 if Input.const_defined?(:SCROLLUP) && (Input.repeat?(Input::SCROLLUP) rescue false)
          return 1 if Input.const_defined?(:SCROLLDOWN) && (Input.repeat?(Input::SCROLLDOWN) rescue false)
          0
        rescue
          0
        end

        def mouse_triggered?
          input_triggered?(:MOUSELEFT)
        end

        def plain_text(bitmap, x, y, width, height, text, color, align = 0)
          draw_x = x
          draw_align = 0
          case align
          when 1
            draw_x = x + width / 2
            draw_align = 2
          when 2
            draw_x = x + width
            draw_align = 1
          end
          pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y, draw_align, color, PopupWindow::TRANSPARENT]])
        rescue
        end

        def draw_rounded_rect(bitmap, x, y, width, height, radius, color)
          if respond_to?(:reloaded_draw_rounded_rect)
            reloaded_draw_rounded_rect(bitmap, x, y, width, height, radius, color, cursor_border)
          else
            PopupWindow.draw_rounded_rect(bitmap, x, y, width, height, radius, color)
          end
        rescue
          bitmap.fill_rect(x, y, width, height, color)
        end

        def dispose
          if @dim_sprite
            if @dim_sprite.bitmap && !@dim_sprite.bitmap.disposed?
              @dim_sprite.bitmap.dispose
            end
            @dim_sprite.dispose unless @dim_sprite.disposed?
          end
          if @sprite
            @sprite.bitmap.dispose if @sprite.bitmap && !@sprite.bitmap.disposed?
            @sprite.dispose unless @sprite.disposed?
          end
          @viewport.dispose if @viewport && !@viewport.disposed?
        rescue
          nil
        end
      end

      class PickerScene
        include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

        def initialize(title, options)
          @title = title.to_s
          @options = options
          @theme = PopupWindow::THEMES[@options[:theme]] || PopupWindow::THEMES[:hr]
          @value = @options[:initial]
          @sprites = {}
        end

        def main
          setup
          notify_change
          draw
          loop do
            Graphics.update
            Input.update
            draw if pulse_redraw?
            if controls_triggered?
              show_controls_popup
              next
            end
            if Input.trigger?(Input::BACK)
              pbPlayCancelSE rescue nil
              return nil
            elsif Input.trigger?(Input::USE)
              result = submit
              return result unless result == :continue
            elsif Input.repeat?(Input::UP)
              adjust(@options[:step], true)
            elsif Input.repeat?(Input::DOWN)
              adjust(-@options[:step], true)
            elsif Input.repeat?(Input::RIGHT)
              adjust(@options[:large_step], false)
            elsif Input.repeat?(Input::LEFT)
              adjust(-@options[:large_step], false)
            elsif max_shortcut_triggered?
              set_value(@options[:max])
            end
            mouse_result = update_mouse
            return mouse_result unless mouse_result == :continue
          end
        ensure
          dispose
          drain_input
        end

        def setup
          @w = [[@options[:width].to_i, PopupWindow::MIN_W].max, PopupWindow::MAX_W].min
          @has_preview_row = preview_row?
          @label_present = !@options[:label].empty?
          @quantity_y = @label_present ? 49 : 27
          @unit_y = @label_present ? 25 : 21
          @preview_y = @label_present ? 49 : 38
          @separator_y = if @has_preview_row
                           @label_present ? 78 : 60
                         else
                           @quantity_y + 25
                         end
          @choice_y = @separator_y + 8
          @h = @choice_y + CHOICE_H * choice_count + 10
          @x = (PopupWindow::SCREEN_W - @w) / 2
          @y = (PopupWindow::SCREEN_H - @h) / 2
          @viewport = Viewport.new(0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          @viewport.z = @options[:z]
          @sprites["dim"] = Sprite.new(@viewport)
          @sprites["dim"].bitmap = Bitmap.new(PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          @sprites["dim"].bitmap.fill_rect(0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H, PopupWindow::DIM_BG) if @options[:show_dim]
          @sprites["picker"] = Sprite.new(@viewport)
          @sprites["picker"].x = @x
          @sprites["picker"].y = @y
          @sprites["picker"].z = @options[:z]
          @sprites["picker"].bitmap = Bitmap.new(@w, @h)
        end

        def draw
          bitmap = @sprites["picker"].bitmap
          bitmap.clear
          PopupWindow.draw_panel(bitmap, @w, @h, @theme, self)
          pbSetSmallFont(bitmap) rescue nil
          plain_text(bitmap, 14, 3, @w - 28, ROW_H, fit_text(bitmap, @title, @w - 28), @theme[:text], 0)
          draw_item_row(bitmap) if @label_present
          draw_quantity_row(bitmap)
          draw_preview_row(bitmap) if @has_preview_row
          bitmap.fill_rect(14, @separator_y, @w - 28, 1, @theme[:border] || PopupWindow::DIM)
          draw_choice_rows(bitmap)
        end

        def draw_item_row(bitmap)
          plain_text(bitmap, 14, 25, @w - 28, ROW_H, fit_text(bitmap, @options[:label], @w - 28), @theme[:text], 0)
        end

        def draw_quantity_row(bitmap)
          value_color = at_max? && @options[:show_max_label] ? PopupWindow::BLUE : @theme[:text]
          plain_text(bitmap, 14, @quantity_y, (@w - 28) / 2, ROW_H, value_text, value_color, 0)
        end

        def draw_preview_row(bitmap)
          preview_text, preview_color = preview
          unit_text = unit_price_text
          plain_text(bitmap, @w / 2, @unit_y, @w / 2 - 14, ROW_H, unit_text, @theme[:dim], 2) unless unit_text.empty?
          plain_text(bitmap, @w / 2, @preview_y, @w / 2 - 14, ROW_H, preview_text, preview_color, 2) unless preview_text.empty?
        end

        def draw_choice_rows(bitmap)
          draw_selection(bitmap, 12, @choice_y, @w - 24, CHOICE_H)
          plain_text(bitmap, 20, @choice_y - 6, @w - 40, CHOICE_H, _INTL("OK"), @theme[:text], 0)
        end

        def choice_count
          1
        end

        def adjust(amount, allow_wrap)
          candidate = @value + amount.to_i
          if allow_wrap && @options[:wrap]
            candidate = @options[:min] if candidate > @options[:max]
            candidate = @options[:max] if candidate < @options[:min]
          end
          set_value(candidate)
        end

        def set_value(value)
          next_value = [[value.to_i, @options[:min]].max, @options[:max]].min
          return if next_value == @value
          @value = next_value
          pbPlayCursorSE rescue nil
          notify_change
          draw
        end

        def submit
          validator = @options[:validator]
          if validator.respond_to?(:call)
            result = validator.call(@value)
            unless result.nil? || result == true
              reason = result == false ? _INTL("This value is unavailable.") : result.to_s
              Reloaded::Toast.warning(reason) if defined?(Reloaded::Toast)
              draw
              return :continue
            end
          end
          pbPlayDecisionSE rescue nil
          @value
        rescue Exception => e
          PopupWindow.log_exception("NumberPicker validation failed", e) if defined?(PopupWindow)
          :continue
        end

        def update_mouse
          scroll = mouse_scroll
          if scroll > 0
            adjust(@options[:step], true)
          elsif scroll < 0
            adjust(-@options[:step], true)
          end
          position = Reloaded::MouseInput.active_position rescue nil
          return :continue unless position
          local_x = position[0].to_i - @x
          local_y = position[1].to_i - @y
          if mouse_right_triggered?
            pbPlayCancelSE rescue nil
            return nil
          end
          return :continue unless mouse_left_triggered?
          if local_x >= 12 && local_x < @w - 12 && local_y >= @choice_y && local_y < @choice_y + CHOICE_H
            return submit
          end
          :continue
        rescue
          :continue
        end

        def preview
          value = if @options[:preview].respond_to?(:call)
                    @options[:preview].call(@value)
                  elsif @options.key?(:unit_price)
                    @options[:unit_price].to_i * @value
                  end
          return ["", @theme[:text]] if value.nil?
          if value.is_a?(Hash)
            return [value[:text].to_s, value[:color] || preview_color(value[:value])]
          end
          return [value[0].to_s, value[1] || @theme[:text]] if value.is_a?(Array)
          numeric = value.is_a?(Numeric) ? value.to_i : nil
          text = numeric.nil? ? value.to_s : format_currency(numeric)
          [text, preview_color(numeric)]
        rescue
          ["", @theme[:text]]
        end

        def preview_color(value)
          color = @options[:preview_color]
          return color.call(value, @value) if color.respond_to?(:call)
          return color if color
          value.to_i <= 0 ? PopupWindow::GREEN : @theme[:text]
        rescue
          @theme[:text]
        end

        def format_currency(value)
          return @options[:free_label] if value.to_i == 0 && !@options[:free_label].empty?
          formatter = @options[:currency_formatter]
          return formatter.call(value.to_i).to_s if formatter.respond_to?(:call)
          value.to_i.to_s
        rescue
          value.to_s
        end

        def unit_price_text
          return "" unless @options.key?(:unit_price)
          label = (@options[:unit_label] || _INTL("Each")).to_s
          "#{label}: #{format_currency(@options[:unit_price].to_i)}"
        end

        def preview_row?
          @options[:show_unit_price] || @options.key?(:unit_price) || @options[:preview].respond_to?(:call)
        rescue
          false
        end

        def value_text
          if at_max? && @options[:show_max_label]
            "MAX (#{@value})#{@options[:value_suffix]}"
          else
            "#{@options[:value_prefix]}#{@value}#{@options[:value_suffix]}"
          end
        end

        def at_max?
          @value == @options[:max]
        end

        def notify_change
          callback = @options[:on_change]
          callback.call(@value) if callback.respond_to?(:call)
        rescue Exception => e
          PopupWindow.log_exception("NumberPicker change callback failed", e) if defined?(PopupWindow)
        end

        def controls_triggered?
          defined?(Reloaded::HintText) && Reloaded::HintText.triggered?
        rescue
          false
        end

        def show_controls_popup
          return unless defined?(Reloaded::HintText)
          entries = [
            Reloaded::HintText.confirm("Choose"),
            Reloaded::HintText.back,
            Reloaded::HintText.other("Step", "Up/Down"),
            Reloaded::HintText.other("Large Step", :page)
          ]
          entries << Reloaded::HintText.action("Maximum") if @options[:allow_max_shortcut]
          Reloaded::HintText.open_popup("Controls", entries)
          draw
        rescue Exception => e
          PopupWindow.log_exception("NumberPicker controls popup failed", e) if defined?(PopupWindow)
        end

        def max_shortcut_triggered?
          @options[:allow_max_shortcut] && Input.const_defined?(:ACTION) && Input.trigger?(Input::ACTION)
        rescue
          false
        end

        def mouse_scroll
          value = Input.scroll_v.to_i rescue 0
          return value unless value == 0
          return 1 if Input.const_defined?(:SCROLLUP) && (Input.repeat?(Input::SCROLLUP) rescue false)
          return -1 if Input.const_defined?(:SCROLLDOWN) && (Input.repeat?(Input::SCROLLDOWN) rescue false)
          0
        rescue
          0
        end

        def mouse_left_triggered?
          Input.const_defined?(:MOUSELEFT) && Input.trigger?(Input::MOUSELEFT)
        rescue
          false
        end

        def mouse_right_triggered?
          Input.const_defined?(:MOUSERIGHT) && Input.trigger?(Input::MOUSERIGHT)
        rescue
          false
        end

        def draw_selection(bitmap, x, y, width, height)
          fill = pulsing_cursor_fill
          border = cursor_border
          if respond_to?(:reloaded_draw_rounded_rect)
            reloaded_draw_rounded_rect(bitmap, x, y, width, height, 4, fill, border)
          else
            PopupWindow.draw_rounded_rect(bitmap, x, y, width, height, 4, fill)
          end
        end

        def plain_text(bitmap, x, y, width, height, text, color, align = 0)
          draw_x = x
          draw_align = 0
          case align
          when 1
            draw_x = x + width / 2
            draw_align = 2
          when 2
            draw_x = x + width
            draw_align = 1
          end
          pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y, draw_align, color, PopupWindow::TRANSPARENT]])
        rescue
        end

        def pulsing_cursor_fill
          base = respond_to?(:reloaded_cursor_fill) ? reloaded_cursor_fill : Color.new(100, 160, 220, 160)
          pulse = Math.sin((Graphics.frame_count rescue 0) * Math::PI / 20.0) * 0.5 + 0.5
          alpha = [[base.alpha.to_i + (pulse * 55).to_i, 255].min, 80].max
          Color.new(base.red, base.green, base.blue, alpha)
        rescue
          Color.new(100, 160, 220, 160)
        end

        def cursor_border
          respond_to?(:reloaded_cursor_border) ? reloaded_cursor_border : Color.new(60, 120, 180, 220)
        rescue
          Color.new(60, 120, 180, 220)
        end

        def fit_text(bitmap, text, width)
          value = text.to_s
          return value if bitmap.text_size(value).width <= width
          value = value[0...-1].to_s while !value.empty? && bitmap.text_size(value + "...").width > width
          value + "..."
        rescue
          text.to_s
        end

        def pulse_redraw?
          ((Graphics.frame_count rescue 0) % 4) == 0
        end

        def drain_input
          2.times { Input.update rescue nil }
          30.times do
            held = (Input.press?(Input::USE) rescue false) || (Input.press?(Input::BACK) rescue false)
            break unless held
            Graphics.update rescue nil
            Input.update rescue nil
          end
        rescue
        end

        def dispose
          @sprites.each_value do |sprite|
            sprite.bitmap.dispose rescue nil
            sprite.dispose rescue nil
          end
          @sprites.clear
          @viewport.dispose rescue nil
        rescue
        end
      end

      class ConfirmationScene < PickerScene
        def initialize(title, options)
          super
          @selected_choice = options[:default] == false ? 1 : 0
        end

        def main
          setup
          draw
          loop do
            Graphics.update
            Input.update
            draw if pulse_redraw?
            if controls_triggered?
              show_confirmation_controls
            elsif Input.trigger?(Input::BACK)
              pbPlayCancelSE rescue nil
              return false
            elsif Input.trigger?(Input::USE)
              pbPlayDecisionSE rescue nil
              return @selected_choice == 0
            elsif Input.trigger?(Input::UP)
              move_choice(-1)
            elsif Input.trigger?(Input::DOWN)
              move_choice(1)
            end
            mouse_result = update_confirmation_mouse
            return mouse_result unless mouse_result == :continue
          end
        ensure
          dispose
          drain_input
        end

        def choice_count
          2
        end

        def draw_choice_rows(bitmap)
          [_INTL("Yes"), _INTL("No")].each_with_index do |label, index|
            y = @choice_y + index * CHOICE_H
            draw_selection(bitmap, 12, y, @w - 24, CHOICE_H) if index == @selected_choice
            plain_text(bitmap, 20, y - 6, @w - 40, CHOICE_H, label, index == @selected_choice ? @theme[:text] : @theme[:dim], 0)
          end
        end

        def move_choice(amount)
          @selected_choice = (@selected_choice + amount.to_i) % choice_count
          pbPlayCursorSE rescue nil
          draw
        end

        def update_confirmation_mouse
          position = Reloaded::MouseInput.active_position rescue nil
          return :continue unless position
          local_x = position[0].to_i - @x
          local_y = position[1].to_i - @y
          if mouse_right_triggered?
            pbPlayCancelSE rescue nil
            return false
          end
          return :continue unless local_x >= 12 && local_x < @w - 12
          index = (local_y - @choice_y) / CHOICE_H
          return :continue unless index >= 0 && index < choice_count
          if index != @selected_choice
            @selected_choice = index
            pbPlayCursorSE rescue nil
            draw
          end
          if mouse_left_triggered?
            pbPlayDecisionSE rescue nil
            return @selected_choice == 0
          end
          :continue
        rescue
          :continue
        end

        def show_confirmation_controls
          return unless defined?(Reloaded::HintText)
          Reloaded::HintText.open_popup("Controls", [
            Reloaded::HintText.confirm("Choose"),
            Reloaded::HintText.back,
            Reloaded::HintText.other("Select", "Up/Down")
          ])
          draw
        rescue Exception => e
          PopupWindow.log_exception("NumberPicker confirmation controls failed", e) if defined?(PopupWindow)
        end
      end
    end
  end

  NumberPicker = API::NumberPicker unless const_defined?(:NumberPicker, false)

  class << self
    def number_picker(title, options = {})
      NumberPicker.open(title, options)
    end

    def quantity_picker(title, options = {})
      NumberPicker.quantity(title, options)
    end
  end
end
