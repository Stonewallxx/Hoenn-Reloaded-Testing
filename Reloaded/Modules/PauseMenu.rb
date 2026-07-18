#======================================================
# Reloaded Pause Menu
# Author: Stonewall
#======================================================
# Optional Reloaded replacement for the base pause menu.
#
# Responsibilities:
#   - Register the Standard/Reloaded pause menu option.
#   - Store REPM layout and favorite state in the Reloaded save bucket.
#   - Draw the REPM grid, carousel, module icons, favorites, and row customizer.
#   - Register reference pause-menu modules.
#   - Route the normal pause-menu call to REPM when the Reloaded option is active.
#   - Keep Standard pause-menu behavior available through the Options menu.
#
#======================================================

module ReloadedPauseMenu
  FIXED_ROW_ORDER = [:RELOADEDMART, :TMVAULT, :POKEVIAL, :PC]
  CAROUSEL_ORDER  = [:POKEDEX, :POKEMON, :PC, :BAG, :POKENAV, :TRAINERINFO, :OUTFIT, :SAVE, :OPTIONS, :DEBUG, :TITLE, :RELOADEDMART, :TMVAULT, :POKEVIAL]
end
# Option/save-state adapter for the REPM scene.
module Reloaded
  module PauseMenuFeature
    class << self
      def install
        install_pokemon_system_settings
        register_option
        Reloaded::Log.info("Installed Reloaded Pause Menu module", :framework) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Reloaded Pause Menu module install failed", e, channel: :framework) if defined?(Reloaded::Log)
        false
      end

      def install_pokemon_system_settings
        return unless defined?(PokemonSystem)
        PokemonSystem.class_eval do
          def hr_pause_menu
            @hr_pause_menu.nil? ? 1 : @hr_pause_menu.to_i
          end

          def hr_pause_menu=(value)
            @hr_pause_menu = value.to_i
          end

          def reloaded_pause_menu
            hr_pause_menu
          end

          def reloaded_pause_menu=(value)
            self.hr_pause_menu = value
          end
        end
      end

      def register_option
        return unless defined?(Reloaded::Options) && Reloaded::Options.respond_to?(:register_category_option)
        Reloaded::Options.register_category_option("RELOADED", :pause_menu, priority: 10) do |_scene|
          [EnumOption.new(
            _INTL("Pause Menu"),
            [_INTL("Standard"), _INTL("Reloaded")],
            proc { ($PokemonSystem.hr_pause_menu rescue 1).to_i == 1 ? 1 : 0 },
            proc { |value| $PokemonSystem.hr_pause_menu = value.to_i if $PokemonSystem },
            _INTL("Standard: Uses the base game's pause menu.\nReloaded: Uses the Reloaded Pause Menu with modules, carousel, and favorites.")
          )]
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to register Reloaded Pause Menu option", e, channel: :options) if defined?(Reloaded::Log)
      end
    end
  end
end

Reloaded::PauseMenuFeature.install if defined?(Reloaded::PauseMenuFeature)

# Main REPM registry and scene implementation.
module ReloadedPauseMenu

  TRIGGER_BUTTON = Input.const_defined?(:Y) ? Input::Y : Input::BACK
  ICON_PATH      = "Reloaded/Graphics/ReloadedMenu/"
  GRID_COLS      = 4
  GRID_ROWS      = 2

  SCREEN_W   = 512
  SCREEN_H   = 384
  WHITE      = Color.new(255, 255, 255)
  MM_SHADOW  = Color.new(40,  35,  55)

  TITLE_Y   = 6
  TITLE_H   = 38


  GRID_PAD    = 12
  ROW_MOD_GAP = 16
  ROW_MOD_W   = 110
  ROW_MOD_H   = 110
  GRID_X      = GRID_PAD
  ROW_Y_START = TITLE_Y + TITLE_H + 4
  ROW_STRIDE  = ROW_MOD_H + 6


  CAR_BIG_W   = 95
  CAR_SIDE_W  = 70
  CAR_GAP     = 8
  CAR_CTR_X   = (SCREEN_W - CAR_BIG_W) / 2
  CAR_MID_XL  = CAR_CTR_X - CAR_SIDE_W - CAR_GAP
  CAR_MID_XR  = CAR_CTR_X + CAR_BIG_W  + CAR_GAP
  CAR_FAR_XL  = CAR_MID_XL - CAR_SIDE_W - CAR_GAP
  CAR_FAR_XR  = CAR_MID_XR + CAR_SIDE_W + CAR_GAP

  ARROW_W        = 18
  ARROW_H        = 30
  GRID_BOX_INSET = 8

  @modules      = []
  @last_car_sel = 0


  def self.register_module(key, label:, handler:, icon: nil, condition: nil, hidden: false, lock_reason: nil, status: nil, status_color: nil)
    return if @modules.any? { |m| m[:key] == key }
    @modules << {
      key: key, label: label, handler: handler, icon: icon,
      condition: condition, hidden: hidden, lock_reason: lock_reason, status: status, status_color: status_color
    }
  end

  def self.register(key, **kwargs)
    register_module(key, **kwargs)
  end

  def self._active_all
    @modules.select { |m| m[:condition].nil? || (m[:condition].call rescue false) }
  end


  def self.all_modules_with_state
    _apply_order(@modules, CAROUSEL_ORDER).filter_map do |m|
      active = m[:condition].nil? || (m[:condition].call rescue false)
      next if !active && m[:hidden]
      { mod: m, locked: !active }
    end
  end

  def self.active_modules
    _apply_order(_active_all, CAROUSEL_ORDER)
  end

  SAVE_SYSTEM = :reloaded_pause_menu

  def self.custom_row
    if defined?(Reloaded::SaveData)
      Array(Reloaded::SaveData.get(SAVE_SYSTEM, :custom_row, [], section: :systems)).map { |entry| entry.to_sym }
    else
      @fallback_custom_row ||= []
    end
  end

  def self.custom_row=(value)
    normalized = Array(value).map { |entry| entry.to_sym }
    if defined?(Reloaded::SaveData)
      Reloaded::SaveData.set(SAVE_SYSTEM, :custom_row, normalized.map { |entry| entry.to_s }, section: :systems)
    else
      @fallback_custom_row = normalized
    end
  end

  def self.favorite_module_key
    value = defined?(Reloaded::SaveData) ? Reloaded::SaveData.get(SAVE_SYSTEM, :favorite, nil, section: :systems) : @fallback_favorite
    value.nil? || value.to_s.empty? ? nil : value.to_sym
  end

  def self.favorite_module_key=(value)
    normalized = value.nil? ? nil : value.to_sym
    if defined?(Reloaded::SaveData)
      Reloaded::SaveData.set(SAVE_SYSTEM, :favorite, normalized ? normalized.to_s : nil, section: :systems)
    else
      @fallback_favorite = normalized
    end
  end

  def self.last_cursor_state
    if defined?(Reloaded::SaveData)
      Reloaded::SaveData.get(SAVE_SYSTEM, :last_cursor_state, {}, section: :systems)
    else
      @fallback_last_cursor_state ||= {}
    end
  rescue
    {}
  end

  def self.last_cursor_state=(value)
    state = value.is_a?(Hash) ? value : {}
    if defined?(Reloaded::SaveData)
      Reloaded::SaveData.set(SAVE_SYSTEM, :last_cursor_state, state, section: :systems)
    else
      @fallback_last_cursor_state = state
    end
  rescue
  end

  def self.lock_reason_for(mod)
    reason = mod[:lock_reason]
    reason = reason.call if reason.respond_to?(:call)
    reason = reason.to_s.strip
    reason.empty? ? "This module is currently locked." : reason
  rescue Exception
    "This module is currently locked."
  end

  def self.status_for(mod)
    status = mod[:status]
    status = status.call if status.respond_to?(:call)
    status.to_s.strip
  rescue Exception
    ""
  end

  def self.status_color_for(mod)
    color = mod[:status_color]
    color = color.call if color.respond_to?(:call)
    color || Color.new(120, 230, 150)
  rescue Exception
    Color.new(120, 230, 150)
  end

  def self.status_color_cache_key(mod)
    color = status_color_for(mod)
    return [color.red, color.green, color.blue, color.alpha] if color.respond_to?(:red)
    color.to_s
  rescue Exception
    "default"
  end


  def self.placeholder_icon
    @placeholder_icon ||= (Bitmap.new("Reloaded/Graphics/Pictures/Pokegear/icon_template") rescue nil)
  end

  def self.icon_for(mod)
    @icon_cache ||= {}
    key = [mod[:key], mod[:icon]]
    return @icon_cache[key] if @icon_cache.key?(key)
    path = mod[:icon] ? mod[:icon] : (ICON_PATH + mod[:key].to_s.upcase)
    @icon_cache[key] = (Bitmap.new(path) rescue nil)
  end
  def self.all_row_modules_with_state(r)
    if r == 1
      order = ReloadedPauseMenu.custom_row
    else
      order = FIXED_ROW_ORDER
    end
    order.map { |k| @modules.find { |m| m[:key] == k } }.compact.map do |m|
      active = m[:condition].nil? || (m[:condition].call rescue false)
      { mod: m, locked: !active }
    end
  end

  def self._apply_order(entries, order_keys)
    ordered   = order_keys.flat_map { |k| entries.select { |m| m[:key] == k } }
    remainder = entries.reject { |m| order_keys.include?(m[:key]) }
    ordered + remainder
  end

  def self.open
    ReloadedPartyPreloader.run rescue nil
    Scene.new.main
  end


  class Scene

    def main
      @all_entries  = ReloadedPauseMenu.all_modules_with_state
      @all_mods     = @all_entries.map { |e| e[:mod] }
      return if @all_mods.empty?

      @row_entries = [
        ReloadedPauseMenu.all_row_modules_with_state(0),
        ReloadedPauseMenu.all_row_modules_with_state(1)
      ]
      @row_mods = @row_entries.map { |r| r.map { |e| e[:mod] } }

      @car_sel     = ReloadedPauseMenu.instance_variable_get(:@last_car_sel).clamp(0, [@all_mods.length - 1, 0].max)
      @focus     = :carousel
      @row_state = [{ offset: 0, slot: 0 }, { offset: 0, slot: 0 }]
      restore_cursor_state
      @cursor_tick = 0
      @running   = true
      @pending   = nil
      @module_box_cache = {}

      @vp     = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
      @vp.z   = 99_000


      @grid_h = GRID_ROWS * ROW_STRIDE
      @car_y  = ROW_Y_START + @grid_h + 4
      @car_h  = SCREEN_H - @car_y - 2

      @title_spr   = BitmapSprite.new(SCREEN_W, TITLE_H, @vp)
      @title_spr.x = 0; @title_spr.y = TITLE_Y; @title_spr.z = 10

      @loc_spr     = BitmapSprite.new(110, 49, @vp)
      @loc_spr.z   = 20

      @economy_spr   = BitmapSprite.new(110, 49, @vp)
      @economy_spr.z = 20

      @grid_spr    = BitmapSprite.new(SCREEN_W, @grid_h + 4, @vp)
      @grid_spr.x  = 0; @grid_spr.y = ROW_Y_START; @grid_spr.z = 10

      @car_spr     = BitmapSprite.new(SCREEN_W, @car_h, @vp)
      @car_spr.x   = 0; @car_spr.y = @car_y; @car_spr.z = 10

      @hint_spr    = BitmapSprite.new(SCREEN_W, 18, @vp)
      @hint_spr.x  = 0; @hint_spr.y = SCREEN_H - 21; @hint_spr.z = 20

      @hover_id = nil

      draw_all

      loop do
        Graphics.update
        Input.update
        break unless @running

        @cursor_tick = (@cursor_tick + 1) % 40
        if @cursor_tick % 2 == 0
          case @focus
          when :carousel       then draw_carousel
          when :row0, :row1    then draw_grid
          end
        end
        handle_input
        handle_mouse
      end

      teardown

      ReloadedPauseMenu.instance_variable_set(:@last_car_sel, @car_sel)
      save_cursor_state

      @pending.call if @pending
      Input.update rescue nil
    end

    private

    def restore_cursor_state
      state = ReloadedPauseMenu.last_cursor_state
      state = {} unless state.is_a?(Hash)
      carousel_key = cursor_state_value(state, :carousel_key)
      if carousel_key
        index = @all_entries.index { |entry| entry[:mod][:key].to_s == carousel_key.to_s }
        @car_sel = index if index
      end
      rows = cursor_state_value(state, :rows)
      rows = {} unless rows.is_a?(Hash)
      restore_row_cursor(0, cursor_state_value(rows, 0) || cursor_state_value(rows, :row0))
      restore_row_cursor(1, cursor_state_value(rows, 1) || cursor_state_value(rows, :row1))
      focus = cursor_state_value(state, :focus).to_s
      @focus = valid_focus?(focus) ? focus.to_sym : :carousel
      @focus = :carousel if @focus == :row0 && @row_mods[0].empty?
      @focus = :carousel if @focus == :row1 && @row_mods[1].empty?
    rescue
      @focus = :carousel
    end

    def restore_row_cursor(row, row_state)
      entries = @row_entries[row] || []
      @row_state[row] = { offset: 0, slot: 0 } if entries.empty?
      return if entries.empty? || !row_state.is_a?(Hash)
      key = cursor_state_value(row_state, :key)
      index = entries.index { |entry| entry[:mod][:key].to_s == key.to_s } if key
      index ||= cursor_state_value(row_state, :index).to_i
      index = [[index, 0].max, entries.length - 1].min
      desired_slot = [[cursor_state_value(row_state, :slot).to_i, 0].max, GRID_COLS - 1].min
      max_offset = [entries.length - GRID_COLS, 0].max
      offset = [[index - desired_slot, 0].max, max_offset].min
      @row_state[row] = { offset: offset, slot: index - offset }
      clamp_slot(row)
    rescue
      @row_state[row] = { offset: 0, slot: 0 }
    end

    def save_cursor_state
      ReloadedPauseMenu.last_cursor_state = {
        "focus" => @focus.to_s,
        "carousel_key" => (@all_entries[@car_sel] && @all_entries[@car_sel][:mod][:key].to_s),
        "rows" => {
          "0" => row_cursor_state(0),
          "1" => row_cursor_state(1)
        }
      }
    rescue
    end

    def row_cursor_state(row)
      state = @row_state[row] || { offset: 0, slot: 0 }
      entries = @row_entries[row] || []
      index = state[:offset].to_i + state[:slot].to_i
      entry = entries[index]
      {
        "key" => (entry && entry[:mod][:key].to_s),
        "index" => index,
        "offset" => state[:offset].to_i,
        "slot" => state[:slot].to_i
      }
    end

    def cursor_state_value(hash, key)
      return nil unless hash.is_a?(Hash)
      hash[key] || hash[key.to_s]
    end

    def valid_focus?(value)
      ["carousel", "row0", "row1"].include?(value.to_s)
    end


    def teardown
      @module_box_cache.each_value { |b| b.dispose rescue nil } if @module_box_cache
      [@title_spr, @grid_spr, @car_spr, @loc_spr, @economy_spr, @hint_spr].compact.each do |s|
        s.bitmap.dispose rescue nil
        s.dispose rescue nil
      end
      @vp.dispose rescue nil
    end


    def draw_all
      draw_title
      draw_economy_box
      draw_location_box
      draw_hint
      draw_grid
      draw_carousel
    end

    def draw_title
      b = @title_spr.bitmap; b.clear
      pbSetSmallFont(b); b.font.size = 30; b.font.bold = true
      pbDrawShadowText(b, 0, 0, SCREEN_W, TITLE_H, "RELOADED MENU", WHITE, MM_SHADOW, 1)
    end

    def draw_hint
      b = @hint_spr.bitmap; b.clear
      pbSetSmallFont(b); b.font.size = 13
      text = "Favorite (A) Enter Favorite (Z)"
      pbDrawTextPositions(b, [[text, 6, 0, 0, Color.new(0, 0, 0), Color.new(0, 0, 0, 0)]])
    end
    def draw_location_box
      bw = 110; bh = 49
      b  = @loc_spr.bitmap; b.clear
      b.fill_rect(0, 0, bw, bh, Color.new(16, 20, 38, 220))
      b.fill_rect(0, 0, bw, 1,  Color.new(55, 75, 160, 255))
      b.fill_rect(0, bh-1, bw, 1, Color.new(55, 75, 160, 255))
      b.fill_rect(0, 0, 1, bh, Color.new(55, 75, 160, 255))
      b.fill_rect(bw-1, 0, 1, bh, Color.new(55, 75, 160, 255))
      pbSetSmallFont(b)
      begin
        loc  = pbGetMapNameFromId($game_map.map_id) rescue ""
        now  = pbGetTimeNow rescue Time.now
        time = now.strftime("%I:%M %p").sub(/^0/, "")
        day  = getDayOfTheWeekName() rescue now.strftime("%A")
        b.font.size = 13; b.font.bold = true
        pbDrawShadowText(b, 4, 3, bw - 8, 14, loc, WHITE, MM_SHADOW, 1)
        b.font.size = 12; b.font.bold = false
        pbDrawShadowText(b, 4, 18, bw - 8, 13, day,  WHITE, MM_SHADOW, 1)
        pbDrawShadowText(b, 4, 33, bw - 8, 13, time, WHITE, MM_SHADOW, 1)
      rescue; end
      @loc_spr.x = SCREEN_W - bw - 4
      @loc_spr.y = 4
    end

    def draw_economy_box
      bw = 110; bh = 49
      b  = @economy_spr.bitmap; b.clear
      b.fill_rect(0, 0, bw, bh, Color.new(16, 20, 38, 220))
      b.fill_rect(0, 0, bw, 1,  Color.new(55, 75, 160, 255))
      b.fill_rect(0, bh-1, bw, 1, Color.new(55, 75, 160, 255))
      b.fill_rect(0, 0, 1, bh, Color.new(55, 75, 160, 255))
      b.fill_rect(bw-1, 0, 1, bh, Color.new(55, 75, 160, 255))
      pbSetSmallFont(b)
      begin
        money = ($Trainer.money rescue 0).to_i
        money_text = money.to_s_formatted rescue money.to_s
        amount = "$#{money_text}"
        b.font.size = 13; b.font.bold = true
        pbDrawShadowText(b, 4, 3, bw - 8, 14, "ECONOMY", WHITE, MM_SHADOW, 1)
        b.font.size = 12; b.font.bold = false
        pbDrawShadowText(b, 4, 23, bw - 8, 18, amount, Color.new(120, 230, 150), Color.new(0, 0, 0, 0), 1)
      rescue; end
      @economy_spr.x = 4
      @economy_spr.y = 4
    end

    def draw_grid
      b = @grid_spr.bitmap; b.clear
      GRID_ROWS.times do |r|
        entries = @row_entries[r] || []
        state   = @row_state[r]
        focused = (@focus == (r == 0 ? :row0 : :row1))
        y = r * ROW_STRIDE
        GRID_COLS.times do |col|
          x   = GRID_X + col * (ROW_MOD_W + ROW_MOD_GAP)
          idx = state[:offset] + col
          i   = GRID_BOX_INSET
          if idx < entries.length
            entry = entries[idx]
            sel   = focused && state[:slot] == col
            draw_module_box(b, entry[:mod], x + i, y + i, ROW_MOD_W - i * 2, ROW_MOD_H - i * 2, sel, true, entry[:locked])
          else
            draw_empty_slot(b, x + i, y + i, ROW_MOD_W - i * 2, ROW_MOD_H - i * 2)
          end
        end
        last_col_x = GRID_X + (GRID_COLS - 1) * (ROW_MOD_W + ROW_MOD_GAP)
        arrow_y = y + (ROW_MOD_H - ARROW_H) / 2
        draw_arrow(b, GRID_X - ARROW_W - 2,            arrow_y, ARROW_W, ARROW_H, "<") if state[:offset] > 0
        draw_arrow(b, last_col_x + ROW_MOD_W + 2,      arrow_y, ARROW_W, ARROW_H, ">") if state[:offset] + GRID_COLS < entries.length
      end
    end

    def draw_carousel
      b = @car_spr.bitmap; b.clear
      n = @all_mods.length; return if n == 0

      cy_big  = (@car_h - CAR_BIG_W)  / 2
      cy_side = cy_big + (CAR_BIG_W - CAR_SIDE_W) / 2

      draw_car_item(b, (@car_sel - 2) % n, CAR_FAR_XL, cy_side, CAR_SIDE_W, false, false)
      draw_car_item(b, (@car_sel + 2) % n, CAR_FAR_XR, cy_side, CAR_SIDE_W, false, false)
      draw_car_item(b, (@car_sel - 1) % n, CAR_MID_XL, cy_side, CAR_SIDE_W, false, false)
      draw_car_item(b, (@car_sel + 1) % n, CAR_MID_XR, cy_side, CAR_SIDE_W, false, false)
      draw_car_item(b, @car_sel,            CAR_CTR_X,  cy_big,  CAR_BIG_W,  @focus == :carousel, true)

      arrow_y = cy_big + (CAR_BIG_W - ARROW_H) / 2
      draw_arrow(b, CAR_CTR_X - ARROW_W - 4,     arrow_y, ARROW_W, ARROW_H, "<")
      draw_arrow(b, CAR_CTR_X + CAR_BIG_W + 4,   arrow_y, ARROW_W, ARROW_H, ">")
    end

    def locked_at_car?(idx)
      @all_entries[idx % @all_entries.length][:locked] rescue false
    end

    def draw_car_item(b, idx, x, y, size, selected, show_label = true)
      entry = @all_entries[idx % @all_entries.length] rescue nil; return unless entry
      draw_module_box(b, entry[:mod], x, y, size, size, selected, show_label, entry[:locked])
    end


    def draw_module_box(b, mod, x, y, w, h, selected, show_label = true, locked = false)
      unless selected
        cached = cached_module_box(mod, w, h, show_label, locked)
        b.blt(x, y, cached, Rect.new(0, 0, w, h)) if cached
        return
      end
      draw_module_box_uncached(b, mod, x, y, w, h, selected, show_label, locked)
    end

    def cached_module_box(mod, w, h, show_label, locked)
      fav_key = ReloadedPauseMenu.favorite_module_key
      status = ReloadedPauseMenu.status_for(mod)
      status_color_key = ReloadedPauseMenu.status_color_cache_key(mod)
      key = [mod[:key], w, h, show_label ? 1 : 0, locked ? 1 : 0, fav_key == mod[:key] ? 1 : 0, status, status_color_key]
      return @module_box_cache[key] if @module_box_cache[key]
      bitmap = Bitmap.new(w, h)
      draw_module_box_uncached(bitmap, mod, 0, 0, w, h, false, show_label, locked)
      @module_box_cache[key] = bitmap
    end

    def draw_module_box_uncached(b, mod, x, y, w, h, selected, show_label = true, locked = false)
      fav_key = ReloadedPauseMenu.favorite_module_key
      is_fav  = fav_key && fav_key == mod[:key]

      if show_label
        if locked

          if selected
            t        = (Math.sin(@cursor_tick * Math::PI / 20.0) * 0.5 + 0.5)
            r_c      = (48 + (75 - 48) * t).to_i
            g_c      = (48 + (75 - 48) * t).to_i
            bl       = (56 + (85 - 56) * t).to_i
            bg_col   = Color.new(r_c, g_c, bl, 220)
            border_c = Color.new(130, 130, 145, 200)
          else
            bg_col   = Color.new(16, 20, 38, 220)
            border_c = Color.new(55, 75, 160, 255)
          end
        elsif selected
          t = (Math.sin(@cursor_tick * Math::PI / 20.0) * 0.5 + 0.5)
          r_c = (18  + (42  - 18)  * t).to_i
          g_c = (22  + (52  - 22)  * t).to_i
          bl  = (48  + (90  - 48)  * t).to_i
          bg_col   = Color.new(r_c, g_c, bl, 220)
          border_c = Color.new(110, 130, 200, 210)
        else
          bg_col   = Color.new(16, 20, 38, 220)
          border_c = Color.new(55, 75, 160, 255)
        end
        b.fill_rect(x, y, w, h, bg_col)
        b.fill_rect(x,         y,         w, 1, border_c)
        b.fill_rect(x,         y + h - 1, w, 1, border_c)
        b.fill_rect(x,         y,         1, h, border_c)
        b.fill_rect(x + w - 1, y,         1, h, border_c)
      end


      pad_x    = [w / 9, 6].max
      pad_top  = [h / 12, 4].max
      sub_h    = show_label ? [h / 6, 16].max : 0
      label_h  = show_label ? [h / 4, 24].max : 0
      ib_w     = w - pad_x * 2
      ib_h     = h - pad_top - label_h - sub_h - (show_label ? 2 : 0)
      ib_x     = x + pad_x
      ib_y     = y + pad_top


      icon = ReloadedPauseMenu.icon_for(mod) || ReloadedPauseMenu.placeholder_icon
      if icon
        sc = [(ib_w).to_f / icon.width, (ib_h).to_f / icon.height].min * 0.88
        iw = (icon.width  * sc).to_i
        ih = (icon.height * sc).to_i
        ix = ib_x + (ib_w - iw) / 2
        iy = ib_y + (ib_h - ih) / 2
        b.stretch_blt(Rect.new(ix, iy, iw, ih), icon, Rect.new(0, 0, icon.width, icon.height))
      end




      if show_label
        sub_y = ib_y + ib_h
        fs_sub = w >= 70 ? 11 : 9
        pbSetSmallFont(b); b.font.size = fs_sub
        status_text = ReloadedPauseMenu.status_for(mod)
        if locked
          pbDrawShadowText(b, x, sub_y, w, sub_h, "LOCKED",
                           Color.new(160, 160, 160), MM_SHADOW, 1)
        elsif !status_text.empty?
          status_color = ReloadedPauseMenu.status_color_for(mod)
          pbDrawShadowText(b, x, sub_y, w, sub_h, status_text,
                           status_color, Color.new(0, 0, 0, 0), 1)
        elsif is_fav
          pbDrawShadowText(b, x, sub_y, w, sub_h, "FAVORITE",
                           Color.new(228, 188, 58), MM_SHADOW, 1)
        end
      end


      if show_label
        label_y = ib_y + ib_h + sub_h
        fs = w >= 88 ? 18 : 14
        pbSetSmallFont(b); b.font.size = fs
        lbl_color = locked ? Color.new(180, 180, 180) : WHITE
        pbDrawShadowText(b, x, label_y - 4, w, label_h, mod[:label].upcase, lbl_color, nil, 1)
      end
    end


    def draw_arrow(b, x, y, w, h, glyph)
      pbSetSmallFont(b); b.font.size = 18
      pbDrawShadowText(b, x, y + (h / 2) - 13, w, 20, glyph, WHITE, nil, 1)
    end


    def _mouse_pos
      if defined?(Reloaded::ModManagerUI::InputSupport)
        return Reloaded::ModManagerUI::InputSupport.mouse_pos
      end
      position = Reloaded::MouseInput.active_position if defined?(Reloaded::MouseInput)
      position || [nil, nil]
    rescue
      [nil, nil]
    end

    def handle_mouse
      mx, my = _mouse_pos
      return unless mx && my
      clicked = if defined?(Reloaded::ModManagerUI::InputSupport)
                  Reloaded::ModManagerUI::InputSupport.mouse_left_trigger?
                else
                  (Input.trigger?(Input::MOUSELEFT) rescue false)
                end


      if clicked
        n = @all_mods.length
        if n > 0
          cy_big  = (@car_h - CAR_BIG_W) / 2
          arrow_y = @car_y + cy_big + (CAR_BIG_W - ARROW_H) / 2
          lax = CAR_CTR_X - ARROW_W - 4
          if mx.between?(lax, lax + ARROW_W - 1) && my.between?(arrow_y, arrow_y + ARROW_H - 1)
            @car_sel = (@car_sel - 1) % n; @focus = :carousel; @hover_id = nil
            pbPlayCursorSE; draw_grid; draw_carousel; return
          end
          rax = CAR_CTR_X + CAR_BIG_W + 4
          if mx.between?(rax, rax + ARROW_W - 1) && my.between?(arrow_y, arrow_y + ARROW_H - 1)
            @car_sel = (@car_sel + 1) % n; @focus = :carousel; @hover_id = nil
            pbPlayCursorSE; draw_grid; draw_carousel; return
          end
        end
        GRID_ROWS.times do |r|
          state  = @row_state[r]
          entries = @row_entries[r] || []
          gy_abs = ROW_Y_START + r * ROW_STRIDE
          next unless my.between?(gy_abs, gy_abs + ROW_MOD_H - 1)
          focus_sym  = r == 0 ? :row0 : :row1
          last_col_x = GRID_X + (GRID_COLS - 1) * (ROW_MOD_W + ROW_MOD_GAP)
          arrow_y    = gy_abs + (ROW_MOD_H - ARROW_H) / 2
          lax = GRID_X - ARROW_W - 2
          if mx.between?(lax, lax + ARROW_W - 1) && my.between?(arrow_y, arrow_y + ARROW_H - 1)
            if state[:offset] > 0
              state[:offset] -= 1; state[:slot] = 0
              @focus = focus_sym; @hover_id = nil; pbPlayCursorSE; draw_grid
            end; return
          end
          rax = last_col_x + ROW_MOD_W + 2
          if mx.between?(rax, rax + ARROW_W - 1) && my.between?(arrow_y, arrow_y + ARROW_H - 1)
            if state[:offset] + GRID_COLS < entries.length
              state[:offset] += 1; state[:slot] = GRID_COLS - 1
              @focus = focus_sym; @hover_id = nil; pbPlayCursorSE; draw_grid
            end; return
          end
        end
      end


      n = @all_mods.length
      if n > 0
        cy_big = (@car_h - CAR_BIG_W) / 2
        ctr_y  = @car_y + cy_big
        if mx.between?(CAR_CTR_X, CAR_CTR_X + CAR_BIG_W - 1) && my.between?(ctr_y, ctr_y + CAR_BIG_W - 1)
          hover_id = :carousel
          if @hover_id != hover_id
            @hover_id = hover_id; @focus = :carousel
            pbPlayCursorSE; draw_grid; draw_carousel
          end
          if clicked
            entry = @all_entries[@car_sel]
            if entry && entry[:locked]
              show_locked_reason(entry)
            elsif entry
              pbPlayDecisionSE; @pending = entry[:mod][:handler]; @running = false
            end
          end
          return
        end
      end

      GRID_ROWS.times do |r|
        entries   = @row_entries[r] || []
        state     = @row_state[r]
        gy_abs    = ROW_Y_START + r * ROW_STRIDE
        next unless my.between?(gy_abs, gy_abs + ROW_MOD_H - 1)
        focus_sym = r == 0 ? :row0 : :row1
        GRID_COLS.times do |col|
          bx = GRID_X + col * (ROW_MOD_W + ROW_MOD_GAP)
          next unless mx.between?(bx, bx + ROW_MOD_W - 1)
          idx   = state[:offset] + col
          next if idx >= entries.length
          entry = entries[idx]
          hover_id = [:grid, r, idx]
          if @hover_id != hover_id
            @hover_id = hover_id; @focus = focus_sym; state[:slot] = col
            pbPlayCursorSE; draw_grid; draw_carousel
          end
          if clicked
            if entry[:locked]
              show_locked_reason(entry)
            else
              pbPlayDecisionSE; @pending = entry[:mod][:handler]; @running = false
            end
          end
          return
        end
      end


      @hover_id = nil
    end


    def draw_empty_slot(b, x, y, w, h); end


    def handle_input
      if Input.trigger?(Input::AUX1)
        open_row1_customizer; return
      end
      case @focus
      when :carousel then handle_carousel
      when :row0     then handle_row(0)
      when :row1     then handle_row(1)
      end
    end

    def handle_carousel
      n = @all_mods.length
      if Input.trigger?(Input::LEFT)
        @car_sel = (@car_sel - 1) % n
        pbPlayCursorSE; draw_carousel
      elsif Input.trigger?(Input::RIGHT)
        @car_sel = (@car_sel + 1) % n
        pbPlayCursorSE; draw_carousel
      elsif Input.trigger?(Input::UP)
        if !@row_mods[1].empty?
          @focus = :row1; clamp_slot(1); pbPlayCursorSE; draw_grid; draw_carousel
        elsif !@row_mods[0].empty?
          @focus = :row0; clamp_slot(0); pbPlayCursorSE; draw_grid; draw_carousel
        end
      elsif Input.trigger?(Input::SPECIAL)
        fav_key = ReloadedPauseMenu.favorite_module_key
        if fav_key
          entry = @all_entries.find { |e| e[:mod][:key] == fav_key }
          if entry && !entry[:locked]
            pbPlayDecisionSE; @pending = entry[:mod][:handler]; @running = false
          end
        end
      elsif Input.trigger?(Input::ACTION)
        entry = @all_entries[@car_sel]; return unless entry
        return if entry[:locked]
        _toggle_favorite(entry[:mod][:key])
        draw_carousel; draw_grid; draw_hint
      elsif Input.trigger?(Input::USE)
        entry = @all_entries[@car_sel]; return unless entry
        if entry[:locked]
          show_locked_reason(entry); return
        end
        pbPlayDecisionSE; @pending = entry[:mod][:handler]; @running = false
      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE; @running = false
      end
    end

    def handle_row(r)
      mods  = @row_mods[r]
      entries = @row_entries[r]
      state = @row_state[r]
      if Input.trigger?(Input::LEFT)
        abs = state[:offset] + state[:slot]
        if abs > 0
          abs -= 1
          state[:offset] = [abs - (GRID_COLS - 1), 0].max
          state[:slot]   = abs - state[:offset]
          pbPlayCursorSE; draw_grid
        elsif mods.length > 1
          abs = mods.length - 1
          state[:offset] = [abs - (GRID_COLS - 1), 0].max
          state[:slot]   = abs - state[:offset]
          pbPlayCursorSE; draw_grid
        end
      elsif Input.trigger?(Input::RIGHT)
        abs = state[:offset] + state[:slot]
        if abs < mods.length - 1
          abs += 1
          state[:offset] = [abs - (GRID_COLS - 1), 0].max
          state[:slot]   = abs - state[:offset]
          pbPlayCursorSE; draw_grid
        elsif mods.length > 1
          state[:offset] = 0; state[:slot] = 0
          pbPlayCursorSE; draw_grid
        end
      elsif Input.trigger?(Input::UP)
        if r == 1 && !@row_mods[0].empty?
          move_focus_to_row(0, 1); pbPlayCursorSE; draw_grid
        end
      elsif Input.trigger?(Input::DOWN)
        if r == 0 && !@row_mods[1].empty?
          move_focus_to_row(1, 0); pbPlayCursorSE; draw_grid
        else
          @focus = :carousel; pbPlayCursorSE; draw_grid; draw_carousel
        end
      elsif Input.trigger?(Input::AUX2)
        @focus = :carousel; pbPlayCursorSE; draw_grid; draw_carousel
      elsif Input.trigger?(Input::SPECIAL)
        fav_key = ReloadedPauseMenu.favorite_module_key
        if fav_key
          entry = @row_entries.flatten.find { |e| e[:mod][:key] == fav_key }
          entry ||= @all_entries.find { |e| e[:mod][:key] == fav_key }
          if entry && !entry[:locked]
            pbPlayDecisionSE; @pending = entry[:mod][:handler]; @running = false
          end
        end
      elsif Input.trigger?(Input::ACTION)
        return if mods.empty?
        entry = entries[state[:offset] + state[:slot]]; return unless entry
        return if entry[:locked]
        _toggle_favorite(entry[:mod][:key])
        draw_grid; draw_carousel; draw_hint
      elsif Input.trigger?(Input::USE)
        return if mods.empty?
        entry = entries[state[:offset] + state[:slot]]; return unless entry
        if entry[:locked]
          show_locked_reason(entry); return
        end
        pbPlayDecisionSE; @pending = entry[:mod][:handler]; @running = false
      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE; @running = false
      end
    end

    def show_locked_reason(entry)
      return unless entry && entry[:locked]
      pbPlayBuzzerSE rescue nil
      pbMessage(ReloadedPauseMenu.lock_reason_for(entry[:mod]))
      draw_all
    end
    def open_row1_customizer
      ReloadedPauseMenu::CustomizeRow1Scene.new.main
      @row_entries[1] = ReloadedPauseMenu.all_row_modules_with_state(1)
      @row_mods[1]    = @row_entries[1].map { |e| e[:mod] }
      @row_state[1]   = { offset: 0, slot: 0 }
      @focus = :row1
      draw_all
    end

    def _toggle_favorite(key)
      fav = ReloadedPauseMenu.favorite_module_key
      ReloadedPauseMenu.favorite_module_key = (fav == key ? nil : key)
      pbPlayDecisionSE
    end

    def clamp_slot(r)
      mods = @row_mods[r]; return if mods.empty?
      max = [mods.length - @row_state[r][:offset], GRID_COLS].min - 1
      @row_state[r][:slot] = @row_state[r][:slot].clamp(0, max)
    end

    def move_focus_to_row(target_row, source_row)
      target_mods = @row_mods[target_row] || []
      return if target_mods.empty?
      source_state = @row_state[source_row] || { offset: 0, slot: 0 }
      desired_offset = source_state[:offset].to_i
      desired_slot = source_state[:slot].to_i
      max_offset = [target_mods.length - GRID_COLS, 0].max
      offset = desired_offset.clamp(0, max_offset)
      max_slot = [[target_mods.length - offset, GRID_COLS].min - 1, 0].max
      slot = desired_slot.clamp(0, max_slot)
      @row_state[target_row] = { offset: offset, slot: slot }
      @focus = target_row == 0 ? :row0 : :row1
    end
  end

  class CustomizeRow1Scene

    ITEM_H   = 28
    LIST_Y   = 52
    LIST_X   = 16
    LIST_W   = 480
    BOX_SIZE = 12
    NUM_W    = 22
    FOOTER_H = 22
    FOOTER_Y = 384 - FOOTER_H
    SCREEN_W = 512
    SCREEN_H = 384
    MAX_VISIBLE_ROWS = 11

    def main
      @all_mods = ReloadedPauseMenu.instance_variable_get(:@modules) || []
      return if @all_mods.empty?

      saved = ReloadedPauseMenu.custom_row
      @checked_order = saved.select { |k| @all_mods.any? { |m| m[:key] == k } }
      @cursor   = 0
      @top_row  = 0
      @dragging = false
      @running  = true

      @vp = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
      @vp.z = 100_000

      @bg_spr   = BitmapSprite.new(SCREEN_W, SCREEN_H, @vp); @bg_spr.z   = 5
      @list_spr = BitmapSprite.new(SCREEN_W, SCREEN_H, @vp); @list_spr.z = 10

      draw_bg
      draw_list

      loop do
        Graphics.update; Input.update
        break unless @running
        handle_input_cust
      end

      teardown_cust
      ReloadedPauseMenu.custom_row = @checked_order
    end

    private

    def sorted_items
      active   = @checked_order.map { |k| @all_mods.find { |m| m[:key] == k } }.compact
      inactive = @all_mods.reject  { |m| @checked_order.include?(m[:key]) }
      active + inactive
    end

    def draw_bg
      b = @bg_spr.bitmap; b.clear
      b.fill_rect(0, 0, SCREEN_W, SCREEN_H, Color.new(10, 12, 30, 255))
      pbSetSmallFont(b); b.font.size = 22; b.font.bold = true
      pbDrawShadowText(b, 0, 8, SCREEN_W, 36, "CUSTOMIZE ROW 2",
        ReloadedPauseMenu::WHITE, ReloadedPauseMenu::MM_SHADOW, 1)
      b.fill_rect(0, FOOTER_Y - 2, SCREEN_W, SCREEN_H - FOOTER_Y + 2, Color.new(10, 12, 30, 255))
    end

    def draw_list
      b = @list_spr.bitmap; b.clear
      b.fill_rect(0, FOOTER_Y - 2, SCREEN_W, SCREEN_H - FOOTER_Y + 2, Color.new(10, 12, 30, 255))
      items    = sorted_items
      n_active = @checked_order.length
      ensure_cursor_visible(items.length)

      last_row = [@top_row + MAX_VISIBLE_ROWS, items.length].min
      items[@top_row...last_row].each_with_index do |mod, visible_i|
        i      = @top_row + visible_i
        y      = LIST_Y + visible_i * ITEM_H
        sel    = (i == @cursor)
        active = @checked_order.include?(mod[:key])
        pos    = active ? @checked_order.index(mod[:key]) + 1 : nil

        if sel && @dragging
          b.fill_rect(LIST_X, y, LIST_W, ITEM_H - 2, Color.new(180, 130, 30, 160))
        elsif sel
          b.fill_rect(LIST_X, y, LIST_W, ITEM_H - 2, Color.new(60, 80, 160, 160))
        end

        box_x = LIST_X + 6
        box_y = y + (ITEM_H - BOX_SIZE) / 2
        box_c = active ? Color.new(80, 200, 100, 230) : Color.new(120, 120, 140, 180)
        b.fill_rect(box_x, box_y, BOX_SIZE, BOX_SIZE, box_c)
        bdr = Color.new(0, 0, 0, 120)
        b.fill_rect(box_x,              box_y,              BOX_SIZE, 1, bdr)
        b.fill_rect(box_x,              box_y + BOX_SIZE-1, BOX_SIZE, 1, bdr)
        b.fill_rect(box_x,              box_y,              1, BOX_SIZE, bdr)
        b.fill_rect(box_x + BOX_SIZE-1, box_y,              1, BOX_SIZE, bdr)

        num_x = box_x + BOX_SIZE + 6
        pbSetSmallFont(b); b.font.size = 14
        if pos
          num_c = sel ? Color.new(255, 220, 80) : Color.new(200, 200, 120)
          pbDrawShadowText(b, num_x, y + 6, NUM_W, ITEM_H - 6, pos.to_s, num_c, nil, 1)
        end

        label_x = num_x + NUM_W + 4
        lbl_c = if @dragging && sel   then Color.new(255, 220, 80)
                elsif sel             then ReloadedPauseMenu::WHITE
                elsif active          then Color.new(200, 215, 200)
                else                       Color.new(160, 160, 175)
                end
        pbSetSmallFont(b); b.font.size = 16
        pbDrawShadowText(b, label_x, y + 5, LIST_W - (label_x - LIST_X), ITEM_H - 5,
          mod[:label].upcase, lbl_c, nil, 0)
      end

      if n_active > @top_row && n_active < last_row
        div_y = LIST_Y + (n_active - @top_row) * ITEM_H - 2
        b.fill_rect(LIST_X + 20, div_y, LIST_W - 40, 1, Color.new(100, 100, 140, 160))
      end

      hint = if @dragging
               "Back (B) Place (A) Move (Up/Down)"
             else
               "Confirm (C) Back (B) Pick Up (A) Move (Up/Down)"
             end
      pbSetSmallFont(b); b.font.size = 16
      pbDrawTextPositions(b, [[hint, (SCREEN_W / 2) + 150, FOOTER_Y - 3, 1, ReloadedPauseMenu::WHITE, Color.new(0, 0, 0, 0)]])
    end
    def ensure_cursor_visible(count)
      @top_row ||= 0
      max_top = [count - MAX_VISIBLE_ROWS, 0].max
      @top_row = [[@top_row, 0].max, max_top].min
      @top_row = @cursor if @cursor < @top_row
      @top_row = @cursor - MAX_VISIBLE_ROWS + 1 if @cursor >= @top_row + MAX_VISIBLE_ROWS
      @top_row = [[@top_row, 0].max, max_top].min
    end
    def handle_input_cust
      items = sorted_items
      n     = items.length

      if @dragging
        if Input.trigger?(Input::DOWN)
          key = items[@cursor][:key]
          idx = @checked_order.index(key)
          if idx && idx < @checked_order.length - 1
            @checked_order.delete(key); @checked_order.insert(idx + 1, key)
            @cursor += 1
            ensure_cursor_visible(sorted_items.length)
            pbPlayCursorSE; draw_list
          end
        elsif Input.trigger?(Input::UP)
          key = items[@cursor][:key]
          idx = @checked_order.index(key)
          if idx && idx > 0
            @checked_order.delete(key); @checked_order.insert(idx - 1, key)
            @cursor -= 1
            ensure_cursor_visible(sorted_items.length)
            pbPlayCursorSE; draw_list
          end
        elsif Input.trigger?(Input::ACTION)
          @dragging = false; pbPlayDecisionSE; draw_list
        elsif Input.trigger?(Input::BACK)
          @dragging = false; pbPlayCursorSE; draw_list
        end
      else
        if Input.trigger?(Input::DOWN)
          @cursor = (@cursor + 1) % n; ensure_cursor_visible(n); pbPlayCursorSE; draw_list
        elsif Input.trigger?(Input::UP)
          @cursor = (@cursor - 1) % n; ensure_cursor_visible(n); pbPlayCursorSE; draw_list
        elsif Input.trigger?(Input::USE)
          key = items[@cursor][:key]
          if @checked_order.include?(key)
            @checked_order.delete(key)
            @cursor = [@cursor, sorted_items.length - 1].min
            ensure_cursor_visible(sorted_items.length)
          else
            @checked_order << key
          end
          pbPlayDecisionSE; draw_list
        elsif Input.trigger?(Input::ACTION)
          key = items[@cursor][:key]
          if @checked_order.include?(key)
            @dragging = true; pbPlayDecisionSE; draw_list
          end
        elsif Input.trigger?(Input::BACK)
          pbPlayCloseMenuSE; @running = false
        end
      end
    end

    def teardown_cust
      [@bg_spr, @list_spr].compact.each do |s|
        s.bitmap.dispose rescue nil; s.dispose rescue nil
      end
      @vp.dispose rescue nil
    end
  end

end
ReloadedPauseMenu.register_module(
  :POKEMON,
  label:     "Pokemon",
  handler:   proc {
    pbPlayDecisionSE
    hiddenmove = nil
    pbFadeOutIn {
      sscene  = PokemonParty_Scene.new
      sscreen = PokemonPartyScreen.new(sscene, $Trainer.party)
      hiddenmove = sscreen.pbPokemonScreen
    }
    if hiddenmove
      $game_temp.in_menu = false
      pbUseHiddenMove(hiddenmove[0], hiddenmove[1])
    end
  },
  condition: proc { $Trainer && $Trainer.party_count > 0 },
  lock_reason: "You do not have any Pokemon yet."
)

ReloadedPauseMenu.register_module(
  :POKEDEX,
  label:     "Pokedex",
  handler:   proc {
    pbPlayDecisionSE
    pbFadeOutIn {
      if (Settings::USE_CURRENT_REGION_DEX rescue false)
        scene  = PokemonPokedex_Scene.new
        screen = PokemonPokedexScreen.new(scene)
        screen.pbStartScreen
      else
        $PokemonGlobal.pokedexDex = $Trainer.pokedex.accessible_dexes[0]
        scene  = PokemonPokedexMenu_Scene.new
        screen = PokemonPokedexMenuScreen.new(scene)
        screen.pbStartScreen
      end
    }
  },
  condition: proc {
    $Trainer && $Trainer.has_pokedex &&
    ($Trainer.pokedex.accessible_dexes rescue []).length > 0
  },
  lock_reason: "You do not have access to the Pokedex yet."
)

ReloadedPauseMenu.register_module(
  :BAG,
  label:     "Bag",
  handler:   proc {
    pbPlayDecisionSE
    item = nil
    if ($PokemonSystem.hr_bag_interface rescue 0).to_i >= 1 && defined?(ReloadedBagEX_Scene)
      pbFadeOutIn {
        scene  = ReloadedBagEX_Scene.new
        screen = ReloadedBagEXScreen.new(scene, $PokemonBag)
        item   = screen.pbStartScreen
      }
    else
      pbFadeOutIn {
        scene  = PokemonBag_Scene.new
        screen = PokemonBagScreen.new(scene, $PokemonBag)
        item   = screen.pbStartScreen
      }
    end
    if item
      $game_temp.in_menu = false
      pbUseKeyItemInField(item)
    end
  },
  condition: proc { !pbInBugContest? }
)

ReloadedPauseMenu.register_module(
  :POKENAV,
  label:     "PokeNav",
  handler:   proc {
    pbPlayDecisionSE
    pbFadeOutIn {
      scene  = PokemonPokegear_Scene.new
      screen = PokemonPokegearScreen.new(scene)
      screen.pbStartScreen
    }
  },
  condition: proc { $Trainer && $Trainer.has_pokegear },
  lock_reason: "You do not have access to the PokeNav yet."
)

ReloadedPauseMenu.register_module(
  :TRAINERINFO,
  label:     "Trainer Info",
  handler:   proc {
    pbPlayDecisionSE
    pbFadeOutIn {
      scene  = PokemonTrainerCard_Scene.new
      screen = PokemonTrainerCardScreen.new(scene)
      screen.pbStartScreen
    }
  },
  condition: proc { $Trainer != nil }
)

ReloadedPauseMenu.register_module(
  :OUTFIT,
  label:     "Outfit",
  handler:   proc {
    pbCommonEvent(COMMON_EVENT_OUTFIT)
  },
  condition: proc { $Trainer && $Trainer.can_change_outfit },
  lock_reason: "Outfit changing is not available right now."
)

ReloadedPauseMenu.register_module(
  :SAVE,
  label:     "Save",
  handler:   proc {
    pbPlayDecisionSE
    scene  = PokemonSave_Scene.new
    screen = PokemonSaveScreen.new(scene)
    screen.pbSaveScreen
  },
  condition: proc { $game_system && !$game_system.save_disabled && !pbInSafari? && !pbInBugContest? },
  lock_reason: "Saving is not available right now."
)

ReloadedPauseMenu.register_module(
  :OPTIONS,
  label:     "Options",
  handler:   proc {
    pbPlayDecisionSE
    pbFadeOutIn {
      scene  = PokemonGameOption_Scene.new
      screen = PokemonOptionScreen.new(scene)
      screen.pbStartScreen
      pbUpdateSceneMap
    }
  },
  condition: proc { true }
)

ReloadedPauseMenu.register_module(
  :TMVAULT,
  label:     "TM Vault",
  handler:   proc { TMVault.open },
  condition: proc { defined?(TMVault) },
  lock_reason: "TM Vault is not available yet."
)

ReloadedPauseMenu.register_module(
  :RELOADEDMART,
  label:     "Reloaded Mart",
  handler:   proc { ReloadedMart.open if defined?(ReloadedMart) },
  condition: proc {
    defined?(ReloadedMart) && ReloadedMart.available?
  },
  lock_reason: "Reloaded Mart is not available yet."
)

ReloadedPauseMenu.register_module(
  :TITLE,
  label:     "Title",
  handler:   proc {
    if pbConfirmMessage(_INTL("Are you sure you want to quit the game and return to the main menu?"))
      scene  = PokemonSave_Scene.new
      screen = PokemonSaveScreen.new(scene)
      screen.pbSaveScreen
      $game_temp.to_title = true
    end
  },
  condition: proc { true }
)

ReloadedPauseMenu.register_module(
  :DEBUG,
  label:     "Debug",
  handler:   proc {
    pbPlayDecisionSE
    pbFadeOutIn {
      pbDebugMenu
    }
  },
  condition: proc { $DEBUG },
  hidden:    true
)





# Route the vanilla pause call based on the Pause Menu option.
if defined?(Scene_Map)
  class Scene_Map
    unless method_defined?(:hr_repm_orig_call_menu)
      alias_method :hr_repm_orig_call_menu, :call_menu
    end
    def call_menu
      if ($PokemonSystem.hr_pause_menu rescue 1).to_i == 1
        $game_temp.menu_calling = false
        $game_temp.in_menu = true
        $game_player.straighten
        $game_map.update
        ReloadedPauseMenu.open
        $game_temp.in_menu = false
      else
        hr_repm_orig_call_menu
      end
    end

    unless method_defined?(:hr_repm_orig_show_location)
      alias_method :hr_repm_orig_show_location, :showLocationWindow
    end
    def showLocationWindow
      return if ($PokemonSystem.hr_pause_menu rescue 1).to_i == 1
      hr_repm_orig_show_location
    end
  end
end
