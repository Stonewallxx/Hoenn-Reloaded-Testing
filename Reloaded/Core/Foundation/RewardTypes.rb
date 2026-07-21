#======================================================
# Reloaded Reward Types
# Author: Stonewall
#======================================================
# Built-in reward adapters beyond items and money.
#======================================================

module Reloaded
  module PokemonDistribution
    class << self
      def tradeable?(pokemon)
        return false unless pokemon
        return pokemon.reloaded_tradeable? if pokemon.respond_to?(:reloaded_tradeable?)
        !pokemon.instance_variable_get(:@reloaded_untradeable)
      rescue
        true
      end

      def trade_lock_reason(pokemon)
        text = pokemon.reloaded_trade_lock_reason.to_s if pokemon && pokemon.respond_to?(:reloaded_trade_lock_reason)
        text.to_s.empty? ? _INTL("This Pokemon cannot be traded.") : text
      rescue
        _INTL("This Pokemon cannot be traded.")
      end

      def reject_trade(pokemon, notify = true)
        return false if tradeable?(pokemon)
        message = trade_lock_reason(pokemon)
        if notify
          if defined?(Reloaded) && Reloaded.respond_to?(:toast_warning)
            Reloaded.toast_warning(message)
          elsif defined?(pbMessage)
            pbMessage(_INTL(message))
          end
        end
        true
      rescue
        false
      end
    end
  end

  module Rewards
    @currencies ||= {}

    class << self
      def install_extended_types
        register_default_currencies
        register_currency_reward unless registered?(:currency)
        register_pokemon_reward unless registered?(:pokemon)
        register_tm_vault_reward unless registered?(:tm_vault)
        register_outfit_reward unless registered?(:outfit)
        register_feature_unlock_reward unless registered?(:feature_unlock)
        register_group_reward unless registered?(:group)
        register_choice_reward unless registered?(:choice)
        register_random_reward unless registered?(:random)
        install_pokemon_typing_patch
        install_trade_restriction_patches
        install_evolution_restriction_patch
        true
      rescue Exception => e
        extended_log_exception("Extended reward installation failed", e)
        false
      end

      def register_currency(id, config = nil, override: false, **keywords)
        key = reward_type_id(id)
        raise ArgumentError, "Currency ID is empty." if key.to_s.empty?
        raise "Currency already registered: #{key}" if @currencies.key?(key) && !override
        source = config.is_a?(Hash) ? config.dup : {}
        source.merge!(keywords) unless keywords.empty?
        getter = source[:get] || source["get"] || source[:getter] || source["getter"]
        setter = source[:set] || source["set"] || source[:setter] || source["setter"]
        raise ArgumentError, "Currency #{key} requires getter and setter callables." unless getter.respond_to?(:call) && setter.respond_to?(:call)
        @currencies[key] = {
          :id => key,
          :name => (source[:name] || source["name"] || reward_titleize(key)).to_s,
          :owner => reward_type_id(source[:owner] || source["owner"] || :reloaded),
          :get => getter,
          :set => setter,
          :max => source[:max] || source["max"],
          :format => source[:format] || source["format"]
        }
        currency(key)
      rescue Exception => e
        extended_log_exception("Currency registration failed for #{id}", e)
        nil
      end

      def currency(id)
        entry = @currencies[normalize_currency_id(id)]
        return nil unless entry
        entry.each_with_object({}) do |(key, value), copy|
          copy[key] = value unless [:get, :set, :format].include?(key)
        end
      rescue
        nil
      end

      def currencies
        @currencies.keys.sort_by(&:to_s).map { |id| currency(id) }
      end

      def currency_balance(id)
        entry = @currencies[normalize_currency_id(id)]
        value = currency_value(entry)
        value.nil? ? nil : value.to_i
      rescue Exception => e
        extended_log_exception("Currency balance lookup failed for #{id}", e)
        nil
      end

      def currency_name(id)
        entry = @currencies[normalize_currency_id(id)]
        entry ? entry[:name].to_s : reward_titleize(normalize_currency_id(id))
      rescue
        reward_titleize(id)
      end

      def format_currency(id, amount)
        entry = @currencies[normalize_currency_id(id)]
        formatter = entry && entry[:format]
        return formatter.call(amount.to_i).to_s if formatter.respond_to?(:call)
        _INTL("{1} {2}", amount.to_i, currency_name(id))
      rescue
        "#{amount.to_i} #{currency_name(id)}"
      end

      def can_spend_currency?(id, amount)
        value = currency_balance(id)
        !value.nil? && amount.to_i >= 0 && value >= amount.to_i
      end

      def spend_currency(id, amount)
        key = normalize_currency_id(id)
        entry = @currencies[key]
        return failure(:unknown_currency, "That currency is unavailable.") unless entry
        cost = amount.to_i
        return failure(:invalid_amount, "That currency amount is invalid.") if cost < 0
        before = currency_value(entry)
        return failure(:currency_unavailable, "That currency is unavailable.") if before.nil?
        return failure(:not_enough_currency, _INTL("You don't have enough {1}.", entry[:name]), :details => { :currency => key, :needed => cost, :available => before }) if before < cost
        entry[:set].call(before - cost)
        after = currency_value(entry)
        return failure(:currency_write_failed, "The transaction could not be completed.") unless after == before - cost
        success(:details => { :currency => key, :before => before, :after => after, :amount => cost })
      rescue Exception => e
        extended_log_exception("Currency charge failed for #{id}", e)
        failure(:currency_write_failed, "The transaction could not be completed.")
      end

      def refund_currency(id, amount)
        key = normalize_currency_id(id)
        entry = @currencies[key]
        return failure(:unknown_currency, "That currency is unavailable.") unless entry
        value = amount.to_i
        return failure(:invalid_amount, "That currency amount is invalid.") if value < 0
        before = currency_value(entry)
        return failure(:currency_unavailable, "That currency is unavailable.") if before.nil?
        target = before + value
        maximum = currency_max(entry)
        return failure(:currency_full, _INTL("There isn't enough room for that {1} refund.", entry[:name])) if maximum && target > maximum
        entry[:set].call(target)
        after = currency_value(entry)
        return failure(:currency_write_failed, "The transaction could not be completed.") unless after == target
        success(:details => { :currency => key, :before => before, :after => after, :amount => value })
      rescue Exception => e
        extended_log_exception("Currency refund failed for #{id}", e)
        failure(:currency_write_failed, "The transaction could not be completed.")
      end

      private

      def register_default_currencies
        register_player_currency(:money, :name => _INTL("Money"), :attribute => :money, :max => proc { defined?(::Settings::MAX_MONEY) ? ::Settings::MAX_MONEY : nil })
        register_player_currency(:coins, :name => _INTL("Coins"), :attribute => :coins, :max => proc { defined?(::Settings::MAX_COINS) ? ::Settings::MAX_COINS : nil })
        register_player_currency(:battle_points, :name => _INTL("Battle Points"), :attribute => :battle_points, :max => proc { defined?(::Settings::MAX_BATTLE_POINTS) ? ::Settings::MAX_BATTLE_POINTS : nil })
        register_player_currency(:quest_points, :name => _INTL("Quest Points"), :attribute => :quest_points)
        register_player_currency(:cosmetics_money, :name => _INTL("Glimmer Coins"), :attribute => :cosmetics_money)
      end

      def register_player_currency(id, options = {})
        return if @currencies.key?(id)
        attribute = options[:attribute]
        register_currency(
          id,
          :name => options[:name],
          :owner => :reloaded,
          :max => options[:max],
          :getter => proc { defined?($Trainer) && $Trainer ? ($Trainer.send(attribute) || 0).to_i : nil },
          :setter => proc { |value| $Trainer.send("#{attribute}=", value.to_i) }
        )
      end

      def register_currency_reward
        register(
          :currency,
          :owner => :reloaded,
          :priority => 70,
          :normalize => proc { |reward| normalize_currency_reward(reward) },
          :validate => proc { |reward, context| validate_currency_reward(reward, context) },
          :grant => proc { |reward, context| grant_currency_reward(reward, context) },
          :rollback => proc { |receipt, _context| rollback_currency_reward(receipt) },
          :expand => proc { |reward, multiplier| [reward.merge(:amount => reward[:amount].to_i * multiplier.to_i, :quantity => reward[:amount].to_i * multiplier.to_i)] },
          :label => proc { |reward| currency_label(reward) },
          :describe => proc { |reward| "currency=#{reward[:currency]} amount=#{reward[:amount].to_i}" },
          :message => proc { |reward, _result, _context| _INTL("You received {1} {2}!", reward[:amount].to_i, currency_label(reward)) }
        )
      end

      def normalize_currency_reward(reward)
        key = normalize_currency_id(reward[:currency] || reward[:currency_id] || reward[:id])
        amount = (reward[:amount] || reward[:quantity] || 0).to_i
        reward.merge(:currency => key, :amount => amount, :quantity => amount)
      end

      def validate_currency_reward(reward, context)
        entry = @currencies[reward[:currency]]
        return failure(:unknown_currency, "That currency is unavailable.", :reward => reward) unless entry
        return failure(:invalid_amount, "That currency reward has an invalid amount.", :reward => reward) if reward[:amount].to_i <= 0
        current = currency_value(entry)
        return failure(:trainer_unavailable, "The player is unavailable.", :reward => reward) if current.nil?
        plan = context[:reward_plan]
        if plan.is_a?(Hash)
          totals = plan[:currency_values] ||= {}
          current = totals.fetch(reward[:currency], current)
          target = current + reward[:amount].to_i
          maximum = currency_max(entry)
          return failure(:currency_full, "That currency is already at its maximum.", :reward => reward) if maximum && target > maximum
          totals[reward[:currency]] = target
        end
        success(:reward => reward)
      rescue Exception => e
        extended_log_exception("Currency reward validation failed", e)
        failure(:currency_validation_failed, "That currency reward could not be validated.", :reward => reward)
      end

      def grant_currency_reward(reward, _context)
        entry = @currencies[reward[:currency]]
        before = currency_value(entry)
        entry[:set].call(before + reward[:amount].to_i)
        after = currency_value(entry)
        return failure(:currency_grant_failed, "That currency could not be granted.", :reward => reward) if after.nil? || after <= before
        success(:reward => reward, :details => { :receipt_data => { :currency => reward[:currency], :before => before } })
      end

      def rollback_currency_reward(receipt)
        data = receipt.data || {}
        entry = @currencies[data[:currency]]
        return false unless entry
        entry[:set].call(data[:before].to_i)
        true
      end

      def currency_label(reward)
        entry = @currencies[reward[:currency]]
        entry ? entry[:name] : reward_titleize(reward[:currency])
      end

      def currency_value(entry)
        value = entry && entry[:get].call
        value.nil? ? nil : value.to_i
      end

      def currency_max(entry)
        value = entry && entry[:max]
        value = value.call if value.respond_to?(:call)
        value.nil? ? nil : value.to_i
      end

      def normalize_currency_id(value)
        key = reward_type_id(value)
        aliases = {
          :bp => :battle_points,
          :battlepoints => :battle_points,
          :qp => :quest_points,
          :questpoints => :quest_points,
          :glimmer_coins => :cosmetics_money,
          :cosmetic_money => :cosmetics_money
        }
        aliases[key] || key
      end

      def register_pokemon_reward
        register(
          :pokemon,
          :owner => :reloaded,
          :priority => 80,
          :normalize => proc { |reward| normalize_pokemon_reward(reward) },
          :validate => proc { |reward, context| validate_pokemon_reward(reward, context) },
          :grant => proc { |reward, context| grant_pokemon_reward(reward, context) },
          :rollback => proc { |receipt, _context| rollback_pokemon_reward(receipt) },
          :finalize => proc { |receipt, _context| finalize_pokemon_reward(receipt) },
          :label => proc { |reward| pokemon_reward_label(reward) },
          :describe => proc { |reward| "pokemon=#{reward[:species]} level=#{reward[:level]} quantity=#{reward[:quantity]} delivery=#{reward[:delivery]}" },
          :message => proc { |reward, _result, _context| pokemon_reward_message(reward) }
        )
      end

      def normalize_pokemon_reward(reward)
        selection_mode = reward_type_id(reward[:species_mode] || reward[:selection_mode] || :single)
        selection_mode = :single unless [:single, :fusion, :random_type, :random_bst].include?(selection_mode)
        requested_species = reward[:resolved_species] || reward[:species] || reward[:pokemon] || reward[:id]
        fallback_species = reward[:fallback_species] || reward[:fallback]
        species = reward[:resolved_species] || resolve_reward_species(reward, selection_mode)
        species ||= requested_species
        species_data = defined?(GameData::Species) ? (GameData::Species.try_get(species) rescue nil) : nil
        if !species_data && fallback_species
          species = fallback_species
          species_data = defined?(GameData::Species) ? (GameData::Species.try_get(species) rescue nil) : nil
        end
        types_specified = (reward.key?(:types) || reward.key?(:type1) || reward.key?(:type2)) &&
                          !Array(reward[:types] || [reward[:type1], reward[:type2]].compact).empty?
        type_values = reward[:types] || [reward[:type1], reward[:type2]].compact
        types = Array(type_values).map { |value| resolve_type_id(value) }.compact.uniq
        generate_moves = if reward.key?(:generate_moves)
                           reward_truthy?(reward[:generate_moves])
                         else
                           !reward.key?(:moves)
                         end
        delivery = reward_type_id(reward[:delivery] || :either)
        is_egg = reward[:egg] == true || reward[:egg].to_s.downcase == "true" || reward[:type].to_s.downcase == "egg"
        reward.merge(
          :species => species_data ? species_data.id : (species.to_sym rescue species),
          :resolved_species => species_data ? species_data.id : nil,
          :species_mode => selection_mode,
          :requested_species => (requested_species.to_sym rescue requested_species),
          :fallback_species => (fallback_species.to_sym rescue fallback_species),
          :level => (reward[:level] || 1).to_i,
          :quantity => [(reward[:quantity] || reward[:qty] || 1).to_i, 1].max,
          :delivery => delivery,
          :egg => is_egg,
          :generate_moves => generate_moves,
          :types => types,
          :types_specified => types_specified,
          :distribution_id => (reward[:distribution_id] || reward[:distribution]).to_s.strip,
          :distribution_version => [(reward[:distribution_version] || 1).to_i, 1].max,
          :untradeable => reward_truthy?(reward[:untradeable] || reward[:trade_locked]),
          :trade_lock_reason => (reward[:trade_lock_reason] || reward[:untradeable_reason]).to_s,
          :duplicate_policy => reward_type_id(reward[:duplicate_policy] || :allow),
          :evolution_policy => reward_type_id(reward[:evolution_policy] || reward[:evolution_behavior] || :allow),
          :custom_type_policy => normalize_policy_hash(reward[:custom_type_policy] || reward[:type_policy]),
          :origin_label => (reward[:origin_label] || reward[:obtain_text]).to_s
        )
      end

      def resolve_reward_species(reward, selection_mode)
        case selection_mode
        when :fusion
          head = GameData::Species.try_get(reward[:fusion_head_species] || reward[:head_species]) rescue nil
          body = GameData::Species.try_get(reward[:fusion_body_species] || reward[:body_species]) rescue nil
          return nil unless reward_base_species?(head) && reward_base_species?(body)
          "B#{body.id_number}H#{head.id_number}".to_sym
        when :random_type
          type_id = resolve_type_id(reward[:random_type] || reward[:pokemon_type])
          candidates = reward_species_candidates.select { |data| data.types.include?(type_id) }
          selected = candidates.empty? ? nil : candidates[rand(candidates.length)]
          selected && selected.id
        when :random_bst
          minimum = (reward[:bst_min] || reward[:minimum_bst] || 0).to_i
          maximum = (reward[:bst_max] || reward[:maximum_bst] || 9_999).to_i
          candidates = reward_species_candidates.select do |data|
            total = reward_species_bst(data)
            total >= minimum && total <= maximum
          end
          selected = candidates.empty? ? nil : candidates[rand(candidates.length)]
          selected && selected.id
        else
          reward[:species] || reward[:pokemon] || reward[:id]
        end
      rescue Exception => e
        extended_log_exception("Pokemon reward species selection failed", e)
        nil
      end

      def reward_species_candidates
        rows = []
        return rows unless defined?(GameData::Species)
        GameData::Species.each do |data|
          rows << data if reward_base_species?(data)
        end
        rows
      rescue
        []
      end

      def reward_base_species?(data)
        return false unless data
        return false if data.respond_to?(:is_fusion) && data.is_fusion
        return false if data.respond_to?(:is_triple_fusion) && data.is_triple_fusion
        return false if data.respond_to?(:form) && data.form.to_i != 0
        number = data.respond_to?(:id_number) ? data.id_number.to_i : 0
        maximum = defined?(::Settings::NB_POKEMON) ? ::Settings::NB_POKEMON.to_i : number
        number > 0 && number <= maximum
      rescue
        false
      end

      def reward_species_bst(data)
        stats = data && data.respond_to?(:base_stats) ? data.base_stats : {}
        stats.respond_to?(:values) ? stats.values.inject(0) { |sum, value| sum + value.to_i } : 0
      rescue
        0
      end

      def validate_pokemon_reward(reward, context)
        return failure(:pokemon_unavailable, "Pokemon rewards are unavailable.", :reward => reward) unless defined?(Pokemon) && defined?(GameData::Species)
        species = GameData::Species.try_get(reward[:species]) rescue nil
        return failure(:missing_species, "That Pokemon species is unavailable.", :reward => reward) unless species
        max_level = defined?(::Settings::MAXIMUM_LEVEL) ? ::Settings::MAXIMUM_LEVEL.to_i : 100
        return failure(:invalid_level, "That Pokemon has an invalid level.", :reward => reward) unless reward[:level].to_i.between?(1, max_level)
        return failure(:invalid_delivery, "That Pokemon has an invalid delivery destination.", :reward => reward) unless [:party, :storage, :either].include?(reward[:delivery])
        return failure(:too_many_types, "A Pokemon can have at most two reward types.", :reward => reward) if reward[:types].length > 2
        return failure(:invalid_type, "That Pokemon has an invalid reward type.", :reward => reward) if reward[:types_specified] && reward[:types].empty?
        validation = validate_pokemon_fields(reward)
        return validation unless validation.ok?
        return failure(:trainer_unavailable, "The player is unavailable.", :reward => reward) unless defined?($Trainer) && $Trainer
        return failure(:storage_unavailable, "Pokemon Storage is unavailable.", :reward => reward) unless defined?($PokemonStorage) && $PokemonStorage
        reserve_pokemon_capacity(reward, context)
      rescue Exception => e
        extended_log_exception("Pokemon reward validation failed", e)
        failure(:pokemon_validation_failed, "That Pokemon reward could not be validated.", :reward => reward)
      end

      def validate_pokemon_fields(reward)
        if reward[:species_mode] == :fusion
          return failure(:missing_fusion_species, "That Pokemon fusion needs a valid head and body.", :reward => reward) unless reward[:resolved_species]
        elsif reward[:species_mode] == :random_type
          return failure(:empty_random_type_pool, "No Pokemon match that reward type pool.", :reward => reward) unless reward[:resolved_species]
        elsif reward[:species_mode] == :random_bst
          minimum = (reward[:bst_min] || 0).to_i
          maximum = (reward[:bst_max] || 9_999).to_i
          return failure(:invalid_bst_range, "That Pokemon reward has an invalid BST range.", :reward => reward) if minimum < 0 || maximum < minimum
          return failure(:empty_random_bst_pool, "No Pokemon match that reward BST range.", :reward => reward) unless reward[:resolved_species]
        end
        return failure(:invalid_form, "That Pokemon has an invalid form.", :reward => reward) if reward[:form] && reward[:form].to_i < 0
        return failure(:invalid_gender, "That Pokemon has an invalid gender.", :reward => reward) if reward.key?(:gender) && !random_reward_value?(reward[:gender]) && ![0, 1, 2, :male, :female, :genderless, "male", "female", "genderless"].include?(reward[:gender])
        return failure(:invalid_nature, "That Pokemon has an invalid nature.", :reward => reward) if reward[:nature] && !random_reward_value?(reward[:nature]) && !(GameData::Nature.try_get(reward[:nature]) rescue nil)
        return failure(:invalid_ability, "That Pokemon has an invalid ability.", :reward => reward) if reward[:ability] && !random_reward_value?(reward[:ability]) && !(GameData::Ability.try_get(reward[:ability]) rescue nil)
        return failure(:invalid_item, "That Pokemon has an invalid held item.", :reward => reward) if reward[:held_item] && !(GameData::Item.try_get(reward[:held_item]) rescue nil)
        return failure(:invalid_poke_ball, "That Pokemon has an invalid Poke Ball.", :reward => reward) if reward[:poke_ball] && !(GameData::Item.try_get(reward[:poke_ball]) rescue nil)
        return failure(:invalid_duplicate_policy, "That Pokemon has an invalid duplicate policy.", :reward => reward) unless [:allow, :reject, :replace].include?(reward[:duplicate_policy])
        return failure(:invalid_evolution_policy, "That Pokemon has an invalid evolution policy.", :reward => reward) unless [:allow, :block].include?(reward[:evolution_policy])
        if reward[:duplicate_policy] != :allow && reward[:distribution_id].to_s.empty?
          return failure(:missing_distribution_id, "Duplicate-controlled Pokemon require a distribution ID.", :reward => reward)
        end
        return failure(:missing_distribution_id, "Trade-restricted Pokemon require a distribution ID.", :reward => reward) if reward[:untradeable] && reward[:distribution_id].to_s.empty?
        if reward[:duplicate_policy] == :reject && owned_distribution_pokemon(reward[:distribution_id]).any?
          return failure(:distribution_already_owned, "That Pokemon distribution is already owned.", :reward => reward)
        end
        Array(reward[:moves]).each do |move|
          return failure(:invalid_move, "That Pokemon has an invalid move.", :reward => reward) unless GameData::Move.try_get(move) rescue nil
        end
        return failure(:too_many_moves, "A Pokemon reward can specify at most four moves.", :reward => reward) if Array(reward[:moves]).length > 4
        validate_stat_values(reward)
      end

      def validate_stat_values(reward)
        iv_source = reward[:ivs] || reward[:iv]
        ivs = random_reward_value?(iv_source) ? {} : normalize_stat_hash(iv_source)
        evs = normalize_stat_hash(reward[:evs] || reward[:ev])
        return failure(:invalid_ivs, "That Pokemon has invalid IVs.", :reward => reward) if ivs.nil? || ivs.any? { |_stat, value| value < 0 || value > Pokemon::IV_STAT_LIMIT }
        return failure(:invalid_evs, "That Pokemon has invalid EVs.", :reward => reward) if evs.nil? || evs.any? { |_stat, value| value < 0 || value > Pokemon::EV_STAT_LIMIT }
        return failure(:invalid_evs, "That Pokemon has too many total EVs.", :reward => reward) if evs.values.inject(0) { |sum, value| sum + value } > Pokemon::EV_LIMIT
        iv_min = reward[:iv_min]
        iv_max = reward[:iv_max]
        if !iv_min.nil? || !iv_max.nil?
          low = (iv_min.nil? ? 0 : iv_min).to_i
          high = (iv_max.nil? ? Pokemon::IV_STAT_LIMIT : iv_max).to_i
          return failure(:invalid_iv_range, "That Pokemon has an invalid IV range.", :reward => reward) unless low.between?(0, Pokemon::IV_STAT_LIMIT) && high.between?(0, Pokemon::IV_STAT_LIMIT) && low <= high
        end
        perfect = (reward[:perfect_ivs] || 0).to_i
        return failure(:invalid_perfect_ivs, "That Pokemon has an invalid perfect IV count.", :reward => reward) unless perfect.between?(0, 6)
        success(:reward => reward)
      end

      def reserve_pokemon_capacity(reward, context)
        plan = context[:reward_plan]
        party_free = [pokemon_party_limit - $Trainer.party.length, 0].max
        storage_free = pokemon_storage_free_slots
        if plan.is_a?(Hash)
          capacity = plan[:pokemon_capacity] ||= { :party => party_free, :storage => storage_free }
          party_free = capacity[:party]
          storage_free = capacity[:storage]
        end
        count = reward[:quantity].to_i
        if reward[:duplicate_policy] == :replace
          owned_distribution_pokemon(reward[:distribution_id]).each do |entry|
            entry[:location] == :party ? party_free += 1 : storage_free += 1
          end
        end
        case reward[:delivery]
        when :party
          return failure(:party_full, "There isn't enough room in the party.", :reward => reward) if party_free < count
          party_free -= count
        when :storage
          return failure(:storage_full, "There isn't enough room in Pokemon Storage.", :reward => reward) if storage_free < count
          storage_free -= count
        else
          party_used = [party_free, count].min
          party_free -= party_used
          storage_needed = count - party_used
          return failure(:storage_full, "There isn't enough room for that Pokemon.", :reward => reward) if storage_free < storage_needed
          storage_free -= storage_needed
        end
        if plan.is_a?(Hash)
          plan[:pokemon_capacity][:party] = party_free
          plan[:pokemon_capacity][:storage] = storage_free
        end
        success(:reward => reward)
      end

      def grant_pokemon_reward(reward, context)
        deliveries = []
        replacements = reward[:duplicate_policy] == :replace ? remove_owned_distribution_pokemon(reward[:distribution_id]) : []
        reward[:quantity].to_i.times do
          pokemon = build_reward_pokemon(reward, context)
          location = deliver_reward_pokemon(pokemon, reward[:delivery])
          unless location
            rollback_pokemon_deliveries(deliveries)
            restore_distribution_pokemon(replacements)
            return failure(:pokemon_delivery_failed, "That Pokemon could not be delivered.", :reward => reward)
          end
          deliveries << location.merge(:pokemon => pokemon)
        end
        success(:reward => reward, :details => { :receipt_data => { :deliveries => deliveries, :replacements => replacements, :source => context[:source] } })
      rescue Exception => e
        rollback_pokemon_deliveries(deliveries || [])
        restore_distribution_pokemon(replacements || [])
        extended_log_exception("Pokemon reward grant failed", e)
        failure(:pokemon_grant_failed, "That Pokemon could not be granted.", :reward => reward)
      end

      def build_reward_pokemon(reward, context = {})
        scope = reward[:egg] ? :egg : :gift
        owner = reward_pokemon_owner(reward)
        creator = proc { owner ? Pokemon.new(reward[:species], reward[:level].to_i, owner) : Pokemon.new(reward[:species], reward[:level].to_i) }
        ignore_boundaries = context[:ignore_iv_boundaries] || context[:source].to_s == "reloaded_mart"
        pokemon = if !ignore_boundaries && defined?(ReloadedIVBoundaries) && ReloadedIVBoundaries.respond_to?(:with_creation_scope)
                    ReloadedIVBoundaries.with_creation_scope(scope, :reward) { creator.call }
                  else
                    creator.call
                  end
        pokemon.form_simple = reward[:form].to_i if reward.key?(:form)
        pokemon.shiny = reward_truthy?(reward[:shiny]) if reward.key?(:shiny) && !random_reward_value?(reward[:shiny])
        pokemon.gender = normalize_gender(reward[:gender]) if reward.key?(:gender) && !random_reward_value?(reward[:gender])
        pokemon.nature = reward[:nature] if reward[:nature] && !random_reward_value?(reward[:nature])
        pokemon.ability = reward[:ability] if reward[:ability] && !random_reward_value?(reward[:ability])
        pokemon.ability_index = reward[:ability_index].to_i if reward.key?(:ability_index)
        pokemon.item = reward[:held_item] if reward[:held_item]
        pokemon.poke_ball = GameData::Item.get(reward[:poke_ball]).id if reward[:poke_ball] && (GameData::Item.try_get(reward[:poke_ball]) rescue nil)
        pokemon.name = reward[:name].to_s unless reward[:name].to_s.empty?
        pokemon.happiness = reward[:happiness].to_i.clamp(0, 255) if reward.key?(:happiness)
        apply_reward_stats(pokemon, reward)
        apply_reward_moves(pokemon, reward)
        pokemon.reloaded_reward_types = reward[:types].dup if !reward[:types].empty? && pokemon.respond_to?(:reloaded_reward_types=)
        apply_distribution_metadata(pokemon, reward, context)
        if reward[:egg]
          pokemon.name = _INTL("Egg")
          pokemon.steps_to_hatch = pokemon.species_data.hatch_steps
          pokemon.obtain_method = 1
        end
        pokemon.calc_stats
        pokemon.record_first_moves
        pokemon
      end

      def apply_reward_stats(pokemon, reward)
        iv_source = reward[:ivs] || reward[:iv]
        ivs = random_reward_value?(iv_source) ? {} : (normalize_stat_hash(iv_source) || {})
        evs = normalize_stat_hash(reward[:evs] || reward[:ev]) || {}
        if reward.key?(:iv_min) || reward.key?(:iv_max)
          low = (reward[:iv_min] || 0).to_i
          high = (reward[:iv_max] || Pokemon::IV_STAT_LIMIT).to_i
          GameData::Stat.each_main { |stat| pokemon.iv[stat.id] = low + rand(high - low + 1) }
        end
        ivs.each { |stat, value| pokemon.iv[stat] = value }
        evs.each { |stat, value| pokemon.ev[stat] = value }
        perfect = [(reward[:perfect_ivs] || 0).to_i, 0].max
        if perfect > 0
          stats = []
          GameData::Stat.each_main { |stat| stats << stat.id }
          stats.sort_by { rand }.first([perfect, stats.length].min).each { |stat| pokemon.iv[stat] = Pokemon::IV_STAT_LIMIT }
        end
      end

      def reward_pokemon_owner(reward)
        name = reward[:ot_name] || reward[:original_trainer_name]
        id = reward[:ot_id] || reward[:original_trainer_id]
        gender = reward[:ot_gender] || reward[:original_trainer_gender]
        language = reward[:ot_language] || reward[:language]
        return nil if name.to_s.empty? && id.nil? && gender.nil? && language.nil?
        default_owner = Pokemon::Owner.new_from_trainer($Trainer)
        owner_name = name.to_s.empty? ? default_owner.name : name.to_s
        owner_id = id.nil? ? default_owner.id : id.to_i
        owner_gender = gender.nil? ? default_owner.gender : normalize_gender(gender)
        owner_language = language.nil? ? default_owner.language : language.to_i
        Pokemon::Owner.new(owner_id, owner_name, owner_gender, owner_language)
      rescue Exception => e
        extended_log_exception("Pokemon reward owner creation failed", e)
        nil
      end

      def apply_distribution_metadata(pokemon, reward, context)
        pokemon.reloaded_distribution_id = reward[:distribution_id] if pokemon.respond_to?(:reloaded_distribution_id=)
        pokemon.reloaded_distribution_version = reward[:distribution_version] if pokemon.respond_to?(:reloaded_distribution_version=)
        pokemon.reloaded_distribution_source = context[:source].to_s if pokemon.respond_to?(:reloaded_distribution_source=)
        pokemon.reloaded_untradeable = reward[:untradeable] if pokemon.respond_to?(:reloaded_untradeable=)
        pokemon.reloaded_trade_lock_reason = reward[:trade_lock_reason] if pokemon.respond_to?(:reloaded_trade_lock_reason=)
        pokemon.reloaded_custom_type_policy = reward[:custom_type_policy] if pokemon.respond_to?(:reloaded_custom_type_policy=)
        pokemon.reloaded_duplicate_policy = reward[:duplicate_policy] if pokemon.respond_to?(:reloaded_duplicate_policy=)
        pokemon.reloaded_evolution_policy = reward[:evolution_policy] if pokemon.respond_to?(:reloaded_evolution_policy=)
        pokemon.obtain_text = reward[:origin_label] unless reward[:origin_label].to_s.empty?
        pokemon.obtain_method = reward[:obtain_method].to_i if reward.key?(:obtain_method)
        pokemon.obtain_method = 4 if reward_truthy?(reward[:fateful_encounter]) && !reward[:egg]
      end

      def apply_reward_moves(pokemon, reward)
        if reward[:generate_moves]
          pokemon.reset_moves
          return
        end
        return unless reward.key?(:moves)
        pokemon.moves = []
        Array(reward[:moves]).each { |move| pokemon.learn_move(move) }
      end

      def deliver_reward_pokemon(pokemon, delivery)
        if delivery != :storage && $Trainer.party.length < pokemon_party_limit
          $Trainer.party << pokemon
          return { :location => :party }
        end
        return nil if delivery == :party
        location = first_storage_position
        return nil unless location
        $PokemonStorage[location[0], location[1]] = pokemon
        { :location => :storage, :box => location[0], :index => location[1] }
      end

      def first_storage_position
        current = $PokemonStorage.currentBox.to_i rescue 0
        boxes = [current] + (0...$PokemonStorage.maxBoxes).to_a
        boxes.uniq.each do |box|
          index = $PokemonStorage.pbFirstFreePos(box)
          return [box, index] if index && index >= 0
        end
        nil
      end

      def rollback_pokemon_reward(receipt)
        data = receipt.data || {}
        result = rollback_pokemon_deliveries(data[:deliveries])
        restore_distribution_pokemon(data[:replacements])
        result
      end

      def owned_distribution_pokemon(distribution_id)
        id = distribution_id.to_s
        return [] if id.empty?
        rows = []
        if defined?($Trainer) && $Trainer
          Array($Trainer.party).each_with_index do |pokemon, index|
            next unless pokemon && pokemon.respond_to?(:reloaded_distribution_id) && pokemon.reloaded_distribution_id.to_s == id
            rows << { :location => :party, :index => index, :pokemon => pokemon }
          end
        end
        if defined?($PokemonStorage) && $PokemonStorage
          (0...$PokemonStorage.maxBoxes).each do |box|
            (0...$PokemonStorage.maxPokemon(box)).each do |index|
              pokemon = $PokemonStorage[box, index]
              next unless pokemon && pokemon.respond_to?(:reloaded_distribution_id) && pokemon.reloaded_distribution_id.to_s == id
              rows << { :location => :storage, :box => box, :index => index, :pokemon => pokemon }
            end
          end
        end
        rows
      rescue Exception => e
        extended_log_exception("Pokemon distribution lookup failed", e)
        []
      end

      def remove_owned_distribution_pokemon(distribution_id)
        rows = owned_distribution_pokemon(distribution_id)
        rows.select { |entry| entry[:location] == :party }.sort_by { |entry| -entry[:index].to_i }.each do |entry|
          $Trainer.party.delete_at(entry[:index].to_i)
        end
        rows.select { |entry| entry[:location] == :storage }.each do |entry|
          $PokemonStorage[entry[:box].to_i, entry[:index].to_i] = nil
        end
        rows
      rescue Exception => e
        extended_log_exception("Pokemon distribution replacement failed", e)
        []
      end

      def restore_distribution_pokemon(rows)
        Array(rows).select { |entry| entry[:location] == :storage }.each do |entry|
          $PokemonStorage[entry[:box].to_i, entry[:index].to_i] = entry[:pokemon]
        end
        Array(rows).select { |entry| entry[:location] == :party }.sort_by { |entry| entry[:index].to_i }.each do |entry|
          $Trainer.party.insert(entry[:index].to_i, entry[:pokemon])
        end
        true
      rescue Exception => e
        extended_log_exception("Pokemon distribution restoration failed", e)
        false
      end

      def rollback_pokemon_deliveries(deliveries)
        Array(deliveries).reverse_each do |entry|
          pokemon = entry[:pokemon]
          if entry[:location] == :party
            index = $Trainer.party.index { |owned| owned.equal?(pokemon) }
            $Trainer.party.delete_at(index) if index
          else
            box = entry[:box].to_i
            index = entry[:index].to_i
            $PokemonStorage[box, index] = nil if $PokemonStorage[box, index].equal?(pokemon)
          end
        end
        true
      rescue
        false
      end

      def finalize_pokemon_reward(receipt)
        return true unless defined?($Trainer) && $Trainer && $Trainer.respond_to?(:pokedex)
        Array((receipt.data || {})[:deliveries]).each do |entry|
          pokemon = entry[:pokemon]
          next unless pokemon
          $Trainer.pokedex.register(pokemon.species, pokemon.gender, pokemon.form_simple)
          $Trainer.pokedex.set_owned(pokemon.species)
          $Trainer.pokedex.register_last_seen(pokemon) if $Trainer.pokedex.respond_to?(:register_last_seen)
        end
        true
      end

      def pokemon_reward_label(reward)
        data = GameData::Species.try_get(reward[:species]) rescue nil
        name = data ? data.name : reward[:species].to_s
        reward[:egg] ? _INTL("{1} Egg", name) : name
      end

      def pokemon_reward_message(reward)
        quantity = reward[:quantity].to_i
        label = pokemon_reward_label(reward)
        quantity > 1 ? _INTL("You received {1} {2}!", quantity, label) : _INTL("You received {1}!", label)
      end

      def pokemon_party_limit
        defined?(::Settings::MAX_PARTY_SIZE) ? ::Settings::MAX_PARTY_SIZE.to_i : 6
      end

      def pokemon_storage_free_slots
        total = 0
        (0...$PokemonStorage.maxBoxes).each do |box|
          (0...$PokemonStorage.maxPokemon(box)).each { |index| total += 1 unless $PokemonStorage[box, index] }
        end
        total
      end

      def normalize_gender(value)
        case value.to_s.downcase
        when "male" then 0
        when "female" then 1
        when "genderless" then 2
        else value.to_i
        end
      end

      def normalize_stat_hash(value)
        return {} if value.nil?
        return nil unless value.is_a?(Hash)
        main_ids = []
        GameData::Stat.each_main { |stat| main_ids << stat.id }
        value.each_with_object({}) do |(stat, amount), result|
          data = GameData::Stat.try_get(stat) rescue nil
          return nil unless data && main_ids.include?(data.id)
          result[data.id] = amount.to_i
        end
      end

      def normalize_policy_hash(value)
        return {} unless value.is_a?(Hash)
        value.each_with_object({}) do |(key, setting), result|
          result[reward_type_id(key)] = reward_type_id(setting)
        end
      end

      def random_reward_value?(value)
        [:random, :roll, :default].include?(reward_type_id(value))
      rescue
        false
      end

      def resolve_type_id(value)
        data = GameData::Type.try_get(value) rescue nil
        return nil unless data && !data.pseudo_type
        data.id
      end

      def register_tm_vault_reward
        register(
          :tm_vault,
          :owner => :reloaded,
          :priority => 85,
          :aliases => [:tm_vault_move],
          :normalize => proc { |reward| normalize_tm_vault_reward(reward) },
          :validate => proc { |reward, _context| validate_tm_vault_reward(reward) },
          :grant => proc { |reward, context| grant_tm_vault_reward(reward, context) },
          :rollback => proc { |receipt, _context| rollback_tm_vault_reward(receipt) },
          :label => proc { |reward| tm_vault_reward_label(reward) },
          :describe => proc { |reward| "tm_vault_move=#{reward[:move]}" },
          :message => proc { |reward, _result, _context| _INTL("{1} was added to your TM Vault!", tm_vault_reward_label(reward)) }
        )
      end

      def normalize_tm_vault_reward(reward)
        move = reward[:move] || reward[:move_id] || reward[:id]
        data = GameData::Move.try_get(move) rescue nil
        reward.merge(:move => data ? data.id : (move.to_sym rescue move), :quantity => 1)
      end

      def validate_tm_vault_reward(reward)
        return failure(:tm_vault_unavailable, "The TM Vault is unavailable.", :reward => reward) unless defined?(TMVault)
        data = GameData::Move.try_get(reward[:move]) rescue nil
        return failure(:missing_move, "That move is unavailable.", :reward => reward) unless data
        return failure(:already_unlocked, "That move is already in the TM Vault.", :reward => reward) if TMVault.vault.include?(data.id)
        success(:reward => reward)
      end

      def grant_tm_vault_reward(reward, context)
        before_moves = TMVault.vault.dup
        before_sources = deep_copy_reward_value(TMVault.source_map)
        added = TMVault.register(reward[:move], :notify => false, :source => context[:source] || :reward)
        return failure(:tm_vault_grant_failed, "That move could not be added to the TM Vault.", :reward => reward) unless added
        success(:reward => reward, :details => { :receipt_data => { :moves => before_moves, :sources => before_sources } })
      end

      def rollback_tm_vault_reward(receipt)
        data = receipt.data || {}
        TMVault.save_vault(Array(data[:moves]))
        sources = deep_copy_reward_value(data[:sources] || {})
        if defined?(Reloaded::SaveData)
          Reloaded::SaveData.set(:tm_vault, :sources, sources, :section => :systems)
        else
          TMVault.data["sources"] = sources
        end
        true
      rescue
        false
      end

      def tm_vault_reward_label(reward)
        data = GameData::Move.try_get(reward[:move]) rescue nil
        data ? data.name : reward[:move].to_s
      end

      def register_outfit_reward
        register(
          :outfit,
          :owner => :reloaded,
          :priority => 90,
          :normalize => proc { |reward| normalize_outfit_reward(reward) },
          :validate => proc { |reward, _context| validate_outfit_reward(reward) },
          :grant => proc { |reward, _context| grant_outfit_reward(reward) },
          :rollback => proc { |receipt, _context| rollback_outfit_reward(receipt) },
          :label => proc { |reward| outfit_reward_label(reward) },
          :describe => proc { |reward| "outfit_category=#{reward[:category]} outfit=#{reward[:outfit_id]}" },
          :message => proc { |reward, _result, _context| _INTL("You unlocked {1}!", outfit_reward_label(reward)) }
        )
      end

      def normalize_outfit_reward(reward)
        category = reward_type_id(reward[:category] || reward[:outfit_type] || :clothes)
        category = :hairstyle if [:hair, :hairstyles].include?(category)
        category = :hat if category == :hats
        category = :clothes if [:clothing, :outfits].include?(category)
        outfit_id = reward[:outfit_id] || reward[:outfit] || reward[:id]
        reward.merge(:category => category, :outfit_id => outfit_id, :quantity => 1)
      end

      def validate_outfit_reward(reward)
        return failure(:trainer_unavailable, "The player is unavailable.", :reward => reward) unless defined?($Trainer) && $Trainer
        return failure(:invalid_outfit_category, "That outfit category is unavailable.", :reward => reward) unless [:clothes, :hat, :hairstyle].include?(reward[:category])
        refresh_outfit_data(reward[:category])
        id = resolved_outfit_id(reward[:category], reward[:outfit_id])
        return failure(:missing_outfit, "That outfit is unavailable.", :reward => reward) if id.nil?
        return failure(:already_unlocked, "That outfit is already unlocked.", :reward => reward) if outfit_unlocks(reward[:category]).include?(id)
        reward[:outfit_id] = id
        success(:reward => reward)
      end

      def grant_outfit_reward(reward)
        id = resolved_outfit_id(reward[:category], reward[:outfit_id])
        list = outfit_unlocks(reward[:category])
        return failure(:outfit_grant_failed, "That outfit could not be unlocked.", :reward => reward) if id.nil? || list.include?(id)
        list << id
        success(:reward => reward, :details => { :receipt_data => { :category => reward[:category], :outfit_id => id } })
      end

      def rollback_outfit_reward(receipt)
        data = receipt.data || {}
        outfit_unlocks(data[:category]).delete(data[:outfit_id])
        true
      rescue
        false
      end

      def refresh_outfit_data(category)
        method_name = { :clothes => :update_global_clothes_list, :hat => :update_global_hats_list, :hairstyle => :update_global_hairstyles_list }[category]
        Object.new.send(method_name) if method_name && Object.private_method_defined?(method_name)
      rescue
      end

      def outfit_data(category)
        return {} unless defined?($PokemonGlobal) && $PokemonGlobal
        value = case category
                when :hat then $PokemonGlobal.hats_data
                when :hairstyle then $PokemonGlobal.hairstyles_data
                else $PokemonGlobal.clothes_data
                end
        value.is_a?(Hash) ? value : {}
      rescue
        {}
      end

      def resolved_outfit_id(category, value)
        data = outfit_data(category)
        return value if data.key?(value)
        string = value.to_s
        return string if data.key?(string)
        symbol = string.to_sym rescue nil
        return symbol if symbol && data.key?(symbol)
        nil
      end

      def outfit_unlocks(category)
        attribute = { :hat => :unlocked_hats, :hairstyle => :unlocked_hairstyles, :clothes => :unlocked_clothes }[category]
        list = $Trainer.send(attribute)
        unless list.is_a?(Array)
          list = []
          $Trainer.send("#{attribute}=", list)
        end
        list
      end

      def outfit_reward_label(reward)
        id = resolved_outfit_id(reward[:category], reward[:outfit_id]) || reward[:outfit_id]
        data = outfit_data(reward[:category])[id]
        data && data.respond_to?(:name) ? data.name.to_s : id.to_s
      end

      def register_feature_unlock_reward
        register(
          :feature_unlock,
          :owner => :reloaded,
          :priority => 95,
          :normalize => proc { |reward| reward.merge(:feature => reward_type_id(reward[:feature] || reward[:feature_id] || reward[:id]), :quantity => 1) },
          :validate => proc { |reward, _context| validate_feature_unlock_reward(reward) },
          :grant => proc { |reward, _context| grant_feature_unlock_reward(reward) },
          :rollback => proc { |receipt, _context| rollback_feature_unlock_reward(receipt) },
          :label => proc { |reward| feature_reward_label(reward) },
          :describe => proc { |reward| "feature_unlock=#{reward[:feature]}" },
          :message => proc { |reward, _result, _context| _INTL("You unlocked {1}!", feature_reward_label(reward)) }
        )
      end

      def validate_feature_unlock_reward(reward)
        return failure(:feature_system_unavailable, "Reloaded features are unavailable.", :reward => reward) unless defined?(Reloaded::Features)
        return failure(:unknown_feature, "That Reloaded feature is unavailable.", :reward => reward) unless Reloaded::Features.registered?(reward[:feature])
        return failure(:already_unlocked, "That Reloaded feature is already enabled.", :reward => reward) if Reloaded::Features.enabled?(reward[:feature])
        success(:reward => reward)
      end

      def grant_feature_unlock_reward(reward)
        bucket = Reloaded::SaveData.system(Reloaded::Features::SAVE_SYSTEM)
        key = reward[:feature]
        had_override = bucket.key?(key) || bucket.key?(key.to_s)
        previous = bucket.key?(key) ? bucket[key] : bucket[key.to_s]
        Reloaded::Features.enable(key, :scope => :save)
        success(:reward => reward, :details => { :receipt_data => { :feature => key, :had_override => had_override, :previous => previous } })
      end

      def rollback_feature_unlock_reward(receipt)
        data = receipt.data || {}
        if data[:had_override]
          Reloaded::SaveData.set(Reloaded::Features::SAVE_SYSTEM, data[:feature], data[:previous], :section => :systems)
        else
          Reloaded::Features.reset(data[:feature], :scope => :save)
        end
        true
      rescue
        false
      end

      def feature_reward_label(reward)
        feature = Reloaded::Features.feature(reward[:feature]) rescue nil
        feature ? feature[:name] : reward_titleize(reward[:feature])
      end

      def register_group_reward
        register(
          :group,
          :owner => :reloaded,
          :priority => 5,
          :aliases => [:reward_group, :package],
          :normalize => proc { |reward| normalize_composite_reward(reward, :grants) },
          :validate => proc { |reward, context| validate_group_reward(reward, context) },
          :grant => proc { |reward, context| grant_group_reward(reward, context) },
          :rollback => proc { |receipt, context| rollback_composite_reward(receipt, context) },
          :finalize => proc { |receipt, context| finalize_composite_reward(receipt, context) },
          :expand => proc { |reward, multiplier| Array.new(multiplier.to_i) { reward.merge(:quantity => 1) } },
          :label => proc { |reward| (reward[:name] || reward[:label] || _INTL("Reward Group")).to_s },
          :describe => proc { |reward| "reward_group grants=#{Array(reward[:grants]).length}" },
          :message => proc { |reward, _result, _context| _INTL("You received {1}!", (reward[:name] || _INTL("a reward package")).to_s) }
        )
      end

      def validate_group_reward(reward, context)
        return failure(:reward_depth_exceeded, "That reward contains too many nested reward groups.", :reward => reward) if context[:reward_depth].to_i >= 8
        grants = Array(reward[:grants])
        return failure(:empty_rewards, "That reward group has no grants.", :reward => reward) if grants.empty?
        result = validate_all(grants, isolated_reward_context(context))
        return failure(result.code, result.message, :reward => reward, :details => result.details) unless result.ok?
        success(:reward => reward, :details => { :rewards => result.details[:rewards] })
      end

      def grant_group_reward(reward, context)
        result = grant_all(Array(reward[:grants]), context.merge(:defer_finalize => true, :reward_depth => context[:reward_depth].to_i + 1))
        return failure(result.code, result.message, :reward => reward, :details => result.details) unless result.ok?
        success(
          :reward => reward,
          :details => {
            :receipt_data => { :receipts => result.details[:receipts] },
            :applied => result.details[:applied]
          }
        )
      end

      def register_choice_reward
        register(
          :choice,
          :owner => :reloaded,
          :priority => 10,
          :normalize => proc { |reward| normalize_composite_reward(reward, :options) },
          :validate => proc { |reward, context| validate_composite_reward(reward, context, :options) },
          :grant => proc { |reward, context| grant_choice_reward(reward, context) },
          :rollback => proc { |receipt, context| rollback_composite_reward(receipt, context) },
          :finalize => proc { |receipt, context| finalize_composite_reward(receipt, context) },
          :expand => proc { |reward, multiplier| Array.new(multiplier.to_i) { reward.merge(:quantity => 1) } },
          :label => proc { |reward| (reward[:name] || reward[:label] || _INTL("Choice Reward")).to_s },
          :describe => proc { |reward| "choice_reward options=#{Array(reward[:options]).length}" },
          :message => proc { |reward, _result, _context| _INTL("You received {1}!", (reward[:name] || _INTL("your chosen reward")).to_s) }
        )
      end

      def register_random_reward
        register(
          :random,
          :owner => :reloaded,
          :priority => 20,
          :aliases => [:random_reward],
          :normalize => proc { |reward| normalize_composite_reward(reward, :rewards) },
          :validate => proc { |reward, context| validate_random_reward(reward, context) },
          :grant => proc { |reward, context| grant_random_reward(reward, context) },
          :rollback => proc { |receipt, context| rollback_composite_reward(receipt, context) },
          :finalize => proc { |receipt, context| finalize_composite_reward(receipt, context) },
          :expand => proc { |reward, multiplier| Array.new(multiplier.to_i) { reward.merge(:quantity => 1) } },
          :label => proc { |reward| (reward[:name] || reward[:label] || _INTL("Random Reward")).to_s },
          :describe => proc { |reward| "random_reward entries=#{Array(reward[:rewards]).length}" },
          :message => proc { |reward, _result, _context| _INTL("You received {1}!", (reward[:name] || _INTL("a random reward")).to_s) }
        )
      end

      def normalize_composite_reward(reward, key)
        values = reward[key] || reward[key.to_s]
        values ||= reward[:choices] if key == :options
        values ||= reward[:rewards] if key == :grants
        reward.merge(key => Array(values), :quantity => 1)
      end

      def validate_composite_reward(reward, context, key)
        return failure(:reward_depth_exceeded, "That reward contains too many nested reward groups.", :reward => reward) if context[:reward_depth].to_i >= 8
        values = Array(reward[key])
        return failure(:empty_rewards, "That reward has no entries.", :reward => reward) if values.empty?
        valid = valid_composite_candidates(values, context)
        return failure(:no_available_rewards, "None of those rewards are currently available.", :reward => reward) if valid.empty?
        success(:reward => reward, :details => { :available => valid.map { |entry| entry[:index] } })
      end

      def validate_random_reward(reward, context)
        distribution = validate_random_distribution(reward)
        return distribution unless distribution.ok?
        validate_composite_reward(reward, context, :rewards)
      end

      def validate_random_distribution(reward)
        entries = Array(reward[:rewards])
        return failure(:empty_rewards, "That reward has no entries.", :reward => reward) if entries.empty?
        if entries.any? { |entry| deprecated_random_chance_present?(entry) }
          return failure(:unsupported_random_chance_field, "Use chance or percentage for percentage-based random rewards.", :reward => reward)
        end
        percentage_mode = entries.any? { |entry| composite_percentage_present?(entry) }
        if percentage_mode
          return failure(:mixed_random_modes, "Random rewards cannot mix percentages and weights.", :reward => reward) if entries.any? { |entry| composite_weight_present?(entry) }
          percentages = entries.map { |entry| composite_percentage(entry) }
          return failure(:mixed_random_modes, "Percentage rewards must give every entry a percentage.", :reward => reward) if percentages.any?(&:nil?)
          return failure(:invalid_percentage, "Reward percentages must be between 0 and 100.", :reward => reward) if percentages.any? { |value| value < 0 || value > 100 }
          total = percentages.inject(0) { |sum, value| sum + value }
          return failure(:invalid_percentage_total, "Reward percentages must total 100.", :reward => reward) unless total == 100
        else
          weights = entries.map { |entry| composite_weight(entry) }
          return failure(:invalid_weight, "Random reward weights cannot be negative.", :reward => reward) if weights.any? { |value| value < 0 }
          return failure(:invalid_weight, "That random reward has no positive weights.", :reward => reward) if weights.inject(0) { |sum, value| sum + value } <= 0
        end
        success(:reward => reward, :details => { :distribution => percentage_mode ? :percentage : :weight })
      end

      def valid_composite_candidates(values, context)
        Array(values).each_with_index.each_with_object([]) do |(candidate, index), rows|
          payload = composite_payload(candidate)
          next unless payload
          result = validate_all([payload], isolated_reward_context(context))
          rows << { :index => index, :reward => payload, :result => result, :weight => composite_weight(candidate) } if result.ok?
        end
      end

      def grant_choice_reward(reward, context)
        candidates = valid_composite_candidates(reward[:options], context)
        return failure(:no_available_rewards, "None of those rewards are currently available.", :reward => reward) if candidates.empty?
        selected = select_choice_candidate(reward, candidates, context)
        return failure(:cancelled, "The reward choice was cancelled.", :reward => reward) unless selected
        grant_composite_candidate(reward, selected[:reward], context)
      end

      def select_choice_candidate(reward, candidates, context)
        selector = context[:choice_selector]
        if selector.respond_to?(:call)
          value = selector.call(reward, candidates.map { |entry| entry[:reward] })
          if value.is_a?(Integer)
            return candidates.find { |entry| entry[:index] == value } || candidates[value]
          end
          return candidates.find { |entry| entry[:reward].equal?(value) || entry[:reward] == value }
        end
        return candidates.first if candidates.length == 1 && context[:auto_select_single_choice]
        return nil unless defined?(Reloaded::ListPicker)
        rows = candidates.map do |entry|
          { :label => label(entry[:reward]), :value => entry[:index], :detail => description(entry[:reward]) }
        end
        selected_index = Reloaded::ListPicker.popup(
          (reward[:prompt] || reward[:name] || _INTL("Choose a Reward")).to_s,
          rows,
          :add_back => true,
          :search => false,
          :controls => true
        )
        candidates.find { |entry| entry[:index] == selected_index }
      end

      def grant_random_reward(reward, context)
        candidates = valid_composite_candidates(reward[:rewards], context)
        return failure(:no_available_rewards, "None of those rewards are currently available.", :reward => reward) if candidates.empty?
        total = candidates.inject(0) { |sum, entry| sum + [entry[:weight].to_i, 0].max }
        return failure(:invalid_weight, "That random reward has no valid weights.", :reward => reward) if total <= 0
        roll = context[:random_roll]
        roll = if roll.respond_to?(:call)
                 roll.call(total).to_i
               elsif roll.is_a?(Numeric)
                 roll.to_i
               else
                 rand(total)
               end
        roll %= total
        selected = candidates.find do |entry|
          roll -= [entry[:weight].to_i, 0].max
          roll < 0
        end
        grant_composite_candidate(reward, selected[:reward], context)
      end

      def grant_composite_candidate(parent, child, context)
        result = grant_all([child], context.merge(:defer_finalize => true, :reward_depth => context[:reward_depth].to_i + 1))
        return failure(result.code, result.message, :reward => parent, :details => result.details) unless result.ok?
        success(
          :reward => parent,
          :details => {
            :selected_reward => child,
            :receipt_data => { :selected_reward => child, :receipts => result.details[:receipts] }
          }
        )
      end

      def rollback_composite_reward(receipt, context)
        rollback_all(Array((receipt.data || {})[:receipts]), context)
      end

      def finalize_composite_reward(receipt, context)
        finalize_all(Array((receipt.data || {})[:receipts]), context)
      end

      def composite_payload(candidate)
        return candidate unless candidate.is_a?(Hash)
        copy = candidate.dup
        [:weight, :percentage, :chance].each do |key|
          copy.delete(key)
          copy.delete(key.to_s)
        end
        copy
      end

      def composite_weight(candidate)
        return 1 unless candidate.is_a?(Hash)
        percentage = composite_percentage(candidate)
        return percentage unless percentage.nil?
        (candidate[:weight] || candidate["weight"] || 1).to_i
      end

      def composite_percentage_present?(candidate)
        return false unless candidate.is_a?(Hash)
        [:percentage, :chance].any? do |key|
          candidate.key?(key) || candidate.key?(key.to_s)
        end
      end

      def deprecated_random_chance_present?(candidate)
        return false unless candidate.is_a?(Hash)
        [:probability, :percent].any? do |key|
          candidate.key?(key) || candidate.key?(key.to_s)
        end
      end

      def composite_weight_present?(candidate)
        candidate.is_a?(Hash) && (candidate.key?(:weight) || candidate.key?("weight"))
      end

      def composite_percentage(candidate)
        return nil unless composite_percentage_present?(candidate)
        raw = nil
        [:percentage, :chance].each do |key|
          if candidate.key?(key)
            raw = candidate[key]
            break
          elsif candidate.key?(key.to_s)
            raw = candidate[key.to_s]
            break
          end
        end
        return nil unless raw.to_s.strip =~ /\A\d+\z/
        raw.to_i
      end

      def isolated_reward_context(context)
        copy = context.dup
        copy[:reward_plan] = deep_copy_reward_value(context[:reward_plan] || {})
        copy[:reward_depth] = context[:reward_depth].to_i + 1
        copy
      end

      def deep_copy_reward_value(value)
        Marshal.load(Marshal.dump(value))
      rescue
        value.is_a?(Hash) ? value.dup : (value.is_a?(Array) ? value.dup : value)
      end

      def reward_type_id(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "").to_sym
      end

      def reward_titleize(value)
        value.to_s.split("_").map { |part| part[0, 1].upcase + part[1..-1].to_s }.join(" ")
      end

      def reward_truthy?(value)
        return value if value == true || value == false
        ["true", "yes", "on", "1"].include?(value.to_s.strip.downcase)
      end

      def install_pokemon_typing_patch
        return false unless defined?(Pokemon)
        Pokemon.class_eval do
          attr_accessor :reloaded_reward_types
          attr_accessor :reloaded_distribution_id
          attr_accessor :reloaded_distribution_version
          attr_accessor :reloaded_distribution_source
          attr_accessor :reloaded_untradeable
          attr_accessor :reloaded_trade_lock_reason
          attr_accessor :reloaded_custom_type_policy
          attr_accessor :reloaded_duplicate_policy
          attr_accessor :reloaded_evolution_policy

          def reloaded_tradeable?
            !@reloaded_untradeable
          end
        end
        return true if Pokemon.method_defined?(:reloaded_rewards_original_types)
        Pokemon.class_eval do
          alias_method :reloaded_rewards_original_type1, :type1
          alias_method :reloaded_rewards_original_type2, :type2
          alias_method :reloaded_rewards_original_types, :types

          def type1
            values = Array(@reloaded_reward_types).compact
            return values[0] unless values.empty?
            reloaded_rewards_original_type1
          end

          def type2
            values = Array(@reloaded_reward_types).compact
            return (values[1] || values[0]) unless values.empty?
            reloaded_rewards_original_type2
          end

          def types
            values = Array(@reloaded_reward_types).compact.uniq
            return values unless values.empty?
            reloaded_rewards_original_types
          end
        end
        if defined?(Reloaded::Patches) && (!Reloaded::Patches.respond_to?(:registered?) || !Reloaded::Patches.registered?(:rewards_pokemon_typing))
          Reloaded::Patches.register(
            :rewards_pokemon_typing,
            :target => "Pokemon#type1/type2/types",
            :type => :runtime_method_bridge,
            :file => __FILE__,
            :owner => :reloaded
          )
        end
        true
      rescue Exception => e
        extended_log_exception("Pokemon reward typing patch failed", e)
        false
      end

      def install_evolution_restriction_patch
        return false unless defined?(Pokemon)
        patched = false
        [:check_evolution_on_level_up, :check_evolution_on_use_item, :check_evolution_on_trade].each do |method_name|
          original = "reloaded_rewards_original_#{method_name}".to_sym
          next unless Pokemon.method_defined?(method_name)
          next if Pokemon.method_defined?(original)
          Pokemon.class_eval do
            alias_method original, method_name
            define_method(method_name) do |*args|
              policy = respond_to?(:reloaded_evolution_policy) ? reloaded_evolution_policy : nil
              next nil if policy.to_s == "block"
              send(original, *args)
            end
          end
          patched = true
        end
        register_distribution_patch(:rewards_evolution_restriction, "Pokemon evolution checks") if patched
        true
      rescue Exception => e
        extended_log_exception("Pokemon reward evolution restriction failed", e)
        false
      end

      def install_trade_restriction_patches
        install_start_trade_restriction
        install_wonder_trade_restriction
        true
      rescue Exception => e
        extended_log_exception("Pokemon reward trade restrictions failed", e)
        false
      end

      def install_start_trade_restriction
        return true if Object.private_method_defined?(:reloaded_rewards_original_pbStartTrade) || Object.method_defined?(:reloaded_rewards_original_pbStartTrade)
        return false unless Object.private_method_defined?(:pbStartTrade) || Object.method_defined?(:pbStartTrade)
        was_private = Object.private_method_defined?(:pbStartTrade)
        Object.class_eval do
          alias_method :reloaded_rewards_original_pbStartTrade, :pbStartTrade
          def pbStartTrade(pokemon_index, *args)
            pokemon = $Trainer.party[pokemon_index] rescue nil
            return false if defined?(Reloaded::PokemonDistribution) && Reloaded::PokemonDistribution.reject_trade(pokemon)
            reloaded_rewards_original_pbStartTrade(pokemon_index, *args)
          end
          private :pbStartTrade if was_private
          private :reloaded_rewards_original_pbStartTrade if was_private
        end
        register_distribution_patch(:rewards_trade_restriction, "Object#pbStartTrade")
        true
      end

      def install_wonder_trade_restriction
        return false unless defined?(OnlineWondertrade)
        return true if OnlineWondertrade.method_defined?(:reloaded_rewards_original_selectPokemonToGive)
        return false unless OnlineWondertrade.method_defined?(:selectPokemonToGive)
        OnlineWondertrade.class_eval do
          alias_method :reloaded_rewards_original_selectPokemonToGive, :selectPokemonToGive
          def selectPokemonToGive
            pokemon = reloaded_rewards_original_selectPokemonToGive
            return nil if pokemon && defined?(Reloaded::PokemonDistribution) && Reloaded::PokemonDistribution.reject_trade(pokemon)
            pokemon
          end
        end
        register_distribution_patch(:rewards_wonder_trade_restriction, "OnlineWondertrade#selectPokemonToGive")
        true
      end

      def register_distribution_patch(id, target)
        return unless defined?(Reloaded::Patches)
        return if Reloaded::Patches.respond_to?(:registered?) && Reloaded::Patches.registered?(id)
        Reloaded::Patches.register(
          id,
          :target => target,
          :type => :runtime_method_bridge,
          :file => __FILE__,
          :owner => :reloaded
        )
      rescue
      end

      def extended_log_exception(message, error)
        Reloaded::Log.exception(message, error, :channel => :framework) if defined?(Reloaded::Log)
      rescue
      end
    end
  end
end

Reloaded::Rewards.install_extended_types if defined?(Reloaded::Rewards)
