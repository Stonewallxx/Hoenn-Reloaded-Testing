#======================================================
# Reloaded List Picker
# Author: Stonewall
#======================================================
# Shared popup and full-screen list selection for Reloaded systems and mods.
#======================================================

module Reloaded
  module API
    module ListPicker
      SCREEN_W = PopupWindow::SCREEN_W
      SCREEN_H = PopupWindow::SCREEN_H
      LIST_JUMP = 3
      DEFAULT_ROW_H = 24
      WRAPPED_ROW_H = 38
      TITLE_H = 28
      SEARCH_H = 24
      FOOTER_H = 24
      DETAIL_H = 72
      SCROLLBAR_W = 5
      CANCEL_VALUE = Object.new

      class << self
        def open(title, rows, options = {})
          PopupWindow.with_modal do
            PickerScene.new(title, rows, normalize_options(options)).main
          end
        rescue Exception => e
          PopupWindow.log_exception("ListPicker failed", e) if defined?(PopupWindow)
          nil
        end

        def popup(title, rows, options = {})
          open(title, rows, options.merge(:layout => :popup))
        end

        def fullscreen(title, rows, options = {})
          open(title, rows, options.merge(:layout => :fullscreen))
        end

        def normalize_options(options)
          opts = {}
          (options || {}).each do |key, value|
            normalized_key = key.to_sym rescue key
            opts[normalized_key] = value
          end
          opts[:layout] = (opts[:layout] || :popup).to_sym rescue :popup
          opts[:layout] = :popup unless [:popup, :fullscreen].include?(opts[:layout])
          opts[:theme] = (opts[:theme] || :hr).to_sym rescue :hr
          opts[:theme] = :hr unless PopupWindow::THEMES[opts[:theme]]
          opts[:search] = !!opts[:search]
          opts[:wrap] = true unless opts.key?(:wrap)
          opts[:multi_select] = !!opts[:multi_select]
          opts[:add_back] = true unless opts.key?(:add_back)
          opts[:start_on_back] = !!opts[:start_on_back]
          opts[:back_label] = (opts[:back_label] || _INTL("Back")).to_s
          opts[:done_label] = (opts[:done_label] || _INTL("Done")).to_s
          opts[:empty_text] = (opts[:empty_text] || _INTL("No matching entries.")).to_s
          opts[:search_label] = (opts[:search_label] || _INTL("Search (Click)")).to_s
          opts[:clear_label] = (opts[:clear_label] || _INTL("Clear")).to_s
          opts[:wrap_labels] = !!opts[:wrap_labels]
          opts[:show_dim] = true unless opts.key?(:show_dim)
          opts[:z] = opts[:z] || 999_999_999
          opts[:live_refresh] = !!opts[:live_refresh]
          opts[:refresh_interval] = [opts[:refresh_interval].to_i, 15].max
          opts[:controls] = true unless opts.key?(:controls)
          opts[:controls] = !!opts[:controls]
          opts[:remember] = !!opts[:remember]
          opts[:memory_key] = opts[:memory_key] || opts[:key]
          opts[:details] = true if opts[:on_highlight].respond_to?(:call) && !opts.key?(:details)
          opts
        end

        def normalize_rows(rows, options = {})
          values = resolve_rows(rows)
          normalized = values.each_with_index.map { |row, index| normalize_row(row, index) }
          if options[:multi_select]
            normalized << special_row(options[:done_label], :done)
          end
          if options[:add_back]
            normalized << special_row(options[:back_label], :back)
          end
          normalized
        end

        def resolve_rows(rows)
          value = rows.respond_to?(:call) ? rows.call : rows
          Array(value).compact
        rescue Exception => e
          PopupWindow.log_exception("ListPicker row provider failed", e) if defined?(PopupWindow)
          []
        end

        def normalize_row(row, index)
          if row.is_a?(Hash)
            label = row[:label] || row["label"] || row[:text] || row["text"] || row[:name] || row["name"] || ""
            header = row[:header] || row["header"] || row[:section] || row["section"]
            disabled = row[:disabled] || row["disabled"]
            value_set = row.key?(:value) || row.key?("value")
            value = row.key?(:value) ? row[:value] : row["value"]
            value = index unless value_set && !value.nil?
            {
              :label => label.to_s,
              :value => value,
              :header => !!header,
              :disabled => !!disabled,
              :disabled_reason => (row[:disabled_reason] || row["disabled_reason"] || "").to_s,
              :status => (row[:status] || row["status"] || "").to_s,
              :detail => row[:detail] || row["detail"] || row[:description] || row["description"],
              :color => row[:color] || row["color"],
              :search_text => (row[:search_text] || row["search_text"] || label).to_s,
              :kind => :entry,
              :source_index => index
            }
          elsif row.is_a?(Array)
            {
              :label => row[0].to_s,
              :value => row.length > 1 ? row[1] : index,
              :header => false,
              :disabled => false,
              :disabled_reason => "",
              :status => row.length > 2 ? row[2].to_s : "",
              :detail => row.length > 3 ? row[3] : nil,
              :color => nil,
              :search_text => row[0].to_s,
              :kind => :entry,
              :source_index => index
            }
          else
            {
              :label => row.to_s,
              :value => index,
              :header => false,
              :disabled => false,
              :disabled_reason => "",
              :status => "",
              :detail => nil,
              :color => nil,
              :search_text => row.to_s,
              :kind => :entry,
              :source_index => index
            }
          end
        end

        def special_row(label, kind)
          {
            :label => label.to_s,
            :value => CANCEL_VALUE,
            :header => false,
            :disabled => false,
            :disabled_reason => "",
            :status => "",
            :detail => nil,
            :color => nil,
            :search_text => "",
            :kind => kind,
            :source_index => -1
          }
        end
      end

      class PickerScene
        include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

        def initialize(title, source_rows, options)
          @title = title.to_s
          @source_rows = source_rows
          @options = options
          @theme = PopupWindow::THEMES[@options[:theme]] || PopupWindow::THEMES[:hr]
          @all_rows = []
          @rows = []
          @query = ""
          @selected = 0
          @scroll = 0
          @list_state = nil
          @selected_values = Array(@options[:start_values]).dup
          @selected_values << @options[:start_value] if @options.key?(:start_value) && !@options[:start_value].nil?
          @selected_values.uniq!
          @sprites = {}
          @last_refresh_frame = -999_999
          @detail_text = ""
        end

        def main
          setup
          rebuild_rows(:preserve_value => @options[:start_value])
          draw
          loop do
            Graphics.update
            Input.update
            refresh_live_rows
            draw if pulse_redraw?
            result = update
            return result unless result == :continue
          end
        ensure
          dispose
          drain_input
        end

        def setup
          calculate_layout
          @viewport = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
          @viewport.z = @options[:z].to_i
          if @options[:layout] == :popup
            @sprites["dim"] = Sprite.new(@viewport)
            @sprites["dim"].bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
            @sprites["dim"].bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, PopupWindow::DIM_BG) if @options[:show_dim]
          end
          @sprites["picker"] = Sprite.new(@viewport)
          @sprites["picker"].x = @x
          @sprites["picker"].y = @y
          @sprites["picker"].z = @options[:z].to_i
          @sprites["picker"].bitmap = Bitmap.new(@w, @h)
        end

        def calculate_layout
          @row_h = @options[:wrap_labels] ? WRAPPED_ROW_H : DEFAULT_ROW_H
          @footer_h = footer_visible? ? FOOTER_H : 0
          if @options[:layout] == :fullscreen
            @x = 0
            @y = 0
            @w = SCREEN_W
            @h = SCREEN_H
          else
            @w = [[(@options[:width] || PopupWindow::MAX_W).to_i, PopupWindow::MIN_W].max, PopupWindow::MAX_W].min
            estimated_rows = ListPicker.normalize_rows(@source_rows, @options).length
            estimated_rows += 1 if estimated_rows <= (@options[:multi_select] ? 2 : 1)
            detail_height = @options[:details] ? [(@options[:detail_height] || DETAIL_H).to_i, 48].max : 0
            desired_h = TITLE_H + (@options[:search] ? SEARCH_H + 4 : 0) +
                        [estimated_rows, 8].min * @row_h.to_i + detail_height + @footer_h.to_i + 12
            requested_h = @options[:height] || desired_h
            @h = [[requested_h.to_i, 132].max, PopupWindow::MAX_H].min
            @x = (SCREEN_W - @w) / 2
            @y = (SCREEN_H - @h) / 2
          end
          @search_y = TITLE_H
          @content_y = TITLE_H + (@options[:search] ? SEARCH_H + 4 : 0)
          if @options[:layout] == :fullscreen && @options[:details]
            @list_x = 8
            @list_w = (@w * 56 / 100) - 12
            @detail_x = @list_x + @list_w + 8
            @detail_y = @content_y
            @detail_w = @w - @detail_x - 8
            @detail_h = @h - @detail_y - @footer_h - 8
            @list_h = @h - @content_y - @footer_h - 8
          else
            @list_x = 8
            @list_w = @w - 16
            detail_height = @options[:details] ? [(@options[:detail_height] || DETAIL_H).to_i, 48].max : 0
            @list_h = @h - @content_y - @footer_h - detail_height - 8
            if detail_height > 0
              @detail_x = 8
              @detail_y = @content_y + @list_h + 4
              @detail_w = @w - 16
              @detail_h = detail_height - 4
            end
          end
          @list_h = [@list_h, @row_h].max
          @visible_rows = [[@list_h / @row_h, 1].max, 20].min
        end

        def rebuild_rows(options = {})
          preserve = options.key?(:preserve_value) ? options[:preserve_value] : selected_value
          @all_rows = ListPicker.normalize_rows(@source_rows, @options)
          reconcile_selected_values
          @rows = filtered_rows(@all_rows, @query)
          insert_empty_row
          target_id = if preserve.nil? && @options[:start_on_back]
                        list_state_id(@rows.find { |row| row[:kind] == :back })
                      elsif preserve.nil?
                        nil
                      else
                        [:entry, preserve]
                      end
          sync_list_state(target_id)
          update_detail
        end

        def filtered_rows(rows, query)
          text = query.to_s.strip.downcase
          return rows.dup if text.empty?
          output = []
          pending_header = nil
          rows.each do |row|
            if row[:header]
              pending_header = row
              next
            end
            if special_row?(row)
              output << row
              next
            end
            haystack = "#{row[:label]} #{row[:search_text]} #{row[:status]}".downcase
            next unless haystack.include?(text)
            output << pending_header if pending_header && output.last != pending_header
            pending_header = nil
            output << row
          end
          output
        end

        def update
          old_selected = @selected
          mouse_result = update_mouse
          return mouse_result unless mouse_result == :continue
          if controls_triggered?
            show_controls_popup
          else
            event = @list_state.update_input(:mouse => false)
            result = handle_state_event(event)
            return result unless result == :continue
          end
          if old_selected != @selected
            pbPlayCursorSE rescue nil
            update_detail
            draw
          end
          :continue
        end

        def activate_selected
          row = @rows[@selected]
          return :continue unless row
          if row[:disabled]
            show_disabled_reason(row)
            return :continue
          end
          if row[:kind] == :back
            pbPlayCancelSE rescue nil
            return nil
          end
          if row[:kind] == :done
            return :continue unless valid_selection?(@selected_values.dup)
            pbPlayDecisionSE rescue nil
            return @selected_values.dup
          end
          return :continue unless selectable?(row)
          if @options[:multi_select]
            pbPlayDecisionSE rescue nil
            toggle_selected_value(row[:value])
            draw
            return :continue
          end
          return :continue unless valid_selection?(row[:value])
          pbPlayDecisionSE rescue nil
          row[:value]
        end

        def move_selection(amount)
          @list_state.move(amount)
          sync_from_list_state
        end

        def sync_list_state(target_id = nil)
          if @list_state
            @list_state.visible_rows = @visible_rows
            @list_state.replace_rows(@rows, :preserve => :id)
            @list_state.select_id(target_id) unless target_id.nil?
          else
            @list_state = Reloaded::ListState.new(
              :rows => @rows,
              :visible_rows => @visible_rows,
              :row_id => proc { |row, _index| list_state_id(row) },
              :wrap => @options[:wrap],
              :jump_size => LIST_JUMP,
              :horizontal => :jump,
              :focus_disabled => false,
              :remember => @options[:remember],
              :memory_key => @options[:memory_key],
              :initial_id => target_id
            )
          end
          sync_from_list_state
        end

        def sync_from_list_state
          @selected = @list_state.index || 0
          @scroll = @list_state.scroll
        end

        def list_state_id(row)
          return nil unless row
          return [:entry, row[:value]] if row[:kind] == :entry
          [row[:kind], row[:label].to_s]
        end

        def handle_state_event(event)
          return :continue unless event
          sync_from_list_state
          case event.type
          when :activate
            activate_selected
          when :disabled
            show_disabled_reason(event.row || @rows[event.index])
            :continue
          when :back
            pbPlayCancelSE rescue nil
            nil
          else
            :continue
          end
        end

        def update_mouse
          pos = Reloaded::MouseInput.active_position rescue nil
          return :continue unless pos.is_a?(Array)
          local_x = pos[0].to_i - @x
          local_y = pos[1].to_i - @y
          return :continue if local_x < 0 || local_y < 0 || local_x >= @w || local_y >= @h
          if controls_clicked?(local_x, local_y)
            show_controls_popup
            return :continue
          end
          if @options[:search] && local_y >= @search_y && local_y < @search_y + SEARCH_H
            if (Input.trigger?(Input::MOUSELEFT) rescue false)
              if !@query.empty? && local_x >= @w - 72
                @query = ""
                rebuild_rows
              else
                open_search
              end
              draw
            end
            return :continue
          end
          event = @list_state.update_input(
            :commands => false,
            :mouse_index => proc { |mx, my| mouse_row_index(mx.to_i - @x, my.to_i - @y) }
          )
          handle_state_event(event)
        rescue Exception => e
          PopupWindow.log_exception("ListPicker mouse input failed", e) if defined?(PopupWindow)
          :continue
        end

        def open_search
          return unless defined?(Reloaded::TextInput)
          value = @list_state.with_dialog do
            Reloaded::TextInput.search(@options[:search_title] || _INTL("Search"), :initial => @query)
          end
          return if value.nil?
          preserve = selected_value
          @query = value.to_s
          rebuild_rows(:preserve_value => preserve)
        end

        def refresh_live_rows
          return unless @options[:live_refresh] && @source_rows.respond_to?(:call)
          frame = Graphics.frame_count rescue 0
          return if frame - @last_refresh_frame < @options[:refresh_interval]
          @last_refresh_frame = frame
          old_signature = row_signature(@all_rows)
          preserve = selected_value
          latest = ListPicker.normalize_rows(@source_rows, @options)
          return if row_signature(latest) == old_signature
          @all_rows = latest
          reconcile_selected_values
          @rows = filtered_rows(@all_rows, @query)
          insert_empty_row
          sync_list_state(preserve.nil? ? nil : [:entry, preserve])
          update_detail
          draw
        end

        def draw
          bitmap = @sprites["picker"].bitmap
          bitmap.clear
          PopupWindow.draw_panel(bitmap, @w, @h, @theme, self)
          pbSetSmallFont(bitmap) rescue nil
          plain_text(bitmap, 12, 0, @w - 24, TITLE_H, @title, @theme[:title], 1)
          draw_search(bitmap) if @options[:search]
          draw_rows(bitmap)
          draw_details(bitmap) if @options[:details]
          draw_footer(bitmap)
        end

        def draw_search(bitmap)
          x = 8
          y = @search_y
          w = @w - 16
          PopupWindow.draw_rounded_rect(bitmap, x, y, w, SEARCH_H - 2, 3, Color.new(18, 38, 64, 220))
          text = @query.empty? ? @options[:search_label] : @query
          plain_text(bitmap, x + 8, y - 4, w - 84, SEARCH_H, text, @query.empty? ? @theme[:dim] : @theme[:text], 0)
          plain_text(bitmap, x + w - 66, y - 4, 58, SEARCH_H, @options[:clear_label], @theme[:title], 2) unless @query.empty?
        end

        def draw_rows(bitmap)
          ensure_visible
          visible = @rows[@scroll, @visible_rows] || []
          visible.each_with_index do |row, local_index|
            index = @scroll + local_index
            y = @content_y + local_index * @row_h
            draw_row(bitmap, row, index, y)
          end
          draw_scrollbar(bitmap)
        end

        def draw_row(bitmap, row, index, y)
          selected = index == @selected
          if selected && selectable?(row)
            draw_selection(bitmap, @list_x, y + 2, @list_w - SCROLLBAR_W - 4, @row_h - 4)
          end
          if row[:header]
            plain_text(bitmap, @list_x + 8, y - 5, @list_w - 20, @row_h, row[:label], @theme[:title], 1)
            return
          end
          status = row_status(row)
          status_w = status.empty? ? 0 : 82
          x = @list_x + 10
          width = @list_w - 24 - status_w - SCROLLBAR_W
          color = row[:disabled] ? PopupWindow::DIM : (row[:color] || (selected ? PopupWindow::WHITE : PopupWindow::GRAY))
          label = row_label(row)
          if @options[:wrap_labels]
            lines = wrap_lines(bitmap, label, width).first(2)
            lines.each_with_index { |line, line_index| plain_text(bitmap, x, y - 6 + line_index * 16, width, 20, line, color, 0) }
          else
            plain_text(bitmap, x, y - 5, width, @row_h, fit_text(bitmap, label, width), color, 0)
          end
          plain_text(bitmap, @list_x + @list_w - status_w - 12, y - 5, status_w, @row_h, fit_text(bitmap, status, status_w), row[:disabled] ? PopupWindow::DIM : @theme[:title], 2) unless status.empty?
        end

        def draw_details(bitmap)
          return unless @detail_w && @detail_h
          PopupWindow.draw_rounded_rect(bitmap, @detail_x, @detail_y, @detail_w, @detail_h, 4, Color.new(18, 34, 58, 210))
          lines = wrap_lines(bitmap, @detail_text.to_s, @detail_w - 16)
          max_lines = [(@detail_h - 12) / 18, 1].max
          lines.first(max_lines).each_with_index do |line, index|
            plain_text(bitmap, @detail_x + 8, @detail_y + 2 + index * 18, @detail_w - 16, 20, line, @theme[:text], 0)
          end
        end

        def draw_footer(bitmap)
          return if @footer_h <= 0
          if defined?(Reloaded::HintText) && @options[:controls]
            Reloaded::HintText.draw_footer(
              bitmap,
              control_entries,
              8,
              @h - FOOTER_H,
              @w - 16,
              :size => 16,
              :height => FOOTER_H,
              :statuses => footer_statuses
            )
          else
            status = footer_statuses.map { |entry| entry[:text] }.join(" | ")
            plain_text(bitmap, 10, @h - FOOTER_H - 4, @w - 20, FOOTER_H, status, @theme[:dim], 1) unless status.empty?
          end
        end

        def footer_visible?
          return true unless footer_statuses.empty?
          return false unless @options[:controls] && defined?(Reloaded::HintText)
          Reloaded::HintText.enabled?
        rescue
          false
        end

        def footer_statuses
          values = @options[:footer_status]
          values = [values] unless values.is_a?(Array)
          values.compact.map do |value|
            if value.is_a?(Hash)
              value
            elsif defined?(Reloaded::HintText)
              Reloaded::HintText.status(value.to_s, @theme[:title])
            else
              { :text => value.to_s, :color => @theme[:title] }
            end
          end.reject { |entry| entry[:text].to_s.empty? }
        rescue
          []
        end

        def control_entries
          return [] unless defined?(Reloaded::HintText)
          entries = []
          entries << Reloaded::HintText.confirm(@options[:multi_select] ? "Toggle" : "Select")
          entries << Reloaded::HintText.back
          entries << Reloaded::HintText.other("Jump 3", :page)
          entries << Reloaded::HintText.other("Search (Click)") if @options[:search]
          entries
        rescue
          []
        end

        def controls_triggered?
          @options[:controls] && defined?(Reloaded::HintText) && Reloaded::HintText.triggered?
        rescue
          false
        end

        def controls_clicked?(local_x, local_y)
          return false unless @options[:controls] && defined?(Reloaded::HintText) && @footer_h > 0
          return false unless (Input.trigger?(Input::MOUSELEFT) rescue false)
          Reloaded::HintText.controls_at?(
            @sprites["picker"].bitmap,
            local_x,
            local_y,
            8,
            @h - FOOTER_H,
            @w - 16,
            :size => 16,
            :height => FOOTER_H
          )
        rescue
          false
        end

        def show_controls_popup
          return unless defined?(Reloaded::HintText)
          pbPlayDecisionSE rescue nil
          if @list_state
            @list_state.with_dialog { Reloaded::HintText.open_popup("Controls", control_entries) }
          else
            Reloaded::HintText.open_popup("Controls", control_entries)
          end
          draw
        rescue Exception => e
          PopupWindow.log_exception("ListPicker controls popup failed", e) if defined?(PopupWindow)
        end

        def draw_scrollbar(bitmap)
          return if @rows.length <= @visible_rows
          x = @list_x + @list_w - SCROLLBAR_W - 2
          y = @content_y + 4
          h = @visible_rows * @row_h - 8
          bitmap.fill_rect(x, y, SCROLLBAR_W, h, Color.new(24, 50, 82, 180))
          thumb_h = [[h * @visible_rows / @rows.length, 12].max, h].min
          max_scroll = [@rows.length - @visible_rows, 1].max
          thumb_y = y + ((h - thumb_h) * @scroll / max_scroll)
          bitmap.fill_rect(x, thumb_y, SCROLLBAR_W, thumb_h, @theme[:title])
        rescue
        end

        def update_detail
          row = @rows[@selected]
          @detail_text = ""
          return unless row && row[:kind] == :entry && !row[:header]
          callback = @options[:on_highlight]
          value = callback.call(public_row(row)) if callback.respond_to?(:call)
          value = row[:detail] if value.nil?
          @detail_text = value.to_s
        rescue Exception => e
          PopupWindow.log_exception("ListPicker highlight callback failed", e) if defined?(PopupWindow)
          @detail_text = row && row[:detail] ? row[:detail].to_s : ""
        end

        def show_disabled_reason(row)
          pbPlayBuzzerSE rescue nil
          reason = row[:disabled_reason].to_s
          reason = _INTL("This option is unavailable.") if reason.empty?
          callback = proc do
            if defined?(Reloaded::Toast)
              Reloaded::Toast.warning(reason)
            elsif defined?(Reloaded)
              Reloaded.message(reason, :theme => :warning)
            end
          end
          @list_state ? @list_state.with_dialog(&callback) : callback.call
        end

        def valid_selection?(value)
          validator = @options[:validator]
          return true unless validator.respond_to?(:call)
          result = validator.call(value)
          return true if result.nil? || result == true
          reason = result == false ? _INTL("This selection is unavailable.") : result.to_s
          callback = proc do
            if defined?(Reloaded::Toast)
              Reloaded::Toast.warning(reason)
            elsif defined?(Reloaded)
              Reloaded.message(reason, :theme => :warning)
            end
          end
          @list_state ? @list_state.with_dialog(&callback) : callback.call
          false
        rescue Exception => e
          PopupWindow.log_exception("ListPicker selection validation failed", e) if defined?(PopupWindow)
          false
        end

        def toggle_selected_value(value)
          if @selected_values.include?(value)
            @selected_values.delete(value)
          else
            @selected_values << value
          end
        end

        def reconcile_selected_values
          return unless @options[:multi_select]
          available = @all_rows.select do |row|
            row[:kind] == :entry && !row[:header] && !row[:disabled]
          end.map { |row| row[:value] }
          @selected_values.select! { |value| available.include?(value) }
        end

        def row_label(row)
          return row[:label].to_s unless @options[:multi_select] && row[:kind] == :entry
          marker = @selected_values.include?(row[:value]) ? "[x]" : "[ ]"
          "#{marker} #{row[:label]}"
        end

        def row_status(row)
          row[:status].to_s
        end

        def selected_value
          row = @rows[@selected]
          row && row[:kind] == :entry ? row[:value] : nil
        end

        def index_for_value(value)
          return nil if value.nil?
          @rows.index { |row| row[:kind] == :entry && row[:value] == value && selectable?(row) }
        end

        def first_selectable_index
          @rows.index { |row| selectable?(row) }
        end

        def selectable_indices
          @rows.each_index.select { |index| selectable?(@rows[index]) }
        end

        def selectable?(row)
          row && !row[:header] && !row[:disabled]
        end

        def special_row?(row)
          row[:kind] == :back || row[:kind] == :done
        end

        def insert_empty_row
          return if @rows.any? { |row| row[:kind] == :entry && !row[:header] }
          special_index = @rows.index { |row| special_row?(row) } || @rows.length
          @rows.insert(special_index, {
            :label => @options[:empty_text],
            :value => CANCEL_VALUE,
            :header => true,
            :disabled => true,
            :disabled_reason => "",
            :status => "",
            :detail => nil,
            :color => nil,
            :search_text => "",
            :kind => :empty,
            :source_index => -1
          })
        end

        def mouse_row_index(local_x, local_y)
          return nil if local_x < @list_x || local_x >= @list_x + @list_w
          return nil if local_y < @content_y || local_y >= @content_y + @list_h
          local = (local_y - @content_y) / @row_h
          return nil if local < 0 || local >= @visible_rows
          index = @scroll + local
          index < @rows.length ? index : nil
        end

        def ensure_visible
          return unless @list_state
          @list_state.visible_rows = @visible_rows
          @list_state.ensure_visible!
          sync_from_list_state
        end

        def row_signature(rows)
          rows.map { |row| [row[:label], row[:value], row[:header], row[:disabled], row[:status], row[:detail]] }
        rescue
          []
        end

        def public_row(row)
          row.reject { |key, _value| key == :kind }.dup
        end

        def wrap_lines(bitmap, text, width)
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

        def fit_text(bitmap, text, width)
          value = text.to_s
          return value if bitmap.text_size(value).width <= width
          suffix = "..."
          value = value[0...-1].to_s while !value.empty? && bitmap.text_size(value + suffix).width > width
          value + suffix
        rescue
          text.to_s
        end

        def draw_selection(bitmap, x, y, w, h)
          fill = pulsing_cursor_fill
          border = cursor_border
          if respond_to?(:reloaded_draw_rounded_rect)
            reloaded_draw_rounded_rect(bitmap, x, y, w, h, 4, fill, border)
          else
            PopupWindow.draw_rounded_rect(bitmap, x, y, w, h, 4, fill)
          end
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
    end
  end

  ListPicker = API::ListPicker unless const_defined?(:ListPicker, false)

  class << self
    def list_picker(title, rows, options = {})
      ListPicker.open(title, rows, options)
    rescue
      nil
    end
  end
end
