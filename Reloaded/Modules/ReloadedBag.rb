#======================================================
# Reloaded Bag
# Author: Stonewall
#======================================================
# Full-screen Reloaded bag interface.
#
# Responsibilities:
#   - Replace the normal and choose-item/battle bag UI when enabled.
#   - Preserve vanilla bag item behavior through existing handlers.
#   - Provide favorites, sorting, custom list order, and autosort tools.
#   - Keep Reloaded-owned save data lazy and backward-compatible.
#
#======================================================

module ReloadedBag
  SCREEN_W = 512
  SCREEN_H = 384
  TITLE_H = 24
  POCKET_H = 22
  FOOTER_H = 20
  INFO_H = 112
  PAD = 8
  LIST_Y = TITLE_H + POCKET_H
  LIST_H = SCREEN_H - TITLE_H - POCKET_H - INFO_H - FOOTER_H
  ROW_H = 24
  SORT_LABELS = ["Default", "A-Z", "Quantity", "Type", "List"].freeze
  AUTOSORT_FILE = "Mods/Reloaded/ReloadedBagAutosort.txt"

  BG = Color.new(18, 22, 34)
  TITLE_BG = Color.new(20, 24, 40)
  POCKET_BG = Color.new(25, 30, 48)
  PANEL_BG = Color.new(28, 34, 52)
  INFO_BG = Color.new(22, 28, 46)
  ROW_HOVER = Color.new(255, 255, 255, 14)
  BORDER = Color.new(60, 80, 130)
  SEP = Color.new(50, 65, 110)
  WHITE = Color.new(255, 255, 255)
  GRAY = Color.new(175, 180, 200)
  DIM = Color.new(105, 110, 135)
  SHADOW = Color.new(10, 12, 22)
  GOLD = Color.new(240, 200, 80)
  BLUE = Color.new(120, 190, 255)
  FAV = Color.new(255, 220, 80)
  NEW_COLOR = Color.new(100, 230, 100)
  HELD_COLOR = Color.new(120, 200, 255)

  class << self
    def install
      install_pokemon_system_settings
      patch_reloaded_ui_options
      patch_bag_screen
      log_info("Installed Reloaded Bag module")
      true
    rescue Exception => e
      log_exception("Reloaded Bag install failed", e)
      false
    end

    def enabled?
      defined?(ReloadedUI::SummaryFeature) && ReloadedUI::SummaryFeature.reloaded_bag?
    rescue
      false
    end

    def toast_message(text)
      if defined?(Reloaded) && Reloaded.respond_to?(:toast_ok)
        Reloaded.toast_ok(text.to_s)
      elsif defined?(Kernel) && Kernel.respond_to?(:pbMessage)
        Kernel.pbMessage(text.to_s)
      end
      true
    rescue
      Kernel.pbMessage(text.to_s) rescue nil
      true
    end

    def move_type_color(type_id)
      type_num = (GameData::Type.get(type_id).id_number rescue nil)
      case type_num
      when (GameData::Type.get(:FIRE).id_number     rescue -1) then Color.new(240, 100,  50)
      when (GameData::Type.get(:WATER).id_number    rescue -1) then Color.new( 80, 160, 240)
      when (GameData::Type.get(:GRASS).id_number    rescue -1) then Color.new( 80, 210,  80)
      when (GameData::Type.get(:ELECTRIC).id_number rescue -1) then Color.new(240, 210,  50)
      when (GameData::Type.get(:ICE).id_number      rescue -1) then Color.new(130, 220, 240)
      when (GameData::Type.get(:FIGHTING).id_number rescue -1) then Color.new(200,  60,  60)
      when (GameData::Type.get(:POISON).id_number   rescue -1) then Color.new(180,  80, 200)
      when (GameData::Type.get(:GROUND).id_number   rescue -1) then Color.new(215, 185, 130)
      when (GameData::Type.get(:FLYING).id_number   rescue -1) then Color.new(180, 150, 230)
      when (GameData::Type.get(:PSYCHIC).id_number  rescue -1) then Color.new(240,  80, 140)
      when (GameData::Type.get(:BUG).id_number      rescue -1) then Color.new(150, 190,  50)
      when (GameData::Type.get(:ROCK).id_number     rescue -1) then Color.new(190, 160,  70)
      when (GameData::Type.get(:GHOST).id_number    rescue -1) then Color.new(110,  80, 160)
      when (GameData::Type.get(:DRAGON).id_number   rescue -1) then Color.new( 80,  60, 220)
      when (GameData::Type.get(:DARK).id_number     rescue -1) then Color.new(120,  90,  60)
      when (GameData::Type.get(:STEEL).id_number    rescue -1) then Color.new(160, 170, 190)
      when (GameData::Type.get(:FAIRY).id_number    rescue -1) then Color.new(240, 140, 200)
      else WHITE
      end
    end

    def open_autosort_options
      pbFadeOutIn do
        scene = AutosortOptionsScene.new
        screen = PokemonOptionScreen.new(scene)
        screen.pbStartScreen
      end
    rescue Exception => e
      log_exception("Reloaded Bag Autosort Options failed", e)
      toast_message(_INTL("Reloaded Bag Autosort Options are unavailable right now."))
    end

    def install_pokemon_system_settings
      return unless defined?(PokemonSystem)
      PokemonSystem.class_eval do
        def reloaded_bag_pocket_sort
          @reloaded_bag_pocket_sort.nil? ? 0 : @reloaded_bag_pocket_sort.to_i
        end

        def reloaded_bag_pocket_sort=(value)
          @reloaded_bag_pocket_sort = value.to_i == 1 ? 1 : 0
        end

        def reloaded_bag_sort_mode
          @reloaded_bag_sort_mode.nil? ? 0 : @reloaded_bag_sort_mode.to_i
        end

        def reloaded_bag_sort_mode=(value)
          max = ReloadedBag::SORT_LABELS.length - 1
          @reloaded_bag_sort_mode = [[value.to_i, 0].max, max].min
        end

        def reloaded_bag_sort_modes
          @reloaded_bag_sort_modes = {} unless @reloaded_bag_sort_modes.is_a?(Hash)
          @reloaded_bag_sort_modes
        end

        def reloaded_bag_sort_modes=(value)
          @reloaded_bag_sort_modes = value.is_a?(Hash) ? value : {}
        end

        def reloaded_bag_list_orders
          @reloaded_bag_list_orders = {} unless @reloaded_bag_list_orders.is_a?(Hash)
          @reloaded_bag_list_orders
        end

        def reloaded_bag_list_orders=(value)
          @reloaded_bag_list_orders = value.is_a?(Hash) ? value : {}
        end

        def reloaded_bag_last_seen_qty
          @reloaded_bag_last_seen_qty = {} unless @reloaded_bag_last_seen_qty.is_a?(Hash)
          @reloaded_bag_last_seen_qty
        end

        def reloaded_bag_last_seen_qty=(value)
          @reloaded_bag_last_seen_qty = value.is_a?(Hash) ? value : {}
        end

        def reloaded_bag_favorites
          @reloaded_bag_favorites = [] unless @reloaded_bag_favorites.is_a?(Array)
          @reloaded_bag_favorites
        end

        def reloaded_bag_favorites=(value)
          @reloaded_bag_favorites = value.is_a?(Array) ? value : []
        end
      end
    end

    def patch_reloaded_ui_options
      return unless defined?(ReloadedUI::OptionsScene)
      return if ReloadedUI::OptionsScene.method_defined?(:reloaded_bag_original_pbGetOptions)
      ReloadedUI::OptionsScene.class_eval do
        alias reloaded_bag_original_pbGetOptions pbGetOptions
        def pbGetOptions(inloadscreen = false)
          opts = reloaded_bag_original_pbGetOptions(inloadscreen)
          idx = opts.index { |opt| (opt.name rescue nil).to_s == _INTL("Reloaded Bag") }
          action = ActionButton.new(
            _INTL("Autosort Options"),
            proc { ReloadedBag.open_autosort_options },
            _INTL("Open Reloaded Bag sorting, custom list order, and import/export options.")
          )
          idx ? opts.insert(idx + 1, action) : opts << action
          opts
        end
      end
    rescue Exception => e
      log_exception("Failed to patch Reloaded UI options for Reloaded Bag", e)
    end

    def patch_bag_screen
      return unless defined?(PokemonBagScreen)
      return if PokemonBagScreen.method_defined?(:reloaded_bag_original_pbStartScreen)
      PokemonBagScreen.class_eval do
        alias reloaded_bag_original_pbStartScreen pbStartScreen
        alias reloaded_bag_original_pbChooseItemScreen pbChooseItemScreen

        def pbStartScreen
          return reloaded_bag_original_pbStartScreen unless ReloadedBag.enabled?
          ReloadedBag::Screen.new(ReloadedBag::Scene.new, @bag, false, nil).pbStartScreen
        rescue SystemExit
          raise
        rescue Exception => e
          ReloadedBag.log_exception("Reloaded Bag normal screen failed", e)
          reloaded_bag_original_pbStartScreen
        end

        def pbChooseItemScreen(proc = nil)
          return reloaded_bag_original_pbChooseItemScreen(proc) unless ReloadedBag.enabled?
          oldlastpocket = @bag.lastpocket
          oldchoices = @bag.getAllChoices
          item = ReloadedBag::Screen.new(ReloadedBag::Scene.new, @bag, true, proc).pbChooseItemScreen
          @bag.lastpocket = oldlastpocket
          @bag.setAllChoices(oldchoices)
          item
        rescue SystemExit
          raise
        rescue Exception => e
          ReloadedBag.log_exception("Reloaded Bag choose-item screen failed", e)
          reloaded_bag_original_pbChooseItemScreen(proc)
        end
      end
    end

    def log_info(message)
      Reloaded::Log.info(message, :modules) if defined?(Reloaded::Log)
    end

    def log_warning(message)
      Reloaded::Log.warning(message, :modules) if defined?(Reloaded::Log)
    end

    def log_exception(message, error)
      Reloaded::Log.exception(message, error, channel: :modules) if defined?(Reloaded::Log)
    end

    def game_root
      File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    end

    def sanitize_path(path)
      return "" if path.nil?
      Reloaded::FileActions.display_path(path)
    rescue
      File.basename(path.to_s)
    end
  end

  module Autosort
    module_function

    def per_pocket?
      ($PokemonSystem.reloaded_bag_pocket_sort rescue 0).to_i == 1
    end

    def global_sort_mode
      ($PokemonSystem.reloaded_bag_sort_mode rescue 0).to_i.clamp(0, SORT_LABELS.length - 1)
    end

    def global_sort_mode=(value)
      $PokemonSystem.reloaded_bag_sort_mode = value if $PokemonSystem
    end

    def sort_mode_for_pocket(pocket_id)
      modes = ($PokemonSystem.reloaded_bag_sort_modes rescue {}) || {}
      (modes[pocket_id] || 0).to_i.clamp(0, SORT_LABELS.length - 1)
    end

    def set_sort_mode_for_pocket(pocket_id, mode)
      modes = ($PokemonSystem.reloaded_bag_sort_modes rescue nil)
      modes = {} unless modes.is_a?(Hash)
      modes[pocket_id] = mode.to_i.clamp(0, SORT_LABELS.length - 1)
      $PokemonSystem.reloaded_bag_sort_modes = modes
    end

    def all_items_for_pocket(pocket_id)
      items = []
      GameData::Item.each do |item|
        next unless item && (item.pocket rescue nil) == pocket_id
        items << item.id
      end
      items.sort_by { |id| [(GameData::Item.try_get(id)&.name || id.to_s).downcase, id.to_s] }
    rescue
      []
    end

    def ensure_list_for_pocket(pocket_id)
      all_items = all_items_for_pocket(pocket_id)
      lists = ($PokemonSystem.reloaded_bag_list_orders rescue nil)
      lists = {} unless lists.is_a?(Hash)
      existing = lists[pocket_id]
      existing = [] unless existing.is_a?(Array)
      existing = existing.select { |id| all_items.include?(id) }
      merged = existing + all_items.reject { |id| existing.include?(id) }
      lists[pocket_id] = merged
      $PokemonSystem.reloaded_bag_list_orders = lists
      merged
    rescue
      all_items || []
    end

    def sort_items(pocket_id, items, favorite_proc, display_proc, qty_proc, mode)
      favs = items.select { |item| favorite_proc.call(item) }
      rest = items.reject { |item| favorite_proc.call(item) }
      sort_group(pocket_id, favs, display_proc, qty_proc, mode) +
        sort_group(pocket_id, rest, display_proc, qty_proc, mode)
    end

    def sort_group(pocket_id, items, display_proc, qty_proc, mode)
      case mode.to_i
      when 1
        items.sort_by { |item| display_proc.call(item).to_s.downcase }
      when 2
        items.sort_by { |item| [-qty_proc.call(item).to_i, display_proc.call(item).to_s.downcase] }
      when 3
        items.sort_by { |item| [item_type_key(item), display_proc.call(item).to_s.downcase] }
      when 4
        list = ensure_list_for_pocket(pocket_id)
        items.each { |item| list << item unless list.include?(item) }
        lists = ($PokemonSystem.reloaded_bag_list_orders rescue {}) || {}
        lists[pocket_id] = list
        $PokemonSystem.reloaded_bag_list_orders = lists
        items.sort_by { |item| [list.index(item) || 99_999, display_proc.call(item).to_s.downcase] }
      else
        items
      end
    end

    def item_type_key(item_id)
      item = GameData::Item.try_get(item_id)
      return 99 unless item
      return 0 if (item.is_machine? rescue false)
      return 1 if (item.field_use rescue 0).to_i > 0
      return 2 if (item.battle_use rescue 0).to_i > 0
      return 3 if (item.can_hold? rescue false)
      4
    end

    def snapshot_quantities
      snap = {}
      return snap unless $PokemonBag
      1.upto((PokemonBag.numPockets rescue 1)) do |pid|
        pocket = $PokemonBag.pockets[pid] rescue nil
        next unless pocket
        pocket.each do |entry|
          item = entry[0] rescue nil
          next unless item
          snap[item] = ($PokemonBag.pbQuantity(item) rescue 0).to_i
        end
      end
      snap
    end

    def save_last_seen_quantities
      $PokemonSystem.reloaded_bag_last_seen_qty = snapshot_quantities if $PokemonSystem
    end

    def export_all(path = nil)
      path ||= AUTOSORT_FILE
      path = Reloaded::FileActions.resolve(path, :must_exist => false)
      ensure_dir(File.dirname(path))
      File.open(path, "wb") do |file|
        write_header(file)
        1.upto((PokemonBag.numPockets rescue 1)) do |pid|
          write_pocket(file, pid, ensure_list_for_pocket(pid))
        end
      end
      ReloadedBag.log_info("Exported Reloaded Bag autosort to #{ReloadedBag.sanitize_path(path)}")
      path
    rescue Exception => e
      ReloadedBag.log_exception("Reloaded Bag autosort export failed", e)
      nil
    end

    def import(path = nil)
      path ||= AUTOSORT_FILE
      path = Reloaded::FileActions.resolve(path, :must_exist => false)
      return { :ok => false, :error => "File not found: #{ReloadedBag.sanitize_path(path)}" } unless File.exist?(path)
      path = Reloaded::FileActions.resolve(path, :type => :file)
      current = nil
      imported = {}
      File.readlines(path).each do |raw|
        line = raw.to_s.strip
        next if line.empty? || line.start_with?("#")
        if line =~ /^\[POCKET\s+(\d+)\]/i
          current = $1.to_i
          imported[current] ||= []
          next
        end
        next unless current
        token = line.split("#", 2)[0].to_s.strip
        next if token.empty?
        id = token.to_sym
        next unless GameData::Item.try_get(id) rescue false
        imported[current] << id unless imported[current].include?(id)
      end
      return { :ok => false, :error => "No pocket sections found." } if imported.empty?
      lists = ($PokemonSystem.reloaded_bag_list_orders rescue {}) || {}
      applied = []
      imported.each do |pid, ids|
        all = all_items_for_pocket(pid)
        valid = ids.select { |id| all.include?(id) }
        lists[pid] = valid + all.reject { |id| valid.include?(id) }
        applied << pid
      end
      $PokemonSystem.reloaded_bag_list_orders = lists
      ReloadedBag.log_info("Imported Reloaded Bag autosort from #{ReloadedBag.sanitize_path(path)} pockets=#{applied.join(",")}")
      { :ok => true, :pockets => applied }
    rescue Exception => e
      ReloadedBag.log_exception("Reloaded Bag autosort import failed", e)
      { :ok => false, :error => e.message }
    end

    def ensure_dir(dir)
      return if Dir.exist?(dir)
      parent = File.dirname(dir)
      ensure_dir(parent) if parent && parent != dir && !Dir.exist?(parent)
      Dir.mkdir(dir)
    end

    def write_header(file)
      file.write("# Reloaded Bag Autosort\n")
      file.write("# Format: [POCKET n], then item IDs one per line.\n\n")
    end

    def write_pocket(file, pocket_id, list)
      name = (PokemonBag.pocketNames[pocket_id] rescue "Pocket #{pocket_id}")
      file.write("[POCKET #{pocket_id}] # #{name}\n")
      list.each do |id|
        item_name = GameData::Item.try_get(id)&.name || id.to_s
        file.write("#{id} # #{item_name}\n")
      end
      file.write("\n")
    end
  end

  class Adapter
    def initialize(bag, filterproc = nil)
      @bag = bag
      @filterproc = filterproc
    end

    def num_pockets
      PokemonBag.numPockets rescue 1
    end

    def pocket_names
      PokemonBag.pocketNames rescue []
    end

    def items_in_pocket(pocket_id)
      pocket = @bag.pockets[pocket_id] rescue nil
      return [] unless pocket
      pocket.map { |entry| entry[0] }.select do |item|
        qty(item) > 0 && (!@filterproc || @filterproc.call(item))
      end
    end

    def qty(item)
      @bag.pbQuantity(item) rescue 0
    end

    def display_name(item)
      base = GameData::Item.try_get(item)&.name || item.to_s
      move = tm_move_name(item)
      move ? "#{base} #{move}" : base
    end

    def description(item)
      GameData::Item.try_get(item)&.description || ""
    end

    def pocket_name(pocket_id)
      pocket_names[pocket_id] || "Pocket #{pocket_id}"
    end

    def favorite?(item)
      ($PokemonSystem.reloaded_bag_favorites rescue []).include?(item)
    end

    def toggle_favorite(item)
      favs = ($PokemonSystem.reloaded_bag_favorites rescue nil)
      return unless favs
      favs.include?(item) ? favs.delete(item) : favs << item
      $PokemonSystem.reloaded_bag_favorites = favs
    end

    def held?(item)
      return false unless $Trainer && $Trainer.party
      $Trainer.party.any? { |pkmn| pkmn && pkmn.item_id == item }
    rescue
      false
    end

    def bag_index(pocket_id, item)
      pocket = @bag.pockets[pocket_id] rescue nil
      return 0 unless pocket
      pocket.index { |entry| (entry[0] rescue nil) == item } || 0
    end

    def tm_move_name(item_id)
      move = tm_move_data(item_id)
      move&.name
    end

    def tm_move_data(item_id)
      item = GameData::Item.try_get(item_id)
      return nil unless item && (item.is_machine? rescue false)
      move_id = item.move rescue nil
      return nil unless move_id
      GameData::Move.try_get(move_id) rescue nil
    end
  end

  module PartyPreloader
    FILES = [
      "Graphics/Pictures/Party/bg",
      "Graphics/Pictures/Party/panel_round",
      "Graphics/Pictures/Party/panel_round_sel",
      "Graphics/Pictures/Party/panel_round_faint",
      "Graphics/Pictures/Party/panel_round_faint_sel",
      "Graphics/Pictures/Party/panel_rect",
      "Graphics/Pictures/Party/panel_rect_sel",
      "Graphics/Pictures/Party/panel_rect_faint",
      "Graphics/Pictures/Party/panel_rect_faint_sel",
      "Graphics/Pictures/Party/overlay_hp_back",
      "Graphics/Pictures/Party/overlay_hp",
      "Graphics/Pictures/Party/icon_ball",
      "Graphics/Pictures/Party/icon_ball_sel",
      "Graphics/Pictures/statuses"
    ].freeze
    @done = false

    def self.run
      return if @done
      FILES.each do |path|
        begin
          bmp = Bitmap.new(path)
          bmp.dispose
        rescue
        end
      end
      @done = true
    end
  end

  class Scene
    include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

    attr_reader :sprites

    @@last_pocket_index = 0
    @@last_item_index = 0

    def self.reset_cursor
      @@last_pocket_index = 0
      @@last_item_index = 0
    end

    def initialize
      @sprites = {}
      @pockets = []
      @pocket_index = 0
      @item_index = 0
      @scroll = 0
      @new_items = {}
      @choosing = false
      @filterproc = nil
      @old_mouse = [nil, nil]
      @last_cursor_pulse_frame = -1
    end

    def pbStartScreen(bag, choosing = false, filterproc = nil)
      @bag = bag
      @choosing = choosing
      @filterproc = filterproc
      @adapter = Adapter.new(@bag, @filterproc)
      @sort_mode = Autosort.global_sort_mode
      mark_new_items
      Graphics.freeze
      setup_sprites
      rebuild_pockets
      if @pockets.empty?
        draw_all
        Graphics.transition(8)
        pbDisplay(_INTL("There are no items."))
        return
      end
      @pocket_index = @@last_pocket_index.clamp(0, @pockets.length - 1)
      @item_index = @@last_item_index.clamp(0, [current_items.length - 1, 0].max)
      setup_item_list_state(@item_index)
      ensure_visible
      draw_all
      Graphics.transition(8)
    end

    def pbEndScreen
      @@last_pocket_index = @pocket_index
      @@last_item_index = @item_index
      Autosort.global_sort_mode = @sort_mode unless Autosort.per_pocket?
      Autosort.save_last_seen_quantities
      Graphics.freeze
      teardown
      Graphics.transition(8)
    end

    def pbChooseItem
      loop do
        Graphics.update
        Input.update
        tick_cursor_pulse
        if hint_triggered?
          show_hint_popup
          next
        end
        mouse_item = update_mouse
        return mouse_item if mouse_item
        return nil if @pockets.empty?
        event = @item_list_state.update_input(:mouse => false)
        result = handle_item_list_event(event)
        return result unless result == :continue
        if Input.const_defined?(:ACTION) && Input.trigger?(Input::ACTION)
          toggle_favorite
        elsif Input.const_defined?(:L) && Input.trigger?(Input::L)
          cycle_sort
        end
      end
    end

    def pbRefresh
      selected_item = @item_list_state ? @item_list_state.selected_id : current_items[@item_index]
      rebuild_pockets
      refresh_item_list_state(selected_item)
      draw_all
    end

    def pbRefreshAfterGive
      pbRefresh
    end

  def pbDisplay(msg, brief = false)
    if defined?(Reloaded) && Reloaded.respond_to?(:toast_ok)
      Reloaded.toast_ok(msg.to_s)
    elsif defined?(Reloaded) && Reloaded.respond_to?(:message)
      Reloaded.message(msg.to_s)
    else
      pbMessage(msg.to_s)
    end
    ensure
      @item_list_state.dialog_closed! if @item_list_state
      draw_all rescue nil
    end

    def pbConfirm(msg)
      return Reloaded.confirm(msg.to_s, :default => true) if defined?(Reloaded) && Reloaded.respond_to?(:confirm)
      pbConfirmMessage(msg.to_s) { pbUpdate }
    ensure
      @item_list_state.dialog_closed! if @item_list_state
      draw_all rescue nil
    end

    def pbChooseNumber(helptext, maximum, initnum = 1)
      if defined?(Reloaded::NumberPicker)
        result = Reloaded::NumberPicker.quantity(
          helptext.to_s,
          :min => 1,
          :max => maximum.to_i,
          :initial => initnum.to_i,
          :step => 1,
          :large_step => 10,
          :wrap => true,
          :show_max_label => true,
          :allow_max_shortcut => true
        )
        return result.nil? ? 0 : result.to_i
      end
      UIHelper.pbChooseNumber(@msgwindow, helptext.to_s, maximum.to_i, initnum.to_i) { pbUpdate }
    ensure
      @item_list_state.dialog_closed! if @item_list_state
    end

    def pbShowCommands(helptext, commands, index = 0)
      show_action_popup(helptext, commands, index)
    end

    def pbUpdate
      pbUpdateSpriteHash(@sprites) rescue nil
    end

    def pbHide
      @viewport.visible = false if @viewport
    end

    def pbShow
      @viewport.visible = true if @viewport
    end

    def pbFadeOutScene
      pbHide
    end

    def pbFadeInScene
      pbShow
    end

    def current_items
      pocket = @pockets[@pocket_index]
      pocket ? pocket[:items] : []
    end

    def current_pocket_id
      pocket = @pockets[@pocket_index]
      pocket ? pocket[:id] : 1
    end

    private

    def setup_sprites
      @viewport = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
      @viewport.z = 99999
      @sprites["bg"] = new_sprite(0, 0, SCREEN_W, SCREEN_H, 0)
      @sprites["title"] = new_sprite(0, 0, SCREEN_W, TITLE_H, 10)
      @sprites["pockets"] = new_sprite(0, TITLE_H, SCREEN_W, POCKET_H, 10)
      @sprites["list"] = new_sprite(0, LIST_Y, SCREEN_W, LIST_H, 10)
      @sprites["info"] = new_sprite(0, LIST_Y + LIST_H, SCREEN_W, INFO_H, 10)
      @sprites["footer"] = new_sprite(0, SCREEN_H - FOOTER_H, SCREEN_W, FOOTER_H, 10)
      @sprites["itemicon"] = ItemIconSprite.new(SCREEN_W - 58, LIST_Y + LIST_H + 55, nil, @viewport)
      @sprites["itemicon"].z = 20
      @sprites["itemicon"].zoom_x = 1.5
      @sprites["itemicon"].zoom_y = 1.5
      @msgwindow = pbCreateMessageWindow(@viewport)
      @msgwindow.visible = false
      draw_bg
    end

    def new_sprite(x, y, w, h, z)
      sprite = Sprite.new(@viewport)
      sprite.x = x
      sprite.y = y
      sprite.z = z
      sprite.bitmap = Bitmap.new(w, [h, 1].max)
      sprite
    end

    def teardown
      pbDisposeMessageWindow(@msgwindow) rescue nil
      @sprites.each do |key, sprite|
        next unless sprite
        sprite.bitmap.dispose rescue nil if key != "itemicon" && sprite.respond_to?(:bitmap) && sprite.bitmap
        sprite.dispose rescue nil
      end
      @sprites.clear
      @viewport.dispose if @viewport
      @viewport = nil
    end

    def rebuild_pockets
      previous_id = current_pocket_id
      @pockets = []
      1.upto(@adapter.num_pockets) do |pid|
        items = @adapter.items_in_pocket(pid)
        next if items.empty?
        mode = Autosort.per_pocket? ? Autosort.sort_mode_for_pocket(pid) : @sort_mode
        items = Autosort.sort_items(
          pid,
          items,
          proc { |item| @adapter.favorite?(item) },
          proc { |item| @adapter.display_name(item) },
          proc { |item| @adapter.qty(item) },
          mode
        )
        @pockets << { :id => pid, :name => clean_pocket_name(@adapter.pocket_name(pid)), :items => items }
      end
      restored = @pockets.index { |p| p[:id] == previous_id }
      @pocket_index = restored || @pocket_index.clamp(0, [@pockets.length - 1, 0].max)
      @item_index = @item_index.clamp(0, [current_items.length - 1, 0].max)
      sync_bag_choice
    end

    def clean_pocket_name(value)
      text = value.to_s.gsub(/[^\x20-\x7E]/, "e")
      text = text.gsub(/\s+/, " ").strip
      compact = text.upcase.gsub(/[^A-Z0-9]/, "")
      return "POKEBALLS" if compact == "POKEBALLS"
      text.empty? ? "POCKET" : text.upcase
    end

    def sync_bag_choice
      item = current_items[@item_index]
      return unless item
      @bag.lastpocket = current_pocket_id
      @bag.setChoice(current_pocket_id, @adapter.bag_index(current_pocket_id, item)) rescue nil
    end

    def rows_per_page
      (LIST_H / ROW_H).floor
    end

    def ensure_visible
      return unless @item_list_state
      @item_list_state.visible_rows = rows_per_page
      @item_list_state.ensure_visible!
      sync_item_list_state
    end

    def setup_item_list_state(initial_index = 0, initial_id = nil)
      @item_list_state_key = [:reloaded_bag, current_pocket_id]
      @item_list_state = Reloaded::ListState.new(
        :key => @item_list_state_key,
        :rows => current_items,
        :visible_rows => rows_per_page,
        :row_id => proc { |item| item },
        :initial_index => initial_index,
        :initial_id => initial_id,
        :wrap => true,
        :horizontal => :external,
        :remember => true
      )
      sync_item_list_state
    end

    def refresh_item_list_state(preserve_item = nil)
      expected_key = [:reloaded_bag, current_pocket_id]
      if @item_list_state && @item_list_state_key == expected_key
        @item_list_state.visible_rows = rows_per_page
        @item_list_state.replace_rows(current_items, :preserve => :id)
        @item_list_state.select_id(preserve_item) if preserve_item
      else
        setup_item_list_state(@item_index, preserve_item)
      end
      sync_item_list_state
    end

    def sync_item_list_state
      @item_index = @item_list_state.index || 0
      @scroll = @item_list_state.scroll
      sync_bag_choice
    end

    def handle_item_list_event(event)
      return :continue unless event
      sync_item_list_state
      case event.type
      when :moved
        pbPlayCursorSE rescue nil
        draw_list
        draw_info
      when :left
        pbPlayCursorSE rescue nil
        switch_pocket(-1)
      when :right
        pbPlayCursorSE rescue nil
        switch_pocket(1)
      when :activate
        return event.row
      when :back
        pbPlayCancelSE rescue nil
        return nil
      end
      :continue
    end

    def switch_pocket(dir)
      return if @pockets.empty?
      @item_list_state.remember! if @item_list_state
      @pocket_index = (@pocket_index + dir) % @pockets.length
      @item_index = 0
      @scroll = 0
      setup_item_list_state(0)
      draw_pockets
      draw_list
      draw_info
      draw_footer
    end

    def move_item(delta)
      return if current_items.empty?
      handle_item_list_event(@item_list_state.move(delta))
    end

    def toggle_favorite
      item = current_items[@item_index]
      return unless item
      @adapter.toggle_favorite(item)
      pbPlayCursorSE
      saved = item
      rebuild_pockets
      refresh_item_list_state(saved)
      draw_list
      draw_info
      draw_footer
    end

    def cycle_sort
      mode = current_sort_mode
      mode = (mode + 1) % SORT_LABELS.length
      if Autosort.per_pocket?
        Autosort.set_sort_mode_for_pocket(current_pocket_id, mode)
      else
        @sort_mode = mode
        Autosort.global_sort_mode = mode
      end
      pbPlayCursorSE
      saved = current_items[@item_index]
      rebuild_pockets
      refresh_item_list_state(saved)
      draw_all
    end

    def current_sort_mode
      Autosort.per_pocket? ? Autosort.sort_mode_for_pocket(current_pocket_id) : @sort_mode
    end

    def tick_cursor_pulse
      frame = (Graphics.frame_count rescue 0)
      pulse_frame = frame / 4
      return if pulse_frame == @last_cursor_pulse_frame
      @last_cursor_pulse_frame = pulse_frame
      draw_list
      draw_footer
    rescue
    end

    def update_mouse
      mx, my = mouse_pos
      return unless mx && my
      if (Input.trigger?(Input::MOUSELEFT) rescue false)
        if my.between?(SCREEN_H - FOOTER_H, SCREEN_H - 1) && controls_mouse_at?(mx, my)
          show_hint_popup
          return
        end
        if my.between?(TITLE_H, TITLE_H + POCKET_H - 1)
          switch_pocket(mx < SCREEN_W / 2 ? -1 : 1)
          return
        end
      end
      event = @item_list_state.update_input(
        :commands => false,
        :mouse_index => proc do |_x, y|
          next nil unless y.to_i.between?(LIST_Y, LIST_Y + LIST_H - 1)
          index = @scroll + ((y.to_i - LIST_Y) / ROW_H)
          index < current_items.length ? index : nil
        end
      )
      result = handle_item_list_event(event)
      result == :continue ? nil : result
    rescue
      nil
    end

    def mouse_pos
      pos = Reloaded::MouseInput.active_position rescue nil
      pos.is_a?(Array) ? pos : [nil, nil]
    rescue
      [nil, nil]
    end

    def key_trigger?(key)
      Input.triggerex?(key) rescue false
    end

    def key_repeat?(key)
      Input.repeatex?(key) rescue false
    end

    def mark_new_items
      previous = ($PokemonSystem.reloaded_bag_last_seen_qty rescue {}) || {}
      current = Autosort.snapshot_quantities
      @new_items = {}
      return if previous.empty?
      current.each do |item, qty|
        @new_items[item] = true if previous[item].to_i <= 0 && qty.to_i > 0
      end
    rescue
      @new_items = {}
    end

    def draw_all
      draw_title
      draw_pockets
      draw_list
      draw_info
      draw_footer
    end

    def draw_bg
      b = @sprites["bg"].bitmap
      b.clear
      b.fill_rect(0, 0, SCREEN_W, SCREEN_H, BG)
    end

    def draw_title
      b = @sprites["title"].bitmap
      b.clear
      b.fill_rect(0, 0, SCREEN_W, TITLE_H, TITLE_BG)
      pbSetSmallFont(b)
      shadow_text(b, PAD, 2, SCREEN_W - PAD * 2, TITLE_H - 2, "RLD Bag", BLUE)
    end

    def draw_pockets
      b = @sprites["pockets"].bitmap
      b.clear
      b.fill_rect(0, 0, SCREEN_W, POCKET_H, POCKET_BG)
      b.fill_rect(0, POCKET_H - 1, SCREEN_W, 1, SEP)
      return if @pockets.empty?
      pbSetSmallFont(b)
      label = "#{@pockets[@pocket_index][:name]}  (#{@pocket_index + 1}/#{@pockets.length})"
      shadow_text(b, 0, -3, SCREEN_W, POCKET_H, label, WHITE, 1)
      shadow_text(b, PAD, -3, 24, POCKET_H, "<", DIM)
      shadow_text(b, SCREEN_W - PAD - 24, -3, 24, POCKET_H, ">", DIM, 2)
    end

    def draw_list
      b = @sprites["list"].bitmap
      b.clear
      b.fill_rect(0, 0, SCREEN_W, LIST_H, PANEL_BG)
      if @pockets.empty?
        pbSetSmallFont(b)
        shadow_text(b, 0, LIST_H / 2 - 8, SCREEN_W, 18, "No matching items", DIM, 1)
        return
      end
      pbSetSmallFont(b)
      rows_per_page.times do |row|
        idx = @scroll + row
        break if idx >= current_items.length
        item = current_items[idx]
        y = row * ROW_H
        selected = idx == @item_index
        fill = selected ? pulsing_cursor_fill : ROW_HOVER
        border = selected ? cursor_border : nil
        draw_selection(b, PAD, y + 2, SCREEN_W - PAD * 2, ROW_H - 4, fill, border)
        fav = @adapter.favorite?(item)
        name = "#{fav ? "* " : ""}#{@adapter.display_name(item)}"
        move_data = @adapter.tm_move_data(item)
        name_color = if fav
                       FAV
                     elsif move_data
                       ReloadedBag.move_type_color(move_data.type)
                     else
                       selected ? WHITE : GRAY
                     end
        shadow_text(b, PAD + 7, y, SCREEN_W - 150, ROW_H, trim_text(b, name, SCREEN_W - 170), name_color)
        badge_x = SCREEN_W - 132
        if @new_items[item]
          badge_x = draw_badge(b, badge_x, y + 5, "NEW!", NEW_COLOR) + 4
        end
        if @adapter.held?(item)
          draw_badge(b, badge_x, y + 5, "HELD", HELD_COLOR)
        end
        if move_data
          draw_tm_type_icon(b, move_data.type, SCREEN_W - PAD - 38, y + 5)
        else
          qty = @adapter.qty(item)
          maxed = qty >= (Settings::BAG_MAX_PER_SLOT rescue 999)
          qty_text = maxed ? "MAX" : "x#{qty}"
          qty_color = maxed ? BLUE : (selected ? GOLD : DIM)
          shadow_text(b, 0, y, SCREEN_W - PAD - 5, ROW_H, qty_text, qty_color, 2)
        end
      end
      shadow_text(b, 0, 0, SCREEN_W, 14, "^", DIM, 1) if @scroll > 0
      if @scroll + rows_per_page < current_items.length
        shadow_text(b, 0, LIST_H - 14, SCREEN_W, 14, "v", DIM, 1)
      end
    end

    def draw_info
      b = @sprites["info"].bitmap
      b.clear
      b.fill_rect(0, 0, SCREEN_W, INFO_H, INFO_BG)
      b.fill_rect(0, 0, SCREEN_W, 1, SEP)
      item = current_items[@item_index]
      @sprites["itemicon"].item = item if @sprites["itemicon"]
      return unless item
      icon_x = SCREEN_W - 104
      draw_icon_box(b, icon_x, 10, 88, 88)
      pbSetSmallFont(b)
      name = @adapter.display_name(item)
      shadow_text(b, PAD, 5, icon_x - PAD * 2, 20, trim_text(b, name, icon_x - PAD * 2), @adapter.favorite?(item) ? FAV : WHITE)
      b.fill_rect(PAD, 29, icon_x - PAD * 2, 1, SEP)
      b.font.size = 16 rescue nil
      desc_lines(item).first(3).each_with_index do |line, i|
        plain_text(b, PAD, 28 + i * 18, icon_x - PAD * 2, 18, line, GRAY)
      end
    end

    def draw_footer
      b = @sprites["footer"].bitmap
      b.clear
      b.fill_rect(0, 0, SCREEN_W, FOOTER_H, TITLE_BG)
      pbSetSmallFont(b)
      b.font.size = 16 rescue nil
      mode = SORT_LABELS[current_sort_mode]
      if defined?(Reloaded::HintText)
        Reloaded::HintText.draw_footer(
          b,
          hint_entries,
          PAD,
          -1,
          SCREEN_W - PAD * 2,
          :size => 16,
          :color => WHITE,
          :align => 0,
          :height => FOOTER_H,
          :statuses => [Reloaded::HintText.status("Sort: #{mode}", BLUE)]
        )
      else
        hint = "Confirm (C) | Back (B) | Favorite (A) | Sort: #{mode} (L) | Pocket (< >)"
        plain_text(b, PAD, -4, SCREEN_W - PAD * 2, FOOTER_H + 3, hint, WHITE)
      end
    end

    def hint_entries
      mode = SORT_LABELS[current_sort_mode]
      [
        Reloaded::HintText.confirm,
        Reloaded::HintText.back,
        Reloaded::HintText.action("Favorite"),
        Reloaded::HintText.other("Sort: #{mode}", :sort),
        Reloaded::HintText.other("Pocket", :pocket)
      ]
    rescue
      []
    end

    def hint_triggered?
      defined?(Reloaded::HintText) && Reloaded::HintText.triggered?
    rescue
      false
    end

    def controls_mouse_at?(mx, my)
      return false unless defined?(Reloaded::HintText)
      Reloaded::HintText.controls_at?(@sprites["footer"].bitmap, mx, my - (SCREEN_H - FOOTER_H), PAD, -1, SCREEN_W - PAD * 2, :size => 16, :height => FOOTER_H)
    rescue
      false
    end

    def show_hint_popup
      pbPlayDecisionSE rescue nil
      if defined?(Reloaded::HintText)
        @item_list_state.with_dialog { Reloaded::HintText.open_popup("RLD Bag Hints", hint_entries) }
      end
      draw_all
    rescue
      draw_all rescue nil
    end

    def draw_selection(bitmap, x, y, w, h, fill, border = nil)
      if respond_to?(:reloaded_draw_rounded_rect)
        reloaded_draw_rounded_rect(bitmap, x, y, w, h, 4, fill, border)
      else
        bitmap.fill_rect(x, y, w, h, fill)
      end
    end

    def cursor_fill
      respond_to?(:reloaded_cursor_fill) ? reloaded_cursor_fill : Color.new(100, 160, 220, 160)
    end

    def pulsing_cursor_fill
      base = cursor_fill
      pulse = Math.sin((Graphics.frame_count rescue 0) * Math::PI / 20.0) * 0.5 + 0.5
      alpha = [[base.alpha.to_i + (pulse * 55).to_i, 255].min, 80].max
      Color.new(base.red, base.green, base.blue, alpha)
    rescue
      Color.new(100, 160, 220, 160)
    end

    def cursor_border
      respond_to?(:reloaded_cursor_border) ? reloaded_cursor_border : Color.new(60, 120, 180, 220)
    end

    def draw_badge(bitmap, x, y, text, color)
      bitmap.font.size = 14 rescue nil
      w = bitmap.text_size(text.to_s).width + 8
      bitmap.fill_rect(x, y, w, 14, Color.new(color.red / 3, color.green / 3, color.blue / 3, 255))
      pbDrawTextPositions(bitmap, [[text.to_s, x + w / 2, y - 7, 2, color, Color.new(0, 0, 0, 0)]])
      x + w
    rescue
      x
    ensure
      pbSetSmallFont(bitmap) rescue nil
    end

    def draw_icon_box(bitmap, x, y, w, h)
      bitmap.fill_rect(x, y, w, h, Color.new(14, 18, 30, 220))
      bitmap.fill_rect(x, y, w, 1, BORDER)
      bitmap.fill_rect(x, y + h - 1, w, 1, BORDER)
      bitmap.fill_rect(x, y, 1, h, BORDER)
      bitmap.fill_rect(x + w - 1, y, 1, h, BORDER)
    end

    def draw_tm_type_icon(bitmap, type_id, x, y)
      Reloaded::TypeIcons.draw(bitmap, type_id, x, y + 1, :badge, 32, 12)
    rescue
    end

    def desc_lines(item)
      b = @sprites["info"].bitmap
      desc = @adapter.description(item)
      width = SCREEN_W - 126
      lines = []
      current = ""
      desc.to_s.split(" ").each do |word|
        test = current.empty? ? word : "#{current} #{word}"
        if b.text_size(test).width > width
          lines << current
          current = word
        else
          current = test
        end
      end
      lines << current unless current.empty?
      lines
    rescue
      []
    end

    def trim_text(bitmap, text, width)
      value = text.to_s
      return value if bitmap.text_size(value).width <= width
      while value.length > 0 && bitmap.text_size(value + "...").width > width
        value = value[0...-1]
      end
      "#{value}..."
    rescue
      text.to_s
    end

    def shadow_text(bitmap, x, y, w, h, text, color, align = 0)
      pbDrawShadowText(bitmap, x, y, w, h, text.to_s, color, SHADOW, align)
    rescue
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
      pbDrawTextPositions(bitmap, [[text.to_s, draw_x, y, draw_align, color, Color.new(0, 0, 0, 0)]])
    rescue
    end

    def show_action_popup(title, commands, index = 0)
      if defined?(Reloaded::ActionMenu)
        rows = Array(commands).each_with_index.map { |cmd, i| { :id => i, :label => cmd.to_s } }
        start_index = rows.empty? ? 0 : index.to_i.clamp(0, rows.length - 1)
        result = Reloaded::ActionMenu.choose(
          title.to_s,
          rows,
          nil,
          :add_back => false,
          :start_id => start_index,
          :list_state => @item_list_state,
          :show_dim => true
        )
        return result.is_a?(Integer) && result >= 0 ? result : commands.length - 1
      end
      Kernel.pbMessage(title.to_s, commands, index)
    ensure
      @item_list_state.dialog_closed! if @item_list_state
      draw_all rescue nil
    end

    def draw_popup(bitmap, title, commands, selected)
      bitmap.clear
      bitmap.fill_rect(0, 0, bitmap.width, bitmap.height, Color.new(8, 14, 28, 235))
      bitmap.fill_rect(0, 0, bitmap.width, 1, BORDER)
      bitmap.fill_rect(0, bitmap.height - 1, bitmap.width, 1, BORDER)
      bitmap.fill_rect(0, 0, 1, bitmap.height, BORDER)
      bitmap.fill_rect(bitmap.width - 1, 0, 1, bitmap.height, BORDER)
      pbSetSmallFont(bitmap)
      plain_text(bitmap, 10, 0, bitmap.width - 20, 20, title.to_s, WHITE, 1)
      commands.each_with_index do |cmd, i|
        y = 32 + i * 24
        draw_selection(bitmap, 10, y + 2, bitmap.width - 20, 20, pulsing_cursor_fill, cursor_border) if i == selected
        plain_text(bitmap, 16, y - 6, bitmap.width - 32, 22, cmd.to_s, i == selected ? WHITE : GRAY)
      end
    end

    def drain_popup_input
      2.times do
        Graphics.update
        Input.update
      end
    rescue
    end
  end

  class Screen
    def initialize(scene, bag, choosing, filterproc)
      @scene = scene
      @bag = bag
      @choosing = choosing
      @filterproc = filterproc
    end

    def pbChooseItemScreen
      @scene.pbStartScreen(@bag, true, @filterproc)
      item = @scene.pbChooseItem
      @scene.pbEndScreen
      item
    end

    def pbStartScreen
      PartyPreloader.run
      @scene.pbStartScreen(@bag, false, nil)
      item = nil
      loop do
        item = @scene.pbChooseItem
        break unless item
        close = handle_item(item)
        break if close
      end
      @scene.pbEndScreen
      item
    end

    def handle_item(item)
      itm = GameData::Item.get(item)
      itemname = itm.name
      cmd_read = cmd_use = cmd_give = cmd_toss = cmd_register = cmd_debug = -1
      commands = []
      commands[cmd_read = commands.length] = _INTL("Read") if itm.is_mail?
      if ItemHandlers.hasOutHandler(item) || (itm.is_machine? && $Trainer.party.length > 0)
        commands[cmd_use = commands.length] = ItemHandlers.hasUseText(item) ? ItemHandlers.getUseText(item) : _INTL("Use")
      end
      commands[cmd_give = commands.length] = _INTL("Give") if $Trainer.pokemon_party.length > 0 && itm.can_hold?
      commands[cmd_toss = commands.length] = _INTL("Toss") if !itm.is_important? || $DEBUG
      if @bag.pbIsRegistered?(item)
        commands[cmd_register = commands.length] = _INTL("Deselect")
      elsif pbCanRegisterItem?(item)
        commands[cmd_register = commands.length] = _INTL("Register")
      end
      commands[cmd_debug = commands.length] = _INTL("Debug") if $DEBUG
      commands << _INTL("Cancel")
      command = @scene.pbShowCommands(_INTL("{1} is selected.", itemname), commands)
      if cmd_read >= 0 && command == cmd_read
        pbFadeOutIn { pbDisplayMail(Mail.new(item, "", "")) }
      elsif cmd_use >= 0 && command == cmd_use
        @scene.pbHide
        ret = pbUseItem(@bag, item, @scene)
        @scene.pbShow
        return true if ret == 2
        @scene.pbRefresh
      elsif cmd_give >= 0 && command == cmd_give
        give_item(item, itm, itemname)
      elsif cmd_toss >= 0 && command == cmd_toss
        toss_item(item, itm, itemname)
      elsif cmd_register >= 0 && command == cmd_register
        @bag.pbIsRegistered?(item) ? @bag.pbUnregisterItem(item) : @bag.pbRegisterItem(item)
        @scene.pbRefresh
      elsif cmd_debug >= 0 && command == cmd_debug
        debug_item(item)
      end
      false
    end

    def give_item(item, itm, itemname)
      if $Trainer.pokemon_count == 0
        @scene.pbDisplay(_INTL("There is no Pokemon."))
      elsif itm.is_important?
        @scene.pbDisplay(_INTL("The {1} can't be held.", itemname))
      else
        pbFadeOutIn do
          sscene = PokemonParty_Scene.new
          sscreen = PokemonPartyScreen.new(sscene, $Trainer.party)
          sscreen.pbPokemonGiveScreen(item)
        end
        @scene.pbRefreshAfterGive
      end
    end

    def toss_item(item, itm, itemname)
      qty = @bag.pbQuantity(item)
      qty = @scene.pbChooseNumber(_INTL("Toss out how many {1}?", itm.name_plural), qty) if qty > 1
      return if qty <= 0
      toss_name = qty > 1 ? itm.name_plural : itemname
      if @scene.pbConfirm(_INTL("Throw away {1}(s)?", itemname))
        if !@bag.pbDeleteItem(item, qty)
          raise "Can't delete items from Bag"
        end
        @scene.pbRefresh
        @scene.pbDisplay(_INTL("Threw away {1} {2}.", qty, toss_name))
      end
    end

    def debug_item(item)
      qty = @bag.pbQuantity(item)
      if defined?(Reloaded::NumberPicker)
        newqty = Reloaded::NumberPicker.open(
          _INTL("Choose new quantity of {1}.", GameData::Item.get(item).name_plural),
          :min => 0,
          :max => Settings::BAG_MAX_PER_SLOT,
          :initial => qty,
          :step => 1,
          :large_step => 10,
          :show_max_label => true,
          :allow_max_shortcut => true
        )
        return if newqty.nil?
        if newqty > qty
          @bag.pbStoreItem(item, newqty - qty)
        elsif newqty < qty
          @bag.pbDeleteItem(item, qty - newqty)
        end
        @scene.pbRefresh
        return
      end
      params = ChooseNumberParams.new
      params.setRange(0, Settings::BAG_MAX_PER_SLOT)
      params.setDefaultValue(qty)
      newqty = pbMessageChooseNumber(
        _INTL("Choose new quantity of {1} (max. {2}).", GameData::Item.get(item).name_plural, Settings::BAG_MAX_PER_SLOT),
        params
      ) { @scene.pbUpdate }
      if newqty > qty
        @bag.pbStoreItem(item, newqty - qty)
      elsif newqty < qty
        @bag.pbDeleteItem(item, qty - newqty)
      end
      @scene.pbRefresh
    end
  end

  class AutosortOptionsScene < PokemonOption_Scene
    def initUIElements
      super
      @sprites["title"].text = _INTL("Reloaded Bag Autosort") rescue nil
    end

    def pbGetOptions(_inloadscreen = false)
      [
        EnumOption.new(
          _INTL("Pocket Sorting"),
          [_INTL("Off"), _INTL("On")],
          proc { ($PokemonSystem.reloaded_bag_pocket_sort rescue 0).to_i },
          proc { |value| $PokemonSystem.reloaded_bag_pocket_sort = value.to_i if $PokemonSystem },
          _INTL("Off: all pockets use the same sort mode.\nOn: each pocket remembers its own sort mode.")
        ),
        ActionButton.new(
          _INTL("Edit Custom Order"),
          proc { open_custom_order_editor },
          _INTL("Edit item order used by the List sort mode.")
        ),
        ActionButton.new(
          _INTL("Export Autosort"),
          proc {
            path = ReloadedBag::Autosort.export_all
            toast_message(path ? _INTL("Exported autosort list to:\n{1}", ReloadedBag.sanitize_path(path)) : _INTL("Autosort export failed."))
          },
          _INTL("Export custom list order to Mods/Reloaded/ReloadedBagAutosort.txt.")
        ),
        ActionButton.new(
          _INTL("Import Autosort"),
          proc {
            result = ReloadedBag::Autosort.import
            if result[:ok]
              toast_message(_INTL("Imported autosort list.\nPockets: {1}", result[:pockets].join(", ")))
            else
              toast_message(_INTL("Autosort import failed:\n{1}", result[:error]))
            end
          },
          _INTL("Import custom list order from Mods/Reloaded/ReloadedBagAutosort.txt.")
        )
      ]
    end

    def open_custom_order_editor
      visibility = {}
      @sprites.each do |key, sprite|
        next unless sprite && sprite.respond_to?(:visible) && sprite.respond_to?(:visible=)
        visibility[key] = sprite.visible
        sprite.visible = false
      end
      ReloadedBag::CustomOrderEditor.open
    ensure
      visibility ||= {}
      @sprites.each do |key, sprite|
        next unless sprite && sprite.respond_to?(:visible=)
        sprite.visible = visibility.key?(key) ? visibility[key] : true
      end
      refresh rescue nil
    end
  end

  module CustomOrderEditor
    module_function

    def open
      pockets = []
      1.upto((PokemonBag.numPockets rescue 1)) do |pid|
        name = PokemonBag.pocketNames[pid] rescue "Pocket #{pid}"
        pockets << [pid, name]
      end
      commands = pockets.map { |row| row[1].to_s }
      selected_pocket = 0
      loop do
        choice = choose_pocket_popup(_INTL("Edit which pocket?"), commands, selected_pocket)
        break if choice < 0 || choice >= pockets.length
        selected_pocket = choice
        EditorScene.new(pockets[choice][0], pockets[choice][1]).main
      end
    rescue Exception => e
      ReloadedBag.log_exception("Reloaded Bag custom order editor failed", e)
      ReloadedBag.toast_message(_INTL("Custom order editor failed."))
    end

    def choose_pocket_popup(prompt, commands, start_index = 0)
      if defined?(Reloaded::ListPicker)
        rows = Array(commands).each_with_index.map { |cmd, i| { :label => cmd.to_s, :value => i } }
        start_value = start_index.to_i
        start_value = nil if start_value < 0 || start_value >= rows.length
        result = Reloaded::ListPicker.popup(
          prompt.to_s,
          rows,
          :start_value => start_value,
          :add_back => true,
          :show_dim => true,
          :width => 300
        )
        return result.nil? ? -1 : result.to_i
      end
      if defined?(Reloaded) && Reloaded.respond_to?(:choice)
        rows = Array(commands).each_with_index.map { |cmd, i| { :label => cmd.to_s, :value => i } }
        return Reloaded.choice(
          prompt.to_s,
          rows,
          :start_index => start_index.to_i,
          :show_dim => true
        )
      end
      row_h = 24
      width = 260
      height = 36 + commands.length * row_h + 20
      x = (SCREEN_W - width) / 2
      y = (SCREEN_H - height) / 2
      viewport = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
      viewport.z = 999_999_999
      popup = Sprite.new(viewport)
      popup.bitmap = Bitmap.new(width, height)
      popup.x = x
      popup.y = y
      popup.z = 999_999_999
      selected = start_index.to_i.clamp(0, commands.length - 1)
      redraw = proc do
        draw_choice_popup(popup.bitmap, prompt.to_s, commands, selected)
      end
      redraw.call
      loop do
        Graphics.update
        Input.update
        redraw.call if ((Graphics.frame_count rescue 0) % 4 == 0)
        old = selected
        if Input.repeat?(Input::UP)
          selected = (selected - 1 + commands.length) % commands.length
        elsif Input.repeat?(Input::DOWN)
          selected = (selected + 1) % commands.length
        elsif Input.repeat?(Input::LEFT)
          selected = (selected - 3 + commands.length) % commands.length
        elsif Input.repeat?(Input::RIGHT)
          selected = (selected + 3) % commands.length
        elsif Input.trigger?(Input::USE)
          pbPlayDecisionSE
          drain_popup_input
          return selected
        elsif Input.trigger?(Input::BACK)
          pbPlayCancelSE rescue nil
          drain_popup_input
          return commands.length - 1
        end
        pbPlayCursorSE if old != selected
        redraw.call if old != selected
      end
    ensure
      popup.bitmap.dispose rescue nil
      popup.dispose rescue nil
      viewport.dispose rescue nil
    end

    def draw_choice_popup(bitmap, title, commands, selected)
      bitmap.clear
      bitmap.fill_rect(0, 0, bitmap.width, bitmap.height, Color.new(8, 14, 28, 235))
      bitmap.fill_rect(0, 0, bitmap.width, 1, BORDER)
      bitmap.fill_rect(0, bitmap.height - 1, bitmap.width, 1, BORDER)
      bitmap.fill_rect(0, 0, 1, bitmap.height, BORDER)
      bitmap.fill_rect(bitmap.width - 1, 0, 1, bitmap.height, BORDER)
      pbSetSmallFont(bitmap)
      pbDrawTextPositions(bitmap, [[title.to_s, bitmap.width / 2, 0, 2, WHITE, Color.new(0, 0, 0, 0)]])
      commands.each_with_index do |cmd, i|
        y = 32 + i * 24
        if i == selected
          if respond_to?(:reloaded_draw_rounded_rect)
            reloaded_draw_rounded_rect(bitmap, 10, y + 2, bitmap.width - 20, 20, 4, pulsing_cursor_fill, cursor_border)
          else
            bitmap.fill_rect(10, y + 2, bitmap.width - 20, 20, pulsing_cursor_fill)
          end
        end
        pbDrawTextPositions(bitmap, [[cmd.to_s, 16, y - 6, 0, i == selected ? WHITE : GRAY, Color.new(0, 0, 0, 0)]])
      end
    end

    def cursor_fill
      respond_to?(:reloaded_cursor_fill) ? reloaded_cursor_fill : Color.new(100, 160, 220, 160)
    end

    def pulsing_cursor_fill
      base = cursor_fill
      pulse = Math.sin((Graphics.frame_count rescue 0) * Math::PI / 20.0) * 0.5 + 0.5
      alpha = [[base.alpha.to_i + (pulse * 55).to_i, 255].min, 80].max
      Color.new(base.red, base.green, base.blue, alpha)
    rescue
      Color.new(100, 160, 220, 160)
    end

    def cursor_border
      respond_to?(:reloaded_cursor_border) ? reloaded_cursor_border : Color.new(60, 120, 180, 220)
    end

    def drain_popup_input
      2.times do
        Graphics.update
        Input.update
      end
    rescue
    end

    class EditorScene
      include ReloadedDrawHelper if defined?(ReloadedDrawHelper)

      def initialize(pocket_id, pocket_name)
        @pocket_id = pocket_id
        @pocket_name = pocket_name
        @items = Autosort.ensure_list_for_pocket(@pocket_id)
        @index = 0
        @scroll = 0
        @held_index = nil
        @last_cursor_pulse_frame = -1
        @editor_list_state = Reloaded::ListState.new(
          :key => [:reloaded_bag_custom_order, @pocket_id],
          :rows => @items,
          :visible_rows => 13,
          :row_id => proc { |item| item },
          :wrap => true,
          :jump_size => 3,
          :remember => true
        )
        sync_editor_list_state
      end

      def main
        result = :back
        setup
        draw
        loop do
          Graphics.update
          Input.update
          tick_cursor_pulse
          if hint_triggered?
            show_hint_popup
          elsif controls_mouse_clicked?
            show_hint_popup
          elsif Input.const_defined?(:ACTION) && Input.trigger?(Input::ACTION)
            toggle_pickup
          else
            event = @editor_list_state.update_input(
              :mouse_activate => false,
              :mouse_index => proc do |_x, y|
                next nil unless y.to_i.between?(42, 42 + 13 * ROW_H - 1)
                index = @scroll + ((y.to_i - 42) / ROW_H)
                index < @items.length ? index : nil
              end
            )
            action = handle_editor_list_event(event)
            if action == :save
              save
              result = :saved
              break
            elsif action == :back
              result = :back
              break
            end
          end
        end
        result
      ensure
        teardown
      end

      def setup
        @viewport = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
        @viewport.z = 999_999_999
        @sprite = Sprite.new(@viewport)
        @sprite.z = 999_999_999
        @sprite.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
      end

      def teardown
        @sprite.bitmap.dispose rescue nil
        @sprite.dispose rescue nil
        @viewport.dispose rescue nil
      end

      def move(delta)
        handle_editor_list_event(@editor_list_state.move(delta))
      end

      def handle_editor_list_event(event)
        return :continue unless event
        if event.moved? && @held_index
          moved_item = @items.delete_at(event.previous_index)
          @items.insert(event.index, moved_item) if moved_item
          @held_index = event.index
          @editor_list_state.replace_rows(@items, :preserve => :id)
        end
        sync_editor_list_state
        case event.type
        when :moved
          pbPlayCursorSE rescue nil
          draw
        when :activate
          return :save
        when :back
          return :back
        end
        :continue
      end

      def sync_editor_list_state
        @index = @editor_list_state.index || 0
        @scroll = @editor_list_state.scroll
      end

      def toggle_pickup
        @held_index = @held_index ? nil : @index
        pbPlayDecisionSE
        draw
      end

      def tick_cursor_pulse
        frame = (Graphics.frame_count rescue 0)
        pulse_frame = frame / 4
        return if pulse_frame == @last_cursor_pulse_frame
        @last_cursor_pulse_frame = pulse_frame
        draw
      rescue
      end

      def ensure_visible
        @editor_list_state.visible_rows = 13
        @editor_list_state.ensure_visible!
        sync_editor_list_state
      end

      def save
        lists = ($PokemonSystem.reloaded_bag_list_orders rescue {}) || {}
        lists[@pocket_id] = @items
        $PokemonSystem.reloaded_bag_list_orders = lists
        ReloadedBag.log_info("Saved Reloaded Bag custom order for pocket #{@pocket_id}")
        ReloadedBag.toast_message(_INTL("Custom order saved."))
      end

      def draw
        b = @sprite.bitmap
        b.clear
        b.fill_rect(0, 0, SCREEN_W, SCREEN_H, BG)
        pbSetSmallFont(b)
        pbDrawShadowText(b, 0, 8, SCREEN_W, 24, "CUSTOM ORDER: #{@pocket_name}".upcase, WHITE, SHADOW, 1)
        rows = 13
        rows.times do |row|
          idx = @scroll + row
          break if idx >= @items.length
          y = 42 + row * ROW_H
          selected = idx == @index
          fill = selected ? pulsing_cursor_fill : ROW_HOVER
          border = selected ? (respond_to?(:reloaded_cursor_border) ? reloaded_cursor_border : Color.new(60, 120, 180, 220)) : nil
          if respond_to?(:reloaded_draw_rounded_rect)
            reloaded_draw_rounded_rect(b, 16, y + 2, SCREEN_W - 32, ROW_H - 4, 4, fill, border)
          else
            b.fill_rect(16, y + 2, SCREEN_W - 32, ROW_H - 4, fill)
          end
          item_name = GameData::Item.try_get(@items[idx])&.name || @items[idx].to_s
          color = @held_index == idx ? GOLD : (selected ? WHITE : GRAY)
          pbDrawShadowText(b, 26, y, 34, ROW_H, (idx + 1).to_s, WHITE, SHADOW, 1)
          pbDrawShadowText(b, 66, y, SCREEN_W - 86, ROW_H, item_name, color, SHADOW)
        end
        pbSetSmallFont(b)
        b.font.size = 16 rescue nil
        if defined?(Reloaded::HintText)
          Reloaded::HintText.draw_footer(b, hint_entries, 8, SCREEN_H - 25, SCREEN_W - 16, :size => 16, :color => WHITE, :align => 0, :height => 25)
        else
          hint = "Save (C) | Back (B) | Pick Up/Place (A)"
          pbDrawTextPositions(b, [[hint, 8, SCREEN_H - 25, 0, WHITE, Color.new(0, 0, 0, 0)]])
        end
      end

      def hint_entries
        [
          Reloaded::HintText.confirm("Save"),
          Reloaded::HintText.back,
          Reloaded::HintText.action("Pick Up/Place"),
          Reloaded::HintText.other("Move 3", :page)
        ]
      rescue
        []
      end

      def hint_triggered?
        defined?(Reloaded::HintText) && Reloaded::HintText.triggered?
      rescue
        false
      end

      def controls_mouse_clicked?
        return false unless defined?(Reloaded::HintText)
        return false unless (Input.trigger?(Input::MOUSELEFT) rescue false)
        pos = Reloaded::MouseInput.active_position rescue nil
        return false unless pos.is_a?(Array)
        Reloaded::HintText.controls_at?(@sprite.bitmap, pos[0], pos[1], 8, SCREEN_H - 25, SCREEN_W - 16, :size => 16, :height => 25)
      rescue
        false
      end

      def show_hint_popup
        pbPlayDecisionSE rescue nil
        if defined?(Reloaded::HintText)
          @editor_list_state.with_dialog { Reloaded::HintText.open_popup("Custom Order Hints", hint_entries) }
        end
        draw
      rescue
        draw rescue nil
      end

      def pulsing_cursor_fill
        base = respond_to?(:reloaded_cursor_fill) ? reloaded_cursor_fill : Color.new(100, 160, 220, 160)
        pulse = Math.sin((Graphics.frame_count rescue 0) * Math::PI / 20.0) * 0.5 + 0.5
        alpha = [[base.alpha.to_i + (pulse * 55).to_i, 255].min, 80].max
        Color.new(base.red, base.green, base.blue, alpha)
      rescue
        Color.new(100, 160, 220, 160)
      end
    end
  end
end

ReloadedBag.install
