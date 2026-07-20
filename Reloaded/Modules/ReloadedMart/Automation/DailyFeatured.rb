#===============================================================================
# Reloaded Mart - Daily Featured
#===============================================================================
# Generates the offline-safe Daily Featured offers used by Reloaded Mart.
# Keep owner-controlled exclusions and policy limits together at the top.

module ReloadedMart
  module DailyFeatured
    GAME_ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", ".."))
    COMPILED_ITEMS_FILE = File.join(GAME_ROOT, "Data", "items.dat")

    ITEM_BLACKLIST = [
      :MASTERBALL,
      :RARECANDY,
      :ABILITYCAPSULE,
      :ABILITYPATCH,
      :EXPALL,
      :EXPSHARE,
      :LUCKYEGG,
      :LEFTOVERS,
      :SACREDSHARD
    ].freeze

    # Trusted HR-added items listed here may enter automatic offline offers.
    # Other Data Patch/runtime item additions remain excluded.
    ADDED_ITEM_ALLOWLIST = [
    ].freeze

    DEFAULT_OFFER_COUNT = 3
    MINIMUM_DISCOUNT = 0
    STANDARD_DISCOUNT_MAXIMUM = 39
    HIGH_DISCOUNT_MINIMUM = 40
    MAXIMUM_DISCOUNT = 100
    DEFAULT_MINIMUM_DISCOUNT = 5
    DEFAULT_MAXIMUM_DISCOUNT = 50
    DEFAULT_HIGH_DISCOUNT_LIMIT = 1
    REPEAT_BLOCK_DAYS = 3
    TRUSTED_CLOCK_STATE_KEY = "trusted_clock"
    CATEGORY_ID = "featured"
    CATEGORY_NAME = "FEATURED"
    POOL_ID = "game_items"

    DEFAULT_CONFIG = {
      "enabled" => true,
      "count" => DEFAULT_OFFER_COUNT,
      "discount_min_percent" => DEFAULT_MINIMUM_DISCOUNT,
      "discount_max_percent" => DEFAULT_MAXIMUM_DISCOUNT,
      "high_discount_limit" => DEFAULT_HIGH_DISCOUNT_LIMIT,
      "category_id" => CATEGORY_ID,
      "category_name" => CATEGORY_NAME,
      "pool" => POOL_ID,
      "stock" => nil,
      "stock_reset" => "daily",
      "blacklist" => []
    }.freeze

    class << self
      def entries(catalog_entries = nil, context = {}, config_override = nil)
        config = configuration(config_override)
        return [] unless enabled?(config)
        ids = item_ids(catalog_entries, context, config)
        generated = ids.map { |item_id| build_entry(item_id, config) }.compact
        log_generation(config, ids, generated, context)
        generated
      rescue Exception => e
        ReloadedMart.log_exception("Daily featured entry generation failed", e)
        []
      end

      def preview(config_override = nil, catalog_entries = nil, context = {})
        config = configuration(config_override)
        preview_context = context.merge(:preview_catalog => true)
        generated = entries(catalog_entries, preview_context, config)
        generated_item_ids = generated.map { |entry| entry_item_id(entry) }
        preview_context = preview_context.merge(:daily_featured_item_ids => generated_item_ids)
        pool = item_pool(config, catalog_entries, preview_context)
        rows = generated.map do |entry|
          raw = entry.raw.is_a?(Hash) ? entry.raw : {}
          item_id = (raw["item"] || entry.id).to_s
          item = GameData::Item.try_get(item_id) rescue nil
          base = item ? item.price.to_i : 0
          discount = discount_percent(config, preview_context, entry)
          {
            :entry => entry,
            :item_id => item_id,
            :name => item ? item.name.to_s : entry.name.to_s,
            :base_price => base,
            :discount_percent => discount,
            :deep_discount => discount >= HIGH_DISCOUNT_MINIMUM,
            :final_price => (base * (100 - discount) / 100.0).round,
            :stock => stock(config)
          }
        end
        {
          :day_key => day_key(preview_context),
          :candidate_count => pool.length,
          :excluded_count => exclusion_snapshot(config, catalog_entries, preview_context)[:all].length,
          :rows => rows
        }
      rescue Exception => e
        ReloadedMart.log_exception("Daily featured preview failed", e)
        { :day_key => day_key(context), :candidate_count => 0, :excluded_count => 0, :rows => [] }
      end

      def configuration(override = nil)
        configured = override
        if configured.nil? && defined?(ReloadedMart::Source) && ReloadedMart::Source.curated_available?
          raw = ReloadedMart::Source.active_raw || {}
          configured = raw["daily_featured"] || raw[:daily_featured]
        end
        return DEFAULT_CONFIG.merge("enabled" => false) if configured == false
        return deep_copy(DEFAULT_CONFIG) unless configured.is_a?(Hash)
        config = deep_copy(DEFAULT_CONFIG).merge(stringify_hash(configured))
        if config.key?("discount_percent") && !configured.key?("discount_min_percent") && !configured.key?(:discount_min_percent)
          config["discount_min_percent"] = config["discount_percent"].to_i
        end
        if config.key?("discount_percent") && !configured.key?("discount_max_percent") && !configured.key?(:discount_max_percent)
          config["discount_max_percent"] = config["discount_percent"].to_i
        end
        config
      rescue
        deep_copy(DEFAULT_CONFIG)
      end

      def enabled?(config = nil)
        config = configuration if config.nil?
        return false if config == false
        return true unless config.is_a?(Hash) && config.key?("enabled")
        ReloadedMart::Rules.truthy?(config["enabled"])
      rescue
        false
      end

      def item_ids(catalog_entries = nil, context = {}, config_override = nil)
        config = config_override.is_a?(Hash) ? configuration(config_override) : configuration
        cache_key = selection_cache_key(config, catalog_entries, context)
        if @selection_cache && @selection_cache[:key] == cache_key
          return Array(@selection_cache[:ids])
        end
        candidates = item_pool(config, catalog_entries, context)
        count = [(config["count"] || DEFAULT_OFFER_COUNT).to_i, 1].max
        ids = select_for_day(candidates, count, day_key(context), catalog_version(context))
        @selection_cache = { :key => cache_key, :ids => ids }
        ids
      rescue Exception => e
        ReloadedMart.log_exception("Daily featured item selection failed", e)
        []
      end

      def select_for_day(candidates, count, date_key, version)
        count = [count.to_i, 1].max
        ordered = Array(candidates).map(&:to_s).uniq.sort_by do |item_id|
          deterministic_score("#{version}:daily_featured_pool:#{item_id}")
        end
        return [] if ordered.empty?
        group_count = [ordered.length / count, 1].max
        groups = Array.new(group_count) { [] }
        ordered.each_with_index { |item_id, index| groups[index % group_count] << item_id }
        day = day_number(date_key)
        group = groups[day % group_count]
        cycle = day / group_count
        offset = group.empty? ? 0 : cycle % group.length
        group.rotate(offset).first(count)
      rescue
        Array(candidates).first(count)
      end

      def day_number(date_key)
        match = /\A(\d{4})-(\d{2})-(\d{2})\z/.match(date_key.to_s)
        return 0 unless match
        (Time.utc(match[1].to_i, match[2].to_i, match[3].to_i).to_i / 86_400).to_i
      rescue
        0
      end

      def item_pool(config = nil, catalog_entries = nil, context = {})
        config = configuration if config.nil?
        exclusions = exclusion_snapshot(config, catalog_entries, context)
        key = pool_cache_key(config, exclusions, context)
        if @pool_cache && @pool_cache[:key] == key
          return Array(@pool_cache[:items])
        end
        items = []
        each_game_item do |item|
          next unless item_allowed?(item, exclusions[:all])
          next if active_global_discount_for_generated_item?(item, config, context)
          items << item.id.to_s
        end
        log_pool(items.length, exclusions[:all].length, context)
        @pool_cache = { :key => key, :items => items }
        items
      rescue Exception => e
        ReloadedMart.log_exception("Daily featured item pool failed", e)
        []
      end

      def exclusion_snapshot(config, catalog_entries = nil, context = {})
        configured = blacklist(config)
        modded = mod_added_item_ids
        curated = curated_featured_item_ids(catalog_entries, config, context)
        discounted = discounted_catalog_item_ids(catalog_entries, context)
        {
          :configured => configured,
          :modded => modded,
          :curated => curated,
          :discounted => discounted,
          :all => (configured + modded + curated + discounted).map(&:to_s).uniq
        }
      rescue
        { :configured => [], :modded => [], :curated => [], :discounted => [], :all => [] }
      end

      def blacklist(config = nil)
        config = configuration if config.nil?
        values = ITEM_BLACKLIST.map(&:to_s)
        values.concat(Array(config["blacklist"] || config[:blacklist]).map(&:to_s)) if config.is_a?(Hash)
        values.reject(&:empty?).uniq
      end

      def mod_added_item_ids
        patches = if defined?(Reloaded::DataPatches)
                    Reloaded::DataPatches.applied_all("items") rescue []
                  else
                    []
                  end
        added = Array(patches).select do |patch|
          patch.is_a?(Hash) && patch[:operation].to_s == "add"
        end.map { |patch| patch[:id].to_s }.reject(&:empty?).uniq
        compiled = compiled_base_item_ids
        unless compiled.empty?
          current = []
          each_game_item { |item| current << item.id.to_s if item && item.respond_to?(:id) }
          added.concat(current.reject { |item_id| compiled.include?(item_id) })
        end
        allowed = added_item_allowlist
        added.uniq.reject { |item_id| allowed.include?(item_id.to_s) }
      rescue
        []
      end

      def added_item_allowlist
        ADDED_ITEM_ALLOWLIST.map(&:to_s).reject(&:empty?).uniq
      rescue
        []
      end

      def compiled_base_item_ids
        return @compiled_base_item_ids if @compiled_base_item_ids
        @compiled_base_item_ids = []
        return @compiled_base_item_ids unless File.file?(COMPILED_ITEMS_FILE)
        raw = File.open(COMPILED_ITEMS_FILE, "rb") { |file| file.read }
        data = nil
        if defined?(Encryption) && Encryption.respond_to?(:xor)
          begin
            data = Marshal.load(Encryption.xor(raw))
          rescue TypeError, ArgumentError
          end
        end
        data = Marshal.load(raw) unless data
        return @compiled_base_item_ids unless data.is_a?(Hash)
        @compiled_base_item_ids = data.values.map do |item|
          item.id.to_s if item && item.respond_to?(:id)
        end.compact.uniq
      rescue
        @compiled_base_item_ids = []
      end

      def curated_featured_item_ids(catalog_entries, config, context = {})
        entries = catalog_entries_for_rules(catalog_entries, context)
        featured_id = category_id(config)
        entries.map do |entry|
          next nil unless entry
          ids = entry.respond_to?(:category_ids) ? Array(entry.category_ids).map(&:to_s) : []
          ids << entry.category_id.to_s if entry.respond_to?(:category_id)
          next nil unless ids.include?(featured_id)
          entry_item_id(entry)
        end.compact.uniq
      rescue
        []
      end

      def discounted_catalog_item_ids(catalog_entries, context = {})
        catalog_entries_for_rules(catalog_entries, context).map do |entry|
          next nil unless entry && entry.kind == :item
          discounted_catalog_entry?(entry, context) ? entry_item_id(entry) : nil
        end.compact.uniq
      rescue
        []
      end

      def discounted_catalog_entry?(entry, context = {})
        base = ReloadedMart::Pricing.base_price(entry, context)
        catalog_price = ReloadedMart::Pricing.catalog_price(entry, base, context)
        current = catalog_price.to_i
        global_discount_modifiers(entry, context).any? do |modifier|
          changed = ReloadedMart::Pricing.apply_modifier(current, modifier)
          discounted = changed.to_i < current.to_i
          current = changed.to_i
          discounted
        end
      rescue
        false
      end

      def active_global_discount_for_generated_item?(item, config, context = {})
        entry = build_entry(item.id, config)
        return false unless entry
        current = item.price.to_i
        global_discount_modifiers(entry, context).any? do |modifier|
          changed = ReloadedMart::Pricing.apply_modifier(current, modifier)
          discounted = changed.to_i < current.to_i
          current = changed.to_i
          discounted
        end
      rescue
        false
      end

      def global_discount_modifiers(entry, context = {})
        result = ReloadedMart::Pricing.entry_modifiers(entry, context)
        raw_catalog = catalog_hash(context)
        Array(raw_catalog["economy_events"] || raw_catalog[:economy_events]).each do |event|
          next unless event.is_a?(Hash)
          next unless ReloadedMart::Economy.event_active?(event, context)
          Array(event["modifiers"] || event[:modifiers]).each do |modifier|
            next unless modifier.is_a?(Hash)
            next unless ReloadedMart::Economy.modifier_applies?(modifier, entry, context)
            result << ReloadedMart::Economy.normalize_modifier(modifier, event)
          end
        end
        result.compact
      rescue
        []
      end

      def catalog_entries_for_rules(catalog_entries, context = {})
        return Array(catalog_entries) if context[:preview_catalog]
        return [] unless defined?(ReloadedMart::Source) && ReloadedMart::Source.curated_available?
        Array(catalog_entries.nil? ? ReloadedMart::Source.active_catalog : catalog_entries)
      rescue
        []
      end

      def catalog_hash(context = {})
        value = context[:catalog]
        return value if value.is_a?(Hash)
        return {} unless defined?(ReloadedMart::Source) && ReloadedMart::Source.curated_available?
        ReloadedMart::Source.active_raw || {}
      rescue
        {}
      end

      def item_allowed?(item, exclusions = [])
        return false unless item
        return false if Array(exclusions).include?(item.id.to_s)
        return false if item.respond_to?(:is_important?) && item.is_important?
        return false if item.respond_to?(:is_key_item?) && item.is_key_item?
        return false if item.respond_to?(:is_TM?) && item.is_TM?
        return false if item.respond_to?(:is_HM?) && item.is_HM?
        return false if item.respond_to?(:is_TR?) && item.is_TR?
        return false if item.price.to_i <= 0
        true
      rescue
        false
      end

      def each_game_item
        if GameData::Item.respond_to?(:each)
          GameData::Item.each { |item| yield item }
          return
        end
        if GameData::Item.respond_to?(:list_all)
          seen = {}
          GameData::Item.list_all.each_value do |item|
            next unless item && item.respond_to?(:id)
            next if seen[item.id]
            seen[item.id] = true
            yield item
          end
        end
      rescue Exception => e
        ReloadedMart.log_exception("Daily featured item enumeration failed", e)
      end

      def build_entry(item_id, config)
        item = GameData::Item.try_get(item_id) rescue nil
        return nil unless item
        raw = {
          "id" => entry_id_for(item.id),
          "kind" => "item",
          "item" => item.id.to_s,
          "name" => item.name,
          "category_id" => category_id(config),
          "category_name" => category_name(config),
          "tags" => ["featured", "daily_featured"],
          "daily_featured_pool" => true,
          "entry_version" => 1,
          "online_policy" => "offline_allowed",
          "source_type" => "automated",
          "stock" => stock(config),
          "stock_reset" => stock_reset(config)
        }
        ReloadedMart::CatalogEntry.new(
          :id => raw["id"],
          :kind => raw["kind"],
          :name => raw["name"],
          :category_id => raw["category_id"],
          :category_name => raw["category_name"],
          :tags => raw["tags"],
          :stock => raw["stock"],
          :stock_reset => raw["stock_reset"],
          :currency => :money,
          :entry_version => raw["entry_version"],
          :online_policy => raw["online_policy"],
          :source_type => raw["source_type"],
          :raw => raw
        )
      end

      def discount_percent(config, context = {}, entry = nil)
        min, max = discount_range(config)
        item_key = discount_key(entry)
        if high_discount_item_ids(config, context).include?(item_key) && max >= HIGH_DISCOUNT_MINIMUM
          floor = [min, HIGH_DISCOUNT_MINIMUM].max
          ceiling = max
        else
          floor = [min, STANDARD_DISCOUNT_MAXIMUM].min
          ceiling = [max, STANDARD_DISCOUNT_MAXIMUM].min
        end
        ceiling = floor if ceiling < floor
        span = ceiling - floor + 1
        seed = "#{catalog_version(context)}:#{day_key(context)}:daily_featured_discount:#{item_key}"
        floor + (deterministic_score(seed) % span)
      rescue
        DEFAULT_MINIMUM_DISCOUNT
      end

      def discount_range(config = nil)
        config = configuration if config.nil?
        min = (config["discount_min_percent"] || DEFAULT_MINIMUM_DISCOUNT).to_i
        max = (config["discount_max_percent"] || DEFAULT_MAXIMUM_DISCOUNT).to_i
        min, max = max, min if min > max
        min = [[min, MINIMUM_DISCOUNT].max, MAXIMUM_DISCOUNT].min
        max = [[max, MINIMUM_DISCOUNT].max, MAXIMUM_DISCOUNT].min
        max = min if max < min
        [min, max]
      end

      def high_discount_item_ids(config = nil, context = {})
        config = configuration if config.nil?
        _min, max = discount_range(config)
        return [] if max < HIGH_DISCOUNT_MINIMUM
        limit = [[(config["high_discount_limit"] || DEFAULT_HIGH_DISCOUNT_LIMIT).to_i, 0].max, 99].min
        return [] if limit <= 0
        ids = Array(context[:daily_featured_item_ids]).map(&:to_s).reject(&:empty?)
        ids = item_ids(nil, context, config) if ids.empty?
        seed = "#{catalog_version(context)}:#{day_key(context)}:daily_featured_high_discount"
        ids.sort_by { |item_id| deterministic_score("#{seed}:#{item_id}") }.first(limit)
      rescue
        []
      end

      def modifier(entry, context = {})
        value = discount_percent(configuration, context, entry)
        return nil if value.to_i <= 0
        {
          :id => "daily_featured",
          :label => "Daily Featured",
          :type => "percent",
          :value => -value.to_i.abs,
          :source => "daily_featured"
        }
      end

      def featured?(entry, context = {})
        return false unless entry && enabled?(configuration)
        raw = entry.raw.is_a?(Hash) ? entry.raw : {}
        return true if ReloadedMart::Rules.truthy?(raw["daily_featured_pool"] || raw[:daily_featured_pool])
        entry_ids(nil, context).include?(entry.id.to_s)
      rescue
        false
      end

      def entry_ids(catalog_entries = nil, context = {})
        entries(catalog_entries, context).map(&:id)
      rescue
        []
      end

      def entry_id(catalog_entries = nil, context = {})
        entry_ids(catalog_entries, context).first
      rescue
        nil
      end

      def category_id(config = nil)
        config = configuration if config.nil?
        (config["category_id"] || CATEGORY_ID).to_s
      end

      def category_name(config = nil)
        config = configuration if config.nil?
        (config["category_name"] || CATEGORY_NAME).to_s
      end

      def stock(config = nil)
        config = configuration if config.nil?
        value = config["stock"] || config[:stock]
        return nil if value.nil? || value.to_s.empty?
        quantity = value.to_i
        quantity > 0 ? quantity : nil
      rescue
        nil
      end

      def stock_reset(config = nil)
        config = configuration if config.nil?
        value = (config["stock_reset"] || config[:stock_reset] || "daily").to_s
        ReloadedMart::STOCK_RESET_RULES.include?(value.to_sym) ? value : "daily"
      rescue
        "daily"
      end

      def entry_id_for(item_id)
        "daily_featured:#{item_id}"
      end

      def discount_key(entry)
        return "global" unless entry
        raw = entry.raw.is_a?(Hash) ? entry.raw : {}
        (raw["item"] || raw[:item] || entry.id || "global").to_s
      rescue
        "global"
      end

      def entry_item_id(entry)
        raw = entry.raw.is_a?(Hash) ? entry.raw : {}
        (raw["item"] || raw[:item] || entry.id).to_s
      rescue
        entry.id.to_s
      end

      def day_key(context = {}, days_ago = 0)
        value = context.key?(:now) ? context[:now] : trusted_time
        time = eastern_time(value)
        time -= days_ago.to_i * 86_400
        "%04d-%02d-%02d" % [time.year, time.month, time.day]
      rescue
        "unknown"
      end

      def record_trusted_server_time(server_time, observed_at = Time.now)
        server_epoch = time_epoch(server_time)
        return false if server_epoch <= 0
        observed_epoch = time_epoch(observed_at)
        observed_epoch = Time.now.to_i if observed_epoch <= 0
        clock = {
          "server_time" => server_epoch,
          "observed_at" => observed_epoch,
          "last_effective_time" => server_epoch,
          "last_day_key" => eastern_date_key(Time.at(server_epoch)),
          "source" => "remote_http_date"
        }
        write_trusted_clock_state(clock)
        set_trusted_runtime_anchor(server_epoch, clock)
        clear_time_sensitive_caches
        ReloadedMart.log_info("Daily featured trusted clock synchronized day=#{clock["last_day_key"]}")
        true
      rescue Exception => e
        ReloadedMart.log_exception("Daily featured trusted clock synchronization failed", e)
        false
      end

      def trusted_time(value = Time.now)
        clock = trusted_clock_state
        server_epoch = clock["server_time"].to_i
        return value if server_epoch <= 0
        signature = trusted_clock_signature(clock)
        if @trusted_clock_signature != signature || !@trusted_clock_anchor
          observed_epoch = clock["observed_at"].to_i
          observed_epoch = time_epoch(value) if observed_epoch <= 0
          elapsed = [time_epoch(value) - observed_epoch, 0].max
          effective = server_epoch + elapsed
          effective = [effective, clock["last_effective_time"].to_i].max
          set_trusted_runtime_anchor(effective, clock)
        end
        elapsed = [monotonic_seconds - @trusted_clock_anchor[:monotonic], 0.0].max
        effective_epoch = @trusted_clock_anchor[:time].to_f + elapsed
        remember_effective_time(effective_epoch.to_i, clock)
        Time.at(effective_epoch)
      rescue
        value
      end

      def trusted_clock?
        trusted_clock_state["server_time"].to_i > 0
      rescue
        false
      end

      def eastern_time(value = Time.now)
        utc = value.respond_to?(:getutc) ? value.getutc : Time.now.getutc
        offset = eastern_daylight_time?(utc) ? -4 * 3600 : -5 * 3600
        utc + offset
      rescue
        value
      end

      def eastern_daylight_time?(utc)
        year = utc.year
        march_day = nth_sunday(year, 3, 2)
        november_day = nth_sunday(year, 11, 1)
        starts = Time.utc(year, 3, march_day, 7, 0, 0)
        ends = Time.utc(year, 11, november_day, 6, 0, 0)
        utc >= starts && utc < ends
      rescue
        false
      end

      def nth_sunday(year, month, occurrence)
        first = Time.utc(year, month, 1)
        first_sunday = 1 + ((7 - first.wday) % 7)
        first_sunday + (occurrence.to_i - 1) * 7
      end

      def eastern_date_key(value)
        time = eastern_time(value)
        "%04d-%02d-%02d" % [time.year, time.month, time.day]
      rescue
        "unknown"
      end

      def trusted_clock_state
        featured = ReloadedMart.state(:daily_featured, {})
        return {} unless featured.is_a?(Hash)
        clock = featured[TRUSTED_CLOCK_STATE_KEY] || featured[TRUSTED_CLOCK_STATE_KEY.to_sym]
        clock.is_a?(Hash) ? stringify_hash(clock) : {}
      rescue
        {}
      end

      def write_trusted_clock_state(clock)
        featured = ReloadedMart.state(:daily_featured, {})
        featured = {} unless featured.is_a?(Hash)
        featured = deep_copy(featured)
        featured[TRUSTED_CLOCK_STATE_KEY] = stringify_hash(clock)
        ReloadedMart.set_state(:daily_featured, featured)
      end

      def remember_effective_time(epoch, clock)
        current_day = eastern_date_key(Time.at(epoch))
        return if current_day == clock["last_day_key"].to_s
        updated = stringify_hash(clock)
        updated["last_effective_time"] = epoch.to_i
        updated["last_day_key"] = current_day
        write_trusted_clock_state(updated)
        @trusted_clock_signature = trusted_clock_signature(updated)
      rescue
      end

      def set_trusted_runtime_anchor(epoch, clock)
        @trusted_clock_anchor = {
          :time => epoch.to_f,
          :monotonic => monotonic_seconds
        }
        @trusted_clock_signature = trusted_clock_signature(clock)
      end

      def trusted_clock_signature(clock)
        [
          clock["server_time"].to_i,
          clock["observed_at"].to_i,
          clock["last_effective_time"].to_i,
          clock["last_day_key"].to_s
        ].join(":")
      rescue
        ""
      end

      def monotonic_seconds
        if Process.respond_to?(:clock_gettime) && defined?(Process::CLOCK_MONOTONIC)
          return Process.clock_gettime(Process::CLOCK_MONOTONIC).to_f
        end
        if defined?(Graphics) && Graphics.respond_to?(:frame_count)
          rate = Graphics.respond_to?(:frame_rate) ? Graphics.frame_rate.to_f : 40.0
          rate = 40.0 if rate <= 0
          return Graphics.frame_count.to_f / rate
        end
        Time.now.to_f
      rescue
        Time.now.to_f
      end

      def time_epoch(value)
        return value.to_i if value.is_a?(Numeric)
        return value.to_i if value.respond_to?(:to_i)
        0
      rescue
        0
      end

      def clear_time_sensitive_caches
        @selection_cache = nil
        @pool_cache = nil
        @pool_log_key = nil
        @generation_log_key = nil
      end

      def catalog_version(context = {})
        configured = context[:catalog_version]
        return configured.to_s unless configured.nil? || configured.to_s.empty?
        raw = context[:catalog]
        if raw.is_a?(Hash)
          configured = raw["catalog_version"] || raw[:catalog_version]
          return configured.to_s unless configured.nil? || configured.to_s.empty?
        end
        report = ReloadedMart::Source.active_report if defined?(ReloadedMart::Source)
        report && report.catalog_version ? report.catalog_version.to_s : ReloadedMart::DEFAULT_CATALOG_VERSION
      rescue
        ReloadedMart::DEFAULT_CATALOG_VERSION
      end

      def selection_cache_key(config, catalog_entries, context)
        exclusions = exclusion_snapshot(config, catalog_entries, context)
        [
          catalog_version(context),
          day_key(context),
          config_cache_key(config),
          exclusions[:all].sort.join(",")
        ].join("|")
      end

      def pool_cache_key(config, exclusions, context)
        [
          catalog_version(context),
          day_key(context),
          config_cache_key(config),
          exclusions[:all].sort.join(","),
          active_event_fingerprint(context)
        ].join("|")
      end

      def config_cache_key(config)
        keys = %w[enabled count discount_min_percent discount_max_percent high_discount_limit category_id category_name stock stock_reset]
        parts = keys.map { |key| "#{key}=#{config[key].inspect}" }
        parts << "blacklist=#{blacklist(config).sort.join(",")}"
        parts.join(";")
      rescue
        config.inspect
      end

      def active_event_fingerprint(context = {})
        catalog = catalog_hash(context)
        Array(catalog["economy_events"] || catalog[:economy_events]).select do |event|
          event.is_a?(Hash) && ReloadedMart::Economy.event_active?(event, context)
        end.map { |event| (event["id"] || event[:id] || event.inspect).to_s }.sort.join(",")
      rescue
        ""
      end

      def deterministic_score(text)
        text.to_s.bytes.inject(2_166_136_261) do |hash, byte|
          ((hash ^ byte) * 16_777_619) & 0xffffffff
        end
      end

      def stringify_hash(hash)
        hash.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
      rescue
        {}
      end

      def deep_copy(value)
        Marshal.load(Marshal.dump(value))
      rescue
        value.dup rescue value
      end

      def log_pool(count, exclusion_count, context = {})
        key = "#{catalog_version(context)}:#{day_key(context)}:pool:#{count}:#{exclusion_count}"
        return if @pool_log_key == key
        @pool_log_key = key
        if count.to_i <= 0
          ReloadedMart.log_warning("Daily featured item pool is empty exclusions=#{exclusion_count}")
        else
          ReloadedMart.log_debug("Daily featured item pool count=#{count} exclusions=#{exclusion_count}")
        end
      rescue
      end

      def log_generation(config, ids, generated, context = {})
        key = "#{catalog_version(context)}:#{day_key(context)}:generated:#{Array(ids).join(",")}:#{generated.length}"
        return if @generation_log_key == key
        @generation_log_key = key
        if generated.empty?
          ReloadedMart.log_warning("Daily featured generated no entries count=#{config["count"]}")
        else
          ReloadedMart.log_info("Daily featured generated entries=#{generated.length} selected=#{generated.map(&:id).join(",")}")
        end
      rescue
      end
    end
  end

  module Economy
    class << self
      def daily_featured_entries(entries = nil, context = {})
        ReloadedMart::DailyFeatured.entries(entries, context)
      end

      def daily_featured_item_ids(entries = nil, context = {})
        ReloadedMart::DailyFeatured.item_ids(entries, context)
      end

      def daily_featured_day_key(context = {})
        ReloadedMart::DailyFeatured.day_key(context)
      end

      def daily_featured_entry_ids(entries = nil, context = {})
        ReloadedMart::DailyFeatured.entry_ids(entries, context)
      end

      def daily_featured_entry_id(entries = nil, context = {})
        ReloadedMart::DailyFeatured.entry_id(entries, context)
      end

      def daily_featured?(entry, context = {})
        ReloadedMart::DailyFeatured.featured?(entry, context)
      end

      def daily_featured_modifier(entry, context = {})
        ReloadedMart::DailyFeatured.modifier(entry, context)
      end

      def daily_featured_config
        ReloadedMart::DailyFeatured.configuration
      end

      def daily_featured_discount_percent(config, context = {}, entry = nil)
        ReloadedMart::DailyFeatured.discount_percent(config, context, entry)
      end

      def daily_featured_enabled?(config)
        ReloadedMart::DailyFeatured.enabled?(config)
      end

      def daily_featured_automation_enabled?
        ReloadedMart::DailyFeatured.enabled?(ReloadedMart::DailyFeatured.configuration)
      end

      def daily_featured_game_item_pool?(_config)
        true
      end

      def daily_featured_category_id(config)
        ReloadedMart::DailyFeatured.category_id(config)
      end

      def daily_featured_category_name(config)
        ReloadedMart::DailyFeatured.category_name(config)
      end

      def daily_featured_stock(config)
        ReloadedMart::DailyFeatured.stock(config)
      end

      def daily_featured_stock_reset(config)
        ReloadedMart::DailyFeatured.stock_reset(config)
      end

      def daily_featured_entry_id_for(item_id)
        ReloadedMart::DailyFeatured.entry_id_for(item_id)
      end

      def daily_featured_item_pool(config)
        ReloadedMart::DailyFeatured.item_pool(config)
      end

      def daily_featured_item_allowed?(item, blacklist)
        ReloadedMart::DailyFeatured.item_allowed?(item, blacklist)
      end

      def daily_featured_blacklist(config)
        ReloadedMart::DailyFeatured.blacklist(config)
      end
    end
  end
end
