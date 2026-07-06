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

    FOOTER_BUTTONS = ["Profiles", "Browser", "Tools"].freeze
    BUG_REPORT_THREAD_URL = "https://discord.com/channels/1121345297352753243/1518892862429855794".freeze
    CORE_UPDATE_INSTALLER = "Hoenn Reloaded Installer.bat".freeze

    class << self
      def open
        Scene_Installed.new.main
      rescue Exception => e
        raise if e.is_a?(SystemExit)
        Reloaded::Log.exception("Failed to open Mod Manager UI", e, channel: :mods) if defined?(Reloaded::Log)
        pbMessage("Mod Manager failed to open.") rescue nil
      end

      def open_admin_tools
        Scene_Installed.new.open_admin_tools_standalone
      rescue Exception => e
        raise if e.is_a?(SystemExit)
        Reloaded::Log.exception("Failed to open Admin Tools", e, channel: :mods) if defined?(Reloaded::Log)
        pbMessage("Admin Tools failed to open.") rescue nil
      end

      def clipboard_write(text)
        Input.clipboard = text
        true
      rescue
        false
      end

      def clipboard_read
        Input.clipboard
      rescue
        nil
      end
    end

    module InputSupport
      KEYBOARD_INPUTS = [
        Input::UP, Input::DOWN, Input::LEFT, Input::RIGHT,
        Input::USE, Input::BACK
      ].tap { |keys|
        keys << Input::ACTION if Input.const_defined?(:ACTION)
        keys << Input::SPECIAL if Input.const_defined?(:SPECIAL)
        keys << Input::L if Input.const_defined?(:L)
        keys << Input::R if Input.const_defined?(:R)
      }.freeze

      @mouse_active = false
      @last_mx = nil
      @last_my = nil
      @mouse_active_frame = -1
      @controller_scroll_dir = 0
      @controller_scroll_frame = -999

      class << self
        def mouse_pos
          mx = Input.mouse_x rescue nil
          my = Input.mouse_y rescue nil
          if KEYBOARD_INPUTS.any? { |key| Input.trigger?(key) rescue false }
            @mouse_active = false
          end
          moved = mx && my && (mx != @last_mx || my != @last_my)
          if moved
            @last_mx = mx
            @last_my = my
            @mouse_active = true
            @mouse_active_frame = Graphics.frame_count rescue @mouse_active_frame
          end
          clicked = mouse_left_raw? || mouse_right_raw?
          scrolled = mouse_scroll.to_i != 0
          if mx && my && (moved || clicked || scrolled)
            @last_mx = mx
            @last_my = my
            @mouse_active = true
            @mouse_active_frame = Graphics.frame_count rescue @mouse_active_frame
            return [mx, my]
          end
          [nil, nil]
        rescue
          [nil, nil]
        end

        def mouse_left_trigger?
          mouse_pos[0] && mouse_left_raw?
        rescue
          false
        end

        def mouse_right_trigger?
          mouse_pos[0] && mouse_right_raw?
        rescue
          false
        end

        def mouse_left_press?
          mouse_pos[0] && Input.const_defined?(:MOUSELEFT) && Input.press?(Input::MOUSELEFT)
        rescue
          false
        end

        def mouse_scroll
          Input.scroll_v.to_i rescue 0
        rescue
          0
        end

        def scroll_delta
          mouse = mouse_scroll
          return mouse unless mouse == 0
          controller_scroll_delta
        rescue
          0
        end

        def scroll_up?
          scroll_delta.to_i > 0
        end

        def scroll_down?
          scroll_delta.to_i < 0
        end

        def controller_scroll_delta
          dir = controller_scroll_direction
          if dir == 0
            @controller_scroll_dir = 0
            return 0
          end
          frame = Graphics.frame_count rescue 0
          if @controller_scroll_dir != dir
            @controller_scroll_dir = dir
            @controller_scroll_frame = frame
            return dir
          end
          return 0 if frame - (@controller_scroll_frame || 0) < 6
          @controller_scroll_frame = frame
          dir
        rescue
          0
        end

        def controller_scroll_direction
          return 1 if right_stick_button?([
            :RIGHTSTICKUP, :RIGHT_STICK_UP, :RSTICKUP, :R_STICK_UP,
            :RUP, :RIGHT_ANALOG_UP, :ANALOG_R_UP
          ])
          return 1 if right_stick_axis_button?([:RIGHT_STICK_UP])
          return -1 if right_stick_button?([
            :RIGHTSTICKDOWN, :RIGHT_STICK_DOWN, :RSTICKDOWN, :R_STICK_DOWN,
            :RDOWN, :RIGHT_ANALOG_DOWN, :ANALOG_R_DOWN
          ])
          return -1 if right_stick_axis_button?([:RIGHT_STICK_DOWN])
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

        def right_stick_axis_button?(names)
          return false unless Input.respond_to?(:axis_repeatex?) || Input.respond_to?(:axis_pressex?)
          names.any? do |name|
            next false unless Input.const_defined?(name)
            key = Input.const_get(name)
            (Input.axis_repeatex?(key) rescue false) || (Input.axis_pressex?(key) rescue false)
          end
        rescue
          false
        end

        def right_stick_y_axis
          if Input.const_defined?(:Controller)
            controller = Input.const_get(:Controller)
            value = controller.axes_right[1] rescue nil
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

        def mouse_left_raw?
          return false unless Input.const_defined?(:MOUSELEFT)
          Input.trigger?(Input::MOUSELEFT)
        rescue
          false
        end

        def mouse_right_raw?
          return false unless Input.const_defined?(:MOUSERIGHT)
          Input.trigger?(Input::MOUSERIGHT)
        rescue
          false
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

      def popup_selection_fill
        pulse = pulse_value
        color_with_alpha(FOOTER_SEL, (165 + (225 - 165) * pulse).to_i)
      end

      def draw_selection_fill(bitmap, x, y, width, height, fill = nil)
        draw_selection_box(bitmap, x, y, width, height, fill)
      end

      def draw_plain_text(bitmap, x, y, width, height, text, color, align = 0)
        draw_x = case align
                 when 1 then x + width / 2
                 when 2 then x + width
                 else x
                 end
        pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y, align, color, Color.new(0, 0, 0, 0)]])
      end

      def draw_hint_text(bitmap, text, x, y, width, height = 16, x_offset = 30, align = 1)
        apply_ui_font(bitmap)
        bitmap.font.size = 12 rescue nil
        max_width = [width - 16, 32].max
        while bitmap.font.size > 8 && bitmap.text_size(text.to_s).width > max_width
          bitmap.font.size -= 1
        end
        draw_x = case align
                 when 2 then x + width - 10
                 when 0 then x + 10 + x_offset
                 else x + width / 2 + x_offset
                 end
        pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y - 2, align, DIM, Color.new(0, 0, 0, 0)]])
      end

      def draw_panel_hint(bitmap, text, width, height, x_offset = 30)
        bitmap.fill_rect(8, height - 26, width - 16, 1, PANEL_LINE)
        draw_hint_text(bitmap, text, 2, height - 20, width - 12, 16, 0, 0)
      end

      def download_failure_message(result)
        lines = ["Could not download:"]
        missing = Array(result[:missing])
        mismatches = Array(result[:version_mismatches])
        no_download_url = Array(result[:no_download_url])
        failed = Array(result[:failed]) - missing - no_download_url - mismatches.map { |entry| entry[:id].to_s }
        lines << "Missing from browser index: #{missing.join(", ")}" unless missing.empty?
        lines << "No download URL in index: #{no_download_url.join(", ")}" unless no_download_url.empty?
        mismatches.each do |entry|
          lines << "#{entry[:id]} needs v#{entry[:required_version]} or newer. Latest indexed: v#{entry[:available_version]}."
        end
        lines << "Failed install/download: #{failed.join(", ")}" unless failed.empty?
        lines << "No details returned." if lines.length == 1
        lines.join("\n")
      end

      def open_spritepack_menu
        unless defined?(Reloaded::ModBrowser)
          show_message("Spritepack downloads are not available.")
          return
        end
        choice = show_message("Spritepacks", ["Latest", "All Files", "Back"])
        case choice
        when 0 then open_spritepack_file_menu("Latest", Reloaded::ModBrowser.spritepack_latest_files)
        when 1 then open_spritepack_file_menu("All Files", Reloaded::ModBrowser.spritepack_all_files)
        end
      rescue Exception => e
        Reloaded::Log.exception("Spritepack menu failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Spritepack menu failed:\n#{e.message}")
      end

      def open_spritepack_file_menu(title, files)
        rows = Array(files).compact
        if rows.empty?
          show_message("No spritepacks are configured.")
          return
        end
        labels = rows.map { |file| file["name"].to_s }
        labels << "Back"
        choice = show_message(title, labels)
        file = rows[choice]
        return unless file
        open_spritepack_action_menu(file)
      end

      def open_spritepack_action_menu(file)
        name = file["name"].to_s
        choices = ["Download", "Mark as Installed", "Back"]
        choice = show_message(name, choices)
        case choice
        when 0 then confirm_spritepack_download(file)
        when 1 then confirm_spritepack_mark_installed(file)
        end
      end

      def confirm_spritepack_download(file)
        name = file["name"].to_s
        url = file["url"].to_s.strip
        if url.empty?
          show_message("No download URL is configured for:\n#{name}\n\nEdit Reloaded/Spritepacks.json.")
          return
        end
        choice = show_message(
          "Download and extract #{name}?\n\nThis can take a while and will write sprite files into the game folder.",
          ["Download", "Back"],
          1
        )
        return unless choice == 0
        result = Reloaded::ModBrowser.download_spritepack(file)
        if result[:success]
          show_message(spritepack_success_message(result))
          refresh_rows if respond_to?(:refresh_rows)
          draw_all if respond_to?(:draw_all)
        else
          show_message(spritepack_failure_message(result))
        end
      rescue Exception => e
        Reloaded::Log.exception("Spritepack download failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Spritepack download failed:\n#{e.message}")
      end

      def confirm_spritepack_mark_installed(file)
        name = file["name"].to_s
        choice = show_message(
          "Mark #{name} as installed?\n\nUse this only if the spritepack was installed manually.",
          ["Mark Installed", "Back"],
          1
        )
        return unless choice == 0
        result = Reloaded::ModBrowser.mark_spritepack_installed(file)
        if result[:success]
          show_message("Spritepack marked as installed:\n#{result[:name]}")
          refresh_rows if respond_to?(:refresh_rows)
          draw_all if respond_to?(:draw_all)
        else
          show_message("Could not mark spritepack installed:\n#{result[:error]}")
        end
      rescue Exception => e
        Reloaded::Log.exception("Spritepack mark installed failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not mark spritepack installed:\n#{e.message}")
      end

      def spritepack_success_message(result)
        import = result[:import] || {}
        lines = ["Spritepack installed:", result[:name].to_s]
        if import[:total]
          lines << ""
          lines << "Files: #{import[:total].to_i}"
          lines << "Copied: #{import[:copied].to_i}"
          lines << "Skipped: #{import[:skipped].to_i}"
          lines << "Failed: #{import[:failed].to_i}"
        end
        lines.join("\n")
      end

      def spritepack_failure_message(result)
        case result[:status]
        when :missing_url
          "No download URL is configured for:\n#{result[:name]}\n\nEdit Reloaded/Spritepacks.json."
        when :download_failed
          url = result[:url].to_s
          "Spritepack download failed.\nCheck your internet connection and the URL.#{url.empty? ? '' : "\n#{url}"}"
        when :extract_failed
          "Spritepack downloaded, but extraction failed.\nConfirm REQUIRED_BY_INSTALLER_UPDATER/7z.exe exists and supports the archive."
        else
          "Spritepack install failed.\n#{result[:error]}"
        end
      end

      def fetch_changelog_text_value(value)
        text = value.to_s.strip
        raise "Changelog path is empty." if text.empty?
        if text[/\Ahttps?:\/\//i]
          raise "Mod Browser is not available." unless defined?(Reloaded::ModBrowser)
          return Reloaded::ModBrowser.fetch_url(text, cache_bust: true).to_s
        end
        path = resolve_local_changelog_path(text)
        raise "Changelog file was not found: #{text}" if path.empty?
        File.read(path)
      end

      def resolve_local_changelog_path(value)
        root = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
        candidates = [
          File.expand_path(value.to_s),
          File.expand_path(File.join(root, value.to_s)),
          File.expand_path(File.join(".", value.to_s))
        ].uniq
        found = candidates.find { |path| File.exist?(path) && !File.directory?(path) }
        found || ""
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

      def tag_label(tag)
        raw = tag.to_s
        alias_label = tag_aliases[tag_key(raw)]
        return alias_label if alias_label
        configured_tag_labels.each do |label|
          return label if tag_key(label) == tag_key(raw)
        end
        raw
      end

      def configured_tag_labels
        labels = []
        if defined?(Reloaded::ModManager)
          labels += Reloaded::ModManager.tags.values.flatten rescue []
          labels += Reloaded::ModManager.system_tags rescue []
        end
        labels.map(&:to_s)
      end

      def tag_aliases
        {
          "qualityoflife" => "QoL",
          "qol" => "QoL",
          "ui" => "UI",
          "moddev" => "ModDev",
          "missingdependency" => "Missing Dependency",
          "updateavailable" => "Update",
          "update" => "Update",
          "specialentry" => "Special",
          "special" => "Special"
        }
      end

      def tag_key(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
      end

      def special_entry?(row)
        special_entry_priority(row) < 2
      end

      def special_entry_priority(row)
        return 2 unless row
        values = special_entry_values(row)
        return 0 if truthy_ui?(values[:featured])
        return 1 if truthy_ui?(values[:special_entry])
        2
      rescue
        2
      end

      def special_entry_values(row)
        values = { :featured => nil, :special_entry => nil }
        if row.is_a?(Hash)
          [:featured, "featured"].each do |key|
            values[:featured] = row[key] if row.has_key?(key)
          end
          [:special_entry, "special_entry"].each do |key|
            values[:special_entry] = row[key] if row.has_key?(key)
          end
        end
        indexed = browser_special_entry_values(row)
        values[:featured] = indexed[:featured] if values[:featured].nil? && indexed
        values[:special_entry] = indexed[:special_entry] if values[:special_entry].nil? && indexed
        values
      end

      def browser_special_entry_values(row)
        entry = browser_entry_for_row(row)
        return nil unless entry
        {
          :featured => entry["featured"],
          :special_entry => entry["special_entry"]
        }
      end

      def browser_entry_for_row(row)
        return nil unless defined?(Reloaded::ModBrowser)
        id = (row[:id] rescue nil) || (row["id"] rescue nil)
        return nil if id.to_s.empty?
        kind = (row[:kind] rescue nil) || (row["kind"] rescue nil)
        if kind.to_s == "profile"
          Reloaded::ModBrowser.profile_entry(id) rescue nil
        else
          Reloaded::ModBrowser.entry(id) rescue nil
        end
      end

      def special_entry_color(row)
        special_entry_priority(row) == 0 ? YELLOW : BLUE
      end

      def admin_tags_for(row)
        tags = []
        tags << "Featured" if special_entry_priority(row) == 0
        tags << "Special" if special_entry_priority(row) == 1
        tags
      rescue
        []
      end

      def truthy_ui?(value)
        return value if value == true || value == false
        ["1", "true", "yes", "on", "enabled"].include?(value.to_s.strip.downcase)
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
            while bitmap.text_size(word).width > max_width && word.length > 1
              chunk = ""
              word.each_char do |char|
                break if !chunk.empty? && bitmap.text_size(chunk + char).width > max_width
                chunk += char
              end
              break if chunk.empty?
              lines << current unless current.empty?
              current = ""
              lines << chunk
              word = word[chunk.length..-1].to_s
            end
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

      def update_available?(row)
        return false unless row && defined?(Reloaded::ModBrowser)
        return false if spritepack_entry_row?(row)
        if core_entry_row?(row)
          entry = Reloaded::ModBrowser.entry(core_entry_id)
          latest = entry ? entry["latest_version"].to_s : ""
          return false if latest.empty?
          return compare_versions(core_installed_version, latest) < 0
        end
        entry = Reloaded::ModBrowser.entry(row[:id])
        latest = entry ? entry["latest_version"].to_s : ""
        return false if latest.empty?
        compare_versions(row[:version], latest) < 0
      rescue
        false
      end

      def core_entry_id
        defined?(Reloaded::ModBrowser::CORE_ENTRY_ID) ? Reloaded::ModBrowser::CORE_ENTRY_ID : "hoenn_reloaded"
      end

      def spritepack_entry_id
        defined?(Reloaded::ModBrowser::SPRITEPACK_ENTRY_ID) ? Reloaded::ModBrowser::SPRITEPACK_ENTRY_ID : "spritepacks"
      end

      def core_entry_row?(row)
        return false unless row
        id = (row[:id] rescue nil) || (row["id"] rescue nil)
        return true if id.to_s == core_entry_id
        !!((row[:core_entry] rescue nil) || (row["core_entry"] rescue nil))
      end

      def spritepack_entry_row?(row)
        return false unless row
        id = (row[:id] rescue nil) || (row["id"] rescue nil)
        return true if id.to_s == spritepack_entry_id
        !!((row[:spritepack_entry] rescue nil) || (row["spritepack_entry"] rescue nil))
      end

      def protected_entry_row?(row)
        return false unless row
        core_entry_row?(row) || spritepack_entry_row?(row) || !!((row[:protected] rescue nil) || (row["protected"] rescue nil))
      end

      def core_installed_version
        Reloaded.version rescue "0.0.0"
      end

      def show_core_update_status(row = nil)
        Reloaded::ModBrowser.refresh(fetch_remote: true) if defined?(Reloaded::ModBrowser)
        entry = defined?(Reloaded::ModBrowser) ? Reloaded::ModBrowser.entry(core_entry_id) : nil
        latest = (entry && entry["latest_version"].to_s) || (row && ((row[:latest_version] rescue nil) || (row["latest_version"] rescue nil))).to_s
        latest = core_installed_version if latest.to_s.empty?
        current = core_installed_version
        status = compare_versions(current, latest) < 0 ? "Update available." : "Hoenn Reloaded is up to date."
        show_message("#{status}\nCurrent: v#{current}\nLatest: v#{latest}")
      rescue Exception => e
        Reloaded::Log.exception("Hoenn Reloaded update check failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not check Hoenn Reloaded updates.")
      end

      def update_core_installation(row = nil)
        Reloaded::ModBrowser.refresh(fetch_remote: true) if defined?(Reloaded::ModBrowser)
        entry = defined?(Reloaded::ModBrowser) ? Reloaded::ModBrowser.entry(core_entry_id) : nil
        latest = (entry && entry["latest_version"].to_s) || (row && ((row[:latest_version] rescue nil) || (row["latest_version"] rescue nil))).to_s
        current = core_installed_version
        if latest.to_s.empty? || compare_versions(current, latest) >= 0
          show_message("Hoenn Reloaded is already up to date.\nCurrent: v#{current}")
          return
        end
        installer = core_update_installer_path
        unless File.file?(installer)
          show_message("#{CORE_UPDATE_INSTALLER} was not found in the game folder.")
          return
        end
        choice = show_message(
          "Update Hoenn Reloaded now?\nCurrent: v#{current}\nLatest: v#{latest}\n\nThis will run #{CORE_UPDATE_INSTALLER} and close the game immediately.",
          ["Update", "Back"]
        )
        return unless choice == 0
        if launch_core_update_installer(installer)
          Reloaded::Log.info("Launched Hoenn Reloaded updater: #{relative_game_path(installer)}", :mods) if defined?(Reloaded::Log)
          close_game_for_core_update
        else
          show_message("Could not run #{CORE_UPDATE_INSTALLER}.")
        end
      rescue Exception => e
        Reloaded::Log.exception("Hoenn Reloaded update failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not start Hoenn Reloaded update:\n#{e.message}")
      end

      def core_update_installer_path
        File.expand_path(File.join(game_root_path, CORE_UPDATE_INSTALLER))
      end

      def launch_core_update_installer(path)
        normalized = File.expand_path(path.to_s)
        return false unless File.file?(normalized)
        return false unless under_game_root?(normalized)
        system("cmd", "/c", "start", "", "/D", File.dirname(normalized), normalized)
      end

      def close_game_for_core_update
        @running = false if instance_variable_defined?(:@running)
        $scene = nil
      rescue Exception
        exit
      end

      def core_patch_notes_path
        resolve_local_changelog_path("Reloaded/Changelog.md")
      end

      def open_core_patch_notes
        path = core_patch_notes_path
        if path.empty?
          show_message("Patch notes file was not found.")
          return
        end
        open_patch_notes_file(path)
      end

      def open_mods_folder
        path = File.expand_path(File.join(game_root_path, "Mods"))
        ensure_local_directory(path)
        open_external_path(path, "Mods folder")
      rescue Exception => e
        Reloaded::Log.exception("Open Mods folder failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not open Mods folder.")
      end

      def file_bug_report
        unless defined?(Reloaded::ModderTools)
          show_message("Log export tools are not available.")
          return
        end
        url = Reloaded::ModderTools.export_log("LatestBugReport.txt")
        bug_report_link = "[Bug Report](#{url})"
        copied = Reloaded::ModManagerUI.clipboard_write(bug_report_link)
        opened = open_external_url(BUG_REPORT_THREAD_URL, "bug report thread")
        if copied && opened
          show_message("LatestBugReport.txt uploaded.\nBug report link copied to clipboard:\n#{bug_report_link}\nDiscord thread opened.")
        elsif copied
          show_message("LatestBugReport.txt uploaded.\nBug report link copied to clipboard:\n#{bug_report_link}\nCould not open Discord thread.")
        elsif opened
          show_message("LatestBugReport.txt uploaded.\nDiscord thread opened.\nCould not copy formatted bug report link.")
        else
          show_message("LatestBugReport.txt uploaded.\nCould not copy formatted bug report link or open Discord thread.\n#{url}")
        end
      rescue Exception => e
        Reloaded::Log.exception("File bug report failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not export bug report:\n#{e.message}")
      end

      def open_external_path(path, label = "file")
        normalized = File.expand_path(path.to_s)
        unless File.exist?(normalized) || File.directory?(normalized)
          show_message("#{label.capitalize} was not found.")
          return false
        end
        unless under_game_root?(normalized)
          show_message("Refusing to open a path outside the game folder.")
          return false
        end
        ok = system("cmd", "/c", "start", "", normalized)
        show_message("Could not open #{label}.") unless ok
        Reloaded::Log.info("Opened #{label}: #{relative_game_path(normalized)}", :mods) if ok && defined?(Reloaded::Log)
        ok
      rescue Exception => e
        Reloaded::Log.exception("Open #{label} failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not open #{label}.")
        false
      end

      def open_external_url(url, label = "link")
        value = url.to_s.strip
        unless value =~ /\Ahttps?:\/\/[^\s]+\z/i
          show_message("Invalid #{label}.")
          return false
        end
        ok = system("cmd", "/c", "start", "", value)
        show_message("Could not open #{label}.") unless ok
        Reloaded::Log.info("Opened #{label}: #{value}", :mods) if ok && defined?(Reloaded::Log)
        ok
      rescue Exception => e
        Reloaded::Log.exception("Open #{label} failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not open #{label}.")
        false
      end

      def open_patch_notes_file(path)
        normalized = File.expand_path(path.to_s)
        unless File.exist?(normalized)
          show_message("Patch notes file was not found.")
          return false
        end
        unless under_game_root?(normalized)
          show_message("Refusing to open a path outside the game folder.")
          return false
        end
        win_path = normalized.gsub("/", "\\")
        ok = system("start \"\" \"#{win_path}\"")
        show_message("Patch notes file:\n#{relative_game_path(normalized)}") unless ok
        Reloaded::Log.info("Opened patch notes: #{relative_game_path(normalized)}", :mods) if ok && defined?(Reloaded::Log)
        ok
      rescue Exception => e
        Reloaded::Log.exception("Open patch notes failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Patch notes file:\n#{relative_game_path(normalized || path)}")
        false
      end

      def game_root_path
        File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
      end

      def under_game_root?(path)
        root = normalize_path(game_root_path)
        value = normalize_path(path)
        value == root || value.start_with?(root + "/")
      end

      def relative_game_path(path)
        normalize_path(path).sub(normalize_path(game_root_path) + "/", "")
      end

      def ensure_local_directory(path)
        target = File.expand_path(path.to_s)
        raise "Refusing to create a folder outside the game folder." unless under_game_root?(target)
        Dir.mkdir(target) unless Dir.exist?(target)
      end

      def normalize_path(path)
        path.to_s.gsub("\\", "/")
      end

      def compare_versions(left, right)
        left_parts = left.to_s.scan(/\d+/).map(&:to_i)
        right_parts = right.to_s.scan(/\d+/).map(&:to_i)
        max = [left_parts.length, right_parts.length, 3].max
        (0...max).each do |index|
          lval = left_parts[index] || 0
          rval = right_parts[index] || 0
          return -1 if lval < rval
          return 1 if lval > rval
        end
        0
      end

      def show_message(text, choices = nil, start_index = 0, center_text = false)
        text = Reloaded::Log.sanitize(text) if defined?(Reloaded::Log)
        choice_count = choices ? choices.length : 0
        pad = 14
        hint_h = choices ? 18 : 0
        box_w = 420
        font_size = 15
        line_h = 18
        lines = []
        choice_lines = []
        choice_heights = []
        box_h = 0
        measure = Bitmap.new(1, 1)
        begin
          loop do
            apply_ui_font(measure)
            measure.font.size = font_size rescue nil
            line_h = [font_size + 3, 14].max
            lines = wrapped_lines(measure, text.to_s, box_w - pad * 2)
            choice_lines = choices ? choices.map { |choice| wrapped_lines(measure, choice.to_s, box_w - pad * 2 - 16) } : []
            choice_heights = choice_lines.map { |row_lines| [row_lines.length, 1].max * line_h }
            box_h = pad * 2 + lines.length * line_h
            box_h += choices ? choice_heights.inject(0) { |sum, height| sum + height } + hint_h + 14 : line_h + 4
            break if box_h <= SCREEN_H - 16 || font_size <= 11
            font_size -= 1
          end
        ensure
          measure.dispose rescue nil
        end
        dim = Sprite.new(@viewport)
        dim.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
        dim.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, Color.new(0, 0, 0, 130))
        dim.z = 900

        box_x = (SCREEN_W - box_w) / 2
        box_y = (SCREEN_H - box_h) / 2

        box = Sprite.new(@viewport)
        box.bitmap = Bitmap.new(box_w, box_h)
        box.x = box_x
        box.y = box_y
        box.z = 901

        selected = choices ? 0 : start_index.to_i
        selected = [[selected, 0].max, [choice_count - 1, 0].max].min

        redraw = proc do
          bitmap = box.bitmap
          bitmap.clear
          draw_rounded_rect(bitmap, 0, 0, box_w, box_h, PANEL_BG)
          draw_border(bitmap, 0, 0, box_w, box_h, PANEL_BORDER)
          apply_ui_font(bitmap)
          bitmap.font.size = font_size rescue nil
          y = pad
          lines.each do |line|
            align = center_text ? 1 : 0
            draw_plain_text(bitmap, pad, y, box_w - pad * 2, line_h, line, WHITE, align)
            y += line_h
          end
          if choices
            y += 4
            choice_lines.each_with_index do |row_lines, index|
              row_h = choice_heights[index]
              draw_selection_box(bitmap, pad, y, box_w - pad * 2, row_h, popup_selection_fill) if index == selected
              color = index == selected ? WHITE : GRAY
              row_lines.each_with_index do |line, line_index|
                draw_plain_text(bitmap, pad + 8, y + line_index * line_h - 6, box_w - pad * 2 - 16, line_h, line, color)
              end
              y += row_h
            end
            draw_hint_text(bitmap, "Confirm (C) Back (B)", 0, box_h - 20, box_w)
          else
            draw_plain_text(bitmap, -10, y + 4, box_w, line_h, "[OK]", GRAY, 1)
          end
        end

        redraw.call
        loop do
          Graphics.update
          Input.update
          redraw.call if choices && ((Graphics.frame_count rescue 0) % 4 == 0)
          old_selected = selected
          if choices
            selected = (selected - 1 + choices.length) % choices.length if Input.repeat?(Input::UP)
            selected = (selected + 1) % choices.length if Input.repeat?(Input::DOWN)
            selected = (selected - 4 + choices.length) % choices.length if Input.repeat?(Input::LEFT)
            selected = (selected + 4) % choices.length if Input.repeat?(Input::RIGHT)
            mx, my = InputSupport.mouse_pos
            if mx && my && mx >= box_x + pad && mx < box_x + box_w - pad
              y = box_y + pad + lines.length * line_h + 4
              choice_heights.each_with_index do |height, index|
                selected = index if my >= y && my < y + height
                y += height
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

      def show_colored_lines(title, colored_lines)
        title = Reloaded::Log.sanitize(title) if defined?(Reloaded::Log)
        dim = Sprite.new(@viewport)
        dim.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
        dim.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, Color.new(0, 0, 0, 130))
        dim.z = 900

        pad = 16
        line_h = 18
        title_h = 32
        hint_h = 22
        max_visible = 12
        visible_count = [[colored_lines.length, 1].max, max_visible].min
        box_w = 460
        box_h = title_h + visible_count * line_h + hint_h + pad
        box_x = (SCREEN_W - box_w) / 2
        box_y = (SCREEN_H - box_h) / 2
        scroll = 0

        box = Sprite.new(@viewport)
        box.bitmap = Bitmap.new(box_w, box_h)
        box.x = box_x
        box.y = box_y
        box.z = 901

        redraw = proc do
          bitmap = box.bitmap
          bitmap.clear
          draw_rounded_rect(bitmap, 0, 0, box_w, box_h, PANEL_BG)
          draw_border(bitmap, 0, 0, box_w, box_h, PANEL_BORDER)
          apply_ui_font(bitmap)
          bitmap.font.size = 14 rescue nil
          draw_plain_text(bitmap, pad, 8, box_w - pad * 2, 18, title.to_s, WHITE)
          bitmap.fill_rect(pad, title_h - 2, box_w - pad * 2, 1, PANEL_LINE)
          colored_lines.each_with_index do |entry, index|
            next if index < scroll
            break if index >= scroll + max_visible
            y = title_h + (index - scroll) * line_h
            line_text = entry[:text].to_s
            line_text = Reloaded::Log.sanitize(line_text) if defined?(Reloaded::Log)
            draw_plain_text(bitmap, pad + 4, y, box_w - pad * 2, line_h, line_text, entry[:color] || GRAY)
          end
          hint = colored_lines.length > max_visible ? "Scroll (Up/Down) Confirm (C) Back (B)" : "Confirm (C) Back (B)"
          draw_hint_text(bitmap, hint, 0, box_h - 20, box_w)
        end

        redraw.call
        loop do
          Graphics.update
          Input.update
          moved = false
          if Input.trigger?(Input::UP) && scroll > 0
            scroll -= 1
            moved = true
          elsif Input.trigger?(Input::DOWN) && scroll < colored_lines.length - max_visible
            scroll += 1
            moved = true
          end
          redraw.call if moved
          break if Input.trigger?(Input::C) || Input.trigger?(Input::B) || InputSupport.mouse_left_trigger? || InputSupport.mouse_right_trigger?
        end
      ensure
        box.bitmap.dispose rescue nil
        box.dispose rescue nil
        dim.bitmap.dispose rescue nil
        dim.dispose rescue nil
      end

      def checkbox_picker(title, entries)
        rows = Array(entries).map do |entry|
          entry.is_a?(Hash) ? entry : { :label => entry.to_s, :value => entry }
        end
        return [] if rows.empty?
        dim = Sprite.new(@viewport)
        dim.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
        dim.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, Color.new(0, 0, 0, 130))
        dim.z = 900

        pad = 16
        line_h = 20
        title_h = 34
        hint_h = 22
        max_visible = 11
        visible_count = [[rows.length, 1].max, max_visible].min
        box_w = 460
        box_h = title_h + visible_count * line_h + hint_h + pad
        box_x = (SCREEN_W - box_w) / 2
        box_y = (SCREEN_H - box_h) / 2
        selected = 0
        scroll = 0
        checked = {}

        box = Sprite.new(@viewport)
        box.bitmap = Bitmap.new(box_w, box_h)
        box.x = box_x
        box.y = box_y
        box.z = 901

        redraw = proc do
          bitmap = box.bitmap
          bitmap.clear
          draw_rounded_rect(bitmap, 0, 0, box_w, box_h, PANEL_BG)
          draw_border(bitmap, 0, 0, box_w, box_h, PANEL_BORDER)
          apply_ui_font(bitmap)
          bitmap.font.size = 14 rescue nil
          draw_plain_text(bitmap, pad, 8, box_w - pad * 2, 18, title.to_s, WHITE)
          bitmap.fill_rect(pad, title_h - 2, box_w - pad * 2, 1, PANEL_LINE)
          rows.each_with_index do |entry, index|
            next if index < scroll
            break if index >= scroll + max_visible
            y = title_h + (index - scroll) * line_h
            draw_selection_box(bitmap, pad, y, box_w - pad * 2, line_h, popup_selection_fill) if index == selected
            mark = checked[index] ? "[x]" : "[ ]"
            color = index == selected ? WHITE : GRAY
            draw_plain_text(bitmap, pad + 6, y - 7, 34, line_h, mark, color)
            label = trim_text(bitmap, entry[:label].to_s, box_w - pad * 2 - 48)
            draw_plain_text(bitmap, pad + 44, y - 7, box_w - pad * 2 - 48, line_h, label, color)
          end
          draw_hint_text(bitmap, "Toggle (C) Back (B) Confirm (A)", 0, box_h - 20, box_w)
        end

        redraw.call
        accepted = false
        loop do
          Graphics.update
          Input.update
          redraw.call if ((Graphics.frame_count rescue 0) % 4 == 0)
          old_selected = selected
          if Input.trigger?(Input::UP)
            selected = (selected - 1 + rows.length) % rows.length
          elsif Input.trigger?(Input::DOWN)
            selected = (selected + 1) % rows.length
          end
          if selected < scroll
            scroll = selected
          elsif selected >= scroll + max_visible
            scroll = selected - max_visible + 1
          end
          mx, my = InputSupport.mouse_pos
          if mx && my && mx >= box_x + pad && mx < box_x + box_w - pad
            rows.each_with_index do |_, index|
              next if index < scroll || index >= scroll + max_visible
              y = box_y + title_h + (index - scroll) * line_h
              selected = index if my >= y && my < y + line_h
            end
          end
          if Input.trigger?(Input::C) || InputSupport.mouse_left_trigger?
            checked[selected] = !checked[selected]
            redraw.call
          elsif menu_trigger? || key_trigger?(0x0D)
            accepted = true
            break
          elsif Input.trigger?(Input::B) || InputSupport.mouse_right_trigger?
            accepted = false
            break
          end
          redraw.call if selected != old_selected
        end
        return nil unless accepted
        rows.each_with_index.select { |_, index| checked[index] }.map { |entry, _| entry[:value] }
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
          draw_plain_text(bitmap, 14, 10, box_w - 28, 18, title.to_s, WHITE)
          draw_rounded_rect(bitmap, 14, 38, box_w - 28, 28, SEARCH_ACTIVE)
          draw_border(bitmap, 14, 38, box_w - 28, 28, PANEL_LINE)
          cursor = ((Graphics.frame_count rescue 0) / 20) % 2 == 0 ? "|" : ""
          shown = trim_text(bitmap, value + cursor, box_w - 42)
          draw_plain_text(bitmap, 22, 43, box_w - 44, 18, shown, WHITE)
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
          if key_trigger?(0x56) && key_pressed?(0x11)
            pasted = Reloaded::ModManagerUI.clipboard_read.to_s
            space = max_length - value.length
            value += pasted[0, space] if space > 0 && !pasted.empty?
          end
          if key_trigger?(0x43) && key_pressed?(0x11)
            Reloaded::ModManagerUI.clipboard_write(value)
          end
          if key_trigger?(0x41) && key_pressed?(0x11)
            value = ""
          end
          value = value[0...-1] if key_repeat?(0x08) && !value.empty?
          value = "" if key_trigger?(0x2E)
          (0x41..0x5A).each do |vk|
            next unless key_trigger?(vk)
            next if key_pressed?(0x11)
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
        draw_plain_text(bitmap, 260, 9, SCREEN_W - 268, 14, "Active: #{active_name}", BLUE, 1)
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
        pbDrawTextPositions(bitmap, [[status, x, y, 0, active_profile?(profile) ? GREEN : RED, Color.new(0, 0, 0, 0)]])
        y += 22
        enabled = profile_mod_names(profile["enabled_mods"])
        disabled = profile_mod_names(profile["disabled_mods"])
        bitmap.font.size = 14 rescue nil
        pbDrawTextPositions(bitmap, [["Enabled Mods: #{summary[:enabled_mods] || 0}", x, y, 0, GREEN, Color.new(0, 0, 0, 0)]])
        y += 16
        y = draw_profile_mod_list(bitmap, x, y, enabled, GREEN)
        y += 4
        pbDrawTextPositions(bitmap, [["Disabled Mods: #{summary[:disabled_mods] || 0}", x, y, 0, RED, Color.new(0, 0, 0, 0)]])
        y += 16
        y = draw_profile_mod_list(bitmap, x, y, disabled, DIM)
        y += 4
        draw_plain_text(bitmap, x, y, PROFILE_RIGHT_W - 24, 16, "Load Order Entries: #{summary[:load_order] || 0}", GRAY)
        y += 18
        draw_plain_text(bitmap, x, y, PROFILE_RIGHT_W - 24, 16, "Mod Settings: #{summary[:mod_settings] || 0}", GRAY)
        y += 24
        bitmap.fill_rect(x, y, PROFILE_RIGHT_W - 24, 1, PANEL_BORDER)
        y += 8
        bitmap.font.size = 15 rescue nil
        pbDrawTextPositions(bitmap, [["Notes", x, y, 0, BLUE, Color.new(0, 0, 0, 0)]])
        y += 18
        apply_ui_font(bitmap)
        bitmap.font.size = 14 rescue nil
        notes = profile["notes"].to_s.empty? ? "No notes set." : profile["notes"].to_s
        wrapped_lines(bitmap, notes, PROFILE_RIGHT_W - 28).each do |line|
          break if y + 16 > CONTENT_H - 32
          pbDrawTextPositions(bitmap, [[line, x, y, 0, DIM, Color.new(0, 0, 0, 0)]])
          y += 16
        end
        draw_panel_hint(bitmap, "Confirm (C) Back (B) Menu (A)", PROFILE_RIGHT_W, CONTENT_H)
      end

      def profile_mod_names(ids)
        Array(ids).map do |id|
          row = defined?(Reloaded::ModManager) ? Reloaded::ModManager.mod_row(id) : nil
          row ? row[:name].to_s : id.to_s
        end.reject { |name| name.empty? }
      rescue
        []
      end

      def draw_profile_mod_list(bitmap, x, y, names, color)
        bitmap.font.size = 13 rescue nil
        if names.empty?
          pbDrawTextPositions(bitmap, [["None", x + 8, y, 0, DIM, Color.new(0, 0, 0, 0)]])
          return y + 15
        end
        names.first(3).each do |name|
          pbDrawTextPositions(bitmap, [[trim_text(bitmap, name, PROFILE_RIGHT_W - 40), x + 8, y, 0, color, Color.new(0, 0, 0, 0)]])
          y += 15
        end
        if names.length > 3
          pbDrawTextPositions(bitmap, [["+#{names.length - 3} more", x + 8, y, 0, DIM, Color.new(0, 0, 0, 0)]])
          y += 15
        end
        y
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
            open_selected_profile_menu if clicked
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
        elsif Input.repeat?(Input::LEFT) && !@profiles.empty?
          @selected_index = (@selected_index - 4 + @profiles.length) % @profiles.length
          ensure_visible
          changed = true
        elsif Input.repeat?(Input::RIGHT) && !@profiles.empty?
          @selected_index = (@selected_index + 4) % @profiles.length
          ensure_visible
          changed = true
        end
        open_selected_profile_menu if Input.trigger?(Input::C)
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
        choices = ["New Profile", "Back"]
        choice = show_message("Profile Menu", choices)
        case choices[choice]
        when "New Profile" then create_profile
        end
      end

      def open_selected_profile_menu
        profile = selected_profile
        return unless profile
        choices = ["Enable/Disable", "Duplicate", "Rename", "Delete", "Import Code", "Export Code", "Back"]
        choice = show_message("Profile Actions", choices)
        case choices[choice]
        when "Enable/Disable" then toggle_selected_profile
        when "Duplicate" then duplicate_profile
        when "Rename" then rename_profile
        when "Delete" then delete_profile
        when "Import Code" then import_profile_code
        when "Export Code" then export_profile_code
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

      def profile_code_input(prompt)
        text_input_popup(prompt, "", 16384)
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

      def toggle_selected_profile
        profile = selected_profile
        return unless profile
        if active_profile?(profile)
          if default_profile?(profile)
            show_message("The default profile cannot be disabled.")
            return
          end
          Reloaded::Profiles.activate(Reloaded::Profiles::DEFAULT_PROFILE_NAME) if defined?(Reloaded::Profiles)
          Reloaded::Log.info("Mod Manager UI disabled profile #{profile["name"]}", :mods) if defined?(Reloaded::Log)
          mark_restart_required("disabled profile #{profile["name"]}")
          refresh_profiles
          draw_all
        else
          activate_selected_profile
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to toggle profile", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not toggle profile:\n#{e.message}")
      end

      def create_profile
        name = profile_name_input("New profile name")
        return if name.empty?
        profile = defined?(Reloaded::Profiles) ? Reloaded::Profiles.create(name, activate: true) : nil
        seed_profile_from_installed(profile) if profile
        Reloaded::Log.info("Mod Manager UI created profile #{name}", :mods) if defined?(Reloaded::Log)
        mark_restart_required("created and activated profile #{name}")
        select_profile(name)
      rescue Exception => e
        Reloaded::Log.exception("Failed to create profile", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not create profile:\n#{e.message}")
      end

      def seed_profile_from_installed(profile)
        ids = installed_profile_seed_ids
        return if ids.empty?
        profile["enabled_mods"] = ids
        profile["disabled_mods"] = []
        profile["load_order"] = ids
        Reloaded::Profiles.write_profile(profile) if defined?(Reloaded::Profiles)
        Reloaded::Profiles.activate(profile["name"]) if defined?(Reloaded::Profiles)
      rescue Exception => e
        Reloaded::Log.exception("Failed to seed profile from installed mods", e, channel: :mods) if defined?(Reloaded::Log)
      end

      def installed_profile_seed_ids
        return [] unless defined?(Reloaded::ModManager)
        Reloaded::ModManager.refresh_metadata rescue nil
        Reloaded::ModManager.mod_rows.map { |row| row[:id].to_s }.reject { |id| id.empty? }.uniq
      rescue
        []
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

      def export_profile_code
        profile = selected_profile
        return unless profile
        unless defined?(Reloaded::ProfileCodes)
          show_message("Profile code system is not available.")
          return
        end
        code = Reloaded::ProfileCodes.export_profile(profile["name"], preset_name: profile["name"])
        copied = Reloaded::ModManagerUI.clipboard_write(code)
        if copied
          show_message("Profile code copied to clipboard.")
        else
          show_message("Profile code:\n#{code}")
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to export profile code", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not export profile code:\n#{e.message}")
      end

      def import_profile_code
        unless defined?(Reloaded::ProfileCodes)
          show_message("Profile code system is not available.")
          return
        end
        code = profile_code_input("Paste profile code")
        return if code.empty?
        payload = Reloaded::ProfileCodes.decode(code)
        missing = Reloaded::ProfileCodes.missing_mod_ids(payload)
        disable_after_download = []
        unless missing.empty?
          choice = show_message("Missing mods:\n#{missing.join(", ")}", ["Download", "Download & Enable", "Back"])
          return if choice != 0 && choice != 1
          unless defined?(Reloaded::ModBrowser)
            show_message("Mod Browser downloads are not available yet.")
            return
          end
          result = Reloaded::ModBrowser.download_mods(missing, enable: choice == 1)
          failed = Array(result[:failed])
          installed = Array(result[:installed])
          unless failed.empty?
            show_message(download_failure_message(result))
            return
          end
          disable_after_download = installed if choice == 0
          Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
        end
        profile = Reloaded::ProfileCodes.import_code(code, activate: true, disable_mod_ids: disable_after_download)
        mark_restart_required("imported and activated profile #{profile["name"]}")
        select_profile(profile["name"])
      rescue Exception => e
        Reloaded::Log.exception("Failed to import profile code", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not import profile code:\n#{e.message}")
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

    class Scene_Browser
      include UIHelpers

      FOOTER_BUTTONS = ["Back"].freeze

      def initialize
        @viewport = nil
        @running = false
        @rows = []
        @selected_index = 0
        @scroll = 0
        @search_text = ""
        @search_active = false
        @cursor_frame = 0
        @filter = :mods
        @footer_index = 0
        @focus = :list
        @description_scroll = 0
        @showing_changelog = false
        @changelog_text = ""
        @changelog_row_id = nil
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
        restart_required = @restart_required
        teardown
        Graphics.transition(8)
        restart_required
      end

      def setup
        @running = true
        Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
        Reloaded::ModBrowser.refresh(fetch_remote: true) if defined?(Reloaded::ModBrowser)
        @viewport = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
        @viewport.z = 100_020

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
        rows = browser_rows
        query = @search_text.to_s.downcase
        unless query.empty?
          rows = rows.select do |row|
            [row["id"], row["name"], row["description"]].any? { |value| value.to_s.downcase.include?(query) } ||
              Array(row["authors"]).any? { |value| value.to_s.downcase.include?(query) } ||
              Array(row["tags"]).any? { |value| value.to_s.downcase.include?(query) }
          end
        end
        rows = rows.select { |row| row["kind"] == "mod" } if @filter == :mods
        rows = rows.select { |row| row["kind"] == "profile" } if @filter == :profiles
        rows = rows.select { |row| row["installed"] } if @filter == :installed
        rows = rows.select { |row| !row["installed"] } if @filter == :available
        @rows = rows
        @selected_index = [[@selected_index, 0].max, [@rows.length - 1, 0].max].min
        ensure_visible
      end

      def browser_rows
        installed = installed_mod_ids
        profiles = installed_profile_ids
        rows = []
        if defined?(Reloaded::ModBrowser)
          Reloaded::ModBrowser.entries.values.each do |entry|
            copy = entry.dup
            next if core_entry_row?(copy) || spritepack_entry_row?(copy)
            copy["kind"] = "mod"
            copy["installed"] = installed.include?(copy["id"].to_s)
            rows << copy
          end
          Reloaded::ModBrowser.profile_entries.values.each do |entry|
            copy = entry.dup
            copy["kind"] = "profile"
            copy["installed"] = profiles.include?(copy["id"].to_s) || profiles.include?(copy["name"].to_s.downcase)
            rows << copy
          end
        end
        rows.sort_by { |row| [special_entry_priority(row), row["kind"] == "profile" ? 1 : 0, row["name"].to_s.downcase, row["id"].to_s] }
      end

      def installed_mod_ids
        ids = defined?(Reloaded::ModManager) ? Reloaded::ModManager.mod_ids.map(&:to_s) : []
        ids << core_entry_id
        ids.uniq
      rescue
        []
      end

      def installed_profile_ids
        return [] unless defined?(Reloaded::Profiles)
        Reloaded::Profiles.list.map do |profile|
          [profile["id"].to_s.downcase, profile["name"].to_s.downcase]
        end.flatten.reject { |value| value.empty? }
      rescue
        []
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
        title = @filter == :profiles ? "Profile Browser (L/R)" : "Mod Browser (L/R)"
        pbDrawShadowText(bitmap, MARGIN, 5, -1, 24, title, WHITE, SHADOW)
        apply_ui_font(bitmap)
        bitmap.font.size = 12 rescue nil
        pbDrawTextPositions(bitmap, [[@rows.length.to_s, SCREEN_W - MARGIN - 3, 0, 2, GRAY, Color.new(0, 0, 0, 0)]])
        pbDrawTextPositions(bitmap, [[browser_sync_status_text, SCREEN_W - MARGIN - 23, 13, 2, DIM, Color.new(0, 0, 0, 0)]])
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
                         "Search (Click)"
                       else
                         @search_text
                       end
        bitmap.font.size = 13 rescue nil
        pbDrawShadowText(bitmap, 12, 8, LEFT_W - 24, 16, search_label, @search_text.empty? && !@search_active ? DIM : WHITE, SHADOW)

        visible = @rows[@scroll, rows_per_page] || []
        if @rows.empty?
          apply_ui_font(bitmap)
          bitmap.font.size = 15 rescue nil
          pbDrawShadowText(bitmap, 0, CONTENT_H / 2 - 10, LEFT_W, 20, "No browser entries", DIM, SHADOW, 1)
        end
        visible.each_with_index do |row, offset|
          index = @scroll + offset
          y = LIST_Y + offset * ROW_H
          selected = index == @selected_index && @focus == :list
          draw_rounded_rect(bitmap, 6, y, LEFT_W - 12, ROW_H - 3, row["installed"] ? ROW_NORMAL : ROW_DISABLED)
          draw_selection_box(bitmap, 6, y - 1, LEFT_W - 12, ROW_H - 2) if selected
          color = browser_row_color(row, selected)
          priority = special_entry_priority(row)
          if priority == 0
            bitmap.font.size = 16 rescue nil
            draw_plain_text(bitmap, 11, y + 1, 10, ROW_H, "*", YELLOW, 1)
          else
            marker_color = priority == 1 ? PURPLE : (row["kind"] == "profile" ? PURPLE : BLUE)
            bitmap.fill_rect(13, y + 7, 6, 6, marker_color)
          end
          bitmap.font.size = 18 rescue nil
          label = trim_text(bitmap, row["name"], LEFT_W - 44)
          draw_plain_text(bitmap, 25, y - 6, LEFT_W - 38, ROW_H, label, color)
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
        draw_panel(bitmap, RIGHT_W, CONTENT_H, row ? row["name"].to_s : "Browser")

        unless row
          draw_panel_hint(bitmap, browser_hint_text, RIGHT_W, CONTENT_H, 90)
          return
        end

        if @showing_changelog
          draw_changelog_panel(bitmap, row)
          return
        end

        x = 12
        y = 29
        apply_ui_font(bitmap)
        bitmap.font.size = 14 rescue nil
        authors = Array(row["authors"]).join(", ")
        pbDrawTextPositions(bitmap, [["by #{authors.empty? ? 'Unknown' : authors}", x, y - 7, 0, GRAY, Color.new(0, 0, 0, 0)]])
        y += 16
        version = row["kind"] == "profile" ? row["version"] : row["latest_version"]
        pbDrawTextPositions(bitmap, [["v#{version}", x, y - 9, 0, row["installed"] ? GREEN : GRAY, Color.new(0, 0, 0, 0)]])
        y += 12

        y = draw_browser_tags(bitmap, x, y, row)
        bitmap.fill_rect(x, y, RIGHT_W - 24, 1, PANEL_BORDER)
        y += 6
        title = row["kind"] == "profile" ? "Profile Details" : "Description"
        bitmap.font.size = 16 rescue nil
        pbDrawTextPositions(bitmap, [[title, x, y - 10, 0, BLUE, Color.new(0, 0, 0, 0)]])
        y += 19

        row["kind"] == "profile" ? draw_profile_browser_details(bitmap, row, x, y) : draw_mod_browser_details(bitmap, row, x, y - 10)

        draw_browser_summary(bitmap, row)
        draw_panel_hint(bitmap, browser_hint_text, RIGHT_W, CONTENT_H, 90)
      end

      def draw_mod_browser_details(bitmap, row, x, y)
        bitmap.font.size = 15 rescue nil
        lines = browser_description_lines(bitmap, row, RIGHT_W - 34)
        draw_scrollable_text_lines(bitmap, lines, x, y, CONTENT_H - 76)
      end

      def draw_profile_browser_details(bitmap, row, x, y)
        bitmap.font.size = 15 rescue nil
        entries = profile_detail_entries(bitmap, row, RIGHT_W - 34)
        row_h = 17
        hint_y = CONTENT_H - 76
        top = y
        max_visible = [(hint_y - y) / row_h, 1].max
        @description_scroll = [[@description_scroll, 0].max, [entries.length - max_visible, 0].max].min
        entries.each_with_index do |entry, index|
          next if index < @description_scroll
          break if y + row_h > hint_y
          case entry[:type]
          when :title
            pbDrawTextPositions(bitmap, [[entry[:text], x, y, 0, BLUE, Color.new(0, 0, 0, 0)]])
          when :mod
            draw_mod_status_row(bitmap, x, y, entry)
          else
            pbDrawTextPositions(bitmap, [[entry[:text].to_s, x, y, 0, entry[:color] || GRAY, Color.new(0, 0, 0, 0)]])
          end
          y += row_h
        end
        draw_scrollbar(bitmap, RIGHT_W - 14, top, hint_y - top, entries.length, max_visible)
      end

      def draw_changelog_panel(bitmap, row)
        x = 12
        y = 31
        apply_ui_font(bitmap)
        bitmap.font.size = 16 rescue nil
        pbDrawTextPositions(bitmap, [["Changelog", x, y - 5, 0, BLUE, Color.new(0, 0, 0, 0)]])
        y += 21
        bitmap.fill_rect(x, y - 3, RIGHT_W - 24, 1, PANEL_LINE)
        y += 6
        bitmap.font.size = 15 rescue nil
        lines = wrapped_lines(bitmap, @changelog_text.to_s, RIGHT_W - 34)
        lines = ["No changelog text found."] if lines.empty?
        draw_scrollable_text_lines(bitmap, lines, x, y, CONTENT_H - 36)
        draw_panel_hint(bitmap, browser_hint_text, RIGHT_W, CONTENT_H, 90)
      end

      def draw_scrollable_text_lines(bitmap, lines, x, y, hint_y)
        top = y
        max_visible = [(hint_y - top) / 17, 1].max
        @description_scroll = [[@description_scroll, 0].max, [lines.length - max_visible, 0].max].min
        lines.each_with_index do |line, index|
          next if index < @description_scroll
          break if y + 17 > hint_y
          pbDrawTextPositions(bitmap, [[line, x, y, 0, GRAY, Color.new(0, 0, 0, 0)]])
          y += 17
        end
        draw_scrollbar(bitmap, RIGHT_W - 14, top, hint_y - top, lines.length, max_visible)
      end

      def draw_scrollbar(bitmap, bar_x, bar_y, bar_h, total, visible)
        return if total <= visible
        bitmap.fill_rect(bar_x, bar_y, 8, bar_h, Color.new(0, 0, 0, 60))
        max_scroll = [total - visible, 1].max
        handle_h = [[bar_h * visible / total, 14].max, bar_h].min
        handle_y = bar_y + (bar_h - handle_h) * @description_scroll.to_f / max_scroll
        bitmap.fill_rect(bar_x + 1, handle_y.to_i, 6, handle_h, GRAY)
      end

      def browser_description_lines(bitmap, row, width)
        lines = wrapped_lines(bitmap, row["description"], width)
        if row["kind"] == "mod"
          versions = sorted_versions(Array(row["versions"])).map { |entry| entry["version"].to_s }.reject { |value| value.empty? }
          lines += ["", "", "Versions: #{versions.join(", ")}"] unless versions.empty?
        end
        lines
      end

      def profile_detail_entries(bitmap, row, width)
        entries = wrapped_lines(bitmap, row["description"], width).map { |line| { :type => :text, :text => line, :color => GRAY } }
        entries << { :type => :text, :text => "" }
        entries << { :type => :title, :text => "Mod List:" }
        mods = Array(row["mods"])
        if mods.empty?
          entries << { :type => :text, :text => "None listed.", :color => DIM }
        else
          mods.each { |mod| entries << profile_mod_entry(mod) }
        end
        entries
      end

      def profile_mod_entry(mod)
        id = mod["id"].to_s
        wanted = mod["version"].to_s
        installed = defined?(Reloaded::ModManager) ? Reloaded::ModManager.mod_row(id) : nil
        browser = defined?(Reloaded::ModBrowser) ? Reloaded::ModBrowser.entry(id) : nil
        name = installed ? installed[:name].to_s : (browser ? browser["name"].to_s : id)
        version = wanted.empty? ? (browser ? browser["latest_version"].to_s : "") : wanted
        if installed.nil?
          status = "Missing"
          color = RED
        elsif !wanted.empty? && compare_versions(installed[:version], wanted) < 0
          status = "Update"
          color = ORANGE
        else
          status = "OK"
          color = GREEN
        end
        { :type => :mod, :status => status, :color => color, :name => name, :version => version }
      rescue
        { :type => :mod, :status => "Missing", :color => RED, :name => mod["id"].to_s, :version => mod["version"].to_s }
      end

      def draw_mod_status_row(bitmap, x, y, entry)
        bitmap.font.size = 12 rescue nil
        tag = entry[:status].to_s
        tag_w = [bitmap.text_size(tag).width + 8, 32].max
        y += 5
        draw_rounded_rect(bitmap, x, y + 1, tag_w, 15, color_with_alpha(entry[:color], 90))
        text_y = tag == "OK" || tag == "Update" ? y + 1 : y
        pbDrawShadowText(bitmap, x, text_y, tag_w, 15, tag, entry[:color], Color.new(0, 0, 0, 0), 1)
        bitmap.font.size = 15 rescue nil
        text = "#{entry[:name]} #{entry[:version]}".strip
        pbDrawShadowText(bitmap, x + tag_w + 6, y, RIGHT_W - tag_w - 40, 17, trim_text(bitmap, text, RIGHT_W - tag_w - 46), GRAY, SHADOW)
      end

      def draw_browser_summary(bitmap, row)
        x = 12
        y = CONTENT_H - 64
        bitmap.fill_rect(x, y - 6, RIGHT_W - 24, 1, PANEL_LINE)
        apply_ui_font(bitmap)
        if row["kind"] == "mod"
          deps = Array(row["dependencies"])
          bitmap.font.size = 16 rescue nil
          draw_plain_text(bitmap, x, y, RIGHT_W - 24, 18, "Dependencies: #{deps.length}", BLUE)
        else
          mods = Array(row["mods"])
          bitmap.font.size = 16 rescue nil
          pbDrawShadowText(bitmap, x, y, RIGHT_W - 24, 18, "Included Mods: #{mods.length}", BLUE, SHADOW)
        end
      end

      def sorted_versions(versions)
        versions.sort_by do |entry|
          version = entry["version"].to_s
          parts = version.scan(/\d+/).map(&:to_i)
          [parts[0] || 0, parts[1] || 0, parts[2] || 0, version]
        end.reverse
      end

      def draw_browser_tags(bitmap, x, y, row)
        tags = (admin_tags_for(row) + Array(row["tags"])).uniq
        bitmap.font.size = 12 rescue nil
        tags.each do |tag|
          label = tag_label(tag)
          width = bitmap.text_size(label).width + 8
          if x + width > RIGHT_W - 12
            x = 12
            y += 18
          end
          bg, color = tag_style(label)
          draw_rounded_rect(bitmap, x, y, width, 16, bg)
          pbDrawTextPositions(bitmap, [[label, x + 4, y - 5, 0, color, Color.new(0, 0, 0, 0)]])
          x += width + 4
        end
        y + 20
      end

      def tag_style(tag)
        key = tag_key(tag)
        case key
        when "outdated", "broken", "invalid"
          [Color.new(96, 30, 44), RED]
        when "update"
          [Color.new(92, 58, 24), ORANGE]
        when "missingdependency", "conflict"
          [Color.new(92, 58, 24), ORANGE]
        when "profile"
          [Color.new(54, 48, 112), PURPLE]
        when "library"
          [Color.new(36, 72, 92), BLUE]
        when "featured"
          [Color.new(104, 76, 16), YELLOW]
        when "specialentry", "special"
          [Color.new(64, 42, 112), PURPLE]
        when "disabled"
          [Color.new(28, 34, 48), DIM]
        else
          [TAG_BG, GRAY]
        end
      end

      def browser_update_available?(row)
        return false unless row && row["installed"]
        if core_entry_row?(row)
          latest = row["latest_version"].to_s
          return !latest.empty? && compare_versions(core_installed_version, latest) < 0
        end
        if row["kind"] == "mod"
          installed = installed_mod_version(row["id"])
          latest = row["latest_version"].to_s
          return !installed.empty? && !latest.empty? && compare_versions(installed, latest) < 0
        end
        return false unless defined?(Reloaded::Profiles)
        profile = Reloaded::Profiles.list.find do |item|
          item["id"].to_s.downcase == row["id"].to_s.downcase ||
            item["name"].to_s.downcase == row["name"].to_s.downcase
        end
        profile && !profile["version"].to_s.empty? && !row["version"].to_s.empty? &&
          compare_versions(profile["version"], row["version"]) < 0
      rescue
        false
      end

      def draw_footer
        draw_footer_buttons(@footer_sprite.bitmap, footer_buttons)
      end

      def handle_input
        handle_mouse
        return handle_search_input if @search_active

        if Input.trigger?(Input::B) || InputSupport.mouse_right_trigger?
          if @showing_changelog
            close_changelog
            return
          end
          request_exit
          return
        end
        if menu_trigger?
          open_action_menu(selected_row)
          return
        end
        if browser_page_trigger?
          toggle_browser_page
          return
        end
        if special_trigger?
          open_filter_menu
          return
        end
        @focus == :list ? handle_list_input : handle_footer_input
      end

      def handle_mouse
        controller_scroll = InputSupport.controller_scroll_delta
        if controller_scroll != 0
          @description_scroll = [@description_scroll - controller_scroll, 0].max
          draw_right
        end
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
            if old_selected != @selected_index
              @description_scroll = 0
              @showing_changelog = false
            end
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
          @showing_changelog = false
          ensure_visible
          changed = true
        elsif Input.repeat?(Input::DOWN) && !@rows.empty?
          @selected_index = (@selected_index + 1) % @rows.length
          @description_scroll = 0
          @showing_changelog = false
          ensure_visible
          changed = true
        elsif Input.repeat?(Input::LEFT) && !@rows.empty?
          @selected_index = (@selected_index - 4 + @rows.length) % @rows.length
          @description_scroll = 0
          @showing_changelog = false
          ensure_visible
          changed = true
        elsif Input.repeat?(Input::RIGHT) && !@rows.empty?
          @selected_index = (@selected_index + 4) % @rows.length
          @description_scroll = 0
          @showing_changelog = false
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

      def execute_footer(index)
        case footer_buttons[index].to_s
        when "Back" then request_exit
        end
      end

      def open_action_menu(row)
        return unless row
        if row["kind"] == "profile"
          choices = ["Import Profile", "Import & Enable Mods", "Back"]
          choice = show_message(row["name"], choices)
          case choices[choice]
          when "Import Profile" then import_profile(row, false)
          when "Import & Enable Mods" then import_profile(row, true)
          end
        elsif spritepack_entry_row?(row)
          open_spritepack_menu
        elsif core_entry_row?(row)
          choices = browser_update_available?(row) ? ["Update", "Update Status"] : ["Check Updates"]
          choices << "Patch Notes" unless changelog_url(row).empty?
          choices << "File A Bug Report"
          choices << "Open Mods Folder"
          choices << "Back"
          choice = show_message(row["name"], choices)
          case choices[choice]
          when "Update" then update_core_installation(row)
          when "Update Status", "Check Updates" then show_core_update_status(row)
          when "Patch Notes" then open_browser_patch_notes_menu(row)
          when "File A Bug Report" then file_bug_report
          when "Open Mods Folder" then open_mods_folder
          end
        else
          choices = ["Download", "Download & Enable", "Versions", "Back"]
          choice = show_message(row["name"], choices)
          case choices[choice]
          when "Download" then download_mod(row, false)
          when "Download & Enable" then download_mod(row, true)
          when "Versions" then choose_version(row)
          end
        end
      end

      def quick_download(row)
        return unless row
        return open_spritepack_menu if spritepack_entry_row?(row)
        return show_core_update_status(row) if core_entry_row?(row)
        row["kind"] == "profile" ? import_profile(row, true) : download_mod(row, false)
      end

      def open_browser_patch_notes_menu(row)
        choices = ["View", "Open", "Back"]
        choice = show_message("Patch Notes", choices)
        case choices[choice]
        when "View" then view_changelog(row)
        when "Open" then open_core_patch_notes
        end
      end

      def download_mod(row, enable, version = nil)
        unless defined?(Reloaded::ModBrowser)
          show_message("Mod Browser is not available.")
          return
        end
        result = if version
                   download_selected_version(row, enable, version)
                 else
                   Reloaded::ModBrowser.download_mods([row["id"]], enable: enable)
        end
        failed = Array(result[:failed])
        return if result[:canceled]
        if failed.empty?
          mark_restart_required("downloaded #{row["id"]}") if enable
          Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
          refresh_rows
          draw_all
          show_message(enable ? "Downloaded and enabled." : "Downloaded.")
          return true
        else
          show_message(download_failure_message(result))
          return false
        end
      rescue Exception => e
        Reloaded::Log.exception("Browser download failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Download failed:\n#{e.message}")
        false
      end

      def download_selected_version(row, enable, version)
        selected = Array(row["versions"]).find { |entry| entry["version"].to_s == version.to_s }
        return { :installed => [], :failed => [row["id"]], :missing => [] } unless selected
        installed_version = installed_mod_version(row["id"])
        if !installed_version.empty? && compare_versions(selected["version"], installed_version) < 0
          choice = show_message(
            "Install older version?\nInstalled: #{installed_version}\nSelected: #{selected["version"]}",
            ["Install Older", "Back"],
            1
          )
          return { :installed => [], :failed => [], :missing => [], :canceled => true } unless choice == 0
        end
        item = row.dup
        item["version"] = selected["version"].to_s
        item["latest_version"] = selected["version"].to_s
        item["download_url"] = selected["download_url"].to_s
        item["dependencies"] = selected["dependencies"] if selected.has_key?("dependencies")
        Reloaded::ModBrowser.download_mods([row["id"]], enable: enable, versions: { row["id"] => selected["version"].to_s })
      end

      def installed_mod_version(mod_id)
        return core_installed_version if mod_id.to_s == core_entry_id
        row = defined?(Reloaded::ModManager) ? Reloaded::ModManager.mod_row(mod_id) : nil
        row ? row[:version].to_s : ""
      rescue
        ""
      end

      def choose_version(row)
        versions = sorted_versions(Array(row["versions"]).select { |entry| !entry["version"].to_s.empty? })
        if versions.empty?
          show_message("No versions listed.")
          return
        end
        labels = versions.map { |entry| version_choice_label(row, entry) } + ["Back"]
        choice = show_message("Choose Version", labels)
        return if choice.nil? || choice >= versions.length
        selected = versions[choice]
        version = selected["version"].to_s
        action = show_message("Download v#{version}?", ["Download", "Download & Enable", "Back"])
        download_mod(row, action == 1, version) if action == 0 || action == 1
      end

      def version_choice_label(row, entry)
        version = entry["version"].to_s
        tags = []
        latest = row["latest_version"].to_s
        installed = installed_mod_version(row["id"])
        tags << "Latest" if !latest.empty? && version == latest
        tags << "Installed" if !installed.empty? && version == installed
        if !installed.empty? && !version.empty? && version != installed
          tags << "Newer" if compare_versions(version, installed) > 0
        end
        tags.empty? ? version : "#{version} (#{tags.join(", ")})"
      end

      def import_profile(row, enable_missing)
        unless defined?(Reloaded::ModBrowser)
          show_message("Mod Browser is not available.")
          return
        end
        result = Reloaded::ModBrowser.import_published_profile(row["id"], download_missing: true, enable_missing: enable_missing, activate: true)
        if result[:success]
          profile = result[:profile]
          mark_restart_required("imported profile #{profile["name"] rescue row["id"]}")
          Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
          refresh_rows
          draw_all
          show_message("Profile imported.")
        else
          show_message("Profile import failed.\n#{download_failure_message(result)}")
        end
      rescue Exception => e
        Reloaded::Log.exception("Published profile import failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Profile import failed:\n#{e.message}")
      end

      def open_filter_menu
        choices = ["All", "Mods", "Profiles", "Installed", "Available"]
        choice = show_message("Filter Browser", choices)
        @filter = case choices[choice]
                  when "Mods" then :mods
                  when "Profiles" then :profiles
                  when "Installed" then :installed
                  when "Available" then :available
                  else :all
                  end
        @selected_index = 0
        @scroll = 0
        refresh_rows
        draw_all
      end

      def browser_page_trigger?
        (Input.const_defined?(:L) && Input.trigger?(Input::L)) ||
          (Input.const_defined?(:R) && Input.trigger?(Input::R))
      rescue
        false
      end

      def toggle_browser_page
        @filter = @filter == :profiles ? :mods : :profiles
        @selected_index = 0
        @scroll = 0
        @description_scroll = 0
        refresh_rows
        draw_all
      end

      def browser_hint_text
        return "Back (B) Scroll (Mouse Wheel)" if @showing_changelog
        "Confirm (C) Back (B) Menu (A) Filter (Z) Switch (L/R)"
      end

      def browser_sync_status_text
        defined?(Reloaded::ModBrowser) ? Reloaded::ModBrowser.sync_status_text : "Sync unavailable"
      rescue
        "Sync unknown"
      end

      def changelog_url(row)
        return "" unless row
        primary = row["changelogurl"].to_s.strip
        return primary unless primary.empty?
        row["changelog_url"].to_s.strip
      end

      def view_changelog(row)
        url = changelog_url(row)
        if url.empty?
          show_message("No changelog URL is configured.")
          return
        end
        text = fetch_changelog_text(url)
        if text.to_s.strip.empty?
          show_message("Changelog is empty or unavailable.")
          return
        end
        @showing_changelog = true
        @changelog_row_id = row["id"].to_s
        @changelog_text = text.to_s
        @description_scroll = 0
        draw_right
      rescue Exception => e
        Reloaded::Log.exception("Browser changelog failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not load changelog:\n#{e.message}")
      end

      def close_changelog
        @showing_changelog = false
        @changelog_text = ""
        @changelog_row_id = nil
        @description_scroll = 0
        draw_right
      end

      def fetch_changelog_text(url)
        fetch_changelog_text_value(url)
      end

      def request_exit
        @running = false
      end

      def mark_restart_required(reason)
        return if @restart_required
        @restart_required = true
        Reloaded::Log.info("Restart required: #{reason}", :mods) if defined?(Reloaded::Log)
        draw_title rescue nil
        draw_right rescue nil
      end

      def browser_row_color(row, selected)
        return WHITE if selected
        return YELLOW if special_entry_priority(row) == 0
        return PURPLE if special_entry_priority(row) == 1
        return GREEN if row["installed"]
        row["kind"] == "profile" ? PURPLE : GRAY
      end

      def filter_label
        case @filter
        when :mods then "Mods"
        when :profiles then "Profiles"
        when :installed then "Installed"
        when :available then "Available"
        else "All"
        end
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
        @showing_changelog = false
        @changelog_text = ""
        @restart_required = false
        @load_order_mode = false
        @held_load_order_id = nil
        @load_order_changed = false
        @load_order_previous_filter = :all
        @load_order_previous_search = ""
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
        Reloaded::ModBrowser.refresh(fetch_remote: true) if defined?(Reloaded::ModBrowser)
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
        rows = installed_rows
        if @load_order_mode
          rows = ordered_for_load_mode(rows)
        else
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
          rows = rows.sort_by { |row| [special_entry_priority(row), row[:name].to_s.downcase, row[:id].to_s] }
        end
        @rows = rows
        @selected_index = [[@selected_index, 0].max, [@rows.length - 1, 0].max].min
        ensure_visible
      end

      def installed_rows
        rows = Reloaded::ModManager.mod_rows rescue []
        if defined?(Reloaded::ModManager) && Reloaded::ModManager.respond_to?(:core_row)
          protected_rows = [Reloaded::ModManager.core_row]
          spritepack = spritepack_installed_row
          protected_rows << spritepack if spritepack
          rows = protected_rows + rows
        end
        rows
      rescue
        []
      end

      def spritepack_installed_row
        entry = defined?(Reloaded::ModBrowser) ? Reloaded::ModBrowser.spritepack_entry : nil
        {
          :id => spritepack_entry_id,
          :game => "hoenn",
          :name => entry ? entry["name"].to_s : "Spritepacks",
          :version => entry ? entry["latest_version"].to_s : "",
          :authors => entry ? Array(entry["authors"]) : ["Hoenn Reloaded"],
          :description => entry ? entry["description"].to_s : "Download Hoenn Reloaded spritepacks.",
          :source => :reloaded_spritepacks,
          :folder_path => Reloaded::ModBrowser::SPRITEPACK_CONFIG_PATH,
          :manifest_path => Reloaded::ModBrowser::SPRITEPACK_CONFIG_PATH,
          :enabled => true,
          :profile_enabled => true,
          :profile_disabled => false,
          :loaded => true,
          :status => :ok,
          :tags => entry ? Array(entry["tags"]) : ["Spritepacks"],
          :system_tags => [],
          :dependencies => [],
          :incompatibilities => [],
          :warnings => [],
          :errors => [],
          :scripts_loaded => 0,
          :settings_count => 0,
          :has_settings => false,
          :moddev => false,
          :featured => true,
          :special_entry => true,
          :virtual => true,
          :protected => true,
          :spritepack_entry => true
        }
      rescue
        {
          :id => spritepack_entry_id,
          :game => "hoenn",
          :name => "Spritepacks",
          :version => "",
          :authors => ["Hoenn Reloaded"],
          :description => "Download Hoenn Reloaded spritepacks.",
          :source => :reloaded_spritepacks,
          :folder_path => nil,
          :manifest_path => nil,
          :enabled => true,
          :profile_enabled => true,
          :profile_disabled => false,
          :loaded => true,
          :status => :ok,
          :tags => ["Spritepacks"],
          :system_tags => [],
          :dependencies => [],
          :incompatibilities => [],
          :warnings => [],
          :errors => [],
          :scripts_loaded => 0,
          :settings_count => 0,
          :has_settings => false,
          :moddev => false,
          :featured => true,
          :special_entry => true,
          :virtual => true,
          :protected => true,
          :spritepack_entry => true
        }
      end

      def ordered_for_load_mode(rows)
        rows = Array(rows).reject { |row| protected_entry_row?(row) }
        order = defined?(Reloaded::Profiles) ? Reloaded::Profiles.load_order : []
        order = Array(order).map(&:to_s)
        order_index = {}
        order.each_with_index { |id, index| order_index[id] = index }
        rows.sort_by do |row|
          index = order_index[row[:id].to_s] || 99_999
          [index, row[:name].to_s.downcase, row[:id].to_s]
        end
      rescue
        rows
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
        bitmap.font.size = 12 rescue nil
        pbDrawTextPositions(bitmap, [[@rows.length.to_s, SCREEN_W - MARGIN - 3, 0, 2, GRAY, Color.new(0, 0, 0, 0)]])
        pbDrawTextPositions(bitmap, [[browser_sync_status_text, SCREEN_W - MARGIN - 23, 13, 2, DIM, Color.new(0, 0, 0, 0)]])
        bitmap.font.size = 12 rescue nil
        title_text = @load_order_mode ? "Load Order" : "Filter (Z): #{filter_label}"
        draw_plain_text(bitmap, 176, 9, 168, 14, title_text, BLUE, 1)
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
                         "Search (Click)"
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
          held = @held_load_order_id && @held_load_order_id == row[:id]
          fill = row[:enabled] ? ROW_NORMAL : ROW_DISABLED
          draw_rounded_rect(bitmap, 6, y, LEFT_W - 12, ROW_H - 3, fill)
          priority = special_entry_priority(row)
          if selected || held
            selection_fill = priority == 0 ? Color.new(104, 76, 16) : nil
            draw_selection_box(bitmap, 6, y - 1, LEFT_W - 12, ROW_H - 2, selection_fill)
          end
          bitmap.fill_rect(13, y + 7, 6, 6, row[:enabled] ? GREEN : RED)
          prefix = row[:moddev] ? "[MD] " : ""
          prefix = "* " + prefix if held
          bitmap.font.size = 18 rescue nil
          name = trim_text(bitmap, prefix + row[:name].to_s, LEFT_W - 44)
          color = if selected || held
                    WHITE
                  elsif priority == 0
                    YELLOW
                  elsif priority == 1
                    PURPLE
                  else
                    text_color_for_status(row[:status])
                  end
          draw_plain_text(bitmap, 25, y - 6, LEFT_W - 38, ROW_H, name, color)
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
          draw_panel_hint(bitmap, panel_hint_text, RIGHT_W, CONTENT_H, 90)
          return
        end

        if @showing_changelog
          draw_installed_changelog_panel(bitmap, row)
          return
        end

        x = 12
        y = 29
        apply_ui_font(bitmap)
        bitmap.font.size = 14
        authors = Array(row[:authors]).join(", ")
        pbDrawTextPositions(bitmap, [["by #{authors.empty? ? 'Unknown' : authors}", x, y - 7, 0, GRAY, Color.new(0, 0, 0, 0)]])
        y += 16
        if spritepack_entry_row?(row)
          y = draw_spritepack_status_rows(bitmap, x, y)
        else
          pbDrawTextPositions(bitmap, [["v#{row[:version]}", x, y - 9, 0, GRAY, Color.new(0, 0, 0, 0)]])
          y += 10
          enabled_label = row[:enabled] ? "Enabled" : "Disabled"
          enabled_color = row[:enabled] ? GREEN : RED
          pbDrawTextPositions(bitmap, [[enabled_label, x, y - 5, 0, enabled_color, Color.new(0, 0, 0, 0)]])
          y += 14
        end

        y = draw_tags(bitmap, x, y + 2, row)
        bitmap.fill_rect(x, y, RIGHT_W - 24, 1, PANEL_BORDER)
        y += 6
        bitmap.font.size = 16 rescue nil
        pbDrawTextPositions(bitmap, [["Description", x, y - 10, 0, BLUE, Color.new(0, 0, 0, 0)]])
        y += 19

        bitmap.font.size = 15 rescue nil
        desc_lines = wrapped_lines(bitmap, row[:description], RIGHT_W - 34)
        desc_top = y - 10
        y = desc_top
        hint_y = CONTENT_H - 76
        max_visible = [(hint_y - desc_top) / 17, 1].max
        @description_scroll = [[@description_scroll, 0].max, [desc_lines.length - max_visible, 0].max].min
        desc_lines.each_with_index do |line, index|
          next if index < @description_scroll
          break if y + 17 > hint_y
          pbDrawTextPositions(bitmap, [[line, x, y, 0, GRAY, Color.new(0, 0, 0, 0)]])
          y += 17
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
        draw_panel_hint(bitmap, panel_hint_text, RIGHT_W, CONTENT_H, 90)
      end

      def draw_spritepack_status_rows(bitmap, x, y)
        full = defined?(Reloaded::ModBrowser) ? Reloaded::ModBrowser.spritepack_full_file : nil
        latest = defined?(Reloaded::ModBrowser) ? Reloaded::ModBrowser.spritepack_latest_file : nil
        full_installed = spritepack_file_installed?(full)
        latest_installed = spritepack_file_installed?(latest)
        pbDrawTextPositions(bitmap, [["Latest Full - #{full_installed ? 'Installed' : 'Not Installed'}", x, y - 9, 0, full_installed ? GREEN : RED, Color.new(0, 0, 0, 0)]])
        y += 10
        pbDrawTextPositions(bitmap, [["Latest Pack - #{latest_installed ? 'Installed' : 'Not Installed'}", x, y - 5, 0, latest_installed ? GREEN : RED, Color.new(0, 0, 0, 0)]])
        y + 14
      rescue
        pbDrawTextPositions(bitmap, [["Latest Full - Not Installed", x, y - 9, 0, RED, Color.new(0, 0, 0, 0)]])
        y += 10
        pbDrawTextPositions(bitmap, [["Latest Pack - Not Installed", x, y - 5, 0, RED, Color.new(0, 0, 0, 0)]])
        y + 14
      end

      def spritepack_file_installed?(file)
        return false unless file && defined?(Reloaded::ModBrowser)
        Reloaded::ModBrowser.spritepack_installed?(file)
      rescue
        false
      end

      def draw_tags(bitmap, x, y, row)
        tags = admin_tags_for(row) + (update_available?(row) ? ["Update"] : []) + Array(row[:system_tags]) + Array(row[:tags])
        tags = tags.reject { |tag| tag_key(tag) == "disabled" }.uniq
        bitmap.font.size = 12 rescue nil
        rows_used = 1
        tags.each do |tag|
          label = tag_label(tag)
          width = bitmap.text_size(label).width + 8
          if x + width > RIGHT_W - 12
            break if rows_used >= 2
            x = 12
            y += 18
            rows_used += 1
          end
          bg, color = tag_style(label)
          draw_rounded_rect(bitmap, x, y, width, 16, bg)
          pbDrawTextPositions(bitmap, [[label, x + 4, y - 5, 0, color, Color.new(0, 0, 0, 0)]])
          x += width + 4
        end
        y + 19
      end

      def tag_style(tag)
        key = tag_key(tag)
        case key
        when "outdated", "broken", "invalid"
          [Color.new(96, 30, 44), RED]
        when "update"
          [Color.new(92, 58, 24), ORANGE]
        when "missingdependency", "conflict"
          [Color.new(92, 58, 24), ORANGE]
        when "profile"
          [Color.new(54, 48, 112), PURPLE]
        when "library"
          [Color.new(36, 72, 92), BLUE]
        when "featured"
          [Color.new(104, 76, 16), YELLOW]
        when "specialentry", "special"
          [Color.new(64, 42, 112), PURPLE]
        when "disabled"
          [Color.new(28, 34, 48), DIM]
        when "moddev"
          [Color.new(82, 54, 28), ORANGE]
        else
          [TAG_BG, GRAY]
        end
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
          bitmap.font.size = 16 rescue nil
          draw_plain_text(bitmap, x, y, RIGHT_W - 24, 18, "Dependencies: #{deps.length}#{bad.empty? ? '' : " (#{bad.length} issue(s))"}", BLUE)
          y += 18
        end
        unless conflicts.empty?
          bitmap.font.size = 16 rescue nil
          pbDrawShadowText(bitmap, x, y, RIGHT_W - 24, 18, "Conflicts: #{conflicts.length}", RED, SHADOW)
        end
      end

      def draw_installed_changelog_panel(bitmap, row)
        x = 12
        y = 31
        apply_ui_font(bitmap)
        bitmap.font.size = 16 rescue nil
        pbDrawTextPositions(bitmap, [["Changelog", x, y - 5, 0, BLUE, Color.new(0, 0, 0, 0)]])
        y += 21
        bitmap.fill_rect(x, y - 3, RIGHT_W - 24, 1, PANEL_LINE)
        y += 6
        bitmap.font.size = 15 rescue nil
        lines = wrapped_lines(bitmap, @changelog_text.to_s, RIGHT_W - 34)
        lines = ["No changelog text found."] if lines.empty?
        top = y
        hint_y = CONTENT_H - 36
        max_visible = [(hint_y - top) / 17, 1].max
        @description_scroll = [[@description_scroll, 0].max, [lines.length - max_visible, 0].max].min
        lines.each_with_index do |line, index|
          next if index < @description_scroll
          break if y + 17 > hint_y
          pbDrawTextPositions(bitmap, [[line, x, y, 0, GRAY, Color.new(0, 0, 0, 0)]])
          y += 17
        end
        if lines.length > max_visible
          bar_x = RIGHT_W - 14
          bar_y = top
          bar_h = hint_y - top
          bitmap.fill_rect(bar_x, bar_y, 8, bar_h, Color.new(0, 0, 0, 60))
          max_scroll = [lines.length - max_visible, 1].max
          handle_h = [[bar_h * max_visible / lines.length, 14].max, bar_h].min
          handle_y = bar_y + (bar_h - handle_h) * @description_scroll.to_f / max_scroll
          bitmap.fill_rect(bar_x + 1, handle_y.to_i, 6, handle_h, GRAY)
        end
        draw_panel_hint(bitmap, panel_hint_text, RIGHT_W, CONTENT_H, 90)
      end

      def draw_footer
        draw_footer_buttons(@footer_sprite.bitmap, footer_buttons)
      end

      def handle_input
        if @load_order_mode
          handle_load_order_input
          return
        end

        handle_mouse
        return handle_search_input if @search_active

        if Input.trigger?(Input::B) || InputSupport.mouse_right_trigger?
          if @showing_changelog
            close_installed_changelog
            return
          end
          request_exit
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
        controller_scroll = InputSupport.controller_scroll_delta
        if controller_scroll != 0
          @description_scroll = [@description_scroll - controller_scroll, 0].max
          draw_right
        end
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
            if old_selected != @selected_index
              @description_scroll = 0
              @showing_changelog = false
            end
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
          @showing_changelog = false
          ensure_visible
          changed = true
        elsif Input.repeat?(Input::DOWN) && !@rows.empty?
          @selected_index = (@selected_index + 1) % @rows.length
          @description_scroll = 0
          @showing_changelog = false
          ensure_visible
          changed = true
        elsif Input.repeat?(Input::LEFT) && !@rows.empty?
          @selected_index = (@selected_index - 4 + @rows.length) % @rows.length
          @description_scroll = 0
          @showing_changelog = false
          ensure_visible
          changed = true
        elsif Input.repeat?(Input::RIGHT) && !@rows.empty?
          @selected_index = (@selected_index + 4) % @rows.length
          @description_scroll = 0
          @showing_changelog = false
          ensure_visible
          changed = true
        end
        open_action_menu(selected_row) if Input.trigger?(Input::C) && selected_row
        if changed
          draw_left
          draw_right
        end
      end

      def handle_load_order_input
        @focus = :list
        if Input.trigger?(Input::B) || InputSupport.mouse_right_trigger?
          exit_load_order_mode
          return
        end
        if menu_trigger? || Input.trigger?(Input::C)
          toggle_held_load_order_mod
          return
        end

        changed = false
        if Input.repeat?(Input::UP) && !@rows.empty?
          if @held_load_order_id
            move_held_load_order_mod(-1)
            return
          else
            @selected_index = (@selected_index - 1 + @rows.length) % @rows.length
            changed = true
          end
        elsif Input.repeat?(Input::DOWN) && !@rows.empty?
          if @held_load_order_id
            move_held_load_order_mod(1)
            return
          else
            @selected_index = (@selected_index + 1) % @rows.length
            changed = true
          end
        end
        if changed
          @description_scroll = 0
          ensure_visible
          draw_left
          draw_right
        end
      end

      def enter_load_order_mode(row = nil)
        @load_order_previous_filter = @filter
        @load_order_previous_search = @search_text.dup
        @load_order_mode = true
        @held_load_order_id = nil
        @load_order_changed = false
        @search_active = false
        @search_text = ""
        @filter = :all
        @focus = :list
        refresh_rows
        select_mod_id(row[:id]) if row
        draw_all
      end

      def exit_load_order_mode
        @held_load_order_id = nil
        @load_order_mode = false
        @filter = @load_order_previous_filter || :all
        @search_text = @load_order_previous_search.to_s
        refresh_rows
        draw_all
      end

      def toggle_held_load_order_mod
        row = selected_row
        return unless row
        if @held_load_order_id
          Reloaded::Log.info("Mod Manager UI placed #{row[:id]} in load order", :mods) if defined?(Reloaded::Log)
          @held_load_order_id = nil
        else
          added = ensure_mod_in_load_order(row[:id])
          @held_load_order_id = row[:id]
          select_mod_id(@held_load_order_id)
          mark_restart_required("changed mod load order") if added
        end
        draw_all
      end

      def ensure_mod_in_load_order(mod_id)
        return unless defined?(Reloaded::Profiles)
        order = Reloaded::Profiles.load_order
        return false if order.include?(mod_id.to_s)
        Reloaded::Profiles.set_load_order(order + [mod_id.to_s])
        true
      end

      def move_held_load_order_mod(delta)
        return unless @held_load_order_id && defined?(Reloaded::Profiles)
        before = (Reloaded::Profiles.load_order.index(@held_load_order_id) || -1)
        Reloaded::Profiles.move_mod(@held_load_order_id, delta)
        after = (Reloaded::Profiles.load_order.index(@held_load_order_id) || -1)
        return if before == after
        @load_order_changed = true
        Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
        refresh_rows
        select_mod_id(@held_load_order_id)
        mark_restart_required("changed mod load order")
        draw_all
      end

      def select_mod_id(mod_id)
        index = @rows.index { |row| row[:id].to_s == mod_id.to_s }
        return unless index
        @selected_index = index
        @description_scroll = 0
        ensure_visible
      end

      def panel_hint_text
        return "Back (B) Scroll (Mouse Wheel)" if @showing_changelog
        if @load_order_mode
          return @held_load_order_id ? "Place (A) Back (B) Move (Up/Down)" : "Pick Up (A) Back (B) Move (Up/Down)"
        end
        "Confirm (C) Back (B) Menu (A) Filter (Z)"
      end

      def browser_sync_status_text
        defined?(Reloaded::ModBrowser) ? Reloaded::ModBrowser.sync_status_text : "Sync unavailable"
      rescue
        "Sync unknown"
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
        if spritepack_entry_row?(row)
          open_spritepack_menu
          return
        end
        if protected_entry_row?(row)
          choices = update_available?(row) ? ["Update", "Update Status"] : ["Check Updates"]
          choices << "Patch Notes" unless installed_changelog_url(row).empty?
          choices << "File A Bug Report"
          choices << "Open Mods Folder"
          choices << "Back"
          choice = show_message(row[:name], choices)
          case choices[choice]
          when "Update" then update_core_installation(row)
          when "Update Status", "Check Updates" then show_core_update_status(row)
          when "Patch Notes" then open_installed_patch_notes_menu(row)
          when "File A Bug Report" then file_bug_report
          when "Open Mods Folder" then open_mods_folder
          end
          return
        end
        enabled = row[:profile_enabled]
        toggle_label = enabled ? "Disable" : "Enable"
        choices = [toggle_label]
        choices << "Update" if update_available?(row)
        choices << "View Changelog" unless installed_changelog_url(row).empty?
        choices << "Settings" if mod_settings_available?(row)
        choices += ["Dependencies", "Conflicts", "Uninstall"]
        choice = show_message(row[:name], choices)
        case choices[choice]
        when "Enable"
          enable_mod(row)
        when "Disable"
          disable_mod(row)
        when "Update"
          update_installed_mod(row)
        when "View Changelog"
          view_installed_changelog(row)
        when "Settings"
          open_mod_settings(row)
        when "Dependencies"
          show_dependency_details(row)
        when "Conflicts"
          show_conflict_details(row)
        when "Uninstall"
          uninstall_mod(row)
        end
      end

      def open_installed_patch_notes_menu(row)
        choices = ["View", "Open", "Back"]
        choice = show_message("Patch Notes", choices)
        case choices[choice]
        when "View" then view_installed_changelog(row)
        when "Open" then open_core_patch_notes
        end
      end

      def mod_settings_available?(row)
        row && defined?(Reloaded::ModSettings) && Reloaded::ModSettings.has_settings?(row[:id])
      rescue
        false
      end

      def open_mod_settings(row)
        unless defined?(Reloaded::ModSettingsUI)
          show_message("Mod Settings UI is not available.")
          return
        end
        restart_required = Reloaded::ModSettingsUI.open(row[:id])
        mark_restart_required("changed settings for #{row[:id]}") if restart_required
        Reloaded::ModSettings.refresh if defined?(Reloaded::ModSettings)
        reload_after_profile_change
      rescue Exception => e
        Reloaded::Log.exception("Could not open mod settings for #{row[:id]}", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not open mod settings.")
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

      def update_installed_mod(row)
        unless defined?(Reloaded::ModBrowser)
          show_message("Mod Browser is not available.")
          return
        end
        if row[:source] == :moddev
          show_message("ModDev mods are not updated here.")
          return
        end
        Reloaded::ModBrowser.refresh(fetch_remote: true)
        entry = Reloaded::ModBrowser.entry(row[:id])
        unless entry
          show_message("No browser entry found for #{row[:name]}.")
          return
        end
        latest = entry["latest_version"].to_s
        if latest.empty? || compare_versions(row[:version], latest) >= 0
          show_message("#{row[:name]} is already up to date.")
          return
        end
        result = Reloaded::ModBrowser.download_mods([row[:id]], enable: row[:profile_enabled])
        failed = Array(result[:failed])
        if failed.empty?
          Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
          mark_restart_required("updated #{row[:id]}")
          reload_after_profile_change
          show_message("Updated to v#{latest}.")
        else
          show_message(download_failure_message(result))
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to update #{row[:id]}", e, channel: :mods) if defined?(Reloaded::Log)
          show_message("Could not update mod:\n#{e.message}")
      end

      def installed_changelog_url(row)
        return "" unless row
        direct = row[:changelogurl].to_s.strip
        return direct unless direct.empty?
        local = installed_changelog_file(row)
        return local unless local.empty?
        entry = browser_entry_for_row(row)
        return "" unless entry
        primary = entry["changelogurl"].to_s.strip
        return primary unless primary.empty?
        entry["changelog_url"].to_s.strip
      rescue
        ""
      end

      def installed_changelog_file(row)
        folder = row[:folder_path].to_s
        return "" if folder.empty?
        [
          "Changelog.txt",
          "changelog.txt",
          "CHANGELOG.txt",
          "CHANGELOG.md",
          "Changelog.md",
          "changelog.md"
        ].each do |file_name|
          path = File.join(folder, file_name)
          return path if File.exist?(path)
        end
        ""
      rescue
        ""
      end

      def view_installed_changelog(row)
        url = installed_changelog_url(row)
        if url.empty?
          show_message("No changelog URL or changelog file is configured.")
          return
        end
        text = fetch_installed_changelog_text(url)
        if text.to_s.strip.empty?
          show_message("Changelog is empty or unavailable.")
          return
        end
        @showing_changelog = true
        @changelog_text = text.to_s
        @description_scroll = 0
        draw_right
      rescue Exception => e
        Reloaded::Log.exception("Installed changelog failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not load changelog:\n#{e.message}")
      end

      def close_installed_changelog
        @showing_changelog = false
        @changelog_text = ""
        @description_scroll = 0
        draw_right
      end

      def fetch_installed_changelog_text(url)
        fetch_changelog_text_value(url)
      end

      def disable_mod(row)
        Reloaded::Profiles.disable_mod(row[:id]) if defined?(Reloaded::Profiles)
        Reloaded::Log.info("Mod Manager UI disabled #{row[:id]} in profile", :mods) if defined?(Reloaded::Log)
        mark_restart_required("disabled #{row[:id]}")
        reload_after_profile_change
      end

      def uninstall_mod(row)
        if row[:source] == :moddev
          show_message("ModDev folders are not uninstalled here.")
          return
        end
        path = safe_mod_folder_path(row)
        unless path
          show_message("Could not uninstall this mod safely.")
          return
        end
        choice = show_message("Uninstall #{row[:name]}?\nThis removes the mod folder.", ["Uninstall", "Cancel"], 1)
        return unless choice == 0
        Reloaded::Profiles.disable_mod(row[:id]) if defined?(Reloaded::Profiles)
        result = remove_mod_folder(path)
        if result == :soft
          Reloaded::Log.warning("Mod Manager UI soft-uninstalled #{row[:id]} at #{path}", :mods) if defined?(Reloaded::Log)
        elsif result == :staged
          Reloaded::Log.warning("Mod Manager UI staged #{row[:id]} for deletion from #{path}", :mods) if defined?(Reloaded::Log)
        else
          Reloaded::Log.info("Mod Manager UI uninstalled #{row[:id]} from #{path}", :mods) if defined?(Reloaded::Log)
        end
        mark_restart_required("uninstalled #{row[:id]}")
        reload_after_profile_change
        if result == :soft
          show_message("Uninstalled #{row[:name]}.\nThe old folder is locked and will be ignored until it can be cleaned up.")
        elsif result == :staged
          show_message("Uninstalled #{row[:name]}.\nThe old folder will be cleaned up later.")
        else
          show_message("Uninstalled #{row[:name]}.")
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to uninstall #{row[:id]}", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not uninstall mod:\n#{e.message}")
      end

      def safe_mod_folder_path(row)
        path = File.expand_path(row[:folder_path].to_s)
        mods_root = File.expand_path("./Mods")
        normalized_path = path.gsub("\\", "/")
        normalized_root = mods_root.gsub("\\", "/")
        return nil unless normalized_path.start_with?(normalized_root + "/")
        return nil if normalized_path == normalized_root
        path
      rescue
        nil
      end

      def remove_mod_folder(path)
        delete_error = nil
        stage_error = nil
        begin
          delete_tree(path)
        rescue Exception => e
          delete_error = e
        end
        return :deleted unless File.directory?(path)
        begin
          result = stage_pending_delete(path)
        rescue Exception => e
          stage_error = e
        end
        return result || :staged unless File.directory?(path)
        soft_uninstall_folder(path, delete_error, stage_error)
      end

      def delete_tree(path)
        return unless path && File.directory?(path)
        delete_tree_entries(path)
        clear_delete_attributes(path)
        Dir.rmdir(path)
      end

      def delete_tree_entries(path)
        directory_entries(path).each do |entry|
          if File.directory?(entry) && !File.symlink?(entry)
            delete_tree(entry)
          else
            clear_delete_attributes(entry)
            File.delete(entry)
          end
        end
      end

      def directory_entries(path)
        Dir[File.join(path, "*"), File::FNM_DOTMATCH].reject do |entry|
          base = File.basename(entry)
          base == "." || base == ".."
        end
      end

      def clear_delete_attributes(path)
        File.chmod(File.directory?(path) ? 0o777 : 0o666, path) rescue nil
      end

      def stage_pending_delete(path)
        pending_root = File.join(File.expand_path("./Mods"), ".ReloadedPendingDelete")
        Dir.mkdir(pending_root) unless Dir.exist?(pending_root)
        target = File.join(pending_root, "#{File.basename(path)}_#{Time.now.to_i}_#{rand(100000)}")
        File.rename(path, target)
        delete_tree(target) rescue nil
        File.directory?(target) ? :staged : :deleted
      end

      def soft_uninstall_folder(path, delete_error = nil, stage_error = nil)
        marker = File.join(path, soft_uninstall_marker_name)
        details = []
        details << "delete failed: #{delete_error.class}: #{delete_error.message}" if delete_error
        details << "stage failed: #{stage_error.class}: #{stage_error.message}" if stage_error
        File.open(marker, "w") do |file|
          file.puts("Soft-uninstalled by Hoenn Reloaded Mod Manager.")
          file.puts("The folder was locked while the game was running.")
          file.puts(details.join("\n")) unless details.empty?
        end
        clear_delete_attributes(marker)
        :soft
      end

      def soft_uninstall_marker_name
        if defined?(Reloaded::ModManager::UNINSTALLED_MARKER)
          Reloaded::ModManager::UNINSTALLED_MARKER
        else
          ".ReloadedUninstalled"
        end
      end

      def reload_after_profile_change
        Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
        return unless @left_sprite && @right_sprite && @title_sprite && @footer_sprite
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
          text = dep[:status_text].to_s
          text = dep[:status].to_s if text.empty?
          "#{dep[:name]} - #{text}"
        end
        show_message(lines.join("\n"))
      end

      def show_conflict_details(row)
        conflicts = Array(row[:incompatibilities])
        if conflicts.empty?
          show_message("No known conflicts.")
          return
        end
        colored = []
        active = conflicts.select { |entry| entry[:status] == :conflict }
        inactive = conflicts - active
        active.each do |entry|
          colored << { :text => "[CONFLICT] #{entry[:name]}  (#{entry[:id]})", :color => RED }
          colored << { :text => "  Installed and enabled with this mod.", :color => ORANGE }
        end
        inactive.each do |entry|
          colored << { :text => "[OK] #{entry[:name]}  (#{entry[:id]})", :color => GREEN }
          colored << { :text => "  Listed as incompatible, but not currently active.", :color => GRAY }
        end
        summary = "#{row[:name]} | #{active.length} Active | #{inactive.length} Inactive"
        show_colored_lines(summary, colored)
      end

      def execute_footer(index)
        case footer_buttons[index].to_s
        when "Profiles" then show_profile_menu
        when "Browser" then open_browser
        when "Tools" then open_tools_menu
        when "Back" then request_exit
        end
      end

      def show_profile_menu
        profile_restart_required = Scene_Profiles.new.main
        mark_restart_required("profile changes") if profile_restart_required
        reload_after_profile_change
      end

      def open_page_menu
        choices = ["Refresh", "Load Order", "Back"]
        choice = show_message("Mod Manager Menu", choices)
        case choices[choice]
        when "Refresh" then refresh_manager_data
        when "Load Order" then enter_load_order_mode(selected_row)
        when "Back" then request_exit
        end
      end

      def refresh_manager_data
        Reloaded::ModBrowser.refresh(fetch_remote: true) if defined?(Reloaded::ModBrowser)
        Reloaded::ModManager.refresh_metadata if defined?(Reloaded::ModManager)
        Reloaded::ModSettings.refresh if defined?(Reloaded::ModSettings)
        refresh_rows
        draw_all
        show_message("Mod Manager refreshed.")
      rescue Exception => e
        Reloaded::Log.exception("Mod Manager refresh failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Refresh failed:\n#{e.message}")
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

      def open_browser
        unless defined?(Reloaded::ModBrowser)
          show_message("Mod Browser is not available.")
          return
        end
        browser_restart_required = Scene_Browser.new.main
        mark_restart_required("browser changes") if browser_restart_required
        reload_after_profile_change
      end

      def open_tools_menu
        loop do
          choices = []
          choices << "Admin Tools" if admin_tools_enabled?
          choices += ["Template Generator", "Manifest Validator/Fixer", "Log Files", "Backup Mods", "Publish"]
          choices << "Back"
          choice = show_message("Tools", choices)
          selected = choices[choice]
          break if selected.nil? || selected == "Back"
          case selected
          when "Template Generator" then open_template_generator_menu
          when "Manifest Validator/Fixer" then open_manifest_tools_menu
          when "Log Files" then open_log_files_menu
          when "Backup Mods" then open_backup_mods_menu
          when "Publish" then open_publisher_tool
          when "Admin Tools" then open_admin_tools_menu
          end
        end
      end

      def open_admin_tools_standalone
        @viewport = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
        @viewport.z = 100_020
        @background = Sprite.new(@viewport)
        @background.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
        @background.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, BG)
        if admin_tools_enabled?
          open_admin_tools_menu
        else
          show_message("Admin Tools are not enabled.")
        end
      ensure
        @background.bitmap.dispose rescue nil
        @background.dispose rescue nil
        @background = nil
        @viewport.dispose rescue nil
        @viewport = nil
      end

      def modder_tools_available?
        defined?(Reloaded::ModderTools)
      end

      def tool_text(value)
        return Reloaded::ModderTools.display_text(value) if defined?(Reloaded::ModderTools)
        value.to_s
      rescue
        value.to_s
      end

      def tool_path(path)
        return Reloaded::ModderTools.display_path(path) if defined?(Reloaded::ModderTools)
        path.to_s
      rescue
        path.to_s
      end

      def open_log_files_menu
        unless modder_tools_available?
          show_message("Modder tools are not available.")
          return
        end
        choices = Reloaded::ModderTools.log_entries.map { |entry| "View #{entry[:label]}" }
        choices << "Clear Logs"
        choices << "Export"
        choices << "Back"
        choice = show_message("Log Files", choices)
        selected = choices[choice]
        if selected.to_s.start_with?("View ")
          label = selected.sub("View ", "")
          Reloaded::ModderTools.open_log(label)
          show_message("Opened #{label}.")
        elsif selected == "Clear Logs"
          clear_logs_menu
        elsif selected == "Export"
          open_log_export_menu
        end
      rescue Exception => e
        Reloaded::Log.exception("Log files tool failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Log tool failed:\n#{tool_text(e.message)}")
      end

      def clear_logs_menu
        return unless show_message("Clear all Reloaded log files?", ["Clear", "Back"], 1) == 0
        Reloaded::ModderTools.clear_logs
        show_message("Reloaded log files cleared.")
      rescue Exception => e
        Reloaded::Log.exception("Clear logs failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not clear logs:\n#{tool_text(e.message)}")
      end

      def open_log_export_menu
        choices = Reloaded::ModderTools.log_entries.map { |entry| entry[:label] }
        choices << "Back"
        choice = show_message("Export Log", choices)
        label = choices[choice]
        return if label.nil? || label == "Back"
        url = Reloaded::ModderTools.export_log(label)
        show_message("#{label} uploaded.\nURL copied to clipboard:\n#{url}")
      rescue Exception => e
        Reloaded::Log.exception("Log export failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not export log:\n#{tool_text(e.message)}")
      end

      def open_backup_mods_menu
        unless modder_tools_available?
          show_message("Modder tools are not available.")
          return
        end
        choices = ["All Mods", "Select Mods", "Back"]
        choice = show_message("Backup Mods", choices)
        case choices[choice]
        when "All Mods"
          archive = Reloaded::ModderTools.backup_all_mods
          show_message("Backup created:\n#{tool_path(archive)}")
        when "Select Mods"
          rows = Reloaded::ModderTools.backupable_mod_rows
          if rows.empty?
            show_message("No backupable mods found.")
            return
          end
          entries = rows.map do |row|
            label = "#{row[:name]} v#{row[:version]}"
            { :label => label, :value => row }
          end
          selected = checkbox_picker("Select Mods To Back Up", entries)
          return if selected.nil?
          if selected.empty?
            show_message("No mods selected.")
            return
          end
          archive = Reloaded::ModderTools.backup_mod_rows(selected, "SelectedMods")
          show_message("Backup created:\n#{tool_path(archive)}")
        end
      rescue Exception => e
        Reloaded::Log.exception("Backup mods tool failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Backup failed:\n#{tool_text(e.message)}")
      end

      def open_manifest_tools_menu
        unless modder_tools_available?
          show_message("Modder tools are not available.")
          return
        end
        choices = ["Validate Manifests", "Fix Selected Manifest", "Back"]
        choice = show_message("Manifest Tools", choices)
        case choices[choice]
        when "Validate Manifests" then validate_manifests_popup
        when "Fix Selected Manifest" then fix_manifest_popup
        end
      end

      def validate_manifests_popup
        results = Reloaded::ModderTools.validate_manifests
        if results.empty?
          show_message("No manifest folders found.")
          return
        end
        colored = results.map do |result|
          errors = Array(result[:errors])
          name = result[:name].to_s.empty? ? File.basename(result[:folder_path].to_s) : result[:name].to_s
          first_error = tool_text(errors.first.to_s)
          first_error = "#{first_error[0, 74]}..." if first_error.length > 77
          text = errors.empty? ? "[OK] #{name}" : "[ERROR] #{name}: #{first_error}"
          { :text => text, :color => errors.empty? ? GREEN : RED }
        end
        valid = results.count { |result| Array(result[:errors]).empty? }
        invalid = results.length - valid
        show_colored_lines("Manifest Validation: #{valid} OK / #{invalid} Error(s)", colored)
      rescue Exception => e
        Reloaded::Log.exception("Manifest validation failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Manifest validation failed:\n#{tool_text(e.message)}")
      end

      def fix_manifest_popup
        results = Reloaded::ModderTools.validate_manifests
        targets = results.select { |result| !Array(result[:errors]).empty? }
        if targets.empty?
          show_message("No manifest fixes needed.")
          return
        end
        labels = targets.map do |target|
          name = target[:name].to_s.empty? ? File.basename(target[:folder_path].to_s) : target[:name].to_s
          "#{name} (#{Array(target[:errors]).length})"
        end
        labels << "Back"
        choice = show_message("Fix Manifest", labels)
        target = targets[choice]
        return unless target
        fixed = Reloaded::ModderTools.fix_manifest(target)
        if Array(fixed[:errors]).empty?
          show_message("Manifest fixed:\n#{fixed[:name]}")
          reload_after_profile_change
        else
          show_message("Manifest was updated, but still has errors:\n#{tool_text(Array(fixed[:errors]).join("\n"))}")
        end
      rescue Exception => e
        Reloaded::Log.exception("Manifest fixer failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not fix manifest:\n#{tool_text(e.message)}")
      end

      def open_template_generator_menu
        unless modder_tools_available?
          show_message("Modder tools are not available.")
          return
        end
        choices = ["Mod", "Profile", "Back"]
        choice = show_message("Template Generator", choices)
        case choices[choice]
        when "Mod"
          name = text_input_popup("Mod Name", "New Mod", 48)
          return if name.nil? || name.strip.empty?
          folder = Reloaded::ModderTools.create_mod_template(name)
          show_message("Mod template created:\n#{tool_path(folder)}")
          reload_after_profile_change
        when "Profile"
          name = text_input_popup("Profile Name", "New Profile", 48)
          return if name.nil? || name.strip.empty?
          path = Reloaded::ModderTools.create_profile_template(name)
          show_message("Profile template created:\n#{tool_path(path)}")
          reload_after_profile_change
        end
      rescue Exception => e
        Reloaded::Log.exception("Template generator failed", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not create template:\n#{tool_text(e.message)}")
      end

      def admin_tools_enabled?
        File.exist?(admin_key_file) && (File.exist?(manager_editor_file) || File.exist?(mart_editor_file))
      rescue
        false
      end

      def open_admin_tools_menu
        choices = []
        choices << "Manager Editor" if File.exist?(manager_editor_file)
        choices << "Reloaded Mart Editor" if File.exist?(mart_editor_file)
        choices << "Back"
        choice = show_message("Admin Tools", choices)
        case choices[choice]
        when "Manager Editor" then open_manager_editor
        when "Reloaded Mart Editor" then open_mart_editor
        end
      end

      def open_manager_editor
        unless File.exist?(admin_key_file)
          show_message("Admin Tools are not enabled.")
          return
        end
        unless File.exist?(manager_editor_file)
          show_message("Manager Editor is not available.")
          return
        end
        unless File.exist?(manager_editor_index_file)
          show_message("Manager Editor index checkout is missing.\nOpen Publish once to sync the GitHub index.")
          return
        end
        load manager_editor_file
        Reloaded::ManagerEditor::Tool.open
        Reloaded::ModBrowser.refresh(fetch_remote: true) if defined?(Reloaded::ModBrowser)
        reload_after_profile_change
      rescue Exception => e
        raise if e.is_a?(SystemExit)
        Reloaded::Log.exception("Failed to open Manager Editor", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not open Manager Editor:\n#{e.message}")
      end

      def open_mart_editor
        unless File.exist?(admin_key_file)
          show_message("Admin Tools are not enabled.")
          return
        end
        unless File.exist?(mart_editor_file)
          show_message("Reloaded Mart Editor is not available.")
          return
        end
        load mart_editor_file
        Reloaded::MartEditor::Tool.open
        ReloadedMart::Source.load_for_open(blocking: false) if defined?(ReloadedMart::Source)
        reload_after_profile_change
      rescue Exception => e
        Reloaded::Log.exception("Failed to open Reloaded Mart Editor", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not open Reloaded Mart Editor:\n#{e.message}")
      end

      def admin_tools_dir
        File.expand_path("./Admin Tools")
      end

      def admin_key_file
        File.join(admin_tools_dir, "Admin.txt")
      end

      def manager_editor_file
        File.join(admin_tools_dir, "Manager Editor", "ManagerEditor.rb")
      end

      def mart_editor_file
        File.join(admin_tools_dir, "Reloaded Mart Editor", "ReloadedMartEditor.rb")
      end

      def manager_editor_index_file
        File.expand_path("./Modders Tools/_repo_cache/Hoenn-Reloaded-Mods/index.json")
      end

      def open_publisher_tool
        unless defined?(Reloaded::Publisher)
          show_message("Publisher tools are not available.")
          return
        end
        unless Reloaded::Publisher.available?
          show_message(Reloaded::Publisher.status_text)
          return
        end
        Reloaded::Publisher.launch_tool
        show_message("Publisher opened in a separate window.")
      rescue Exception => e
        Reloaded::Log.exception("Failed to open publisher", e, channel: :mods) if defined?(Reloaded::Log)
        show_message("Could not open publisher:\n#{e.message}")
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
