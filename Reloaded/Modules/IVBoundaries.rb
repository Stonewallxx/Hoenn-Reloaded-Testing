#======================================================
# Reloaded IV Boundaries
# Author: Stonewall
#======================================================
# Runtime IV floor/ceiling controls for newly generated Pokemon.
#
# Responsibilities:
#   - Let players tune IV boundaries for new wild/player-obtained Pokemon.
#   - Let difficulty config tune trainer Pokemon IV boundaries.
#   - Support gifts, static encounters, eggs, wild Pokemon, and trainer parties.
#   - Provide a modder API for applying/generating bounded IVs.
#
#======================================================

module ReloadedIVBoundaries
  IV_MIN = 0
  IV_MAX = Pokemon::IV_STAT_LIMIT rescue 31
  SAVE_SYSTEM = :iv_boundaries

  PLAYER_SCOPES = [:wild, :gift, :static, :egg, :player].freeze
  TRAINER_SCOPE = :trainer
  CALLBACK_EVENTS = [:before_apply, :after_apply].freeze

  # Config: player-facing preset rows.
  PLAYER_PRESETS = [
    { :id => :custom, :label => "Custom", :min => nil, :max => nil, :enabled => nil },
    { :id => :vanilla, :label => "Vanilla", :min => 0, :max => 31, :enabled => 0 },
    { :id => :accessibility, :label => "Accessibility", :min => 15, :max => 31, :enabled => 1 },
    { :id => :strong, :label => "Strong", :min => 20, :max => 31, :enabled => 1 },
    { :id => :perfectish, :label => "Perfect-ish", :min => 25, :max => 31, :enabled => 1 },
    { :id => :challenge, :label => "Challenge", :min => 0, :max => 15, :enabled => 1 }
  ].freeze

  # Config: difficulty-driven trainer rules. Players cannot edit trainer IV boundaries.
  TRAINER_DIFFICULTY_RULES = {
    :normal => { :min => 0, :max => 31 },
    :hard => { :min => 10, :max => 31 }
  }.freeze

  # Config: trainer class groups can be referenced by TRAINER_CLASS_EXEMPTIONS.
  TRAINER_CLASS_GROUPS = {
    :bosses => [:LEADER, :ELITEFOUR, :CHAMPION],
    :rivals => [:RIVAL1, :RIVAL2]
  }.freeze

  # Config: add trainer classes here if a difficulty should leave them untouched.
  # Example: { :all => [:group_bosses], :hard => [:LEADER] }
  TRAINER_CLASS_EXEMPTIONS = {}.freeze

  # Config: default temporary IV Boundary reward length, in real minutes.
  DEFAULT_TEMP_BOOST_MINUTES = 10

  # Config: maximum temporary IV Boundary reward length, in real minutes.
  MAX_TEMP_BOOST_MINUTES = 24 * 60

  class << self
    def player_enabled?
      ($PokemonSystem.hr_iv_boundaries_enabled rescue 0).to_i == 1
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

    def preset_selectable?(index)
      return true unless hard_difficulty?
      preset = PLAYER_PRESETS[index.to_i]
      return false unless preset
      return false if preset[:id] == :custom
      preset[:min].to_i <= IV_MIN
    rescue
      false
    end

    def show_hard_boundary_warning
      message = _INTL("Hard difficulty does not allow beneficial player IV minimums.")
      if defined?(Reloaded) && Reloaded.respond_to?(:toast_warning)
        Reloaded.toast_warning(message)
      elsif defined?(pbMessage)
        pbMessage(message)
      end
      false
    rescue
      false
    end

    def player_min
      return IV_MIN if hard_difficulty?
      value = $PokemonSystem.hr_iv_boundaries_min rescue IV_MIN
      clamp_iv(value)
    end

    def player_max
      value = $PokemonSystem.hr_iv_boundaries_max rescue IV_MAX
      clamp_iv(value)
    end

    def preset_labels
      PLAYER_PRESETS.map { |preset| _INTL(preset[:label]) }
    end

    def current_preset_index
      PLAYER_PRESETS.each_with_index do |preset, index|
        next if preset[:id] == :custom
        next unless preset[:min].to_i == player_min && preset[:max].to_i == player_max
        next unless preset[:enabled].nil? || preset[:enabled].to_i == (player_enabled? ? 1 : 0)
        return index
      end
      0
    rescue
      0
    end

    def apply_preset(index)
      preset = PLAYER_PRESETS[index.to_i] || PLAYER_PRESETS[0]
      return true if preset[:id] == :custom
      if hard_difficulty? && preset[:min].to_i > IV_MIN
        show_hard_boundary_warning
        return false
      end
      old_enabled = player_enabled? ? 1 : 0
      old_min = player_min
      old_max = player_max
      if $PokemonSystem
        $PokemonSystem.hr_iv_boundaries_enabled = preset[:enabled].to_i unless preset[:enabled].nil?
        $PokemonSystem.hr_iv_boundaries_min = clamp_iv(preset[:min])
        $PokemonSystem.hr_iv_boundaries_max = clamp_iv(preset[:max])
      end
      changed = old_enabled != (player_enabled? ? 1 : 0) || old_min != player_min || old_max != player_max
      log_info("IV Boundaries preset applied #{preset[:id]} min=#{preset[:min]} max=#{preset[:max]}") if changed
      true
    rescue Exception => e
      log_exception("IV Boundaries preset failed", e)
      false
    end

    def set_player_enabled(value)
      old_value = player_enabled? ? 1 : 0
      enabled = value.to_i == 1 ? 1 : 0
      $PokemonSystem.hr_iv_boundaries_enabled = enabled if $PokemonSystem
      log_info("IV Boundaries player setting #{enabled == 1 ? 'enabled' : 'disabled'}") if old_value != enabled
      true
    rescue Exception => e
      log_exception("IV Boundaries enabled setting failed", e)
      false
    end

    def set_player_min(value)
      old_min = player_min
      old_max = player_max
      requested = clamp_iv(value)
      if hard_difficulty? && requested > IV_MIN
        show_hard_boundary_warning
        requested = IV_MIN
      end
      min_value = requested
      max_value = [player_max, min_value].max
      if $PokemonSystem
        $PokemonSystem.hr_iv_boundaries_min = min_value
        $PokemonSystem.hr_iv_boundaries_max = max_value
      end
      log_info("IV Boundaries player minimum set to #{min_value}") if old_min != player_min || old_max != player_max
      true
    rescue Exception => e
      log_exception("IV Boundaries minimum setting failed", e)
      false
    end

    def set_player_max(value)
      old_min = player_min
      old_max = player_max
      max_value = clamp_iv(value)
      min_value = [player_min, max_value].min
      if $PokemonSystem
        $PokemonSystem.hr_iv_boundaries_min = min_value
        $PokemonSystem.hr_iv_boundaries_max = max_value
      end
      log_info("IV Boundaries player maximum set to #{max_value}") if old_min != player_min || old_max != player_max
      true
    rescue Exception => e
      log_exception("IV Boundaries maximum setting failed", e)
      false
    end

    def data
      return Reloaded::SaveData.system(SAVE_SYSTEM) if defined?(Reloaded::SaveData)
      @fallback_data ||= {}
    rescue
      @fallback_data ||= {}
    end

    def get_data(key, default = nil)
      if defined?(Reloaded::SaveData)
        Reloaded::SaveData.get(SAVE_SYSTEM, key, default, section: :systems)
      else
        data.key?(key) ? data[key] : default
      end
    rescue
      default
    end

    def set_data(key, value)
      if defined?(Reloaded::SaveData)
        Reloaded::SaveData.set(SAVE_SYSTEM, key, value, section: :systems)
      else
        data[key] = value
        true
      end
    rescue
      false
    end

    def now
      Time.now.to_i
    rescue
      0
    end

    def temporary_boosts
      prune_temporary_boosts
      Array(get_data(:temporary_boosts, []))
    rescue
      []
    end

    def grant_temporary_boost(scope = :wild, rule = {}, source: :script, duration_seconds: nil, duration_minutes: nil, notify: true)
      scope_key = normalize_scope(scope || rule[:scope] || rule["scope"])
      source_rule = rule.is_a?(Hash) ? rule : {}
      seconds = normalize_duration_seconds(duration_seconds, duration_minutes)
      boost = {
        "scope" => scope_key.to_s,
        "min" => source_rule[:min] || source_rule["min"] || source_rule[:floor] || source_rule["floor"],
        "max" => source_rule[:max] || source_rule["max"] || source_rule[:ceiling] || source_rule["ceiling"],
        "floor_bonus" => source_rule[:floor_bonus] || source_rule["floor_bonus"] || source_rule[:min_bonus] || source_rule["min_bonus"],
        "ceiling_bonus" => source_rule[:ceiling_bonus] || source_rule["ceiling_bonus"] || source_rule[:max_bonus] || source_rule["max_bonus"],
        "perfect_ivs" => source_rule[:perfect_ivs] || source_rule["perfect_ivs"] || source_rule[:perfect] || source_rule["perfect"],
        "source" => source.to_s,
        "created_at" => now,
        "expires_at" => now + seconds
      }
      boosts = temporary_boosts
      boosts << boost
      boosts = boosts.last(MAX_QUEUED_RULES)
      set_data(:temporary_boosts, boosts)
      log_info("IV Boundaries temporary boost granted scope=#{scope_key} source=#{source} seconds=#{seconds}")
      pbMessage(_INTL("IV Boundary boost activated.")) if notify
      true
    rescue Exception => e
      log_exception("IV Boundaries temporary boost failed", e)
      false
    end

    alias grant_boost grant_temporary_boost

    def force_next(scope = :gift, rule = {}, source: :script, count: 1, notify: false)
      scope_key = normalize_scope(scope || rule[:scope] || rule["scope"])
      rule_hash = normalize_rule(rule)
      entries = forced_rules
      [count.to_i, 1].max.times do
        entries << {
          "scope" => scope_key.to_s,
          "min" => rule_hash[:min],
          "max" => rule_hash[:max],
          "perfect_ivs" => rule_hash[:perfect_ivs],
          "source" => source.to_s,
          "created_at" => now
        }
      end
      entries = entries.last(MAX_QUEUED_RULES)
      set_data(:forced_rules, entries)
      log_info("IV Boundaries force-next queued scope=#{scope_key} source=#{source} count=#{count.to_i}")
      pbMessage(_INTL("The next Pokemon will use special IV boundaries.")) if notify
      true
    rescue Exception => e
      log_exception("IV Boundaries force-next failed", e)
      false
    end

    def exempt_next(scope = :gift, count: 1, source: :script)
      scope_key = normalize_scope(scope)
      entries = exempt_rules
      [count.to_i, 1].max.times do
        entries << { "scope" => scope_key.to_s, "source" => source.to_s, "created_at" => now }
      end
      entries = entries.last(MAX_QUEUED_RULES)
      set_data(:exempt_rules, entries)
      log_info("IV Boundaries exemption queued scope=#{scope_key} source=#{source} count=#{count.to_i}")
      true
    rescue Exception => e
      log_exception("IV Boundaries exemption queue failed", e)
      false
    end

    def forced_rules
      Array(get_data(:forced_rules, []))
    rescue
      []
    end

    def exempt_rules
      Array(get_data(:exempt_rules, []))
    rescue
      []
    end

    def preview(scope = :wild, sample = nil)
      scope_key = normalize_scope(scope)
      before = sample.is_a?(Hash) ? sample : random_iv_hash
      after = preview_ivs(before, scope_key)
      { :scope => scope_key, :before => before, :after => after, :bounds => bounds_for(scope_key) }
    rescue Exception => e
      log_exception("IV Boundaries preview failed", e)
      { :scope => normalize_scope(scope), :before => {}, :after => {}, :bounds => nil }
    end

    def enabled?(scope = :wild, options = {})
      scope_key = normalize_scope(scope)
      return player_enabled? if PLAYER_SCOPES.include?(scope_key)
      return !!bounds_for(TRAINER_SCOPE, options) if scope_key == TRAINER_SCOPE
      false
    end

    def bounds_for(scope = :wild, options = {})
      scope_key = normalize_scope(scope)
      if PLAYER_SCOPES.include?(scope_key)
        boosts = temporary_boosts_for(scope_key)
        return nil unless player_enabled? || !boosts.empty?
        return player_bounds(scope_key, options, boosts)
      end
      return trainer_bounds(options) if scope_key == TRAINER_SCOPE
      nil
    rescue Exception => e
      log_exception("IV Boundaries bounds lookup failed", e)
      nil
    end

    def apply_to(pokemon, scope = :wild, options = {})
      return false unless pokemon && pokemon.respond_to?(:iv)
      scope_key = normalize_scope(scope)
      return true if pokemon_exempt?(pokemon)
      return true if consume_exempt_rule(scope_key)
      rule = consume_forced_rule(scope_key) || application_rule_for(scope_key, options)
      return true unless rule
      bounds = normalize_bounds(rule)
      context = {
        :pokemon => pokemon,
        :scope => scope_key,
        :source => options[:source],
        :trainer_type => normalize_symbol(options[:trainer_type]),
        :difficulty => options[:difficulty] || current_difficulty_key,
        :bounds => bounds,
        :rule => rule,
        :ivs_before => copy_ivs(pokemon)
      }
      return false if run_callbacks(:before_apply, context) == false
      changed = roll_pokemon_ivs_within_bounds(pokemon, bounds, rule, scope_key)
      changed = apply_perfect_ivs(pokemon, rule[:perfect_ivs]) || changed
      pokemon.calc_stats if changed && pokemon.respond_to?(:calc_stats)
      context[:changed] = changed
      context[:ivs_after] = copy_ivs(pokemon)
      run_callbacks(:after_apply, context)
      true
    rescue Exception => e
      log_exception("IV Boundaries apply failed", e)
      false
    end

    def generate_iv(scope = :wild, options = {})
      rule = application_rule_for(normalize_scope(scope), options) || normalize_bounds(:min => IV_MIN, :max => IV_MAX)
      bounds = normalize_bounds(rule)
      rand(bounds[:min]..bounds[:max])
    rescue
      rand(IV_MAX + 1)
    end

    def generate_ivs(scope = :wild, options = {})
      result = {}
      GameData::Stat.each_main { |s| result[s.id] = generate_iv(scope, options) }
      rule = application_rule_for(normalize_scope(scope), options)
      if rule && rule[:perfect_ivs].to_i > 0
        stats = []
        GameData::Stat.each_main { |s| stats << s.id }
        stats.shuffle[0, rule[:perfect_ivs].to_i].each { |stat| result[stat] = IV_MAX }
      end
      result
    rescue Exception => e
      log_exception("IV Boundaries IV generation failed", e)
      {}
    end

    def with_creation_scope(scope, source = nil)
      @creation_scope_stack ||= []
      @creation_scope_stack.push({ :scope => normalize_scope(scope), :source => source })
      yield
    ensure
      @creation_scope_stack.pop if @creation_scope_stack && !@creation_scope_stack.empty?
    end

    def creation_context
      @creation_scope_stack ||= []
      @creation_scope_stack.last
    end

    def creation_scope
      context = creation_context
      context ? context[:scope] : nil
    end

    def on(event, id = nil, handler = nil, &block)
      register_callback(event, id, handler, &block)
    end

    def register_callback(event, id = nil, handler = nil, &block)
      event_key = normalize_symbol(event)
      return false unless CALLBACK_EVENTS.include?(event_key)
      callable = block || handler
      return false unless callable.respond_to?(:call)
      callback_id = id ? normalize_symbol(id) : callable.object_id
      @callbacks ||= {}
      @callbacks[event_key] ||= []
      @callbacks[event_key].reject! { |row| row[:id] == callback_id }
      @callbacks[event_key] << { :id => callback_id, :handler => callable }
      log_info("Registered IV Boundaries callback event=#{event_key} id=#{callback_id}")
      true
    rescue Exception => e
      log_exception("IV Boundaries callback registration failed", e)
      false
    end

    def unregister_callback(event, id)
      event_key = normalize_symbol(event)
      callback_id = normalize_symbol(id)
      return false unless event_key && callback_id
      @callbacks ||= {}
      return false unless @callbacks[event_key]
      before = @callbacks[event_key].length
      @callbacks[event_key].reject! { |row| row[:id] == callback_id }
      before != @callbacks[event_key].length
    rescue
      false
    end

    def run_callbacks(event, context = {})
      event_key = normalize_symbol(event)
      @callbacks ||= {}
      Array(@callbacks[event_key]).each do |row|
        result = row[:handler].call(context)
        return false if result == false
      end
      true
    rescue Exception => e
      log_exception("IV Boundaries callback failed event=#{event}", e)
      false
    end

    def open_options
      return unless defined?(ReloadedIVBoundaries::OptionsScene)
      pbFadeOutIn do
        scene = ReloadedIVBoundaries::OptionsScene.new
        screen = PokemonOptionScreen.new(scene)
        screen.pbStartScreen
      end
    rescue Exception => e
      log_exception("IV Boundaries options failed", e)
      pbMessage(_INTL("IV Boundaries options could not be opened.")) rescue nil
    end

    def install_runtime_patches
      install_pokemon_patches
      install_top_level_patches
      install_trainer_patch
      register_reward_handlers
      log_info("Installed IV Boundaries runtime patches")
      true
    rescue Exception => e
      log_exception("IV Boundaries runtime patch install failed", e)
      false
    end

    def register_reward_handlers
      return false unless defined?(Reloaded::Rewards)
      return true if @reward_handlers_registered &&
                     Reloaded::Rewards.registered?(:iv_boundary_boost) &&
                     Reloaded::Rewards.registered?(:iv_boundary_force_next)
      boost = Reloaded::Rewards.register(
        :iv_boundary_boost,
        :owner => :iv_boundaries,
        :priority => 100,
        :aliases => [:iv_boundary, :iv_boundaries, :iv_boost, :iv_floor_boost],
        :normalize => proc { |reward| normalize_reward_payload(reward, :boost) },
        :validate => proc { |reward, _context| validate_registered_reward(reward) },
        :grant => proc { |reward, context| grant_registered_reward(reward, context) },
        :rollback => proc { |receipt, _context| rollback_registered_reward(receipt) },
        :expand => proc { |reward, multiplier| Array.new(multiplier) { reward.dup } },
        :label => proc { |_reward| _INTL("IV Boundary Boost") },
        :describe => proc { |reward| "iv_boundary_boost scope=#{reward[:scope]} seconds=#{reward[:duration_seconds]}" },
        :message => proc { |_reward, _result, _context| _INTL("\\me[Item get]IV Boundary reward activated!\\wtnp[30]") }
      )
      force_next_reward = Reloaded::Rewards.register(
        :iv_boundary_force_next,
        :owner => :iv_boundaries,
        :priority => 100,
        :aliases => [:iv_force_next, :iv_next],
        :normalize => proc { |reward| normalize_reward_payload(reward, :force_next) },
        :validate => proc { |reward, _context| validate_registered_reward(reward) },
        :grant => proc { |reward, context| grant_registered_reward(reward, context) },
        :rollback => proc { |receipt, _context| rollback_registered_reward(receipt) },
        :expand => proc { |reward, multiplier|
          [reward.merge(:count => reward[:count].to_i * multiplier.to_i, :quantity => 1)]
        },
        :label => proc { |_reward| _INTL("IV Boundary Next Pokemon") },
        :describe => proc { |reward| "iv_boundary_force_next scope=#{reward[:scope]} count=#{reward[:count]}" },
        :message => proc { |_reward, _result, _context| _INTL("\\me[Item get]IV Boundary reward activated!\\wtnp[30]") }
      )
      @reward_handlers_registered = !!(boost && force_next_reward)
    rescue Exception => e
      log_exception("IV Boundaries reward registration failed", e)
      false
    end

    def normalize_reward_payload(reward, kind)
      normalized = mart_special_grant(reward)
      normalized[:type] = kind == :force_next ? :iv_boundary_force_next : :iv_boundary_boost
      normalized[:quantity] = 1
      normalized
    end

    def validate_registered_reward(reward)
      scope = normalize_scope(reward[:scope])
      valid_scopes = PLAYER_SCOPES + [TRAINER_SCOPE]
      return Reloaded::Rewards.failure(:invalid_iv_scope, "That IV Boundary reward has an invalid scope.", :reward => reward) unless valid_scopes.include?(scope)
      Reloaded::Rewards.success(:reward => reward)
    end

    def grant_registered_reward(reward, context)
      snapshot = {
        :temporary_boosts => copy_reward_rows(get_data(:temporary_boosts, [])),
        :forced_rules => copy_reward_rows(get_data(:forced_rules, []))
      }
      ok = apply_reward(reward, :source => context[:source], :notify => false)
      return Reloaded::Rewards.failure(:iv_reward_failed, "The IV Boundary reward could not be granted.", :reward => reward) unless ok
      Reloaded::Rewards.success(:reward => reward, :details => { :receipt_data => snapshot })
    end

    def rollback_registered_reward(receipt)
      snapshot = receipt.data || {}
      set_data(:temporary_boosts, copy_reward_rows(snapshot[:temporary_boosts]))
      set_data(:forced_rules, copy_reward_rows(snapshot[:forced_rules]))
      true
    rescue Exception => e
      log_exception("IV Boundaries reward rollback failed", e)
      false
    end

    def copy_reward_rows(rows)
      Array(rows).map { |row| row.is_a?(Hash) ? row.dup : row }
    end

    def normalize_scope(scope)
      value = normalize_symbol(scope)
      return :wild if value.nil?
      return :gift if value == :new || value == :new_pokemon
      value
    rescue
      :wild
    end

    def normalize_symbol(value)
      return nil if value.nil?
      value.to_sym
    rescue
      nil
    end

    def iv_reward?(payload)
      return false unless payload.is_a?(Hash)
      marker = payload[:type] || payload["type"] || payload[:kind] || payload["kind"] || payload[:grant_type] || payload["grant_type"]
      marker ||= payload[:id] || payload["id"] || payload[:item] || payload["item"] || payload[:item_id] || payload["item_id"]
      IV_REWARD_MARKERS.include?(marker.to_s)
    rescue
      false
    end

    def iv_reward_kind(payload)
      marker = payload[:type] || payload["type"] || payload[:kind] || payload["kind"] || payload[:grant_type] || payload["grant_type"]
      marker ||= payload[:id] || payload["id"] || payload[:item] || payload["item"] || payload[:item_id] || payload["item_id"]
      text = marker.to_s
      return :force_next if ["iv_boundary_force_next", "iv_force_next", "iv_next"].include?(text)
      :boost
    rescue
      :boost
    end

    def reward_scope(payload, fallback = :wild)
      normalize_scope(payload[:scope] || payload["scope"] || fallback)
    rescue
      normalize_scope(fallback)
    end

    def reward_rule(payload)
      {
        :min => payload[:min] || payload["min"] || payload[:floor] || payload["floor"],
        :max => payload[:max] || payload["max"] || payload[:ceiling] || payload["ceiling"],
        :floor_bonus => payload[:floor_bonus] || payload["floor_bonus"] || payload[:min_bonus] || payload["min_bonus"],
        :ceiling_bonus => payload[:ceiling_bonus] || payload["ceiling_bonus"] || payload[:max_bonus] || payload["max_bonus"],
        :perfect_ivs => payload[:perfect_ivs] || payload["perfect_ivs"] || payload[:perfect] || payload["perfect"]
      }
    rescue
      {}
    end

    def reward_duration(payload)
      value = payload[:duration_seconds] || payload["duration_seconds"] || payload[:seconds] || payload["seconds"]
      minutes = payload[:duration_minutes] || payload["duration_minutes"] || payload[:minutes] || payload["minutes"]
      normalize_duration_seconds(value, minutes)
    rescue
      default_temp_boost_seconds
    end

    def reward_count(payload)
      value = payload[:count] || payload["count"] || payload[:quantity] || payload["quantity"] || payload[:qty] || payload["qty"] || 1
      [value.to_i, 1].max
    rescue
      1
    end

    def apply_reward(payload, source: :script, notify: false)
      return false unless payload.is_a?(Hash)
      scope = reward_scope(payload)
      rule = reward_rule(payload)
      if iv_reward_kind(payload) == :force_next
        force_next(scope, rule, source: source, count: reward_count(payload), notify: notify)
      else
        grant_temporary_boost(scope, rule, source: source, duration_seconds: reward_duration(payload), notify: notify)
      end
    rescue Exception => e
      log_exception("IV Boundaries reward failed", e)
      false
    end

    def clamp_iv(value)
      [[value.to_i, IV_MIN].max, IV_MAX].min
    rescue
      IV_MIN
    end

    def default_temp_boost_seconds
      [DEFAULT_TEMP_BOOST_MINUTES.to_i, 1].max * 60
    rescue
      10 * 60
    end

    def max_temp_boost_seconds
      [MAX_TEMP_BOOST_MINUTES.to_i, 1].max * 60
    rescue
      24 * 60 * 60
    end

    def normalize_duration_seconds(seconds = nil, minutes = nil)
      value = seconds.to_i if !seconds.nil? && seconds.to_i > 0
      value ||= minutes.to_i * 60 if !minutes.nil? && minutes.to_i > 0
      value ||= default_temp_boost_seconds
      [[value.to_i, 1].max, max_temp_boost_seconds].min
    rescue
      default_temp_boost_seconds
    end

    def normalize_bounds(rule)
      min_value = clamp_iv(rule[:min] || rule["min"] || IV_MIN)
      max_value = clamp_iv(rule[:max] || rule["max"] || IV_MAX)
      min_value, max_value = max_value, min_value if min_value > max_value
      { :min => min_value, :max => max_value }
    end

    def normalize_rule(rule)
      source = rule.is_a?(Hash) ? rule : {}
      normalized = normalize_bounds(source)
      normalized[:floor_bonus] = source[:floor_bonus] || source["floor_bonus"] || source[:min_bonus] || source["min_bonus"]
      normalized[:ceiling_bonus] = source[:ceiling_bonus] || source["ceiling_bonus"] || source[:max_bonus] || source["max_bonus"]
      perfect_value = source[:perfect_ivs] || source["perfect_ivs"] || source[:perfect] || source["perfect"] || 0
      normalized[:perfect_ivs] = [perfect_value.to_i, 0].max
      normalized
    rescue
      normalize_bounds(:min => IV_MIN, :max => IV_MAX)
    end

    def player_bounds(scope = :wild, _options = {}, boosts = nil)
      rule = player_enabled? ? normalize_bounds(:min => player_min, :max => player_max) : normalize_bounds(:min => IV_MIN, :max => IV_MAX)
      Array(boosts || temporary_boosts_for(scope)).each { |boost| rule = merge_boost_rule(rule, boost) }
      rule
    end

    def application_rule_for(scope, options = {})
      scope_key = normalize_scope(scope)
      if PLAYER_SCOPES.include?(scope_key)
        boosts = temporary_boosts_for(scope_key)
        return player_bounds(scope_key, options, boosts) if player_enabled? || !boosts.empty?
      end
      return trainer_bounds(options) if scope_key == TRAINER_SCOPE
      nil
    end

    def merge_boost_rule(base_rule, boost)
      merged = normalize_bounds(base_rule)
      min_value = boost["min"] || boost[:min]
      max_value = boost["max"] || boost[:max]
      floor_bonus = boost["floor_bonus"] || boost[:floor_bonus]
      ceiling_bonus = boost["ceiling_bonus"] || boost[:ceiling_bonus]
      merged[:min] = clamp_iv(min_value) unless min_value.nil?
      merged[:max] = clamp_iv(max_value) unless max_value.nil?
      merged[:min] = clamp_iv(merged[:min] + floor_bonus.to_i) unless floor_bonus.nil?
      merged[:max] = clamp_iv(merged[:max] + ceiling_bonus.to_i) unless ceiling_bonus.nil?
      merged = normalize_bounds(merged)
      perfect = boost["perfect_ivs"] || boost[:perfect_ivs]
      merged[:perfect_ivs] = [perfect.to_i, 0].max if perfect
      merged
    end

    def temporary_boosts_for(scope)
      scope_key = normalize_scope(scope)
      temporary_boosts.select do |boost|
        boost_scope = normalize_scope(boost["scope"] || boost[:scope])
        boost_scope == scope_key || boost_scope == :player || (boost_scope == :wild && scope_key == :static)
      end
    rescue
      []
    end

    def prune_temporary_boosts
      boosts = Array(get_data(:temporary_boosts, []))
      kept = boosts.select do |boost|
        expires_at = (boost["expires_at"] || boost[:expires_at]).to_i
        expires_at <= 0 || expires_at > now
      end
      set_data(:temporary_boosts, kept) if kept.length != boosts.length
      kept
    rescue
      []
    end

    def consume_forced_rule(scope)
      scope_key = normalize_scope(scope)
      entries = forced_rules
      index = entries.index do |entry|
        entry_scope = normalize_scope(entry["scope"] || entry[:scope])
        entry_scope == scope_key || entry_scope == :player || (entry_scope == :wild && scope_key == :static)
      end
      return nil if index.nil?
      entry = entries.delete_at(index)
      set_data(:forced_rules, entries)
      log_info("IV Boundaries force-next consumed scope=#{scope_key} source=#{entry["source"] || entry[:source]}")
      normalize_rule(entry)
    rescue Exception => e
      log_exception("IV Boundaries force-next consume failed", e)
      nil
    end

    def consume_exempt_rule(scope)
      scope_key = normalize_scope(scope)
      entries = exempt_rules
      index = entries.index do |entry|
        entry_scope = normalize_scope(entry["scope"] || entry[:scope])
        entry_scope == scope_key || entry_scope == :player || (entry_scope == :wild && scope_key == :static)
      end
      return false if index.nil?
      entry = entries.delete_at(index)
      set_data(:exempt_rules, entries)
      log_info("IV Boundaries exemption consumed scope=#{scope_key} source=#{entry["source"] || entry[:source]}")
      true
    rescue Exception => e
      log_exception("IV Boundaries exemption consume failed", e)
      false
    end

    def pokemon_exempt?(pokemon)
      return false unless pokemon
      return true if pokemon.respond_to?(:reloaded_iv_boundaries_exempt) && pokemon.reloaded_iv_boundaries_exempt
      value = pokemon.instance_variable_get(:@reloaded_iv_boundaries_exempt) rescue false
      !!value
    rescue
      false
    end

    def random_iv_hash
      result = {}
      GameData::Stat.each_main { |s| result[s.id] = rand(IV_MAX + 1) }
      result
    rescue
      {}
    end

    def preview_ivs(before, scope = :wild)
      rule = application_rule_for(scope) || normalize_bounds(:min => IV_MIN, :max => IV_MAX)
      bounds = normalize_bounds(rule)
      result = {}
      before.each do |stat, value|
        result[stat] = bounded_iv_value(value, bounds)
      end
      if rule[:perfect_ivs].to_i > 0
        result.keys.shuffle[0, rule[:perfect_ivs].to_i].each { |stat| result[stat] = IV_MAX }
      end
      result
    rescue
      before
    end

    def copy_ivs(pokemon)
      result = {}
      return result unless pokemon && pokemon.respond_to?(:iv)
      GameData::Stat.each_main { |s| result[s.id] = pokemon.iv[s.id].to_i }
      result
    rescue
      {}
    end

    def roll_pokemon_ivs_within_bounds(pokemon, bounds, rule = {}, scope = :wild)
      changed = false
      GameData::Stat.each_main do |s|
        before = pokemon.iv[s.id].to_i
        after = bounded_iv_value(before, bounds)
        next if before == after
        pokemon.iv[s.id] = after
        changed = true
      end
      changed
    end

    def bounded_iv_value(value, bounds)
      current = clamp_iv(value)
      min_value = clamp_iv(bounds[:min])
      max_value = clamp_iv(bounds[:max])
      min_value, max_value = max_value, min_value if min_value > max_value
      return current if current >= min_value && current <= max_value
      rand(min_value..max_value)
    rescue
      clamp_iv(value)
    end

    def apply_perfect_ivs(pokemon, count)
      amount = [[count.to_i, 0].max, 6].min
      return false if amount <= 0
      stats = []
      GameData::Stat.each_main { |s| stats << s.id }
      changed = false
      stats.shuffle[0, amount].each do |stat|
        next if pokemon.iv[stat].to_i >= IV_MAX
        pokemon.iv[stat] = IV_MAX
        changed = true
      end
      changed
    rescue
      false
    end

    def truthy?(value)
      return true if value == true
      return false if value == false || value.nil?
      text = value.to_s.downcase
      text == "true" || text == "on" || text == "yes" || text == "1"
    rescue
      false
    end

    def trainer_bounds(options = {})
      difficulty = options[:difficulty] || current_difficulty_key
      trainer_type = normalize_symbol(options[:trainer_type])
      return nil if trainer_class_exempt?(trainer_type, difficulty)
      normalize_bounds(trainer_class_rule(trainer_type, difficulty) || TRAINER_DIFFICULTY_RULES[difficulty] || TRAINER_DIFFICULTY_RULES[:normal])
    end

    def trainer_class_exempt?(trainer_type, difficulty = current_difficulty_key)
      return false unless trainer_type
      all = expand_trainer_class_selectors(TRAINER_CLASS_EXEMPTIONS[:all] || TRAINER_CLASS_EXEMPTIONS["all"])
      specific = expand_trainer_class_selectors(TRAINER_CLASS_EXEMPTIONS[difficulty] || TRAINER_CLASS_EXEMPTIONS[difficulty.to_s])
      (all + specific).include?(trainer_type)
    rescue
      false
    end

    def trainer_class_rule(trainer_type, difficulty = current_difficulty_key)
      return nil unless trainer_type
      rule = TRAINER_CLASS_OVERRIDES[trainer_type] || TRAINER_CLASS_OVERRIDES[trainer_type.to_s]
      rule ||= trainer_group_rule(trainer_type)
      return nil unless rule
      if rule.key?(:min) || rule.key?("min") || rule.key?(:max) || rule.key?("max")
        return rule
      end
      rule[difficulty] || rule[difficulty.to_s] || rule[:all] || rule["all"]
    rescue
      nil
    end

    def trainer_group_rule(trainer_type)
      TRAINER_CLASS_GROUPS.each do |group_id, members|
        next unless Array(members).map { |member| normalize_symbol(member) }.include?(trainer_type)
        key = "group_#{group_id}".to_sym
        return TRAINER_CLASS_OVERRIDES[key] || TRAINER_CLASS_OVERRIDES[key.to_s]
      end
      nil
    rescue
      nil
    end

    def expand_trainer_class_selectors(values)
      result = []
      Array(values).each do |value|
        key = normalize_symbol(value)
        if key && key.to_s.start_with?("group_")
          group_id = key.to_s.sub(/^group_/, "").to_sym
          result.concat(Array(TRAINER_CLASS_GROUPS[group_id]).map { |member| normalize_symbol(member) })
        else
          result << key
        end
      end
      result.compact.uniq
    rescue
      []
    end

    def current_difficulty_key
      return :hard if switch_enabled?(:SWITCH_GAME_DIFFICULTY_HARD)
      :normal
    rescue
      :normal
    end

    def switch_enabled?(constant_name)
      return false unless defined?($game_switches) && $game_switches
      return false unless Object.const_defined?(constant_name)
      switch_id = Object.const_get(constant_name)
      !!$game_switches[switch_id]
    rescue
      false
    end

    def log_info(message)
      Reloaded::Log.info(message, :modules) if defined?(Reloaded::Log)
    rescue
    end

    def log_exception(message, error)
      Reloaded::Log.exception(message, error, channel: :modules) if defined?(Reloaded::Log)
    rescue
    end

    def install_mart_patch
      return false unless defined?(ReloadedMart::BundleEntryHandler) && defined?(ReloadedMart::Inventory)
      log_info("IV Boundaries uses shared Reloaded reward handlers for Mart grants")
      true
    rescue Exception => e
      log_exception("IV Boundaries Mart patch failed", e)
      false
    end

    def install_mart_bundle_patch
      true
    end

    def install_mart_inventory_patch
      true
    end

    def mart_special_grant(grant)
      {
        :type => iv_reward_kind(grant) == :force_next ? :iv_boundary_force_next : :iv_boundary_boost,
        :scope => reward_scope(grant),
        :rule => reward_rule(grant),
        :duration_seconds => reward_duration(grant),
        :count => reward_count(grant)
      }
    rescue
      { :type => :iv_boundary_boost, :scope => :wild, :rule => {}, :duration_seconds => default_temp_boost_seconds, :count => 1 }
    end

    def apply_mart_special_grant(grant)
      type = grant[:type] || grant["type"]
      scope = reward_scope(grant, grant[:scope] || grant["scope"] || :wild)
      rule = grant[:rule] || grant["rule"] || {}
      if type == :iv_boundary_force_next || type.to_s == "iv_boundary_force_next"
        force_next(scope, rule, source: :reloaded_mart, count: grant[:count] || grant["count"] || 1, notify: false)
      else
        grant_temporary_boost(scope, rule, source: :reloaded_mart, duration_seconds: grant[:duration_seconds] || grant["duration_seconds"], notify: false)
      end
    rescue Exception => e
      log_exception("IV Boundaries Mart reward apply failed", e)
      false
    end

    def install_mystery_gift_patch
      return true if Object.private_method_defined?(:reloaded_iv_boundaries_original_pbReceiveMysteryGift) || Object.method_defined?(:reloaded_iv_boundaries_original_pbReceiveMysteryGift)
      return false unless Object.private_method_defined?(:pbReceiveMysteryGift) || Object.method_defined?(:pbReceiveMysteryGift)
      was_private = Object.private_method_defined?(:pbReceiveMysteryGift)
      Object.class_eval do
        alias_method :reloaded_iv_boundaries_original_pbReceiveMysteryGift, :pbReceiveMysteryGift
        def pbReceiveMysteryGift(id)
          handled = ReloadedIVBoundaries.receive_mystery_gift(id) if defined?(ReloadedIVBoundaries)
          return handled unless handled.nil?
          reloaded_iv_boundaries_original_pbReceiveMysteryGift(id)
        end
        private :pbReceiveMysteryGift if was_private
        private :reloaded_iv_boundaries_original_pbReceiveMysteryGift if was_private
      end
      log_info("Installed IV Boundaries Mystery Gift patch")
      true
    rescue Exception => e
      log_exception("IV Boundaries Mystery Gift patch failed", e)
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
      return nil unless iv_reward?(payload)
      return false unless apply_reward(payload, source: :mystery_gift, notify: false)
      $Trainer.mystery_gifts[index] = [id]
      pbMessage(_INTL("\\me[Item get]IV Boundary reward activated!\\wtnp[30]")) rescue nil
      log_info("IV Boundaries Mystery Gift claimed id=#{id} kind=#{iv_reward_kind(payload)} scope=#{reward_scope(payload)}")
      true
    rescue Exception => e
      log_exception("IV Boundaries Mystery Gift claim failed", e)
      false
    end

    def install_pokemon_patches
      return unless defined?(Pokemon)
      Pokemon.class_eval do
        attr_accessor :reloaded_iv_boundaries_exempt unless method_defined?(:reloaded_iv_boundaries_exempt)

        unless method_defined?(:reloaded_iv_boundaries_original_initialize)
          alias_method :reloaded_iv_boundaries_original_initialize, :initialize
          def initialize(*args, &block)
            reloaded_iv_boundaries_original_initialize(*args, &block)
            if defined?(ReloadedIVBoundaries)
              ctx = ReloadedIVBoundaries.creation_context
              ReloadedIVBoundaries.apply_to(self, ctx[:scope], :source => ctx[:source]) if ctx
            end
          end
        end

        unless method_defined?(:reloaded_iv_boundaries_original_iv_writer)
          alias_method :reloaded_iv_boundaries_original_iv_writer, :iv=
          def iv=(value)
            reloaded_iv_boundaries_original_iv_writer(value)
            if defined?(ReloadedIVBoundaries)
              ctx = ReloadedIVBoundaries.creation_context
              ReloadedIVBoundaries.apply_to(self, ctx[:scope], :source => ctx[:source]) if ctx
            end
          end
        end
      end
    end

    def install_top_level_patches
      Object.class_eval do
        if private_method_defined?(:pbGenerateWildPokemon) && !private_method_defined?(:reloaded_iv_boundaries_original_pbGenerateWildPokemon)
          alias_method :reloaded_iv_boundaries_original_pbGenerateWildPokemon, :pbGenerateWildPokemon
          def pbGenerateWildPokemon(*args, &block)
            pkmn = reloaded_iv_boundaries_original_pbGenerateWildPokemon(*args, &block)
            ReloadedIVBoundaries.apply_to(pkmn, :wild, :source => :pbGenerateWildPokemon) if defined?(ReloadedIVBoundaries)
            pkmn
          end
        end

        if private_method_defined?(:pbWildBattleSpecific) && !private_method_defined?(:reloaded_iv_boundaries_original_pbWildBattleSpecific)
          alias_method :reloaded_iv_boundaries_original_pbWildBattleSpecific, :pbWildBattleSpecific
          def pbWildBattleSpecific(pokemon, *args, &block)
            ReloadedIVBoundaries.apply_to(pokemon, :static, :source => :pbWildBattleSpecific) if defined?(ReloadedIVBoundaries)
            reloaded_iv_boundaries_original_pbWildBattleSpecific(pokemon, *args, &block)
          end
        end

        if private_method_defined?(:pbStorePokemon) && !private_method_defined?(:reloaded_iv_boundaries_original_pbStorePokemon)
          alias_method :reloaded_iv_boundaries_original_pbStorePokemon, :pbStorePokemon
          def pbStorePokemon(pkmn, *args, &block)
            ReloadedIVBoundaries.apply_to(pkmn, :gift, :source => :pbStorePokemon) if defined?(ReloadedIVBoundaries)
            reloaded_iv_boundaries_original_pbStorePokemon(pkmn, *args, &block)
          end
        end

        if private_method_defined?(:pbNicknameAndStore) && !private_method_defined?(:reloaded_iv_boundaries_original_pbNicknameAndStore)
          alias_method :reloaded_iv_boundaries_original_pbNicknameAndStore, :pbNicknameAndStore
          def pbNicknameAndStore(pkmn, *args, &block)
            ReloadedIVBoundaries.apply_to(pkmn, :gift, :source => :pbNicknameAndStore) if defined?(ReloadedIVBoundaries)
            reloaded_iv_boundaries_original_pbNicknameAndStore(pkmn, *args, &block)
          end
        end

        if private_method_defined?(:pbAddPokemon) && !private_method_defined?(:reloaded_iv_boundaries_original_pbAddPokemon)
          alias_method :reloaded_iv_boundaries_original_pbAddPokemon, :pbAddPokemon
          def pbAddPokemon(*args, &block)
            if defined?(ReloadedIVBoundaries)
              ReloadedIVBoundaries.with_creation_scope(:gift, :pbAddPokemon) { reloaded_iv_boundaries_original_pbAddPokemon(*args, &block) }
            else
              reloaded_iv_boundaries_original_pbAddPokemon(*args, &block)
            end
          end
        end

        if private_method_defined?(:pbAddPokemonSilent) && !private_method_defined?(:reloaded_iv_boundaries_original_pbAddPokemonSilent)
          alias_method :reloaded_iv_boundaries_original_pbAddPokemonSilent, :pbAddPokemonSilent
          def pbAddPokemonSilent(*args, &block)
            if defined?(ReloadedIVBoundaries)
              ReloadedIVBoundaries.with_creation_scope(:gift, :pbAddPokemonSilent) { reloaded_iv_boundaries_original_pbAddPokemonSilent(*args, &block) }
            else
              reloaded_iv_boundaries_original_pbAddPokemonSilent(*args, &block)
            end
          end
        end

        if private_method_defined?(:pbAddToParty) && !private_method_defined?(:reloaded_iv_boundaries_original_pbAddToParty)
          alias_method :reloaded_iv_boundaries_original_pbAddToParty, :pbAddToParty
          def pbAddToParty(*args, &block)
            if defined?(ReloadedIVBoundaries)
              ReloadedIVBoundaries.with_creation_scope(:gift, :pbAddToParty) { reloaded_iv_boundaries_original_pbAddToParty(*args, &block) }
            else
              reloaded_iv_boundaries_original_pbAddToParty(*args, &block)
            end
          end
        end

        if private_method_defined?(:pbAddToPartySilent) && !private_method_defined?(:reloaded_iv_boundaries_original_pbAddToPartySilent)
          alias_method :reloaded_iv_boundaries_original_pbAddToPartySilent, :pbAddToPartySilent
          def pbAddToPartySilent(*args, &block)
            if defined?(ReloadedIVBoundaries)
              ReloadedIVBoundaries.with_creation_scope(:gift, :pbAddToPartySilent) { reloaded_iv_boundaries_original_pbAddToPartySilent(*args, &block) }
            else
              reloaded_iv_boundaries_original_pbAddToPartySilent(*args, &block)
            end
          end
        end

        if private_method_defined?(:pbAddForeignPokemon) && !private_method_defined?(:reloaded_iv_boundaries_original_pbAddForeignPokemon)
          alias_method :reloaded_iv_boundaries_original_pbAddForeignPokemon, :pbAddForeignPokemon
          def pbAddForeignPokemon(*args, &block)
            if defined?(ReloadedIVBoundaries)
              ReloadedIVBoundaries.with_creation_scope(:gift, :pbAddForeignPokemon) { reloaded_iv_boundaries_original_pbAddForeignPokemon(*args, &block) }
            else
              reloaded_iv_boundaries_original_pbAddForeignPokemon(*args, &block)
            end
          end
        end

        if private_method_defined?(:pbGenerateEgg) && !private_method_defined?(:reloaded_iv_boundaries_original_pbGenerateEgg)
          alias_method :reloaded_iv_boundaries_original_pbGenerateEgg, :pbGenerateEgg
          def pbGenerateEgg(*args, &block)
            if defined?(ReloadedIVBoundaries)
              ReloadedIVBoundaries.with_creation_scope(:egg, :pbGenerateEgg) { reloaded_iv_boundaries_original_pbGenerateEgg(*args, &block) }
            else
              reloaded_iv_boundaries_original_pbGenerateEgg(*args, &block)
            end
          end
        end

        if private_method_defined?(:pbDayCareGenerateEgg) && !private_method_defined?(:reloaded_iv_boundaries_original_pbDayCareGenerateEgg)
          alias_method :reloaded_iv_boundaries_original_pbDayCareGenerateEgg, :pbDayCareGenerateEgg
          def pbDayCareGenerateEgg(*args, &block)
            if defined?(ReloadedIVBoundaries)
              ReloadedIVBoundaries.with_creation_scope(:egg, :pbDayCareGenerateEgg) { reloaded_iv_boundaries_original_pbDayCareGenerateEgg(*args, &block) }
            else
              reloaded_iv_boundaries_original_pbDayCareGenerateEgg(*args, &block)
            end
          end
        end

        [
          :pbGenerateWildPokemon,
          :pbWildBattleSpecific,
          :pbStorePokemon,
          :pbNicknameAndStore,
          :pbAddPokemon,
          :pbAddPokemonSilent,
          :pbAddToParty,
          :pbAddToPartySilent,
          :pbAddForeignPokemon,
          :pbGenerateEgg,
          :pbDayCareGenerateEgg
        ].each do |method_name|
          private method_name if method_defined?(method_name)
        end
      end
    end

    def install_trainer_patch
      return unless defined?(GameData::Trainer)
      GameData::Trainer.class_eval do
        unless method_defined?(:reloaded_iv_boundaries_original_to_trainer)
          alias_method :reloaded_iv_boundaries_original_to_trainer, :to_trainer
          def to_trainer(*args, &block)
            trainer = reloaded_iv_boundaries_original_to_trainer(*args, &block)
            if defined?(ReloadedIVBoundaries) && trainer && trainer.respond_to?(:party)
              trainer_type = trainer.trainer_type rescue nil
              trainer.party.each do |pkmn|
                ReloadedIVBoundaries.apply_to(pkmn, :trainer,
                  :source => :trainer_to_trainer,
                  :trainer_type => trainer_type
                )
              end
            end
            trainer
          end
        end
      end
    end
  end

  MAX_QUEUED_RULES = 25
  TRAINER_CLASS_OVERRIDES = {}.freeze
  IV_REWARD_MARKERS = [
    "iv_boundary",
    "iv_boundaries",
    "iv_boundary_boost",
    "iv_boost",
    "iv_floor_boost",
    "iv_boundary_force_next",
    "iv_force_next",
    "iv_next"
  ].freeze

  class LiveEnumOption < EnumOption
    def current_value
      value = get
      value ? value.to_i : 0
    end

    def next(_current)
      value = super(current_value)
      set(value)
      value
    end

    def prev(_current)
      value = super(current_value)
      set(value)
      value
    end
  end

  class LiveSliderOption < SliderOption
    def current_value
      value = get
      value ? value.to_i : @optstart.to_i
    end

    def next(_current)
      value = super(current_value)
      set(value)
      value
    end

    def prev(_current)
      value = super(current_value)
      set(value)
      value
    end
  end

  class HardPresetOption < LiveEnumOption
    def next(_current)
      return super(current_value) unless ReloadedIVBoundaries.hard_difficulty?
      move_to_allowed(1)
    end

    def prev(_current)
      return super(current_value) unless ReloadedIVBoundaries.hard_difficulty?
      move_to_allowed(-1)
    end

    def move_to_allowed(direction)
      value = current_value
      PLAYER_PRESETS.length.times do
        value = (value + direction) % PLAYER_PRESETS.length
        next unless ReloadedIVBoundaries.preset_selectable?(value)
        set(value)
        return value
      end
      current_value
    end
  end

  class HardLockedMinSliderOption < LiveSliderOption
    def disabled?
      ReloadedIVBoundaries.hard_difficulty?
    end

    def disabled_label
      _INTL("0")
    end

    def next(current)
      disabled? ? current : super
    end

    def prev(current)
      disabled? ? current : super
    end
  end

  class OptionsScene < PokemonOption_Scene
    def initUIElements
      super
      @sprites["title"].text = _INTL("IV Boundaries") rescue nil
    end

    def pbGetOptions(_inloadscreen = false)
      [
        HardPresetOption.new(
          _INTL("Preset"),
          ReloadedIVBoundaries.preset_labels,
          proc { ReloadedIVBoundaries.current_preset_index },
          proc { |value| ReloadedIVBoundaries.apply_preset(value) },
          _INTL("Applies a quick IV boundary preset.")
        ),
        LiveEnumOption.new(
          _INTL("IV Boundaries"),
          [_INTL("Off"), _INTL("On")],
          proc { ReloadedIVBoundaries.player_enabled? ? 1 : 0 },
          proc { |value| ReloadedIVBoundaries.set_player_enabled(value) },
          _INTL("Controls IV boundaries for new wild, gift, static, and Egg Pokemon.")
        ),
        HardLockedMinSliderOption.new(
          _INTL("Min IV"),
          IV_MIN, IV_MAX, 1,
          proc { ReloadedIVBoundaries.player_min },
          proc { |value| ReloadedIVBoundaries.set_player_min(value) },
          _INTL("Lowest IV allowed for new player-obtained Pokemon. Always 0 while playing on Hard.")
        ),
        LiveSliderOption.new(
          _INTL("Max IV"),
          IV_MIN, IV_MAX, 1,
          proc { ReloadedIVBoundaries.player_max },
          proc { |value| ReloadedIVBoundaries.set_player_max(value) },
          _INTL("Highest IV allowed for new player-obtained Pokemon.")
        ),
        ActionButton.new(
          _INTL("Preview"),
          proc { show_iv_boundary_preview },
          _INTL("Shows a sample before/after IV boundary preview.")
        )
      ]
    end

    def show_iv_boundary_preview
      sample = ReloadedIVBoundaries.preview(:wild)
      before = format_iv_hash(sample[:before])
      after = format_iv_hash(sample[:after])
      bounds = sample[:bounds]
      header = bounds ? _INTL("Current bounds: {1}-{2}", bounds[:min], bounds[:max]) : _INTL("Current bounds: Off")
      pbMessage(_INTL("{1}\nBefore: {2}\nAfter: {3}", header, before, after))
    rescue Exception => e
      ReloadedIVBoundaries.log_exception("IV Boundaries preview message failed", e) if defined?(ReloadedIVBoundaries)
      pbMessage(_INTL("IV Boundary preview is unavailable.")) rescue nil
    end

    def format_iv_hash(values)
      order = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]
      labels = {
        :HP => "HP",
        :ATTACK => "Atk",
        :DEFENSE => "Def",
        :SPECIAL_ATTACK => "SpA",
        :SPECIAL_DEFENSE => "SpD",
        :SPEED => "Spe"
      }
      order.map { |stat| "#{labels[stat]} #{values[stat].to_i}" }.join(", ")
    rescue
      ""
    end
  end
end

module Reloaded
  module IVBoundariesFeature
    class << self
      def install
        install_pokemon_system_settings
        register_option
        ReloadedIVBoundaries.install_runtime_patches if defined?(ReloadedIVBoundaries)
        Reloaded::Log.info("Installed IV Boundaries module", :modules) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("IV Boundaries install failed", e, channel: :modules) if defined?(Reloaded::Log)
        false
      end

      def install_pokemon_system_settings
        return unless defined?(PokemonSystem)
        PokemonSystem.class_eval do
          def hr_iv_boundaries_enabled
            @hr_iv_boundaries_enabled.nil? ? 0 : @hr_iv_boundaries_enabled.to_i
          end

          def hr_iv_boundaries_enabled=(value)
            @hr_iv_boundaries_enabled = value.to_i
          end

          def hr_iv_boundaries_min
            @hr_iv_boundaries_min.nil? ? ReloadedIVBoundaries::IV_MIN : @hr_iv_boundaries_min.to_i
          end

          def hr_iv_boundaries_min=(value)
            @hr_iv_boundaries_min = ReloadedIVBoundaries.clamp_iv(value)
          end

          def hr_iv_boundaries_max
            @hr_iv_boundaries_max.nil? ? ReloadedIVBoundaries::IV_MAX : @hr_iv_boundaries_max.to_i
          end

          def hr_iv_boundaries_max=(value)
            @hr_iv_boundaries_max = ReloadedIVBoundaries.clamp_iv(value)
          end
        end
      end

      def register_option
        return unless defined?(Reloaded::Options) && Reloaded::Options.respond_to?(:register_category_option)
        Reloaded::Options.register_category_option("CHALLENGE", :iv_boundaries_options, priority: 0) do |_scene|
          [ActionButton.new(
            _INTL("IV Boundaries"),
            proc { ReloadedIVBoundaries.open_options if defined?(ReloadedIVBoundaries) },
            _INTL("Open IV Boundaries options.")
          )]
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to register IV Boundaries option", e, channel: :options) if defined?(Reloaded::Log)
      end
    end
  end
end

Reloaded::IVBoundariesFeature.install if defined?(Reloaded::IVBoundariesFeature)
