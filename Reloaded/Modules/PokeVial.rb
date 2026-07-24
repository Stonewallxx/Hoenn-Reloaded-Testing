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

          def hr_pokevial_refill_mode
            value = @hr_pokevial_refill_mode.nil? ? ReloadedPokeVial::REFILL_MODE_ASK : @hr_pokevial_refill_mode.to_i
            [[value, ReloadedPokeVial::REFILL_MODE_ASK].max, ReloadedPokeVial::REFILL_MODE_NEVER].min
          end

          def hr_pokevial_refill_mode=(value)
            @hr_pokevial_refill_mode = [[value.to_i, ReloadedPokeVial::REFILL_MODE_ASK].max, ReloadedPokeVial::REFILL_MODE_NEVER].min
          end
        end
      end

      def register_option
        return unless defined?(Reloaded::Options) && Reloaded::Options.respond_to?(:register_category_option)
        Reloaded::Options.register_category_option("GAMEPLAY", :pokevial_options, priority: 0) do |_scene|
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
  REFILL_BASE_COST = 500
  REFILL_BADGE_COST = 100
  REFILL_PARTY_COST = 50
  HARD_REFILL_COST_PERCENT = 125
  HARD_COOLDOWN_SECONDS = 10 * 60
  REFILL_MODE_ASK = 0
  REFILL_MODE_AUTOMATIC = 1
  REFILL_MODE_NEVER = 2

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
  @capacity_notice_frames = nil

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
      progressive_forced? || ($PokemonSystem.hr_pokevial_progressive rescue 1).to_i == 1
    end

    def progressive_forced?
      hard_difficulty?
    end

    def hard_difficulty?
      return ReloadedDifficulty.hard? if defined?(ReloadedDifficulty)
      if defined?($game_switches) && $game_switches && Object.const_defined?(:SWITCH_GAME_DIFFICULTY_HARD)
        return true if $game_switches[Object.const_get(:SWITCH_GAME_DIFFICULTY_HARD)]
      end
      ($Trainer.selected_difficulty rescue nil).to_i == 2
    rescue
      false
    end

    def hp_only?
      ($PokemonSystem.hr_pokevial_heal_mode rescue 0).to_i == 1
    end

    def cooldown_enabled?
      cooldown_forced? || ($PokemonSystem.hr_pokevial_cooldown_enabled rescue 0).to_i == 1
    end

    def cooldown_forced?
      hard_difficulty?
    end

    def pokecenter_refill_mode
      value = ($PokemonSystem.hr_pokevial_refill_mode rescue REFILL_MODE_ASK).to_i
      [:ask, :automatic, :never][[value, REFILL_MODE_ASK].max] || :never
    end

    def cooldown_seconds
      return HARD_COOLDOWN_SECONDS if cooldown_forced?
      [($PokemonSystem.hr_pokevial_cooldown_seconds rescue DEFAULT_COOLDOWN_SECONDS).to_i, 0].max
    end

    def trainer_badge_count
      [($Trainer.badge_count rescue 0).to_i, 0].max
    end

    def trainer_party_size
      party = $Trainer.party rescue []
      Array(party).compact.length
    rescue
      0
    end

    def refill_cost_per_charge
      REFILL_BASE_COST +
        trainer_badge_count * REFILL_BADGE_COST +
        trainer_party_size * REFILL_PARTY_COST
    end

    def refill_cost_percent
      hard_difficulty? ? HARD_REFILL_COST_PERCENT : 100
    end

    def pokecenter_refill_cost(missing_charges = uses_needed_for_refill)
      base_cost = [missing_charges.to_i, 0].max * refill_cost_per_charge
      (base_cost * refill_cost_percent / 100.0).ceil
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

    def update_progressive_badge_unlock
      current_badge_max = [[badge_progression_max_uses, 1].max, MAX_USES_CAP].min
      observed = state_get(:observed_badge_max_uses, nil)
      if observed.nil?
        state_set(:observed_badge_max_uses, current_badge_max)
        return false
      end
      observed = [[observed.to_i, 1].max, MAX_USES_CAP].min
      unless progressive_enabled?
        state_set(:observed_badge_max_uses, current_badge_max) if observed != current_badge_max
        return false
      end
      if current_badge_max > observed
        prior_max = [observed, saved_unlocked_max_uses, switch_progression_max_uses,
                     variable_progression_max_uses].max
        prior_max = [[prior_max, 1].max, MAX_USES_CAP].min
        current_max = configured_max_uses
        if current_max > prior_max
          added_capacity = current_max - prior_max
          set_uses([uses + added_capacity, current_max].min)
          queue_capacity_notice(current_max, added_capacity)
        end
      end
      state_set(:observed_badge_max_uses, current_badge_max) if observed != current_badge_max
      true
    rescue Exception => e
      log_exception("PokeVial badge progression update failed", e)
      false
    end

    def queue_capacity_notice(max_uses, added_charges)
      state_set(:pending_capacity_notice, {
        "max_uses" => max_uses.to_i,
        "added_charges" => added_charges.to_i
      })
      @capacity_notice_frames = 15
      true
    end

    def update_capacity_notice
      notice = state_get(:pending_capacity_notice, nil)
      return false unless notice.is_a?(Hash)
      return false if event_or_transition_busy?
      @capacity_notice_frames = 15 if @capacity_notice_frames.nil?
      @capacity_notice_frames -= 1
      return false if @capacity_notice_frames > 0
      max_uses = (notice["max_uses"] || notice[:max_uses]).to_i
      added = (notice["added_charges"] || notice[:added_charges]).to_i
      label = added == 1 ? _INTL("charge") : _INTL("charges")
      notify(:success, _INTL("PokeVial capacity increased to {1}. The new {2} {3} ready.",
                             max_uses, label, added == 1 ? _INTL("is") : _INTL("are")))
      state_set(:pending_capacity_notice, nil)
      @capacity_notice_frames = nil
      true
    rescue Exception => e
      @capacity_notice_frames = nil
      log_exception("PokeVial capacity notice failed", e)
      false
    end

    def update_overworld
      update_progressive_badge_unlock
      update_capacity_notice
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
        notify(:success, _INTL("PokeVial max charges increased to {1}.", after)) if notify
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
      notify(:success, _INTL("PokeVial refilled. Charges: {1}.", uses)) if notify
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
      notify(:success, _INTL("PokeVial was fully refilled. Charges: {1}.", uses)) if notify
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
        notify(:success, _INTL("Received {1} PokeVial charge(s). Charges: {2}.", added, uses)) if notify
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
      value = state_get(:last_use_time, 0).to_i
      now = Time.now.to_i
      if value <= 0
        state_set(:last_use_time, 0) if value != 0
        return 0
      end
      if value > now
        state_set(:last_use_time, now)
        return now
      end
      value
    rescue
      state_set(:last_use_time, 0) rescue nil
      0
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

    def notify(kind, message, options = {})
      if defined?(Reloaded)
        case kind.to_sym
        when :success
          return Reloaded.toast_success(message.to_s, options) if Reloaded.respond_to?(:toast_success)
        when :error
          return Reloaded.toast_error(message.to_s, options) if Reloaded.respond_to?(:toast_error)
        else
          return Reloaded.toast_warning(message.to_s, options) if Reloaded.respond_to?(:toast_warning)
        end
      end
      pbMessage(message.to_s) rescue nil
    rescue
      pbMessage(message.to_s) rescue nil
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

    def pokemon_needs_healing?(pkmn)
      return false unless pkmn
      return false if pkmn.respond_to?(:egg?) && pkmn.egg?
      if pkmn.respond_to?(:fainted?) && pkmn.fainted? && ($PokemonSystem.no_reviving rescue false)
        return false
      end
      return true if pkmn.hp.to_i < pkmn.totalhp.to_i
      return false if hp_only?
      return true if (pkmn.status rescue :NONE) != :NONE
      Array(pkmn.moves).any? do |move|
        move && move.total_pp.to_i > 0 && move.pp.to_i < move.total_pp.to_i
      end
    rescue
      false
    end

    def party_needs_healing?
      return false unless party_ready?
      $Trainer.party.any? { |pkmn| pokemon_needs_healing?(pkmn) }
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

    def deny(message, popup: nil, severity: :warning, toast_options: {})
      pbPlayBuzzerSE rescue nil
      if popup
        popup.call(message)
      else
        notify(severity, message, toast_options)
      end
      false
    end

    def use_from_menu(source = :repm, popup: nil)
      return deny(lock_reason, popup: popup) unless selectable?
      unless party_needs_healing?
        return deny(
          _INTL("Your party is already fully healed."),
          popup: popup,
          toast_options: { :compact => true }
        )
      end
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
      play_healing_sound
      message = _INTL("Your party was healed. Charges: {1}.", uses)
      popup ? popup.call(message) : notify(:success, message)
      true
    rescue Exception => e
      @healing_from_vial = false
      log_exception("PokeVial use failed", e)
      deny(_INTL("The PokeVial cannot be used right now."), popup: popup, severity: :error)
    end

    def use_from_overworld_menu(screen)
      if screen && screen.respond_to?(:show_popup_menu)
        choice = screen.show_popup_menu("POKEVIAL", ["Use PokeVial", "Back"])
        return false unless choice == 0
      elsif !pbConfirmMessage(_INTL("Use the PokeVial?"))
        return false
      end
      use_from_menu(:overworld_menu)
    end

    def heal_party
      return false unless party_ready?
      $Trainer.party.each do |pkmn|
        next unless pkmn
        hp_only? ? pkmn.heal_HP : pkmn.heal
      end
      true
    end

    def play_healing_sound
      if defined?(pbSEPlay)
        pbSEPlay("Recovery")
      elsif defined?(pbPlayDecisionSE)
        pbPlayDecisionSE
      end
      true
    rescue
      pbPlayDecisionSE rescue nil
      false
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
      mode = pokecenter_refill_mode
      return false if mode == :never
      current = uses
      max = configured_max_uses
      cost = pokecenter_refill_cost(needed)
      if mode == :ask
        prompt = _INTL("Refill PokeVial?\nCost: ${1}\nCharges: {2} -> {3}", cost.to_s_formatted, current, max)
        return false unless pbConfirmMessage(prompt)
      end
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
      unless run_callbacks(:before_refill, ctx)
        notify(:warning, ctx[:message] || _INTL("The PokeVial could not be refilled right now."))
        return false
      end
      money = ($Trainer.money rescue 0).to_i
      unless money >= cost
        notify(:warning, _INTL("You don't have enough money to refill PokeVial. Need ${1}.", cost.to_s_formatted))
        return false
      end
      $Trainer.money -= cost
      pbSEPlay("Mart buy item") rescue nil
      refill
      ctx[:uses_after] = uses
      ctx[:charges_after] = uses
      run_callbacks(:after_refill, ctx)
      log_info("PokeVial refilled at PokeCenter uses=#{uses}/#{configured_max_uses} cost=#{cost}")
      charge_label = needed == 1 ? _INTL("charge") : _INTL("charges")
      notify(:success, _INTL("Restored {1} {2} for ${3}.", needed, charge_label, cost.to_s_formatted))
      true
    rescue Exception => e
      log_exception("PokeVial PokeCenter refill failed", e)
      notify(:error, _INTL("The PokeVial could not be refilled right now."))
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
      register_reward_handlers
      install_trainer_heal_patch
      install_interpreter_recover_all_patch
    end

    def register_reward_handlers
      return false unless defined?(Reloaded::Rewards)
      return true if @reward_handlers_registered &&
                     Reloaded::Rewards.registered?(:pokevial_charge) &&
                     Reloaded::Rewards.registered?(:pokevial_refill) &&
                     Reloaded::Rewards.registered?(:pokevial_max_uses)

      charge = Reloaded::Rewards.register(
        :pokevial_charge,
        :owner => :poke_vial,
        :priority => 40,
        :aliases => [:pokevial, :poke_vial, :pokevial_uses, :poke_vial_uses],
        :normalize => proc { |reward|
          amount = reward[:uses] || reward[:pokevial_uses] || reward[:quantity] || reward[:qty] || reward[:amount] || 1
          reward.merge(:quantity => amount.to_i)
        },
        :validate => proc { |reward, context| validate_charge_reward(reward, context) },
        :grant => proc { |reward, context| grant_charge_reward(reward, context) },
        :rollback => proc { |receipt, _context| rollback_pokevial_reward(receipt) },
        :label => proc { |_reward| _INTL("PokeVial Charges") },
        :describe => proc { |reward| "pokevial_charge quantity=#{reward[:quantity].to_i}" },
        :message => proc { |reward, _result, _context|
          _INTL("\\me[Item get]You received {1} PokeVial charge(s)! Charges: {2}.\\wtnp[30]", reward[:quantity].to_i, uses)
        }
      )
      refill_reward = Reloaded::Rewards.register(
        :pokevial_refill,
        :owner => :poke_vial,
        :priority => 30,
        :aliases => [:poke_vial_refill, :refill_pokevial],
        :validate => proc { |reward, context| validate_refill_reward(reward, context) },
        :grant => proc { |reward, context| grant_refill_reward(reward, context) },
        :rollback => proc { |receipt, _context| rollback_pokevial_reward(receipt) },
        :expand => proc { |reward, multiplier| Array.new(multiplier) { reward.dup } },
        :label => proc { |_reward| _INTL("PokeVial Refill") },
        :describe => proc { |_reward| "pokevial_refill" },
        :message => proc { |_reward, _result, _context|
          _INTL("\\me[Item get]You received a PokeVial refill!\\wtnp[30]")
        }
      )
      max_reward = Reloaded::Rewards.register(
        :pokevial_max_uses,
        :owner => :poke_vial,
        :priority => 20,
        :aliases => [:pokevial_max, :pokevial_unlock, :poke_vial_unlock],
        :normalize => proc { |reward|
          amount = reward[:max_uses] || reward[:max] || reward[:amount] || reward[:quantity]
          reward.merge(:amount => amount.to_i, :quantity => 1)
        },
        :validate => proc { |reward, context| validate_max_uses_reward(reward, context) },
        :grant => proc { |reward, context| grant_max_uses_reward(reward, context) },
        :rollback => proc { |receipt, _context| rollback_pokevial_reward(receipt) },
        :expand => proc { |reward, _multiplier| [reward] },
        :label => proc { |_reward| _INTL("PokeVial Max Uses") },
        :describe => proc { |reward| "pokevial_max_uses max=#{reward[:amount].to_i}" },
        :message => proc { |_reward, _result, _context|
          _INTL("\\me[Item get]PokeVial max charges increased to {1}!\\wtnp[30]", configured_max_uses)
        }
      )
      @reward_handlers_registered = !!(charge && refill_reward && max_reward)
    rescue Exception => e
      log_exception("PokeVial reward registration failed", e)
      false
    end

    def validate_charge_reward(reward, context)
      return Reloaded::Rewards.failure(:pokevial_unavailable, "The PokeVial is unavailable.", :reward => reward) unless enabled?
      amount = reward[:quantity].to_i
      state = pokevial_reward_plan(context)
      unless amount > 0 && state[:uses] + amount <= state[:max]
        return Reloaded::Rewards.failure(:pokevial_full, "The PokeVial does not have enough empty charge slots.", :reward => reward)
      end
      state[:uses] += amount
      Reloaded::Rewards.success(:reward => reward)
    end

    def validate_refill_reward(reward, context)
      return Reloaded::Rewards.failure(:pokevial_unavailable, "The PokeVial is unavailable.", :reward => reward) unless enabled?
      state = pokevial_reward_plan(context)
      return Reloaded::Rewards.failure(:pokevial_full, "The PokeVial is already full.", :reward => reward) unless state[:uses] < state[:max]
      state[:uses] = state[:max]
      Reloaded::Rewards.success(:reward => reward)
    end

    def validate_max_uses_reward(reward, context)
      return Reloaded::Rewards.failure(:pokevial_unavailable, "The PokeVial is unavailable.", :reward => reward) unless enabled?
      state = pokevial_reward_plan(context)
      target = reward[:amount].to_i
      return Reloaded::Rewards.failure(:pokevial_maxed, "The PokeVial is already upgraded enough.", :reward => reward) unless target > state[:max]
      state[:max] = [target, MAX_USES_CAP].min
      state[:uses] = state[:max] if reward[:refill] == true || reward[:refill].to_s.downcase == "true"
      Reloaded::Rewards.success(:reward => reward)
    end

    def grant_charge_reward(reward, context)
      before = pokevial_reward_snapshot
      added = add_uses(reward[:quantity].to_i, :source => context[:source], :notify => false)
      return Reloaded::Rewards.failure(:pokevial_grant_failed, "The PokeVial charge could not be granted.", :reward => reward) unless added == reward[:quantity].to_i
      Reloaded::Rewards.success(:reward => reward, :details => { :receipt_data => before })
    end

    def grant_refill_reward(reward, context)
      before = pokevial_reward_snapshot
      return Reloaded::Rewards.failure(:pokevial_grant_failed, "The PokeVial refill could not be granted.", :reward => reward) unless grant_full_refill(:source => context[:source], :notify => false)
      Reloaded::Rewards.success(:reward => reward, :details => { :receipt_data => before })
    end

    def grant_max_uses_reward(reward, context)
      before = pokevial_reward_snapshot
      refill_after = reward[:refill] == true || reward[:refill].to_s.downcase == "true"
      unless unlock_max_uses(reward[:amount].to_i, :source => context[:source], :refill => refill_after, :notify => false)
        return Reloaded::Rewards.failure(:pokevial_grant_failed, "The PokeVial upgrade could not be granted.", :reward => reward)
      end
      Reloaded::Rewards.success(:reward => reward, :details => { :receipt_data => before })
    end

    def pokevial_reward_plan(context)
      plan = context[:reward_plan]
      return { :uses => uses, :max => configured_max_uses } unless plan.is_a?(Hash)
      plan[:pokevial] ||= { :uses => uses, :max => configured_max_uses }
    end

    def pokevial_reward_snapshot
      {
        :uses => uses,
        :unlocked_max_uses => state_get(:unlocked_max_uses, nil)
      }
    end

    def rollback_pokevial_reward(receipt)
      snapshot = receipt.data || {}
      state_set(:unlocked_max_uses, snapshot[:unlocked_max_uses])
      set_uses(snapshot[:uses].to_i)
      true
    rescue Exception => e
      log_exception("PokeVial reward rollback failed", e)
      false
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
          source: "Reloaded/Modules/PokeVial.rb",
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
        notify(:warning, _INTL("The PokeVial has no empty charge slots."))
        return 0
      end
      added = add_uses(1, source: :item, notify: false)
      return 0 if added <= 0
      notify(:success, _INTL("The PokeVial regained 1 charge. Charges: {1}.", uses))
      3
    rescue Exception => e
      log_exception("PokeVial Charge item failed", e)
      notify(:error, _INTL("The PokeVial Charge could not be used right now."))
      0
    end

    def use_refill_item
      unless can_refill?
        notify(:warning, _INTL("The PokeVial is already full."))
        return 0
      end
      return 0 unless grant_full_refill(source: :item, notify: false)
      notify(:success, _INTL("The PokeVial was fully refilled. Charges: {1}.", uses))
      3
    rescue Exception => e
      log_exception("PokeVial Refill item failed", e)
      notify(:error, _INTL("The PokeVial Refill could not be used right now."))
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
        ConditionalEnumOption.new(
          _INTL("Progressive Uses"),
          [_INTL("Off"), _INTL("On")],
          proc { ReloadedPokeVial.progressive_enabled? ? 1 : 0 },
          proc { |value|
            $PokemonSystem.hr_pokevial_progressive = value.to_i if $PokemonSystem
          },
          proc { ReloadedPokeVial.progressive_forced? },
          _INTL("Auto-scales max charges by badge count. Always On while playing on Hard."),
          disabled_label: _INTL("On")
        ),
        ConditionalSliderOption.new(
          _INTL("Max Uses"),
          1, 5, 1,
          proc { ReloadedPokeVial.configured_max_uses },
          proc { |value| ReloadedPokeVial.set_max_uses(value) },
          proc { ReloadedPokeVial.progressive_enabled? },
          _INTL("Maximum PokeVial charges between refills. Controlled by Progressive Uses while disabled."),
          disabled_label: proc { _INTL("Auto ({1})", ReloadedPokeVial.configured_max_uses) }
        )
      ]
      options.concat([
        EnumOption.new(
          _INTL("Heal Mode"),
          [_INTL("Full Heal"), _INTL("HP Only")],
          proc { ReloadedPokeVial.hp_only? ? 1 : 0 },
          proc { |value| $PokemonSystem.hr_pokevial_heal_mode = value.to_i if $PokemonSystem },
          _INTL("Full Heal restores HP, status, and PP. HP Only restores HP.")
        ),
        EnumOption.new(
          _INTL("PokeCenter Refill Mode"),
          [_INTL("Ask"), _INTL("Automatic"), _INTL("Never")],
          proc { ($PokemonSystem.hr_pokevial_refill_mode rescue REFILL_MODE_ASK).to_i },
          proc { |value| $PokemonSystem.hr_pokevial_refill_mode = value.to_i if $PokemonSystem },
          _INTL("Ask before refilling, refill automatically, or never refill after a PokeCenter heal.")
        ),
        ConditionalEnumOption.new(
          _INTL("Cooldown"),
          [_INTL("Off"), _INTL("On")],
          proc { ReloadedPokeVial.cooldown_enabled? ? 1 : 0 },
          proc { |value| $PokemonSystem.hr_pokevial_cooldown_enabled = value.to_i if $PokemonSystem },
          proc { ReloadedPokeVial.cooldown_forced? },
          _INTL("Controls whether the PokeVial must recharge between uses. Always On while playing on Hard."),
          disabled_label: _INTL("On")
        ),
        ConditionalEnumOption.new(
          _INTL("Cooldown Time (Real)"),
          cooldown_labels,
          proc {
            minutes = ReloadedPokeVial.cooldown_seconds / 60
            cooldown_values.index(minutes) || 0
          },
          proc { |index| $PokemonSystem.hr_pokevial_cooldown_seconds = cooldown_values[index.to_i] * 60 if $PokemonSystem },
          proc { !ReloadedPokeVial.cooldown_enabled? || ReloadedPokeVial.cooldown_forced? },
          _INTL("Recharge time between PokeVial uses. Fixed at 10 minutes while playing on Hard."),
          disabled_label: proc {
            ReloadedPokeVial.cooldown_forced? ? _INTL("10 min") : _INTL("Disabled")
          }
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
    if defined?(ReloadedPokeVial)
      ReloadedPokeVial.install_runtime_patches
      ReloadedPokeVial.update_overworld
    end
  }
end
