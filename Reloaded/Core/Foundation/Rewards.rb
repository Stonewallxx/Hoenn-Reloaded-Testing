#======================================================
# Reloaded Rewards
# Author: Stonewall
#======================================================
# Shared reward registration and grant pipeline for Reloaded systems and mods.
#======================================================

module Reloaded
  module Rewards
    class Result
      attr_reader :success, :code, :message, :reward, :receipt, :details

      def initialize(success, code = :ok, message = "", options = {})
        @success = !!success
        @code = (code || (@success ? :ok : :failed)).to_sym
        @message = message.to_s
        @reward = options[:reward]
        @receipt = options[:receipt]
        @details = options[:details].is_a?(Hash) ? options[:details] : {}
      end

      def ok?
        @success
      end
    end

    class Receipt
      attr_reader :type, :reward, :data, :owner

      def initialize(type, reward, data = nil, owner = :reloaded)
        @type = type.to_sym
        @reward = reward
        @data = data
        @owner = owner.to_sym
      end
    end

    @handlers = {}
    @aliases = {}
    @installed = false

    class << self
      def boot
        register_builtin_rewards
        install_mystery_gift_bridge
        register_install_events
        true
      rescue Exception => e
        log_exception("Rewards boot failed", e)
        false
      end

      def register(type, config = nil, owner: nil, aliases: nil, override: false, **keywords, &grant_block)
        type_id = normalize_id(type)
        raise ArgumentError, "Reward type is empty." if type_id.to_s.empty?
        if @handlers.key?(type_id) && !override
          log_warning("Reward type registration rejected type=#{type_id} existing_owner=#{@handlers[type_id][:owner]} requested_owner=#{owner || current_owner}")
          return nil
        end
        source = config.is_a?(Hash) ? config.dup : {}
        source.merge!(keywords) unless keywords.empty?
        source[:grant] ||= grant_block
        raise ArgumentError, "Reward type #{type_id} requires a grant handler." unless source[:grant].respond_to?(:call)
        entry = {
          :type => type_id,
          :owner => normalize_id(owner || source[:owner] || source["owner"] || current_owner),
          :priority => (source[:priority] || source["priority"] || 100).to_i,
          :normalize => source[:normalize] || source["normalize"],
          :validate => source[:validate] || source["validate"],
          :grant => source[:grant] || source["grant"],
          :rollback => source[:rollback] || source["rollback"],
          :finalize => source[:finalize] || source["finalize"],
          :label => source[:label] || source["label"],
          :describe => source[:describe] || source["describe"],
          :message => source[:message] || source["message"],
          :expand => source[:expand] || source["expand"]
        }
        remove_aliases_for(type_id) if override
        @handlers[type_id] = entry
        Array(aliases || source[:aliases] || source["aliases"]).each do |alias_id|
          register_alias(alias_id, type_id, :override => override)
        end
        type(type_id)
      rescue Exception => e
        log_exception("Reward registration failed for #{type}", e)
        nil
      end

      def register_alias(alias_id, type_id, override: false)
        alias_key = normalize_id(alias_id)
        canonical = canonical_type(type_id)
        raise ArgumentError, "Reward alias is empty." if alias_key.to_s.empty?
        raise "Unknown reward type: #{type_id}" unless @handlers.key?(canonical)
        if @aliases.key?(alias_key) && @aliases[alias_key] != canonical && !override
          log_warning("Reward alias registration rejected alias=#{alias_key} existing_type=#{@aliases[alias_key]} requested_type=#{canonical}")
          return false
        end
        @aliases[alias_key] = canonical
        true
      rescue Exception => e
        log_exception("Reward alias registration failed for #{alias_id}", e)
        false
      end

      def registered?(type_id)
        @handlers.key?(canonical_type(type_id))
      rescue
        false
      end

      def type(type_id)
        entry = @handlers[canonical_type(type_id)]
        entry ? public_entry(entry) : nil
      rescue
        nil
      end

      def types
        @handlers.keys.sort_by(&:to_s).map { |type_id| type(type_id) }
      end

      def normalize(payload, defaults = {})
        source = reward_hash(payload)
        return nil unless source
        defaults_hash = symbolize_hash(defaults)
        source = defaults_hash.merge(source)
        explicit_type = source[:type] || source[:kind] || source[:grant_type] || source[:reward_type]
        item_candidate = source[:item_id] || source[:item]
        item_candidate ||= source[:id] if explicit_type.nil?
        type_id = nil
        if explicit_type
          type_id = canonical_type(explicit_type)
        elsif item_candidate && resolve_item(item_candidate)
          type_id = :item
        elsif item_candidate
          type_id = canonical_type(item_candidate)
        end
        return nil unless type_id && @handlers.key?(type_id)
        source[:type] = type_id
        source[:quantity] = quantity_for(source)
        entry = @handlers[type_id]
        if entry[:normalize].respond_to?(:call)
          normalized = entry[:normalize].call(source.dup)
          return nil unless normalized.is_a?(Hash)
          source = symbolize_hash(normalized)
          source[:type] = type_id
          source[:quantity] = quantity_for(source)
        end
        source
      rescue Exception => e
        log_exception("Reward normalization failed", e)
        nil
      end

      def normalize_all(payloads, defaults = {})
        Array(payloads).map { |payload| normalize(payload, defaults) }.compact
      end

      def recognized?(payload)
        !normalize(payload).nil?
      rescue
        false
      end

      def validate(payload, context = {})
        reward = normalize(payload)
        return failure(:unknown_reward, "That reward type is unavailable.") unless reward
        entry = @handlers[reward[:type]]
        qty = reward[:quantity].to_i
        return failure(:invalid_quantity, "That reward has an invalid quantity.", :reward => reward) if qty <= 0
        return success(:reward => reward) unless entry[:validate].respond_to?(:call)
        coerce_result(entry[:validate].call(reward, normalize_context(context)), reward)
      rescue Exception => e
        log_exception("Reward validation failed", e)
        failure(:validation_exception, "That reward could not be validated.")
      end

      def validate_all(payloads, context = {})
        rewards = ordered_rewards(normalize_all(payloads))
        return failure(:empty_rewards, "There are no rewards to grant.") if rewards.empty?
        ctx = normalize_context(context)
        ctx[:reward_plan] ||= {}
        rewards.each_with_index do |reward, index|
          ctx[:reward_index] = index
          ctx[:planned_rewards] = rewards
          result = validate(reward, ctx)
          return result unless result.ok?
        end
        success(:details => { :rewards => rewards })
      rescue Exception => e
        log_exception("Reward batch validation failed", e)
        failure(:batch_validation_exception, "The rewards could not be validated.")
      end

      def grant(payload, context = {})
        ctx = normalize_context(context)
        reward = normalize(payload)
        return failed_grant(failure(:unknown_reward, "That reward type is unavailable."), nil, ctx) unless reward
        unless ctx[:skip_validation]
          validation = validate(reward, ctx)
          return failed_grant(validation, reward, ctx) unless validation.ok?
        end
        decision = emit_decision(:reward_grant_requested, reward, ctx)
        if decision == false
          return failed_grant(failure(:cancelled, "The reward was cancelled.", :reward => reward), reward, ctx)
        elsif decision.is_a?(Result) && !decision.ok?
          return failed_grant(decision, reward, ctx)
        end
        entry = @handlers[reward[:type]]
        handler_result = coerce_result(entry[:grant].call(reward, ctx), reward)
        return failed_grant(handler_result, reward, ctx) unless handler_result.ok?
        receipt = handler_result.receipt
        unless receipt.is_a?(Receipt)
          receipt = Receipt.new(reward[:type], reward, handler_result.details[:receipt_data], entry[:owner])
        end
        result = success(
          :reward => reward,
          :receipt => receipt,
          :details => handler_result.details.merge(:receipt => receipt)
        )
        finalize_receipt(receipt, ctx) unless ctx[:defer_finalize]
        unless ctx[:defer_finalize]
          emit(:reward_granted, reward, ctx, result)
          log_info("Reward granted type=#{reward[:type]} source=#{ctx[:source]} #{description(reward)}")
        end
        result
      rescue Exception => e
        log_exception("Reward grant failed", e)
        failed_grant(failure(:grant_exception, "The reward could not be granted."), reward, ctx || {})
      end

      def grant_all(payloads, context = {})
        ctx = normalize_context(context)
        validation = validate_all(payloads, ctx)
        return failed_batch(validation, ctx) unless validation.ok?
        rewards = validation.details[:rewards]
        receipts = []
        applied = []
        rewards.each do |reward|
          result = grant(reward, ctx.merge(:skip_validation => true, :defer_finalize => true))
          unless result.ok?
            rollback_all(receipts, ctx.merge(:source => :reward_batch_rollback))
            return failed_batch(failure(
              result.code,
              result.message,
              :reward => reward,
              :details => result.details.merge(:applied => applied, :receipts => receipts)
            ), ctx)
          end
          receipts << result.receipt
          applied << reward
        end
        finalize_all(receipts, ctx) unless ctx[:defer_finalize]
        success(:details => { :rewards => rewards, :applied => applied, :receipts => receipts })
      rescue Exception => e
        log_exception("Reward batch grant failed", e)
        rollback_all(receipts || [], ctx || {})
        failed_batch(failure(:batch_grant_exception, "The rewards could not be granted."), ctx || {})
      end

      def finalize_all(receipts, context = {})
        ctx = normalize_context(context)
        ok = true
        Array(receipts).each do |receipt|
          next unless receipt.is_a?(Receipt)
          reward = receipt.reward
          ok = false unless finalize_receipt(receipt, ctx)
          result = success(:reward => reward, :receipt => receipt)
          emit(:reward_granted, reward, ctx, result)
          log_info("Reward granted type=#{reward[:type]} source=#{ctx[:source]} #{description(reward)}")
        end
        ok
      rescue Exception => e
        log_exception("Reward batch finalize failed", e)
        false
      end

      def rollback(receipt, context = {})
        return true unless receipt.is_a?(Receipt)
        entry = @handlers[receipt.type]
        return false unless entry
        return true unless entry[:rollback].respond_to?(:call)
        result = entry[:rollback].call(receipt, normalize_context(context))
        ok = result != false && (!result.is_a?(Result) || result.ok?)
        log_info("Reward rolled back type=#{receipt.type} source=#{normalize_context(context)[:source]}") if ok
        ok
      rescue Exception => e
        log_exception("Reward rollback failed type=#{receipt.type rescue :unknown}", e)
        false
      end

      def rollback_all(receipts, context = {})
        ok = true
        Array(receipts).reverse_each { |receipt| ok = false unless rollback(receipt, context) }
        ok
      end

      def expand(payload, multiplier = 1)
        reward = normalize(payload)
        return [] unless reward
        count = [multiplier.to_i, 1].max
        entry = @handlers[reward[:type]]
        if entry[:expand].respond_to?(:call)
          return Array(entry[:expand].call(reward.dup, count)).map { |row| normalize(row) }.compact
        end
        expanded = reward.dup
        expanded[:quantity] = reward[:quantity].to_i * count
        [expanded]
      rescue Exception => e
        log_exception("Reward expansion failed", e)
        []
      end

      def description(payload)
        reward = normalize(payload)
        return "reward=unknown" unless reward
        entry = @handlers[reward[:type]]
        text = entry[:describe].call(reward) if entry[:describe].respond_to?(:call)
        text = "type=#{reward[:type]} quantity=#{reward[:quantity]}" if text.to_s.empty?
        sanitize(text.to_s)
      rescue
        "reward=unknown"
      end

      def label(payload)
        reward = normalize(payload)
        return "Reward" unless reward
        entry = @handlers[reward[:type]]
        text = entry[:label].call(reward) if entry[:label].respond_to?(:call)
        return text.to_s unless text.to_s.empty?
        reward[:type].to_s.split("_").map { |part| part[0, 1].upcase + part[1..-1].to_s }.join(" ")
      rescue
        "Reward"
      end

      def message(payload, result = nil, context = {})
        reward = normalize(payload)
        return "" unless reward
        entry = @handlers[reward[:type]]
        return "" unless entry[:message].respond_to?(:call)
        entry[:message].call(reward, result, normalize_context(context)).to_s
      rescue Exception => e
        log_exception("Reward message failed", e)
        ""
      end

      # Returns the actual leaf rewards represented by one or more receipts.
      # Composite rewards keep their child receipts in :receipts so callers
      # such as Mystery Boxes can reveal what was selected or rolled.
      def revealed_rewards(receipts)
        Array(receipts).each_with_object([]) do |receipt, rewards|
          next unless receipt.is_a?(Receipt)
          data = receipt.data.is_a?(Hash) ? receipt.data : {}
          children = data[:receipts] || data["receipts"]
          if children && !Array(children).empty?
            rewards.concat(revealed_rewards(children))
          elsif receipt.reward
            rewards << receipt.reward
          end
        end
      rescue Exception => e
        log_exception("Reward receipt reveal failed", e)
        []
      end

      def receive_mystery_gift(id)
        return nil unless defined?($Trainer) && $Trainer && $Trainer.respond_to?(:mystery_gifts)
        index = mystery_gift_index(id)
        return nil if index < 0
        gift = $Trainer.mystery_gifts[index]
        payload = gift[2]
        defaults = { :quantity => gift[1] }
        reward = normalize(payload, defaults)
        return nil unless reward
        result = grant(reward, :source => :mystery_gift, :mystery_gift_id => id, :notify => false)
        unless result.ok?
          pbMessage(_INTL(result.message)) if defined?(pbMessage) && !result.message.empty?
          return false
        end
        $Trainer.mystery_gifts[index] = [id]
        text = message(reward, result, :source => :mystery_gift, :mystery_gift_id => id)
        pbMessage(_INTL(text)) if defined?(pbMessage) && !text.empty?
        true
      rescue Exception => e
        log_exception("Mystery Gift reward failed", e)
        false
      end

      def install_mystery_gift_bridge
        if Object.private_method_defined?(:reloaded_rewards_original_pbReceiveMysteryGift) || Object.method_defined?(:reloaded_rewards_original_pbReceiveMysteryGift)
          register_bridge_patch
          return true
        end
        return false unless Object.private_method_defined?(:pbReceiveMysteryGift) || Object.method_defined?(:pbReceiveMysteryGift)
        was_private = Object.private_method_defined?(:pbReceiveMysteryGift)
        Object.class_eval do
          alias_method :reloaded_rewards_original_pbReceiveMysteryGift, :pbReceiveMysteryGift
          def pbReceiveMysteryGift(id)
            handled = Reloaded::Rewards.receive_mystery_gift(id) if defined?(Reloaded::Rewards)
            return handled unless handled.nil?
            reloaded_rewards_original_pbReceiveMysteryGift(id)
          end
          private :pbReceiveMysteryGift if was_private
          private :reloaded_rewards_original_pbReceiveMysteryGift if was_private
        end
        register_bridge_patch
        log_info("Installed Rewards Mystery Gift bridge")
        true
      rescue Exception => e
        log_exception("Rewards Mystery Gift bridge failed", e)
        false
      end

      def success(options = {})
        Result.new(true, options[:code] || :ok, options[:message] || "", options)
      end

      def failure(code, message, options = {})
        Result.new(false, code, message, options)
      end

      private

      def register_builtin_rewards
        register_item_reward unless registered?(:item)
        register_money_reward unless registered?(:money)
      end

      def register_item_reward
        register(
          :item,
          :owner => :reloaded,
          :priority => 100,
          :normalize => proc { |reward| normalize_item_reward(reward) },
          :validate => proc { |reward, context| validate_item_reward(reward, context) },
          :grant => proc { |reward, context| grant_item_reward(reward, context) },
          :rollback => proc { |receipt, _context| rollback_item_reward(receipt) },
          :finalize => proc { |receipt, context| finalize_item_reward(receipt, context) },
          :label => proc { |reward|
            data = resolve_item(reward[:item_id])
            data ? data.name : reward[:item_id].to_s
          },
          :describe => proc { |reward| describe_item_reward(reward) },
          :message => proc { |reward, _result, _context| item_reward_message(reward) }
        )
      end

      def register_money_reward
        register(
          :money,
          :owner => :reloaded,
          :priority => 100,
          :normalize => proc { |reward| reward.merge(:amount => (reward[:amount] || reward[:quantity]).to_i) },
          :validate => proc { |reward, _context|
            if !defined?($Trainer) || !$Trainer
              failure(:trainer_unavailable, "The player is unavailable.", :reward => reward)
            elsif reward[:amount].to_i <= 0
              failure(:invalid_amount, "That money reward has an invalid amount.", :reward => reward)
            else
              success(:reward => reward)
            end
          },
          :grant => proc { |reward, _context|
            before = $Trainer.money.to_i
            $Trainer.money = before + reward[:amount].to_i
            success(:reward => reward, :details => { :receipt_data => { :before => before, :amount => reward[:amount].to_i } })
          },
          :rollback => proc { |receipt, _context|
            next false unless defined?($Trainer) && $Trainer
            $Trainer.money = receipt.data[:before].to_i
            true
          },
          :label => proc { |_reward| _INTL("Money") },
          :describe => proc { |reward| "money=#{reward[:amount].to_i}" },
          :message => proc { |reward, _result, _context| _INTL("\\me[Item get]You received ${1}!\\wtnp[30]", reward[:amount].to_i) }
        )
      end

      def normalize_item_reward(reward)
        item_id = reward[:item_id] || reward[:item] || reward[:id]
        reward.merge(:id => normalize_item_id(item_id), :item_id => normalize_item_id(item_id))
      end

      def validate_item_reward(reward, context)
        data = resolve_item(reward[:item_id])
        return failure(:missing_item, "That item is unavailable.", :reward => reward) unless data
        return failure(:bag_unavailable, "The Bag is unavailable.", :reward => reward) unless defined?($PokemonBag) && $PokemonBag
        qty = reward[:quantity].to_i
        plan = context[:reward_plan]
        if plan.is_a?(Hash) && defined?(ItemStorageHelper)
          pockets = plan[:bag_pockets] ||= duplicate_bag_pockets
          maxsize = simulated_bag_size(pockets, data.pocket)
          stored = ItemStorageHelper.pbStoreItem(pockets[data.pocket], maxsize, bag_max_per_slot, data.id, qty, false)
          return failure(:bag_full, "There isn't enough room in the Bag.", :reward => reward) unless stored
        elsif $PokemonBag.respond_to?(:pbCanStore?) && !$PokemonBag.pbCanStore?(data.id, qty)
          return failure(:bag_full, "There isn't enough room in the Bag.", :reward => reward)
        end
        success(:reward => reward)
      rescue Exception => e
        log_exception("Item reward validation failed", e)
        failure(:bag_preflight_failed, "There isn't enough room in the Bag.", :reward => reward)
      end

      def grant_item_reward(reward, _context)
        data = resolve_item(reward[:item_id])
        qty = reward[:quantity].to_i
        stored = if $PokemonBag.respond_to?(:pbStoreAllOrNone)
                   $PokemonBag.pbStoreAllOrNone(data.id, qty)
                 else
                   $PokemonBag.pbStoreItem(data.id, qty)
                 end
        return failure(:item_grant_failed, "The item could not be added to the Bag.", :reward => reward) unless stored
        success(:reward => reward, :details => { :receipt_data => { :item_id => data.id, :quantity => qty } })
      end

      def rollback_item_reward(receipt)
        return false unless defined?($PokemonBag) && $PokemonBag
        data = receipt.data || {}
        $PokemonBag.pbDeleteItem(data[:item_id], data[:quantity].to_i)
      end

      def finalize_item_reward(receipt, context)
        data = resolve_item((receipt.data || {})[:item_id])
        register_tm_vault_item(data, context[:source]) if data
        true
      end

      def describe_item_reward(reward)
        data = resolve_item(reward[:item_id])
        "item=#{data ? data.id : reward[:item_id]} quantity=#{reward[:quantity].to_i}"
      end

      def item_reward_message(reward)
        data = resolve_item(reward[:item_id])
        return "" unless data
        qty = reward[:quantity].to_i
        item_name = qty > 1 ? data.name_plural : data.name
        if data.id == :LEFTOVERS
          _INTL("\\me[Item get]You obtained some \\c[1]{1}\\c[0]!\\wtnp[30]", item_name)
        elsif data.is_machine?
          _INTL("\\me[Item get]You obtained \\c[1]{1} {2}\\c[0]!\\wtnp[30]", item_name, GameData::Move.get(data.move).name)
        elsif qty > 1
          _INTL("\\me[Item get]You obtained {1} \\c[1]{2}\\c[0]!\\wtnp[30]", qty, item_name)
        elsif item_name.respond_to?(:starts_with_vowel?) && item_name.starts_with_vowel?
          _INTL("\\me[Item get]You obtained an \\c[1]{1}\\c[0]!\\wtnp[30]", item_name)
        else
          _INTL("\\me[Item get]You obtained a \\c[1]{1}\\c[0]!\\wtnp[30]", item_name)
        end
      rescue
        ""
      end

      def reward_hash(payload)
        return symbolize_hash(payload) if payload.is_a?(Hash)
        if payload.is_a?(Symbol) || payload.is_a?(String)
          key = canonical_type(payload)
          return { :type => key } if @handlers.key?(key)
          return { :type => :item, :item_id => payload } if resolve_item(payload)
        end
        nil
      end

      def symbolize_hash(hash)
        hash.each_with_object({}) do |(key, value), result|
          normalized_key = key.to_sym rescue key
          result[normalized_key] = value
        end
      end

      def quantity_for(reward)
        value = reward[:quantity] || reward[:qty] || reward[:amount] || 1
        value.to_i
      rescue
        0
      end

      def normalize_context(context)
        source = context.is_a?(Hash) ? symbolize_hash(context) : {}
        source[:source] = normalize_id(source[:source] || current_owner)
        source[:notify] = !!source[:notify]
        source
      end

      def ordered_rewards(rewards)
        Array(rewards).each_with_index.sort_by do |reward, index|
          entry = @handlers[reward[:type]]
          [entry ? entry[:priority] : 100, index]
        end.map { |pair| pair[0] }
      end

      def coerce_result(value, reward)
        return value if value.is_a?(Result)
        return failure(:handler_rejected, "The reward could not be granted.", :reward => reward) if value == false || value.nil?
        if value.is_a?(Hash)
          options = symbolize_hash(value)
          return failure(options[:code] || :handler_rejected, options[:message] || "The reward could not be granted.", :reward => reward, :details => options) if options[:ok] == false
          return success(:reward => reward, :receipt => options[:receipt], :details => options)
        end
        success(:reward => reward)
      end

      def failed_grant(result, reward, context)
        emit(:reward_grant_failed, reward, context, result)
        log_warning("Reward failed type=#{reward ? reward[:type] : :unknown} source=#{context[:source]} code=#{result.code} message=#{result.message}")
        result
      end

      def failed_batch(result, context)
        log_warning("Reward batch failed source=#{context[:source]} code=#{result.code} message=#{result.message}")
        result
      end

      def emit(event, reward, context, result = nil)
        return 0 unless defined?(Reloaded::Events)
        Reloaded::Events.emit(event, {
          :reward => reward,
          :source => context[:source],
          :context => context,
          :result => result
        })
      rescue
        0
      end

      def emit_decision(event, reward, context)
        return nil unless defined?(Reloaded::Events)
        Reloaded::Events.first_result(event, {
          :reward => reward,
          :source => context[:source],
          :context => context
        })
      rescue
        nil
      end

      def mystery_gift_index(id)
        $Trainer.mystery_gifts.each_with_index do |gift, index|
          return index if gift[0] == id && gift.length > 1
        end
        -1
      end

      def register_install_events
        return unless defined?(Reloaded::Events)
        [:core_loaded, :modules_loaded, :game_data_loaded].each do |event|
          Reloaded::Events.on(event, :reloaded_rewards_mystery_gift_bridge, owner: :reloaded) do |_context|
            install_mystery_gift_bridge
          end
        end
      rescue Exception => e
        log_exception("Rewards install event registration failed", e)
      end

      def register_bridge_patch
        return unless defined?(Reloaded::Patches)
        return if Reloaded::Patches.respond_to?(:registered?) && Reloaded::Patches.registered?(:rewards_mystery_gift_bridge)
        Reloaded::Patches.register(
          :rewards_mystery_gift_bridge,
          :target => "Object#pbReceiveMysteryGift",
          :type => :runtime_method_bridge,
          :file => __FILE__,
          :owner => :reloaded
        )
      rescue
      end

      def remove_aliases_for(type_id)
        @aliases.delete_if { |_alias_id, target| target == type_id }
      end

      def canonical_type(value)
        key = normalize_id(value)
        @aliases[key] || key
      end

      def normalize_id(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "").to_sym
      end

      def normalize_item_id(value)
        data = resolve_item(value)
        data ? data.id : (value.to_sym rescue value)
      end

      def resolve_item(value)
        return nil if value.nil? || value.to_s.empty?
        return nil unless defined?(GameData::Item)
        GameData::Item.try_get(value) rescue nil
      end

      def duplicate_bag_pockets
        $PokemonBag.pockets.map do |pocket|
          Array(pocket).map { |slot| slot ? [slot[0], slot[1]] : nil }
        end
      end

      def simulated_bag_size(pockets, pocket)
        maxsize = $PokemonBag.maxPocketSize(pocket)
        maxsize = pockets[pocket].length + 1 if maxsize < 0
        maxsize
      end

      def bag_max_per_slot
        return ::Settings::BAG_MAX_PER_SLOT.to_i if defined?(::Settings::BAG_MAX_PER_SLOT)
        9999
      rescue
        9999
      end

      def register_tm_vault_item(data, source = :reward)
        return unless defined?(TMVault)
        return unless data.respond_to?(:is_machine?) && data.is_machine? && data.move
        TMVault.register(data.move, :notify => false, :source => source || :reward)
      rescue Exception => e
        log_exception("Reward TM Vault registration failed", e)
      end

      def finalize_receipt(receipt, context)
        return true unless receipt.is_a?(Receipt)
        entry = @handlers[receipt.type]
        return true unless entry && entry[:finalize].respond_to?(:call)
        entry[:finalize].call(receipt, normalize_context(context)) != false
      rescue Exception => e
        log_exception("Reward finalize failed type=#{receipt.type rescue :unknown}", e)
        false
      end

      def public_entry(entry)
        {
          :type => entry[:type],
          :owner => entry[:owner],
          :priority => entry[:priority],
          :aliases => @aliases.select { |_key, value| value == entry[:type] }.keys.sort_by(&:to_s),
          :supports_rollback => entry[:rollback].respond_to?(:call),
          :supports_finalize => entry[:finalize].respond_to?(:call),
          :supports_label => entry[:label].respond_to?(:call),
          :supports_description => entry[:describe].respond_to?(:call)
        }
      end

      def current_owner
        mod_id = Thread.current[:reloaded_mod_id] rescue nil
        mod_id.to_s.empty? ? :reloaded : mod_id
      end

      def sanitize(text)
        return Reloaded::FileActions.sanitize(text) if defined?(Reloaded::FileActions)
        text.to_s
      rescue
        text.to_s
      end

      def log_info(message)
        Reloaded::Log.info(message, :framework) if defined?(Reloaded::Log)
      rescue
      end

      def log_warning(message)
        Reloaded::Log.warning(message, :framework) if defined?(Reloaded::Log)
      rescue
      end

      def log_exception(message, error)
        Reloaded::Log.exception(message, error, :channel => :framework) if defined?(Reloaded::Log)
      rescue
      end
    end
  end

  class << self
    def grant_reward(payload, options = {})
      Rewards.grant(payload, options)
    end

    def grant_rewards(payloads, options = {})
      Rewards.grant_all(payloads, options)
    end
  end
end

Reloaded::Rewards.boot
