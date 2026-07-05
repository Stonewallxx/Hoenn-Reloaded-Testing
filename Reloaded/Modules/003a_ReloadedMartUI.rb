#======================================================
# Reloaded Mart UI
# Author: Stonewall
#======================================================
# REX-style full-screen buy interface for the online Reloaded Mart backend.
#
# Responsibilities:
#   - Keep UI code separate from the catalog/transaction backend.
#   - Present online catalog entries through category/pocket navigation.
#   - Preserve the Reloaded EX mart interaction model.
#   - Route purchases through ReloadedMart::Transactions.
#
#======================================================

module ReloadedMart
  module UI
    # -- Config -------------------------------------------------------------
    SORT_MODES = [:name, :price_low, :price_high, :stock].freeze
    MONEY_ANIMATION_SECONDS = 0.45
    QUANTITY_ANIMATION_SECONDS = 0.45
    ROW_BADGE_LIMIT = 6
    DEFAULT_CATEGORY_NAMES = {
      :featured => "FEATURED",
      :favorites => "FAVORITES",
      :items => "ITEMS",
      :medicine => "MEDICINE",
      :poke_balls => "POKE BALLS",
      :tms_hms => "TMS & HMS",
      :berries => "BERRIES",
      :mail => "MAIL",
      :battle_items => "BATTLE ITEMS"
    }.freeze
    BANNER_KEY_PRIORITY = {
      :vanilla_mart => {
        :buy => ["vanilla_buy", "regular_buy", "npc_buy", "vanilla", "regular"],
        :sell => ["vanilla_sell", "regular_sell", "npc_sell", "vanilla", "regular"]
      },
      :reloaded_mart => {
        :buy => ["reloaded_buy", "reloaded", "buy"],
        :sell => ["reloaded_sell", "reloaded", "sell"]
      }
    }.freeze

    class << self
      def open
        if defined?(pbMessage)
          commands = [_INTL("Buy"), _INTL("Sell"), _INTL("Quit")]
          loop do
            choice = pbMessage(_INTL("Welcome! How may I serve you?"), commands, 3)
            case choice
            when 0 then open_buy
            when 1 then open_sell
            else
              pbMessage(_INTL("Please come again!")) rescue nil
              break
            end
          end
        else
          open_buy
        end
      end

      def open_buy
        adapter = ReloadedMartBuyAdapter.new
        scene = ReloadedMartBuyScene.new
        screen = ReloadedMartBuyScreen.new(scene, adapter)
        screen.pbBuyScreen
      end

      def open_sell
        adapter = ReloadedMartSellAdapter.new
        scene = ReloadedMartSellScene.new
        screen = ReloadedMartSellScreen.new(scene, adapter)
        screen.pbSellScreen
      end

      def banner_text(context = {}, entries = [])
        raw = ReloadedMart::Source.active_raw || {}
        parts = []
        banner = contextual_banner(raw, context)
        parts << banner unless banner.to_s.empty?
        ReloadedMart::Economy.countdowns(context).each do |timer|
          next if timer[:label].to_s.empty?
          parts << "#{timer[:label]}: #{timer[:text]}"
        end
        parts.uniq.join("     ")
      rescue
        ""
      end

      private

      def contextual_banner(raw, context)
        source = context[:source].to_s
        mode = context[:mode].to_s
        banners = raw["banners"] || raw[:banners]
        keys = banner_keys(source, mode)
        if banners.is_a?(Hash)
          keys.each do |key|
            text = banner_value(banners[key] || banners[key.to_sym])
            return text unless text.to_s.empty?
          end
        end
        return banner_value(raw["banner"] || raw[:banner]) if source == "reloaded_mart" && mode == "buy"
        ""
      end

      def banner_keys(source, mode)
        source_key = source.to_s.to_sym
        mode_key = mode.to_s.to_sym
        configured = BANNER_KEY_PRIORITY[source_key]
        return configured[mode_key] if configured && configured[mode_key]
        ["#{source}_#{mode}", source, mode]
      end

      def banner_value(value)
        if value.is_a?(Hash)
          active = value.key?("active") ? value["active"] : value[:active]
          return "" if active == false
          return (value["text"] || value[:text]).to_s
        end
        value.to_s
      end
    end
  end
end

class ReloadedMartBuyAdapter
  def initialize
    @price_cache = {}
  end

  def categories(sort_mode = :name)
    rows = visible_entries
    groups = []
    favorite_rows = rows.select { |entry| ReloadedMart.favorite?(entry.id) }
    groups << { :id => :favorites, :name => ReloadedMart::UI::DEFAULT_CATEGORY_NAMES[:favorites], :entries => sort_entries(favorite_rows, sort_mode) } unless favorite_rows.empty?
    ordered_category_ids.each do |category|
      entries = rows.select { |entry| same_category?(entry, category) }
      next if entries.empty?
      groups << {
        :id => category[:id],
        :name => category[:name],
        :entries => sort_entries(entries, sort_mode)
      }
    end
    uncategorized = rows.reject { |entry| groups.any? { |group| group[:entries].include?(entry) } }
    groups << { :id => :items, :name => ReloadedMart::UI::DEFAULT_CATEGORY_NAMES[:items], :entries => sort_entries(uncategorized, sort_mode) } unless uncategorized.empty?
    groups
  end

  def visible_entries
    catalog_rows = Array(ReloadedMart::Source.active_catalog).select do |entry|
      entry && entry.purchasable? && !ReloadedMart::Availability.hidden?(entry, context)
    end
    rows = catalog_rows + ReloadedMart::Economy.daily_featured_entries(catalog_rows, context)
    seen = {}
    rows.select do |entry|
      next false unless entry
      next false if seen[entry.id.to_s]
      seen[entry.id.to_s] = true
      true
    end
  rescue
    []
  end

  def context
    { :source => :reloaded_mart, :mode => :buy }
  end

  def ui_title
    "RLD Mart"
  end

  def display_name(entry)
    return "" unless entry
    return entry.name unless entry.kind == :item
    data = item_data(entry)
    return entry.name.to_s.empty? ? entry.id.to_s : entry.name unless data
    name = data.name
    name = "#{name} #{GameData::Move.get(data.move).name}" if data.is_machine? && data.move rescue name
    name
  end

  def description(entry)
    return "" unless entry
    display = entry.display.is_a?(Hash) ? entry.display : {}
    text = display["description"] || display[:description] || entry.raw["description"] rescue nil
    return "???" if mystery_box?(entry)
    return text.to_s unless text.to_s.empty?
    return bundle_preview_text(entry, hidden: false) if entry.bundle_like?
    item_data(entry)&.description.to_s
  rescue
    ""
  end

  def item_data(entry)
    return nil unless entry
    item_id = entry.raw.is_a?(Hash) ? (entry.raw["item"] || entry.raw[:item] || entry.id) : entry.id
    GameData::Item.try_get(item_id) rescue nil
  end

  def icon_item(entry)
    data = item_data(entry)
    data ? data.id : nil
  end

  def favorite?(entry)
    entry && ReloadedMart.favorite?(entry.id)
  end

  def toggle_favorite(entry)
    return false unless entry
    ReloadedMart.toggle_favorite(entry.id)
  end

  def price(entry)
    @price_cache[entry.id] ||= ReloadedMart::Pricing.price_for(entry, context)
  end

  def buy_price(entry)
    [price(entry).final.to_i, 0].max
  end

  def base_price(entry)
    price(entry).base.to_i
  end

  def price_overridden?(entry)
    price(entry).overridden?
  rescue
    false
  end

  def buy_price_str(entry)
    value = buy_price(entry)
    value <= 0 ? "FREE" : ReloadedMart.format_currency(value, price(entry).currency)
  end

  def money
    ReloadedMart::Inventory.money
  end

  def money_str
    ReloadedMart.format_currency(money)
  end

  def in_bag_qty(entry)
    data = item_data(entry)
    data ? ReloadedMart::Inventory.quantity(data.id) : 0
  end

  def locked?(entry)
    ReloadedMart::Availability.locked?(entry, context)
  end

  def lock_text(entry)
    ReloadedMart::Availability.lock_text(entry, context)
  end

  def maxed?(entry)
    return false unless entry && entry.kind == :item
    max = Settings::BAG_MAX_PER_SLOT rescue 999
    in_bag_qty(entry) >= max
  end

  def stock_remaining(entry)
    ReloadedMart::Stock.remaining(entry)
  end

  def restock_text(entry)
    seconds = ReloadedMart::Stock.restock_seconds(entry, context)
    seconds ? ReloadedMart::Rules.format_duration(seconds) : nil
  end

  def limited_time_text(entry)
    ReloadedMart::Availability.remaining_time_text(entry, context)
  end

  def daily_featured?(entry)
    ReloadedMart::Economy.daily_featured?(entry, context)
  end

  def new?(entry)
    report = ReloadedMart::Source.active_report
    version = report ? report.catalog_version : ReloadedMart::DEFAULT_CATALOG_VERSION
    ReloadedMart.new_catalog_version?(version)
  rescue
    false
  end

  def mystery_box?(entry)
    return false unless entry
    display = entry.display.is_a?(Hash) ? entry.display : {}
    value = display["mystery_box"] || display[:mystery_box] || entry.raw["mystery_box"] rescue false
    ReloadedMart::Rules.truthy?(value)
  end

  def max_quantity(entry)
    return 0 unless entry
    return 0 if locked?(entry)
    max = ReloadedMart::Limits.max_per_purchase(entry) || (Settings::BAG_MAX_PER_SLOT rescue 999)
    stock = stock_remaining(entry)
    max = [max, stock.to_i].min unless stock.nil?
    max = [max, 1].min if [:service, :unlock, :coupon].include?(entry.kind)
    unit = buy_price(entry)
    max = [max, (money / unit).floor].min if unit > 0
    max = [max, 1].min if ReloadedMart::Limits.one_time?(entry)
    max = [max, 0].max
    return max if max <= 0
    handler = ReloadedMart.entry_handler(entry.kind) || ReloadedMart::EntryHandler.new(entry.kind)
    max.downto(1) do |qty|
      grants = handler.grants_for(entry, qty, context)
      return qty if ReloadedMart::Inventory.can_store_grants?(grants).ok?
    end
    0
  rescue Exception => e
    ReloadedMart.log_exception("Mart UI max quantity failed for #{entry&.id}", e)
    0
  end

  def build_cart(entry, quantity)
    ReloadedMart::Transactions.build_cart(entry, quantity, context)
  end

  def complete_purchase(entry, quantity)
    ReloadedMart::Transactions.complete_cart(build_cart(entry, quantity), context)
  end

  def banner_text
    ReloadedMart::UI.banner_text(context, visible_entries)
  end

  def bundle_preview_lines(entry)
    return [] unless entry && entry.bundle_like?
    return ["Contents: ???", "Items are revealed after purchase."] if mystery_box?(entry)
    lines = ["Will receive:"]
    Array(entry.grants).each do |grant|
      item_id = grant.is_a?(Hash) ? (grant["id"] || grant[:id] || grant["item"] || grant[:item]) : grant
      qty = grant.is_a?(Hash) ? (grant["qty"] || grant[:qty] || grant["quantity"] || grant[:quantity] || 1).to_i : 1
      data = GameData::Item.try_get(item_id) rescue nil
      owned = data ? ReloadedMart::Inventory.quantity(data.id) : 0
      label = data ? data.name : item_id.to_s
      lines << "#{label} x#{qty}   Owned: #{owned}"
    end
    lines
  end

  def bundle_preview_text(entry, hidden: true)
    return "???" if hidden && mystery_box?(entry)
    bundle_preview_lines(entry).join(", ")
  end

  def mark_seen
    report = ReloadedMart::Source.active_report
    ReloadedMart.mark_catalog_seen(report.catalog_version) if report
  rescue
  end

  private

  def ordered_category_ids
    raw = ReloadedMart::Source.active_raw || {}
    categories = Array(raw["categories"] || raw[:categories]).select { |cat| cat.is_a?(Hash) }
    known = {}
    result = categories.map do |cat|
      id = (cat["id"] || cat[:id] || cat["name"] || cat[:name]).to_s
      name = (cat["name"] || cat[:name] || id).to_s
      known[id] = true
      { :id => id, :name => name }
    end
    featured_config = ReloadedMart::Economy.daily_featured_config
    featured_id = ReloadedMart::Economy.daily_featured_category_id(featured_config)
    featured_name = ReloadedMart::Economy.daily_featured_category_name(featured_config)
    if visible_entries.any? { |entry| entry.category_id.to_s == featured_id.to_s } && !known[featured_id.to_s]
      known[featured_id.to_s] = true
      result.unshift({ :id => featured_id.to_s, :name => featured_name.to_s })
    end
    visible_entries.each do |entry|
      next if known[entry.category_id.to_s]
      known[entry.category_id.to_s] = true
      result << { :id => entry.category_id.to_s, :name => entry.category_name.to_s.empty? ? entry.category_id.to_s.upcase : entry.category_name.to_s }
    end
    result
  end

  def same_category?(entry, category)
    entry.category_id.to_s == category[:id].to_s || entry.category_name.to_s.casecmp(category[:name].to_s) == 0
  end

  def sort_entries(entries, sort_mode)
    type_priority = lambda do |entry|
      next 0 if entry.kind == :gift
      next 1 if mystery_box?(entry)
      next 2 if entry.kind == :bundle
      3
    end
    case sort_mode.to_sym
    when :price_low
      entries.sort_by { |entry| [type_priority.call(entry), buy_price(entry), display_name(entry).downcase] }
    when :price_high
      entries.sort_by { |entry| [type_priority.call(entry), -buy_price(entry), display_name(entry).downcase] }
    when :stock
      entries.sort_by { |entry| [type_priority.call(entry), stock_remaining(entry).nil? ? 1 : 0, stock_remaining(entry).to_i, display_name(entry).downcase] }
    else
      entries.sort_by { |entry| [type_priority.call(entry), display_name(entry).downcase] }
    end
  end
end

class ReloadedMartBuyScene
  include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

  SW = 512
  SH = 384
  TITLE_H = 24
  POCKET_H = 22
  FOOTER_H = 22
  INFO_H = 112
  PAD = 8
  LIST_Y = TITLE_H + POCKET_H
  LIST_H = SH - TITLE_H - POCKET_H - INFO_H - FOOTER_H
  ROW_H = 24

  BG_COLOR = Color.new(18, 22, 34, 255)
  PANEL_BG = Color.new(28, 34, 52)
  PANEL_BORDER = Color.new(60, 80, 130)
  ROW_HOVER = Color.new(255, 255, 255, 14)
  WHITE = Color.new(255, 255, 255)
  GRAY = Color.new(175, 180, 200)
  DIM = Color.new(105, 110, 135)
  SHADOW = Color.new(10, 12, 22)
  GOLD = Color.new(240, 200, 80)
  GREEN = Color.new(100, 215, 80)
  RED = Color.new(220, 80, 80)
  BLUE = Color.new(120, 190, 255)
  PINK = Color.new(255, 160, 210)
  PURPLE = Color.new(190, 130, 255)
  ORANGE = Color.new(255, 170, 70)
  FOOTER_BG = Color.new(20, 24, 40)
  POCKET_BG = Color.new(25, 30, 48)
  INFO_BG = Color.new(22, 28, 46)
  INFO_BORDER = Color.new(55, 75, 125)
  SEP = Color.new(50, 65, 110)

  @@last_pocket_index = 0
  @@last_entry_index = 0
  @@last_sort_mode = 0
  @@last_quick_buy = false

  attr_reader :quick_buy

  def initialize
    @viewport = nil
    @bg_sprite = nil
    @title_sprite = nil
    @pocket_sprite = nil
    @list_sprite = nil
    @info_sprite = nil
    @footer_sprite = nil
    @icon_sprite = nil
    @special_icon_sprite = nil
    @adapter = nil
    @pockets = []
    @pocket_index = 0
    @entry_index = 0
    @scroll = 0
    @sort_index = @@last_sort_mode
    @quick_buy = @@last_quick_buy
    @money_display = 0
    @money_start = 0
    @money_target = 0
    @money_frame = 0
    @money_duration = 0
    @qty_display = 0.0
    @qty_target = 0
    @qty_start = 0.0
    @qty_frame = 0
    @qty_duration = 0
    @banner_offset = 0.0
    @cursor_pulse = 0
    @bundle_scroll = 0
    @last_mx = nil
    @last_my = nil
  end

  def pbStartBuyScene(adapter)
    @adapter = adapter
    @money_display = adapter.money
    @money_start = adapter.money
    @money_target = adapter.money
    Graphics.freeze
    setup_sprites
    rebuild_pockets
    if @pockets.empty?
      draw_all
      Graphics.transition(8)
      show_message("The Reloaded Mart has nothing in stock right now.")
      pbEndBuyScene
      return false
    end
    @pocket_index = @@last_pocket_index.clamp(0, [@pockets.length - 1, 0].max)
    @entry_index = @@last_entry_index.clamp(0, [current_entries.length - 1, 0].max)
    ensure_visible
    snap_quantity
    draw_all
    Graphics.transition(8)
    true
  end

  def pbEndBuyScene
    @adapter.mark_seen if @adapter
    Graphics.freeze
    teardown
    Graphics.transition(8)
  end

  def pbChooseBuyEntry
    loop do
      Graphics.update
      Input.update
      tick_money_anim
      tick_qty_anim
      tick_banner
      tick_cursor

      return nil if @pockets.empty?
      handle_category_input
      handle_entry_input
      handle_mode_input
      handle_mouse

      if Input.trigger?(Input::BACK)
        pbPlayCancelSE rescue nil
        remember_cursor
        return nil
      elsif Input.trigger?(Input::USE)
        entry = current_entries[@entry_index]
        remember_cursor
        return entry if entry
      end
    end
  end

  def pbChooseBuyNumber(entry, maximum)
    return 0 if maximum <= 0
    return 1 if maximum == 1
    unit = @adapter.buy_price(entry)
    cur = 1
    result = 0
    dim = Sprite.new(@viewport)
    dim.z = 950
    dim.bitmap = Bitmap.new(SW, SH)
    dim.bitmap.fill_rect(0, 0, SW, SH, Color.new(0, 0, 0, 140))
    box_w = 340
    box_h = 96
    box_x = (SW - box_w) / 2
    box_y = (SH - box_h) / 2
    box = Sprite.new(@viewport)
    box.z = 951
    box.x = box_x
    box.y = box_y
    box.bitmap = Bitmap.new(box_w, box_h)
    loop do
      cur = cur.clamp(1, maximum)
      bitmap = box.bitmap
      bitmap.clear
      draw_panel(bitmap, 0, 0, box_w, box_h)
      pbSetSmallFont(bitmap)
      shadow_text(bitmap, PAD, 10, box_w - PAD * 2, 20, @adapter.display_name(entry), WHITE)
      shadow_text(bitmap, PAD, 32, box_w / 2, 20, "x#{cur}", WHITE)
      shadow_text(bitmap, 0, 32, box_w - PAD, 20, ReloadedMart.format_currency(unit * cur), unit <= 0 ? GREEN : RED, 2)
      bitmap.fill_rect(PAD, 56, box_w - PAD * 2, 1, SEP)
      bitmap.font.size = 16
      shadow_text(bitmap, PAD, 62, box_w - PAD * 2, 18, "Confirm (C) Back (B) Adjust (< >) Quantity (Up Down)", WHITE)
      Graphics.update
      Input.update
      if Input.trigger?(Input::BACK)
        result = 0
        break
      elsif Input.trigger?(Input::USE)
        result = cur
        break
      elsif Input.repeat?(Input::UP)
        pbPlayCursorSE rescue nil
        cur = cur >= maximum ? 1 : cur + 1
      elsif Input.repeat?(Input::DOWN)
        pbPlayCursorSE rescue nil
        cur = cur <= 1 ? maximum : cur - 1
      elsif Input.repeat?(Input::RIGHT)
        pbPlayCursorSE rescue nil
        cur = [cur + 10, maximum].min
      elsif Input.repeat?(Input::LEFT)
        pbPlayCursorSE rescue nil
        cur = [cur - 10, 1].max
      end
      mx, my = mouse_pos
      if mx && my
        if (Input.repeat?(Input::SCROLLUP) rescue false)
          pbPlayCursorSE rescue nil
          cur = cur >= maximum ? 1 : cur + 1
        elsif (Input.repeat?(Input::SCROLLDOWN) rescue false)
          pbPlayCursorSE rescue nil
          cur = cur <= 1 ? maximum : cur - 1
        elsif (Input.trigger?(Input::MOUSELEFT) rescue false)
          result = mx.between?(box_x, box_x + box_w) && my.between?(box_y, box_y + box_h) ? cur : 0
          break
        elsif (Input.trigger?(Input::MOUSERIGHT) rescue false)
          result = 0
          break
        end
      end
    end
    box.bitmap.dispose rescue nil
    box.dispose rescue nil
    dim.bitmap.dispose rescue nil
    dim.dispose rescue nil
    result
  end

  def pbConfirmPurchase(entry, quantity, total)
    return true if ($PokemonSystem.hr_mart_confirm rescue 1).to_i == 0
    choices = [_INTL("Yes"), _INTL("No")]
    selected = 0
    result = false
    line_h = 18
    pad = 12
    box_w = 340
    box_h = pad * 2 + line_h * 3 + 13 + line_h * choices.length
    box_x = (SW - box_w) / 2
    box_y = (SH - box_h) / 2
    choices_y = pad + line_h * 3 + 13
    dim = Sprite.new(@viewport)
    dim.z = 960
    dim.bitmap = Bitmap.new(SW, SH)
    dim.bitmap.fill_rect(0, 0, SW, SH, Color.new(0, 0, 0, 140))
    box = Sprite.new(@viewport)
    box.z = 961
    box.x = box_x
    box.y = box_y
    box.bitmap = Bitmap.new(box_w, box_h)
    loop do
      bitmap = box.bitmap
      bitmap.clear
      draw_panel(bitmap, 0, 0, box_w, box_h)
      pbSetSmallFont(bitmap)
      shadow_text(bitmap, pad, pad, box_w - pad * 2, line_h, "Confirm Purchase?", WHITE)
      qty_label = quantity > 1 ? "#{@adapter.display_name(entry)}  x#{quantity}" : @adapter.display_name(entry)
      shadow_text(bitmap, pad, pad + line_h + 4, box_w - pad * 2, line_h, qty_label, GRAY)
      shadow_text(bitmap, pad, pad + line_h * 2 + 4, box_w / 2, line_h, "Each: #{@adapter.buy_price_str(entry)}", DIM)
      shadow_text(bitmap, 0, pad + line_h * 2 + 4, box_w - pad, line_h, ReloadedMart.format_currency(total), total <= 0 ? GREEN : RED, 2)
      bitmap.fill_rect(pad, choices_y - 4, box_w - pad * 2, 1, SEP)
      @cursor_pulse = (@cursor_pulse + 1) % 60
      draw_modal_choices(bitmap, choices, selected, pad, choices_y, box_w - pad * 2, line_h)
      Graphics.update
      Input.update
      selected = (selected - 1) % choices.length if Input.trigger?(Input::UP)
      selected = (selected + 1) % choices.length if Input.trigger?(Input::DOWN)
      mx, my = mouse_pos
      if mx && my && my.between?(box_y + choices_y, box_y + choices_y + line_h * choices.length - 1)
        selected = ((my - (box_y + choices_y)) / line_h).clamp(0, choices.length - 1)
      end
      if Input.trigger?(Input::USE) || (Input.trigger?(Input::MOUSELEFT) rescue false)
        result = selected == 0
        break
      elsif Input.trigger?(Input::BACK) || (Input.trigger?(Input::MOUSERIGHT) rescue false)
        result = false
        break
      end
    end
    box.bitmap.dispose rescue nil
    box.dispose rescue nil
    dim.bitmap.dispose rescue nil
    dim.dispose rescue nil
    result
  end

  def animate_purchase
    fps = (Graphics.frame_rate rescue 40).to_f
    @money_start = @money_display
    @money_target = @adapter.money
    @money_frame = 0
    @money_duration = (fps * ReloadedMart::UI::MONEY_ANIMATION_SECONDS).round
    rebuild_pockets
    @pocket_index = [@pocket_index, @pockets.length - 1].min
    @entry_index = [@entry_index, [current_entries.length - 1, 0].max].min
    ensure_visible
    @qty_start = @qty_display
    @qty_target = selected_entry ? @adapter.in_bag_qty(selected_entry) : 0
    @qty_frame = 0
    @qty_duration = (fps * ReloadedMart::UI::QUANTITY_ANIMATION_SECONDS).round
    draw_all
  end

  def play_purchase_animation
    animate_purchase
    frames = [@money_duration, @qty_duration].max
    frames.times do
      Graphics.update
      Input.update
      tick_money_anim
      tick_qty_anim
      tick_banner
      @cursor_pulse = (@cursor_pulse + 1) % 60
      draw_list
    end
    @money_display = @money_target
    @qty_display = @qty_target
    @money_frame = @money_duration
    @qty_frame = @qty_duration
    draw_all
  end

  def pbDisplayPaused(message)
    yield if block_given?
    show_message(message)
  end

  private

  def setup_sprites
    @viewport = Viewport.new(0, 0, SW, SH)
    @viewport.z = 100_000
    @bg_sprite = Sprite.new(@viewport)
    @bg_sprite.bitmap = Bitmap.new(SW, SH)
    @bg_sprite.bitmap.fill_rect(0, 0, SW, SH, BG_COLOR)
    @title_sprite = new_sprite(0, 0, SW, TITLE_H)
    @pocket_sprite = new_sprite(0, TITLE_H, SW, POCKET_H)
    @list_sprite = new_sprite(0, LIST_Y, SW, LIST_H)
    @info_sprite = new_sprite(0, LIST_Y + LIST_H, SW, INFO_H)
    @footer_sprite = new_sprite(0, SH - FOOTER_H, SW, FOOTER_H)
    @icon_sprite = ItemIconSprite.new(SW - PAD - 48, LIST_Y + LIST_H + 52, nil, @viewport) rescue nil
    if @icon_sprite
      @icon_sprite.z = 20
      @icon_sprite.zoom_x = 1.5
      @icon_sprite.zoom_y = 1.5
    end
    @special_icon_sprite = Sprite.new(@viewport) rescue nil
    if @special_icon_sprite
      @special_icon_sprite.z = 21
      @special_icon_sprite.x = SW - PAD - 96
      @special_icon_sprite.y = LIST_Y + LIST_H + 4
      @special_icon_sprite.visible = false
    end
  end

  def new_sprite(x, y, width, height)
    sprite = Sprite.new(@viewport)
    sprite.z = 10
    sprite.x = x
    sprite.y = y
    sprite.bitmap = Bitmap.new(width, [height, 1].max)
    sprite
  end

  def teardown
    [@footer_sprite, @info_sprite, @list_sprite, @pocket_sprite, @title_sprite, @bg_sprite].each do |sprite|
      next unless sprite
      sprite.bitmap.dispose rescue nil
      sprite.dispose rescue nil
    end
    @icon_sprite.dispose rescue nil
    if @special_icon_sprite
      @special_icon_sprite.bitmap.dispose rescue nil
      @special_icon_sprite.dispose rescue nil
    end
    @viewport.dispose rescue nil
    @viewport = nil
  end

  def rebuild_pockets
    mode = ReloadedMart::UI::SORT_MODES[@sort_index] || :name
    @pockets = @adapter.categories(mode)
    @pocket_index = @pocket_index.clamp(0, [@pockets.length - 1, 0].max)
    @entry_index = @entry_index.clamp(0, [current_entries.length - 1, 0].max)
    @scroll = @scroll.clamp(0, [current_entries.length - rows_per_page, 0].max)
  end

  def current_entries
    return [] if @pockets.empty?
    @pockets[@pocket_index][:entries] || []
  end

  def selected_entry
    current_entries[@entry_index]
  end

  def rows_per_page
    (LIST_H / ROW_H).floor
  end

  def ensure_visible
    rows = rows_per_page
    return if current_entries.empty?
    @scroll = @entry_index if @entry_index < @scroll
    @scroll = @entry_index - rows + 1 if @entry_index >= @scroll + rows
    @scroll = @scroll.clamp(0, [current_entries.length - rows, 0].max)
  end

  def remember_cursor
    @@last_pocket_index = @pocket_index
    @@last_entry_index = @entry_index
  end

  def snap_quantity
    @qty_display = selected_entry ? @adapter.in_bag_qty(selected_entry) : 0
    @qty_target = @qty_display
    @qty_start = @qty_display
    @qty_frame = 0
    @qty_duration = 0
  end

  def handle_category_input
    if Input.trigger?(Input::LEFT)
      pbPlayCursorSE rescue nil
      @pocket_index = (@pocket_index - 1) % @pockets.length
      @entry_index = 0
      @scroll = 0
      @bundle_scroll = 0
      snap_quantity
      draw_pocket_nav
      draw_list
      draw_info
    elsif Input.trigger?(Input::RIGHT)
      pbPlayCursorSE rescue nil
      @pocket_index = (@pocket_index + 1) % @pockets.length
      @entry_index = 0
      @scroll = 0
      @bundle_scroll = 0
      snap_quantity
      draw_pocket_nav
      draw_list
      draw_info
    end
  end

  def handle_entry_input
    entries = current_entries
    return if entries.empty?
    if Input.repeat?(Input::UP)
      pbPlayCursorSE rescue nil
      @entry_index = (@entry_index - 1) % entries.length
      ensure_visible
      @bundle_scroll = 0
      snap_quantity
      draw_list
      draw_info
    elsif Input.repeat?(Input::DOWN)
      pbPlayCursorSE rescue nil
      @entry_index = (@entry_index + 1) % entries.length
      ensure_visible
      @bundle_scroll = 0
      snap_quantity
      draw_list
      draw_info
    end
  end

  def handle_mode_input
    if Input.trigger?(Input::JUMPUP)
      pbPlayCursorSE rescue nil
      @sort_index = (@sort_index + 1) % ReloadedMart::UI::SORT_MODES.length
      @@last_sort_mode = @sort_index
      rebuild_pockets
      snap_quantity
      draw_all
    elsif Input.trigger?(Input::JUMPDOWN)
      pbPlayCursorSE rescue nil
      @quick_buy = !@quick_buy
      @@last_quick_buy = @quick_buy
      draw_footer
    elsif Input.trigger?(Input::ACTION)
      entry = selected_entry
      if entry
        @adapter.toggle_favorite(entry)
        preserve_entry_after_rebuild(entry)
      end
    end
  end

  def preserve_entry_after_rebuild(entry)
    category_name = @pockets[@pocket_index][:name] rescue nil
    rebuild_pockets
    found_category = @pockets.index { |pocket| pocket[:name] == category_name }
    @pocket_index = found_category if found_category
    found_entry = current_entries.index { |row| row.id == entry.id }
    @entry_index = found_entry if found_entry
    @entry_index = @entry_index.clamp(0, [current_entries.length - 1, 0].max)
    ensure_visible
    snap_quantity
    draw_all
  end

  def handle_mouse
    mx, my = mouse_pos
    return unless mx && my
    moved = (mx != @last_mx || my != @last_my)
    @last_mx = mx
    @last_my = my
    entries = current_entries
    if (Input.repeat?(Input::SCROLLUP) rescue false)
      if info_bundle_scroll_area?(mx, my)
        scroll_bundle_preview(-1)
        return
      end
      return if entries.empty?
      pbPlayCursorSE rescue nil
      @entry_index = [@entry_index - 1, 0].max
      ensure_visible
      snap_quantity
      draw_list
      draw_info
    elsif (Input.repeat?(Input::SCROLLDOWN) rescue false)
      if info_bundle_scroll_area?(mx, my)
        scroll_bundle_preview(1)
        return
      end
      return if entries.empty?
      pbPlayCursorSE rescue nil
      @entry_index = [@entry_index + 1, [entries.length - 1, 0].max].min
      ensure_visible
      snap_quantity
      draw_list
      draw_info
    end
    if my.between?(TITLE_H, TITLE_H + POCKET_H - 1) && (Input.trigger?(Input::MOUSELEFT) rescue false)
      pbPlayCursorSE rescue nil
      @pocket_index = (mx < SW / 2) ? (@pocket_index - 1) % @pockets.length : (@pocket_index + 1) % @pockets.length
      @entry_index = 0
      @scroll = 0
      snap_quantity
      draw_pocket_nav
      draw_list
      draw_info
      return
    end
    if my.between?(LIST_Y, LIST_Y + LIST_H - 1)
      row_index = (my - LIST_Y) / ROW_H
      real_index = @scroll + row_index
      if real_index < entries.length
        if moved && real_index != @entry_index
          pbPlayCursorSE rescue nil
          @entry_index = real_index
          ensure_visible
          @bundle_scroll = 0
          snap_quantity
          draw_list
          draw_info
        end
        if (Input.trigger?(Input::MOUSELEFT) rescue false)
          remember_cursor
          throw :reloaded_mart_mouse_pick, entries[@entry_index]
        end
      end
    elsif my.between?(SH - FOOTER_H, SH - 1) && (Input.trigger?(Input::MOUSELEFT) rescue false)
      @quick_buy = !@quick_buy
      @@last_quick_buy = @quick_buy
      draw_footer
    end
  end

  def info_bundle_scroll_area?(mx, my)
    entry = selected_entry
    entry && entry.bundle_like? && mx && my && my.between?(LIST_Y + LIST_H, SH - FOOTER_H - 1)
  rescue
    false
  end

  def scroll_bundle_preview(delta)
    entry = selected_entry
    return unless entry && entry.bundle_like?
    count = normalized_bundle_grants(entry).length
    max_scroll = [count - 4, 0].max
    @bundle_scroll = (@bundle_scroll + delta.to_i).clamp(0, max_scroll)
    draw_info
  end

  def mouse_pos
    return nil unless defined?(Mouse)
    Mouse.getMousePos
  rescue
    nil
  end

  def draw_all
    draw_title
    draw_pocket_nav
    draw_list
    draw_info
    draw_footer
  end

  def draw_title
    bitmap = @title_sprite.bitmap
    bitmap.clear
    bitmap.fill_rect(0, 0, SW, TITLE_H, FOOTER_BG)
    pbSetSmallFont(bitmap)
    banner = @adapter.banner_text
    return if banner.to_s.empty?
    bitmap.font.size = 16
    x = PAD - @banner_offset.to_i
    width = bitmap.text_size(banner).width + 80
    while x < SW
      shadow_text(bitmap, x, 6, width, 16, banner, GOLD)
      x += width
    end
  end

  def draw_pocket_nav
    bitmap = @pocket_sprite.bitmap
    bitmap.clear
    bitmap.fill_rect(0, 0, SW, POCKET_H, POCKET_BG)
    bitmap.fill_rect(0, POCKET_H - 1, SW, 1, SEP)
    return if @pockets.empty?
    pbSetSmallFont(bitmap)
    pocket = @pockets[@pocket_index]
    title = @adapter.respond_to?(:ui_title) ? @adapter.ui_title : "RLD Mart"
    shadow_text(bitmap, PAD, -1, 102, POCKET_H, title, WHITE)
    shadow_text(bitmap, 102, -1, SW - 204, POCKET_H, "#{pocket[:name]}  (#{@pocket_index + 1}/#{@pockets.length})", WHITE, 1)
    shadow_text(bitmap, 0, -1, SW - PAD, POCKET_H, ReloadedMart.format_currency(@money_display), GREEN, 2)
  end

  def draw_list
    bitmap = @list_sprite.bitmap
    bitmap.clear
    bitmap.fill_rect(0, 0, SW, LIST_H, PANEL_BG)
    entries = current_entries
    return if entries.empty?
    rows = rows_per_page
    pbSetSmallFont(bitmap)
    entries[@scroll, rows].each_with_index do |entry, i|
      real_index = @scroll + i
      y = i * ROW_H
      selected = real_index == @entry_index
      if selected
        draw_cursor(bitmap, PAD, y + 2, SW - PAD * 2, ROW_H - 4)
      else
        bitmap.fill_rect(PAD, y + 2, SW - PAD * 2, ROW_H - 4, ROW_HOVER)
      end
      draw_entry_row(bitmap, entry, y, selected)
    end
    draw_scrollbar(bitmap, entries.length, rows)
    bitmap.fill_rect(0, LIST_H - 1, SW, 1, SEP)
  end

  def draw_entry_row(bitmap, entry, y, selected)
    locked = @adapter.locked?(entry)
    maxed = @adapter.maxed?(entry)
    free = @adapter.buy_price(entry) <= 0
    favorite = @adapter.favorite?(entry)
    name = row_label(entry, favorite)
    color = row_color(entry, selected, locked, favorite)
    price_str = if locked
      "Locked"
    elsif maxed
      "MAX"
    elsif free
      "FREE"
    else
      @adapter.buy_price_str(entry)
    end
    price_badge = !locked && !maxed && !free && @adapter.price_overridden?(entry) ? price_change_badge(bitmap, entry) : nil
    price_w = bitmap.text_size(price_str).width
    price_badge_w = price_badge ? price_badge[:width] + 4 : 0
    price_limit_x = SW - PAD - 10 - price_w - price_badge_w
    name_w = [bitmap.text_size(name).width, [price_limit_x - PAD - 12, 24].max].min
    shadow_text(bitmap, PAD + 6, y, name_w + 4, ROW_H, trim_text(bitmap, name, name_w), color)
    badge_x = PAD + 10 + name_w
    badges = row_badges(entry).first(ReloadedMart::UI::ROW_BADGE_LIMIT)
    badges.each do |badge|
      next if badge_x >= price_limit_x - 6
      badge_x = draw_badge(bitmap, badge_x + 4, y + 5, badge[:label], badge[:color], price_limit_x)
    end
    price_color = locked ? DIM : (free ? GREEN : (selected ? GOLD : GRAY))
    right = SW - PAD - 4
    price_x = right - price_w
    if price_badge
      badge_x = price_x - price_badge[:width] - 4
      draw_price_change_badge(bitmap, badge_x, y + 5, price_badge) if badge_x > PAD
      price_color = price_badge[:color]
    end
    shadow_text(bitmap, 0, y, right, ROW_H, price_str, price_color, 2)
  end

  def row_label(entry, favorite)
    prefix = case entry.kind
             when :bundle then @adapter.mystery_box?(entry) ? "[?] " : "[B] "
             when :gift then "[G] "
             when :service then "[S] "
             when :unlock then "[U] "
             when :coupon then "[C] "
             else ""
    end
    marks = ""
    marks += "* " if favorite
    "#{marks}#{prefix}#{@adapter.display_name(entry)}"
  end

  def row_badges(entry)
    badges = []
    badges << { :label => "NEW!", :color => BLUE } if @adapter.new?(entry)
    badges << { :label => "FEATURED", :color => GOLD } if @adapter.daily_featured?(entry)
    badges << { :label => "LIMITED", :color => RED } if @adapter.limited_time_text(entry) || !@adapter.stock_remaining(entry).nil?
    badges << { :label => "LAST", :color => RED } if stock_label(entry) == "LAST"
    badges
  end

  def row_color(entry, selected, locked, favorite)
    return DIM if locked
    return WHITE if selected
    return PINK if entry.kind == :gift
    return PURPLE if @adapter.mystery_box?(entry)
    return BLUE if entry.kind == :bundle
    return ORANGE if entry.kind == :service
    return RED if entry.kind == :unlock
    return GOLD if favorite
    GRAY
  end

  def price_change_badge(bitmap, entry)
    base = @adapter.base_price(entry).to_i
    final = @adapter.buy_price(entry).to_i
    return nil if base <= 0 || final == base
    pct = ((final - base).abs * 100.0 / base).round
    return nil if pct <= 0
    label = final < base ? "#{pct}% OFF" : "#{pct}% MORE"
    color = final < base ? GREEN : RED
    { :label => label, :color => color, :width => badge_width(bitmap, label) }
  rescue
    nil
  end

  def badge_width(bitmap, label)
    bitmap.font.size = 14
    bitmap.text_size(label.to_s).width + 14
  rescue
    label.to_s.length * 7 + 14
  ensure
    pbSetSmallFont(bitmap) rescue nil
  end

  def draw_price_change_badge(bitmap, x, y, badge)
    width = badge[:width].to_i
    color = badge[:color] || GREEN
    bitmap.font.size = 14 rescue nil
    bitmap.fill_rect(x, y, width, 14, Color.new(color.red / 3, color.green / 3, color.blue / 3, 170))
    shadow_text(bitmap, x + 7, y - 2, width - 14, 16, badge[:label], color, 1)
  rescue
  ensure
    pbSetSmallFont(bitmap) rescue nil
  end

  def stock_label(entry)
    remaining = @adapter.stock_remaining(entry)
    return nil if remaining.nil?
    return "LAST" if remaining == 1
    "x#{remaining}"
  end

  def draw_info
    bitmap = @info_sprite.bitmap
    bitmap.clear
    bitmap.fill_rect(0, 0, SW, INFO_H, INFO_BG)
    bitmap.fill_rect(0, INFO_H - 1, SW, 1, INFO_BORDER)
    entry = selected_entry
    unless entry
      @icon_sprite.item = nil if @icon_sprite
      @special_icon_sprite.visible = false if @special_icon_sprite
      shadow_text(bitmap, PAD, INFO_H / 2 - 8, SW - PAD * 2, 20, "Nothing to buy here.", DIM)
      return
    end
    icon_x = SW - PAD - 96
    draw_icon_box(bitmap, icon_x, 4, 96, 96)
    if @icon_sprite
      @icon_sprite.visible = entry.kind == :item
      @icon_sprite.item = @adapter.icon_item(entry) if entry.kind == :item
    end
    draw_special_icon(entry)
    pbSetSmallFont(bitmap)
    shadow_text(bitmap, PAD, 4, icon_x - PAD * 2 - 4, 20, @adapter.display_name(entry), WHITE)
    time_text = @adapter.limited_time_text(entry)
    if time_text && !time_text.to_s.empty?
      bitmap.font.size = 14
      shadow_text(bitmap, PAD + 112, 6, icon_x - PAD * 2 - 166, 14, time_text, GOLD, 1)
      pbSetSmallFont(bitmap)
    end
    meta = info_meta(entry)
    shadow_text(bitmap, PAD, 4, icon_x - PAD - 10, 20, meta, meta_color(entry), 2)
    bitmap.fill_rect(PAD + 2, 27, icon_x - PAD - 4, 1, SEP)
    draw_info_body(bitmap, entry, icon_x)
  end

  def draw_special_icon(entry)
    return unless @special_icon_sprite
    @special_icon_sprite.visible = false
    @special_icon_sprite.bitmap.dispose rescue nil
    @special_icon_sprite.bitmap = nil
    return unless entry && entry.bundle_like?
    path = entry.kind == :gift ? "Reloaded/Graphics/Icons/gift" : "Reloaded/Graphics/Icons/bundle"
    bitmap = Bitmap.new(path) rescue nil
    return unless bitmap
    scale = [48.0 / [bitmap.width, bitmap.height, 1].max, 1.5].min
    box_x = SW - PAD - 96
    box_y = LIST_Y + LIST_H + 4
    @special_icon_sprite.bitmap = bitmap
    @special_icon_sprite.zoom_x = scale
    @special_icon_sprite.zoom_y = scale
    @special_icon_sprite.x = box_x + ((96 - bitmap.width * scale) / 2).round
    @special_icon_sprite.y = box_y + ((96 - bitmap.height * scale) / 2).round
    @special_icon_sprite.visible = true
  end

  def info_meta(entry)
    if entry.bundle_like?
      entry.kind == :gift ? "Gift" : (@adapter.mystery_box?(entry) ? "Mystery Box" : "Bundle")
    elsif entry.kind == :item
      "In Bag: #{@qty_display.round}"
    else
      entry.kind.to_s.capitalize
    end
  end

  def meta_color(entry)
    return PINK if entry.kind == :gift
    return PURPLE if @adapter.mystery_box?(entry)
    return BLUE if entry.kind == :bundle
    return ORANGE if entry.kind == :service
    return RED if entry.kind == :unlock
    GRAY
  end

  def draw_info_body(bitmap, entry, icon_x)
    x = PAD
    y = 34
    width = icon_x - PAD * 2 - 4
    if @adapter.locked?(entry)
      wrap_text(@adapter.lock_text(entry), width, bitmap).first(4).each do |line|
        shadow_text(bitmap, x, y, width, 16, line, DIM)
        y += 16
      end
      return
    end
    if entry.bundle_like?
      draw_bundle_preview(bitmap, entry, x, y, width)
    else
      pbSetSmallFont(bitmap)
      bitmap.font.size = 16
      stock = @adapter.stock_remaining(entry)
      unless stock.nil?
        shadow_text(bitmap, x, y, width, 18, "Stock: #{stock}", GOLD)
        y += 18
      end
      wrap_text(@adapter.description(entry), width, bitmap).first(4).each do |line|
        shadow_text(bitmap, x, y, width, 18, line, GRAY)
        y += 18
      end
    end
    details = []
    details << "Restock: #{@adapter.restock_text(entry)}" if @adapter.restock_text(entry)
    shadow_text(bitmap, x, INFO_H - 20, width, 16, details.compact.join("  "), GOLD) unless details.compact.empty?
  end

  def draw_bundle_preview(bitmap, entry, x, y, width)
    pbSetSmallFont(bitmap)
    bitmap.font.size = 16
    if @adapter.mystery_box?(entry)
      shadow_text(bitmap, x, y, width, 18, "Contents: ???", GRAY)
      shadow_text(bitmap, x, y + 18, width, 18, "Items are revealed after purchase.", GRAY)
      return
    end
    grants = normalized_bundle_grants(entry)
    visible_rows = 4
    @bundle_scroll = @bundle_scroll.clamp(0, [grants.length - visible_rows, 0].max)
    shadow_text(bitmap, x, y, width, 15, "Will receive:", WHITE)
    stock = @adapter.stock_remaining(entry)
    shadow_text(bitmap, 0, y, x + width, 15, "Stock: #{stock}", GOLD, 2) unless stock.nil?
    y += 15
    item_w = width - 86
    grants[@bundle_scroll, visible_rows].to_a.each do |grant|
      label = grant[:quantity] > 1 ? "#{grant[:name]} x#{grant[:quantity]}" : grant[:name]
      shadow_text(bitmap, x + 6, y, item_w, 14, trim_text(bitmap, label, item_w), GRAY)
      shadow_text(bitmap, x + item_w, y, 82, 14, "Owned: #{grant[:owned]}", DIM, 2)
      y += 14
    end
    if grants.length > visible_rows
      hint = "#{@bundle_scroll + 1}-#{[@bundle_scroll + visible_rows, grants.length].min}/#{grants.length}"
      shadow_text(bitmap, x, INFO_H - 20, width, 16, hint, GOLD, 2)
    end
  end

  def normalized_bundle_grants(entry)
    Array(entry.grants).map do |grant|
      item_id = grant.is_a?(Hash) ? (grant["id"] || grant[:id] || grant["item"] || grant[:item]) : grant
      qty = grant.is_a?(Hash) ? (grant["qty"] || grant[:qty] || grant["quantity"] || grant[:quantity] || 1).to_i : 1
      data = GameData::Item.try_get(item_id) rescue nil
      next nil unless data
      { :name => data.name, :quantity => qty, :owned => ReloadedMart::Inventory.quantity(data.id) }
    end.compact
  end

  def draw_footer
    bitmap = @footer_sprite.bitmap
    bitmap.clear
    bitmap.fill_rect(0, 0, SW, FOOTER_H, FOOTER_BG)
    pbSetSmallFont(bitmap)
    bitmap.font.size = 16
    sort_name = sort_label
    quick = @quick_buy ? "On" : "Off"
    hint = "Buy (C) Back (B) Favorite (A) Sort: #{sort_name} (L) Quick Buy: #{quick} (R)"
    shadow_text(bitmap, PAD, 2, SW - PAD * 2, FOOTER_H - 2, trim_text(bitmap, hint, SW - PAD * 2), WHITE)
  end

  def sort_label
    case ReloadedMart::UI::SORT_MODES[@sort_index]
    when :price_low then "Price Low"
    when :price_high then "Price High"
    when :stock then "Stock"
    else "Name"
    end
  end

  def draw_scrollbar(bitmap, total, visible)
    return if total <= visible
    track_h = LIST_H - 4
    bar_h = [((visible.to_f / total) * track_h).round, 6].max
    bar_y = ((@scroll.to_f / [total - visible, 1].max) * (track_h - bar_h)).round
    bitmap.fill_rect(SW - 5, 2, 3, track_h, DIM)
    bitmap.fill_rect(SW - 5, 2 + bar_y, 3, bar_h, GRAY)
  end

  def tick_money_anim
    return if @money_duration <= 0 || @money_frame >= @money_duration
    @money_frame += 1
    t = @money_frame.to_f / @money_duration
    eased = 1.0 - ((1.0 - t) * (1.0 - t))
    @money_display = (@money_start + (@money_target - @money_start) * eased).round
    draw_pocket_nav
  end

  def tick_qty_anim
    return if @qty_duration <= 0 || @qty_frame >= @qty_duration
    @qty_frame += 1
    t = @qty_frame.to_f / @qty_duration
    eased = 1.0 - ((1.0 - t) * (1.0 - t))
    @qty_display = @qty_start + (@qty_target - @qty_start) * eased
    draw_info
  end

  def tick_banner
    banner = @adapter.banner_text
    return if banner.to_s.empty?
    width = @title_sprite.bitmap.text_size(banner).width + 80 rescue 240
    @banner_offset = (@banner_offset + 0.8) % [width, 1].max
    draw_title
  end

  def tick_cursor
    @cursor_pulse = (@cursor_pulse + 1) % 60
    draw_list
  rescue
  end

  def draw_panel(bitmap, x, y, width, height)
    bitmap.fill_rect(x, y, width, height, PANEL_BG)
    bitmap.fill_rect(x, y, width, 1, PANEL_BORDER)
    bitmap.fill_rect(x, y + height - 1, width, 1, PANEL_BORDER)
    bitmap.fill_rect(x, y, 1, height, PANEL_BORDER)
    bitmap.fill_rect(x + width - 1, y, 1, height, PANEL_BORDER)
  end

  def draw_cursor(bitmap, x, y, width, height)
    if respond_to?(:reloaded_draw_rounded_rect)
      pulse = ((Math.sin((@cursor_pulse || 0) / 60.0 * Math::PI * 2) + 1.0) * 0.5)
      fill_alpha = (72 + pulse * 58).round
      border_alpha = (150 + pulse * 80).round
      reloaded_draw_rounded_rect(bitmap, x, y, width, height, 4,
        reloaded_with_alpha(reloaded_cursor_fill, fill_alpha),
        reloaded_with_alpha(reloaded_cursor_border, border_alpha))
    else
      bitmap.fill_rect(x, y, width, height, Color.new(80, 100, 160))
    end
  end

  def draw_modal_choices(bitmap, choices, selected, x, y, width, line_h)
    choices.each_with_index do |choice, i|
      row_y = y + i * line_h
      draw_cursor(bitmap, x, row_y + 3, width, line_h) if i == selected
      color = i == selected ? WHITE : GRAY
      shadow_text(bitmap, x + 8, row_y, width - 16, line_h, choice, color)
    end
  end

  def draw_icon_box(bitmap, x, y, width, height)
    bitmap.fill_rect(x, y, width, height, Color.new(15, 18, 30))
    bitmap.fill_rect(x, y, width, 1, INFO_BORDER)
    bitmap.fill_rect(x, y + height - 1, width, 1, INFO_BORDER)
    bitmap.fill_rect(x, y, 1, height, INFO_BORDER)
    bitmap.fill_rect(x + width - 1, y, 1, height, INFO_BORDER)
  end

  def draw_badge(bitmap, x, y, label, color, max_x = SW - 150)
    bitmap.font.size = 14
    width = bitmap.text_size(label).width + 8
    return x if x + width > max_x
    bitmap.fill_rect(x, y, width, 14, Color.new(color.red / 3, color.green / 3, color.blue / 3, 170))
    shadow_text(bitmap, x + 4, y - 2, width - 8, 16, label, color, 1)
    x + width
  rescue
    x
  ensure
    pbSetSmallFont(bitmap) rescue nil
  end

  def shadow_text(bitmap, x, y, width, height, text, color, align = 0)
    pbDrawShadowText(bitmap, x, y, width, height, text.to_s, color, SHADOW, align)
  rescue
  end

  def trim_text(bitmap, text, max_width)
    value = text.to_s
    return value if bitmap.text_size(value).width <= max_width
    ellipsis = "..."
    while value.length > 0 && bitmap.text_size(value + ellipsis).width > max_width
      value = value[0...-1]
    end
    value + ellipsis
  rescue
    text.to_s
  end

  def wrap_text(text, width, bitmap)
    words = text.to_s.split(/\s+/)
    lines = []
    line = ""
    words.each do |word|
      test = line.empty? ? word : "#{line} #{word}"
      if bitmap.text_size(test).width <= width
        line = test
      else
        lines << line unless line.empty?
        line = word
      end
    end
    lines << line unless line.empty?
    lines.empty? ? [""] : lines
  rescue
    [text.to_s]
  end

  def show_message(message)
    return pbMessage(message) if !@viewport && defined?(pbMessage)
    box_w = 360
    pad = 12
    line_h = 18
    measure = Bitmap.new(1, 1)
    pbSetSmallFont(measure)
    lines = []
    message.to_s.split(/\n/).each do |part|
      lines.concat(wrap_text(part, box_w - pad * 2, measure))
    end
    measure.dispose rescue nil
    lines = [""] if lines.empty?
    box_h = [pad * 2 + line_h * lines.length + 18, 68].max
    box_x = (SW - box_w) / 2
    box_y = (SH - box_h) / 2
    dim = Sprite.new(@viewport)
    dim.z = 970
    dim.bitmap = Bitmap.new(SW, SH)
    dim.bitmap.fill_rect(0, 0, SW, SH, Color.new(0, 0, 0, 70))
    box = Sprite.new(@viewport)
    box.z = 971
    box.x = box_x
    box.y = box_y
    box.bitmap = Bitmap.new(box_w, box_h)
    bitmap = box.bitmap
    draw_panel(bitmap, 0, 0, box_w, box_h)
    pbSetSmallFont(bitmap)
    y = pad
    lines.each do |line|
      shadow_text(bitmap, pad, y, box_w - pad * 2, line_h, line, WHITE)
      y += line_h
    end
    bitmap.font.size = 16
    shadow_text(bitmap, pad, box_h - pad - 16, box_w - pad * 2, 16, "Confirm (C)", GRAY, 2)
    loop do
      Graphics.update
      Input.update
      break if Input.trigger?(Input::USE) || Input.trigger?(Input::BACK) ||
               (Input.trigger?(Input::MOUSELEFT) rescue false) ||
               (Input.trigger?(Input::MOUSERIGHT) rescue false)
    end
  rescue
    pbMessage(message) if defined?(pbMessage)
  ensure
    box.bitmap.dispose rescue nil
    box.dispose rescue nil
    dim.bitmap.dispose rescue nil
    dim.dispose rescue nil
    draw_all rescue nil
  end
end

class ReloadedMartBuyScreen
  def initialize(scene, adapter)
    @scene = scene
    @adapter = adapter
  end

  def pbBuyScreen
    return unless @scene.pbStartBuyScene(@adapter)
    loop do
      entry = catch(:reloaded_mart_mouse_pick) { @scene.pbChooseBuyEntry }
      break unless entry
      handle_entry(entry)
    end
    @scene.pbEndBuyScene
  rescue Exception => e
    raise if e.is_a?(SystemExit)
    ReloadedMart.log_exception("Reloaded Mart buy screen failed", e)
    @scene.pbEndBuyScene rescue nil
    pbMessage(_INTL("The Reloaded Mart is unavailable right now.")) rescue nil
  end

  def handle_entry(entry)
    if @adapter.locked?(entry)
      @scene.pbDisplayPaused(_INTL(@adapter.lock_text(entry)))
      return
    end
    max = @adapter.max_quantity(entry)
    if max <= 0
      message = @adapter.buy_price(entry) > @adapter.money ? "You don't have enough money." : "There isn't enough room in the Bag."
      @scene.pbDisplayPaused(_INTL(message))
      return
    end
    quantity = @scene.quick_buy ? max : @scene.pbChooseBuyNumber(entry, max)
    return if quantity <= 0
    total = @adapter.buy_price(entry) * quantity
    return unless @scene.pbConfirmPurchase(entry, quantity, total)
    result = @adapter.complete_purchase(entry, quantity)
    if result.ok?
      pbSEPlay("Mart buy item") rescue nil
      @scene.play_purchase_animation
      show_mystery_box_result(entry, result) if @adapter.mystery_box?(entry)
    else
      @scene.pbDisplayPaused(_INTL(result.message.to_s.empty? ? "The transaction could not be completed." : result.message))
      @scene.animate_purchase
    end
  end

  def show_mystery_box_result(entry, result)
    applied = Array(result.details[:applied] || result.details["applied"])
    return if applied.empty?
    lines = applied.map do |grant|
      data = GameData::Item.try_get(grant[:item_id] || grant["item_id"]) rescue nil
      next nil unless data
      qty = (grant[:quantity] || grant["quantity"] || 1).to_i
      qty > 1 ? "#{data.name} x#{qty}" : data.name
    end.compact
    return if lines.empty?
    @scene.pbDisplayPaused(_INTL("{1} contained:\n{2}", @adapter.display_name(entry), lines.join("\n")))
  rescue Exception => e
    ReloadedMart.log_exception("Mystery Box reveal failed", e)
  end
end

class ReloadedMartSellAdapter
  KEY_ITEMS_POCKET = 8
  SORT_MODES = [:name, :price_high, :price_low].freeze

  def initialize
    @price_cache = {}
  end

  def pocket_names
    PokemonBag.pocketNames rescue []
  end

  def num_pockets
    PokemonBag.numPockets rescue 0
  end

  def pockets(sort_mode = :name)
    rows = []
    1.upto(num_pockets) do |pocket|
      next if pocket == KEY_ITEMS_POCKET
      items = items_in_pocket(pocket)
      next if items.empty?
      rows << {
        :id => :"pocket_#{pocket}",
        :name => pocket_names[pocket] || "Pocket #{pocket}",
        :entries => sort_items(items, sort_mode)
      }
    end
    rows
  end

  def items_in_pocket(pocket)
    return [] unless defined?($PokemonBag) && $PokemonBag
    bag_pocket = $PokemonBag.pockets[pocket]
    return [] unless bag_pocket
    bag_pocket.map { |slot| slot[0] }.select { |item| can_sell?(item) && quantity(item) > 0 }
  rescue
    []
  end

  def can_sell?(item)
    data = item_data(item)
    return false unless data
    return false if data.is_important?
    sell_price(item) > 0
  rescue
    false
  end

  def item_data(item)
    GameData::Item.try_get(item) rescue nil
  end

  def display_name(item)
    data = item_data(item)
    return item.to_s unless data
    name = data.name
    name = "#{name} #{GameData::Move.get(data.move).name}" if data.is_machine? && data.move rescue name
    name
  end

  def description(item)
    item_data(item)&.description.to_s
  rescue
    ""
  end

  def quantity(item)
    ReloadedMart::Inventory.quantity(item)
  end

  def money
    ReloadedMart::Inventory.money
  end

  def price_result(item)
    id = item_data(item)&.id || item
    @price_cache[id] ||= ReloadedMart::Pricing.price_for(sell_entry(item), context)
  end

  def sell_price(item)
    [price_result(item).final.to_i, 0].max
  end

  def base_sell_price(item)
    data = item_data(item)
    data ? (data.price.to_i / 2).floor : 0
  end

  def sell_price_str(item)
    ReloadedMart.format_currency(sell_price(item))
  end

  def complete_sale(item, quantity)
    ReloadedMart::Transactions.complete_sale(item, quantity, sell_price(item), context)
  end

  def context
    { :source => :reloaded_mart, :mode => :sell }
  end

  def ui_title
    "SELL ITEMS"
  end

  def banner_text
    ReloadedMart::UI.banner_text(context, [])
  end

  def sort_items(items, sort_mode)
    case sort_mode.to_sym
    when :price_high
      items.sort_by { |item| [-sell_price(item), display_name(item).downcase] }
    when :price_low
      items.sort_by { |item| [sell_price(item), display_name(item).downcase] }
    else
      items.sort_by { |item| display_name(item).downcase }
    end
  end

  private

  def sell_entry(item)
    data = item_data(item)
    pocket = data ? data.pocket : 0
    ReloadedMart::CatalogEntry.new(
      :id => "sell:#{data ? data.id : item}",
      :kind => :item,
      :name => display_name(item),
      :category_id => "pocket_#{pocket}",
      :category_name => pocket_names[pocket] || "Pocket #{pocket}",
      :tags => ["sell", "pocket_#{pocket}"],
      :price => data ? data.price.to_i : 0,
      :sell_price => base_sell_price(item),
      :currency => :money,
      :raw => { "item" => data ? data.id : item }
    )
  end
end

class ReloadedMartSellScene < ReloadedMartBuyScene
  @@last_sell_pocket_index = 0
  @@last_sell_item_index = 0
  @@last_sell_sort_index = 0

  attr_reader :sell_all_mode

  def initialize
    super
    @sell_all_mode = false
    @sort_index = @@last_sell_sort_index
  end

  def pbStartSellScene(adapter)
    @adapter = adapter
    @money_display = adapter.money
    @money_start = adapter.money
    @money_target = adapter.money
    Graphics.freeze
    setup_sprites
    rebuild_sell_pockets
    if @pockets.empty?
      draw_all
      Graphics.transition(8)
      show_message("Your Bag has nothing to sell right now.")
      pbEndSellScene
      return false
    end
    @pocket_index = @@last_sell_pocket_index.clamp(0, [@pockets.length - 1, 0].max)
    @entry_index = @@last_sell_item_index.clamp(0, [current_entries.length - 1, 0].max)
    ensure_visible
    snap_quantity
    draw_all
    Graphics.transition(8)
    true
  end

  def pbEndSellScene
    Graphics.freeze
    teardown
    Graphics.transition(8)
  end

  def pbChooseSellItem
    loop do
      Graphics.update
      Input.update
      tick_money_anim
      tick_qty_anim
      tick_banner
      tick_cursor
      return nil if @pockets.empty?
      handle_sell_category_input
      handle_sell_item_input
      handle_sell_mode_input
      handle_sell_mouse
      if Input.trigger?(Input::BACK)
        pbPlayCancelSE rescue nil
        remember_sell_cursor
        return nil
      elsif Input.trigger?(Input::USE)
        item = current_entries[@entry_index]
        remember_sell_cursor
        return item if item
      end
    end
  end

  def pbChooseSellNumber(item, maximum)
    return 0 if maximum <= 0
    return 1 if maximum == 1
    unit = @adapter.sell_price(item)
    cur = 1
    result = 0
    dim = Sprite.new(@viewport)
    dim.z = 950
    dim.bitmap = Bitmap.new(SW, SH)
    dim.bitmap.fill_rect(0, 0, SW, SH, Color.new(0, 0, 0, 140))
    box_w = 340
    box_h = 96
    box_x = (SW - box_w) / 2
    box_y = (SH - box_h) / 2
    box = Sprite.new(@viewport)
    box.z = 951
    box.x = box_x
    box.y = box_y
    box.bitmap = Bitmap.new(box_w, box_h)
    loop do
      cur = cur.clamp(1, maximum)
      bitmap = box.bitmap
      bitmap.clear
      draw_panel(bitmap, 0, 0, box_w, box_h)
      pbSetSmallFont(bitmap)
      shadow_text(bitmap, PAD, 10, box_w - PAD * 2, 20, @adapter.display_name(item), WHITE)
      shadow_text(bitmap, PAD, 32, box_w / 2, 20, "x#{cur}", WHITE)
      shadow_text(bitmap, 0, 32, box_w - PAD, 20, ReloadedMart.format_currency(unit * cur), GREEN, 2)
      bitmap.fill_rect(PAD, 56, box_w - PAD * 2, 1, SEP)
      bitmap.font.size = 16
      shadow_text(bitmap, PAD, 62, box_w - PAD * 2, 18, "Confirm (C) Back (B) Adjust (< >) Quantity (Up Down)", WHITE)
      Graphics.update
      Input.update
      if Input.trigger?(Input::BACK)
        result = 0
        break
      elsif Input.trigger?(Input::USE)
        result = cur
        break
      elsif Input.repeat?(Input::UP)
        pbPlayCursorSE rescue nil
        cur = cur >= maximum ? 1 : cur + 1
      elsif Input.repeat?(Input::DOWN)
        pbPlayCursorSE rescue nil
        cur = cur <= 1 ? maximum : cur - 1
      elsif Input.repeat?(Input::RIGHT)
        pbPlayCursorSE rescue nil
        cur = [cur + 10, maximum].min
      elsif Input.repeat?(Input::LEFT)
        pbPlayCursorSE rescue nil
        cur = [cur - 10, 1].max
      end
      mx, my = mouse_pos
      if mx && my
        if (Input.repeat?(Input::SCROLLUP) rescue false)
          pbPlayCursorSE rescue nil
          cur = cur >= maximum ? 1 : cur + 1
        elsif (Input.repeat?(Input::SCROLLDOWN) rescue false)
          pbPlayCursorSE rescue nil
          cur = cur <= 1 ? maximum : cur - 1
        elsif (Input.trigger?(Input::MOUSELEFT) rescue false)
          result = mx.between?(box_x, box_x + box_w) && my.between?(box_y, box_y + box_h) ? cur : 0
          break
        elsif (Input.trigger?(Input::MOUSERIGHT) rescue false)
          result = 0
          break
        end
      end
    end
    box.bitmap.dispose rescue nil
    box.dispose rescue nil
    dim.bitmap.dispose rescue nil
    dim.dispose rescue nil
    result
  end

  def pbConfirmSale(item, quantity, total)
    return true if ($PokemonSystem.hr_mart_confirm rescue 1).to_i == 0
    choices = [_INTL("Yes"), _INTL("No")]
    selected = 0
    result = false
    line_h = 18
    pad = 12
    box_w = 340
    box_h = pad * 2 + line_h * 3 + 13 + line_h * choices.length
    box_x = (SW - box_w) / 2
    box_y = (SH - box_h) / 2
    choices_y = pad + line_h * 3 + 13
    dim = Sprite.new(@viewport)
    dim.z = 960
    dim.bitmap = Bitmap.new(SW, SH)
    dim.bitmap.fill_rect(0, 0, SW, SH, Color.new(0, 0, 0, 140))
    box = Sprite.new(@viewport)
    box.z = 961
    box.x = box_x
    box.y = box_y
    box.bitmap = Bitmap.new(box_w, box_h)
    loop do
      bitmap = box.bitmap
      bitmap.clear
      draw_panel(bitmap, 0, 0, box_w, box_h)
      pbSetSmallFont(bitmap)
      shadow_text(bitmap, pad, pad, box_w - pad * 2, line_h, "Confirm Sale?", WHITE)
      qty_label = quantity > 1 ? "#{@adapter.display_name(item)}  x#{quantity}" : @adapter.display_name(item)
      shadow_text(bitmap, pad, pad + line_h + 4, box_w - pad * 2, line_h, qty_label, GRAY)
      shadow_text(bitmap, pad, pad + line_h * 2 + 4, box_w / 2, line_h, "Each: #{@adapter.sell_price_str(item)}", DIM)
      shadow_text(bitmap, 0, pad + line_h * 2 + 4, box_w - pad, line_h, ReloadedMart.format_currency(total), GREEN, 2)
      bitmap.fill_rect(pad, choices_y - 4, box_w - pad * 2, 1, SEP)
      @cursor_pulse = (@cursor_pulse + 1) % 60
      draw_modal_choices(bitmap, choices, selected, pad, choices_y, box_w - pad * 2, line_h)
      Graphics.update
      Input.update
      selected = (selected - 1) % choices.length if Input.trigger?(Input::UP)
      selected = (selected + 1) % choices.length if Input.trigger?(Input::DOWN)
      mx, my = mouse_pos
      if mx && my && my.between?(box_y + choices_y, box_y + choices_y + line_h * choices.length - 1)
        selected = ((my - (box_y + choices_y)) / line_h).clamp(0, choices.length - 1)
      end
      if Input.trigger?(Input::USE) || (Input.trigger?(Input::MOUSELEFT) rescue false)
        result = selected == 0
        break
      elsif Input.trigger?(Input::BACK) || (Input.trigger?(Input::MOUSERIGHT) rescue false)
        result = false
        break
      end
    end
    box.bitmap.dispose rescue nil
    box.dispose rescue nil
    dim.bitmap.dispose rescue nil
    dim.dispose rescue nil
    result
  end

  def animate_sale
    fps = (Graphics.frame_rate rescue 40).to_f
    @money_start = @money_display
    @money_target = @adapter.money
    @money_frame = 0
    @money_duration = (fps * ReloadedMart::UI::MONEY_ANIMATION_SECONDS).round
    rebuild_sell_pockets
    return false if @pockets.empty?
    @pocket_index = [@pocket_index, @pockets.length - 1].min
    @entry_index = [@entry_index, [current_entries.length - 1, 0].max].min
    ensure_visible
    @qty_start = @qty_display
    @qty_target = selected_entry ? @adapter.quantity(selected_entry) : 0
    @qty_frame = 0
    @qty_duration = (fps * ReloadedMart::UI::QUANTITY_ANIMATION_SECONDS).round
    draw_all
    true
  end

  def play_sale_animation
    return false unless animate_sale
    frames = [@money_duration, @qty_duration].max
    frames.times do
      Graphics.update
      Input.update
      tick_money_anim
      tick_qty_anim
      tick_banner
      @cursor_pulse = (@cursor_pulse + 1) % 60
      draw_list
    end
    @money_display = @money_target
    @qty_display = @qty_target
    @money_frame = @money_duration
    @qty_frame = @qty_duration
    draw_all
    true
  end

  def draw_title
    super
  end

  def draw_list
    bitmap = @list_sprite.bitmap
    bitmap.clear
    bitmap.fill_rect(0, 0, SW, LIST_H, PANEL_BG)
    items = current_entries
    return if items.empty?
    rows = rows_per_page
    pbSetSmallFont(bitmap)
    items[@scroll, rows].each_with_index do |item, i|
      real_index = @scroll + i
      y = i * ROW_H
      selected = real_index == @entry_index
      if selected
        draw_cursor(bitmap, PAD, y + 2, SW - PAD * 2, ROW_H - 4)
      else
        bitmap.fill_rect(PAD, y + 2, SW - PAD * 2, ROW_H - 4, ROW_HOVER)
      end
      name = @adapter.display_name(item)
      price = @sell_all_mode ? @adapter.sell_price(item) * @adapter.quantity(item) : @adapter.sell_price(item)
      price_str = ReloadedMart.format_currency(price)
      price_color = @sell_all_mode && selected ? RED : (selected ? GOLD : WHITE)
      shadow_text(bitmap, PAD + 6, y, SW * 3 / 4, ROW_H, trim_text(bitmap, name, SW * 3 / 4 - PAD), selected ? WHITE : GRAY)
      shadow_text(bitmap, 0, y, SW - PAD - 4, ROW_H, price_str, price_color, 2)
    end
    draw_scrollbar(bitmap, items.length, rows)
    bitmap.fill_rect(0, LIST_H - 1, SW, 1, SEP)
  end

  def draw_info
    bitmap = @info_sprite.bitmap
    bitmap.clear
    bitmap.fill_rect(0, 0, SW, INFO_H, INFO_BG)
    bitmap.fill_rect(0, INFO_H - 1, SW, 1, INFO_BORDER)
    item = selected_entry
    unless item
      @icon_sprite.item = nil if @icon_sprite
      @special_icon_sprite.visible = false if @special_icon_sprite
      shadow_text(bitmap, PAD, INFO_H / 2 - 8, SW - PAD * 2, 20, "Nothing to sell here.", DIM)
      return
    end
    icon_x = SW - PAD - 96
    draw_icon_box(bitmap, icon_x, 4, 96, 96)
    if @icon_sprite
      @icon_sprite.visible = true
      @icon_sprite.item = item
    end
    pbSetSmallFont(bitmap)
    shadow_text(bitmap, PAD, 4, icon_x - PAD * 2 - 4, 20, @adapter.display_name(item), WHITE)
    shadow_text(bitmap, PAD, 4, icon_x - PAD - 10, 20, "x#{@qty_display.round}", WHITE, 2)
    bitmap.fill_rect(PAD + 2, 27, icon_x - PAD - 4, 1, SEP)
    y = 34
    width = icon_x - PAD * 2 - 4
    bitmap.font.size = 16
    wrap_text(@adapter.description(item), width, bitmap).first(4).each do |line|
      shadow_text(bitmap, PAD, y, width, 18, line, GRAY)
      y += 18
    end
  end

  def draw_footer
    bitmap = @footer_sprite.bitmap
    bitmap.clear
    bitmap.fill_rect(0, 0, SW, FOOTER_H, FOOTER_BG)
    pbSetSmallFont(bitmap)
    bitmap.font.size = 16
    sort = case ReloadedMartSellAdapter::SORT_MODES[@sort_index]
           when :price_high then "Price High"
           when :price_low then "Price Low"
           else "Name"
           end
    mode = @sell_all_mode ? "On" : "Off"
    hint = "Sell (C) Back (B) Page (< >) Sort: #{sort} (L) Sell-All: #{mode} (R)"
    shadow_text(bitmap, PAD, 2, SW - PAD * 2, FOOTER_H - 2, trim_text(bitmap, hint, SW - PAD * 2), WHITE)
  end

  private

  def rebuild_sell_pockets
    mode = ReloadedMartSellAdapter::SORT_MODES[@sort_index] || :name
    @pockets = @adapter.pockets(mode)
    @pocket_index = @pocket_index.clamp(0, [@pockets.length - 1, 0].max)
    @entry_index = @entry_index.clamp(0, [current_entries.length - 1, 0].max)
    @scroll = @scroll.clamp(0, [current_entries.length - rows_per_page, 0].max)
  end

  def handle_sell_category_input
    if Input.trigger?(Input::LEFT)
      pbPlayCursorSE rescue nil
      @pocket_index = (@pocket_index - 1) % @pockets.length
      @entry_index = 0
      @scroll = 0
      snap_quantity
      draw_pocket_nav
      draw_list
      draw_info
    elsif Input.trigger?(Input::RIGHT)
      pbPlayCursorSE rescue nil
      @pocket_index = (@pocket_index + 1) % @pockets.length
      @entry_index = 0
      @scroll = 0
      snap_quantity
      draw_pocket_nav
      draw_list
      draw_info
    end
  end

  def handle_sell_item_input
    items = current_entries
    return if items.empty?
    if Input.repeat?(Input::UP)
      pbPlayCursorSE rescue nil
      @entry_index = (@entry_index - 1) % items.length
      ensure_visible
      snap_quantity
      draw_list
      draw_info
    elsif Input.repeat?(Input::DOWN)
      pbPlayCursorSE rescue nil
      @entry_index = (@entry_index + 1) % items.length
      ensure_visible
      snap_quantity
      draw_list
      draw_info
    end
  end

  def handle_sell_mode_input
    if Input.trigger?(Input::JUMPUP)
      pbPlayCursorSE rescue nil
      @sort_index = (@sort_index + 1) % ReloadedMartSellAdapter::SORT_MODES.length
      @@last_sell_sort_index = @sort_index
      rebuild_sell_pockets
      snap_quantity
      draw_all
    elsif Input.trigger?(Input::JUMPDOWN)
      pbPlayCursorSE rescue nil
      @sell_all_mode = !@sell_all_mode
      draw_list
      draw_info
      draw_footer
    end
  end

  def handle_sell_mouse
    mx, my = mouse_pos
    return unless mx && my
    moved = (mx != @last_mx || my != @last_my)
    @last_mx = mx
    @last_my = my
    items = current_entries
    if (Input.repeat?(Input::SCROLLUP) rescue false)
      return if items.empty?
      pbPlayCursorSE rescue nil
      @entry_index = [@entry_index - 1, 0].max
      ensure_visible
      snap_quantity
      draw_list
      draw_info
    elsif (Input.repeat?(Input::SCROLLDOWN) rescue false)
      return if items.empty?
      pbPlayCursorSE rescue nil
      @entry_index = [@entry_index + 1, [items.length - 1, 0].max].min
      ensure_visible
      snap_quantity
      draw_list
      draw_info
    end
    if my.between?(TITLE_H, TITLE_H + POCKET_H - 1) && (Input.trigger?(Input::MOUSELEFT) rescue false)
      pbPlayCursorSE rescue nil
      @pocket_index = mx < SW / 2 ? (@pocket_index - 1) % @pockets.length : (@pocket_index + 1) % @pockets.length
      @entry_index = 0
      @scroll = 0
      snap_quantity
      draw_pocket_nav
      draw_list
      draw_info
      return
    end
    if my.between?(LIST_Y, LIST_Y + LIST_H - 1)
      row_index = (my - LIST_Y) / ROW_H
      real_index = @scroll + row_index
      if real_index < items.length
        if moved && real_index != @entry_index
          pbPlayCursorSE rescue nil
          @entry_index = real_index
          ensure_visible
          snap_quantity
          draw_list
          draw_info
        end
        if (Input.trigger?(Input::MOUSELEFT) rescue false)
          remember_sell_cursor
          throw :reloaded_mart_sell_mouse_pick, items[@entry_index]
        end
      end
    elsif my.between?(SH - FOOTER_H, SH - 1) && (Input.trigger?(Input::MOUSELEFT) rescue false)
      @sell_all_mode = !@sell_all_mode
      draw_list
      draw_info
      draw_footer
    end
  end

  def remember_sell_cursor
    @@last_sell_pocket_index = @pocket_index
    @@last_sell_item_index = @entry_index
  end

  def snap_quantity
    item = selected_entry
    quantity = item ? @adapter.quantity(item) : 0
    @qty_display = quantity.to_f
    @qty_target = quantity
    @qty_start = quantity.to_f
    @qty_frame = 0
    @qty_duration = 0
  end
end

class ReloadedMartSellScreen
  def initialize(scene, adapter)
    @scene = scene
    @adapter = adapter
  end

  def pbSellScreen
    return unless @scene.pbStartSellScene(@adapter)
    loop do
      item = catch(:reloaded_mart_sell_mouse_pick) { @scene.pbChooseSellItem }
      break unless item
      handle_item(item)
    end
    @scene.pbEndSellScene
  rescue Exception => e
    raise if e.is_a?(SystemExit)
    ReloadedMart.log_exception("Reloaded Mart sell screen failed", e)
    @scene.pbEndSellScene rescue nil
    pbMessage(_INTL("The Reloaded Mart is unavailable right now.")) rescue nil
  end

  def handle_item(item)
    unless @adapter.can_sell?(item)
      @scene.pbDisplayPaused(_INTL("{1}? Oh, no. I can't buy that.", @adapter.display_name(item)))
      return
    end
    owned = @adapter.quantity(item)
    return if owned <= 0
    quantity = @scene.sell_all_mode ? owned : @scene.pbChooseSellNumber(item, owned)
    return if quantity <= 0
    total = @adapter.sell_price(item) * quantity
    return unless @scene.pbConfirmSale(item, quantity, total)
    result = @adapter.complete_sale(item, quantity)
    if result.ok?
      pbSEPlay("Mart buy item") rescue nil
      return unless @scene.play_sale_animation
    else
      @scene.pbDisplayPaused(_INTL(result.message.to_s.empty? ? "The transaction could not be completed." : result.message))
      @scene.animate_sale
    end
  end
end

class ReloadedMartVanillaBuyAdapter < ReloadedMartBuyAdapter
  def initialize(stock, mart_adapter = nil)
    super()
    @mart_adapter = mart_adapter || PokemonMartAdapter.new
    @stock = normalize_stock(stock)
    @last_bonus_item = nil
  end

  def categories(sort_mode = :name)
    rows = sort_entries(visible_entries, sort_mode)
    rows.empty? ? [] : [{ :id => :stock, :name => "SHOP", :entries => rows }]
  end

  def visible_entries
    @stock.map { |item| entry_for(item) }.compact
  end

  def context
    { :source => :vanilla_mart, :mode => :buy, :vanilla => true }
  end

  def display_name(entry)
    data = item_data(entry)
    return entry.name unless data
    name = data.name
    name = "#{name} #{GameData::Move.get(data.move).name}" if data.is_machine? && data.move rescue name
    name
  end

  def description(entry)
    item_data(entry)&.description.to_s
  rescue
    ""
  end

  def price(entry)
    data = item_data(entry)
    value = data ? @mart_adapter.getPrice(data.id, false).to_i : 0
    base = data ? data.price.to_i : value
    ReloadedMart::PriceResult.new(base: base, catalog: value, final: value, currency: :money)
  end

  def max_quantity(entry)
    data = item_data(entry)
    return 0 unless data
    return 1 if data.is_important? && !ReloadedMart::Inventory.quantity(data.id).positive?
    max = Settings::BAG_MAX_PER_SLOT rescue 999
    unit = buy_price(entry)
    max = [max, (money / unit).floor].min if unit > 0
    max = [max, 0].max
    return 0 if max <= 0
    max.downto(1) do |qty|
      return qty if ReloadedMart::Inventory.can_store_grants?([{ :item_id => data.id, :quantity => qty }]).ok?
    end
    0
  rescue
    0
  end

  def maxed?(entry)
    data = item_data(entry)
    return false unless data
    !ReloadedMart::Inventory.can_store_grants?([{ :item_id => data.id, :quantity => 1 }]).ok?
  end

  def locked?(_entry); false; end
  def lock_text(_entry); ""; end
  def ui_title; "BUY ITEMS"; end
  def favorite?(_entry); false; end
  def toggle_favorite(_entry); false; end
  def stock_remaining(_entry); nil; end
  def restock_text(_entry); nil; end
  def limited_time_text(_entry); nil; end
  def daily_featured?(_entry); false; end
  def new?(_entry); false; end
  def banner_text
    ReloadedMart::UI.banner_text(context, visible_entries)
  end

  def complete_purchase(entry, quantity)
    data = item_data(entry)
    return ReloadedMart::TransactionResult.new(false, :missing_item, "That item is unavailable.") unless data
    qty = [quantity.to_i, 1].max
    total = buy_price(entry) * qty
    grants = [{ :item_id => data.id, :quantity => qty }]
    preflight = ReloadedMart::Inventory.can_store_grants?(grants)
    return preflight unless preflight.ok?
    charge = ReloadedMart::Inventory.charge(total)
    return charge unless charge.ok?
    applied = ReloadedMart::Inventory.apply_grants(grants)
    unless applied.ok?
      ReloadedMart::Inventory.refund(total)
      return applied
    end
    prune_owned_important_items
    @last_bonus_item = apply_bonus_item(data.id, qty)
    result = ReloadedMart::TransactionResult.new(true, :ok, "Purchase complete.", :applied => applied.details[:applied], :bonus_item => @last_bonus_item)
    ReloadedMart.emit(ReloadedMart::EVENT_PURCHASE_COMPLETED, {
      :source => :vanilla_mart,
      :catalog_version => ReloadedMart::DEFAULT_CATALOG_VERSION,
      :currency => :money,
      :entries => [{ :id => data.id, :kind => :item, :quantity => qty, :price => total }],
      :grants => grants,
      :total_price => total,
      :result => result.code,
      :message => result.message,
      :details => result.details
    })
    result
  rescue Exception => e
    raise if e.is_a?(SystemExit)
    ReloadedMart.log_exception("Vanilla mart purchase failed", e)
    ReloadedMart::TransactionResult.new(false, :exception, "The transaction could not be completed.")
  end

  def take_bonus_item
    item = @last_bonus_item
    @last_bonus_item = nil
    item
  end

  private

  def normalize_stock(stock)
    Array(stock).map do |item|
      data = GameData::Item.get(item) rescue nil
      next nil unless data
      next nil if data.is_important? && ReloadedMart::Inventory.quantity(data.id) > 0
      data.id
    end.compact
  end

  def prune_owned_important_items
    @stock = @stock.reject do |item|
      data = GameData::Item.try_get(item) rescue nil
      data && data.is_important? && ReloadedMart::Inventory.quantity(data.id) > 0
    end
  end

  def entry_for(item)
    data = GameData::Item.try_get(item) rescue nil
    return nil unless data
    ReloadedMart::CatalogEntry.new(
      :id => "vanilla:#{data.id}",
      :kind => :item,
      :name => data.name,
      :category_id => "stock",
      :category_name => "SHOP",
      :price => @mart_adapter.getPrice(data.id, false),
      :currency => :money,
      :raw => { "item" => data.id }
    )
  end

  def apply_bonus_item(item, quantity)
    return nil unless defined?($PokemonBag) && $PokemonBag
    return nil if quantity.to_i < 10
    bonus = nil
    data = GameData::Item.get(item) rescue nil
    if data && data.is_poke_ball?
      bonus = :PREMIERBALL
    elsif item == :DNASPLICERS || item == :SUPERSPLICERS
      bonus = :DNAREVERSER
    elsif item == :DNAREVERSER
      bonus = :DNASPLICERS
    end
    bonus_data = GameData::Item.try_get(bonus) rescue nil
    return nil unless bonus_data
    return nil unless ReloadedMart::Inventory.apply_grants([{ :item_id => bonus_data.id, :quantity => 1 }]).ok?
    bonus_data.id
  end
end

class ReloadedMartVanillaSellAdapter < ReloadedMartSellAdapter
  def initialize(mart_adapter = nil)
    super()
    @mart_adapter = mart_adapter || PokemonMartAdapter.new
  end

  def context
    { :source => :vanilla_mart, :mode => :sell, :vanilla => true }
  end

  def can_sell?(item)
    @mart_adapter.canSell?(item) rescue false
  end

  def sell_price(item)
    [(@mart_adapter.getPrice(item, true).to_i / 2).floor, 0].max
  end

  def base_sell_price(item)
    sell_price(item)
  end

  def price_result(item)
    value = sell_price(item)
    ReloadedMart::PriceResult.new(base: value, catalog: value, final: value, currency: :money)
  end
end

class ReloadedMartVanillaBuyScreen < ReloadedMartBuyScreen
  def handle_entry(entry)
    super
    bonus = @adapter.take_bonus_item if @adapter.respond_to?(:take_bonus_item)
    return unless bonus
    data = GameData::Item.try_get(bonus) rescue nil
    @scene.pbDisplayPaused(_INTL("I'll throw in a {1}, too.", data.name)) if data
  end
end

module ReloadedMart
  module Vanilla
    class << self
      def open(stock, speech_welcome = nil, cantsell = false, speech_bye = nil, speech_what_else = nil)
        mart_adapter = PokemonMartAdapter.new
        processed_stock = preprocess_stock(stock)
        commands = []
        cmd_buy = cmd_sell = cmd_quit = -1
        commands[cmd_buy = commands.length] = _INTL("Buy")
        commands[cmd_sell = commands.length] = _INTL("Sell") unless cantsell
        commands[cmd_quit = commands.length] = _INTL("Quit")
        cmd = pbMessage(speech_welcome || _INTL("Welcome! How may I serve you?"), commands, cmd_quit + 1)
        loop do
          if cmd == cmd_buy
            open_buy(processed_stock, mart_adapter)
          elsif cmd_sell >= 0 && cmd == cmd_sell
            open_sell(mart_adapter)
          else
            pbMessage(speech_bye || _INTL("Please come again!")) unless speech_bye == ""
            break
          end
          cmd = pbMessage(speech_what_else || _INTL("Is there anything else I can help you with?"), commands, cmd_quit + 1)
        end
        $game_temp.clear_mart_prices if defined?($game_temp) && $game_temp
        true
      rescue Exception => e
        raise if e.is_a?(SystemExit)
        ReloadedMart.log_exception("Vanilla mart REX wrapper failed", e)
        $game_temp.clear_mart_prices if defined?($game_temp) && $game_temp
        false
      end

      def preprocess_stock(stock)
        list = Array(stock)
        if defined?($game_switches) && $game_switches &&
           defined?(SWITCH_RANDOM_ITEMS_GENERAL) && defined?(SWITCH_RANDOM_SHOP_ITEMS) &&
           $game_switches[SWITCH_RANDOM_ITEMS_GENERAL] && $game_switches[SWITCH_RANDOM_SHOP_ITEMS] &&
           defined?(replaceShopStockWithRandomized)
          list = replaceShopStockWithRandomized(list)
        end
        list.map do |item|
          data = GameData::Item.get(item) rescue nil
          next nil unless data
          next nil if data.is_important? && defined?($PokemonBag) && $PokemonBag && $PokemonBag.pbHasItem?(data.id)
          data.id
        end.compact
      end

      def open_buy(stock, mart_adapter)
        adapter = ReloadedMartVanillaBuyAdapter.new(stock, mart_adapter)
        scene = ReloadedMartBuyScene.new
        screen = ReloadedMartVanillaBuyScreen.new(scene, adapter)
        screen.pbBuyScreen
      end

      def open_sell(mart_adapter)
        adapter = ReloadedMartVanillaSellAdapter.new(mart_adapter)
        scene = ReloadedMartSellScene.new
        screen = ReloadedMartSellScreen.new(scene, adapter)
        screen.pbSellScreen
      end
    end
  end
end

module ReloadedMart
  class << self
    def ui_ready?
      defined?(ReloadedMartBuyScene) && defined?(ReloadedMartBuyAdapter) &&
        defined?(ReloadedMartSellScene) && defined?(ReloadedMartSellAdapter)
    end

    def open_ui
      ReloadedMart::UI.open_buy
    end
  end
end

unless defined?($reloaded_mart_original_pbPokemonMart_aliased) && $reloaded_mart_original_pbPokemonMart_aliased
  alias reloaded_mart_original_pbPokemonMart pbPokemonMart if defined?(pbPokemonMart)
  $reloaded_mart_original_pbPokemonMart_aliased = true
end

def pbPokemonMart(stock, speech_welcome = nil, cantsell = false, speech_bye = nil, speech_what_else = nil)
  if defined?(ReloadedMart::Vanilla) && ReloadedMart.ui_ready?
    handled = ReloadedMart::Vanilla.open(stock, speech_welcome, cantsell, speech_bye, speech_what_else)
    return if handled
  end
  reloaded_mart_original_pbPokemonMart(stock, speech_welcome, cantsell, speech_bye, speech_what_else)
rescue Exception => e
  raise if e.is_a?(SystemExit)
  ReloadedMart.log_exception("pbPokemonMart REX wrapper failed; falling back to base mart", e) if defined?(ReloadedMart)
  reloaded_mart_original_pbPokemonMart(stock, speech_welcome, cantsell, speech_bye, speech_what_else)
end
