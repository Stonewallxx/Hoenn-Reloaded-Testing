#======================================================
# Reloaded Mod Manager UI
# Author: Stonewall
#======================================================
# In-game UI for viewing installed mods and editing the active profile.
#
# Responsibilities:
#   - Show installed mods in a two-panel Mod Manager scene.
#   - Support keyboard/controller and mouse navigation.
#   - Toggle mods through Reloaded profile APIs.
#   - Display dependency, incompatibility, profile, and validation details.
#   - Provide a stable UI entry point for future profile/settings/browser work.
#
#======================================================

module Reloaded
  module ModManagerUI
    SCREEN_W = 512
    SCREEN_H = 384

    TITLE_H = 34
    FOOTER_H = 30
    MARGIN = 8
    GAP = 8
    LEFT_W = 206
    RIGHT_W = SCREEN_W - LEFT_W - (MARGIN * 2) - GAP
    CONTENT_Y = TITLE_H + 6
    CONTENT_H = SCREEN_H - TITLE_H - FOOTER_H - 16
    SEARCH_H = 24
    LIST_Y = 36
    ROW_H = 22
    LIST_H = CONTENT_H - LIST_Y - 8

    WHITE = Color.new(255, 255, 255)
    GRAY = Color.new(174, 198, 220)
    DIM = Color.new(101, 132, 164)
    SHADOW = Color.new(5, 10, 22)
    GREEN = Color.new(105, 224, 164)
    RED = Color.new(235, 96, 116)
    YELLOW = Color.new(246, 218, 112)
    ORANGE = Color.new(244, 157, 88)
    BLUE = Color.new(104, 190, 255)
    PURPLE = Color.new(176, 160, 255)

    BG = Color.new(7, 14, 29)
    TITLE_BG = Color.new(9, 23, 43)
    PANEL_BG = Color.new(12, 28, 50)
    PANEL_BG_ALT = Color.new(16, 38, 67)
    PANEL_BORDER = Color.new(39, 83, 132)
    PANEL_LINE = Color.new(28, 61, 101)
    ROW_NORMAL = Color.new(25, 57, 94, 55)
    ROW_DISABLED = Color.new(11, 25, 44, 80)
    TAG_BG = Color.new(19, 48, 82)
    FOOTER_BG = Color.new(8, 20, 38)
    FOOTER_SEL = Color.new(23, 78, 125)
    SEARCH_BG = Color.new(10, 24, 43)
    SEARCH_ACTIVE = Color.new(15, 49, 82)
    SELECTION_FILL = Color.new(74, 158, 238)
    SELECTION_BORDER = Color.new(210, 236, 255)

    FOOTER_BUTTONS = ["Browser"].freeze

    class << self
      def open
        Scene_Installed.new.main
      rescue Exception => e
        Reloaded::Log.exception("Failed to open Mod Manager UI", e, channel: :mods) if defined?(Reloaded::Log)
        pbMessage("Mod Manager failed to open.") rescue nil
      end
    end

    module InputSupport
      KEYBOARD_INPUTS = [
        Input::UP, Input::DOWN, Input::LEFT, Input::RIGHT,
        Input::USE, Input::BACK
      ].tap { |keys|
        keys << Input::ACTION if Input.const_defined?(:ACTION)
        keys << Input::SPECIAL if Input.const_defined?(:SPECIAL)
      }.freeze

      @mouse_active = false
      @last_mx = nil
      @last_my = nil

      class << self
        def mouse_pos
          mx = Input.mouse_x rescue nil
          my = Input.mouse_y rescue nil
          if KEYBOARD_INPUTS.any? { |key| Input.trigger?(key) rescue false }
            @mouse_active = false
          end
          if mx && my && (mx != @last_mx || my != @last_my)
            @last_mx = mx
            @last_my = my
            @mouse_active = true
          end
          @mouse_active ? [mx, my] : [nil, nil]
        rescue
          [nil, nil]
        end

        def mouse_left_trigger?
          return false unless Input.const_defined?(:MOUSELEFT)
          Input.trigger?(Input::MOUSELEFT)
        rescue
          false
        end

        def mouse_right_trigger?
          return false unless Input.const_defined?(:MOUSERIGHT)
          Input.trigger?(Input::MOUSERIGHT)
        rescue
          false
        end

        def mouse_left_press?
          return false unless Input.const_defined?(:MOUSELEFT)
          Input.press?(Input::MOUSELEFT)
        rescue
          false
        end

        def mouse_scroll
          Input.scroll_v rescue 0
        rescue
          0
        end
      end
    end

    module UIHelpers
      def draw_rounded_rect(bitmap, x, y, width, height, color)
        bitmap.fill_rect(x + 2, y, width - 4, height, color)
        bitmap.fill_rect(x, y + 2, width, height - 4, color)
        bitmap.fill_rect(x + 1, y + 1, width - 2, height - 2, color)
      end

      def draw_border(bitmap, x, y, width, height, color)
        bitmap.fill_rect(x + 2, y, width - 4, 1, color)
        bitmap.fill_rect(x + 2, y + height - 1, width - 4, 1, color)
        bitmap.fill_rect(x, y + 2, 1, height - 4, color)
        bitmap.fill_rect(x + width - 1, y + 2, 1, height - 4, color)
      end

      def global_small_text?
        ($PokemonSystem.reloaded_small_text rescue 1).to_i == 1
      end

      def apply_ui_font(bitmap)
        global_small_text? ? pbSetSmallFont(bitmap) : pbSetSystemFont(bitmap)
      end

      def color_with_alpha(color, alpha)
        Color.new(color.red, color.green, color.blue, alpha)
      rescue
        Color.new(255, 255, 255, alpha)
      end

      def pulse_value
        Math.sin((Graphics.frame_count rescue 0) * Math::PI / 20.0) * 0.5 + 0.5
      end

      def draw_selection_box(bitmap, x, y, width, height, fill = nil, _border = nil)
        pulse = pulse_value
        fill ||= color_with_alpha(FOOTER_SEL, (110 + (170 - 110) * pulse).to_i)
        draw_rounded_rect(bitmap, x, y, width, height, fill)
      end

      def draw_selection_fill(bitmap, x, y, width, height, fill = nil)
        draw_selection_box(bitmap, x, y, width, height, fill)
      end

      def draw_hint_text(bitmap, text, x, y, width, height = 16)
        apply_ui_font(bitmap)
        bitmap.font.size = 12 rescue nil
        pbDrawShadowText(bitmap, x, y, width, height, text.to_s, DIM, SHADOW, 1)
      end

      def draw_panel_hint(bitmap, text, width, height)
        bitmap.fill_rect(8, height - 26, width - 16, 1, PANEL_LINE)
        draw_hint_text(bitmap, text, 8, height - 20, width - 16)
      end

      def footer_button_rect(index, buttons)
        count = [buttons.length, 1].max
        width = SCREEN_W / count
        x = index * width
        width = SCREEN_W - x if index == count - 1
        [x, 0, width, FOOTER_H]
      end

      def footer_buttons
        buttons = self.class.const_defined?(:FOOTER_BUTTONS) ? self.class::FOOTER_BUTTONS : FOOTER_BUTTONS
        normal, back = buttons.partition { |label| label.to_s.downcase != "back" }
        normal + back
      end

      def footer_button_at(x)
        buttons = footer_buttons
        return nil if buttons.empty?
        buttons.each_index do |index|
          bx, by, bw, bh = footer_button_rect(index, buttons)
          return index if x >= bx && x < bx + bw
        end
        nil
      end

      def draw_footer_buttons(bitmap, buttons)
        bitmap.clear
        bitmap.fill_rect(0, 0, SCREEN_W, FOOTER_H, FOOTER_BG)
        bitmap.fill_rect(0, 0, SCREEN_W, 1, PANEL_BORDER)
        apply_ui_font(bitmap)
        buttons.each_with_index do |label, index|
          x, y, width, height = footer_button_rect(index, buttons)
          selected = @focus == :footer && @footer_index == index
          if selected
            draw_selection_box(bitmap, x + 2, y + 4, width - 4, height - 8)
          end
          color = selected ? WHITE : GRAY
          pbDrawShadowText(bitmap, x + 4, y + 3, width - 8, height - 10, label.to_s, color, SHADOW, 1)
        end
      end

      def draw_panel(bitmap, width, height, title = nil)
        draw_rounded_rect(bitmap, 0, 0, width, height, PANEL_BG)
        draw_border(bitmap, 0, 0, width, height, PANEL_BORDER)
        return unless title
        bitmap.fill_rect(1, 1, width - 2, 24, PANEL_BG_ALT)
        bitmap.fill_rect(8, 25, width - 16, 1, PANEL_LINE)
        apply_ui_font(bitmap)
        pbDrawShadowText(bitmap, 10, 3, width - 20, 18, title, BLUE, SHADOW)
      end

      def text_color_for_status(status)
        case status
        when :enabled then GREEN
        when :disabled then DIM
        when :missing_dependency then ORANGE
        when :conflict, :broken, :invalid, :missing then RED
        else GRAY
        end
      end

      def trim_text(bitmap, text, max_width)
        value = text.to_s.dup
        return value if bitmap.text_size(value).width <= max_width
        value = value[0...-1] while value.length > 0 && bitmap.text_size(value + "..").width > max_width
        value + ".."
      end

      def wrapped_lines(bitmap, text, max_width)
        lines = []
        text.to_s.split("\n").each do |raw|
          words = raw.split(" ")
          if words.empty?
            lines << ""
            next
          end
          current = ""
          words.each do |word|
            test = current.empty? ? word : "#{current} #{word}"
            if bitmap.text_size(test).width > max_width && !current.empty?
              lines << current
              current = word
            else
              current = test
            end
          end
          lines << current unless current.empty?
        end
        lines
      end

      def show_message(text, choices = nil, start_index = 0, center_text = false)
        dim = Sprite.new(@viewport)
        dim.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
        dim.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, Color.new(0, 0, 0, 130))
        dim.z = 900

        lines = text.to_s.split("\n")
        choice_count = choices ? choices.length : 0
        line_h = 18
        pad = 14
        hint_h = choices ? 18 : 0
        box_w = 420
        box_h = pad * 2 + lines.length * line_h + (choices ? choice_count * line_h + hint_h + 10 : line_h + 4)
        box_x = (SCREEN_W - box_w) / 2
        box_y = (SCREEN_H - box_h) / 2

        box = Sprite.new(@viewport)
        box.bitmap = Bitmap.new(box_w, box_h)
        box.x = box_x
        box.y = box_y
        box.z = 901

        selected = start_index.to_i
        selected = [[selected, 0].max, [choice_count - 1, 0].max].min

        redraw = proc do
          bitmap = box.bitmap
          bitmap.clear
          draw_rounded_rect(bitmap, 0, 0, box_w, box_h, PANEL_BG)
          draw_border(bitmap, 0, 0, box_w, box_h, PANEL_BORDER)
          apply_ui_font(bitmap)
          y = pad
          lines.each do |line|
            align = center_text ? 1 : 0
            pbDrawShadowText(bitmap, pad, y, box_w - pad * 2, line_h, line, WHITE, SHADOW, align)
            y += line_h
          end
          if choices
            y += 4
            choices.each_with_index do |choice, index|
              row_y = y + index * line_h
              draw_selection_box(bitmap, pad, row_y, box_w - pad * 2, line_h) if index == selected
              color = index == selected ? WHITE : GRAY
              pbDrawShadowText(bitmap, pad + 8, row_y - 3, box_w - pad * 2, line_h, choice.to_s, color, SHADOW)
            end
            draw_hint_text(bitmap, "Confirm (C) Back (B)", 0, box_h - 20, box_w)
          else
            pbDrawShadowText(bitmap, -10, y + 4, box_w, line_h, "[OK]", GRAY, SHADOW, 1)
          end
        end

        redraw.call
        loop do
          Graphics.update
          Input.update
          redraw.call if choices && ((Graphics.frame_count rescue 0) % 4 == 0)
          old_selected = selected
          if choices
            selected = (selected - 1 + choices.length) % choices.length if Input.trigger?(Input::UP)
            selected = (selected + 1) % choices.length if Input.trigger?(Input::DOWN)
            mx, my = InputSupport.mouse_pos
            if mx && my && mx >= box_x + pad && mx < box_x + box_w - pad
              choice_y = box_y + pad + lines.length * line_h + 4
              choices.each_with_index do |_, index|
                y = choice_y + index * line_h
                selected = index if my >= y && my < y + line_h
              end
            end
            redraw.call if selected != old_selected
            break if Input.trigger?(Input::C) || InputSupport.mouse_left_trigger?
            if Input.trigger?(Input::B) || InputSupport.mouse_right_trigger?
              selected = choices.length
              break
            end
          else
            break if Input.trigger?(Input::C) || Input.trigger?(Input::B) || InputSupport.mouse_left_trigger?
          end
        end
        selected
      ensure
        box.bitmap.dispose rescue nil
        box.dispose rescue nil
        dim.bitmap.dispose rescue nil
        dim.dispose rescue nil
      end

      def init_keyboard
        @_gas ||= Win32API.new("user32", "GetAsyncKeyState", ["i"], "i") rescue nil
      end

      def key_trigger?(vk)
        init_keyboard
        return false unless @_gas
        (@_gas.call(vk) & 0x01) != 0
      rescue
        false
      end

      def key_pressed?(vk)
        init_keyboard
        return false unless @_gas
        (@_gas.call(vk) & 0x8000) != 0
      rescue
        false
      end

      def key_repeat?(vk)
        @_repeat ||= {}
        if key_pressed?(vk)
          @_repeat[vk] ||= 0
          @_repeat[vk] += 1
          count = @_repeat[vk]
          count == 1 || (count > 12 && count % 4 == 0)
        else
          @_repeat[vk] = 0
          false
        end
      end

      def special_trigger?
        Input.trigger?(Input::SPECIAL)
      rescue
        false
      end

      def menu_trigger?
        return true if Input.const_defined?(:ACTION) && Input.trigger?(Input::ACTION)
        false
      rescue
        false
      end

      def text_input_popup(title, initial = "", max_length = 32)
        dim = Sprite.new(@viewport)
        dim.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
        dim.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, Color.new(0, 0, 0, 130))
        dim.z = 900

        box_w = 380
        box_h = 116
        box_x = (SCREEN_W - box_w) / 2
        box_y = (SCREEN_H - box_h) / 2
        box = Sprite.new(@viewport)
        box.bitmap = Bitmap.new(box_w, box_h)
        box.x = box_x
        box.y = box_y
        box.z = 901

        value = initial.to_s[0, max_length]
        accepted = false
        redraw = proc do
          bitmap = box.bitmap
          bitmap.clear
          draw_rounded_rect(bitmap, 0, 0, box_w, box_h, PANEL_BG)
          draw_border(bitmap, 0, 0, box_w, box_h, PANEL_BORDER)
          apply_ui_font(bitmap)
          pbDrawShadowText(bitmap, 14, 10, box_w - 28, 18, title.to_s, WHITE, SHADOW)
          draw_rounded_rect(bitmap, 14, 38, box_w - 28, 28, SEARCH_ACTIVE)
          draw_border(bitmap, 14, 38, box_w - 28, 28, PANEL_LINE)
          cursor = ((Graphics.frame_count rescue 0) / 20) % 2 == 0 ? "|" : ""
          shown = trim_text(bitmap, value + cursor, box_w - 42)
          pbDrawShadowText(bitmap, 22, 43, box_w - 44, 18, shown, WHITE, SHADOW)
          bitmap.font.size = 12 rescue nil
          draw_hint_text(bitmap, "Confirm (Enter) Back (Esc/Right Click)", 0, box_h - 20, box_w)
        end

        redraw.call
        loop do
          Graphics.update
          Input.update
          redraw.call if ((Graphics.frame_count rescue 0) % 4 == 0)
          if key_trigger?(0x1B) || InputSupport.mouse_right_trigger?
            accepted = false
            break
          end
          if key_trigger?(0x0D)
            accepted = true
            break
          end
          old_value = value.dup
          value = value[0...-1] if key_repeat?(0x08) && !value.empty?
          value = "" if key_trigger?(0x2E)
          (0x41..0x5A).each do |vk|
            next unless key_trigger?(vk)
            char = (vk - 0x41 + 97).chr
            char = char.upcase if key_pressed?(0x10)
            value += char if value.length < max_length
          end
          (0x30..0x39).each do |vk|
            value += (vk - 0x30).to_s if key_trigger?(vk) && value.length < max_length
          end
          value += " " if key_trigger?(0x20) && value.length < max_length
          value += "-" if key_trigger?(0xBD) && value.length < max_length
          value += "_" if key_trigger?(0xBF) && value.length < max_length
          redraw.call if value != old_value
        end
        accepted ? value.strip : ""
      ensure
        box.bitmap.dispose rescue nil
        box.dispose rescue nil
        dim.bitmap.dispose rescue nil
        dim.dispose rescue nil
      end
    end

    class Scene_Profiles
      include UIHelpers

      FOOTER_BUTTONS = ["Back"].freeze
      PROFILE_LEFT_W = 180
      PROFILE_RIGHT_W = SCREEN_W - PROFILE_LEFT_W - (MARGIN * 2) - GAP
      PROFILE_ROW_H = 24
      PROFILE_LIST_Y = 8

      def initialize
        @viewport = nil
        @running = false
        @profiles = []
        @selected_index = 0
        @scroll = 0
        @footer_index = 0
        @focus = :list
        @cursor_frame = 0
        @restart_required = false
      end

      def main
        Graphics.freeze
        setup
        Graphics.transition(8)
        loop do
          Graphics.update
          Input.update
          break unless @running
          @cursor_frame += 1
          if @cursor_frame % 4 == 0
            draw_left if @focus == :list
            draw_footer if @focus == :footer
          end
          handle_input
        end
        Graphics.freeze
        restart_required = @restart_required
        teardown
        Graphics.transition(8)
        restart_required
      end

      def setup
        @running = true
        Reloaded::Profiles.boot if defined?(Reloaded::Profiles)
        @viewport = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
        @viewport.z = 100_010

        @background = Sprite.new(@viewport)
        @background.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
        @background.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, BG)

        @title_sprite = Sprite.new(@viewport)
        @title_sprite.bitmap = Bitmap.new(SCREEN_W, TITLE_H)
        @title_sprite.z = 10

        @left_sprite = Sprite.new(@viewport)
        @left_sprite.bitmap = Bitmap.new(PROFILE_LEFT_W, CONTENT_H)
        @left_sprite.x = MARGIN
        @left_sprite.y = CONTENT_Y
        @left_sprite.z = 10

        @right_sprite = Sprite.new(@viewport)
        @right_sprite.bitmap = Bitmap.new(PROFILE_RIGHT_W, CONTENT_H)
        @right_sprite.x = MARGIN + PROFILE_LEFT_W + GAP
        @right_sprite.y = CONTENT_Y
        @right_sprite.z = 10

        @footer_sprite = Sprite.new(@viewport)
        @footer_sprite.bitmap = Bitmap.new(SCREEN_W, FOOTER_H)
        @footer_sprite.y = SCREEN_H - FOOTER_H
        @footer_sprite.z = 10

        refresh_profiles
        draw_all
      end

      def teardown
        [@footer_sprite, @right_sprite, @left_sprite, @title_sprite, @background].compact.each do |sprite|
          sprite.bitmap.dispose rescue nil
          sprite.dispose rescue nil
        end
        @viewport.dispose rescue nil
      end

      def draw_all
        draw_title
        draw_left
        draw_right
        draw_footer
      end

      def refresh_profiles
        @profiles = Reloaded::Profiles.list rescue []
        @selected_index = [[@selected_index, 0].max, [@profiles.length - 1, 0].max].min
        ensure_visible
      end

      def selected_profile
        @profiles[@selected_index]
      end

      def rows_per_page
        ((CONTENT_H - PROFILE_LIST_Y - 8) / PROFILE_ROW_H).floor
      end

      def ensure_visible
        page = rows_per_page
        @scroll = @selected_index if @selected_index < @scroll
        @scroll = @selected_index - page + 1 if @selected_index >= @scroll + page
        @scroll = [[@scroll, 0].max, [@profiles.length - page, 0].max].min
      end

      def active_name
        Reloaded::Profiles.active_name rescue "Default"
      end

      def active_profile?(profile)
        profile && profile["name"].to_s.downcase == active_name.to_s.downcase
      end

      def default_profile?(profile)
        profile && profile["name"].to_s.downcase == Reloaded::Profiles::DEFAULT_PROFILE_NAME.downcase
      rescue
        false
      end

      def draw_title
        bitmap = @title_sprite.bitmap
        bitmap.clear
        bitmap.fill_rect(0, 0, SCREEN_W, TITLE_H, TITLE_BG)
        bitmap.fill_rect(MARGIN, TITLE_H - 2, SCREEN_W - MARGIN * 2, 1, PANEL_BORDER)
        pbSetSystemFont(bitmap)
        bitmap.font.size = 19
        pbDrawShadowText(bitmap, MARGIN, 6, -1, 22, "Profiles", WHITE, SHADOW)
        apply_ui_font(bitmap)
        bitmap.font.size = 12 rescue nil
        pbDrawShadowText(bitmap, 260, 9, SCREEN_W - 268, 14, "Active: #{active_name}", BLUE, SHADOW, 1)
      end

      def draw_left
        bitmap = @left_sprite.bitmap
        bitmap.clear
        draw_panel(bitmap, PROFILE_LEFT_W, CONTENT_H)
        apply_ui_font(bitmap)
        visible = @profiles[@scroll, rows_per_page] || []
        visible.each_with_index do |profile, offset|
          index = @scroll + offset
          y = PROFILE_LIST_Y + offset * PROFILE_ROW_H
          selected = index == @selected_index && @focus == :list
          active = active_profile?(profile)
          draw_rounded_rect(bitmap, 6, y, PROFILE_LEFT_W - 12, PROFILE_ROW_H - 3, active ? ROW_NORMAL : ROW_DISABLED)
          draw_selection_box(bitmap, 6, y - 1, PROFILE_LEFT_W - 12, PROFILE_ROW_H - 2) if selected
          color = active ? GREEN : GRAY
          marker = active ? "*" : " "
          name = trim_text(bitmap, "#{marker} #{profile["name"]}", PROFILE_LEFT_W - 28)
          pbDrawShadowText(bitmap, 14, y - 1, PROFILE_LEFT_W - 28, PROFILE_ROW_H, name, selected ? WHITE : color, SHADOW)
        end
        pbDrawShadowText(bitmap, PROFILE_LEFT_W / 2 - 10, 0, 20, 12, "^", GRAY, SHADOW, 1) if @scroll > 0
        if @scroll + rows_per_page < @profiles.length
          pbDrawShadowText(bitmap, PROFILE_LEFT_W / 2 - 10, CONTENT_H - 16, 20, 12, "v", GRAY, SHADOW, 1)
        end
      end

      def draw_right
        bitmap = @right_sprite.bitmap
        bitmap.clear
        profile = selected_profile
        draw_panel(bitmap, PROFILE_RIGHT_W, CONTENT_H, profile ? profile["name"].to_s : "Profile")
        unless profile
          draw_panel_hint(bitmap, "Confirm (C) Back (B) Menu (A)", PROFILE_RIGHT_W, CONTENT_H)
          return
        end

        summary = Reloaded::Profiles.summary(profile["name"]) rescue {}
        x = 12
        y = 32
        apply_ui_font(bitmap)
        bitmap.font.size = 14 rescue nil
        status = active_profile?(profile) ? "Active" : "Inactive"
        pbDrawShadowText(bitmap, x, y, PROFILE_RIGHT_W - 24, 16, status, active_profile?(profile) ? GREEN : RED, SHADOW)
        y += 22
        pbDrawShadowText(bitmap, x, y, PROFILE_RIGHT_W - 24, 16, "Enabled Mods: #{summary[:enabled_mods] || 0}", GRAY, SHADOW)
        y += 18
        pbDrawShadowText(bitmap, x, y, PROFILE_RIGHT_W - 24, 16, "Disabled Mods: #{summary[:disabled_mods] || 0}", GRAY, SHADOW)
        y += 18
        pbDrawShadowText(bitmap, x, y, PROFILE_RIGHT_W - 24, 16, "Load Order Entries: #{summary[:load_order] || 0}", GRAY, SHADOW)
        y += 18
        pbDrawShadowText(bitmap, x, y, PROFILE_RIGHT_W - 24, 16, "Mod Settings: #{summary[:mod_settings] || 0}", GRAY, SHADOW)
        y += 24
        bitmap.fill_rect(x, y, PROFILE_RIGHT_W - 24, 1, PANEL_BORDER)
        y += 8
        bitmap.font.size = 15 rescue nil
        pbDrawShadowText(bitmap, x, y, PROFILE_RIGHT_W - 24, 16, "Notes", BLUE, SHADOW)
        y += 18
        apply_ui_font(bitmap)
        bitmap.font.size = 14 rescue nil
        notes = profile["notes"].to_s.empty? ? "No notes set." : profile["notes"].to_s
        wrapped_lines(bitmap, notes, PROFILE_RIGHT_W - 28).each do |line|
          break if y + 16 > CONTENT_H - 32
          pbDrawShadowText(bitmap, x, y, PROFILE_RIGHT_W - 28, 16, line, DIM, SHADOW)
          y += 16
        end
        draw_panel_hint(bitmap, "Confirm (C) Back (B) Menu (A)", PROFILE_RIGHT_W, CONTENT_H)
      end

      def draw_footer
        draw_footer_buttons(@footer_sprite.bitmap, footer_buttons)
      end

      def handle_input
        handle_mouse
        if Input.trigger?(Input::B) || InputSupport.mouse_right_trigger?
          @running = false
          return
        end
        if menu_trigger?
          open_profile_menu
          return
        end
        @focus == :list ? handle_list_input : handle_footer_input
      end

      def handle_mouse
        mx, my = InputSupport.mouse_pos
        return unless mx && my
        clicked = InputSupport.mouse_left_trigger?
        old_selected = @selected_index
        old_focus = @focus
        old_footer = @footer_index

        lx = @left_sprite.x
        ly = @left_sprite.y
        if mx >= lx && mx < lx + PROFILE_LEFT_W && my >= ly + PROFILE_LIST_Y && my < ly + CONTENT_H
          row = ((my - ly - PROFILE_LIST_Y) / PROFILE_ROW_H).floor
          index = @scroll + row
          if index >= 0 && index < @profiles.length
            @focus = :list
            @selected_index = index
          end
        end

        fy = @footer_sprite.y
        if my >= fy && my < fy + FOOTER_H
          footer_index = footer_button_at(mx)
          if footer_index
            @focus = :footer
            @footer_index = footer_index
            execute_footer(@footer_index) if clicked
          end
        end

        draw_left if old_selected != @selected_index || old_focus != @focus
        draw_right if old_selected != @selected_index
        draw_footer if old_focus != @focus || old_footer != @footer_index
      end

      def handle_list_input
        changed = false
        if Input.trigger?(Input::DOWN) && (@profiles.empty? || @selected_index >= @profiles.length - 1)
          @focus = :footer
          draw_left
          draw_footer
          return
        end
        if Input.repeat?(Input::UP) && !@profiles.empty?
          @selected_index = (@selected_index - 1 + @profiles.length) % @profiles.length
          ensure_visible
          changed = true
        elsif Input.repeat?(Input::DOWN) && !@profiles.empty?
          @selected_index = (@selected_index + 1) % @profiles.length
          ensure_visible
          changed = true
        end
        activate_selected_profile if Input.trigger?(Input::C)
        if changed
          draw_left
          draw_right
        end
      end

      def handle_footer_input
        if Input.trigger?(Input::UP)
          @focus = :list
          draw_left
          draw_footer
        elsif Input.trigger?(Input::LEFT) && footer_buttons.length > 1
          @footer_index = (@footer_index - 1 + footer_buttons.length) % footer_buttons.length
          draw_footer
        elsif Input.trigger?(Input::RIGHT) && footer_buttons.length > 1
          @footer_index = (@footer_index + 1) % footer_buttons.length
          draw_footer
        elsif Input.trigger?(Input::C)
          execute_footer(@footer_index)
        end
      end

      def execute_footer(index)
        case footer_buttons[index].to_s
        when "Back" then @running = false
        end
      end

      def open_profile_menu
        choices = ["Activate", "New Profile", "Duplicate", "Rename", "Delete", "Back"]
        choice = show_message("Profile Actions", choices)
        case choices[choice]
        when "Activate" then activate_selected_profile
        when "New Profile" then create_profile
        when "Duplicate" then duplicate_profile
        when "Rename" then rename_profile
        when "Delete" then delete_profile
        when "Back" then @running = false
      end
      end

      def mark_restart_required(reason)
        return if @restart_required
        @restart_required = true
        Reloaded::Log.info("Restart required: #{reason}", :mods) if defined?(Reloaded::Log)
      end

      def profile_name_input(prompt, initial = "")
        text_input_popup(prompt, initial, 32)
      end

      def activate_selected_profile
        profile = selected_profile
        return unless profile
        if active_profile?(profile)
          show_message("#{profile["name"]} is already active.")
          return
        end
        Reloaded::Profiles.activate(profile["name"]) if defined?(Reloaded::Profiles)
        Reloaded::Log.info("Mod Manager UI activated profile #{profile["name"]}", :mods) if defined?(Reloaded::Log)
        mark_restart_required("activated profile #{profile["name"]}")
        refresh_profiles
        draw_all
      rescue Exception => e
        Reloaded::Log.exception("Failed to activate profile", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not activate profile:\n#{e.message}")
      end

      def create_profile
        name = profile_name_input("New profile name")
        return if name.empty?
        Reloaded::Profiles.create(name, activate: true) if defined?(Reloaded::Profiles)
        Reloaded::Log.info("Mod Manager UI created profile #{name}", :mods) if defined?(Reloaded::Log)
        mark_restart_required("created and activated profile #{name}")
        select_profile(name)
      rescue Exception => e
        Reloaded::Log.exception("Failed to create profile", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not create profile:\n#{e.message}")
      end

      def duplicate_profile
        profile = selected_profile
        return unless profile
        name = profile_name_input("Duplicate profile as", "#{profile["name"]} Copy")
        return if name.empty?
        Reloaded::Profiles.duplicate(profile["name"], name, activate: true) if defined?(Reloaded::Profiles)
        Reloaded::Log.info("Mod Manager UI duplicated profile #{profile["name"]} as #{name}", :mods) if defined?(Reloaded::Log)
        mark_restart_required("duplicated and activated profile #{name}")
        select_profile(name)
      rescue Exception => e
        Reloaded::Log.exception("Failed to duplicate profile", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not duplicate profile:\n#{e.message}")
      end

      def rename_profile
        profile = selected_profile
        return unless profile
        if default_profile?(profile)
          show_message("The default profile cannot be renamed.")
          return
        end
        name = profile_name_input("Rename profile", profile["name"])
        return if name.empty? || name == profile["name"]
        Reloaded::Profiles.rename(profile["name"], name) if defined?(Reloaded::Profiles)
        Reloaded::Log.info("Mod Manager UI renamed profile #{profile["name"]} to #{name}", :mods) if defined?(Reloaded::Log)
        select_profile(name)
      rescue Exception => e
        Reloaded::Log.exception("Failed to rename profile", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not rename profile:\n#{e.message}")
      end

      def delete_profile
        profile = selected_profile
        return unless profile
        if default_profile?(profile)
          show_message("The default profile cannot be deleted.")
          return
        end
        if active_profile?(profile)
          show_message("The active profile cannot be deleted.\nActivate another profile first.")
          return
        end
        return unless show_message("Delete profile #{profile["name"]}?", ["Delete", "Cancel"]) == 0
        Reloaded::Profiles.delete(profile["name"]) if defined?(Reloaded::Profiles)
        Reloaded::Log.info("Mod Manager UI deleted profile #{profile["name"]}", :mods) if defined?(Reloaded::Log)
        refresh_profiles
        draw_all
      rescue Exception => e
        Reloaded::Log.exception("Failed to delete profile", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not delete profile:\n#{e.message}")
      end

      def select_profile(name)
        refresh_profiles
        wanted = name.to_s.downcase
        index = @profiles.index { |profile| profile["name"].to_s.downcase == wanted }
        @selected_index = index if index
        ensure_visible
        draw_all
      end
    end

    class Scene_Installed
      include UIHelpers

      def initialize
        @viewport = nil
        @running = false
        @rows = []
        @visible_rows = []
        @selected_index = 0
        @scroll = 0
        @search_text = ""
        @search_active = false
        @cursor_frame = 0
        @filter = :all
        @footer_index = 0
        @focus = :list
        @description_scroll = 0
        @dragging_description = false
        @restart_required = false
      end

      def main
        Graphics.freeze
        setup
        Graphics.transition(8)
        loop do
          Graphics.update
          Input.update
          break unless @running
          @cursor_frame += 1
          if @cursor_frame % 4 == 0
            draw_left if @focus == :list || @search_active
            draw_footer if @focus == :footer
          end
          handle_input
        end
        Graphics.freeze
        teardown
        Graphics.transition(8)
      end

      def setup
        @running = true
        Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
        @viewport = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
        @viewport.z = 100_000

        @background = Sprite.new(@viewport)
        @background.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
        @background.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, BG)

        @title_sprite = Sprite.new(@viewport)
        @title_sprite.bitmap = Bitmap.new(SCREEN_W, TITLE_H)
        @title_sprite.z = 10

        @left_sprite = Sprite.new(@viewport)
        @left_sprite.bitmap = Bitmap.new(LEFT_W, CONTENT_H)
        @left_sprite.x = MARGIN
        @left_sprite.y = CONTENT_Y
        @left_sprite.z = 10

        @right_sprite = Sprite.new(@viewport)
        @right_sprite.bitmap = Bitmap.new(RIGHT_W, CONTENT_H)
        @right_sprite.x = MARGIN + LEFT_W + GAP
        @right_sprite.y = CONTENT_Y
        @right_sprite.z = 10

        @footer_sprite = Sprite.new(@viewport)
        @footer_sprite.bitmap = Bitmap.new(SCREEN_W, FOOTER_H)
        @footer_sprite.y = SCREEN_H - FOOTER_H
        @footer_sprite.z = 10

        refresh_rows
        draw_all
      end

      def teardown
        [@footer_sprite, @right_sprite, @left_sprite, @title_sprite, @background].compact.each do |sprite|
          sprite.bitmap.dispose rescue nil
          sprite.dispose rescue nil
        end
        @viewport.dispose rescue nil
      end

      def draw_all
        draw_title
        draw_left
        draw_right
        draw_footer
      end

      def refresh_rows
        rows = Reloaded::ModManager.mod_rows rescue []
        query = @search_text.to_s.downcase
        unless query.empty?
          rows = rows.select do |row|
            [row[:id], row[:name], row[:description]].any? { |value| value.to_s.downcase.include?(query) } ||
              Array(row[:authors]).any? { |value| value.to_s.downcase.include?(query) } ||
              Array(row[:tags]).any? { |value| value.to_s.downcase.include?(query) }
          end
        end
        rows = rows.select { |row| row[:enabled] } if @filter == :enabled
        rows = rows.select { |row| !row[:enabled] } if @filter == :disabled
        rows = rows.select { |row| row[:status] == :conflict } if @filter == :conflicts
        rows = rows.select { |row| row[:status] == :missing_dependency } if @filter == :dependencies
        @rows = rows
        @selected_index = [[@selected_index, 0].max, [@rows.length - 1, 0].max].min
        ensure_visible
      end

      def selected_row
        @rows[@selected_index]
      end

      def rows_per_page
        (LIST_H / ROW_H).floor
      end

      def ensure_visible
        page = rows_per_page
        @scroll = @selected_index if @selected_index < @scroll
        @scroll = @selected_index - page + 1 if @selected_index >= @scroll + page
        @scroll = [[@scroll, 0].max, [@rows.length - page, 0].max].min
      end

      def draw_title
        bitmap = @title_sprite.bitmap
        bitmap.clear
        bitmap.fill_rect(0, 0, SCREEN_W, TITLE_H, TITLE_BG)
        bitmap.fill_rect(MARGIN, TITLE_H - 2, SCREEN_W - MARGIN * 2, 1, PANEL_BORDER)
        pbSetSystemFont(bitmap)
        bitmap.font.size = 21
        pbDrawShadowText(bitmap, MARGIN, 5, -1, 24, "Reloaded Mod Manager", WHITE, SHADOW)
        apply_ui_font(bitmap)
        bitmap.font.size = 10 rescue nil
        pbDrawShadowText(bitmap, SCREEN_W - MARGIN - 3, 0, -1, 14, @rows.length.to_s, GRAY, SHADOW, 1)
        bitmap.font.size = 12 rescue nil
        pbDrawShadowText(bitmap, 176, 9, 168, 14, "Filter (Z): #{filter_label}", BLUE, SHADOW, 1)
      end

      def draw_left
        bitmap = @left_sprite.bitmap
        bitmap.clear
        draw_panel(bitmap, LEFT_W, CONTENT_H)

        search_color = @search_active ? SEARCH_ACTIVE : SEARCH_BG
        draw_rounded_rect(bitmap, 6, 5, LEFT_W - 12, SEARCH_H, search_color)
        if @search_active
          draw_selection_box(bitmap, 6, 5, LEFT_W - 12, SEARCH_H)
        else
          draw_border(bitmap, 6, 5, LEFT_W - 12, SEARCH_H, PANEL_LINE)
        end
        apply_ui_font(bitmap)
        search_label = if @search_active
                         @search_text + ((@cursor_frame / 20) % 2 == 0 ? "|" : "")
                       elsif @search_text.empty?
                         "Search (S or Click)"
                       else
                         @search_text
                       end
        bitmap.font.size = 13 rescue nil
        pbDrawShadowText(bitmap, 12, 8, LEFT_W - 24, 16, search_label, @search_text.empty? && !@search_active ? DIM : WHITE, SHADOW)

        visible = @rows[@scroll, rows_per_page] || []
        if @rows.empty?
          apply_ui_font(bitmap)
          bitmap.font.size = 16 rescue nil
          pbDrawShadowText(bitmap, 0, CONTENT_H / 2 - 10, LEFT_W, 20, "No mods installed", DIM, SHADOW, 1)
        end
        visible.each_with_index do |row, offset|
          index = @scroll + offset
          y = LIST_Y + offset * ROW_H
          selected = index == @selected_index && @focus == :list
          fill = row[:enabled] ? ROW_NORMAL : ROW_DISABLED
          draw_rounded_rect(bitmap, 6, y, LEFT_W - 12, ROW_H - 3, fill)
          draw_selection_box(bitmap, 6, y - 1, LEFT_W - 12, ROW_H - 2) if selected
          bitmap.fill_rect(13, y + 7, 6, 6, text_color_for_status(row[:status]))
          prefix = row[:moddev] ? "[MD] " : ""
          name = trim_text(bitmap, prefix + row[:name].to_s, LEFT_W - 44)
          color = selected ? WHITE : text_color_for_status(row[:status])
          pbDrawShadowText(bitmap, 25, y - 2, LEFT_W - 38, ROW_H, name, color, SHADOW)
        end

        pbDrawShadowText(bitmap, LEFT_W / 2 - 10, LIST_Y - 12, 20, 12, "^", GRAY, SHADOW, 1) if @scroll > 0
        if @scroll + rows_per_page < @rows.length
          pbDrawShadowText(bitmap, LEFT_W / 2 - 10, LIST_Y + rows_per_page * ROW_H - 2, 20, 12, "v", GRAY, SHADOW, 1)
        end
      end

      def draw_right
        bitmap = @right_sprite.bitmap
        bitmap.clear
        row = selected_row
        draw_panel(bitmap, RIGHT_W, CONTENT_H, row ? row[:name].to_s : "Details")

        unless row
          draw_panel_hint(bitmap, "Confirm (C) Back (B) Filter (Z) Menu (A)", RIGHT_W, CONTENT_H)
          return
        end

        x = 12
        y = 31
        apply_ui_font(bitmap)
        bitmap.font.size = 14
        authors = Array(row[:authors]).join(", ")
        pbDrawShadowText(bitmap, x, y, RIGHT_W - 24, 16, "by #{authors.empty? ? 'Unknown' : authors}", GRAY, SHADOW)
        y += 16
        pbDrawShadowText(bitmap, x, y, RIGHT_W - 24, 16, "v#{row[:version]}  |  #{status_label(row[:status])}", GRAY, SHADOW)
        y += 20
        pbDrawShadowText(bitmap, x, y, RIGHT_W - 24, 16, "Source: #{row[:source]}", row[:moddev] ? ORANGE : DIM, SHADOW)
        y += 20

        y = draw_tags(bitmap, x, y, row)
        bitmap.fill_rect(x, y, RIGHT_W - 24, 1, PANEL_BORDER)
        y += 6
        pbDrawShadowText(bitmap, x, y, RIGHT_W - 24, 14, "Description", BLUE, SHADOW)
        y += 16

        desc_lines = wrapped_lines(bitmap, row[:description], RIGHT_W - 34)
        desc_top = y
        hint_y = CONTENT_H - 76
        max_visible = [(hint_y - desc_top) / 16, 1].max
        @description_scroll = [[@description_scroll, 0].max, [desc_lines.length - max_visible, 0].max].min
        desc_lines.each_with_index do |line, index|
          next if index < @description_scroll
          break if y + 16 > hint_y
          pbDrawShadowText(bitmap, x, y, RIGHT_W - 34, 16, line, GRAY, SHADOW)
          y += 16
        end

        if desc_lines.length > max_visible
          bar_x = RIGHT_W - 14
          bar_y = desc_top
          bar_h = hint_y - desc_top
          bitmap.fill_rect(bar_x, bar_y, 8, bar_h, Color.new(0, 0, 0, 60))
          max_scroll = [desc_lines.length - max_visible, 1].max
          handle_h = [[bar_h * max_visible / desc_lines.length, 14].max, bar_h].min
          handle_y = bar_y + (bar_h - handle_h) * @description_scroll.to_f / max_scroll
          bitmap.fill_rect(bar_x + 1, handle_y.to_i, 6, handle_h, GRAY)
          @description_scrollbar = Rect.new(bar_x, bar_y, 8, bar_h)
          @description_line_count = desc_lines.length
          @description_max_visible = max_visible
        else
          @description_scrollbar = nil
        end

        draw_dependency_summary(bitmap, row)
        draw_panel_hint(bitmap, "Confirm (C) Back (B) Filter (Z) Menu (A)", RIGHT_W, CONTENT_H)
      end

      def draw_tags(bitmap, x, y, row)
        tags = (Array(row[:system_tags]) + Array(row[:tags])).uniq
        tags.each do |tag|
          label = tag.to_s
          width = bitmap.text_size(label).width + 10
          if x + width > RIGHT_W - 12
            x = 12
            y += 20
          end
          draw_rounded_rect(bitmap, x, y, width, 18, TAG_BG)
          pbDrawShadowText(bitmap, x + 5, y - 4, width, 18, label, GRAY, SHADOW)
          x += width + 4
        end
        y + 22
      end

      def draw_dependency_summary(bitmap, row)
        x = 12
        y = CONTENT_H - 64
        deps = Array(row[:dependencies])
        conflicts = Array(row[:incompatibilities]).select { |entry| entry[:status] == :conflict }
        apply_ui_font(bitmap)
        bitmap.fill_rect(x, y - 6, RIGHT_W - 24, 1, PANEL_LINE)
        unless deps.empty?
          bad = deps.select { |entry| entry[:status] != :ok }
          color = bad.empty? ? GREEN : ORANGE
          pbDrawShadowText(bitmap, x, y, RIGHT_W - 24, 14, "Dependencies: #{deps.length}#{bad.empty? ? '' : " (#{bad.length} issue(s))"}", color, SHADOW)
          y += 14
        end
        unless conflicts.empty?
          pbDrawShadowText(bitmap, x, y, RIGHT_W - 24, 14, "Conflicts: #{conflicts.length}", RED, SHADOW)
        end
      end

      def draw_footer
        draw_footer_buttons(@footer_sprite.bitmap, footer_buttons)
      end

      def handle_input
        handle_mouse
        return handle_search_input if @search_active

        if Input.trigger?(Input::B) || InputSupport.mouse_right_trigger?
          request_exit
          return
        end
        if key_trigger?(0x53)
          activate_search
          return
        end
        if menu_trigger?
          open_page_menu
          return
        end
        if special_trigger?
          open_filter_menu
          return
        end
        @focus == :list ? handle_list_input : handle_footer_input
      end

      def handle_mouse
        mx, my = InputSupport.mouse_pos
        return unless mx && my
        clicked = InputSupport.mouse_left_trigger?
        old_selected = @selected_index
        old_focus = @focus
        old_footer = @footer_index

        lx = @left_sprite.x
        ly = @left_sprite.y
        if clicked && mx >= lx && mx < lx + LEFT_W && my >= ly + 5 && my < ly + 5 + SEARCH_H
          activate_search
          return
        end

        if mx >= lx && mx < lx + LEFT_W && my >= ly + LIST_Y && my < ly + LIST_Y + LIST_H
          row = ((my - ly - LIST_Y) / ROW_H).floor
          index = @scroll + row
          if index >= 0 && index < @rows.length
            @focus = :list
            @selected_index = index
            @description_scroll = 0 if old_selected != @selected_index
            open_action_menu(selected_row) if clicked
          end
        end

        fy = @footer_sprite.y
        if my >= fy && my < fy + FOOTER_H
          footer_index = footer_button_at(mx)
          if footer_index
            @focus = :footer
            @footer_index = footer_index
            execute_footer(@footer_index) if clicked
          end
        end

        rx = @right_sprite.x
        ry = @right_sprite.y
        if mx >= rx && mx < rx + RIGHT_W && my >= ry && my < ry + CONTENT_H
          scroll = InputSupport.mouse_scroll
          if scroll != 0
            @description_scroll = [@description_scroll - scroll, 0].max
            draw_right
          end
        end

        draw_left if old_selected != @selected_index || old_focus != @focus
        draw_right if old_selected != @selected_index
        draw_footer if old_focus != @focus || old_footer != @footer_index
      end

      def handle_list_input
        changed = false
        if Input.trigger?(Input::DOWN) && (@rows.empty? || @selected_index >= @rows.length - 1)
          @focus = :footer
          draw_left
          draw_footer
          return
        end
        if Input.repeat?(Input::UP) && !@rows.empty?
          @selected_index = (@selected_index - 1 + @rows.length) % @rows.length
          @description_scroll = 0
          ensure_visible
          changed = true
        elsif Input.repeat?(Input::DOWN) && !@rows.empty?
          @selected_index = (@selected_index + 1) % @rows.length
          @description_scroll = 0
          ensure_visible
          changed = true
        end
        open_action_menu(selected_row) if Input.trigger?(Input::C) && selected_row
        if changed
          draw_left
          draw_right
        end
      end

      def handle_footer_input
        if Input.trigger?(Input::UP)
          @focus = :list
          draw_left
          draw_footer
        elsif Input.trigger?(Input::LEFT) && footer_buttons.length > 1
          @footer_index = (@footer_index - 1 + footer_buttons.length) % footer_buttons.length
          draw_footer
        elsif Input.trigger?(Input::RIGHT) && footer_buttons.length > 1
          @footer_index = (@footer_index + 1) % footer_buttons.length
          draw_footer
        elsif Input.trigger?(Input::C)
          execute_footer(@footer_index)
        end
      end

      def activate_search
        @search_active = true
        @focus = :list
        draw_left
      end

      def deactivate_search(clear = false)
        @search_active = false
        @search_text = "" if clear
        refresh_rows
        draw_all
      end

      def handle_search_input
        if Input.trigger?(Input::B) || InputSupport.mouse_right_trigger?
          deactivate_search(true)
          return
        end
        if Input.trigger?(Input::C) || key_trigger?(0x0D)
          deactivate_search(false)
          return
        end

        old_text = @search_text.dup
        @search_text = @search_text[0...-1] if key_repeat?(0x08) && !@search_text.empty?
        @search_text = "" if key_trigger?(0x2E)
        (0x41..0x5A).each do |vk|
          next unless key_trigger?(vk)
          char = (vk - 0x41 + 97).chr
          char = char.upcase if key_pressed?(0x10)
          @search_text += char if @search_text.length < 30
        end
        (0x30..0x39).each do |vk|
          @search_text += (vk - 0x30).to_s if key_trigger?(vk) && @search_text.length < 30
        end
        @search_text += " " if key_trigger?(0x20) && @search_text.length < 30
        @search_text += "-" if key_trigger?(0xBD) && @search_text.length < 30
        if @search_text != old_text
          @selected_index = 0
          @scroll = 0
          refresh_rows
          draw_title
          draw_left
          draw_right
        end
      end

      def open_action_menu(row)
        return unless row
        enabled = row[:profile_enabled]
        toggle_label = enabled ? "Disable" : "Enable"
        choices = [toggle_label, "Move Up", "Move Down", "Dependencies", "Conflicts"]
        choice = show_message(row[:name], choices)
        case choices[choice]
        when "Enable"
          enable_mod(row)
        when "Disable"
          disable_mod(row)
        when "Move Up"
          Reloaded::Profiles.move_mod(row[:id], -1) if defined?(Reloaded::Profiles)
          mark_restart_required("moved #{row[:id]} up in load order")
          reload_after_profile_change
        when "Move Down"
          Reloaded::Profiles.move_mod(row[:id], 1) if defined?(Reloaded::Profiles)
          mark_restart_required("moved #{row[:id]} down in load order")
          reload_after_profile_change
        when "Dependencies"
          show_dependency_details(row)
        when "Conflicts"
          show_conflict_details(row)
        end
      end

      def enable_mod(row)
        missing = Array(row[:dependencies]).select { |entry| entry[:status] == :missing }
        disabled = Array(row[:dependencies]).select { |entry| entry[:status] == :disabled }
        unless missing.empty?
          show_message("Missing dependencies:\n#{missing.map { |entry| entry[:id] }.join(", ")}")
        end
        if !disabled.empty?
          names = disabled.map { |entry| entry[:name] }.join(", ")
          if show_message("Enable disabled dependencies?\n#{names}", ["Yes", "No"]) == 0
            disabled.each { |entry| Reloaded::Profiles.enable_mod(entry[:id]) if defined?(Reloaded::Profiles) }
            mark_restart_required("enabled dependencies for #{row[:id]}")
          end
        end
        Reloaded::Profiles.enable_mod(row[:id]) if defined?(Reloaded::Profiles)
        Reloaded::Log.info("Mod Manager UI enabled #{row[:id]} in profile", :mods) if defined?(Reloaded::Log)
        mark_restart_required("enabled #{row[:id]}")
        reload_after_profile_change
      end

      def disable_mod(row)
        Reloaded::Profiles.disable_mod(row[:id]) if defined?(Reloaded::Profiles)
        Reloaded::Log.info("Mod Manager UI disabled #{row[:id]} in profile", :mods) if defined?(Reloaded::Log)
        mark_restart_required("disabled #{row[:id]}")
        reload_after_profile_change
      end

      def reload_after_profile_change
        Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
        refresh_rows
        draw_all
      end

      def show_dependency_details(row)
        deps = Array(row[:dependencies])
        if deps.empty?
          show_message("No dependencies.")
          return
        end
        lines = deps.map do |dep|
          "#{dep[:name]} - #{dep[:status]}#{dep[:required_version] ? " >= #{dep[:required_version]}" : ""}"
        end
        show_message(lines.join("\n"))
      end

      def show_conflict_details(row)
        conflicts = Array(row[:incompatibilities])
        if conflicts.empty?
          show_message("No known conflicts.")
          return
        end
        lines = conflicts.map { |entry| "#{entry[:name]} - #{entry[:status]}" }
        show_message(lines.join("\n"))
      end

      def execute_footer(index)
        case footer_buttons[index].to_s
        when "Browser" then open_browser_placeholder
        when "Back" then request_exit
        end
      end

      def show_profile_menu
        profile_restart_required = Scene_Profiles.new.main
        mark_restart_required("profile changes") if profile_restart_required
        reload_after_profile_change
      end

      def open_page_menu
        choices = ["Profiles", "Filter", "Back"]
        choice = show_message("Mod Manager Menu", choices)
        case choices[choice]
        when "Profiles" then show_profile_menu
        when "Filter" then open_filter_menu
        when "Back" then request_exit
        end
      end

      def request_exit
        if @restart_required
          show_message("Changes have been made.\nRestart Required.", nil, 0, true)
        end
        @running = false
      end

      def mark_restart_required(reason)
        return if @restart_required
        @restart_required = true
        Reloaded::Log.info("Restart required: #{reason}", :mods) if defined?(Reloaded::Log)
        draw_title rescue nil
        draw_right rescue nil
      end

      def open_browser_placeholder
        show_message("Browser is not implemented yet.")
      end

      def open_filter_menu
        choices = ["All", "Enabled", "Disabled", "Dependency Issues", "Conflicts"]
        choice = show_message("Filter Mods", choices)
        @filter = case choices[choice]
                  when "Enabled" then :enabled
                  when "Disabled" then :disabled
                  when "Dependency Issues" then :dependencies
                  when "Conflicts" then :conflicts
                  when "All" then :all
                  else @filter
                  end
        @selected_index = 0
        @scroll = 0
        refresh_rows
        draw_all
      end

      def filter_label
        case @filter
        when :enabled then "Enabled"
        when :disabled then "Disabled"
        when :dependencies then "Dependency Issues"
        when :conflicts then "Conflicts"
        else "All"
        end
      end

      def status_label(status)
        status.to_s.split("_").map { |part| part.capitalize }.join(" ")
      end
    end
  end
end
