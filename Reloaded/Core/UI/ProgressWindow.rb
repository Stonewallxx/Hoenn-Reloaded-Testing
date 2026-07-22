#======================================================
# Reloaded Progress Window
# Author: Stonewall
#======================================================
# Shared HR-style progress UI for Reloaded::Task workers.
#======================================================

module Reloaded
  module API
    module ProgressWindow
      MODES = [:auto, :determinate, :indeterminate].freeze
      DEFAULT_WIDTH = 340
      BAR_H = 14
      CHOICE_H = 22

      class << self
        def show(handle, options = {})
          validate_handle!(handle)
          if defined?(Reloaded::Task) && Reloaded::Task.respond_to?(:updating?) && Reloaded::Task.updating?
            raise "ProgressWindow cannot open from inside a Task callback. Show it after starting the task instead."
          end
          opts = normalize_options(options)
          PopupWindow.with_modal do
            ProgressScene.new(handle, opts).main
          end
          Reloaded::Task.update if defined?(Reloaded::Task)
          handle.outcome
        rescue Exception => e
          PopupWindow.log_exception("ProgressWindow failed", e) if defined?(PopupWindow)
          nil
        end

        def run(key, options = {}, &worker)
          raise ArgumentError, "A progress worker block is required." unless worker
          opts = normalize_options(options)
          task_options = options[:task].is_a?(Hash) ? options[:task].dup : {}
          handle = Reloaded::Task.start(key, task_options, &worker)
          show(handle, opts)
        end

        def normalize_options(options)
          opts = {}
          (options || {}).each do |key, value|
            normalized_key = key.to_sym rescue key
            opts[normalized_key] = value
          end
          mode = (opts[:mode] || :auto).to_sym rescue :auto
          opts[:mode] = MODES.include?(mode) ? mode : :auto
          opts[:title] = (opts[:title] || _INTL("Working")).to_s
          opts[:stage] = (opts[:stage] || _INTL("Please wait...")).to_s
          opts[:cancellable] = !!opts[:cancellable]
          opts[:confirm_cancel] = true unless opts.key?(:confirm_cancel)
          opts[:cancel_text] = (opts[:cancel_text] || _INTL("Cancel")).to_s
          opts[:cancel_prompt] = (opts[:cancel_prompt] || _INTL("Cancel this operation?")).to_s
          opts[:cancelling_text] = (opts[:cancelling_text] || _INTL("Cancelling...")).to_s
          opts[:theme] = (opts[:theme] || :hr).to_sym rescue :hr
          opts[:theme] = :hr unless PopupWindow::THEMES[opts[:theme]]
          opts[:show_dim] = true unless opts.key?(:show_dim)
          opts[:minimum_visible_time] = [opts.fetch(:minimum_visible_time, 0.2).to_f, 0.0].max
          opts[:width] = [[(opts[:width] || DEFAULT_WIDTH).to_i, PopupWindow::MIN_W].max, PopupWindow::MAX_W].min
          opts[:z] = (opts[:z] || 999_999_999).to_i
          opts
        end

        private

        def validate_handle!(handle)
          valid = handle && handle.respond_to?(:state) && handle.respond_to?(:progress) &&
                  handle.respond_to?(:stage) && handle.respond_to?(:cancel)
          raise ArgumentError, "ProgressWindow requires a Reloaded::Task handle." unless valid
          raise ArgumentError, "ProgressWindow received an unknown or expired task handle." if handle.state.nil?
          true
        end
      end

      class ProgressScene
        include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

        def initialize(handle, options)
          @handle = handle
          @options = options
          @theme = PopupWindow::THEMES[@options[:theme]] || PopupWindow::THEMES[:hr]
          @sprites = {}
          @opened_at = Time.now.to_f
          @cancel_requested = false
          @last_signature = nil
        end

        def main
          setup
          draw
          loop do
            Graphics.update
            Input.update
            snapshot = task_snapshot
            signature = snapshot_signature(snapshot)
            if signature != @last_signature || animated_redraw?
              @last_signature = signature
              draw(snapshot)
            end
            return if finished_and_releasable?(snapshot)
            update_cancel_input(snapshot)
          end
        ensure
          dispose
          drain_input
        end

        def setup
          @w = @options[:width]
          @title_y = 3
          @stage_y = 28
          @bar_y = 57
          @percent_y = 67
          @choice_y = 97
          @h = @options[:cancellable] ? 130 : 98
          @x = (PopupWindow::SCREEN_W - @w) / 2
          @y = (PopupWindow::SCREEN_H - @h) / 2
          @viewport = Viewport.new(0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          @viewport.z = @options[:z]
          @sprites["dim"] = Sprite.new(@viewport)
          @sprites["dim"].bitmap = Bitmap.new(PopupWindow::SCREEN_W, PopupWindow::SCREEN_H)
          if @options[:show_dim]
            @sprites["dim"].bitmap.fill_rect(0, 0, PopupWindow::SCREEN_W, PopupWindow::SCREEN_H, PopupWindow::DIM_BG)
          end
          @sprites["progress"] = Sprite.new(@viewport)
          @sprites["progress"].x = @x
          @sprites["progress"].y = @y
          @sprites["progress"].z = @options[:z]
          @sprites["progress"].bitmap = Bitmap.new(@w, @h)
        end

        def draw(snapshot = nil)
          snapshot ||= task_snapshot
          bitmap = @sprites["progress"].bitmap
          bitmap.clear
          PopupWindow.draw_panel(bitmap, @w, @h, @theme, self)
          pbSetSmallFont(bitmap) rescue nil
          plain_text(bitmap, 14, @title_y, @w - 28, 24, fit_text(bitmap, @options[:title], @w - 28), @theme[:title], 1)
          stage = display_stage(snapshot)
          plain_text(bitmap, 18, @stage_y, @w - 36, 24, fit_text(bitmap, stage, @w - 36), @theme[:text], 1)
          draw_progress_bar(bitmap, snapshot)
          draw_cancel_row(bitmap, snapshot) if @options[:cancellable]
        rescue Exception => e
          PopupWindow.log_exception("ProgressWindow draw failed", e) if defined?(PopupWindow)
        end

        def draw_progress_bar(bitmap, snapshot)
          x = 18
          width = @w - 36
          track = Color.new(18, 34, 58, 225)
          border = @theme[:border] || PopupWindow::PANEL_BORDER
          PopupWindow.draw_rounded_rect(bitmap, x, @bar_y, width, BAR_H, 4, border)
          PopupWindow.draw_rounded_rect(bitmap, x + 1, @bar_y + 1, width - 2, BAR_H - 2, 3, track)
          progress = displayed_progress(snapshot)
          if progress.nil?
            draw_indeterminate_fill(bitmap, x + 2, @bar_y + 2, width - 4, BAR_H - 4)
          else
            fill_width = ((width - 4) * progress).round
            PopupWindow.draw_rounded_rect(bitmap, x + 2, @bar_y + 2, fill_width, BAR_H - 4, 3, @theme[:title]) if fill_width > 0
          end
          percent = progress.nil? ? "" : "#{(progress * 100).round}%"
          plain_text(bitmap, 18, @percent_y, @w - 36, 22, percent, @theme[:dim], 1)
        end

        def draw_indeterminate_fill(bitmap, x, y, width, height)
          segment = [[width / 4, 26].max, width].min
          travel = [width - segment, 1].max
          frame = Graphics.frame_count.to_i rescue 0
          position = frame % (travel * 2)
          position = travel * 2 - position if position > travel
          PopupWindow.draw_rounded_rect(bitmap, x + position, y, segment, height, 3, @theme[:title])
        end

        def draw_cancel_row(bitmap, snapshot)
          cancelling = cancel_pending?(snapshot)
          unless cancelling
            draw_selection(bitmap, 12, @choice_y, @w - 24, CHOICE_H)
          end
          color = cancelling ? @theme[:dim] : @theme[:text]
          label = cancelling ? @options[:cancelling_text] : @options[:cancel_text]
          plain_text(bitmap, 20, @choice_y - 6, @w - 40, CHOICE_H, label, color, 1)
        end

        def update_cancel_input(snapshot)
          return unless @options[:cancellable]
          return if cancel_pending?(snapshot) || task_finished?(snapshot)
          mouse_cancel = cancel_mouse_triggered?
          input_cancel = (Input.trigger?(Input::BACK) rescue false) || (Input.trigger?(Input::USE) rescue false)
          return unless mouse_cancel || input_cancel
          confirmed = true
          if @options[:confirm_cancel]
            confirmed = Reloaded::PopupWindow.confirm(
              @options[:cancel_prompt],
              :default => false,
              :yes_label => _INTL("Cancel"),
              :no_label => _INTL("Keep Running")
            )
          end
          if confirmed
            @cancel_requested = @handle.cancel
            pbPlayCancelSE rescue nil
          else
            pbPlayCursorSE rescue nil
          end
          draw
        rescue Exception => e
          PopupWindow.log_exception("ProgressWindow cancellation failed", e) if defined?(PopupWindow)
        end

        def cancel_mouse_triggered?
          position = Reloaded::MouseInput.active_position rescue nil
          return false unless position && (Input.const_defined?(:MOUSELEFT) rescue false)
          clicked = Input.trigger?(Input::MOUSELEFT) rescue false
          return false unless clicked
          local_x = position[0].to_i - @x
          local_y = position[1].to_i - @y
          local_x >= 12 && local_x < @w - 12 && local_y >= @choice_y && local_y < @choice_y + CHOICE_H
        rescue
          false
        end

        def task_snapshot
          return @handle.snapshot if @handle.respond_to?(:snapshot)
          Reloaded::Task.snapshot(@handle)
        rescue
          nil
        end

        def snapshot_signature(snapshot)
          return [:missing] unless snapshot
          [snapshot[:state], snapshot[:progress], snapshot[:stage], snapshot[:cancel_requested]]
        end

        def display_stage(snapshot)
          return @options[:cancelling_text] if cancel_pending?(snapshot)
          value = snapshot ? snapshot[:stage].to_s.strip : ""
          value.empty? ? @options[:stage] : value
        end

        def displayed_progress(snapshot)
          return nil if cancel_pending?(snapshot)
          return nil if @options[:mode] == :indeterminate
          value = snapshot && snapshot[:progress]
          return nil if value.nil? && @options[:mode] == :auto
          value = 0.0 if value.nil?
          [[value.to_f, 0.0].max, 1.0].min
        rescue
          nil
        end

        def cancel_pending?(snapshot)
          @cancel_requested || !!(snapshot && snapshot[:cancel_requested])
        end

        def task_finished?(snapshot)
          state = snapshot && snapshot[:state]
          state == :ready || (defined?(Reloaded::Task) && Reloaded::Task.terminal_state?(state))
        rescue
          false
        end

        def finished_and_releasable?(snapshot)
          return false unless task_finished?(snapshot)
          return false if Time.now.to_f - @opened_at < @options[:minimum_visible_time]
          input_neutral?
        rescue
          false
        end

        def input_neutral?
          names = [:USE, :BACK, :ACTION, :SPECIAL, :UP, :DOWN, :LEFT, :RIGHT, :MOUSELEFT, :MOUSERIGHT]
          names.none? do |name|
            next false unless Input.const_defined?(name)
            Input.press?(Input.const_get(name)) rescue false
          end
        rescue
          true
        end

        def animated_redraw?
          ((Graphics.frame_count rescue 0) % 4) == 0
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
  end

  ProgressWindow = API::ProgressWindow unless const_defined?(:ProgressWindow, false)
end
