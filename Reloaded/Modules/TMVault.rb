#======================================================
# Reloaded TM Vault
# Author: Stonewall
#======================================================
# Persistent TM/HM and tutor-move vault for free move re-teaching.
#
# Responsibilities:
#   - Store registered moves inside the Reloaded save bucket.
#   - Register TM/HM and tutor moves as the player obtains them.
#   - Provide the TM Vault full-screen teaching UI.
#   - Add the TM Vault PokeNav app when enabled.
#   - Keep the REPM TM Vault entry available regardless of PokeNav setting.
#
#======================================================

module Reloaded
  module TMVaultFeature
    class << self
      def install
        install_pokemon_system_settings
        register_option
        true
      rescue Exception => e
        Reloaded::Log.exception("TM Vault install failed", e, channel: :modules) if defined?(Reloaded::Log)
        false
      end

      def install_pokemon_system_settings
        return unless defined?(PokemonSystem)
        PokemonSystem.class_eval do
          def hr_tmvault
            @hr_tmvault.nil? ? 1 : @hr_tmvault.to_i
          end

          def hr_tmvault=(value)
            @hr_tmvault = value.to_i
          end
        end
      end

      def register_option
        return unless defined?(Reloaded::Options) && Reloaded::Options.respond_to?(:register_category_option)
        Reloaded::Options.register_category_option("GAMEPLAY", :tm_vault, priority: 1) do |_scene|
          [ActionButton.new(
            _INTL("TM Vault"),
            proc { TMVault.open_options if defined?(TMVault) },
            _INTL("Open TM Vault options.")
          )]
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to register TM Vault option", e, channel: :options) if defined?(Reloaded::Log)
      end
    end
  end
end

Reloaded::TMVaultFeature.install if defined?(Reloaded::TMVaultFeature)

module TMVault

  # -- Palette --------------------------------------------------------------
  SCREEN_W  = 512
  SCREEN_H  = 384

  BG_COLOR     = Color.new(10,  20,  40,  255)
  PANEL_BG     = Color.new(18,  32,  62)
  PANEL_BORDER = Color.new(50,  90,  160)
  TITLE_BG     = Color.new(12,  24,  50)
  FOOTER_BG    = Color.new(12,  24,  50)

  WHITE        = Color.new(255, 255, 255)
  GRAY         = Color.new(180, 180, 180)
  DIM          = Color.new(120, 120, 140)
  SHADOW       = Color.new(10,  15,  30)

  COLOR_COMPAT = Color.new(120, 230, 120)   # green  - can learn
  COLOR_KNOWS  = Color.new(120, 200, 255)   # cyan   - already knows
  COLOR_CANT   = Color.new(130, 120, 150)   # dim    - can't learn
  COLOR_GOLD   = Color.new(240, 220, 80)    # gold   - active filter label

  # -- Layout ---------------------------------------------------------------
  TITLE_H  = 36
  FOOTER_H = 28
  LEFT_W   = 220
  RIGHT_W  = SCREEN_W - LEFT_W - 16   # 276
  CONT_Y   = TITLE_H + 2
  CONT_H   = SCREEN_H - TITLE_H - FOOTER_H - 4
  ROW_H    = 20

  ROW_SEL  = Color.new(255, 255, 255, 30)
  ROW_NORM = Color.new(255, 255, 255, 8)

  # Party icon grid (coordinates are relative to the right panel)
  PARTY_COLS   = 3
  PARTY_X0     = 18
  PARTY_Y0     = 14
  PARTY_X_GAP  = 88
  PARTY_Y_GAP  = 100
  PARTY_ICO_W  = 64
  PARTY_ICO_H  = 64

  ICON_PATH = "Reloaded/Graphics/Pokegear/icon_TMVAULT"
  SORT_NAMES = ["Name", "Type", "Category", "Recent", "Level Learned"].freeze

  # -- Data helpers ---------------------------------------------------------

  def self.data
    return Reloaded::SaveData.system(:tm_vault) if defined?(Reloaded::SaveData)
    @fallback_data ||= {}
  end
  def self.vault
    raw = data["moves"] || data[:moves] || []
    valid = []
    invalid = []
    Array(raw).each do |entry|
      id = normalize_move_id(entry)
      id ? valid << id : invalid << entry
    end
    valid = valid.uniq
    if invalid.any? || Array(raw) != valid
      log_invalid_moves(invalid)
      save_vault(valid)
    else
      data["moves"] = valid
    end
    valid
  end

  def self.save_vault(list)
    normalized = Array(list).map { |id| normalize_move_id(id) }.compact.uniq
    if defined?(Reloaded::SaveData)
      Reloaded::SaveData.set(:tm_vault, :moves, normalized, section: :systems)
    else
      data["moves"] = normalized
    end
    prune_sources(normalized)
    normalized
  end

  def self.source_map
    raw = data["sources"] || data[:sources] || {}
    raw = {} unless raw.is_a?(Hash)
    data["sources"] = raw
    raw
  end

  def self.sort_mode
    value = data["sort_mode"] || data[:sort_mode] || 0
    value.to_i.clamp(0, SORT_NAMES.length - 1)
  end

  def self.sort_mode=(value)
    normalized = value.to_i.clamp(0, SORT_NAMES.length - 1)
    if defined?(Reloaded::SaveData)
      Reloaded::SaveData.set(:tm_vault, :sort_mode, normalized, section: :systems)
    else
      data["sort_mode"] = normalized
    end
  end

  def self.egg_moves_enabled?
    value = data.key?("egg_moves") ? data["egg_moves"] : data[:egg_moves]
    value.nil? ? true : !!value
  end

  def self.egg_moves_enabled=(value)
    enabled = value ? true : false
    if defined?(Reloaded::SaveData)
      Reloaded::SaveData.set(:tm_vault, :egg_moves, enabled, section: :systems)
    else
      data["egg_moves"] = enabled
    end
  end

  def self.source_for(move_id)
    source_map[move_key(move_id)] || []
  end

  def self.open_options

    return unless defined?(TMVault::OptionsScene)
    pbFadeOutIn do
      scene = TMVault::OptionsScene.new
      screen = PokemonOptionScreen.new(scene)
      screen.pbStartScreen
    end
  rescue Exception => e
    Reloaded::Log.exception("TM Vault options failed", e, channel: :options) if defined?(Reloaded::Log)
  end

  def self.normalize_move_id(move_id)
    move = GameData::Move.try_get(move_id) rescue nil
    move&.id
  end

  def self.move_key(move_id)
    id = normalize_move_id(move_id) || move_id
    id.to_s
  end

  def self.normalize_source(source)
    value = source.to_s.strip.downcase
    case value
    when "tm", "hm", "machine" then "Machine"
    when "tutor", "move_tutor" then "Tutor"
    when "shop", "mart" then "Shop"
    when "pickup", "item_ball" then "Pickup"
    when "receive", "gift", "event" then "Receive"
    when "bag", "bag_scan" then "Bag Scan"
    else "Script"
    end
  end

  def self.record_source(move_id, source)
    key = move_key(move_id)
    label = normalize_source(source)
    sources = Array(source_map[key])
    sources << label unless sources.include?(label)
    source_map[key] = sources
    Reloaded::SaveData.set(:tm_vault, :sources, source_map, section: :systems) if defined?(Reloaded::SaveData)
    sources
  end

  def self.prune_sources(valid_moves)
    valid_keys = Array(valid_moves).map { |id| move_key(id) }
    sources = source_map
    before = sources.length
    sources.keys.each { |key| sources.delete(key) unless valid_keys.include?(key) }
    Reloaded::SaveData.set(:tm_vault, :sources, sources, section: :systems) if defined?(Reloaded::SaveData) && before != sources.length
  end

  def self.log_invalid_moves(entries)
    Array(entries).each do |entry|
      key = entry.to_s
      next if key.empty?
      @invalid_log_once ||= {}
      next if @invalid_log_once[key]
      @invalid_log_once[key] = true
      Reloaded::Log.warning("TM Vault removed invalid or missing move #{key}", :modules) if defined?(Reloaded::Log)
    end
  end

  def self.emit(event_name, context = {})
    Reloaded::Events.emit(event_name, context) if defined?(Reloaded::Events)
  rescue Exception => e
    Reloaded::Log.exception("TM Vault event #{event_name} failed", e, channel: :modules) if defined?(Reloaded::Log)
  end

  def self.register(move_id, notify: false, source: :script)
    return false unless $Trainer
    md = GameData::Move.try_get(move_id)
    unless md
      log_invalid_moves([move_id])
      return false
    end
    id = md.id
    list = vault
    already_registered = list.include?(id)
    record_source(id, source)
    return false if already_registered
    list << id
    save_vault(list)
    emit(:tm_vault_move_registered, :move => id, :move_data => md, :source => normalize_source(source))
    pbMessage(_INTL("{1} was added to your TM Vault!", md.name)) if notify
    true
  rescue Exception => e
    Reloaded::Log.exception("TM Vault register failed", e, channel: :modules) if defined?(Reloaded::Log)
    false
  end

  # Scan ALL bag pockets and register every TM/HM found.
  # Scans all pockets (not just pocket 4) to handle IF's bag layout.
  def self.pocket_scan
    return unless $PokemonBag && $Trainer
    pockets = ($PokemonBag.pockets rescue nil)
    return unless pockets.is_a?(Array)
    pockets.each do |pocket|
      next unless pocket.is_a?(Array)
      pocket.each do |entry|
        item_id = entry.is_a?(Array) ? entry[0] : entry
        next unless item_id
        itm = GameData::Item.try_get(item_id)
        next unless itm && itm.is_machine? && itm.move
        register(itm.move, notify: false, source: :bag_scan)
      end
    end
  end

  # Returns :knows, :compat, :cant, or :none
  def self.compat(move_id, pokemon)
    return :none unless pokemon && !pokemon.egg?
    return :knows  if pokemon.hasMove?(move_id)
    return :compat if pokemon.compatible_with_move?(move_id)
    :cant
  end

  # Module-level TM label cache — built once per game session.
  def self.tm_label_cache
    return @tm_label_cache if @tm_label_cache
    @tm_label_cache = {}
    GameData::Item.each do |itm|
      next unless itm.is_machine? && itm.move
      @tm_label_cache[itm.move] = itm.name
    end rescue nil
    @tm_label_cache ||= {}
  end

  def self.egg_icon_bitmap
    return @egg_icon_bitmap if @egg_icon_bitmap
    @egg_icon_animated_bitmap = AnimatedBitmap.new("Graphics/Icons/iconEgg") rescue nil
    @egg_icon_bitmap = @egg_icon_animated_bitmap&.bitmap
  rescue
    @egg_icon_bitmap = nil
  end

  # -- PokeNav app ID -------------------------------------------------------
  # PokeNav icon: Reloaded/Graphics/Pokegear/icon_TMVAULT.png
  if defined?(Pokenav) && !Pokenav::AVAILABLE_APPS.key?(:TMVAULT)
    Pokenav::AVAILABLE_APPS[:TMVAULT] = "TM Vault"
  end

  def self.open
    pocket_scan
    emit(:tm_vault_opened, :move_count => vault.length)
    pbFadeOutIn { TMVault::Scene.new.main }
  end

  def self.sync_pokenav_app
    return unless defined?(Pokenav) && $Trainer && $Trainer.pokenav
    Pokenav::AVAILABLE_APPS[:TMVAULT] = "TM Vault" unless Pokenav::AVAILABLE_APPS.key?(:TMVAULT)
    apps = $Trainer.pokenav.installed_apps
    if ($PokemonSystem.hr_tmvault rescue 1).to_i == 1
      apps << :TMVAULT unless apps.include?(:TMVAULT)
    else
      apps.delete(:TMVAULT)
    end
  rescue Exception => e
    Reloaded::Log.exception("TM Vault PokeNav sync failed", e, channel: :modules) if defined?(Reloaded::Log)
  end

  class OptionsScene < PokemonOption_Scene
    def initUIElements
      super
      @sprites["title"].text = _INTL("TM Vault") rescue nil
    end

    def pbGetOptions(_inloadscreen = false)
      [
        EnumOption.new(
          _INTL("TM Vault"),
          [_INTL("Off"), _INTL("PokeNav")],
          proc { ($PokemonSystem.hr_tmvault rescue 1).to_i == 1 ? 1 : 0 },
          proc { |value|
            $PokemonSystem.hr_tmvault = value.to_i if $PokemonSystem
            TMVault.sync_pokenav_app if defined?(TMVault)
          },
          _INTL("Controls whether TM Vault appears in the PokeNav. REPM access remains available.")
        ),
        EnumOption.new(
          _INTL("Egg Moves"),
          [_INTL("Off"), _INTL("On")],
          proc { TMVault.egg_moves_enabled? ? 1 : 0 },
          proc { |value| TMVault.egg_moves_enabled = value.to_i == 1 },
          _INTL("Controls whether TM Vault's Relearn Moves mode includes egg moves.")
        )
      ]
    end
  end

  # -- Scene -----------------------------------------------------------------
  class Scene
    include Reloaded::ModManagerUI::UIHelpers if defined?(Reloaded::ModManagerUI::UIHelpers)

    def main

      setup
      loop do
        Graphics.update
        Input.update
        @party_icons.compact.each(&:update)
        # Animate cursor: redraw left panel every 2 frames so the pulse is smooth
        @cursor_tick = (@cursor_tick + 1) % 40
        draw_left if @focus == :list && @cursor_tick % 2 == 0
        draw_footer if @cursor_tick % 2 == 0
        break unless @running
        handle_input
      end
      teardown
    end

    private

    # -- Setup / Teardown -----------------------------------------------------
    def setup
      @running    = true
      @sel        = 0
      @scroll     = 0
      @filter_mon = nil
      @move_mode  = :vault
      @relearn_mon = nil
      @pending_relearn_pick = false
      @focus      = :list   # :list or :party
      @party_sel  = 0
      @cursor_tick = 0      # frame counter for animated cursor pulse

      @vp = Viewport.new(0, 0, SCREEN_W, SCREEN_H)
      @vp.z = 100_000

      @bg       = Sprite.new(@vp)
      @bg.bitmap = Bitmap.new(SCREEN_W, SCREEN_H)
      @bg.bitmap.fill_rect(0, 0, SCREEN_W, SCREEN_H, BG_COLOR)

      @title_spr  = BitmapSprite.new(SCREEN_W, TITLE_H,   @vp)
      @left_spr   = BitmapSprite.new(LEFT_W,   CONT_H,    @vp)
      @right_spr  = BitmapSprite.new(RIGHT_W,  CONT_H,    @vp)
      @footer_spr = BitmapSprite.new(SCREEN_W, FOOTER_H,  @vp)

      @title_spr.z  = 10
      @left_spr.z   = 10
      @right_spr.z  = 10
      @footer_spr.z = 10

      @left_spr.x   = 4;         @left_spr.y   = CONT_Y
      @right_spr.x  = LEFT_W+12; @right_spr.y  = CONT_Y
      @footer_spr.y = SCREEN_H - FOOTER_H

      # Party icon sprites � drawn on the right panel
      @party_icons = Array.new(6) do |i|
        pkmn = $Trainer.party[i]
        next nil unless pkmn
        col = i % PARTY_COLS
        row = i / PARTY_COLS
        row_y_extra = row == 1 ? 10 : 0
        ico = PokemonIconSprite.new(pkmn, @vp)
        ico.setOffset(PictureOrigin::Center)
        ico.x = @right_spr.x + PARTY_X0 + col * PARTY_X_GAP + PARTY_ICO_W / 2
        ico.y = CONT_Y + PARTY_Y0 + row * PARTY_Y_GAP + PARTY_ICO_H / 2 + row_y_extra
        ico.z = 20
        ico
      end

      @_sprites = { "bg" => @bg, "title" => @title_spr, "left" => @left_spr,
                    "right" => @right_spr, "footer" => @footer_spr }
      @party_icons.compact.each_with_index { |ico, i| @_sprites["icon#{i}"] = ico }

      build_list
      clamp_scroll
      TMVault.pocket_scan          # fast: scans bag for any unregistered TMs; deduped
      build_list                   # rebuild in case pocket_scan added new entries
      clamp_scroll
      TMVault.tm_label_cache       # instant: pre-warmed at game boot
      draw_all
    end

    def teardown
      @party_icons.compact.each { |ico| ico.dispose rescue nil }
      [@footer_spr, @right_spr, @left_spr, @title_spr, @bg].compact.each do |s|
        s.bitmap.dispose rescue nil; s.dispose rescue nil
      end
      @vp.dispose rescue nil
    end

    # -- List building --------------------------------------------------------
    def build_list
      preserve_move = selected_move_id rescue nil
      mon = @filter_mon && $Trainer.party[@filter_mon]
      full = if @move_mode == :relearn
        relearnable_moves_for(@relearn_mon)
      else
        @relearn_egg_move_ids = []
        sorted_vault_moves(mon)
      end
      @list = if mon
        full.select { |id| mon.hasMove?(id) || mon.compatible_with_move?(id) }
      else
        full
      end
      sync_move_list_state(preserve_move)
    end

    def sorted_vault_moves(pokemon = nil)
      sort_moves(TMVault.vault, pokemon)
    end

    def sort_moves(move_ids, pokemon = nil)
      sort = TMVault.sort_mode
      moves = Array(move_ids)
      positions = {}
      moves.each_with_index { |id, index| positions[id] ||= index }
      moves.sort_by do |id|
        md = GameData::Move.try_get(id)
        case sort
        when 1
          [(GameData::Type.get(md&.type)&.name rescue "ZZZ"), md&.name.to_s.downcase]
        when 2
          [md&.category.to_i, md&.name.to_s.downcase]
        when 3
          pokemon ? positions[id].to_i : -(positions[id].to_i)
        when 4
          level_learned_sort_key(id, pokemon)
        else
          (md&.name || id.to_s).downcase
        end
      end
    end

    def level_learned_sort_key(move_id, pokemon)
      name = (GameData::Move.try_get(move_id)&.name || move_id.to_s).downcase
      return [3, 0, name] unless pokemon
      levels = Array(pokemon.getMoveList).each_with_object([]) do |entry, found|
        found << entry[0].to_i if entry[1] == move_id
      end
      return [0, levels.min, name] unless levels.empty?
      return [0, 0, name] if Array(pokemon.first_moves).include?(move_id)
      return [2, 0, name] if relearn_egg_move?(move_id)
      [1, 0, name]
    rescue
      [3, 0, name]
    end

    def relearnable_moves_for(index)
      pkmn = index.nil? ? nil : $Trainer.party[index]
      unless pkmn && !pkmn.egg? && !pkmn.shadowPokemon?
        @relearn_egg_move_ids = []
        return []
      end
      moves = []
      pkmn.getMoveList.each do |move_entry|
        next if move_entry[0] > pkmn.level || pkmn.hasMove?(move_entry[1])
        moves << move_entry[1] unless moves.include?(move_entry[1])
      end
      Array(pkmn.learned_moves).each do |move|
        move_id = move.is_a?(Symbol) ? move : move.id
        next if pkmn.hasMove?(move_id)
        next unless pkmn.compatible_with_move?(move_id)
        moves << move_id unless moves.include?(move_id)
      end
      first_moves = []
      Array(pkmn.first_moves).each do |move_id|
        first_moves << move_id if !pkmn.hasMove?(move_id) && !moves.include?(move_id)
      end
      egg_moves = []
      egg_move_ids = []
      if TMVault.egg_moves_enabled?
        baby = pbGetBabySpecies(pkmn.species) rescue nil
        Array((pbGetSpeciesEggMoves(baby) rescue [])).each do |move_id|
          egg_move_ids << move_id unless pkmn.hasMove?(move_id)
          egg_moves << move_id if !pkmn.hasMove?(move_id) && !moves.include?(move_id) && !first_moves.include?(move_id)
        end
      end
      @relearn_egg_move_ids = egg_move_ids.uniq
      sort_moves((first_moves + moves + egg_moves).uniq, pkmn)
    end

    def relearn_egg_move?(move_id)
      @move_mode == :relearn && Array(@relearn_egg_move_ids).include?(move_id)
    end

    def empty_list_message
      if @move_mode == :relearn
        pkmn = @relearn_mon.nil? ? nil : $Trainer.party[@relearn_mon]
        return "No Pokemon selected." unless pkmn
        return "No relearnable moves."
      end
      @filter_mon ? "No compatible moves." : "No TMs registered yet.\nFind, buy, or receive TMs."
    end

    def rows_per_page
      (CONT_H / ROW_H).floor
    end

    def clamp_scroll
      return unless @move_list_state
      @move_list_state.visible_rows = rows_per_page
      @move_list_state.ensure_visible!
      sync_from_move_list_state
    end

    def move_list_memory_key
      [:tm_vault, @move_mode, @filter_mon, @relearn_mon]
    end

    def sync_move_list_state(preserve_move = nil)
      key = move_list_memory_key
      if @move_list_state && @move_list_state_key == key
        @move_list_state.visible_rows = rows_per_page
        @move_list_state.replace_rows(@list, :preserve => :id)
        @move_list_state.select_id(preserve_move) if preserve_move
      else
        @move_list_state_key = key
        @move_list_state = Reloaded::ListState.new(
          :key => key,
          :rows => @list,
          :visible_rows => rows_per_page,
          :row_id => proc { |move_id| move_id },
          :initial_id => preserve_move,
          :wrap => true,
          :jump_wrap => false,
          :jump_size => 3,
          :remember => true
        )
      end
      sync_from_move_list_state
    end

    def sync_from_move_list_state
      @sel = @move_list_state.index || 0
      @scroll = @move_list_state.scroll
    end

    def selected_move_id
      @list[@sel]
    end

    # Build move_id -> "TM01"/"HM04" label cache.
    # Stored on the module so it's built once per game session, not per open.
    def tm_label_cache
      TMVault.tm_label_cache
    end

    def active_mon
      @filter_mon ? $Trainer.party[@filter_mon] : nil
    end

    # -- Drawing --------------------------------------------------------------
    def draw_all
      draw_title; draw_left; draw_right; draw_footer
    end

    def draw_title
      b = @title_spr.bitmap; b.clear
      b.fill_rect(0, 0, SCREEN_W, TITLE_H, TITLE_BG)
      pbSetSystemFont(b); b.font.size = 32
      tw = b.text_size("TM Vault").width
      tx = (SCREEN_W - tw) / 2
      pbDrawShadowText(b, tx, 5, tw, TITLE_H, "TM Vault", WHITE, SHADOW)
      b.font.size = 13
      # Filter/Filtering text: 100px left of title text
      if @move_mode == :relearn
        b.font.size = 16
        label = @relearn_mon.nil? ? "RELEARN" : "RELEARN: #{$Trainer.party[@relearn_mon].name}"
        pbDrawShadowText(b, tx - 170, 20, 160, 20, label, COLOR_GOLD, SHADOW, 1)
      elsif @filter_mon || @focus == :filter
        b.font.size = 16
        pbDrawShadowText(b, tx - 160, 20, 140, 20, "FILTERING...", COLOR_GOLD, SHADOW, 1)
      end
      detail =
 @filter_mon || @move_mode == :relearn ? @list.length.to_s : TMVault.vault.length.to_s
      pbDrawShadowText(b, SCREEN_W - 18, 2, -1, TITLE_H - 4, detail, DIM, SHADOW, 1)
    end

    def draw_left
      b = @left_spr.bitmap; b.clear
      draw_rounded_rect(b, 0, 0, LEFT_W, CONT_H, PANEL_BG)
      draw_border(b, 0, 0, LEFT_W, CONT_H, PANEL_BORDER)
      pbSetSmallFont(b)

      # "Filtering..." banner now drawn in draw_title
      if @list.empty?
        msg = empty_list_message
        msg.split("\n").each_with_index do |line, i|
          pbDrawShadowText(b, 8, CONT_H/2 - 16 + i*18, LEFT_W-16, 18, line, DIM, SHADOW, 2)
        end
        return
      end

      mon = active_mon
      rpp = rows_per_page

      @list.each_with_index do |id, i|
        next if i < @scroll
        break if i >= @scroll + rpp
        ry  = (i - @scroll) * ROW_H
        sel = (i == @sel)
        if sel
          # Animated pulse: alpha oscillates between 20 and 55 over 40 frames
          pulse = (Math.sin(@cursor_tick * Math::PI / 20.0) * 17.5 + 37.5).to_i
          b.fill_rect(2, ry + 3, LEFT_W-4, ROW_H-1, Color.new(255, 255, 255, pulse))
        else
          b.fill_rect(2, ry + 3, LEFT_W-4, ROW_H-1, ROW_NORM)
        end

        md    = GameData::Move.try_get(id)
        name  = md ? md.name : id.to_s
        display_name = name
        sort = TMVault.sort_mode
        # Category sort: color by category regardless of filter.
        # All other sorts: color by type, but compat overrides when filter active
        #   on Name (0) and Recent (3) sorts.
        color = if sort == 2 && md  # Category sort — color by category
          case md.category
          when 0 then Color.new(220,  60,  60)   # Physical — red
          when 1 then Color.new(100, 180, 255)   # Special  — blue
          else        Color.new(240, 210,  60)   # Status   — yellow
          end
        elsif mon && (sort == 0 || sort == 3)  # Name/Recent with filter — compat colors
          case TMVault.compat(id, mon)
          when :knows  then COLOR_KNOWS
          when :compat then COLOR_COMPAT
          else              COLOR_CANT
          end
        elsif md  # Type color (Name, Type, Recent sorts)
          type_num = (GameData::Type.get(md.type).id_number rescue nil)
          case type_num
          when (GameData::Type.get(:FIRE).id_number    rescue -1) then Color.new(240, 100,  50)
          when (GameData::Type.get(:WATER).id_number   rescue -1) then Color.new( 80, 160, 240)
          when (GameData::Type.get(:GRASS).id_number   rescue -1) then Color.new( 80, 210,  80)
          when (GameData::Type.get(:ELECTRIC).id_number rescue -1) then Color.new(240, 210,  50)
          when (GameData::Type.get(:ICE).id_number     rescue -1) then Color.new(130, 220, 240)
          when (GameData::Type.get(:FIGHTING).id_number rescue -1) then Color.new(200,  60,  60)
          when (GameData::Type.get(:POISON).id_number  rescue -1) then Color.new(180,  80, 200)
          when (GameData::Type.get(:GROUND).id_number  rescue -1) then Color.new(215, 185, 130)
          when (GameData::Type.get(:FLYING).id_number  rescue -1) then Color.new(180, 150, 230)
          when (GameData::Type.get(:PSYCHIC).id_number rescue -1) then Color.new(240,  80, 140)
          when (GameData::Type.get(:BUG).id_number     rescue -1) then Color.new(150, 190,  50)
          when (GameData::Type.get(:ROCK).id_number    rescue -1) then Color.new(190, 160,  70)
          when (GameData::Type.get(:GHOST).id_number   rescue -1) then Color.new(110,  80, 160)
          when (GameData::Type.get(:DRAGON).id_number  rescue -1) then Color.new( 80,  60, 220)
          when (GameData::Type.get(:DARK).id_number    rescue -1) then Color.new(120,  90,  60)
          when (GameData::Type.get(:STEEL).id_number   rescue -1) then Color.new(160, 170, 190)
          when (GameData::Type.get(:FAIRY).id_number   rescue -1) then Color.new(240, 140, 200)
          else WHITE
          end
        else
          WHITE
        end
        # Drop one font size if display_name is too wide
        pbSetSmallFont(b)
        max_name_w = LEFT_W - 84
        if b.text_size(display_name).width > max_name_w
          b.font.size = b.font.size - 2
        end
        pbDrawShadowText(b, 10, ry, max_name_w, ROW_H, display_name, color, SHADOW)

        if md
          Reloaded::TypeIcons.draw(b, md.type, LEFT_W - 38, ry + 6, :badge, 32, 12)
          if relearn_egg_move?(id) && (egg_bmp = TMVault.egg_icon_bitmap)
            egg_src = Rect.new(18, 22, 28, 34)
            egg_dst = Rect.new(LEFT_W - 54, ry + 3, 14, 17)
            b.stretch_blt(egg_dst, egg_bmp, egg_src) rescue nil
          end
        end

      end
    end

    def draw_right
      b = @right_spr.bitmap; b.clear
      draw_rounded_rect(b, 0, 0, RIGHT_W, CONT_H, PANEL_BG)
      draw_border(b, 0, 0, RIGHT_W, CONT_H, PANEL_BORDER)
      pbSetSmallFont(b)

      mid = selected_move_id

      # Party icons
      (0...6).each do |i|
        pkmn = $Trainer.party[i]; next unless pkmn
        col  = i % PARTY_COLS
        row  = i / PARTY_COLS
        row_y_extra = row == 1 ? 10 : 0
        ix   = PARTY_X0 + col * PARTY_X_GAP
        iy   = PARTY_Y0 + row * PARTY_Y_GAP + row_y_extra

        # Background box: covers icon + name, extends right; no border
        # Box height: icon + name label (14px) + padding
        box_x = ix - 6
        box_y = iy - 1
        box_w = PARTY_ICO_W + 20
        box_h = PARTY_ICO_H + 40
        relearn_selected = @move_mode == :relearn && @relearn_mon == i
        if (@focus == :party || @focus == :filter) && @party_sel == i
          fill_col = (@focus == :filter || @move_mode == :relearn) ? Color.new(240, 200, 60, 70) : Color.new(255, 255, 255, 55)
          b.fill_rect(box_x, box_y, box_w, box_h, fill_col)
        elsif @filter_mon == i || relearn_selected
          b.fill_rect(box_x, box_y, box_w, box_h, Color.new(240, 220, 80, 45))
        end

        # Name — white, truly centered in box; start from pbSetSmallFont natural size
        pbSetSmallFont(b)
        name_max_w = box_w - 4
        name_size  = [24, 22, 20, 18, 16, 14, 12, 10].find do |sz|
          b.font.size = sz
          b.text_size(pkmn.name).width <= name_max_w
        end || 10
        b.font.size = name_size
        name_w = b.text_size(pkmn.name).width
        name_x = box_x + (box_w - name_w) / 2
        pbDrawShadowText(b, name_x, iy+PARTY_ICO_H+1, name_w + 2, 14, pkmn.name, WHITE, SHADOW)

        # Compatibility label centered below name, 2px lower
        if mid
          compat_label, compat_col = case TMVault.compat(mid, pkmn)
          when :knows  then ["LEARNED",     COLOR_KNOWS]
          when :compat then ["LEARNABLE",    COLOR_COMPAT]
          else              ["CAN'T LEARN",  Color.new(200, 60, 60)]
          end
          b.font.size = 13
          lbl_w = b.text_size(compat_label).width
          lbl_x = ix + PARTY_ICO_W/2 - lbl_w/2 + 3
          pbDrawShadowText(b, lbl_x, iy+PARTY_ICO_H+22, lbl_w+2, 14, compat_label, compat_col, SHADOW)
        end
      end

      # Move info strip below party grid
      if mid && (md = GameData::Move.try_get(mid))
        info_y = PARTY_Y0 + PARTY_Y_GAP + PARTY_ICO_H + 60
        b.fill_rect(8, info_y-2, RIGHT_W-16, 1, PANEL_BORDER)
        b.font.size = 12

        cat_col   = md.category == 0 ? Color.new(220, 60, 60) :
                    md.category == 1 ? Color.new(100, 180, 255) : Color.new(240, 210, 60)
        cat_name  = ["Physical", "Special", "Status"][md.category] || "???"
        pow_str   = md.base_damage <= 1 ? (md.base_damage==1 ? "???" : "---") : md.base_damage.to_s
        acc_str   = md.accuracy == 0 ? "---" : "#{md.accuracy}%"

        # Move name + STAB badge — only show when hovering a party slot or filter active
        b.font.size = 12
        pbDrawShadowText(b, 10, info_y, RIGHT_W-20, 15, md.name, WHITE, SHADOW)
        ctx_mon = if @focus == :party
          $Trainer.party[@party_sel] rescue nil
        elsif @filter_mon
          $Trainer.party[@filter_mon] rescue nil
        end
        if ctx_mon
          pkmn_types = [ctx_mon.type1, ctx_mon.type2].compact.uniq
          if pkmn_types.include?(md.type)
            b.font.size = 14
            stab_w = b.text_size("STAB").width + 4
            pbDrawShadowText(b, RIGHT_W - stab_w - 6, info_y, stab_w, 14, "STAB", Color.new(220, 60, 60), SHADOW)
            b.font.size = 12
          end
        end
        b.font.size = 12


        # Category (colored) + stats — measure cat_name width so stats sit right after
        pbDrawShadowText(b, 10, info_y+15, 70, 14, cat_name, cat_col, SHADOW)
        cat_px = b.text_size(cat_name).width + 6
        sx = 10 + cat_px
        pbDrawShadowText(b, sx, info_y+15, 46, 14, "Power:", WHITE, SHADOW)
        sx += b.text_size("Power:").width + 2
        pbDrawShadowText(b, sx, info_y+15, 30, 14, pow_str, GRAY, SHADOW)
        sx += b.text_size(pow_str).width + 6
        pbDrawShadowText(b, sx, info_y+15, 54, 14, "Accuracy:", WHITE, SHADOW)
        sx += b.text_size("Accuracy:").width + 2
        pbDrawShadowText(b, sx, info_y+15, 36, 14, acc_str, GRAY, SHADOW)
        sx += b.text_size(acc_str).width + 6
        pbDrawShadowText(b, sx, info_y+15, 20, 14, "PP:", WHITE, SHADOW)
        sx += b.text_size("PP:").width + 2
        pbDrawShadowText(b, sx, info_y+15, RIGHT_W - sx - 4, 14, md.total_pp.to_s, GRAY, SHADOW)

        # Description — wrap using actual pixel measurement
        desc  = md.description.to_s
        desc_w = RIGHT_W - 20
        dy    = info_y + 32
        words = desc.split(" ")
        line  = ""
        words.each do |w|
          test = line.empty? ? w : "#{line} #{w}"
          if b.text_size(test).width > desc_w
            pbDrawShadowText(b, 10, dy, desc_w, 14, line, DIM, SHADOW)
            dy  += 13
            line = w
          else
            line = test
          end
        end
        pbDrawShadowText(b, 10, dy, desc_w, 14, line, DIM, SHADOW) unless line.empty?
      end
    end

    def draw_footer
      b = @footer_spr.bitmap; b.clear
      b.fill_rect(0, 0, SCREEN_W, FOOTER_H, FOOTER_BG)
      if defined?(Reloaded::HintText)
        Reloaded::HintText.draw_footer(
          b,
          hint_entries,
          8,
          8,
          SCREEN_W - 16,
          :size => 16,
          :color => WHITE,
          :height => FOOTER_H,
          :statuses => hint_statuses
        )
        return
      end
      # Hint Text system: pbSetSmallFont + size 16 + WHITE
      # Format: "Verb (KEY)" � no colon, verb first
      # Order: Confirm (C)  Back (B)  Action (A)  Special (SHIFT)
      pbSetSmallFont(b); b.font.size = 16
      if @focus == :party
        hint = "Teach (C)   Cancel (B)"
      elsif @focus == :filter
        if @pending_relearn_pick
          hint = "Pick Pokemon (C)   Cancel (B)"
        else
          filter_lbl = @filter_mon ? "Clear filter (A)" : "Filter (A)"
          hint = "Pick filter (C)   Cancel (B)   #{filter_lbl}"
        end
      else
        sort_lbl   = SORT_NAMES[TMVault.sort_mode] || "Name"
        filter_lbl = @filter_mon ? "Clear filter (A)" : "Filter (A)"
        relearn_lbl = @move_mode == :relearn ? "Vault Moves (L)" : "Relearn Moves (L)"
        hint = "Select (C)   Back (B)   #{filter_lbl}   #{relearn_lbl}   Sort (R): #{sort_lbl}"
      end
      pbDrawShadowText(b, 8, 3, SCREEN_W - 16, FOOTER_H, hint, WHITE, SHADOW)
    end

    def hint_entries
      if @focus == :party
        return [
          Reloaded::HintText.confirm("Teach"),
          Reloaded::HintText.back("Cancel")
        ]
      elsif @focus == :filter
        if @pending_relearn_pick
          return [
            Reloaded::HintText.confirm("Pick Pokemon"),
            Reloaded::HintText.back("Cancel")
          ]
        end
        filter_lbl = @filter_mon ? "Clear Filter" : "Filter"
        return [
          Reloaded::HintText.confirm("Pick Filter"),
          Reloaded::HintText.back("Cancel"),
          Reloaded::HintText.action(filter_lbl)
        ]
      end
      filter_lbl = @filter_mon ? "Clear Filter" : "Filter"
      relearn_lbl = @move_mode == :relearn ? "Vault Moves" : "Relearn Moves"
      [
        Reloaded::HintText.confirm("Select"),
        Reloaded::HintText.back,
        Reloaded::HintText.action(filter_lbl),
        Reloaded::HintText.other(relearn_lbl, :sort),
        Reloaded::HintText.other("Sort", :quick)
      ]
    rescue
      []
    end

    def hint_statuses
      return [] unless defined?(Reloaded::HintText)
      statuses = []
      statuses << Reloaded::HintText.status("Sort: #{tm_vault_sort_label}", COLOR_KNOWS) if @focus == :list
      statuses << Reloaded::HintText.status("Relearn Mode", COLOR_COMPAT) if @move_mode == :relearn
      statuses
    rescue
      []
    end

    def tm_vault_sort_label
      SORT_NAMES[TMVault.sort_mode] || "Name"
    rescue
      "Name"
    end

    def hint_triggered?
      defined?(Reloaded::HintText) && Reloaded::HintText.triggered?
    rescue
      false
    end

    def open_hint_popup
      if defined?(Reloaded::HintText)
        @move_list_state.with_dialog do
          Reloaded::HintText.open_popup("TM Vault Hints", hint_entries, :statuses => hint_statuses)
        end
      end
    rescue
    end

    # -- Input ----------------------------------------------------------------
    def handle_input
      if hint_triggered?
        open_hint_popup
        draw_footer
        return
      end
      if controls_mouse_clicked?
        open_hint_popup
        draw_footer
        return
      end
      if @focus == :party
        handle_input_party
      elsif @focus == :filter
        handle_input_filter
      else
        handle_input_list
      end
    end

    def controls_mouse_clicked?
      return false unless defined?(Reloaded::HintText)
      return false unless (Input.trigger?(Input::MOUSELEFT) rescue false)
      pos = Reloaded::MouseInput.active_position rescue nil
      return false unless pos.is_a?(Array)
      Reloaded::HintText.controls_at?(@footer_spr.bitmap, pos[0], pos[1] - (SCREEN_H - FOOTER_H), 8, 8, SCREEN_W - 16, :size => 16, :height => FOOTER_H)
    rescue
      false
    end

    def handle_input_list
      event = @move_list_state.update_input(
        :mouse_index => proc do |x, y|
          next nil unless x.to_i.between?(@left_spr.x, @left_spr.x + LEFT_W - 1)
          next nil unless y.to_i.between?(CONT_Y, CONT_Y + CONT_H - 1)
          index = @scroll + ((y.to_i - CONT_Y) / ROW_H)
          index < @list.length ? index : nil
        end
      )
      sync_from_move_list_state
      if event.moved?
        pbPlayCursorSE rescue nil
        draw_left; draw_right
      elsif event.back?
        pbPlayCloseMenuSE
        if @move_mode == :relearn || @filter_mon || @pending_relearn_pick
          return_to_main_vault
        else
          @running = false
        end
      elsif event.activate?
        return if @list.empty?
        pbPlayDecisionSE
        if @move_mode == :relearn && !@relearn_mon.nil?
          @party_sel = @relearn_mon
          teach_to_party_sel
        else
          @focus     = :party
          @party_sel = 0
          @party_sel += 1 while @party_sel < 6 && !$Trainer.party[@party_sel]
          draw_right; draw_footer
        end
      elsif Input.trigger?(Input::ACTION)
        toggle_filter
      elsif Input.trigger?(Input::L)
        toggle_relearn_mode
      elsif Input.trigger?(Input::R)
        next_sort = (TMVault.sort_mode + 1) % SORT_NAMES.length
        TMVault.sort_mode = next_sort
        build_list; clamp_scroll; draw_left; draw_footer
      end
    end

    def handle_input_filter
      party_size = $Trainer.party.length
      if Input.repeat?(Input::UP)
        new_sel = @party_sel - PARTY_COLS
        if new_sel >= 0 && $Trainer.party[new_sel]
          @party_sel = new_sel; draw_right
        end
      elsif Input.repeat?(Input::DOWN)
        new_sel = @party_sel + PARTY_COLS
        if new_sel < party_size
          @party_sel = new_sel; draw_right
        end
      elsif Input.repeat?(Input::LEFT)
        new_sel = @party_sel - 1
        if new_sel >= 0 && $Trainer.party[new_sel]
          @party_sel = new_sel; draw_right
        end
      elsif Input.repeat?(Input::RIGHT)
        new_sel = @party_sel + 1
        if new_sel < party_size
          @party_sel = new_sel; draw_right
        end
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        if @pending_relearn_pick
          @pending_relearn_pick = false
          @move_mode = :relearn
          @relearn_mon = @party_sel
          @filter_mon = nil
        else
          @filter_mon = (@filter_mon == @party_sel) ? nil : @party_sel
        end
        @focus = :list
        build_list; clamp_scroll; draw_all
        @move_list_state.dialog_closed!
      elsif Input.trigger?(Input::ACTION)
        @pending_relearn_pick = false
        @filter_mon = nil
        @focus = :list
        build_list; clamp_scroll; draw_all
        @move_list_state.dialog_closed!
      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        @pending_relearn_pick = false
        @focus = :list
        draw_right; draw_footer
        @move_list_state.dialog_closed!
      end
    end

    def handle_input_party
      party_size = $Trainer.party.length
      if Input.repeat?(Input::UP)
        new_sel = @party_sel - PARTY_COLS
        if new_sel >= 0 && $Trainer.party[new_sel]
          @party_sel = new_sel
          draw_right
        end
      elsif Input.repeat?(Input::DOWN)
        new_sel = @party_sel + PARTY_COLS
        if new_sel < party_size
          @party_sel = new_sel
          draw_right
        end
      elsif Input.repeat?(Input::LEFT)
        new_sel = @party_sel - 1
        if new_sel >= 0 && $Trainer.party[new_sel]
          @party_sel = new_sel
          draw_right
        end
      elsif Input.repeat?(Input::RIGHT)
        new_sel = @party_sel + 1
        if new_sel < party_size
          @party_sel = new_sel
          draw_right
        end
      elsif Input.trigger?(Input::USE)
        teach_to_party_sel
      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        @focus = :list
        @move_list_state.dialog_closed!
        draw_right; draw_footer
      end
    end

    # -- Actions --------------------------------------------------------------
    def toggle_filter
      if @filter_mon
        pbPlayCloseMenuSE
        @filter_mon = nil
        build_list; clamp_scroll; draw_all
      else
        @focus = :filter
        @party_sel = 0
        @party_sel += 1 while @party_sel < 6 && !$Trainer.party[@party_sel]
        @pending_relearn_pick = false
        draw_left; draw_right; draw_footer
      end
    end

    def toggle_relearn_mode
      if @move_mode == :relearn
        @move_mode = :vault
        @relearn_mon = nil
        @filter_mon = nil
        @pending_relearn_pick = false
        @focus = :list
        pbPlayCursorSE
        build_list; clamp_scroll; draw_all
        return
      end
      @focus = :filter
      @party_sel = 0
      @party_sel += 1 while @party_sel < 6 && !$Trainer.party[@party_sel]
      @pending_relearn_pick = true
      pbPlayCursorSE
      draw_left; draw_right; draw_footer
    end

    def return_to_main_vault
      @move_mode = :vault
      @relearn_mon = nil
      @filter_mon = nil
      @pending_relearn_pick = false
      @focus = :list
      build_list
      clamp_scroll
      draw_all
    end

    def show_move_info


      id = selected_move_id; return unless id
      md = GameData::Move.try_get(id); return unless md
      type_name = (GameData::Type.get(md.type).name rescue "???")
      cat_name  = ["Physical","Special","Status"][md.category] || "???"
      pow_str   = md.base_damage <= 1 ? (md.base_damage==1 ? "???" : "---") : md.base_damage.to_s
      acc_str   = md.accuracy == 0 ? "---" : "#{md.accuracy}%"
      show_message(
        "#{md.name}\n" \
        "Type: #{type_name}   Category: #{cat_name}\n" \
        "Power: #{pow_str}   Accuracy: #{acc_str}   PP: #{md.total_pp}\n\n" \
        "#{md.description}"
      )
    end

    def teach_to_party_sel
      id   = selected_move_id; return unless id
      md   = GameData::Move.try_get(id); return unless md
      pkmn = $Trainer.party[@party_sel]; return unless pkmn
      if pkmn.egg?
        hr_message("Eggs can't be taught any moves.")
        return
      end
      if pkmn.shadowPokemon?
        hr_message("Shadow Pokemon can't be taught any moves.")
        return
      end
      if pkmn.hasMove?(id)
        hr_message("#{pkmn.name} already knows #{md.name}.")
        return
      end
      if @move_mode != :relearn && !pkmn.compatible_with_move?(id)
        hr_message("#{pkmn.name} can't learn #{md.name}.")
        return
      end

      # Use our own in-viewport teach flow � all messages render over the vault
      taught = hr_teach_move(pkmn, id)
      TMVault.emit(:tm_vault_move_taught, :move => id, :move_data => md, :pokemon => pkmn) if taught
      @focus = :list
      refresh_party_icons
      draw_all
    end

    # -- In-viewport message helpers -------------------------------------------
    # Full-width dialog box at bottom of screen, MM dark style, small font.
    # If choices given, shows Yes/No panel to the right above the dialog simultaneously.
    # Returns nil (no choices) or true/false (Yes/No).
    def hr_message(text, choices: nil)
      _init_gas rescue nil
      Graphics.update; Input.update
      lines   = text.to_s.split("\n").reject(&:empty?)
      n_lines = [lines.length, 2].max
      pad     = 12
      line_h  = 18
      box_h   = pad * 2 + n_lines * line_h
      box_y   = SCREEN_H - box_h - FOOTER_H

      # Dialog sprite — BitmapSprite owns its bitmap
      spr = BitmapSprite.new(SCREEN_W, box_h, @vp)
      spr.x = 0; spr.y = box_y; spr.z = 500
      b = spr.bitmap
      b.fill_rect(0, 0, SCREEN_W, box_h, Color.new(12, 24, 50, 240))
      draw_border(b, 0, 0, SCREEN_W, box_h, PANEL_BORDER)
      pbSetSmallFont(b); b.font.size = 15
      lines.each_with_index do |line, i|
        pbDrawShadowText(b, pad, pad + i * line_h, SCREEN_W - pad * 2, line_h, line, WHITE, SHADOW)
      end

      # Optional Yes/No panel above-right
      csel = 0
      cspr = nil
      if choices
        cpad   = 10; cline_h = 18
        cw     = 72
        ch     = cpad * 2 + choices.length * cline_h
        cx     = SCREEN_W - cw - 8
        cy     = box_y - ch - 4
        cspr   = BitmapSprite.new(cw, ch, @vp)
        cspr.x = cx; cspr.y = cy; cspr.z = 501
        redraw_choices = proc do
          cb = cspr.bitmap; cb.clear
          cb.fill_rect(0, 0, cw, ch, Color.new(12, 24, 50, 240))
          draw_border(cb, 0, 0, cw, ch, PANEL_BORDER)
          pbSetSmallFont(cb); cb.font.size = 15
          choices.each_with_index do |ch_text, i|
            if i == csel
              cb.fill_rect(2, cpad + i * cline_h - 2, cw - 4, cline_h, Color.new(30, 60, 110, 255))
            end
            col = i == csel ? WHITE : GRAY
            pbDrawShadowText(cb, cpad, cpad + i * cline_h, cw - cpad * 2, cline_h, ch_text, col, SHADOW)
          end
        end
        redraw_choices.call
      end

      result = nil
      loop do
        Graphics.update; Input.update
        if choices
          if Input.trigger?(Input::UP) && csel > 0
            csel -= 1; redraw_choices.call
          elsif Input.trigger?(Input::DOWN) && csel < choices.length - 1
            csel += 1; redraw_choices.call
          elsif Input.trigger?(Input::USE)
            result = csel == 0; break
          elsif Input.trigger?(Input::BACK)
            result = false; break
          end
        else
          break if Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
        end
      end

      cspr.dispose if cspr
      spr.dispose
      Input.update
      result
    ensure
      @move_list_state.dialog_closed! if @move_list_state
    end

    # Shorthand confirm — shows message + Yes/No panel together.
    def hr_confirm(text)
      hr_message(text, choices: ["Yes", "No"])
    end

    # Drop z, open the real game forget-move screen, restore z.
    def hr_forget_move(pkmn, move_id)
      @vp.z = 1
      ret = pbForgetMove(pkmn, move_id)
      @vp.z = 100_000
      ret
    ensure
      @move_list_state.dialog_closed! if @move_list_state
    end

    # Full in-viewport reimplementation of pbLearnMove logic.
    def hr_teach_move(pkmn, move_id)
      md        = GameData::Move.get(move_id)
      move_name = md.name
      pkmn_name = pkmn.name
      if pkmn.numMoves < Pokemon::MAX_MOVES
        pkmn.learn_move(move_id)
        pbSEPlay("Pkmn move learnt") rescue nil
        hr_message("#{pkmn_name} learned #{move_name}!")
        return true
      end
      loop do
        chose_yes = hr_message("#{pkmn_name} wants to learn #{move_name}, but it already knows #{pkmn.numMoves.to_word} moves. Replace a move?",
                               choices: ["Yes", "No"])
        unless chose_yes
          hr_message("#{pkmn_name} did not learn #{move_name}.")
          return false
        end
        forget_idx = hr_forget_move(pkmn, move_id)
        if forget_idx >= 0
          old_name = pkmn.moves[forget_idx].name
          pkmn.moves[forget_idx] = Pokemon::Move.new(move_id)
          pbSEPlay("Battle ball drop") rescue nil
          hr_message("#{pkmn_name} forgot #{old_name}.")
          pbSEPlay("Pkmn move learnt") rescue nil
          hr_message("#{pkmn_name} learned #{move_name}!")
          return true
        else
          # Forget screen cancelled — ask if they want to give up
          if hr_message("Give up on learning #{move_name}?", choices: ["Yes", "No"])
            hr_message("#{pkmn_name} did not learn #{move_name}.")
            return false
          end
          # No → loop back to "Replace a move?" prompt
        end
      end
    end

    def refresh_party_icons
      @party_icons.compact.each { |ico| ico.dispose rescue nil }
      @party_icons = Array.new(6) do |i|
        pkmn = $Trainer.party[i]; next nil unless pkmn
        col = i % PARTY_COLS; row = i / PARTY_COLS
        ico = PokemonIconSprite.new(pkmn, @vp)
        ico.setOffset(PictureOrigin::Center)
        ico.x = @right_spr.x + PARTY_X0 + col*PARTY_X_GAP + PARTY_ICO_W/2
        ico.y = CONT_Y + PARTY_Y0 + row*PARTY_Y_GAP + PARTY_ICO_H/2
        ico.z = 20; ico
      end
    end
  end
end  # module TMVault

# -- Auto-registration: pbItemBall (TM found on ground) -----------------------
unless defined?(_tmvault_orig_pbItemBall)
  alias _tmvault_orig_pbItemBall pbItemBall
  def pbItemBall(item, quantity = 1, item_name = "", canRandom = true)
    result = _tmvault_orig_pbItemBall(item, quantity, item_name, canRandom)
    if result
      itm = GameData::Item.try_get(item)
      TMVault.register(itm.move, notify: false, source: :pickup) if itm && itm.is_machine? && itm.move
    end
    result
  rescue => e
    Reloaded::Log.exception("TM Vault pbItemBall hook failed", e, channel: :modules) if defined?(Reloaded::Log)
    result
  end
end

# -- Auto-registration: pbReceiveItem (TM given by NPC/event) -----------------
unless defined?(_tmvault_orig_pbReceiveItem)
  alias _tmvault_orig_pbReceiveItem pbReceiveItem
  def pbReceiveItem(item, quantity = 1, item_name = "", music = nil, canRandom = true)
    result = _tmvault_orig_pbReceiveItem(item, quantity, item_name, music, canRandom)
    if result
      itm = GameData::Item.try_get(item)
      TMVault.register(itm.move, notify: false, source: :receive) if itm && itm.is_machine? && itm.move
    end
    result
  rescue => e
    Reloaded::Log.exception("TM Vault pbReceiveItem hook failed", e, channel: :modules) if defined?(Reloaded::Log)
    result
  end
end

# -- Auto-registration: pbMoveTutorChoose (NPC tutors) -------------------------
# Alias only if not already aliased (guard against double-load).
unless defined?(_tmvault_orig_pbMoveTutorChoose)
  alias _tmvault_orig_pbMoveTutorChoose pbMoveTutorChoose
  def pbMoveTutorChoose(move, movelist=nil, bymachine=false, oneusemachine=false, selVar=nil)
    result = _tmvault_orig_pbMoveTutorChoose(move, movelist, bymachine, oneusemachine, selVar)
    # Notify only for NPC tutor moves (not TM use � those are registered via addItem)
    TMVault.register(move, notify: !bymachine, source: bymachine ? :machine : :tutor) if result
    result
  rescue => e
    Reloaded::Log.exception("TM Vault move tutor hook failed", e, channel: :modules) if defined?(Reloaded::Log)
    result
  end
end

# -- Auto-registration: PokemonMartAdapter#addItem (mart purchases) -------------
class PokemonMartAdapter
  unless method_defined?(:_tmvault_orig_addItem)  # rubocop guard
    alias _tmvault_orig_addItem addItem
    def addItem(item)
      result = _tmvault_orig_addItem(item)
      if result
        itm = GameData::Item.try_get(item)
        TMVault.register(itm.move, notify: false, source: :shop) if itm && itm.is_machine? && itm.move
      end
      result
    rescue => e
      Reloaded::Log.exception("TM Vault mart hook failed", e, channel: :modules) if defined?(Reloaded::Log)
      result
    end
  end
end

# -- PokeNav: register TMVAULT app and handle dispatch -------------------------
# Register in AVAILABLE_APPS so the PokeNav grid shows the icon/name.
if defined?(Pokenav) && !Pokenav::AVAILABLE_APPS.key?(:TMVAULT)
  Pokenav::AVAILABLE_APPS[:TMVAULT] = "TM Vault"
end

if defined?(PokegearButton)
  class PokegearButton
    unless method_defined?(:reloaded_tmvault_refresh)
      alias_method :reloaded_tmvault_refresh, :refresh
      def refresh
        return reloaded_tmvault_refresh unless @image.to_s.upcase == "TMVAULT"
        self.bitmap.clear
        rect = Rect.new(0, 0, @cursor.width, @cursor.height / 2)
        rect.y = @cursor.height / 2 if @selected
        self.bitmap.blt(0, 0, @cursor.bitmap, rect)
        if @held
          self.opacity = 200
          self.y -= 6
        else
          self.opacity = 255
        end
        pbDrawImagePositions(self.bitmap, [[TMVault::ICON_PATH, 0, 0]])
        self.x = @base_x
        self.y = @base_y
        self.y -= 6 if @held
      end
    end
  end
end
class PokemonPokegearScreen
  unless method_defined?(:_tmvault_orig_pokenav_start)
    alias _tmvault_orig_pokenav_start pbStartScreen

    def pbStartScreen
      # One-time bag scan per game session: runs here because game scripts are
      # guaranteed loaded by the time the PokeNav is opened.
      unless $tmvault_load_hook_applied
        $tmvault_load_hook_applied = true
        TMVault.pocket_scan rescue nil
      end

            # Sync app presence. Off removes it from PokeNav only; REPM remains available.
      if $Trainer && $Trainer.pokenav
        want_in_pokenav = $PokemonSystem.hr_tmvault == 1
        apps = $Trainer.pokenav.installed_apps
        if want_in_pokenav && !apps.include?(:TMVAULT)
          apps << :TMVAULT
        elsif !want_in_pokenav
          apps.delete(:TMVAULT)
        end
      end

      # Patch the scene's pbScene return so we can intercept TMVAULT
      # without reimplementing the whole loop.
      $Trainer.pokenav = Pokenav.new unless $Trainer.pokenav
      commands = update_commands
      @scene.pbStartScene(commands)
      loop do
        cmd      = @scene.pbScene
        commands = update_commands
        break if cmd < 0
        next if cmd >= commands.length
        chosen = commands[cmd][0].to_sym rescue nil
        next unless chosen

        if chosen == :TMVAULT
          TMVault.open
        else
          _tmvault_dispatch_other(chosen)
        end
      end
      @scene.pbEndScene
    end

    private

    def _tmvault_dispatch_other(chosen)
      case chosen
      when :MAP           then pbWeatherMap
      when :JUKEBOX
        pbFadeOutIn {
          scene  = PokemonJukebox_Scene.new
          screen = PokemonJukeboxScreen.new(scene)
          screen.pbStartScreen
        }
      when :QUESTS        then pbQuestlog()
      when :CONTACTS      then openContactsApp
      when :WEATHER       then pbWeatherMap
      when :POKECHALLENGE then openChallengeApp
      when :POKERADAR     then openPokeRadarApp
      when :REARRANGE     then @scene.rearrange_order
      when :DAYNIGHT      then toggleDarkMode
      when :BOXLINK       then openBoxLinkApp
      when :FUSIONQUIZ    then openGuessThatFusionApp
      when :BERRYDEX      then pbBerryDex
      end
    rescue => e
      Reloaded::Log.exception("TM Vault PokeNav dispatch failed", e, channel: :modules) if defined?(Reloaded::Log)
    end
  end
end

# -- Auto-register on game load -----------------------------------------------
# Hook onLoadExistingGame to scan the bag on every save load, registering any
# TMs the player had before the vault was installed.
# IMPORTANT: Reloaded loads before game scripts, so onLoadExistingGame may not
# exist yet. We use a deferred open+alias via Module#class_eval on Object so
# the patch applies once the method is defined (game scripts load after us).
# The "tm_label_cache" pre-warm below handles the first-open speed issue.
$tmvault_load_hook_applied = false
# Pre-warm module-level caches at game boot (Reloaded runs during boot screen).
# GameData is already loaded at this point. This eliminates the black pause on
# first vault open: the TM label cache is instant by then.
TMVault.tm_label_cache rescue nil
