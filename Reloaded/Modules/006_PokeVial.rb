#======================================================
# Reloaded PokeVial
# Author: Stonewall
#======================================================
# Limited-use party healing module for Reloaded systems.
#
# Responsibilities:
#   - Register the REPM and Overworld Menu PokeVial entries.
#   - Store PokeVial settings through PokemonSystem.
#   - Store current charges and cooldown in the Reloaded save bucket.
#   - Provide a small modder API for granting uses and refill sources.
#   - Support PokeVial use grants from Reloaded Mart and Mystery Gift.
#
#======================================================

module Reloaded
  module PokeVialFeature
    class << self
      def install
        install_pokemon_system_settings
        register_option
        ReloadedPokeVial.install_runtime_patches if defined?(ReloadedPokeVial)
        Reloaded::Log.info("Installed PokeVial module", :modules) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("PokeVial install failed", e, channel: :modules) if defined?(Reloaded::Log)
        false
      end

      def install_pokemon_system_settings
        return unless defined?(PokemonSystem)
        PokemonSystem.class_eval do
          def hr_pokevial_enabled
            @hr_pokevial_enabled.nil? ? 1 : @hr_pokevial_enabled.to_i
          end

          def hr_pokevial_enabled=(value)
            @hr_pokevial_enabled = value.to_i
          end

          def hr_pokevial_max_uses
            @hr_pokevial_max_uses.nil? ? ReloadedPokeVial::DEFAULT_MAX_USES : @hr_pokevial_max_uses.to_i
          end

          def hr_pokevial_max_uses=(value)
            @hr_pokevial_max_uses = value.to_i
            ReloadedPokeVial.clamp_uses_to_max if defined?(ReloadedPokeVial)
          end

          def hr_pokevial_progressive
            @hr_pokevial_progressive.nil? ? 1 : @hr_pokevial_progressive.to_i
          end

          def hr_pokevial_progressive=(value)
            @hr_pokevial_progressive = value.to_i
            ReloadedPokeVial.clamp_uses_to_max if defined?(ReloadedPokeVial)
          end

          def hr_pokevial_heal_mode
            @hr_pokevial_heal_mode.nil? ? 0 : @hr_pokevial_heal_mode.to_i
          end

          def hr_pokevial_heal_mode=(value)
            @hr_pokevial_heal_mode = value.to_i
          end

          def hr_pokevial_cooldown_enabled
            @hr_pokevial_cooldown_enabled.nil? ? 0 : @hr_pokevial_cooldown_enabled.to_i
          end

          def hr_pokevial_cooldown_enabled=(value)
            @hr_pokevial_cooldown_enabled = value.to_i
          end

          def hr_pokevial_cooldown_seconds
            @hr_pokevial_cooldown_seconds.nil? ? ReloadedPokeVial::DEFAULT_COOLDOWN_SECONDS : @hr_pokevial_cooldown_seconds.to_i
          end

          def hr_pokevial_cooldown_seconds=(value)
            @hr_pokevial_cooldown_seconds = value.to_i
          end

          def hr_pokevial_refill_cost_enabled
            @hr_pokevial_refill_cost_enabled.nil? ? 0 : @hr_pokevial_refill_cost_enabled.to_i
          end

          def hr_pokevial_refill_cost_enabled=(value)
            @hr_pokevial_refill_cost_enabled = value.to_i
          end

          def hr_pokevial_refill_cost_per_use
            @hr_pokevial_refill_cost_per_use.nil? ? ReloadedPokeVial::DEFAULT_REFILL_COST_PER_USE : @hr_pokevial_refill_cost_per_use.to_i
          end

          def hr_pokevial_refill_cost_per_use=(value)
            @hr_pokevial_refill_cost_per_use = value.to_i
          end
        end
      end

      def register_option
        return unless defined?(Reloaded::Options) && Reloaded::Options.respond_to?(:register_category_option)
        Reloaded::Options.register_category_option("RELOADED", :pokevial_options, priority: 6) do |_scene|
          [ActionButton.new(
            _INTL("PokeVial"),
            proc { ReloadedPokeVial.open_options if defined?(ReloadedPokeVial) },
            _INTL("Open PokeVial options.")
          )]
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to register PokeVial option", e, channel: :options) if defined?(Reloaded::Log)
      end
    end
  end
end

module ReloadedPokeVial
  SAVE_SYSTEM = :poke_vial

  DEFAULT_MAX_USES = 3
  DEFAULT_COOLDOWN_SECONDS = 5 * 60
  DEFAULT_REFILL_COST_PER_USE = 500

  # Add map IDs here if PokeVial access should be blocked somewhere later.
  BLOCKED_MAP_IDS = [].freeze
  # Optional per-map denial text. Example: { 123 => _INTL("The PokeVial signal is blocked here.") }
  BLOCKED_MAP_REASONS = {}.freeze
  # Optional progression rules. Switch rules use switch_id => max_uses.
  PROGRESSION_SWITCH_UNLOCKS = {}.freeze
  # Variable rules can use variable_id => max_uses or variable_id => { threshold => max_uses }.
  PROGRESSION_VARIABLE_UNLOCKS = {}.freeze
  MAX_USES_CAP = 5
  LOW_CHARGE_PERCENT = 35
  CALLBACK_EVENTS = [:before_use, :after_use, :before_refill, :after_refill].freeze
  ITEM_DEFINITIONS = {
    :POKEVIAL_CHARGE => {
      :name => "PokeVial Charge",
      :name_plural => "PokeVial Charges",
      :pocket => 2,
      :price => 500,
      :description => "A compact charge that restores one PokeVial use.",
      :icon => "Reloaded/Graphics/Items/pokevial_charge"
    },
    :POKEVIAL_REFILL => {
      :name => "PokeVial Refill",
      :name_plural => "PokeVial Refills",
      :pocket => 2,
      :price => 1500,
      :description => "A stored refill that restores all PokeVial charges.",
      :icon => "Reloaded/Graphics/Items/pokevial_refill"
    }
  }.freeze

  @fallback_state = {}
  @refill_sources = {}
  @callbacks = {}
  @item_patches_registered = false
  @healing_from_vial = false
  @pokecenter_heal_depth = 0

  class << self
    def enabled?
      ($PokemonSystem.hr_pokevial_enabled rescue 1).to_i == 1
    end

    def item_id?(item)
      key = item.to_sym rescue nil
      return true if key && ITEM_DEFINITIONS.key?(key)
      data = GameData::Item.get(item) rescue nil
      data && ITEM_DEFINITIONS.key?(data.id)
    rescue
      false
    end

    def progressive_enabled?
      ($PokemonSystem.hr_pokevial_progressive rescue 1).to_i == 1
    end

    def hp_only?
      ($PokemonSystem.hr_pokevial_heal_mode rescue 0).to_i == 1
    end

    def cooldown_enabled?
      ($PokemonSystem.hr_pokevial_cooldown_enabled rescue 0).to_i == 1
    end

    def refill_cost_enabled?
      ($PokemonSystem.hr_pokevial_refill_cost_enabled rescue 0).to_i == 1
    end

    def cooldown_seconds
      [($PokemonSystem.hr_pokevial_cooldown_seconds rescue DEFAULT_COOLDOWN_SECONDS).to_i, 0].max
    end

    def refill_cost_per_use
      [($PokemonSystem.hr_pokevial_refill_cost_per_use rescue DEFAULT_REFILL_COST_PER_USE).to_i, 0].max
    end

    def configured_max_uses
      if progressive_enabled?
        return [[progression_max_uses, 1].max, MAX_USES_CAP].min
      end
      value = ($PokemonSystem.hr_pokevial_max_uses rescue DEFAULT_MAX_USES).to_i
      [[value, 1].max, MAX_USES_CAP].min
    end

    def progression_max_uses
      [badge_progression_max_uses, saved_unlocked_max_uses, switch_progression_max_uses, variable_progression_max_uses].max
    rescue
      badge_progression_max_uses
    end

    def badge_progression_max_uses
      badges = ($Trainer.badge_count rescue 0).to_i
      1 + (badges / 2)
    end

    def saved_unlocked_max_uses
      [state_get(:unlocked_max_uses, 1).to_i, 1].max
    end

    def switch_progression_max_uses
      value = 1
      PROGRESSION_SWITCH_UNLOCKS.each do |switch_id, max_uses|
        next unless $game_switches && $game_switches[switch_id.to_i]
        value = [value, max_uses.to_i].max
      end
      value
    rescue
      1
    end

    def variable_progression_max_uses
      value = 1
      PROGRESSION_VARIABLE_UNLOCKS.each do |variable_id, rule|
        current = ($game_variables[variable_id.to_i] rescue 0).to_i
        if rule.is_a?(Hash)
          rule.each do |threshold, max_uses|
            value = [value, max_uses.to_i].max if current >= threshold.to_i
          end
        else
          value = [value, rule.to_i].max if current > 0
        end
      end
      value
    rescue
      1
    end

    def state_get(key, default = nil)
      if defined?(Reloaded::SaveData)
        Reloaded::SaveData.get(SAVE_SYSTEM, key, default, section: :systems)
      else
        @fallback_state[key.to_s] || @fallback_state[key.to_sym] || default
      end
    end

    def state_set(key, value)
      if defined?(Reloaded::SaveData)
        Reloaded::SaveData.set(SAVE_SYSTEM, key, value, section: :systems)
      else
        @fallback_state[key.to_s] = value
      end
    end

    def uses
      max = configured_max_uses
      value = state_get(:uses, nil)
      if value.nil?
        state_set(:uses, max)
        return max
      end
      clamped = [[value.to_i, 0].max, max].min
      state_set(:uses, clamped) if clamped != value.to_i
      clamped
    end

    def set_uses(value)
      state_set(:uses, [[value.to_i, 0].max, configured_max_uses].min)
    end

    def clamp_uses_to_max
      set_uses(uses)
    end

    def set_max_uses(amount)
      return false unless $PokemonSystem
      $PokemonSystem.hr_pokevial_progressive = 0
      $PokemonSystem.hr_pokevial_max_uses = [[amount.to_i, 1].max, MAX_USES_CAP].min
      clamp_uses_to_max
      true
    rescue Exception => e
      log_exception("PokeVial max uses update failed", e)
      false
    end

    def unlock_max_uses(amount, source: :script, refill: false, notify: true)
      target = [[amount.to_i, 1].max, MAX_USES_CAP].min
      before = configured_max_uses
      state_set(:unlocked_max_uses, [saved_unlocked_max_uses, target].max)
      after = configured_max_uses
      refill ? refill() : clamp_uses_to_max
      if after > before
        log_info("PokeVial max uses unlocked source=#{source} max=#{after}")
        pbMessage(_INTL("PokeVial max charges increased to {1}.", after)) if notify
      end
      after > before
    rescue Exception => e
      log_exception("PokeVial max uses unlock failed", e)
      false
    end

    def increase_max_uses(amount = 1, source: :script, refill: false, notify: true)
      qty = [amount.to_i, 1].max
      unlock_max_uses(configured_max_uses + qty, source: source, refill: refill, notify: notify)
    end

    def refill
      set_uses(configured_max_uses)
    end

    def refill_with_hooks(source: :script, notify: true, cost: 0, context: {})
      before = uses
      max = configured_max_uses
      return false if before >= max
      ctx = {
        :source => source,
        :uses_before => before,
        :uses_after => max,
        :max_uses => max,
        :restored => max - before,
        :cost => cost.to_i
      }.merge(context || {})
      return false unless run_callbacks(:before_refill, ctx)
      refill
      ctx[:uses_after] = uses
      ctx[:restored] = ctx[:uses_after].to_i - before
      run_callbacks(:after_refill, ctx)
      pbMessage(_INTL("PokeVial refilled. Charges: {1}.", uses)) if notify
      true
    rescue Exception => e
      log_exception("PokeVial refill failed", e)
      false
    end

    def uses_needed_for_refill
      [configured_max_uses - uses, 0].max
    end

    def can_refill?
      enabled? && uses_needed_for_refill > 0
    rescue
      false
    end

    def grant_full_refill(source: :script, notify: true)
      return false unless enabled?
      before = uses
      return false unless refill_with_hooks(source: source, notify: false)
      restored = uses - before
      log_info("PokeVial full refill granted source=#{source} restored=#{restored} uses=#{uses}/#{configured_max_uses}")
      pbMessage(_INTL("PokeVial was fully refilled. Charges: {1}.", uses)) if notify
      true
    rescue Exception => e
      log_exception("PokeVial full refill failed", e)
      false
    end
    alias grant_refill grant_full_refill

    def can_add_uses?(amount = 1)
      return false unless enabled?
      qty = amount.to_i
      qty > 0 && uses + qty <= configured_max_uses
    rescue
      false
    end

    def add_uses(amount, source: :script, notify: true, allow_overflow: false)
      qty = amount.to_i
      return 0 if qty <= 0
      before = uses
      target = before + qty
      target = [target, configured_max_uses].min unless allow_overflow
      set_uses(target)
      added = uses - before
      if added > 0
        log_info("PokeVial uses granted amount=#{added} source=#{source} uses=#{uses}/#{configured_max_uses}")
        pbMessage(_INTL("Received {1} PokeVial charge(s). Charges: {2}.", added, uses)) if notify
      end
      added
    rescue Exception => e
      log_exception("PokeVial add uses failed", e)
      0
    end
    alias grant_uses add_uses

    def register_refill_source(id, handler = nil, &block)
      key = id.to_sym rescue nil
      callable = block || handler
      return false unless key && callable.respond_to?(:call)
      @refill_sources[key] = callable
      log_info("Registered PokeVial refill source #{key}")
      true
    rescue Exception => e
      log_exception("PokeVial refill source registration failed", e)
      false
    end

    def refill_from_source(id, notify: true)
      key = id.to_sym rescue nil
      handler = @refill_sources[key]
      return false unless key && handler
      result = handler.call(self)
      return false if result == false
      return false unless refill_with_hooks(source: key, notify: notify)
      log_info("PokeVial refilled source=#{key} uses=#{uses}/#{configured_max_uses}")
      true
    rescue Exception => e
      log_exception("PokeVial refill source failed", e)
      false
    end

    def last_use_time
      state_get(:last_use_time, 0).to_i
    end

    def record_use_time
      state_set(:last_use_time, Time.now.to_i)
    end

    def cooldown_remaining_seconds
      return 0 unless cooldown_enabled?
      last = last_use_time
      return 0 if last <= 0
      remaining = cooldown_seconds - (Time.now.to_i - last)
      remaining > 0 ? remaining : 0
    rescue
      0
    end

    def format_time(total_seconds)
      seconds = [total_seconds.to_i, 0].max
      minutes = seconds / 60
      secs = seconds % 60
      hours = minutes / 60
      minutes %= 60
      hours > 0 ? sprintf("%02d:%02d:%02d", hours, minutes, secs) : sprintf("%02d:%02d", minutes, secs)
    end

    def status_text
      return "" unless enabled?
      remaining = cooldown_remaining_seconds
      return "Cooldown: #{format_time(remaining)}" if remaining > 0
      return "EMPTY" if uses <= 0
      "Charges: #{uses}"
    rescue
      ""
    end

    def low_charges?
      return false if uses <= 0
      max = configured_max_uses
      return false if max <= 0
      (uses.to_f / max.to_f) * 100.0 <= LOW_CHARGE_PERCENT
    rescue
      false
    end

    def status_color
      return Color.new(235, 80, 80) if uses <= 0
      return Color.new(255, 205, 90) if cooldown_remaining_seconds > 0 || low_charges?
      Color.new(120, 230, 150)
    rescue
      Color.new(120, 230, 150)
    end

    def current_map_id
      $game_map ? $game_map.map_id.to_i : 0
    rescue
      0
    end

    def blocked_map?
      map_id = current_map_id
      BLOCKED_MAP_IDS.include?(map_id) || BLOCKED_MAP_REASONS.key?(map_id)
    end

    def blocked_map_reason
      BLOCKED_MAP_REASONS[current_map_id] || _INTL("The PokeVial cannot be used here.")
    rescue
      _INTL("The PokeVial cannot be used here.")
    end

    def map_transfer_pending?
      return false unless $game_temp
      return true if $game_temp.respond_to?(:player_transferring) && $game_temp.player_transferring
      if $game_temp.respond_to?(:player_new_map_id)
        new_map_id = ($game_temp.player_new_map_id rescue 0).to_i
        return true if new_map_id > 0 && new_map_id != current_map_id
      end
      false
    rescue
      false
    end

    def event_or_transition_busy?
      return true if map_transfer_pending?
      return true if battle_or_restricted_state?
      return true if defined?(pbMapInterpreterRunning?) && pbMapInterpreterRunning?
      return true if $game_temp && ($game_temp.respond_to?(:message_window_showing) && $game_temp.message_window_showing)
      return true if $game_player && ($game_player.respond_to?(:move_route_forcing) && $game_player.move_route_forcing)
      false
    rescue
      true
    end

    def battle_or_restricted_state?
      return true if $game_temp && ($game_temp.respond_to?(:in_battle) && $game_temp.in_battle)
      return true if defined?(pbInSafari?) && pbInSafari?
      return true if defined?(pbInBugContest?) && pbInBugContest?
      false
    rescue
      true
    end

    def party_ready?
      defined?($Trainer) && $Trainer && $Trainer.respond_to?(:party) && $Trainer.party && !$Trainer.party.empty?
    rescue
      false
    end

    def selectable?
      return false unless enabled?
      return false unless party_ready?
      return false if blocked_map?
      return false if event_or_transition_busy?
      true
    rescue
      false
    end

    def lock_reason
      return _INTL("PokeVial is turned off.") unless enabled?
      return _INTL("You do not have any Pokemon yet.") unless party_ready?
      return blocked_map_reason if blocked_map?
      return _INTL("The PokeVial cannot be used right now.") if event_or_transition_busy?
      _INTL("The PokeVial cannot be used right now.")
    rescue
      "The PokeVial cannot be used right now."
    end

    def deny(message, popup: nil)
      pbPlayBuzzerSE rescue nil
      if popup
        popup.call(message)
      else
        pbMessage(message) rescue nil
      end
      false
    end

    def use_from_menu(source = :repm, popup: nil)
      return deny(lock_reason, popup: popup) unless selectable?
      return deny(_INTL("The PokeVial is EMPTY. Visit a PokeCenter to replenish it."), popup: popup) if uses <= 0
      remaining = cooldown_remaining_seconds
      if remaining > 0
        return deny(_INTL("Cooldown: {1}.", format_time(remaining)), popup: popup)
      end
      ctx = {
        :source => source,
        :uses_before => uses,
        :uses_after => uses - 1,
        :max_uses => configured_max_uses,
        :heal_mode => hp_only? ? :hp_only : :full
      }
      unless run_callbacks(:before_use, ctx)
        return deny(ctx[:message] || _INTL("The PokeVial cannot be used right now."), popup: popup)
      end
      @healing_from_vial = true
      heal_party
      set_uses(uses - 1)
      record_use_time
      @healing_from_vial = false
      ctx[:uses_after] = uses
      run_callbacks(:after_use, ctx)
      pbPlayDecisionSE rescue nil
      message = _INTL("Your party was healed. Charges: {1}.", uses)
      popup ? popup.call(message) : (pbMessage(message) rescue nil)
      true
    rescue Exception => e
      @healing_from_vial = false
      log_exception("PokeVial use failed", e)
      deny(_INTL("The PokeVial cannot be used right now."), popup: popup)
    end

    def use_from_overworld_menu(screen)
      if screen && screen.respond_to?(:show_popup_menu)
        choice = screen.show_popup_menu("POKEVIAL", ["Use PokeVial", "Back"])
        return false unless choice == 0
      elsif !pbConfirmMessage(_INTL("Use the PokeVial?"))
        return false
      end
      use_from_menu(:overworld_menu, popup: proc { |message|
        screen.show_popup("POKEVIAL", [message]) if screen
      })
    end

    def heal_party
      return false unless party_ready?
      $Trainer.party.each do |pkmn|
        next unless pkmn
        hp_only? ? pkmn.heal_HP : pkmn.heal
      end
      true
    end

    def healing_from_vial?
      @healing_from_vial
    end

    def pokecenter_refill_context?
      return false unless enabled?
      return false if healing_from_vial?
      stack = caller.join("\n").downcase rescue ""
      return true if stack.include?("pokecenter") || stack.include?("poke_center") || stack.include?("pokemon center")
      center_map = ($PokemonGlobal.pokecenterMapId rescue -1).to_i
      center_map > 0 && current_map_id == center_map
    rescue
      false
    end

    def after_trainer_heal_party
      return false unless @pokecenter_heal_depth.to_i > 0 || pokecenter_refill_context?
      refill_from_pokecenter
    end

    def with_pokecenter_heal_context
      @pokecenter_heal_depth = @pokecenter_heal_depth.to_i + 1
      yield
    ensure
      @pokecenter_heal_depth = [@pokecenter_heal_depth.to_i - 1, 0].max
    end

    def refill_from_pokecenter
      needed = uses_needed_for_refill
      return false if needed <= 0
      current = uses
      max = configured_max_uses
      cost = refill_cost_enabled? ? needed * refill_cost_per_use : 0
      prompt = _INTL("Refill PokeVial?\nCost: ${1}\nCharges: {2} -> {3}", cost.to_s_formatted, current, max)
      return false unless pbConfirmMessage(prompt)
      ctx = {
        :source => :pokecenter,
        :uses_before => current,
        :uses_after => max,
        :max_uses => max,
        :restored => max - current,
        :cost => cost,
        :charges_before => current,
        :charges_after => max
      }
      return false unless run_callbacks(:before_refill, ctx)
      if cost > 0
        money = ($Trainer.money rescue 0).to_i
        unless money >= cost
          pbMessage(_INTL("You don't have enough money to refill PokeVial. Need ${1}.", cost.to_s_formatted)) rescue nil
          return false
        end
        $Trainer.money -= cost
        pbSEPlay("Mart buy item") rescue nil
      end
      refill
      ctx[:uses_after] = uses
      ctx[:charges_after] = uses
      run_callbacks(:after_refill, ctx)
      log_info("PokeVial refilled at PokeCenter uses=#{uses}/#{configured_max_uses} cost=#{cost}")
      pbMessage(_INTL("PokeVial refilled. Charges: {1}.", uses)) rescue nil
      true
    rescue Exception => e
      log_exception("PokeVial PokeCenter refill failed", e)
      false
    end

    def open_options
      return unless defined?(ReloadedPokeVial::OptionsScene)
      pbFadeOutIn do
        scene = ReloadedPokeVial::OptionsScene.new
        screen = PokemonOptionScreen.new(scene)
        screen.pbStartScreen
      end
    rescue Exception => e
      log_exception("PokeVial options failed", e)
    end

    def install_runtime_patches
      install_item_icon_patch
      register_item_patches
      register_item_handlers
      install_trainer_heal_patch
      install_interpreter_recover_all_patch
      install_mystery_gift_patch
    end

    def register_item_patches
      return true if @item_patches_registered
      return false unless defined?(Reloaded::DataPatches) &&
                          Reloaded::DataPatches.respond_to?(:register_internal_patch)
      registered = 0
      ITEM_DEFINITIONS.each do |item_id, config|
        next unless Reloaded::DataPatches.register_internal_patch(
          "items",
          item_id.to_s,
          item_patch_data(item_id, config),
          owner: :pokevial,
          source: "Reloaded/Modules/006_PokeVial.rb",
          hidden: true
        )
        registered += 1
      end
      @item_patches_registered = true
      Reloaded::DataPatches.rebuild if registered > 0 && Reloaded::DataPatches.respond_to?(:rebuild)
      log_info("Registered PokeVial item datapatches count=#{registered}") if registered > 0
      true
    rescue Exception => e
      log_exception("PokeVial item datapatch registration failed", e)
      false
    end

    def item_patch_data(item_id, config)
      {
        "id" => item_id.to_s,
        "name" => config[:name].to_s,
        "name_plural" => config[:name_plural].to_s,
        "pocket" => config[:pocket].to_i,
        "price" => config[:price].to_i,
        "description" => config[:description].to_s,
        "field_use" => 2,
        "battle_use" => 0,
        "type" => 0,
        "move" => nil
      }
    end

    def register_item_handlers
      return false unless defined?(ItemHandlers) && ItemHandlers.const_defined?(:UseFromBag)
      ItemHandlers::UseFromBag.add(:POKEVIAL_CHARGE, proc { |_item|
        next use_charge_item
      })
      ItemHandlers::UseFromBag.add(:POKEVIAL_REFILL, proc { |_item|
        next use_refill_item
      })
      true
    rescue Exception => e
      log_exception("PokeVial item handler registration failed", e)
      false
    end

    def use_charge_item
      unless can_add_uses?(1)
        pbMessage(_INTL("The PokeVial has no empty charge slots.")) rescue nil
        return 0
      end
      added = add_uses(1, source: :item, notify: false)
      return 0 if added <= 0
      pbMessage(_INTL("The PokeVial regained 1 charge. Charges: {1}.", uses)) rescue nil
      3
    rescue Exception => e
      log_exception("PokeVial Charge item failed", e)
      pbMessage(_INTL("The PokeVial Charge could not be used right now.")) rescue nil
      0
    end

    def use_refill_item
      unless can_refill?
        pbMessage(_INTL("The PokeVial is already full.")) rescue nil
        return 0
      end
      return 0 unless grant_full_refill(source: :item, notify: false)
      pbMessage(_INTL("The PokeVial was fully refilled. Charges: {1}.", uses)) rescue nil
      3
    rescue Exception => e
      log_exception("PokeVial Refill item failed", e)
      pbMessage(_INTL("The PokeVial Refill could not be used right now.")) rescue nil
      0
    end

    def install_item_icon_patch
      return false unless defined?(GameData::Item)
      singleton = class << GameData::Item; self; end
      return true if singleton.method_defined?(:reloaded_pokevial_original_icon_filename)
      singleton.class_eval do
        alias_method :reloaded_pokevial_original_icon_filename, :icon_filename
        def icon_filename(item)
          custom = ReloadedPokeVial.item_icon_filename(item) if defined?(ReloadedPokeVial)
          return custom if custom
          reloaded_pokevial_original_icon_filename(item)
        end
      end
      true
    rescue Exception => e
      log_exception("PokeVial item icon patch failed", e)
      false
    end

    def item_icon_filename(item)
      data = GameData::Item.try_get(item) rescue nil
      return nil unless data
      config = ITEM_DEFINITIONS[data.id]
      return nil unless config
      path = config[:icon].to_s
      pbResolveBitmap(path) ? path : nil
    rescue
      nil
    end

    def install_trainer_heal_patch
      return false unless defined?(Trainer)
      return true if Trainer.method_defined?(:reloaded_pokevial_original_heal_party)
      Trainer.class_eval do
        alias_method :reloaded_pokevial_original_heal_party, :heal_party
        def heal_party
          result = reloaded_pokevial_original_heal_party
          ReloadedPokeVial.after_trainer_heal_party if defined?(ReloadedPokeVial)
          result
        end
      end
      log_info("Installed PokeVial Trainer#heal_party patch")
      true
    rescue Exception => e
      log_exception("PokeVial Trainer#heal_party patch failed", e)
      false
    end

    def install_interpreter_recover_all_patch
      return false unless defined?(Interpreter)
      return true if Interpreter.method_defined?(:reloaded_pokevial_original_command_314)
      Interpreter.class_eval do
        alias_method :reloaded_pokevial_original_command_314, :command_314
        def command_314
          if defined?(ReloadedPokeVial) && @parameters && @parameters[0] == 0
            return ReloadedPokeVial.with_pokecenter_heal_context { reloaded_pokevial_original_command_314 }
          end
          reloaded_pokevial_original_command_314
        end
      end
      log_info("Installed PokeVial Recover All patch")
      true
    rescue Exception => e
      log_exception("PokeVial Recover All patch failed", e)
      false
    end

    def install_mystery_gift_patch
      return true if Object.private_method_defined?(:reloaded_pokevial_original_pbReceiveMysteryGift) || Object.method_defined?(:reloaded_pokevial_original_pbReceiveMysteryGift)
      return false unless Object.private_method_defined?(:pbReceiveMysteryGift) || Object.method_defined?(:pbReceiveMysteryGift)
      was_private = Object.private_method_defined?(:pbReceiveMysteryGift)
      Object.class_eval do
        alias_method :reloaded_pokevial_original_pbReceiveMysteryGift, :pbReceiveMysteryGift
        def pbReceiveMysteryGift(id)
          handled = ReloadedPokeVial.receive_mystery_gift(id) if defined?(ReloadedPokeVial)
          return handled unless handled.nil?
          reloaded_pokevial_original_pbReceiveMysteryGift(id)
        end
        private :pbReceiveMysteryGift if was_private
        private :reloaded_pokevial_original_pbReceiveMysteryGift if was_private
      end
      log_info("Installed PokeVial Mystery Gift patch")
      true
    rescue Exception => e
      log_exception("PokeVial Mystery Gift patch failed", e)
      false
    end

    def receive_mystery_gift(id)
      return nil unless defined?($Trainer) && $Trainer && $Trainer.respond_to?(:mystery_gifts)
      index = -1
      for i in 0...$Trainer.mystery_gifts.length
        if $Trainer.mystery_gifts[i][0] == id && $Trainer.mystery_gifts[i].length > 1
          index = i
          break
        end
      end
      return nil if index < 0
      gift = $Trainer.mystery_gifts[index]
      payload = gift[2]
      return nil unless mystery_gift_payload?(payload)
      kind = mystery_gift_kind(payload)
      amount = mystery_gift_amount(payload, gift[1])
      if kind == :refill
        unless can_refill?
          pbMessage(_INTL("Your PokeVial is already full.")) rescue nil
          return false
        end
        return false unless grant_full_refill(source: :mystery_gift, notify: false)
        pbMessage(_INTL("\\me[Item get]You received a PokeVial refill!\\wtnp[30]")) rescue nil
      elsif kind == :max_uses
        if amount <= configured_max_uses
          pbMessage(_INTL("Your PokeVial is already upgraded enough.")) rescue nil
          return false
        end
        refill_after = mystery_gift_refill_after_unlock?(payload)
        return false unless unlock_max_uses(amount, source: :mystery_gift, refill: refill_after, notify: false)
        pbMessage(_INTL("\\me[Item get]PokeVial max charges increased to {1}!\\wtnp[30]", configured_max_uses)) rescue nil
      elsif amount <= 0
        pbMessage(_INTL("This PokeVial gift is unavailable.")) rescue nil
        return false
      else
        unless can_add_uses?(amount)
          pbMessage(_INTL("Your PokeVial does not have enough empty charge slots. Use some charges first.")) rescue nil
          return false
        end
        added = add_uses(amount, source: :mystery_gift, notify: false)
        return false if added <= 0
        pbMessage(_INTL("\\me[Item get]You received {1} PokeVial charge(s)! Charges: {2}.\\wtnp[30]", added, uses)) rescue nil
      end
      $Trainer.mystery_gifts[index] = [id]
      log_info("PokeVial Mystery Gift claimed id=#{id} kind=#{kind} amount=#{amount}")
      true
    rescue Exception => e
      log_exception("PokeVial Mystery Gift claim failed", e)
      false
    end

    def mystery_gift_payload?(payload)
      return true if [:POKEVIAL, :POKEVIAL_CHARGE, :POKEVIAL_USES, :POKEVIAL_REFILL, :POKEVIAL_MAX_USES, :PokeVial].include?(payload)
      return false unless payload.is_a?(Hash)
      marker = payload["type"] || payload[:type] || payload["kind"] || payload[:kind] || payload["id"] || payload[:id]
      ["pokevial", "poke_vial", "pokevial_charge", "POKEVIAL_CHARGE", "pokevial_uses", "POKEVIAL_USES", "pokevial_refill", "poke_vial_refill",
       "POKEVIAL_REFILL", "refill_pokevial", "pokevial_max", "pokevial_max_uses", "POKEVIAL_MAX_USES",
       "pokevial_unlock", "poke_vial_unlock"].include?(marker.to_s)
    rescue
      false
    end

    def mystery_gift_kind(payload)
      return :refill if [:POKEVIAL_REFILL].include?(payload)
      return :max_uses if [:POKEVIAL_MAX_USES].include?(payload)
      return :uses unless payload.is_a?(Hash)
      marker = payload["type"] || payload[:type] || payload["kind"] || payload[:kind] || payload["id"] || payload[:id]
      text = marker.to_s
      return :refill if ["pokevial_refill", "poke_vial_refill", "POKEVIAL_REFILL", "refill_pokevial"].include?(text)
      return :max_uses if ["pokevial_max", "pokevial_max_uses", "POKEVIAL_MAX_USES", "pokevial_unlock", "poke_vial_unlock"].include?(text)
      :uses
    rescue
      :uses
    end

    def mystery_gift_amount(payload, fallback)
      return [fallback.to_i, 1].max unless payload.is_a?(Hash)
      value = payload["max_uses"] || payload[:max_uses] || payload["max"] || payload[:max]
      value ||= payload["quantity"] || payload[:quantity] || payload["qty"] || payload[:qty] || payload["uses"] || payload[:uses] || fallback
      [value.to_i, 1].max
    rescue
      1
    end

    def mystery_gift_refill_after_unlock?(payload)
      return false unless payload.is_a?(Hash)
      value = payload["refill"] || payload[:refill] || payload["fill"] || payload[:fill]
      value == true || value.to_s.downcase == "true" || value.to_i == 1
    rescue
      false
    end

    def log_info(message)
      Reloaded::Log.info(message, :modules) if defined?(Reloaded::Log)
    rescue
    end

    def on(event, id = nil, handler = nil, &block)
      register_callback(event, id, handler, &block)
    end

    def register_callback(event, id = nil, handler = nil, &block)
      event_key = event.to_sym rescue nil
      return false unless CALLBACK_EVENTS.include?(event_key)
      callable = block || handler
      return false unless callable.respond_to?(:call)
      callback_id = id ? id.to_sym : callable.object_id
      @callbacks[event_key] ||= []
      @callbacks[event_key].reject! { |row| row[:id] == callback_id }
      @callbacks[event_key] << { :id => callback_id, :handler => callable }
      log_info("Registered PokeVial callback event=#{event_key} id=#{callback_id}")
      true
    rescue Exception => e
      log_exception("PokeVial callback registration failed", e)
      false
    end

    def unregister_callback(event, id)
      event_key = event.to_sym rescue nil
      callback_id = id.to_sym rescue nil
      return false unless event_key && callback_id && @callbacks[event_key]
      before = @callbacks[event_key].length
      @callbacks[event_key].reject! { |row| row[:id] == callback_id }
      before != @callbacks[event_key].length
    rescue
      false
    end

    def run_callbacks(event, context = {})
      event_key = event.to_sym rescue nil
      Array(@callbacks[event_key]).each do |row|
        result = row[:handler].call(context)
        return false if result == false
      end
      true
    rescue Exception => e
      log_exception("PokeVial callback failed event=#{event}", e)
      false
    end

    def log_exception(message, error)
      Reloaded::Log.exception(message, error, channel: :modules) if defined?(Reloaded::Log)
    rescue
    end
  end

  class OptionsScene < PokemonOption_Scene
    def initUIElements
      super
      @sprites["title"].text = _INTL("PokeVial") rescue nil
    end

    def pbGetOptions(_inloadscreen = false)
      cooldown_values = [5, 10, 15, 20, 25, 30, 35, 40, 45]
      cooldown_labels = cooldown_values.map { |minutes| _INTL("{1} min", minutes) }
      options = [
        EnumOption.new(
          _INTL("PokeVial"),
          [_INTL("Off"), _INTL("On")],
          proc { ReloadedPokeVial.enabled? ? 1 : 0 },
          proc { |value| $PokemonSystem.hr_pokevial_enabled = value.to_i if $PokemonSystem },
          _INTL("Controls whether the PokeVial can be used from Reloaded menus.")
        ),
        EnumOption.new(
          _INTL("Progressive Uses"),
          [_INTL("Off"), _INTL("On")],
          proc { ReloadedPokeVial.progressive_enabled? ? 1 : 0 },
          proc { |value|
            $PokemonSystem.hr_pokevial_progressive = value.to_i if $PokemonSystem
          },
          _INTL("Auto-scales max charges by badge count.")
        )
      ]
      if ReloadedPokeVial.progressive_enabled?
        options << EnumOption.new(
          _INTL("Max Uses"),
          [_INTL("Auto ({1})", ReloadedPokeVial.configured_max_uses)],
          proc { 0 },
          proc { |_value| },
          _INTL("Current max charges are controlled by Progressive Uses.")
        )
      else
        options << SliderOption.new(
          _INTL("Max Uses"),
          1, 5, 1,
          proc { ReloadedPokeVial.configured_max_uses },
          proc { |value| ReloadedPokeVial.set_max_uses(value) },
          _INTL("Maximum PokeVial charges between refills.")
        )
      end
      options.concat([
        EnumOption.new(
          _INTL("Heal Mode"),
          [_INTL("Full Heal"), _INTL("HP Only")],
          proc { ReloadedPokeVial.hp_only? ? 1 : 0 },
          proc { |value| $PokemonSystem.hr_pokevial_heal_mode = value.to_i if $PokemonSystem },
          _INTL("Full Heal restores HP, status, and PP. HP Only restores HP.")
        ),
        EnumOption.new(
          _INTL("Cooldown"),
          [_INTL("Off"), _INTL("On")],
          proc { ReloadedPokeVial.cooldown_enabled? ? 1 : 0 },
          proc { |value| $PokemonSystem.hr_pokevial_cooldown_enabled = value.to_i if $PokemonSystem },
          _INTL("Controls whether the PokeVial must recharge between uses.")
        ),
        EnumOption.new(
          _INTL("Cooldown Time (Real)"),
          cooldown_labels,
          proc {
            minutes = ReloadedPokeVial.cooldown_seconds / 60
            cooldown_values.index(minutes) || 0
          },
          proc { |index| $PokemonSystem.hr_pokevial_cooldown_seconds = cooldown_values[index.to_i] * 60 if $PokemonSystem },
          _INTL("Recharge time between PokeVial uses.")
        ),
        EnumOption.new(
          _INTL("PokeCenter Cost"),
          [_INTL("Off"), _INTL("On")],
          proc { ReloadedPokeVial.refill_cost_enabled? ? 1 : 0 },
          proc { |value| $PokemonSystem.hr_pokevial_refill_cost_enabled = value.to_i if $PokemonSystem },
          _INTL("Controls whether PokeCenters charge money to refill PokeVial uses.")
        ),
        SliderOption.new(
          _INTL("Cost Per Use"),
          0, 5000, 100,
          proc { ReloadedPokeVial.refill_cost_per_use },
          proc { |value| $PokemonSystem.hr_pokevial_refill_cost_per_use = value.to_i if $PokemonSystem },
          _INTL("Cost for each missing PokeVial charge when refilling.")
        )
      ])
      options
    end
  end
end

Reloaded::PokeVialFeature.install if defined?(Reloaded::PokeVialFeature)

if defined?(ReloadedPauseMenu)
  ReloadedPauseMenu.register_module(
    :POKEVIAL,
    label: "PokeVial",
    handler: proc { ReloadedPokeVial.use_from_menu(:repm) },
    icon: "Reloaded/Graphics/ReloadedMenu/POKEVIAL",
    condition: proc { ReloadedPokeVial.selectable? },
    lock_reason: proc { ReloadedPokeVial.lock_reason },
    status: proc { ReloadedPokeVial.status_text },
    status_color: proc { ReloadedPokeVial.status_color }
  )
end

if defined?(OverworldMenu)
  OverworldMenu.register(:pokevial,
    :label => "PokeVial",
    :priority => 7,
    :condition => proc { ReloadedPokeVial.enabled? && ReloadedPokeVial.party_ready? },
    :handler => proc { |screen| ReloadedPokeVial.use_from_overworld_menu(screen) },
    :status => proc { ReloadedPokeVial.status_text },
    :status_color => proc { ReloadedPokeVial.status_color }
  )
end

if defined?(Events) && Events.respond_to?(:onMapUpdate)
  Events.onMapUpdate += proc { |_sender, _event|
    ReloadedPokeVial.install_runtime_patches if defined?(ReloadedPokeVial)
  }
end
