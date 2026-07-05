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
    BOX_ANIMATION_SPEED = 2.25
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
    catalog_rows = catalog_visible_entries
    daily_rows = daily_featured_rows(catalog_rows)
    rows = dedupe_entries(catalog_rows + daily_rows)
    groups = []
    favorite_rows = rows.select { |entry| ReloadedMart.favorite?(entry.id) }
    groups << { :id => :favorites, :name => ReloadedMart::UI::DEFAULT_CATEGORY_NAMES[:favorites], :entries => sort_entries(favorite_rows, sort_mode) } unless favorite_rows.empty?
    ordered_category_ids(rows, daily_rows).each do |category|
      entries = rows.select { |entry| same_category?(entry, category) }
      if featured_category?(category)
        entries = dedupe_entries(daily_rows + entries)
      end
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
    catalog_rows = catalog_visible_entries
    dedupe_entries(catalog_rows + daily_featured_rows(catalog_rows))
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
    item_display_name(data)
  end

  def item_display_name(data)
    return "" unless data
    name = data.name.to_s
    name = "#{name} #{GameData::Move.get(data.move).name}" if data.is_machine? && data.move rescue name
    name
  rescue
    data.respond_to?(:name) ? data.name.to_s : data.to_s
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
    max = ReloadedMart.bag_max_per_slot
    in_bag_qty(entry) >= max
  end

  def item_stack_remaining(entry)
    return nil unless entry && entry.kind == :item
    data = item_data(entry)
    return 0 unless data
    owned = ReloadedMart::Inventory.quantity(data.id)
    return 0 if data.is_important? && owned.positive?
    [ReloadedMart.bag_max_per_slot - owned.to_i, 0].max
  rescue
    nil
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
    max = ReloadedMart::Limits.max_per_purchase(entry) || ReloadedMart.bag_max_per_slot
    stock = stock_remaining(entry)
    max = [max, stock.to_i].min unless stock.nil?
    max = [max, 1].min if [:service, :unlock, :coupon].include?(entry.kind)
    unit = buy_price(entry)
    max = [max, (money / unit).floor].min if unit > 0
    max = [max, 1].min if ReloadedMart::Limits.one_time?(entry)
    max = [max, 0].max
    return max if max <= 0
    return mystery_box_max_quantity(entry, max) if mystery_box?(entry)
    remaining = item_stack_remaining(entry)
    unless remaining.nil?
      candidate = [max, remaining].min
      return 0 if candidate <= 0
      data = item_data(entry)
      return ReloadedMart::Inventory.can_store_grants?([{ :item_id => data.id, :quantity => candidate }]).ok? ? candidate : 0
    end
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

  def mystery_box_max_quantity(entry, max)
    possible_grants = Array(entry.grants).map do |grant|
      item_id, count = mystery_grant_item_and_quantity(grant)
      next nil if item_id.nil? || item_id.to_s.empty?
      { :item_id => item_id, :quantity => [count.to_i, 1].max }
    end.compact
    return max if possible_grants.empty?
    possible_grants.any? { |grant| ReloadedMart::Inventory.can_store_grants?([grant]).ok? } ? max : 0
  rescue Exception => e
    ReloadedMart.log_exception("Mystery Box max quantity failed for #{entry&.id}", e)
    0
  end

  def mystery_grant_item_and_quantity(grant)
    if grant.is_a?(Hash)
      item_id = grant["id"] || grant[:id] || grant["item"] || grant[:item] || grant["item_id"] || grant[:item_id]
      count = grant["qty"] || grant[:qty] || grant["quantity"] || grant[:quantity] || 1
    else
      item_id = grant
      count = 1
    end
    [item_id, count]
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
      label = data ? item_display_name(data) : item_id.to_s
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

  def catalog_visible_entries
    Array(ReloadedMart::Source.active_catalog).select do |entry|
      entry && entry.purchasable? && !ReloadedMart::Availability.hidden?(entry, context)
    end
  rescue
    []
  end

  def daily_featured_rows(catalog_rows = nil)
    ReloadedMart::Economy.daily_featured_entries(catalog_rows || catalog_visible_entries, context).select do |entry|
      entry && entry.purchasable? && !ReloadedMart::Availability.hidden?(entry, context)
    end
  rescue Exception => e
    ReloadedMart.log_exception("Daily featured UI rows failed", e)
    []
  end

  def dedupe_entries(rows)
    seen = {}
    Array(rows).select do |entry|
      next false unless entry
      next false if seen[entry.id.to_s]
      seen[entry.id.to_s] = true
      true
    end
  end

  def ordered_category_ids(rows = nil, daily_rows = nil)
    rows ||= visible_entries
    daily_rows ||= daily_featured_rows(rows)
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
    if (daily_rows.any? || rows.any? { |entry| entry_category_ids(entry).include?(featured_id.to_s) }) && !known[featured_id.to_s]
      known[featured_id.to_s] = true
      result.unshift({ :id => featured_id.to_s, :name => featured_name.to_s })
    end
    rows.each do |entry|
      entry_category_ids(entry).each do |category_id|
        next if known[category_id.to_s]
        known[category_id.to_s] = true
        result << { :id => category_id.to_s, :name => category_name_for(entry, category_id) }
      end
    end
    result
  end

  def same_category?(entry, category)
    entry_category_ids(entry).include?(category[:id].to_s) || entry.category_name.to_s.casecmp(category[:name].to_s) == 0
  end

  def featured_category?(category)
    config = ReloadedMart::Economy.daily_featured_config
    category[:id].to_s == ReloadedMart::Economy.daily_featured_category_id(config).to_s
  rescue
    false
  end

  def entry_category_ids(entry)
    ids = entry.respond_to?(:category_ids) ? Array(entry.category_ids) : []
    ids << entry.category_id if entry.respond_to?(:category_id)
    ids.map { |id| id.to_s }.reject(&:empty?).uniq
  end

  def category_name_for(entry, category_id)
    return entry.category_name.to_s if entry.category_id.to_s == category_id.to_s && !entry.category_name.to_s.empty?
    raw = ReloadedMart::Source.active_raw || {}
    category = Array(raw["categories"] || raw[:categories]).find do |cat|
      cat.is_a?(Hash) && (cat["id"] || cat[:id]).to_s == category_id.to_s
    end
    name = category && (category["name"] || category[:name])
    name.to_s.empty? ? category_id.to_s.upcase : name.to_s
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
  ROW_HOVER = Color.new(36, 44, 68, 255)
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
    @info_scroll = 0
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
      scroll = scroll_delta
      if scroll > 0
        pbPlayCursorSE rescue nil
        cur = cur >= maximum ? 1 : cur + 1
      elsif scroll < 0
        pbPlayCursorSE rescue nil
        cur = cur <= 1 ? maximum : cur - 1
      else
        mx, my = mouse_pos
        if mx && my && mouse_left_trigger?
          result = mx.between?(box_x, box_x + box_w) && my.between?(box_y, box_y + box_h) ? cur : 0
          break
        elsif mx && my && mouse_right_trigger?
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
      if Input.trigger?(Input::USE) || mouse_left_trigger?
        result = selected == 0
        break
      elsif Input.trigger?(Input::BACK) || mouse_right_trigger?
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

  def play_mystery_box_reveal(entry, result, adapter)
    return false unless ReloadedMart.box_animation_enabled?
    rows = mystery_box_reveal_rows(result)
    return false if rows.empty?
    overlay = Sprite.new(@viewport)
    overlay.z = 980
    overlay.bitmap = Bitmap.new(SW, SH)
    chest_sheet = load_box_animation_sheet(entry, :mystery_box)
    chest = create_box_animation_sprite(chest_sheet)
    icon = ItemIconSprite.new(SW / 2, 190, nil, @viewport) rescue nil
    if icon
      icon.z = 982
      icon.visible = false
      icon.item = rows.first[:item_id]
      icon.setOffset(PictureOrigin::Center) rescue nil
      icon.zoom_x = 1.35
      icon.zoom_y = 1.35
    end
    pbSEPlay("GUI naming tab swap start") rescue nil
    rows.each_with_index do |row, index|
      icon.visible = false if icon
      icon.item = row[:item_id] if icon
      result_state = play_mystery_box_single_reveal(overlay.bitmap, chest, icon, entry, row, index, rows.length, adapter)
      if result_state == :skip_all
        chest.visible = false if chest
        show_mystery_box_results(rows, index, "Mystery Box Results", true)
        break
      end
    end
    true
  rescue Exception => e
    ReloadedMart.log_exception("Mystery Box reveal animation failed", e)
    false
  ensure
    icon.dispose rescue nil
    chest.dispose rescue nil
    chest_sheet.dispose rescue nil
    overlay.bitmap.dispose rescue nil
    overlay.dispose rescue nil
    draw_all rescue nil
  end

  def play_bundle_reveal(entry, result, adapter)
    return false unless ReloadedMart.box_animation_enabled?
    rows = mystery_box_reveal_rows(result)
    return false if rows.empty?
    overlay = Sprite.new(@viewport)
    overlay.z = 980
    overlay.bitmap = Bitmap.new(SW, SH)
    chest_sheet = load_box_animation_sheet(entry, entry.kind == :gift ? :gift : :bundle)
    chest = create_box_animation_sprite(chest_sheet, 5)
    icons = create_bundle_reveal_icons(rows[0, 5])
    frame = 0
    ready = false
    arrive_se_played = false
    loop do
      Graphics.update
      Input.update
      frame += 1
      anim_frame = (frame * ReloadedMart::UI::BOX_ANIMATION_SPEED).round
      if Input.const_defined?(:ACTION) && Input.trigger?(Input::ACTION)
        ready = true
        anim_frame = 108
      elsif Input.trigger?(Input::USE) || mouse_left_trigger?
        break if ready
        frame = [frame, 64].max
        anim_frame = (frame * ReloadedMart::UI::BOX_ANIMATION_SPEED).round
      end
      update_box_animation_sprite(chest, anim_frame)
      update_bundle_reveal_item_sprites(icons, anim_frame)
      if !arrive_se_played && anim_frame >= 100
        play_box_reward_arrive_se
        arrive_se_played = true
      end
      ready = true if anim_frame >= 108
      draw_bundle_reveal_frame(overlay.bitmap, entry, rows, anim_frame, adapter, !chest.nil?, ready)
      icons.each { |sprite| sprite.update rescue nil }
    end
    chest.visible = false if chest
    show_mystery_box_results(rows, 0, entry.kind == :gift ? "Gift Contents" : "Bundle Contents", false)
    true
  rescue Exception => e
    ReloadedMart.log_exception("Bundle reveal animation failed", e)
    false
  ensure
    icons.each { |sprite| sprite.dispose rescue nil } if icons
    chest.dispose rescue nil
    chest_sheet.dispose rescue nil
    overlay.bitmap.dispose rescue nil
    overlay.dispose rescue nil
    draw_all rescue nil
  end

  def play_mystery_box_single_reveal(bitmap, chest, icon, entry, row, index, total_rows, adapter)
    frame = 0
    revealed = false
    closing_ready = false
    arrive_se_played = false
    loop do
      Graphics.update
      Input.update
      frame += 1
      anim_frame = (frame * ReloadedMart::UI::BOX_ANIMATION_SPEED).round
      if anim_frame >= 82 && !revealed
        revealed = true
        pbSEPlay("Mining reveal full") rescue pbSEPlay("Item get") rescue nil
      end
      if Input.const_defined?(:ACTION) && Input.trigger?(Input::ACTION)
        return :skip_all
      elsif Input.trigger?(Input::USE) || mouse_left_trigger?
        if revealed && closing_ready
          break
        else
          frame = [frame, 70].max
          anim_frame = (frame * ReloadedMart::UI::BOX_ANIMATION_SPEED).round
          revealed = true
          closing_ready = true
        end
      end
      closing_ready = true if revealed && anim_frame >= 132
      update_reveal_item_sprite(icon, anim_frame, revealed)
      if revealed && !arrive_se_played && anim_frame >= 106
        play_box_reward_arrive_se
        arrive_se_played = true
      end
      update_box_animation_sprite(chest, anim_frame)
      draw_mystery_box_reveal_frame(bitmap, entry, row, index, total_rows, anim_frame, revealed, adapter, !chest.nil?)
      icon.update if icon
    end
    true
  end

  def pbDisplayPaused(message)
    yield if block_given?
    show_message(message)
  end

  def mystery_box_reveal_rows(result)
    details = result && result.respond_to?(:details) ? result.details : {}
    raw = Array(details[:revealed] || details["revealed"] || details[:applied] || details["applied"])
    raw.map do |grant|
      item_id = grant[:item_id] || grant["item_id"] || grant[:id] || grant["id"] || grant[:item] || grant["item"]
      data = GameData::Item.try_get(item_id) rescue nil
      next nil unless data
      {
        :item_id => data.id,
        :name => data.name.to_s,
        :quantity => [(grant[:quantity] || grant["quantity"] || grant[:qty] || grant["qty"] || 1).to_i, 1].max,
        :rarity => (grant[:rarity] || grant["rarity"]).to_s
      }
    end.compact
  rescue
    []
  end

  def mystery_box_rarity_color(rarity)
    case rarity.to_s.downcase
    when "common" then GRAY
    when "uncommon" then GREEN
    when "rare" then BLUE
    when "ultra_rare" then PURPLE
    when "legendary" then GOLD
    else PURPLE
    end
  end

  def mystery_box_rarity_label(rarity)
    text = rarity.to_s.strip
    return "Mystery Reward" if text.empty?
    text.split("_").map { |part| part.capitalize }.join(" ")
  end

  def box_animation_title_color(entry = nil, title = nil)
    return PURPLE if box_animation_mystery_box_entry?(entry)
    return PINK if entry && entry.respond_to?(:kind) && entry.kind == :gift
    return BLUE if entry && entry.respond_to?(:kind) && entry.kind == :bundle
    title_text = title.to_s
    return PURPLE if title_text.include?("Mystery")
    return PINK if title_text.include?("Gift")
    return BLUE if title_text.include?("Bundle")
    PURPLE
  rescue
    WHITE
  end

  def box_animation_mystery_box_entry?(entry)
    return false unless entry
    display = entry.respond_to?(:display) && entry.display.is_a?(Hash) ? entry.display : {}
    raw = entry.respond_to?(:raw) && entry.raw.is_a?(Hash) ? entry.raw : {}
    value = display["mystery_box"] || display[:mystery_box] ||
            raw["mystery_box"] || raw[:mystery_box] ||
            raw["mystery"] || raw[:mystery] ||
            raw["hidden_contents"] || raw[:hidden_contents]
    ReloadedMart::Rules.truthy?(value)
  rescue
    false
  end

  def play_box_reward_arrive_se
    pbSEPlay("Item get") rescue pbSEPlay("Mining reveal full") rescue nil
  end

  def load_box_animation_sheet(entry_or_kind, fallback_kind = nil)
    kind = fallback_kind || entry_or_kind
    name = box_animation_name(entry_or_kind, kind)
    bitmap = load_box_animation_bitmap(name)
    return bitmap if bitmap
    fallback = default_box_animation_name(kind)
    if !name.to_s.empty? && name.to_s != fallback.to_s
      ReloadedMart.log_warning("Box animation image missing name=#{name} fallback=#{fallback} entry=#{entry_or_kind&.id rescue "unknown"}")
    end
    bitmap = load_box_animation_bitmap(fallback)
    ReloadedMart.log_warning("Box animation fallback image missing name=#{fallback}") unless bitmap
    bitmap
  rescue
    fallback = default_box_animation_name(kind)
    ReloadedMart.log_warning("Box animation image load failed name=#{name rescue "unknown"} fallback=#{fallback}")
    load_box_animation_bitmap(fallback) rescue nil
  end

  def box_animation_name(entry, kind)
    if entry.respond_to?(:display) && entry.display.is_a?(Hash)
      raw = entry.display["box_image"] || entry.display[:box_image] ||
            entry.display["box_png"] || entry.display[:box_png] ||
            entry.display["box_animation"] || entry.display[:box_animation]
      return sanitize_box_animation_name(raw) unless raw.to_s.strip.empty?
    end
    default_box_animation_name(kind)
  end

  def default_box_animation_name(kind)
    case kind.to_sym
    when :gift then "gift"
    when :bundle then "bundle"
    else "mysterybox"
    end
  rescue
    "mysterybox"
  end

  def sanitize_box_animation_name(value)
    name = File.basename(value.to_s.strip).sub(/\.(png|bmp|jpg|jpeg)\z/i, "")
    name.gsub(/[^A-Za-z0-9_\- ]/, "")
  rescue
    ""
  end

  def load_box_animation_bitmap(name)
    return nil if name.to_s.strip.empty?
    Bitmap.new("Reloaded/Graphics/Boxes/#{name}.png")
  rescue
    Bitmap.new("Reloaded/Graphics/Boxes/#{name}") rescue nil
  end

  def create_box_animation_sprite(sheet, y_offset = 0)
    return nil unless sheet
    sprite = Sprite.new(@viewport)
    sprite.z = 983
    sprite.bitmap = sheet
    sprite.x = SW / 2
    sprite.y = 198 + y_offset.to_i
    sprite.ox = box_animation_frame_width(sheet) / 2
    sprite.oy = box_animation_frame_height(sheet) / 2
    sprite.zoom_x = 3.0
    sprite.zoom_y = 3.0
    update_box_animation_sprite(sprite, 0)
    sprite
  rescue
    nil
  end

  def update_box_animation_sprite(sprite, frame)
    return unless sprite && sprite.bitmap
    frame_w = box_animation_frame_width(sprite.bitmap)
    frame_h = box_animation_frame_height(sprite.bitmap)
    frame_count = box_animation_frame_count(sprite.bitmap, frame_w)
    index = box_animation_frame_index(frame, frame_count)
    sprite.src_rect.set(index * frame_w, 0, frame_w, frame_h) rescue sprite.src_rect = Rect.new(index * frame_w, 0, frame_w, frame_h)
    sprite.visible = true
  rescue
  end

  def update_reveal_item_sprite(icon, frame, revealed)
    return unless icon
    unless revealed
      icon.visible = false
      return
    end
    progress = ((frame.to_f - 82.0) / 24.0).clamp(0.0, 1.0)
    eased = 1.0 - ((1.0 - progress) * (1.0 - progress))
    start_y = 212
    end_y = 135
    icon.x = SW / 2
    icon.y = (start_y + (end_y - start_y) * eased).round
    icon.z = progress >= 1.0 ? 984 : 982
    icon.visible = true
  rescue
  end

  def create_bundle_reveal_icons(rows)
    Array(rows)[0, 5].to_a.each_with_index.map do |row, index|
      sprite = ItemIconSprite.new(SW / 2, 217, nil, @viewport) rescue nil
      next nil unless sprite
      sprite.z = 982
      sprite.visible = false
      sprite.item = row[:item_id]
      sprite.setOffset(PictureOrigin::Center) rescue nil
      sprite.zoom_x = 1.15
      sprite.zoom_y = 1.15
      sprite
    end.compact
  rescue
    []
  end

  def bundle_reveal_sprite_targets
    [
      [SW / 2, 140],       # Center
      [SW / 2 - 56, 153],  # Left Inner
      [SW / 2 + 56, 153],  # Right Inner
      [SW / 2 - 97, 177],  # Left Outer
      [SW / 2 + 97, 177]   # Right Outer
    ]
  end

  def update_bundle_reveal_item_sprites(icons, frame)
    progress = ((frame.to_f - 72.0) / 28.0).clamp(0.0, 1.0)
    return icons.each { |sprite| sprite.visible = false rescue nil } if progress <= 0.0
    eased = 1.0 - ((1.0 - progress) * (1.0 - progress))
    targets = bundle_reveal_sprite_targets
    icons.each_with_index do |sprite, index|
      target = targets[index] || targets[0]
      sprite.x = (SW / 2 + (target[0] - SW / 2) * eased).round
      sprite.y = (217 + (target[1] - 217) * eased).round
      sprite.z = progress >= 1.0 ? 984 : 982
      sprite.visible = true
    end
  rescue
  end

  def box_animation_frame_width(sheet)
    if sheet.width % 10 == 0
      candidate = [sheet.width / 10, 1].max
      return candidate if candidate.between?(40, 64) && (candidate - sheet.height).abs <= 12
    end
    if sheet.width % 12 == 0
      candidate = [sheet.width / 12, 1].max
      return candidate if (candidate - sheet.height).abs <= 4
    end
    [sheet.width / 6, 1].max
  rescue
    48
  end

  def box_animation_frame_height(sheet)
    [sheet.height, 1].max
  rescue
    32
  end

  def box_animation_frame_count(sheet, frame_w = nil)
    frame_w ||= box_animation_frame_width(sheet)
    [[sheet.width / [frame_w, 1].max, 1].max, 1].max
  rescue
    6
  end

  def box_animation_frame_index(frame, frame_count = 6)
    frame_count = frame_count.to_i
    if frame_count > 6
      return [[frame.to_i / 12, 0].max, frame_count - 1].min
    end
    return 0 if frame < 16
    return 1 if frame < 32
    return 2 if frame < 48
    return 3 if frame < 64
    return 4 if frame < 82
    5
  end

  def draw_mystery_box_reveal_frame(bitmap, entry, row, index, total_rows, frame, revealed, adapter, custom_box = false)
    color = mystery_box_rarity_color(row[:rarity])
    bitmap.clear
    bitmap.fill_rect(0, 0, SW, SH, Color.new(0, 0, 0, 172))
    box_w = 382
    box_h = 300
    box_x = (SW - box_w) / 2
    box_y = 40
    draw_panel(bitmap, box_x, box_y, box_w, box_h)
    pbSetSmallFont(bitmap)
    shadow_text(bitmap, box_x + 14, box_y + 10, box_w - 28, 22, adapter.display_name(entry), box_animation_title_color(entry), 1)
    subtitle = revealed ? "Reward #{index + 1}/#{total_rows}" : "Opening..."
    shadow_text(bitmap, box_x + 14, box_y + 31, box_w - 28, 16, subtitle, revealed ? GRAY : box_animation_title_color(entry), 1)
    shake = frame.between?(22, 78) ? Math.sin(frame * 0.85) * (frame < 56 ? 5 : 3) : 0
    lift = revealed ? [[frame - 82, 0].max, 22].min : 0
    draw_mystery_box(bitmap, SW / 2 + shake.round, box_y + 158 + lift / 3, color, frame, revealed) unless custom_box
    draw_reveal_stars(bitmap, color, frame) if frame > 58
    draw_mystery_box_reward_text(bitmap, box_x, box_y, box_w, row, color, frame, revealed)
    hint = revealed ? "Confirm (C)  Skip All (A)" : "Reveal (C)  Skip All (A)"
    bitmap.font.size = 13 rescue nil
    shadow_text(bitmap, box_x + 14, box_y + box_h - 22, box_w - 28, 16, hint, DIM, 1)
  end

  def draw_bundle_reveal_frame(bitmap, entry, rows, frame, adapter, custom_box = false, ready = false)
    color = box_animation_title_color(entry)
    bitmap.clear
    bitmap.fill_rect(0, 0, SW, SH, Color.new(0, 0, 0, 172))
    box_w = 382
    box_h = 260
    box_x = (SW - box_w) / 2
    box_y = 58
    draw_panel(bitmap, box_x, box_y, box_w, box_h)
    pbSetSmallFont(bitmap)
    shadow_text(bitmap, box_x + 14, box_y + 10, box_w - 28, 22, adapter.display_name(entry), color, 1)
    subtitle = frame >= 82 ? "Contents ready" : "Opening..."
    shadow_text(bitmap, box_x + 14, box_y + 31, box_w - 28, 16, subtitle, frame >= 82 ? GRAY : color, 1)
    draw_mystery_box(bitmap, SW / 2, box_y + 163, color, frame, frame >= 82) unless custom_box
    draw_reveal_stars(bitmap, color, frame) if frame > 58
    if frame >= 86
      draw_bundle_reveal_summary(bitmap, rows, box_x, box_y, box_w, entry)
      pbSetSmallFont(bitmap) rescue nil
    end
    hint = ready ? "Results (C)" : "Skip (A)"
    bitmap.font.size = 13 rescue nil
    shadow_text(bitmap, box_x + 14, box_y + box_h - 22, box_w - 28, 16, hint, DIM, 1)
  end

  def draw_bundle_reveal_summary(bitmap, rows, box_x, box_y, box_w, entry = nil)
    bitmap.font.size = 13 rescue nil
    entries = bundle_reveal_visual_rows(rows)
    col_w = ((box_w - 36) / 3.0).floor
    y_offset = entry && entry.respond_to?(:kind) && entry.kind == :gift ? 5 : 0
    row1_y = box_y + 202 + y_offset
    row2_y = box_y + 218 + y_offset
    entries[0, 3].to_a.each_with_index do |row, index|
      x = box_x + 18 + index * col_w
      draw_bundle_reveal_summary_name(bitmap, row, x, row1_y, col_w)
    end
    row2_w = col_w + 10
    row2_x = box_x + (box_w - row2_w * 2 - 8) / 2
    entries[3, 2].to_a.each_with_index do |row, index|
      draw_bundle_reveal_summary_name(bitmap, row, row2_x + index * (row2_w + 8), row2_y, row2_w)
    end
  rescue
  ensure
    pbSetSmallFont(bitmap) rescue nil
  end

  def bundle_reveal_visual_rows(rows)
    entries = Array(rows)[0, 5].to_a
    order = [3, 0, 4, 1, 2]
    order.map { |index| entries[index] }.compact
  rescue
    Array(rows)[0, 5].to_a
  end

  def draw_bundle_reveal_summary_name(bitmap, row, x, y, width)
    return unless row
    qty = row[:quantity].to_i
    label = qty > 1 ? "#{row[:name]} x#{qty}" : row[:name].to_s
    shadow_text(bitmap, x, y, width, 15, trim_text(bitmap, label, width), GRAY, 1)
  rescue
  end

  def draw_mystery_box_glow(bitmap, cx, cy, color, alpha)
    return if alpha <= 0
    5.downto(1) do |step|
      half_w = 20 + step * 19
      half_h = 5 + step * 4
      a = (alpha / (step + 2)).to_i
      fill_diamond(bitmap, cx, cy, half_w, half_h, Color.new(color.red, color.green, color.blue, a))
    end
  end

  def draw_mystery_box(bitmap, cx, cy, color, frame, opened)
    top_y = cy - 30
    body_h = 64
    lift = opened ? [[frame - 82, 0].max, 22].min : 0
    lid_y = opened ? top_y - 24 - lift : top_y - 16
    dark = Color.new(43, 31, 62)
    body = Color.new(62, 44, 90)
    side = Color.new(34, 27, 51)
    lid = Color.new(82, 58, 118)
    ribbon = Color.new(color.red, color.green, color.blue, 168)
    fill_trapezoid(bitmap, cx - 64, top_y, 128, cx - 52, top_y + body_h, 104, body)
    fill_trapezoid(bitmap, cx - 64, top_y, 64, cx - 52, top_y + body_h, 52, side)
    fill_trapezoid(bitmap, cx, top_y, 64, cx, top_y + body_h, 52, dark)
    bitmap.fill_rect(cx - 7, top_y + 5, 14, body_h - 5, ribbon)
    fill_diamond(bitmap, cx, top_y, 66, 18, opened ? dark : lid)
    fill_diamond(bitmap, cx, lid_y, 72, 20, lid)
    fill_diamond(bitmap, cx, lid_y - 1, 66, 15, Color.new(98, 71, 137))
    bitmap.fill_rect(cx - 9, lid_y - 2, 18, 27, ribbon)
    if opened
      fill_diamond(bitmap, cx, top_y - 2, 54, 10, Color.new(color.red, color.green, color.blue, 112))
    end
  end

  def fill_diamond(bitmap, cx, cy, half_w, half_h, color)
    (-half_h).upto(half_h) do |dy|
      ratio = 1.0 - (dy.abs.to_f / [half_h, 1].max)
      width = [(half_w * ratio).round, 1].max
      bitmap.fill_rect(cx - width, cy + dy, width * 2, 1, color)
    end
  end

  def fill_trapezoid(bitmap, top_x, top_y, top_w, bottom_x, bottom_y, bottom_w, color)
    height = [bottom_y - top_y, 1].max
    0.upto(height) do |i|
      ratio = i.to_f / height
      x = (top_x + (bottom_x - top_x) * ratio).round
      width = (top_w + (bottom_w - top_w) * ratio).round
      bitmap.fill_rect(x, top_y + i, width, 1, color)
    end
  end

  def draw_reveal_stars(bitmap, color, frame)
    points = [
      [126, 114, 0],  [386, 114, 23],
      [104, 132, 11], [408, 132, 34],
      [142, 154, 19], [370, 154, 42],
      [112, 182, 31], [400, 182, 6],
      [150, 210, 47], [362, 210, 17],
      [186, 230, 9],  [326, 230, 38],
      [96, 222, 27],  [416, 222, 54],
      [176, 122, 44], [336, 122, 14],
      [206, 118, 57], [306, 118, 29],
      [86, 166, 50],  [426, 166, 20],
      [212, 208, 36], [300, 208, 4]
    ]
    points.each do |x, y, offset|
      phase = (frame + offset) % 56
      next if phase > 28
      size = 1 + phase / 10
      alpha = 225 - phase * 5
      star = Color.new(color.red, color.green, color.blue, alpha)
      bitmap.fill_rect(x - size, y, size * 2 + 1, 1, star)
      bitmap.fill_rect(x, y - size, 1, size * 2 + 1, star)
    end
  end

  def draw_mystery_box_reward_text(bitmap, box_x, box_y, box_w, row, color, frame, revealed)
    return unless revealed
    fade = [[frame - 84, 0].max * 10, 255].min
    text_color = Color.new(WHITE.red, WHITE.green, WHITE.blue, fade)
    accent = Color.new(color.red, color.green, color.blue, fade)
    y = box_y + 218
    qty = row[:quantity].to_i
    name = qty > 1 ? "#{row[:name]} x#{qty}" : row[:name].to_s
    shadow_text(bitmap, box_x + 18, y, box_w - 36, 20, trim_text(bitmap, name, box_w - 36), text_color, 1)
    draw_badge_plain(bitmap, box_x, y + 27, box_w, mystery_box_rarity_label(row[:rarity]).upcase, accent)
  end

  def draw_badge_plain(bitmap, box_x, y, box_w, label, color)
    bitmap.font.size = 14
    width = bitmap.text_size(label).width + 14
    x = box_x + (box_w - width) / 2
    fill = Color.new(color.red / 3, color.green / 3, color.blue / 3, 255)
    if respond_to?(:reloaded_draw_rounded_rect)
      reloaded_draw_rounded_rect(bitmap, x, y, width, 14, 4, fill, fill)
    else
      bitmap.fill_rect(x, y, width, 14, fill)
    end
    pbDrawTextPositions(bitmap, [[label, x + width / 2, y - 6, 2, color, Color.new(0, 0, 0, 0)]])
  rescue
  ensure
    pbSetSmallFont(bitmap) rescue nil
  end

  def show_mystery_box_results(rows, start_index = 0, title = "Mystery Box Results", show_rarity = true)
    rows = Array(rows)
    return if rows.empty?
    overlay = Sprite.new(@viewport)
    overlay.z = 984
    overlay.bitmap = Bitmap.new(SW, SH)
    page = [[start_index.to_i / 10, 0].max, [(rows.length - 1) / 10, 0].max].min
    icons = []
    loop do
      refresh_mystery_box_results(overlay.bitmap, rows, page, icons, title, show_rarity)
      Graphics.update
      Input.update
      icons.each { |sprite| sprite.update rescue nil }
      if Input.trigger?(Input::USE) || mouse_left_trigger?
        break
      elsif Input.trigger?(Input::BACK) || mouse_right_trigger?
        break
      elsif Input.trigger?(Input::LEFT) || Input.trigger?(Input::JUMPUP)
        page = page <= 0 ? (rows.length - 1) / 10 : page - 1
      elsif Input.trigger?(Input::RIGHT) || Input.trigger?(Input::JUMPDOWN)
        max_page = (rows.length - 1) / 10
        page = page >= max_page ? 0 : page + 1
      end
    end
  ensure
    icons.each { |sprite| sprite.dispose rescue nil } if icons
    overlay.bitmap.dispose rescue nil
    overlay.dispose rescue nil
    draw_all rescue nil
  end

  def refresh_mystery_box_results(bitmap, rows, page, icons, title, show_rarity)
    bitmap.clear
    bitmap.fill_rect(0, 0, SW, SH, Color.new(0, 0, 0, 172))
    box_w = 456
    box_h = 286
    box_x = (SW - box_w) / 2
    box_y = 48
    draw_panel(bitmap, box_x, box_y, box_w, box_h)
    pbSetSmallFont(bitmap)
    max_page = (rows.length - 1) / 10
    header = max_page > 0 ? "#{title} (#{page + 1}/#{max_page + 1})" : title
    shadow_text(bitmap, box_x + 12, box_y + 8, box_w - 24, 20, header, box_animation_title_color(nil, title), 1)
    page_rows = rows[page * 10, 10] || []
    positions = mystery_box_result_positions(box_x, box_y)
    while icons.length < 10
      sprite = ItemIconSprite.new(0, 0, nil, @viewport) rescue nil
      break unless sprite
      sprite.z = 986
      sprite.setOffset(PictureOrigin::Center) rescue nil
      icons << sprite
    end
    icons.each_with_index do |sprite, i|
      row = page_rows[i]
      if row
        x, y = positions[i]
        y -= 1 if title.to_s == "Bundle Contents" && (i % 5) == 0
        sprite.x = x
        sprite.y = y
        sprite.item = row[:item_id]
        sprite.visible = true
        qty = row[:quantity].to_i
        name = row[:name].to_s
        text_y = y + 25
        bitmap.font.size = 16 rescue nil
        shadow_text(bitmap, x - 58, text_y, 116, 18, trim_text(bitmap, name, 116), WHITE, 1)
        if show_rarity && !row[:rarity].to_s.empty?
          draw_badge_plain(bitmap, x - 58, y + 47, 116, mystery_box_rarity_label(row[:rarity]).upcase, mystery_box_rarity_color(row[:rarity]))
        end
      else
        sprite.visible = false
      end
    end
    hint = max_page > 0 ? "Close (C)  Page (< >)" : "Close (C)"
    bitmap.font.size = 13 rescue nil
    shadow_text(bitmap, box_x + 12, box_y + box_h - 22, box_w - 24, 16, hint, DIM, 1)
    pbSetSmallFont(bitmap) rescue nil
  end

  def draw_result_quantity(bitmap, x, y, quantity)
    bitmap.font.size = 12 rescue nil
    pbDrawTextPositions(bitmap, [["x#{quantity.to_i}", x, y, 0, WHITE, Color.new(0, 0, 0, 0)]])
  rescue
  ensure
    pbSetSmallFont(bitmap) rescue nil
  end

  def mystery_box_result_positions(box_x, box_y)
    positions = []
    start_x = box_x + 54
    start_y = box_y + 68
    2.times do |row|
      5.times do |col|
        positions << [start_x + col * 86, start_y + row * 92]
      end
    end
    positions
  end

  def autosave_mystery_box_rewards
    return unless defined?(AUTOSAVE_ENABLED_SWITCH)
    return unless $game_switches && $game_switches[AUTOSAVE_ENABLED_SWITCH]
    if defined?(Kernel) && Kernel.respond_to?(:tryAutosave)
      Kernel.tryAutosave
    elsif defined?(Game) && Game.respond_to?(:save)
      Game.save(safe: true)
    end
    ReloadedMart.log_info("Autosaved after Mystery Box rewards") if defined?(ReloadedMart)
  rescue Exception => e
    ReloadedMart.log_exception("Mystery Box autosave failed", e) if defined?(ReloadedMart)
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
      @info_scroll = 0
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
      @info_scroll = 0
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
      @info_scroll = 0
      snap_quantity
      draw_list
      draw_info
    elsif Input.repeat?(Input::DOWN)
      pbPlayCursorSE rescue nil
      @entry_index = (@entry_index + 1) % entries.length
      ensure_visible
      @bundle_scroll = 0
      @info_scroll = 0
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
      @info_scroll = 0
      @bundle_scroll = 0
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
    @info_scroll = 0
    @bundle_scroll = 0
    ensure_visible
    snap_quantity
    draw_all
  end

  def handle_mouse
    controller_scroll = controller_scroll_delta
    if controller_scroll != 0
      scroll_info_panel(controller_scroll)
      return
    end
    mx, my = mouse_pos
    return unless mx && my
    moved = (mx != @last_mx || my != @last_my)
    @last_mx = mx
    @last_my = my
    entries = current_entries
    mouse_scroll = mouse_scroll_delta
    if mouse_scroll > 0
      if info_bundle_scroll_area?(mx, my)
        scroll_bundle_preview(-1)
        return
      end
      scroll_entry_list(mouse_scroll)
    elsif mouse_scroll < 0
      if info_bundle_scroll_area?(mx, my)
        scroll_bundle_preview(1)
        return
      end
      scroll_entry_list(mouse_scroll)
    end
    clicked = mouse_left_trigger?
    if my.between?(TITLE_H, TITLE_H + POCKET_H - 1) && clicked
      pbPlayCursorSE rescue nil
      @pocket_index = (mx < SW / 2) ? (@pocket_index - 1) % @pockets.length : (@pocket_index + 1) % @pockets.length
      @entry_index = 0
      @scroll = 0
      @info_scroll = 0
      @bundle_scroll = 0
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
        if (moved || clicked) && real_index != @entry_index
          pbPlayCursorSE rescue nil
          @entry_index = real_index
          ensure_visible
          @bundle_scroll = 0
          @info_scroll = 0
          snap_quantity
          draw_list
          draw_info
        end
        if clicked
          remember_cursor
          throw :reloaded_mart_mouse_pick, entries[@entry_index]
        end
      end
    elsif my.between?(SH - FOOTER_H, SH - 1) && clicked
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
    old_scroll = @bundle_scroll
    @bundle_scroll = (@bundle_scroll + delta.to_i).clamp(0, max_scroll)
    return if @bundle_scroll == old_scroll
    pbPlayCursorSE rescue nil
    draw_info
  end

  def scroll_entry_list(delta)
    entries = current_entries
    return if entries.empty?
    old_index = @entry_index
    @entry_index = (@entry_index - delta.to_i).clamp(0, [entries.length - 1, 0].max)
    return if @entry_index == old_index
    pbPlayCursorSE rescue nil
    ensure_visible
    @info_scroll = 0
    @bundle_scroll = 0
    snap_quantity
    draw_list
    draw_info
  end

  def scroll_info_panel(delta)
    entry = selected_entry
    return unless entry
    if entry.respond_to?(:bundle_like?) && entry.bundle_like? && !@adapter.mystery_box?(entry)
      scroll_bundle_preview(delta.to_i > 0 ? -1 : 1)
      return
    end
    max_scroll = info_scroll_max(entry)
    old_scroll = @info_scroll.to_i
    @info_scroll = (@info_scroll.to_i - delta.to_i).clamp(0, max_scroll)
    return if @info_scroll == old_scroll
    pbPlayCursorSE rescue nil
    draw_info
  end

  def info_scroll_max(entry)
    bitmap = @info_sprite.bitmap
    icon_x = SW - PAD - 96
    width = icon_x - PAD * 2 - 4
    [info_panel_lines(entry, bitmap, width).length - 4, 0].max
  rescue
    0
  end

  def scroll_delta
    if defined?(Reloaded::ModManagerUI::InputSupport)
      return Reloaded::ModManagerUI::InputSupport.scroll_delta
    end
    mouse_scroll_delta
  rescue
    0
  end

  def mouse_scroll_delta
    if defined?(Reloaded::ModManagerUI::InputSupport)
      return Reloaded::ModManagerUI::InputSupport.mouse_scroll
    end
    return 1 if (Input.repeat?(Input::SCROLLUP) rescue false)
    return -1 if (Input.repeat?(Input::SCROLLDOWN) rescue false)
    0
  rescue
    0
  end

  def controller_scroll_delta
    if defined?(Reloaded::ModManagerUI::InputSupport)
      return Reloaded::ModManagerUI::InputSupport.controller_scroll_delta
    end
    0
  rescue
    0
  end

  def mouse_pos
    if defined?(Reloaded::ModManagerUI::InputSupport)
      return Reloaded::ModManagerUI::InputSupport.mouse_pos
    end
    return nil unless defined?(Mouse)
    Mouse.getMousePos
  rescue
    nil
  end

  def mouse_left_trigger?
    if defined?(Reloaded::ModManagerUI::InputSupport)
      return Reloaded::ModManagerUI::InputSupport.mouse_left_trigger?
    end
    return false unless mouse_pos
    Input.trigger?(Input::MOUSELEFT) rescue false
  end

  def mouse_right_trigger?
    if defined?(Reloaded::ModManagerUI::InputSupport)
      return Reloaded::ModManagerUI::InputSupport.mouse_right_trigger?
    end
    return false unless mouse_pos
    Input.trigger?(Input::MOUSERIGHT) rescue false
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
    price_color = locked ? DIM : (maxed ? BLUE : (free ? GREEN : (selected ? GOLD : GRAY)))
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
    color = base_row_color(entry, locked, favorite)
    return selected_row_text_color(color) if selected
    color
  end

  def base_row_color(entry, locked, favorite)
    return DIM if locked
    return PINK if entry.kind == :gift
    return PURPLE if @adapter.mystery_box?(entry)
    return BLUE if entry.kind == :bundle
    return ORANGE if entry.kind == :service
    return RED if entry.kind == :unlock
    return GOLD if favorite
    GRAY
  end

  def selected_row_text_color(color)
    return color unless color_matches_cursor?(color)
    color_distance(color, WHITE) > 80 ? WHITE : Color.new(20, 24, 34)
  rescue
    color
  end

  def color_matches_cursor?(color)
    fill = respond_to?(:reloaded_cursor_fill) ? reloaded_cursor_fill : nil
    border = respond_to?(:reloaded_cursor_border) ? reloaded_cursor_border : nil
    [fill, border].compact.any? { |cursor_color| color_distance(color, cursor_color) < 90 }
  rescue
    false
  end

  def color_distance(a, b)
    dr = a.red.to_i - b.red.to_i
    dg = a.green.to_i - b.green.to_i
    db = a.blue.to_i - b.blue.to_i
    Math.sqrt((dr * dr) + (dg * dg) + (db * db))
  rescue
    999
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
    bitmap.fill_rect(x, y, width, 14, Color.new(color.red / 3, color.green / 3, color.blue / 3, 255))
    pbDrawTextPositions(bitmap, [[badge[:label], x + width / 2, y - 7, 2, color, Color.new(0, 0, 0, 0)]])
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
    box_kind = @adapter.mystery_box?(entry) ? :mystery_box : entry.kind
    path_name = box_animation_name(entry, box_kind)
    bitmap = Bitmap.new("Reloaded/Graphics/Icons/#{path_name}.png") rescue nil
    icon_bitmap = !bitmap.nil?
    unless bitmap
      bitmap = load_box_animation_bitmap(path_name)
      bitmap = load_box_animation_bitmap(default_box_animation_name(box_kind)) unless bitmap
    end
    return unless bitmap
    frame_w = icon_bitmap ? bitmap.width : box_animation_frame_width(bitmap)
    frame_h = icon_bitmap ? bitmap.height : box_animation_frame_height(bitmap)
    scale = 2.25
    box_x = SW - PAD - 96
    box_y = LIST_Y + LIST_H + 4
    @special_icon_sprite.bitmap = bitmap
    @special_icon_sprite.src_rect.set(0, 0, frame_w, frame_h) rescue @special_icon_sprite.src_rect = Rect.new(0, 0, frame_w, frame_h)
    @special_icon_sprite.zoom_x = scale
    @special_icon_sprite.zoom_y = scale
    @special_icon_sprite.x = box_x + ((96 - frame_w * scale) / 2).round
    @special_icon_sprite.y = box_y + ((96 - frame_h * scale) / 2).round - 5
    if entry.kind == :gift
      @special_icon_sprite.x -= 10
      @special_icon_sprite.y -= 15
    end
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
    if entry.bundle_like?
      draw_bundle_preview(bitmap, entry, x, y, width)
    else
      pbSetSmallFont(bitmap)
      bitmap.font.size = 16
      lines = info_panel_lines(entry, bitmap, width)
      max_scroll = [lines.length - 4, 0].max
      @info_scroll = @info_scroll.to_i.clamp(0, max_scroll)
      draw_info_scroll_arrows(bitmap, x, y, width, @info_scroll, max_scroll)
      lines[@info_scroll, 4].to_a.each do |line|
        locked = @adapter.respond_to?(:locked?) && @adapter.locked?(entry)
        color = line.start_with?("Stock:") ? GOLD : (locked ? DIM : GRAY)
        shadow_text(bitmap, x, y, width, 18, line, color)
        y += 18
      end
    end
    details = []
    details << "Restock: #{@adapter.restock_text(entry)}" if @adapter.restock_text(entry)
    shadow_text(bitmap, x, INFO_H - 20, width, 16, details.compact.join("  "), GOLD) unless details.compact.empty?
  end

  def info_panel_lines(entry, bitmap, width)
    if @adapter.respond_to?(:locked?) && @adapter.locked?(entry)
      return wrap_text(@adapter.lock_text(entry), width, bitmap)
    end
    lines = []
    stock = @adapter.respond_to?(:stock_remaining) ? @adapter.stock_remaining(entry) : nil
    lines << "Stock: #{stock}" unless stock.nil?
    lines.concat(wrap_text(@adapter.description(entry), width, bitmap))
    lines
  rescue
    []
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
    max_scroll = [grants.length - visible_rows, 0].max
    @bundle_scroll = @bundle_scroll.clamp(0, max_scroll)
    draw_info_scroll_arrows(bitmap, x, y + 15, width, @bundle_scroll, max_scroll)
    shadow_text(bitmap, x, y, width, 15, "Will receive:", WHITE)
    stock = @adapter.stock_remaining(entry)
    shadow_text(bitmap, 0, y, x + width, 15, "Stock: #{stock}", DIM, 2) unless stock.nil?
    y += 15
    item_w = width - 118
    owned_x = x + width - 92
    grants[@bundle_scroll, visible_rows].to_a.each do |grant|
      label = grant[:quantity] > 1 ? "#{grant[:quantity]}x #{grant[:name]}" : grant[:name]
      shadow_text(bitmap, x + 6, y, item_w, 14, trim_text(bitmap, label, item_w), GRAY)
      shadow_text(bitmap, owned_x, y, 92, 14, "Owned: #{grant[:owned]}", DIM, 2)
      y += 14
    end
    # Intentionally no range label; bundle scrolling remains mouse-wheel controlled.
  end

  def draw_info_scroll_arrows(bitmap, x, y, width, scroll, max_scroll)
    return if max_scroll.to_i <= 0
    arrow_x = x + width + 4
    draw_tiny_scroll_arrow(bitmap, arrow_x, y - 3, :up, GOLD) if scroll.to_i > 0
    draw_tiny_scroll_arrow(bitmap, arrow_x, INFO_H - 11, :down, GOLD) if scroll.to_i < max_scroll.to_i
  rescue
  end

  def draw_tiny_scroll_arrow(bitmap, x, y, direction, color)
    if direction == :up
      bitmap.fill_rect(x, y, 1, 1, color)
      bitmap.fill_rect(x - 1, y + 1, 3, 1, color)
      bitmap.fill_rect(x - 2, y + 2, 5, 1, color)
    else
      bitmap.fill_rect(x - 2, y, 5, 1, color)
      bitmap.fill_rect(x - 1, y + 1, 3, 1, color)
      bitmap.fill_rect(x, y + 2, 1, 1, color)
    end
  rescue
  end

  def normalized_bundle_grants(entry)
    Array(entry.grants).map do |grant|
      item_id = grant.is_a?(Hash) ? (grant["id"] || grant[:id] || grant["item"] || grant[:item]) : grant
      qty = grant.is_a?(Hash) ? (grant["qty"] || grant[:qty] || grant["quantity"] || grant[:quantity] || 1).to_i : 1
      data = GameData::Item.try_get(item_id) rescue nil
      next nil unless data
      { :name => item_display_name(data), :quantity => qty, :owned => ReloadedMart::Inventory.quantity(data.id) }
    end.compact
  end

  def item_display_name(data)
    return "" unless data
    name = data.name.to_s
    name = "#{name} #{GameData::Move.get(data.move).name}" if data.is_machine? && data.move rescue name
    name
  rescue
    data.respond_to?(:name) ? data.name.to_s : data.to_s
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
      fill_alpha = (96 + pulse * 34).round
      border_alpha = (210 + pulse * 45).round
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
    bitmap.fill_rect(x, y, width, 14, Color.new(color.red / 3, color.green / 3, color.blue / 3, 255))
    pbDrawTextPositions(bitmap, [[label, x + width / 2, y - 7, 2, color, Color.new(0, 0, 0, 0)]])
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
               mouse_left_trigger? ||
               mouse_right_trigger?
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
      if @adapter.mystery_box?(entry)
        show_mystery_box_result(entry, result)
      elsif entry.bundle_like?
        show_bundle_result(entry, result)
      end
    else
      @scene.pbDisplayPaused(_INTL(result.message.to_s.empty? ? "The transaction could not be completed." : result.message))
      @scene.animate_purchase
    end
  end

  def show_mystery_box_result(entry, result)
    return if @scene.play_mystery_box_reveal(entry, result, @adapter)
    applied = Array(result.details[:applied] || result.details["applied"])
    return if applied.empty?
    lines = applied.map do |grant|
      data = GameData::Item.try_get(grant[:item_id] || grant["item_id"]) rescue nil
      next nil unless data
      qty = (grant[:quantity] || grant["quantity"] || 1).to_i
      name = @scene.send(:item_display_name, data)
      qty > 1 ? "#{name} x#{qty}" : name
    end.compact
    return if lines.empty?
    @scene.pbDisplayPaused(_INTL("{1} contained:\n{2}", @adapter.display_name(entry), lines.join("\n")))
  rescue Exception => e
    ReloadedMart.log_exception("Mystery Box reveal failed", e)
  ensure
    @scene.autosave_mystery_box_rewards if result && result.respond_to?(:ok?) && result.ok?
  end

  def show_bundle_result(entry, result)
    return if @scene.play_bundle_reveal(entry, result, @adapter)
    applied = Array(result.details[:applied] || result.details["applied"])
    return if applied.empty?
    lines = applied.map do |grant|
      data = GameData::Item.try_get(grant[:item_id] || grant["item_id"]) rescue nil
      next nil unless data
      qty = (grant[:quantity] || grant["quantity"] || 1).to_i
      name = @scene.send(:item_display_name, data)
      qty > 1 ? "#{name} x#{qty}" : name
    end.compact
    return if lines.empty?
    @scene.pbDisplayPaused(_INTL("{1} contained:\n{2}", @adapter.display_name(entry), lines.join("\n")))
  rescue Exception => e
    ReloadedMart.log_exception("Bundle reveal failed", e)
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
      scroll = scroll_delta
      if scroll > 0
        pbPlayCursorSE rescue nil
        cur = cur >= maximum ? 1 : cur + 1
      elsif scroll < 0
        pbPlayCursorSE rescue nil
        cur = cur <= 1 ? maximum : cur - 1
      else
        mx, my = mouse_pos
        if mx && my && mouse_left_trigger?
          result = mx.between?(box_x, box_x + box_w) && my.between?(box_y, box_y + box_h) ? cur : 0
          break
        elsif mx && my && mouse_right_trigger?
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
      if Input.trigger?(Input::USE) || mouse_left_trigger?
        result = selected == 0
        break
      elsif Input.trigger?(Input::BACK) || mouse_right_trigger?
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
      name_color = selected ? selected_row_text_color(GRAY) : GRAY
      shadow_text(bitmap, PAD + 6, y, SW * 3 / 4, ROW_H, trim_text(bitmap, name, SW * 3 / 4 - PAD), name_color)
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
    lines = info_panel_lines(item, bitmap, width)
    max_scroll = [lines.length - 4, 0].max
    @info_scroll = @info_scroll.to_i.clamp(0, max_scroll)
    draw_info_scroll_arrows(bitmap, PAD, y, width, @info_scroll, max_scroll)
    lines[@info_scroll, 4].to_a.each do |line|
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
      @info_scroll = 0
      snap_quantity
      draw_pocket_nav
      draw_list
      draw_info
    elsif Input.trigger?(Input::RIGHT)
      pbPlayCursorSE rescue nil
      @pocket_index = (@pocket_index + 1) % @pockets.length
      @entry_index = 0
      @scroll = 0
      @info_scroll = 0
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
      @info_scroll = 0
      snap_quantity
      draw_list
      draw_info
    elsif Input.repeat?(Input::DOWN)
      pbPlayCursorSE rescue nil
      @entry_index = (@entry_index + 1) % items.length
      ensure_visible
      @info_scroll = 0
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
      @info_scroll = 0
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
    controller_scroll = controller_scroll_delta
    if controller_scroll != 0
      scroll_info_panel(controller_scroll)
      return
    end
    mx, my = mouse_pos
    return unless mx && my
    moved = (mx != @last_mx || my != @last_my)
    @last_mx = mx
    @last_my = my
    items = current_entries
    mouse_scroll = mouse_scroll_delta
    if mouse_scroll != 0
      scroll_entry_list(mouse_scroll)
    end
    clicked = mouse_left_trigger?
    if my.between?(TITLE_H, TITLE_H + POCKET_H - 1) && clicked
      pbPlayCursorSE rescue nil
      @pocket_index = mx < SW / 2 ? (@pocket_index - 1) % @pockets.length : (@pocket_index + 1) % @pockets.length
      @entry_index = 0
      @scroll = 0
      @info_scroll = 0
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
        if (moved || clicked) && real_index != @entry_index
          pbPlayCursorSE rescue nil
          @entry_index = real_index
          ensure_visible
          @info_scroll = 0
          snap_quantity
          draw_list
          draw_info
        end
        if clicked
          remember_sell_cursor
          throw :reloaded_mart_sell_mouse_pick, items[@entry_index]
        end
      end
    elsif my.between?(SH - FOOTER_H, SH - 1) && clicked
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
    max = ReloadedMart.bag_max_per_slot
    unit = buy_price(entry)
    max = [max, (money / unit).floor].min if unit > 0
    max = [max, 0].max
    return 0 if max <= 0
    owned = ReloadedMart::Inventory.quantity(data.id)
    return 0 if data.is_important? && owned.positive?
    candidate = [max, ReloadedMart.bag_max_per_slot - owned.to_i].min
    return 0 if candidate <= 0
    ReloadedMart::Inventory.can_store_grants?([{ :item_id => data.id, :quantity => candidate }]).ok? ? candidate : 0
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
