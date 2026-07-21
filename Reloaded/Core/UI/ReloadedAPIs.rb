#======================================================
# Reloaded APIs
# Author: Stonewall
#======================================================
# Public helper APIs for Reloaded-owned systems and mods.
#
# Responsibilities:
#   - Provide a shared HR-style popup window API.
#   - Keep popup input isolated from the scene behind it.
#   - Give modders a stable, documented helper instead of copied UI code.
#
#======================================================

module Reloaded
  module MouseInput
    class << self
      def active_position
        frame = Graphics.frame_count rescue 0
        position = raw_position
        return nil unless position
        mx, my = position
        if @last_x.nil? || @last_y.nil?
          @last_x = mx
          @last_y = my
          @active_frame = frame if mouse_activity?
          return @active_frame == frame ? [mx, my] : nil
        end
        moved = mx != @last_x || my != @last_y
        @last_x = mx
        @last_y = my
        if command_triggered?
          @active_frame = -1
        elsif moved || mouse_activity?
          @active_frame = frame
        end
        @active_frame == frame ? [mx, my] : nil
      rescue
        nil
      end

      def raw_position
        mx = Input.mouse_x rescue nil
        my = Input.mouse_y rescue nil
        return [mx, my] if !mx.nil? && !my.nil?
        position = Mouse.getMousePos rescue nil
        position.is_a?(Array) ? position : nil
      rescue
        nil
      end

      def command_triggered?
        command_inputs.any? { |key| Input.trigger?(key) rescue false }
      rescue
        false
      end

      def command_inputs
        names = [:UP, :DOWN, :LEFT, :RIGHT, :USE, :BACK, :ACTION, :SPECIAL, :L, :R, :Y]
        names.map { |name| Input.const_get(name) if Input.const_defined?(name) }.compact.uniq
      rescue
        []
      end

      def mouse_activity?
        return true if mouse_button_active?(:MOUSELEFT)
        return true if mouse_button_active?(:MOUSERIGHT)
        return true if (Input.scroll_v.to_i rescue 0) != 0
        return true if Input.const_defined?(:SCROLLUP) && (Input.repeat?(Input::SCROLLUP) rescue false)
        return true if Input.const_defined?(:SCROLLDOWN) && (Input.repeat?(Input::SCROLLDOWN) rescue false)
        false
      rescue
        false
      end

      def mouse_button_active?(name)
        return false unless Input.const_defined?(name)
        key = Input.const_get(name)
        (Input.trigger?(key) rescue false) || (Input.press?(key) rescue false)
      rescue
        false
      end
    end
  end

  module API
    module PopupWindow
      SCREEN_W = 512
      SCREEN_H = 384
      MAX_W = (SCREEN_W * 3 / 4)
      MAX_H = (SCREEN_H * 3 / 4)
      MIN_W = 220
      MIN_H = 84
      PAD = 14
      ROW_H = 24
      LINE_H = 24
      MESSAGE_LINE_H = 26
      HEADER_H = 22
      FOOTER_H = 24
      TEXT_SAFETY_PAD = 12
      LIST_JUMP = 3
      PANEL_RADIUS = 5

      WHITE = Color.new(255, 255, 255)
      GRAY = Color.new(175, 180, 200)
      DIM = Color.new(105, 110, 135)
      BLUE = Color.new(120, 190, 255)
      GREEN = Color.new(105, 224, 164)
      RED = Color.new(235, 96, 116)
      GOLD = Color.new(240, 200, 80)
      ORANGE = Color.new(244, 157, 88)
      PANEL_BG = Color.new(8, 14, 28, 235)
      PANEL_BORDER = Color.new(60, 80, 130)
      DIM_BG = Color.new(0, 0, 0, 120)
      TRANSPARENT = Color.new(0, 0, 0, 0)

      THEMES = {
        :hr => {
          :title => BLUE,
          :text => WHITE,
          :dim => GRAY,
          :border => PANEL_BORDER,
          :background => PANEL_BG
        },
        :success => {
          :title => GREEN,
          :text => GREEN,
          :dim => GRAY,
          :border => Color.new(50, 150, 90),
          :background => PANEL_BG
        },
        :warning => {
          :title => GOLD,
          :text => GOLD,
          :dim => GRAY,
          :border => Color.new(180, 135, 40),
          :background => PANEL_BG
        },
        :error => {
          :title => RED,
          :text => RED,
          :dim => GRAY,
          :border => Color.new(180, 60, 70),
          :background => PANEL_BG
        }
      }

      class << self
        def modal_active?
          @modal_depth.to_i > 0
        rescue
          false
        end

        def with_modal
          @modal_depth = @modal_depth.to_i + 1
          yield
        ensure
          @modal_depth = [@modal_depth.to_i - 1, 0].max
        end

        def message(text, options = {})
          with_modal { PopupScene.new(:message, text, [], normalize_options(options)).main }
          true
        rescue Exception => e
          log_exception("PopupWindow message failed", e)
          fallback_message(text)
          true
        end

        def confirm(text, options = {})
          opts = normalize_options(options)
          default_yes = !!opts[:default]
          commands = [
            { :label => opts[:yes_label] || _INTL("Yes"), :value => true },
            { :label => opts[:no_label] || _INTL("No"), :value => false }
          ]
          rows = normalize_rows(commands, false)
          result = with_modal { PopupScene.new(:choice, text, rows, opts.merge(:start_index => default_yes ? 0 : 1)).main }
          result == true
        rescue Exception => e
          log_exception("PopupWindow confirm failed", e)
          fallback_confirm(text)
        end

        def choice(title, commands, options = {})
          opts = normalize_options(options)
          rows = normalize_rows(commands, opts.key?(:add_back) ? opts[:add_back] : true)
          with_modal { PopupScene.new(:choice, title, rows, opts).main }
        rescue Exception => e
          log_exception("PopupWindow choice failed", e)
          -1
        end

        def command(title, commands, options = {})
          opts = normalize_options(options)
          rows = normalize_rows(commands, opts.key?(:add_back) ? opts[:add_back] : true)
          result = with_modal { PopupScene.new(:choice, title, rows, opts).main }
          row = rows.find { |entry| entry[:return_value] == result || entry[:value] == result }
          if row && row[:proc]
            safe_call(row[:proc], title)
          else
            result
          end
        rescue Exception => e
          log_exception("PopupWindow command failed", e)
          -1
        end

        def async(text, options = {})
          AsyncPopup.new(text, normalize_options(options))
        rescue Exception => e
          log_exception("PopupWindow async failed", e)
          nil
        end

        alias async_message async

        def draw_panel(bitmap, width, height, theme, helper = nil)
          background = theme[:background] || PANEL_BG
          border = theme[:border] || PANEL_BORDER
          if width > 4 && height > 4
            draw_rounded_rect(bitmap, 0, 0, width, height, PANEL_RADIUS, border)
            draw_rounded_rect(bitmap, 1, 1, width - 2, height - 2, [PANEL_RADIUS - 1, 1].max, background)
          else
            bitmap.fill_rect(0, 0, width, height, background)
            bitmap.fill_rect(0, 0, width, 1, border)
            bitmap.fill_rect(0, height - 1, width, 1, border)
            bitmap.fill_rect(0, 0, 1, height, border)
            bitmap.fill_rect(width - 1, 0, 1, height, border)
          end
        rescue
          bitmap.fill_rect(0, 0, width, height, PANEL_BG) rescue nil
        end

        def draw_rounded_rect(bitmap, x, y, width, height, radius, color)
          radius = [radius.to_i, width / 2, height / 2].min
          return bitmap.fill_rect(x, y, width, height, color) if radius <= 0
          bitmap.fill_rect(x + radius, y, width - radius * 2, height, color)
          bitmap.fill_rect(x, y + radius, radius, height - radius * 2, color)
          bitmap.fill_rect(x + width - radius, y + radius, radius, height - radius * 2, color)
          draw_quarter_circle(bitmap, x + radius, y + radius, radius, color, :top_left)
          draw_quarter_circle(bitmap, x + width - radius - 1, y + radius, radius, color, :top_right)
          draw_quarter_circle(bitmap, x + radius, y + height - radius - 1, radius, color, :bottom_left)
          draw_quarter_circle(bitmap, x + width - radius - 1, y + height - radius - 1, radius, color, :bottom_right)
        rescue
          bitmap.fill_rect(x, y, width, height, color) rescue nil
        end

        def draw_quarter_circle(bitmap, center_x, center_y, radius, color, corner)
          (0..radius).each do |dx|
            (0..radius).each do |dy|
              next unless dx * dx + dy * dy <= radius * radius
              px = center_x + ([:top_right, :bottom_right].include?(corner) ? dx : -dx)
              py = center_y + ([:bottom_left, :bottom_right].include?(corner) ? dy : -dy)
              bitmap.fill_rect(px, py, 1, 1, color)
            end
          end
        rescue
        end

        def safe_call(callable, context = nil)
          callable.call
        rescue Exception => e
          label = context ? "PopupWindow command failed for #{context}" : "PopupWindow command failed"
          log_exception(label, e)
          message(_INTL("That action failed."), :theme => :error) rescue nil
          nil
        end

        def normalize_options(options)
          opts = {}
          (options || {}).each { |key, value| opts[key] = value } rescue nil
          opts[:theme] = (opts[:theme] || :hr).to_sym rescue :hr
          opts[:theme] = :hr unless THEMES[opts[:theme]]
          opts[:wrap] = true unless opts.key?(:wrap)
          opts[:show_dim] = true unless opts.key?(:show_dim)
          opts[:z] = opts[:z] || 999_999_999
          opts[:start_index] = opts[:start_index].to_i if opts.key?(:start_index)
          opts
        end

        def normalize_rows(commands, add_back = false)
          rows = []
          Array(commands).each_with_index do |command, i|
            rows << normalize_row(command, i)
          end
          if add_back && !rows.any? { |row| row[:back] }
            rows << {
              :label => _INTL("Back"),
              :value => -1,
              :return_value => -1,
              :back => true,
              :selectable => true,
              :source_index => rows.length
            }
          end
          rows
        end

        def normalize_row(command, index)
          if command.is_a?(Hash)
            label = command[:label] || command["label"] || command[:text] || command["text"] || command[:name] || command["name"] || ""
            header = command[:header] || command["header"] || command[:section] || command["section"]
            disabled = command[:disabled] || command["disabled"]
            back = command[:back] || command["back"]
            align = command.key?(:align) ? command[:align] : command["align"]
            value = command.key?(:value) ? command[:value] : command["value"]
            value = index if value.nil?
            selectable = command.key?(:selectable) ? command[:selectable] : command["selectable"]
            selectable = !header && !disabled if selectable.nil?
            {
              :label => label.to_s,
              :value => value,
              :return_value => value,
              :proc => command[:proc] || command["proc"] || command[:action] || command["action"],
              :header => !!header,
              :disabled => !!disabled,
              :disabled_reason => command[:disabled_reason] || command["disabled_reason"] || command[:reason] || command["reason"],
              :back => !!back,
              :align => align.nil? ? nil : align.to_i,
              :selectable => !!selectable,
              :source_index => index,
              :input => command[:input] || command["input"],
              :kind => command[:kind] || command["kind"],
              :color => command[:color] || command["color"]
            }
          elsif command.is_a?(Array)
            label = command[0].to_s
            action = command[1]
            value = command.length > 2 ? command[2] : index
            {
              :label => label,
              :value => value,
              :return_value => value,
              :proc => action.respond_to?(:call) ? action : nil,
              :header => false,
              :disabled => false,
              :disabled_reason => nil,
              :back => value == -1,
              :align => nil,
              :selectable => true,
              :source_index => index,
              :input => nil,
              :kind => nil,
              :color => nil
            }
          else
            {
              :label => command.to_s,
              :value => index,
              :return_value => index,
              :header => false,
              :disabled => false,
              :disabled_reason => nil,
              :back => false,
              :align => nil,
              :selectable => true,
              :source_index => index,
              :input => nil,
              :kind => nil,
              :color => nil
            }
          end
        end

        def log_exception(message, error)
          if defined?(Reloaded::Log)
            Reloaded::Log.error("#{message}: #{error.class}: #{error}", :api)
            Reloaded::Log.debug(Array(error.backtrace).first(6).join("\n"), :api) rescue nil
          end
        rescue
        end

        def fallback_message(text)
          Kernel.pbMessage(text.to_s) if defined?(Kernel.pbMessage)
        rescue
        end

        def fallback_confirm(text)
          return false unless defined?(Kernel.pbMessage)
          Kernel.pbMessage(text.to_s, [_INTL("No"), _INTL("Yes")], 0) == 1
        rescue
          false
        end
      end

      class PopupScene
        include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

        def initialize(kind, title, rows, options)
          @kind = kind
          @title = title.to_s
          @rows = Array(rows)
          @options = options || {}
          @theme = THEMES[@options[:theme]] || THEMES[:hr]
          @selected = first_selectable_index(@options[:start_index] || 0)
          @scroll = 0
          @text_scroll = 0
          @sprites = {}
        end

        def main
          setup
          draw
          loop do
            unless update_frame
              return -1 if @update_failures.to_i >= 3
              next
            end
            draw if pulse_redraw?
            if choice_mode?
              result = update_choice
            else
              result = update_message
            end
            return result unless result == :continue
          end
        ensure
          dispose
          drain_input
        end

        def update_frame
          Graphics.update
          Input.update
          @update_failures = 0
          true
        rescue Exception
          @update_failures = @update_failures.to_i + 1
          false
        end

        def setup
          @viewport = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
          @viewport.z = @options[:z].to_i
          @sprites["dim"] = Sprite.new(@viewport)
          @sprites["dim"].bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
          @sprites["dim"].bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, DIM_BG) if @options[:show_dim]
          calculate_layout
          @sprites["popup"] = Sprite.new(@viewport)
          @sprites["popup"].x = @x
          @sprites["popup"].y = @y
          @sprites["popup"].z = @options[:z].to_i
          @sprites["popup"].bitmap = Bitmap.new(@w, @h)
        end

        def calculate_layout
          measure = Bitmap.new(1, 1)
          pbSetSmallFont(measure) rescue nil
          title_width = measure.text_size(@title).width + PAD * 2 + TEXT_SAFETY_PAD rescue MIN_W
          text_width = @options[:width] ? @options[:width].to_i : [title_width, MIN_W].max
          text_width = [[text_width, MIN_W].max, MAX_W].min
          @message_lines = wrap_lines(measure, @title, text_width - PAD * 2)
          row_width = @rows.map { |row| measure.text_size(row[:label].to_s).width + PAD * 2 + TEXT_SAFETY_PAD rescue MIN_W }.max || MIN_W
          row_width = [row_width, @options[:row_width].to_i].max if @options[:row_width].to_i > 0
          @w = [[text_width, row_width, MIN_W].max, MAX_W].min
          @message_lines = wrap_lines(measure, @title, @w - PAD * 2)
          message_line_h = choice_mode? ? LINE_H : MESSAGE_LINE_H
          message_h = [@message_lines.length * message_line_h, message_line_h].max
          rows_h = choice_mode? ? @rows.length * ROW_H : 0
          message_gap = choice_mode? ? 4 : 12
          desired_h = (choice_mode? ? 4 : PAD) + message_h + message_gap + rows_h + PAD
          @h = [[desired_h, MIN_H].max, MAX_H].min
          @content_y = choice_mode? ? 4 : PAD
          @rows_y = @content_y + message_h + 4
          @visible_rows = choice_mode? ? [((@h - @rows_y - PAD) / ROW_H), 1].max : 0
          @visible_text_lines = choice_mode? ? @message_lines.length : [((@h - PAD * 2 - message_gap) / MESSAGE_LINE_H), 1].max
          @x = (SCREEN_W - @w) / 2
          @y = (SCREEN_H - @h) / 2
          measure.dispose rescue nil
        end

        def draw
          bitmap = @sprites["popup"].bitmap
          bitmap.clear
          draw_panel(bitmap)
          pbSetSmallFont(bitmap) rescue nil
          if choice_mode?
            draw_choice_title(bitmap)
            draw_rows(bitmap)
          else
            draw_message_text(bitmap)
          end
        end

        def draw_panel(bitmap)
          PopupWindow.draw_panel(bitmap, bitmap.width, bitmap.height, @theme, self)
        end

        def draw_choice_title(bitmap)
          draw_wrapped_lines(bitmap, @message_lines, 10, @content_y - 4, @w - 20, @theme[:title], 1)
        end

        def draw_message_text(bitmap)
          lines = @message_lines[@text_scroll, @visible_text_lines] || []
          y = PAD
          align = @options[:center_text] ? 1 : 0
          lines.each do |line|
            plain_text(bitmap, PAD, y, @w - PAD * 2, MESSAGE_LINE_H, line, @theme[:text], align)
            y += MESSAGE_LINE_H
          end
          draw_scroll_markers(bitmap, @message_lines.length, @visible_text_lines, @text_scroll)
        end

        def draw_rows(bitmap)
          if read_only_scroller?
            draw_read_only_rows(bitmap)
            return
          end
          ensure_visible
          visible = @rows[@scroll, @visible_rows] || []
          visible.each_with_index do |row, local_index|
            index = @scroll + local_index
            y = @rows_y + local_index * ROW_H
            if index == @selected
              draw_selection(bitmap, 10, y + 2, @w - 20, 20, pulsing_cursor_fill, cursor_border)
            end
            if render_custom_row(bitmap, row, index, y)
              next
            end
            color = row_color(row, index == @selected)
            align = row[:align].nil? ? (row[:header] ? 1 : 0) : row[:align].to_i
            x = row[:header] || align == 1 ? 12 : 18
            width = @w - x - 18
            plain_text(bitmap, x, y - 5, width, 22, row[:label], color, align)
          end
          draw_scroll_markers(bitmap, @rows.length, @visible_rows, @scroll)
        end

        def draw_read_only_rows(bitmap)
          visible_count = content_visible_rows
          content = read_only_content_indices
          visible = content[@scroll, visible_count] || []
          visible.each_with_index do |index, local_index|
            draw_row(bitmap, @rows[index], index, @rows_y + local_index * ROW_H)
          end
          draw_row(bitmap, @rows[@selected], @selected, @rows_y + visible_count * ROW_H) if @rows[@selected]
          draw_scroll_markers(bitmap, content.length, visible_count, @scroll)
        end

        def draw_row(bitmap, row, index, y)
          if index == @selected
            draw_selection(bitmap, 10, y + 2, @w - 20, 20, pulsing_cursor_fill, cursor_border)
          end
          return if render_custom_row(bitmap, row, index, y)
          color = row_color(row, index == @selected)
          align = row[:align].nil? ? (row[:header] ? 1 : 0) : row[:align].to_i
          x = row[:header] || align == 1 ? 12 : 18
          width = @w - x - 18
          plain_text(bitmap, x, y - 5, width, 22, row[:label], color, align)
        end

        def render_custom_row(bitmap, row, index, y)
          renderer = @options[:row_renderer]
          return false unless renderer.respond_to?(:call)
          bounds = {
            :x => 10,
            :y => y,
            :width => @w - 20,
            :height => ROW_H,
            :selected => index == @selected,
            :row_index => index,
            :scroll => @scroll
          }
          renderer.call(bitmap, row, bounds) == true
        rescue
          false
        end

        def draw_scroll_markers(bitmap, total, visible, scroll)
          return if total <= visible
          plain_text(bitmap, @w - 16, 5, 12, 16, "^", @theme[:dim], 1) if scroll > 0
          plain_text(bitmap, @w - 16, @h - 22, 12, 16, "v", @theme[:dim], 1) if scroll + visible < total
        end

        def update_message
          if Input.repeat?(Input::UP) || Input.repeat?(Input::LEFT)
            scroll_text(-1)
          elsif Input.repeat?(Input::DOWN) || Input.repeat?(Input::RIGHT)
            scroll_text(1)
          elsif Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
            pbPlayDecisionSE rescue nil
            return true
          end
          :continue
        end

        def update_choice
          old = @selected
          old_scroll = @scroll
          mouse_result = update_choice_mouse
          return mouse_result unless mouse_result == :continue
          if read_only_scroller? && Input.repeat?(Input::UP)
            scroll_rows(-1)
          elsif read_only_scroller? && Input.repeat?(Input::DOWN)
            scroll_rows(1)
          elsif read_only_scroller? && Input.repeat?(Input::LEFT)
            scroll_rows(-LIST_JUMP)
          elsif read_only_scroller? && Input.repeat?(Input::RIGHT)
            scroll_rows(LIST_JUMP)
          elsif Input.repeat?(Input::UP)
            move_selection(-1)
          elsif Input.repeat?(Input::DOWN)
            move_selection(1)
          elsif Input.repeat?(Input::LEFT)
            move_selection(-LIST_JUMP)
          elsif Input.repeat?(Input::RIGHT)
            move_selection(LIST_JUMP)
          elsif Input.trigger?(Input::USE)
            row = @rows[@selected]
            if row && row[:selectable]
              if row[:disabled]
                show_disabled_reason(row)
              else
                pbPlayDecisionSE rescue nil
                return row[:return_value]
              end
            else
              pbPlayBuzzerSE rescue nil
            end
          elsif Input.trigger?(Input::BACK)
            pbPlayCancelSE rescue nil
            return -1
          end
          if old != @selected
            pbPlayCursorSE rescue nil
            draw
          elsif old_scroll != @scroll
            pbPlayCursorSE rescue nil
            draw
          end
          :continue
        end

        def update_choice_mouse
          if (Input.repeat?(Input::SCROLLUP) rescue false)
            read_only_scroller? ? scroll_rows(-1) : move_selection(-1)
            pbPlayCursorSE rescue nil
            draw
            return :continue
          elsif (Input.repeat?(Input::SCROLLDOWN) rescue false)
            read_only_scroller? ? scroll_rows(1) : move_selection(1)
            pbPlayCursorSE rescue nil
            draw
            return :continue
          end
          pos = Reloaded::MouseInput.active_position
          return :continue unless pos.is_a?(Array)
          local_x = pos[0].to_i - @x
          local_y = pos[1].to_i - @y
          return :continue if local_x < 0 || local_x >= @w
          index = mouse_row_index(local_y)
          return :continue if index.nil?
          row = @rows[index]
          return :continue unless row && row[:selectable]
          if index != @selected
            @selected = index
            ensure_visible
            pbPlayCursorSE rescue nil
            draw
          end
          if (Input.trigger?(Input::MOUSELEFT) rescue false)
            if row[:disabled]
              show_disabled_reason(row)
            else
              pbPlayDecisionSE rescue nil
              return row[:return_value]
            end
          end
          :continue
        rescue
          :continue
        end

        def mouse_row_index(local_y)
          return nil if local_y < @rows_y
          local = (local_y - @rows_y) / ROW_H
          if read_only_scroller?
            visible_count = content_visible_rows
            return @selected if local == visible_count
            return nil if local < 0 || local >= visible_count
            read_only_content_indices[@scroll + local]
          else
            return nil if local < 0 || local >= @visible_rows
            index = @scroll + local
            index < @rows.length ? index : nil
          end
        rescue
          nil
        end

        def move_selection(amount)
          return if selectable_indices.empty?
          indices = selectable_indices
          pos = indices.index(@selected) || 0
          pos = (pos + amount) % indices.length
          @selected = indices[pos]
          ensure_visible
        end

        def scroll_text(amount)
          max = [@message_lines.length - @visible_text_lines, 0].max
          old = @text_scroll
          @text_scroll = [[@text_scroll + amount, 0].max, max].min
          if old != @text_scroll
            pbPlayCursorSE rescue nil
            draw
          end
        end

        def scroll_rows(amount)
          if read_only_scroller?
            max = [read_only_content_indices.length - content_visible_rows, 0].max
          else
            max = [@rows.length - @visible_rows, 0].max
          end
          @scroll = [[@scroll + amount.to_i, 0].max, max].min
        rescue
        end

        def ensure_visible
          return unless choice_mode?
          @scroll = @selected if @selected < @scroll
          @scroll = @selected - @visible_rows + 1 if @selected >= @scroll + @visible_rows
          @scroll = [[@scroll, 0].max, [@rows.length - @visible_rows, 0].max].min
        end

        def selectable_indices
          @selectable_indices ||= @rows.each_index.select { |i| @rows[i][:selectable] }
        end

        def read_only_scroller?
          choice_mode? && @rows.length > @visible_rows && selectable_indices.length <= 1
        rescue
          false
        end

        def content_visible_rows
          [@visible_rows - 1, 1].max
        rescue
          1
        end

        def read_only_content_indices
          @rows.each_index.reject { |index| index == @selected }
        rescue
          []
        end

        def first_selectable_index(preferred)
          indices = @rows.each_index.select { |i| @rows[i][:selectable] }
          return 0 if indices.empty?
          preferred = preferred.to_i
          return preferred if indices.include?(preferred)
          indices.find { |i| i >= preferred } || indices.first
        end

        def row_color(row, selected)
          return @theme[:title] if row[:header]
          return DIM if row[:disabled]
          selected ? WHITE : GRAY
        end

        def show_disabled_reason(row)
          pbPlayBuzzerSE rescue nil
          reason = row[:disabled_reason].to_s.strip
          reason = _INTL("This action is unavailable.") if reason.empty?
          if defined?(Reloaded::Toast) && Reloaded::Toast.respond_to?(:warning)
            Reloaded::Toast.warning(reason)
          else
            PopupWindow.message(reason, :theme => :warning)
          end
          draw
          :continue
        rescue
          :continue
        end

        def choice_mode?
          @kind == :choice
        end

        def pulse_redraw?
          ((Graphics.frame_count rescue 0) % 4) == 0
        end

        def wrap_lines(bitmap, text, width)
          value = text.to_s.gsub("\r\n", "\n")
          lines = []
          value.split("\n").each do |paragraph|
            if paragraph.empty?
              lines << ""
              next
            end
            current = ""
            paragraph.split(" ").each do |word|
              test = current.empty? ? word : "#{current} #{word}"
              if bitmap.text_size(test).width > width && !current.empty?
                lines << current
                current = word
              else
                current = test
              end
            end
            lines << current unless current.empty?
          end
          lines.empty? ? [""] : lines
        rescue
          [text.to_s]
        end

        def draw_wrapped_lines(bitmap, lines, x, y, width, color, align = 0)
          Array(lines).each do |line|
            plain_text(bitmap, x, y, width, LINE_H, line, color, align)
            y += LINE_H
          end
        end

        def draw_selection(bitmap, x, y, w, h, fill, border = nil)
          if respond_to?(:reloaded_draw_rounded_rect)
            reloaded_draw_rounded_rect(bitmap, x, y, w, h, 4, fill, border)
          else
            bitmap.fill_rect(x, y, w, h, fill)
            return unless border
            bitmap.fill_rect(x, y, w, 1, border)
            bitmap.fill_rect(x, y + h - 1, w, 1, border)
            bitmap.fill_rect(x, y, 1, h, border)
            bitmap.fill_rect(x + w - 1, y, 1, h, border)
          end
        end

        def pulsing_cursor_fill
          base = cursor_fill
          pulse = Math.sin((Graphics.frame_count rescue 0) * Math::PI / 20.0) * 0.5 + 0.5
          alpha = [[base.alpha.to_i + (pulse * 55).to_i, 255].min, 80].max
          Color.new(base.red, base.green, base.blue, alpha)
        rescue
          Color.new(100, 160, 220, 160)
        end

        def cursor_fill
          respond_to?(:reloaded_cursor_fill) ? reloaded_cursor_fill : Color.new(100, 160, 220, 160)
        end

        def cursor_border
          respond_to?(:reloaded_cursor_border) ? reloaded_cursor_border : Color.new(60, 120, 180, 220)
        end

        def plain_text(bitmap, x, y, w, h, text, color, align = 0)
          draw_x = x
          draw_align = 0
          case align
          when 1
            draw_x = x + w / 2
            draw_align = 2
          when 2
            draw_x = x + w
            draw_align = 1
          end
          pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y, draw_align, color, TRANSPARENT]])
        rescue
        end

        def drain_input
          2.times do
            begin
              Input.update
            rescue Exception
              break
            end
          end
          30.times do
            confirm_held = (Input.press?(Input::USE) rescue false)
            back_held = (Input.press?(Input::BACK) rescue false)
            break unless confirm_held || back_held
            Graphics.update rescue nil
            Input.update rescue nil
          end
        rescue Exception
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

      class AsyncPopup
        include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

        def initialize(text, options = {})
          @options = options || {}
          @theme = THEMES[@options[:theme]] || THEMES[:hr]
          @text = text.to_s
          @closed = false
          setup
          draw
        end

        def update(text = nil)
          return false if @closed
          @text = text.to_s if text
          Graphics.update rescue nil
          Input.update rescue nil
          draw
          true
        rescue Exception => e
          PopupWindow.log_exception("PopupWindow async update failed", e)
          false
        end

        def close
          return if @closed
          @closed = true
          dispose
          drain_input
        rescue
        end

        def closed?
          @closed
        end

        def setup
          @viewport = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
          @viewport.z = @options[:z].to_i
          @sprites = {}
          @sprites["dim"] = Sprite.new(@viewport)
          @sprites["dim"].bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
          @sprites["dim"].bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, DIM_BG) if @options[:show_dim]
          @w = [[@options[:width].to_i, MIN_W].max, MAX_W].min rescue 280
          @w = 280 if @w <= 0
          @h = 96
          @x = (SCREEN_W - @w) / 2
          @y = (SCREEN_H - @h) / 2
          @sprites["popup"] = Sprite.new(@viewport)
          @sprites["popup"].x = @x
          @sprites["popup"].y = @y
          @sprites["popup"].bitmap = Bitmap.new(@w, @h)
        end

        def draw
          bitmap = @sprites["popup"].bitmap
          bitmap.clear
          PopupWindow.draw_panel(bitmap, @w, @h, @theme, self)
          pbSetSmallFont(bitmap) rescue nil
          lines = wrap_lines(bitmap, @text, @w - PAD * 2)
          y = PAD
          lines.first(3).each do |line|
            plain_text(bitmap, PAD, y, @w - PAD * 2, LINE_H, line, @theme[:text], 1)
            y += LINE_H
          end
        end

        def wrap_lines(bitmap, text, width)
          lines = []
          current = ""
          text.to_s.split(" ").each do |word|
            test = current.empty? ? word : "#{current} #{word}"
            if bitmap.text_size(test).width > width && !current.empty?
              lines << current
              current = word
            else
              current = test
            end
          end
          lines << current unless current.empty?
          lines.empty? ? [""] : lines
        rescue
          [text.to_s]
        end

        def plain_text(bitmap, x, y, w, h, text, color, align = 0)
          draw_x = x
          draw_align = 0
          case align
          when 1
            draw_x = x + w / 2
            draw_align = 2
          when 2
            draw_x = x + w
            draw_align = 1
          end
          pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y, draw_align, color, TRANSPARENT]])
        rescue
        end

        def drain_input
          2.times do
            begin
              Input.update
            rescue Exception
              break
            end
          end
        rescue Exception
        end

        def dispose
          @sprites.each_value do |sprite|
            sprite.bitmap.dispose rescue nil
            sprite.dispose rescue nil
          end
          @viewport.dispose rescue nil
        rescue
        end
      end
    end

    module TextInput
      SIZE_PRESETS = {
        :compact => { :width => 360, :height => 132 },
        :standard => { :width => 384, :height => 176 },
        :large => { :width => PopupWindow::MAX_W, :height => 240 },
        :max => { :width => PopupWindow::MAX_W, :height => PopupWindow::MAX_H }
      }.freeze

      INPUT_PAD = 8
      INPUT_LINE_H = 22
      SCROLLBAR_W = 5
      INPUT_BG = Color.new(14, 34, 62, 220)
      INPUT_BORDER = Color.new(52, 100, 152)
      SELECTION_BG = Color.new(100, 160, 220, 95)

      class << self
        def open(title, options = {})
          PopupWindow.with_modal do
            InputScene.new(title, normalize_options(options)).main
          end
        rescue Exception => e
          PopupWindow.log_exception("TextInput failed", e) if defined?(PopupWindow)
          fallback_input(title, options)
        end

        def single_line(title, options = {})
          open(title, options.merge(:mode => :single_line))
        end

        def multiline(title, options = {})
          open(title, options.merge(:mode => :multiline, :size => options[:size] || :large))
        end

        def search(title, options = {})
          open(title, options.merge(:mode => :search, :size => options[:size] || :compact))
        end

        def code(title, options = {})
          opts = options.merge(:mode => :code, :size => options[:size] || :compact)
          opts[:formatter] ||= proc { |value| value.to_s.upcase }
          opts[:filter] ||= /[A-Za-z0-9_\-]/
          open(title, opts)
        end

        def url(title, options = {})
          validator = options[:validator] || proc do |value|
            text = value.to_s.strip
            text.empty? || text =~ /\Ahttps?:\/\/\S+\z/i || "Enter a valid URL."
          end
          open(title, options.merge(:mode => :url, :size => options[:size] || :large, :validator => validator))
        end

        def number(title, options = {})
          open(title, options.merge(:mode => :number, :filter => /[0-9\-]/, :size => options[:size] || :compact))
        end

        def normalize_options(options)
          opts = {}
          (options || {}).each do |key, value|
            normalized_key = key.to_sym rescue key
            opts[normalized_key] = value
          end
          opts[:mode] = (opts[:mode] || :single_line).to_sym rescue :single_line
          opts[:size] = (opts[:size] || :standard).to_sym rescue :standard
          opts[:theme] = (opts[:theme] || :hr).to_sym rescue :hr
          opts[:theme] = :hr unless PopupWindow::THEMES[opts[:theme]]
          opts[:initial] = opts[:initial].to_s
          opts[:allow_empty] = true unless opts.key?(:allow_empty)
          opts[:show_dim] = true unless opts.key?(:show_dim)
          opts[:z] = opts[:z] || 999_999_999
          opts
        end

        def fallback_input(_title, options = {})
          initial = options && options[:initial] ? options[:initial].to_s : ""
          initial
        rescue
          ""
        end
      end

      class InputScene
        include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

        def initialize(title, options)
          @title = title.to_s
          @options = options || {}
          @theme = PopupWindow::THEMES[@options[:theme]] || PopupWindow::THEMES[:hr]
          @value = @options[:initial].to_s
          @select_all = false
          @scroll = 0
          @right_scroll_dir = 0
          @right_scroll_frame = -999
          @sprites = {}
        end

        def main
          setup
          Input.text_input = true rescue nil
          draw
          loop do
            Graphics.update
            Input.update
            draw if pulse_redraw?
            scroll_input = scroll_delta
            scroll_lines(scroll_input) if scroll_input != 0
            if enter_triggered?
              if multiline? && shift_pressed?
                append_text("\n")
                draw
                next
              end
              next unless valid_for_submit?
              pbPlayDecisionSE rescue nil
              return formatted_value
            elsif escape_triggered?
              pbPlayCancelSE rescue nil
              return nil
            end
            old = @value.dup
            handle_shortcuts
            handle_delete_keys
            read_typed_chars
            if old != @value
              @scroll = max_scroll
              draw
            end
          end
        ensure
          Input.text_input = false rescue nil
          dispose
          drain_input
        end

        def setup
          calculate_layout
          @viewport = Viewport.new(0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          @viewport.z = @options[:z].to_i
          @sprites["dim"] = Sprite.new(@viewport)
          @sprites["dim"].bitmap = Bitmap.new(PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          @sprites["dim"].bitmap.fill_rect(0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H, PopupWindow::DIM_BG) if @options[:show_dim]
          @sprites["popup"] = Sprite.new(@viewport)
          @sprites["popup"].x = @x
          @sprites["popup"].y = @y
          @sprites["popup"].z = @options[:z].to_i
          @sprites["popup"].bitmap = Bitmap.new(@w, @h)
        end

        def calculate_layout
          preset = SIZE_PRESETS[@options[:size]] || SIZE_PRESETS[:standard]
          @w = [[(@options[:width] || preset[:width]).to_i, PopupWindow::MIN_W].max, PopupWindow::MAX_W].min
          @h = [[(@options[:height] || preset[:height]).to_i, PopupWindow::MIN_H].max, PopupWindow::MAX_H].min
          @x = (PopupWindow::SCREEN_W - @w) / 2
          @y = (PopupWindow::SCREEN_H - @h) / 2
          measure = Bitmap.new(1, 1)
          pbSetSmallFont(measure) rescue nil
          @title_lines = wrap_lines(measure, @title, @w - PopupWindow::PAD * 2)
          @subtitle_lines = wrap_lines(measure, @options[:subtitle].to_s, @w - PopupWindow::PAD * 2)
          @subtitle_lines = [] if @options[:subtitle].to_s.empty?
          top = PopupWindow::PAD + @title_lines.length * PopupWindow::LINE_H
          top += @subtitle_lines.length * 18 + 2 unless @subtitle_lines.empty?
          @input_x = PopupWindow::PAD
          @input_y = top + 8
          @input_w = @w - PopupWindow::PAD * 2
          @input_h = [@h - @input_y - PopupWindow::PAD, INPUT_LINE_H + INPUT_PAD * 2].max
          @visible_lines = [(@input_h - INPUT_PAD * 2) / INPUT_LINE_H, 1].max
          measure.dispose rescue nil
        end

        def draw
          bitmap = @sprites["popup"].bitmap
          bitmap.clear
          PopupWindow.draw_panel(bitmap, @w, @h, @theme, self)
          pbSetSmallFont(bitmap) rescue nil
          y = PopupWindow::PAD - 4
          @title_lines.each do |line|
            plain_text(bitmap, PopupWindow::PAD, y, @w - PopupWindow::PAD * 2, PopupWindow::LINE_H, line, @theme[:title], 1)
            y += PopupWindow::LINE_H
          end
          unless @subtitle_lines.empty?
            @subtitle_lines.each do |line|
              plain_text(bitmap, PopupWindow::PAD, y, @w - PopupWindow::PAD * 2, 18, line, @theme[:dim], 1)
              y += 18
            end
          end
          draw_input_box(bitmap)
        end

        def draw_input_box(bitmap)
          PopupWindow.draw_rounded_rect(bitmap, @input_x, @input_y, @input_w, @input_h, 4, INPUT_BORDER)
          PopupWindow.draw_rounded_rect(bitmap, @input_x + 1, @input_y + 1, @input_w - 2, @input_h - 2, 3, INPUT_BG)
          lines = wrapped_value_lines(bitmap)
          @scroll = [[@scroll, 0].max, [lines.length - @visible_lines, 0].max].min
          visible = lines[@scroll, @visible_lines] || []
          if @select_all
            visible.each_with_index do |_, index|
              sy = @input_y + INPUT_PAD + index * INPUT_LINE_H + 2
              bitmap.fill_rect(@input_x + INPUT_PAD, sy, @input_w - INPUT_PAD * 2 - scrollbar_space(lines), INPUT_LINE_H - 3, SELECTION_BG)
            end
          end
          y = @input_y + INPUT_PAD - 4
          visible.each_with_index do |line, index|
            text = line.to_s
            if @scroll + index == lines.length - 1 && cursor_visible?
              text += "|"
            end
            plain_text(bitmap, @input_x + INPUT_PAD, y, @input_w - INPUT_PAD * 2 - scrollbar_space(lines), INPUT_LINE_H, text, @theme[:text], 0)
            y += INPUT_LINE_H
          end
          draw_scrollbar(bitmap, lines.length)
        end

        def wrapped_value_lines(bitmap)
          text = @value.to_s
          text = " " if text.empty?
          wrap_lines(bitmap, text, @input_w - INPUT_PAD * 2 - SCROLLBAR_W - 4)
        end

        def draw_scrollbar(bitmap, total_lines)
          return if total_lines <= @visible_lines
          track_x = @input_x + @input_w - SCROLLBAR_W - 5
          track_y = @input_y + INPUT_PAD
          track_h = @input_h - INPUT_PAD * 2
          bitmap.fill_rect(track_x, track_y, SCROLLBAR_W, track_h, Color.new(24, 50, 82, 180))
          thumb_h = [[track_h * @visible_lines / total_lines, 12].max, track_h].min
          max_scroll_value = [total_lines - @visible_lines, 1].max
          thumb_y = track_y + ((track_h - thumb_h) * @scroll / max_scroll_value)
          bitmap.fill_rect(track_x, thumb_y, SCROLLBAR_W, thumb_h, @theme[:title])
        rescue
        end

        def scrollbar_space(lines)
          lines.length > @visible_lines ? SCROLLBAR_W + 8 : 0
        end

        def handle_shortcuts
          return unless ctrl_pressed?
          if key_trigger?(0x41) # A
            @select_all = true
          elsif key_trigger?(0x43) # C
            clipboard_write(@value)
          elsif key_trigger?(0x58) # X
            clipboard_write(@value)
            clear_selection_or_all
          elsif key_trigger?(0x56) # V
            paste = clipboard_read.to_s
            append_text(paste) unless paste.empty?
          end
        end

        def handle_delete_keys
          if key_repeat?(0x08) # Backspace
            if @select_all
              clear_selection_or_all
            else
              @value = @value[0...-1].to_s
            end
          elsif key_trigger?(0x2E) # Delete
            clear_selection_or_all if @select_all
          end
        end

        def read_typed_chars
          Input.gets.to_s.each_char do |char|
            next if char == "\r"
            next if char == "\n" && !multiline?
            next if char == "\n" && !shift_pressed?
            append_text(char)
          end
        rescue
        end

        def append_text(text)
          value = text.to_s
          value = value.gsub(/\r\n?/, "\n")
          value = value.gsub("\n", " ") unless multiline?
          value = filtered_text(value)
          return if value.empty?
          @value = "" if @select_all
          @select_all = false
          @value += value
          @value = @value[0, @options[:max_length].to_i] if @options[:max_length].to_i > 0
        end

        def filtered_text(text)
          filter = @options[:filter]
          return text unless filter
          text.each_char.select { |char| char =~ filter || (multiline? && char == "\n") }.join
        rescue
          text.to_s
        end

        def valid_for_submit?
          value = formatted_value
          if !@options[:allow_empty] && value.to_s.strip.empty?
            warning(_INTL("Enter a value."))
            return false
          end
          validator = @options[:validator]
          return true unless validator.respond_to?(:call)
          result = validator.call(value)
          return true if result == true || result.nil?
          warning(result == false ? _INTL("Check this value.") : result.to_s)
          false
        rescue Exception => e
          PopupWindow.log_exception("TextInput validation failed", e) if defined?(PopupWindow)
          warning(_INTL("Check this value."))
          false
        end

        def formatted_value
          value = @value.to_s
          formatter = @options[:formatter]
          value = formatter.call(value) if formatter.respond_to?(:call)
          @options[:strip] == false ? value : value.strip
        rescue
          @value.to_s
        end

        def warning(text)
          if defined?(Reloaded::Toast)
            Reloaded::Toast.warning(text.to_s)
          elsif defined?(Reloaded)
            Reloaded.message(text.to_s, :theme => :warning)
          end
        rescue
        end

        def clear_selection_or_all
          @value = ""
          @select_all = false
        end

        def scroll_delta
          return -1 if (Input.repeat?(Input::SCROLLUP) rescue false)
          return 1 if (Input.repeat?(Input::SCROLLDOWN) rescue false)
          return -1 if Input.repeat?(Input::UP) rescue false
          return 1 if Input.repeat?(Input::DOWN) rescue false
          return -right_stick_scroll
        rescue
          0
        end

        def right_stick_scroll
          dir = right_stick_direction
          if dir == 0
            @right_scroll_dir = 0
            return 0
          end
          frame = Graphics.frame_count rescue 0
          if @right_scroll_dir != dir
            @right_scroll_dir = dir
            @right_scroll_frame = frame
            return dir
          end
          return 0 if frame - @right_scroll_frame < 6
          @right_scroll_frame = frame
          dir
        rescue
          0
        end

        def right_stick_direction
          return 1 if right_stick_button?([:RIGHTSTICKUP, :RIGHT_STICK_UP, :RSTICKUP, :R_STICK_UP, :RUP, :RIGHT_ANALOG_UP, :ANALOG_R_UP])
          return -1 if right_stick_button?([:RIGHTSTICKDOWN, :RIGHT_STICK_DOWN, :RSTICKDOWN, :R_STICK_DOWN, :RDOWN, :RIGHT_ANALOG_DOWN, :ANALOG_R_DOWN])
          axis = right_stick_y_axis
          return 1 if axis && axis <= -0.45
          return -1 if axis && axis >= 0.45
          0
        rescue
          0
        end

        def right_stick_button?(names)
          names.any? do |name|
            next false unless Input.const_defined?(name)
            key = Input.const_get(name)
            (Input.press?(key) rescue false) || (Input.repeat?(key) rescue false)
          end
        rescue
          false
        end

        def right_stick_y_axis
          if Input.const_defined?(:Controller)
            value = Input.const_get(:Controller).axes_right[1] rescue nil
            return normalize_axis(value) unless value.nil?
          end
          [:right_stick_y, :right_y, :r_y, :rightStickY, :right_axis_y].each do |method_name|
            next unless Input.respond_to?(method_name)
            value = Input.send(method_name) rescue nil
            return normalize_axis(value) unless value.nil?
          end
          if Input.respond_to?(:axis)
            [:right_y, :right_stick_y, :ry, :r_y, 3].each do |axis_id|
              value = Input.axis(axis_id) rescue nil
              return normalize_axis(value) unless value.nil?
            end
          end
          nil
        rescue
          nil
        end

        def normalize_axis(value)
          axis = value.to_f
          axis = axis / 32767.0 if axis.abs > 1.0
          axis
        rescue
          nil
        end

        def scroll_lines(amount)
          return if amount == 0
          old = @scroll
          @scroll = [[@scroll + amount.to_i, 0].max, max_scroll].min
          draw if old != @scroll
        end

        def max_scroll
          measure = @sprites["popup"] && @sprites["popup"].bitmap
          return 0 unless measure
          [wrapped_value_lines(measure).length - @visible_lines, 0].max
        rescue
          0
        end

        def enter_triggered?
          key_trigger?(0x0D) || (Input.triggerex?(:RETURN) rescue false)
        end

        def escape_triggered?
          key_trigger?(0x1B) || (Input.triggerex?(:ESCAPE) rescue false)
        end

        def key_trigger?(vk)
          init_keyboard
          return (@gas.call(vk) & 0x01) != 0 if @gas
          false
        rescue
          false
        end

        def key_pressed?(vk)
          init_keyboard
          return (@gas.call(vk) & 0x8000) != 0 if @gas
          false
        rescue
          false
        end

        def key_repeat?(vk)
          @repeat ||= {}
          if key_pressed?(vk)
            @repeat[vk] ||= 0
            @repeat[vk] += 1
            count = @repeat[vk]
            count == 1 || (count > 12 && count % 4 == 0)
          else
            @repeat[vk] = 0
            false
          end
        rescue
          false
        end

        def init_keyboard
          return if @gas_checked
          @gas_checked = true
          @gas = Win32API.new("user32", "GetAsyncKeyState", ["i"], "i") rescue nil
        end

        def ctrl_pressed?
          return true if key_pressed?(0x11)
          return Input.press?(Input::CTRL) if Input.const_defined?(:CTRL)
          false
        rescue
          false
        end

        def shift_pressed?
          return true if key_pressed?(0x10)
          return Input.press?(Input::SHIFT) if Input.const_defined?(:SHIFT)
          false
        rescue
          false
        end

        def clipboard_write(text)
          Reloaded::FileActions.copy(text)
        rescue
          false
        end

        def clipboard_read
          Reloaded::FileActions.read_clipboard
        rescue
          ""
        end

        def multiline?
          @options[:mode] == :multiline
        end

        def cursor_visible?
          ((Graphics.frame_count rescue 0) / 20) % 2 == 0
        end

        def pulse_redraw?
          ((Graphics.frame_count rescue 0) % 4) == 0
        end

        def wrap_lines(bitmap, text, width)
          width = [width.to_i, 24].max
          lines = []
          text.to_s.gsub("\r\n", "\n").split("\n", -1).each do |paragraph|
            current = ""
            paragraph.each_char do |char|
              test = current + char
              if !current.empty? && bitmap.text_size(test).width > width
                lines << current
                current = char
              else
                current = test
              end
            end
            lines << current
          end
          lines.empty? ? [""] : lines
        rescue
          [text.to_s]
        end

        def plain_text(bitmap, x, y, w, h, text, color, align = 0)
          draw_x = x
          draw_align = 0
          case align
          when 1
            draw_x = x + w / 2
            draw_align = 2
          when 2
            draw_x = x + w
            draw_align = 1
          end
          pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y, draw_align, color, PopupWindow::TRANSPARENT]])
        rescue
        end

        def drain_input
          2.times { Input.update rescue nil }
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
    end

    module InputBindings
      ACTION_TARGETS = {
        :down => 2,
        :left => 4,
        :right => 6,
        :up => 8,
        :action => 11,
        :back => 12,
        :confirm => 13,
        :menu => 13,
        :special => 16,
        :sort => 17,
        :quick => 18
      }.freeze

      CONTROLLER_BUTTON_LABELS = {
        0 => "A", 1 => "B", 2 => "X", 3 => "Y",
        4 => "Back", 5 => "Guide", 6 => "Start",
        7 => "LS", 8 => "RS", 9 => "LB", 10 => "RB",
        11 => "Up", 12 => "Down", 13 => "Left", 14 => "Right",
        15 => "Misc", 16 => "Paddle 1", 17 => "Paddle 2",
        18 => "Paddle 3", 19 => "Paddle 4", 20 => "Touchpad"
      }.freeze

      SPECIAL_KEY_LABELS = {
        40 => "Enter", 41 => "Esc", 42 => "Backspace", 43 => "Tab",
        44 => "Space", 45 => "-", 46 => "=", 47 => "[", 48 => "]",
        49 => "\\", 51 => ";", 52 => "'", 53 => "`", 54 => ",",
        55 => ".", 56 => "/", 57 => "Caps Lock",
        73 => "Insert", 74 => "Home", 75 => "Page Up", 76 => "Delete",
        77 => "End", 78 => "Page Down", 79 => "Right", 80 => "Left",
        81 => "Down", 82 => "Up", 224 => "Ctrl", 225 => "Shift",
        226 => "Alt", 228 => "Ctrl", 229 => "Shift", 230 => "Alt"
      }.freeze

      class << self
        def primary_input
          return :controller if defined?(Input::Controller) && Input::Controller.connected?
          :keyboard
        rescue
          :keyboard
        end

        def label(action, preferred = nil)
          key = normalize_action(action)
          return combined_direction_label(key, preferred) if [:page, :pocket].include?(key)
          target = ACTION_TARGETS[key]
          return "" unless target
          rows = bindings.select { |row| row[:target] == target }
          device = preferred || primary_input
          row = rows.find { |entry| entry[:device] == device }
          row ||= rows.find { |entry| entry[:device] == :keyboard }
          row ||= rows.first
          row ? row[:label].to_s : ""
        rescue
          ""
        end

        def bindings
          path = binding_path
          return [] unless path
          signature = [path, File.mtime(path).to_f, File.size(path)] rescue [path]
          if @binding_signature != signature
            @binding_signature = signature
            @bindings = parse_file(path)
          end
          @bindings || []
        rescue
          []
        end

        def binding_path
          candidates = []
          if defined?(System) && System.respond_to?(:data_directory)
            candidates << File.join(System.data_directory.to_s, "keybindings.mkxp1")
          end
          candidates << File.join("Data", "keybindings.mkxp1")
          candidates.find { |path| File.file?(path) }
        rescue
          File.join("Data", "keybindings.mkxp1")
        end

        private

        def normalize_action(action)
          action.to_s.downcase.gsub(/\s+/, "_").to_sym
        rescue
          action
        end

        def combined_direction_label(_action, preferred)
          left = label(:left, preferred)
          right = label(:right, preferred)
          return "Left/Right" if left.empty? || right.empty?
          left == "Left" && right == "Right" ? "Left/Right" : "#{left}/#{right}"
        rescue
          "Left/Right"
        end

        def parse_file(path)
          data = File.binread(path)
          return [] if data.bytesize < 12
          format_version, rgss_version, count = data[0, 12].unpack("V3")
          return [] unless format_version == 3 && rgss_version == 1
          return [] if count > 1024 || data.bytesize < 12 + count * 16
          rows = []
          count.times do |index|
            type, source, direction, target = data[12 + index * 16, 16].unpack("V4")
            row = binding_row(type, source, direction, target)
            rows << row if row
          end
          rows
        rescue
          []
        end

        def binding_row(type, source, direction, target)
          case type
          when 1
            { :device => :keyboard, :label => keyboard_label(source), :target => target }
          when 2
            { :device => :controller, :label => CONTROLLER_BUTTON_LABELS[source] || "Button #{source}", :target => target }
          when 3
            { :device => :controller, :label => axis_label(source, direction), :target => target }
          else
            nil
          end
        end

        def keyboard_label(scancode)
          return (scancode + 61).chr if scancode >= 4 && scancode <= 29
          return (scancode == 39 ? "0" : (scancode - 29).to_s) if scancode >= 30 && scancode <= 39
          return "F#{scancode - 57}" if scancode >= 58 && scancode <= 69
          SPECIAL_KEY_LABELS[scancode] || "Key #{scancode}"
        rescue
          "Key #{scancode}"
        end

        def axis_label(axis, direction)
          negative = direction.to_i == 0
          case axis
          when 0 then negative ? "LS Left" : "LS Right"
          when 1 then negative ? "LS Up" : "LS Down"
          when 2 then negative ? "RS Left" : "RS Right"
          when 3 then negative ? "RS Up" : "RS Down"
          when 4 then "LT"
          when 5 then "RT"
          else "Axis #{axis}"
          end
        end
      end
    end

    module HintText
      KEYBOARD_LABELS = {
        :confirm => "C",
        :back => "B",
        :action => "A",
        :special => "Z",
        :left => "<",
        :right => ">",
        :page => "< >",
        :pocket => "< >",
        :sort => "L",
        :quick => "R",
        :menu => "C",
      }.freeze

      CONTROLLER_LABELS = {
        :confirm => "A",
        :back => "B",
        :action => "X",
        :special => "Y",
        :left => "Left",
        :right => "Right",
        :page => "Left/Right",
        :pocket => "Left/Right",
        :sort => "LB",
        :quick => "RB",
        :menu => "A",
      }.freeze

      ORDER = {
        :confirm => 0,
        :back => 1,
        :action => 2,
        :special => 3,
        :other => 4
      }.freeze

      WHITE = Color.new(248, 248, 248)
      SHADOWLESS = Color.new(0, 0, 0, 0)
      DEFAULT_SIZE = 17
      SEPARATOR = " | "
      ICON_ZOOM = 0.62
      ICON_GAP = 3
      FOOTER_TEXT_Y_OFFSET = -5
      FOOTER_ICON_Y_OFFSET = 2
      POPUP_ICON_ZOOM = 0.82

      class << self
        def enabled?
          return true unless defined?($PokemonSystem) && $PokemonSystem
          return true unless $PokemonSystem.respond_to?(:reloaded_hint_texts)
          $PokemonSystem.reloaded_hint_texts.to_i == 1
        rescue
          true
        end

        def primary_input
          return Reloaded::InputBindings.primary_input if defined?(Reloaded::InputBindings)
          :keyboard
        rescue
          :keyboard
        end

        def label(input, options = {})
          return "" if input.nil?
          if defined?(Reloaded::InputBindings)
            bound = Reloaded::InputBindings.label(input, primary_input) rescue nil
            return bound.to_s if bound && !bound.to_s.empty?
          end
          labels = primary_input == :controller ? CONTROLLER_LABELS : KEYBOARD_LABELS
          labels[input.to_sym] || input.to_s
        rescue
          input.to_s
        end

        def entry(group, text, input = nil, options = {})
          return nil if text.nil? || text.to_s.empty?
          {
            :group => normalize_group(group),
            :text => text.to_s,
            :input => input,
            :order => options[:order],
            :enabled => options.key?(:enabled) ? options[:enabled] : true
          }
        end

        def confirm(text = "Confirm", input = :confirm, options = {})
          entry(:confirm, text, input, options)
        end

        def back(text = "Back", input = :back, options = {})
          entry(:back, text, input, options)
        end

        def action(text, input = :action, options = {})
          entry(:action, text, input, options)
        end

        def special(text, input = :special, options = {})
          entry(:special, text, input, options)
        end

        def other(text, input = nil, options = {})
          entry(:other, text, input, options)
        end

        def status(text, color = nil, options = {})
          return nil if text.nil? || text.to_s.empty?
          {
            :text => text.to_s,
            :color => color || options[:color] || WHITE,
            :enabled => options.key?(:enabled) ? options[:enabled] : true
          }
        end

        def format(entries, options = {})
          rows = normalize_entries(entries)
          return "" if rows.empty?
          rows = sort_entries(rows) unless options[:preserve_order]
          rows.map { |row| format_entry(row) }.reject { |text| text.empty? }.join(options[:separator] || SEPARATOR)
        rescue
          Array(entries).compact.map(&:to_s).join(SEPARATOR)
        end

        def draw(bitmap, entries, x, y, width, options = {})
          return "" if options[:respect_enabled] != false && !enabled?
          rows = normalize_entries(entries)
          return "" if rows.empty?
          rows = sort_entries(rows) unless options[:preserve_order]
          if options[:icons] == true && draw_with_icons(bitmap, rows, x, y, width, options)
            return format(rows, options)
          end
          text = rows.map { |row| format_entry(row) }.reject { |value| value.empty? }.join(options[:separator] || SEPARATOR)
          return "" if text.empty?
          pbSetSmallFont(bitmap) rescue nil
          bitmap.font.size = (options[:size] || DEFAULT_SIZE).to_i if bitmap.respond_to?(:font) && bitmap.font
          text = trim_text(bitmap, text, width.to_i) if options[:trim] != false
          color = options[:color] || WHITE
          align = options.key?(:align) ? options[:align].to_i : 1
          draw_x = x
          draw_align = 0
          if align == 1
            draw_x = x + width / 2
            draw_align = 2
          elsif align == 2
            draw_x = x + width
            draw_align = 1
          end
          pbDrawTextPositions(bitmap, [[text, draw_x, y, draw_align, color, SHADOWLESS]])
          text
        rescue
          ""
        end

        def draw_footer(bitmap, entries, x, y, width, options = {})
          return "" if options[:respect_enabled] != false && !enabled?
          pbSetSmallFont(bitmap) rescue nil
          bitmap.font.size = (options[:size] || DEFAULT_SIZE).to_i if bitmap.respond_to?(:font) && bitmap.font
          footer_y = y + (options[:y_offset] || FOOTER_TEXT_Y_OFFSET).to_i
          hint = options[:hint_entry] || other(options[:hint_label] || "Controls (Y)")
          hint_options = options.merge(
            :align => 0,
            :trim => false,
            :icon_y_offset => (options[:icon_y_offset] || FOOTER_ICON_Y_OFFSET).to_i
          )
          hint_width = [[measure_entries_width(bitmap, [hint], hint_options) + 30, 48].max, width.to_i].min
          gap = hint_width >= width.to_i ? 0 : 8
          status_width = [width.to_i - hint_width - gap, 0].max
          draw_statuses(bitmap, normalize_statuses(options[:statuses]), x, footer_y, status_width, options.merge(:align => 1)) if status_width > 0
          cursor_x = x + width.to_i - hint_width + 7
          cursor_width = [hint_width - 15, 1].max
          if options[:draw_controls_cursor] != false && controls_hovered?(bitmap, x, y, width, options)
            draw_controls_selection(bitmap, cursor_x, y, cursor_width, options)
          end
          draw(
            bitmap,
            [hint],
            cursor_x + 7,
            footer_y,
            [cursor_width - 10, 1].max,
            hint_options
          )
          [x + width.to_i - hint_width, y, hint_width, (options[:height] || 24).to_i]
        rescue
          nil
        end

        def controls_rect(bitmap, x, y, width, options = {})
          pbSetSmallFont(bitmap) rescue nil
          bitmap.font.size = (options[:size] || DEFAULT_SIZE).to_i if bitmap.respond_to?(:font) && bitmap.font
          hint = other(options[:hint_label] || "Controls (Y)")
          hint_width = [[measure_entries_width(bitmap, [hint], options) + 30, 48].max, width.to_i].min
          [x + width.to_i - hint_width, y, hint_width, (options[:height] || 24).to_i]
        rescue
          [x + width.to_i - 64, y, 64, 24]
        end

        def controls_at?(bitmap, mouse_x, mouse_y, x, y, width, options = {})
          rx, ry, rw, rh = controls_rect(bitmap, x, y, width, options)
          mouse_x.to_i >= rx && mouse_x.to_i < rx + rw && mouse_y.to_i >= ry && mouse_y.to_i < ry + rh
        rescue
          false
        end

        def controls_hovered?(bitmap, x, y, width, options = {})
          pos = Reloaded::MouseInput.active_position
          return false unless pos.is_a?(Array)
          origin_y = [(Graphics.height rescue bitmap.height) - bitmap.height, 0].max
          controls_at?(bitmap, pos[0], pos[1] - origin_y, x, y, width, options)
        rescue
          false
        end

        def open_popup(title, entries, options = {})
          rows = normalize_entries(entries)
          return false if rows.empty?
          rows = sort_entries(rows) unless options[:preserve_order]
          rows = rows.reject { |row| sort_row?(row) }
          statuses = normalize_statuses(options[:statuses]).reject { |row| row[:text].to_s.start_with?("Sort:") }
          return false if rows.empty?
          return false unless defined?(Reloaded::Toast) && Reloaded::Toast.respond_to?(:rows)
          Reloaded::Toast.rows(
            "Controls",
            controls_popup_rows(rows),
            options.merge(
              :statuses => statuses,
              :width => controls_popup_width(rows),
              :row_width => controls_popup_width(rows)
            )
          )
        rescue
          false
        end

        def triggered?
          defined?(Input) && Input.const_defined?(:Y) && Input.trigger?(Input::Y)
        rescue
          false
        end

        private

        def draw_controls_selection(bitmap, x, y, width, options)
          theme = if defined?(Reloaded::Options) && Reloaded::Options.respond_to?(:cursor_theme)
                    Reloaded::Options.cursor_theme(($PokemonSystem.reloaded_cursor_theme rescue 0))
                  else
                    { :fill => Color.new(100, 160, 220, 160), :border => Color.new(60, 120, 180, 220) }
                  end
          base = theme[:fill] || Color.new(100, 160, 220, 160)
          border = theme[:border] || Color.new(60, 120, 180, 220)
          pulse = Math.sin((Graphics.frame_count rescue 0) * Math::PI / 20.0) * 0.5 + 0.5
          alpha = [[base.alpha.to_i + (pulse * 55).to_i, 255].min, 80].max
          fill = Color.new(base.red, base.green, base.blue, alpha)
          top = y + 2
          height = [(options[:height] || 24).to_i - 4, 4].max
          draw_rounded_cursor_rect(bitmap, x, top, width, height, 4, border)
          draw_rounded_cursor_rect(bitmap, x + 1, top + 1, width - 2, height - 2, 3, fill)
        rescue
        end

        def draw_rounded_cursor_rect(bitmap, x, y, width, height, radius, color)
          return if width <= 0 || height <= 0
          radius = [radius.to_i, width / 2, height / 2].min
          bitmap.fill_rect(x + radius, y, width - radius * 2, height, color)
          bitmap.fill_rect(x, y + radius, width, height - radius * 2, color)
          radius.times do |offset|
            inset = radius - offset
            row_width = width - inset * 2
            next if row_width <= 0
            bitmap.fill_rect(x + inset, y + offset, row_width, 1, color)
            bitmap.fill_rect(x + inset, y + height - offset - 1, row_width, 1, color)
          end
        rescue
        end

        def draw_statuses(bitmap, statuses, x, y, width, options = {})
          return 0 if statuses.empty?
          return 0 if width.to_i <= 0
          separator = options[:status_separator] || SEPARATOR
          pieces = []
          statuses.each_with_index do |row, index|
            pieces << { :text => row[:text].to_s, :color => row[:color] || WHITE }
            pieces << { :text => separator, :color => options[:color] || WHITE } if index < statuses.length - 1
          end
          total_w = pieces.inject(0) { |sum, piece| sum + bitmap.text_size(piece[:text]).width }
          align = options.key?(:align) ? options[:align].to_i : 1
          cursor_x = case align
                     when 1 then x + [(width.to_i - total_w) / 2, 0].max
                     when 2 then x + [width.to_i - total_w, 0].max
                     else x
                     end
          pieces.each do |piece|
            pbDrawTextPositions(bitmap, [[piece[:text], cursor_x, y, 0, piece[:color], SHADOWLESS]])
            cursor_x += bitmap.text_size(piece[:text]).width
          end
          total_w
        rescue
          0
        end

        def measure_entries_width(bitmap, entries, options = {})
          rows = normalize_entries(entries)
          return 0 if rows.empty?
          rows = sort_entries(rows) unless options[:preserve_order]
          separator = options[:separator] || SEPARATOR
          text = rows.map { |row| format_entry(row) }.reject { |value| value.empty? }.join(separator)
          bitmap.text_size(text).width
        rescue
          format(entries, options).length * 8
        end

        def normalize_statuses(statuses)
          Array(statuses).compact.map do |row|
            if row.is_a?(Hash)
              text = row[:text] || row["text"] || row[:label] || row["label"]
              enabled = row.key?(:enabled) ? row[:enabled] : row["enabled"]
              next nil if enabled == false
              { :text => text.to_s, :color => row[:color] || row["color"] || WHITE }
            else
              { :text => row.to_s, :color => WHITE }
            end
          end.compact.reject { |row| row[:text].empty? }
        rescue
          []
        end

        def sort_row?(row)
          row[:text].to_s.start_with?("Sort:")
        rescue
          false
        end

        def controls_popup_width(rows)
          scratch = Bitmap.new(1, 1)
          pbSetSmallFont(scratch) rescue nil
          scratch.font.size = 18 rescue nil
          text_w = rows.inject(0) { |max, row| [max, scratch.text_size(format_entry(row)).width].max }
          scratch.dispose rescue nil
          [[text_w + 64, 292].max, 384].min
        rescue
          320
        end

        def controls_popup_body_height(rows)
          [rows.length * 28, 28].max
        rescue
          112
        end

        def controls_popup_rows(rows)
          rows.map do |row|
            {
              :label => format_entry(row),
              :selectable => false,
              :value => nil
            }
          end
        rescue
          []
        end

        def draw_popup_text(bitmap, text, x, y, w, h, color, align = 0)
          draw_x = x
          draw_align = 0
          case align
          when 1
            draw_x = x + w / 2
            draw_align = 2
          when 2
            draw_x = x + w
            draw_align = 1
          end
          pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y, draw_align, color, SHADOWLESS]])
        rescue
        end

        def draw_with_icons(bitmap, rows, x, y, width, options = {})
          false
        end

        def icon_pieces(bitmap, rows, separator, size = DEFAULT_SIZE, zoom = ICON_ZOOM)
          pieces = []
          rows.each_with_index do |row, index|
            pieces.concat(entry_icon_pieces(bitmap, row, size, zoom))
            pieces << text_piece(bitmap, separator) if index < rows.length - 1
          end
          pieces
        rescue
          []
        end

        def entry_icon_pieces(bitmap, row, size = DEFAULT_SIZE, zoom = ICON_ZOOM)
          [text_piece(bitmap, format_entry(row))]
        rescue
          [text_piece(bitmap, format_entry(row))]
        end

        def icon_zoom_for_sheet(sheet, base_zoom, context = :footer)
          case sheet.to_s
          when "gamepadsticks"
            context == :popup ? 0.42 : 0.34
          when "gamepadtriggers"
            context == :popup ? 0.92 : 0.78
          else
            base_zoom
          end
        rescue
          base_zoom
        end

        def text_piece(bitmap, text)
          { :type => :text, :text => text.to_s, :width => bitmap.text_size(text.to_s).width }
        rescue
          { :type => :text, :text => text.to_s, :width => text.to_s.length * 8 }
        end

        def normalize_entries(entries)
          Array(entries).compact.map.with_index do |entry_value, index|
            row = normalize_entry(entry_value)
            next nil unless row
            next nil if row[:enabled] == false
            row[:source_order] = index
            row
          end.compact
        end

        def normalize_entry(entry_value)
          if entry_value.is_a?(Hash)
            group = entry_value[:group] || entry_value["group"] || entry_value[:type] || entry_value["type"] || :other
            text = entry_value[:text] || entry_value["text"] || entry_value[:label] || entry_value["label"]
            input = entry_value.key?(:input) ? entry_value[:input] : entry_value["input"]
            {
              :group => normalize_group(group),
              :text => text.to_s,
              :input => normalize_input(input),
              :order => entry_value[:order] || entry_value["order"],
              :enabled => entry_value.key?(:enabled) ? entry_value[:enabled] : entry_value["enabled"]
            }
          elsif entry_value.is_a?(Array)
            {
              :group => normalize_group(entry_value[0] || :other),
              :text => entry_value[1].to_s,
              :input => normalize_input(entry_value[2]),
              :order => entry_value[3].is_a?(Hash) ? entry_value[3][:order] : nil,
              :enabled => true
            }
          else
            {
              :group => :other,
              :text => entry_value.to_s,
              :input => nil,
              :order => nil,
              :enabled => true
            }
          end
        rescue
          nil
        end

        def sort_entries(entries)
          entries.sort_by do |row|
            group = normalize_group(row[:group])
            [row[:order] || ORDER[group] || ORDER[:other], row[:source_order] || 0]
          end
        end

        def format_entry(row)
          text = row[:text].to_s
          input = normalize_input(row[:input])
          input_label = input ? label(input) : ""
          input_label.empty? ? text : "#{text} (#{input_label})"
        rescue
          row[:text].to_s
        end

        def trim_text(bitmap, text, width)
          value = text.to_s
          return value if width <= 0
          return value if bitmap.text_size(value).width <= width
          while value.length > 3 && bitmap.text_size("#{value}...").width > width
            value = value[0...-1]
          end
          value.length > 3 ? "#{value}..." : value
        rescue
          text.to_s
        end

        def normalize_group(group)
          key = group.to_s.downcase.gsub(/\s+/, "_").to_sym
          return :confirm if [:confirm, :use, :select].include?(key)
          return :back if [:back, :cancel, :close].include?(key)
          return :action if [:action, :secondary].include?(key)
          return :special if [:special, :tertiary].include?(key)
          :other
        rescue
          :other
        end

        def normalize_input(input)
          return nil if input.nil? || input.to_s.empty?
          input.to_s.downcase.gsub(/\s+/, "_").to_sym
        rescue
          nil
        end

      end
    end

    module Toast
      DEFAULT_DURATION = 90

      class << self
        def show(text, options = {})
          opts = normalize_options(options)
          return auto(text, opts) if opts[:mode] == :auto
          ok(text, opts)
        end

        def ok(text, options = {})
          opts = normalize_options(options)
          PopupWindow.choice(
            text.to_s,
            [{ :label => opts[:ok_label] || _INTL("OK"), :value => true, :align => 1 }],
            opts.merge(:add_back => false, :start_index => 0, :center_text => true)
          )
          true
        rescue Exception => e
          PopupWindow.log_exception("Toast OK failed", e) if defined?(PopupWindow)
          false
        end

        def auto(text, options = {})
          opts = normalize_options(options).merge(:mode => :auto)
          toast = AutoToast.new(text, opts)
          active_toasts << toast
          toast
        rescue Exception => e
          PopupWindow.log_exception("Toast auto failed", e) if defined?(PopupWindow)
          nil
        end

        def custom(title, options = {}, &block)
          opts = normalize_options(options).merge(:mode => :custom)
          PopupWindow.with_modal { CustomToast.new(title, opts, block).main }
        rescue Exception => e
          PopupWindow.log_exception("Toast custom failed", e) if defined?(PopupWindow)
          false
        end

        def rows(title, rows, options = {})
          opts = normalize_options(options).merge(:mode => :rows)
          commands = Array(rows).compact
          commands << { :label => opts[:ok_label] || _INTL("OK"), :value => true, :align => 1 }
          PopupWindow.choice(
            title.to_s,
            commands,
            opts.merge(:add_back => false, :start_index => commands.length - 1)
          )
          true
        rescue Exception => e
          PopupWindow.log_exception("Toast rows failed", e) if defined?(PopupWindow)
          false
        end

        def success(text, options = {})
          show(text, normalize_options(options).merge(:theme => :success))
        end

        def warning(text, options = {})
          show(text, normalize_options(options).merge(:theme => :warning))
        end

        def error(text, options = {})
          show(text, normalize_options(options).merge(:theme => :error))
        end

        def update
          active_toasts.delete_if do |toast|
            !toast.update
          end
          true
        rescue Exception => e
          PopupWindow.log_exception("Toast update failed", e) if defined?(PopupWindow)
          false
        end

        alias update_all update

        def close_all
          active_toasts.each { |toast| toast.close rescue nil }
          active_toasts.clear
          true
        rescue
          false
        end

        def normalize_options(options)
          opts = {}
          (options || {}).each { |key, value| opts[key] = value } rescue nil
          opts[:mode] = (opts[:mode] || :ok).to_sym rescue :ok
          opts[:duration] = (opts[:duration] || DEFAULT_DURATION).to_i
          opts[:duration] = DEFAULT_DURATION if opts[:duration] <= 0
          opts[:position] = (opts[:position] || :center).to_sym rescue :center
          opts[:theme] = (opts[:theme] || :hr).to_sym rescue :hr
          opts[:show_dim] = false if opts[:mode] == :auto && !opts.key?(:show_dim)
          opts
        end

        def active_toasts
          @active_toasts ||= []
        end
      end

      class CustomToast
        include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

        TITLE_H = 26
        OK_H = 24
        PAD = 16
        WHITE = Color.new(248, 248, 248)
        BLUE = Color.new(120, 190, 255)
        GREEN = Color.new(105, 224, 164)
        SHADOWLESS = Color.new(0, 0, 0, 0)
        CURSOR = Color.new(170, 64, 70, 190)
        CURSOR_BORDER = Color.new(220, 96, 104, 230)

        def initialize(title, options = {}, renderer = nil)
          @title = title.to_s
          @options = options || {}
          @renderer = renderer
          @theme = PopupWindow::THEMES[@options[:theme]] || PopupWindow::THEMES[:hr]
          @statuses = Array(@options[:statuses])
          @sprites = {}
        end

        def main
          setup
          draw
          loop do
            Graphics.update
            Input.update
            draw if ((Graphics.frame_count rescue 0) % 4) == 0
            break if close_input?
          end
          true
        ensure
          dispose
          drain_input
        end

        private

        def setup
          @viewport = Viewport.new(0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          @viewport.z = (@options[:z] || 999_999_999).to_i
          @sprites["dim"] = Sprite.new(@viewport)
          @sprites["dim"].bitmap = Bitmap.new(PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          @sprites["dim"].bitmap.fill_rect(0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H, PopupWindow::DIM_BG) if @options[:show_dim] != false
          calculate_layout
          @sprites["toast"] = Sprite.new(@viewport)
          @sprites["toast"].x = @x
          @sprites["toast"].y = @y
          @sprites["toast"].bitmap = Bitmap.new(@w, @h)
        end

        def calculate_layout
          measure = Bitmap.new(1, 1)
          pbSetSmallFont(measure) rescue nil
          @w = [[(@options[:width] || 320).to_i, PopupWindow::MIN_W].max, PopupWindow::MAX_W].min
          @title_lines = wrap_lines(measure, @title.empty? ? "Controls" : @title, @w - PAD * 2)
          body_h = [(@options[:body_height] || 80).to_i, 24].max
          status_h = @statuses.empty? ? 0 : @statuses.length * 18 + 4
          title_h = [@title_lines.length * TITLE_H, TITLE_H].max
          @h = [[PAD + title_h + status_h + body_h + OK_H + PAD, PopupWindow::MIN_H].max, PopupWindow::MAX_H].min
          @x = (PopupWindow::SCREEN_W - @w) / 2
          @y = (PopupWindow::SCREEN_H - @h) / 2
          measure.dispose rescue nil
        end

        def draw
          bitmap = @sprites["toast"].bitmap
          bitmap.clear
          PopupWindow.draw_panel(bitmap, @w, @h, @theme, self)
          pbSetSmallFont(bitmap) rescue nil
          bitmap.font.size = 19 rescue nil
          y = 8
          @title_lines.each do |line|
            draw_text(bitmap, line, PAD, y, @w - PAD * 2, TITLE_H, @theme[:title] || BLUE, 1)
            y += TITLE_H
          end
          @statuses.each do |status|
            bitmap.font.size = 16 rescue nil
            draw_text(bitmap, status[:text].to_s, PAD, y, @w - PAD * 2, 18, status[:color] || GREEN, 1)
            y += 18
          end
          y += 4 unless @statuses.empty?
          body_bottom = @h - PAD - OK_H - 4
          rect = { :x => PAD, :y => y, :width => @w - PAD * 2, :height => [body_bottom - y, 1].max }
          @renderer.call(bitmap, rect) if @renderer
          draw_ok(bitmap)
        end

        def draw_ok(bitmap)
          x, y, w, h = ok_bounds
          if respond_to?(:reloaded_draw_rounded_rect)
            reloaded_draw_rounded_rect(bitmap, x, y, w, h, 4, pulsing_cursor_fill, cursor_border)
          else
            PopupWindow.draw_rounded_rect(bitmap, x, y, w, h, 4, cursor_border)
            PopupWindow.draw_rounded_rect(bitmap, x + 1, y + 1, w - 2, h - 2, 3, pulsing_cursor_fill)
          end
          bitmap.font.size = 25 rescue nil
          text_offset = (@options[:ok_text_offset_y] || -5).to_i
          draw_text(bitmap, "OK", x, y + text_offset, w, OK_H, WHITE, 1)
        rescue
        end

        def ok_bounds
          [10, @h - PAD - OK_H + 4, @w - 20, OK_H - 4]
        rescue
          [10, 0, @w - 20, OK_H - 4]
        end

        def draw_text(bitmap, text, x, y, w, h, color, align = 0)
          draw_x = x
          draw_align = 0
          case align
          when 1
            draw_x = x + w / 2
            draw_align = 2
          when 2
            draw_x = x + w
            draw_align = 1
          end
          pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y, draw_align, color, SHADOWLESS]])
        rescue
        end

        def close_input?
          return true if Input.trigger?(Input::USE)
          return true if Input.trigger?(Input::BACK)
          ok_clicked?
        rescue
          false
        end

        def ok_clicked?
          return false unless (Input.trigger?(Input::MOUSELEFT) rescue false)
          pos = Reloaded::MouseInput.active_position
          return false unless pos.is_a?(Array)
          mx, my = pos
          x, y, w, h = ok_bounds
          mx.between?(@x + x, @x + x + w) && my.between?(@y + y, @y + y + h)
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

        def dispose
          @sprites.each_value do |sprite|
            sprite.bitmap.dispose rescue nil
            sprite.dispose rescue nil
          end
          @sprites.clear
          @viewport.dispose rescue nil
        rescue
        end

        def wrap_lines(bitmap, text, width)
          value = text.to_s.gsub("\r\n", "\n")
          lines = []
          value.split("\n").each do |paragraph|
            if paragraph.empty?
              lines << ""
              next
            end
            current = ""
            paragraph.split(" ").each do |word|
              test = current.empty? ? word : "#{current} #{word}"
              if bitmap.text_size(test).width > width && !current.empty?
                lines << current
                current = word
              else
                current = test
              end
            end
            lines << current unless current.empty?
          end
          lines.empty? ? [""] : lines
        rescue
          [text.to_s]
        end

        def pulsing_cursor_fill
          base = cursor_fill
          pulse = Math.sin((Graphics.frame_count rescue 0) * Math::PI / 20.0) * 0.5 + 0.5
          alpha = [[base.alpha.to_i + (pulse * 55).to_i, 255].min, 80].max
          Color.new(base.red, base.green, base.blue, alpha)
        rescue
          CURSOR
        end

        def cursor_fill
          respond_to?(:reloaded_cursor_fill) ? reloaded_cursor_fill : CURSOR
        rescue
          CURSOR
        end

        def cursor_border
          respond_to?(:reloaded_cursor_border) ? reloaded_cursor_border : CURSOR_BORDER
        rescue
          CURSOR_BORDER
        end
      end

      class AutoToast
        include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

        def initialize(text, options = {})
          @text = text.to_s
          @options = options || {}
          @theme = PopupWindow::THEMES[@options[:theme]] || PopupWindow::THEMES[:hr]
          @duration = @options[:duration].to_i
          @duration = DEFAULT_DURATION if @duration <= 0
          @frames = 0
          @closed = false
          setup
          draw
        end

        def update
          return false if @closed
          @frames += 1
          draw if ((Graphics.frame_count rescue @frames) % 8) == 0
          close if mouse_clicked?
          close if @frames >= @duration
          !@closed
        rescue Exception => e
          PopupWindow.log_exception("AutoToast update failed", e) if defined?(PopupWindow)
          close
          false
        end

        def close
          return if @closed
          @closed = true
          dispose
          false
        rescue
          false
        end

        def closed?
          @closed
        end

        def mouse_clicked?
          return false unless (Input.trigger?(Input::MOUSELEFT) rescue false)
          pos = Reloaded::MouseInput.active_position
          return false unless pos.is_a?(Array)
          pos[0].to_i >= @x && pos[0].to_i < @x + @w && pos[1].to_i >= @y && pos[1].to_i < @y + @h
        rescue
          false
        end

        def setup
          @viewport = Viewport.new(0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          @viewport.z = (@options[:z] || 999_999_998).to_i
          @sprites = {}
          @sprites["dim"] = Sprite.new(@viewport)
          @sprites["dim"].bitmap = Bitmap.new(PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          @sprites["dim"].bitmap.fill_rect(0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H, PopupWindow::DIM_BG) if @options[:show_dim]
          calculate_layout
          @sprites["toast"] = Sprite.new(@viewport)
          @sprites["toast"].x = @x
          @sprites["toast"].y = @y
          @sprites["toast"].bitmap = Bitmap.new(@w, @h)
        end

        def calculate_layout
          measure = Bitmap.new(1, 1)
          pbSetSmallFont(measure) rescue nil
          preferred_w = [[measure.text_size(@text).width + PopupWindow::PAD * 2 + PopupWindow::TEXT_SAFETY_PAD, PopupWindow::MIN_W].max, PopupWindow::MAX_W].min rescue 280
          @w = preferred_w
          @lines = wrap_lines(measure, @text, @w - PopupWindow::PAD * 2)
          @h = [[PopupWindow::PAD * 2 + @lines.length * PopupWindow::MESSAGE_LINE_H, PopupWindow::MIN_H].max, PopupWindow::MAX_H].min
          @x = (PopupWindow::SCREEN_W - @w) / 2
          @y = case @options[:position]
               when :top
                 24
               when :bottom
                 PopupWindow::SCREEN_H - @h - 24
               else
                 (PopupWindow::SCREEN_H - @h) / 2
               end
          measure.dispose rescue nil
        end

        def draw
          bitmap = @sprites["toast"].bitmap
          bitmap.clear
          PopupWindow.draw_panel(bitmap, @w, @h, @theme, self)
          pbSetSmallFont(bitmap) rescue nil
          y = PopupWindow::PAD
          @lines.each do |line|
            plain_text(bitmap, PopupWindow::PAD, y, @w - PopupWindow::PAD * 2, PopupWindow::MESSAGE_LINE_H, line, @theme[:text], 1)
            y += PopupWindow::MESSAGE_LINE_H
          end
        rescue
        end

        def wrap_lines(bitmap, text, width)
          lines = []
          current = ""
          text.to_s.gsub("\r\n", "\n").split("\n").each do |paragraph|
            paragraph.split(" ").each do |word|
              test = current.empty? ? word : "#{current} #{word}"
              if bitmap.text_size(test).width > width && !current.empty?
                lines << current
                current = word
              else
                current = test
              end
            end
            lines << current unless current.empty?
            current = ""
          end
          lines.empty? ? [""] : lines
        rescue
          [text.to_s]
        end

        def plain_text(bitmap, x, y, w, h, text, color, align = 0)
          draw_x = x
          draw_align = 0
          case align
          when 1
            draw_x = x + w / 2
            draw_align = 2
          when 2
            draw_x = x + w
            draw_align = 1
          end
          pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y, draw_align, color, PopupWindow::TRANSPARENT]])
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
    end
  end

  PopupWindow = API::PopupWindow unless const_defined?(:PopupWindow, false)
  TextInput = API::TextInput unless const_defined?(:TextInput, false)
  HintText = API::HintText unless const_defined?(:HintText, false)
  Toast = API::Toast unless const_defined?(:Toast, false)

  unless const_defined?(:Confirm, false)
    module Confirm
      class << self
        def message(text, options = {})
          Reloaded.message(text, options)
        end

        def confirm(text, options = {})
          Reloaded.confirm(text, options)
        end

        alias call confirm

        def choice(title, commands, options = {})
          Reloaded.choice(title, commands, options)
        end

        def command(title, commands, options = {})
          Reloaded.command(title, commands, options)
        end

        def toast(text, options = {})
          Reloaded.toast(text, options)
        end

        def text_input(title, options = {})
          Reloaded.text_input(title, options)
        end
      end
    end
  end

  class << self
    def message(text, options = {})
      return PopupWindow.message(text, options) if const_defined?(:PopupWindow, false)
      Kernel.pbMessage(text.to_s) if defined?(Kernel) && Kernel.respond_to?(:pbMessage)
      true
    rescue
      true
    end

    def confirm(text, options = {})
      return PopupWindow.confirm(text, options) if const_defined?(:PopupWindow, false)
      return false unless defined?(Kernel) && Kernel.respond_to?(:pbMessage)
      Kernel.pbMessage(text.to_s, [_INTL("No"), _INTL("Yes")], 0) == 1
    rescue
      false
    end

    def choice(title, commands, options = {})
      return PopupWindow.choice(title, commands, options) if const_defined?(:PopupWindow, false)
      rows = Array(commands)
      return -1 if rows.empty?
      labels = rows.map { |row| choice_label(row) }
      index = Kernel.pbMessage(title.to_s, labels, labels.length) if defined?(Kernel) && Kernel.respond_to?(:pbMessage)
      return -1 if index.nil? || index < 0 || index >= rows.length
      choice_value(rows[index], index)
    rescue
      -1
    end

    def command(title, commands, options = {})
      return PopupWindow.command(title, commands, options) if const_defined?(:PopupWindow, false)
      choice(title, commands, options)
    rescue
      -1
    end

    def popup_async(text, options = {})
      return PopupWindow.async(text, options) if const_defined?(:PopupWindow, false)
      nil
    rescue
      nil
    end

    alias async_popup popup_async

    def toast(text, options = {})
      return Toast.show(text, options) if const_defined?(:Toast, false)
      message(text, options)
    rescue
      false
    end

    def toast_ok(text, options = {})
      return Toast.ok(text, options) if const_defined?(:Toast, false)
      message(text, options)
    rescue
      false
    end

    def toast_success(text, options = {})
      return Toast.success(text, options) if const_defined?(:Toast, false)
      message(text, options.merge(:theme => :success))
    rescue
      false
    end

    def toast_warning(text, options = {})
      return Toast.warning(text, options) if const_defined?(:Toast, false)
      message(text, options.merge(:theme => :warning))
    rescue
      false
    end

    def toast_error(text, options = {})
      return Toast.error(text, options) if const_defined?(:Toast, false)
      message(text, options.merge(:theme => :error))
    rescue
      false
    end

    def text_input(title, options = {})
      return TextInput.open(title, options) if const_defined?(:TextInput, false)
      options && options[:initial] ? options[:initial].to_s : ""
    rescue
      nil
    end

    def multiline_input(title, options = {})
      return TextInput.multiline(title, options) if const_defined?(:TextInput, false)
      options && options[:initial] ? options[:initial].to_s : ""
    rescue
      nil
    end

    def search_input(title, options = {})
      return TextInput.search(title, options) if const_defined?(:TextInput, false)
      options && options[:initial] ? options[:initial].to_s : ""
    rescue
      nil
    end

    def code_input(title, options = {})
      return TextInput.code(title, options) if const_defined?(:TextInput, false)
      options && options[:initial] ? options[:initial].to_s : ""
    rescue
      nil
    end

    def url_input(title, options = {})
      return TextInput.url(title, options) if const_defined?(:TextInput, false)
      options && options[:initial] ? options[:initial].to_s : ""
    rescue
      nil
    end

    def hint_text(entries, options = {})
      return HintText.format(entries, options) if const_defined?(:HintText, false)
      Array(entries).compact.map(&:to_s).join(" | ")
    rescue
      ""
    end

    def draw_hint_text(bitmap, entries, x, y, width, options = {})
      return HintText.draw(bitmap, entries, x, y, width, options) if const_defined?(:HintText, false)
      ""
    rescue
      ""
    end

    def draw_hint_footer(bitmap, entries, x, y, width, options = {})
      return HintText.draw_footer(bitmap, entries, x, y, width, options) if const_defined?(:HintText, false)
      ""
    rescue
      ""
    end

    def open_hint_popup(title, entries, options = {})
      return HintText.open_popup(title, entries, options) if const_defined?(:HintText, false)
      false
    rescue
      false
    end

    private

    def choice_label(row)
      if row.is_a?(Hash)
        (row[:label] || row["label"] || row[:text] || row["text"] || row[:name] || row["name"] || "").to_s
      elsif row.is_a?(Array)
        row[0].to_s
      else
        row.to_s
      end
    end

    def choice_value(row, index)
      if row.is_a?(Hash)
        value = row.key?(:value) ? row[:value] : row["value"]
        value.nil? ? index : value
      elsif row.is_a?(Array)
        row.length > 2 ? row[2] : index
      else
        index
      end
    end
  end
end
