#======================================================
# Reloaded Mart
# Author: Stonewall
#======================================================
# Online-catalog mart system using the Reloaded full-screen mart interface.
#
# Responsibilities:
#   - Provide the Reloaded Mart module entry point.
#   - Store Mart runtime state inside the Reloaded save bucket.
#   - Define normalized backend objects for catalog, pricing, carts, stock,
#     availability, validation, and transactions.
#   - Register player-facing Mart options.
#   - Expose public events for future systems such as TM Vault, quests, and
#     economy events.
#   - Keep the UI/backend ready for the REX mart screens.
#
#======================================================

begin
  require "json"
rescue Exception
end

module Reloaded
  module MartFeature
    class << self
      def install
        install_pokemon_system_settings
        register_options
        ReloadedMart.register_patch_points if defined?(ReloadedMart)
        ReloadedMart.register_builtin_entry_handlers if defined?(ReloadedMart)
        ReloadedMart.log_info("Installed Reloaded Mart foundation") if defined?(ReloadedMart)
        true
      rescue Exception => e
        Reloaded::Log.exception("Reloaded Mart install failed", e, channel: :modules) if defined?(Reloaded::Log)
        false
      end

      def install_pokemon_system_settings
        return unless defined?(PokemonSystem)
        PokemonSystem.class_eval do
          def hr_mart_confirm
            @hr_mart_confirm.nil? ? 1 : @hr_mart_confirm.to_i
          end

          def hr_mart_confirm=(value)
            @hr_mart_confirm = value.to_i
          end

          def hr_mart_box_animation
            @hr_mart_box_animation.nil? ? 1 : @hr_mart_box_animation.to_i
          end

          def hr_mart_box_animation=(value)
            @hr_mart_box_animation = value.to_i
          end
        end
      end

      def register_options
        return unless defined?(Reloaded::Options) && Reloaded::Options.respond_to?(:register_category_option)
        Reloaded::Options.register_category_option("RELOADED", :reloaded_mart_options, priority: 4) do |_scene|
          [ActionButton.new(
            _INTL("Reloaded Mart"),
            proc { ReloadedMart.open_options if defined?(ReloadedMart) },
            _INTL("Open Reloaded Mart options.")
          )]
        end
      rescue Exception => e
        Reloaded::Log.exception("Failed to register Reloaded Mart options", e, channel: :options) if defined?(Reloaded::Log)
      end
    end
  end
end

module ReloadedMart
  # -- Config ---------------------------------------------------------------
  SAVE_SYSTEM = :reloaded_mart
  SCHEMA_VERSION = 1
  DEFAULT_CATALOG_VERSION = "none"
  ONLINE_CATALOG_URL = "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/main/Reloaded/ReloadedMartOnline.json"
  DEFAULT_DAILY_FEATURED = {
    "enabled" => true,
    "count" => 2,
    "discount_min_percent" => 10,
    "discount_max_percent" => 40,
    "category_id" => "featured",
    "category_name" => "FEATURED",
    "pool" => "game_items",
    "stock" => nil,
    "stock_reset" => "daily",
    "blacklist" => []
  }.freeze
  # Explicit high-value exclusions. The complete generated-pool filter also
  # rejects key items, TMs/HMs/TRs, important/untossable items, and 0-price data.
  DAILY_FEATURED_ITEM_BLACKLIST = [
    :MASTERBALL, :RARECANDY, :ABILITYCAPSULE, :ABILITYPATCH,
    :EXPALL, :EXPSHARE, :LUCKYEGG, :LEFTOVERS,
    :SACREDSHARD
  ].freeze
  CURRENCY_SYMBOLS = {
    :money => "$"
  }.freeze
  DEFAULT_AUTOMATION = {
    "enabled" => true,
    "daily_featured" => true,
    "economy_events" => true,
    "profile_tuning" => true,
    "restocks" => true
  }.freeze

  ENTRY_KINDS = [:item, :bundle, :gift, :service, :unlock, :coupon].freeze
  STOCK_RESET_RULES = [:never, :daily, :weekly, :monthly, :catalog_version, :stock_epoch].freeze
  DEFAULT_BAG_MAX_PER_SLOT = 9999
  PROMO_CODE_DURATION_SECONDS = 300

  EVENT_PURCHASE_VALIDATED = :reloaded_mart_purchase_validated
  EVENT_PURCHASE_COMPLETED = :reloaded_mart_purchase_completed
  EVENT_PURCHASE_FAILED    = :reloaded_mart_purchase_failed
  EVENT_SALE_COMPLETED     = :reloaded_mart_sale_completed
  EVENT_SALE_FAILED        = :reloaded_mart_sale_failed
  EVENT_STOCK_CHANGED      = :reloaded_mart_stock_changed
  EVENT_CATALOG_LOADED     = :reloaded_mart_catalog_loaded
  EVENT_CATALOG_FAILED     = :reloaded_mart_catalog_failed

  @entry_handlers = {}
  @price_modifier_handlers = []
  @patches_registered = false

  class CatalogEntry
    attr_accessor :id, :kind, :name, :category_id, :category_ids, :category_name, :tags,
                  :price, :sell_price, :currency, :stock, :stock_reset,
                  :availability, :limits, :display, :dependencies, :grants,
                  :raw

    def initialize(attrs = {})
      @id            = attrs[:id].to_s
      @kind          = normalize_kind(attrs[:kind])
      @name          = attrs[:name].to_s
      @category_ids  = normalize_category_ids(attrs[:category_ids], attrs[:category_id])
      @category_id   = @category_ids.first.to_s
      @category_name = attrs[:category_name].to_s
      @tags          = Array(attrs[:tags]).map { |tag| tag.to_s }
      @price         = attrs[:price]
      @sell_price    = attrs[:sell_price]
      @currency      = normalize_currency(attrs[:currency])
      @stock         = attrs[:stock]
      @stock_reset   = (attrs[:stock_reset] || :never).to_sym
      @availability  = attrs[:availability].is_a?(Hash) ? attrs[:availability] : {}
      @limits        = attrs[:limits].is_a?(Hash) ? attrs[:limits] : {}
      @display       = attrs[:display].is_a?(Hash) ? attrs[:display] : {}
      @dependencies  = attrs[:dependencies].is_a?(Hash) ? attrs[:dependencies] : {}
      @grants        = Array(attrs[:grants])
      @raw           = attrs[:raw]
    end

    def purchasable?
      [:item, :bundle, :gift, :service, :unlock, :coupon].include?(@kind)
    end

    def bundle_like?
      @kind == :bundle || @kind == :gift
    end

    def in_category?(category)
      @category_ids.map { |id| id.to_s }.include?(category.to_s)
    end

    private

    def normalize_category_ids(values, fallback)
      ids = Array(values).map { |id| id.to_s.strip }
      ids << fallback.to_s.strip
      ids = ids.reject(&:empty?).uniq
      ids.empty? ? ["items"] : ids
    end

    def normalize_currency(value)
      key = value.to_s.strip.downcase
      return :money if key.empty? || key == "money"
      key.to_sym
    end

    def normalize_kind(value)
      kind = value.to_s.strip.downcase.to_sym
      ENTRY_KINDS.include?(kind) ? kind : :item
    end
  end

  class PriceResult
    attr_accessor :base, :catalog, :modifiers, :final, :currency, :display

    def initialize(base: 0, catalog: nil, modifiers: [], final: nil, currency: :money, display: nil)
      @base      = base.to_i
      @catalog   = catalog.nil? ? @base : catalog.to_i
      @modifiers = Array(modifiers)
      @final     = final.nil? ? @catalog : final.to_i
      @currency  = currency.to_sym
      @display   = display || ReloadedMart.format_currency(@final, @currency)
    end

    def overridden?
      @final != @base
    end
  end

  class CartLine
    attr_accessor :entry, :quantity, :grants, :price_result

    def initialize(entry, quantity = 1, grants = nil, price_result = nil)
      @entry        = entry
      @quantity     = [quantity.to_i, 1].max
      @grants       = Array(grants)
      @price_result = price_result
    end

    def total_price
      unit = @price_result ? [@price_result.final.to_i, 0].max : 0
      unit * @quantity
    end

    def entry_id
      @entry ? @entry.id : nil
    end

    def entry_kind
      @entry ? @entry.kind : nil
    end
  end

  class Cart
    attr_reader :lines

    def initialize(source: :reloaded_mart)
      @source = source.to_sym
      @lines = []
    end

    def add(entry, quantity = 1, grants = nil, price_result = nil)
      @lines << CartLine.new(entry, quantity, grants, price_result)
      self
    end

    def source
      @source
    end

    def total_price
      @lines.inject(0) { |sum, line| sum + line.total_price }
    end

    def total_quantity
      @lines.inject(0) { |sum, line| sum + line.quantity.to_i }
    end

    def grant_items
      @lines.flat_map { |line| line.grants }
    end

    def empty?
      @lines.empty?
    end
  end

  class EntryHandler
    attr_reader :kind

    def initialize(kind)
      @kind = kind.to_sym
    end

    def grants_for(_entry, _quantity, _context = {})
      []
    end

    def validate(_line, _context = {})
      TransactionResult.new(true, :ok, "")
    end

    def apply(_line, _context = {})
      TransactionResult.new(true, :ok, "")
    end

    def defer_charge?(_line, _context = {})
      false
    end
  end

  class ItemEntryHandler < EntryHandler
    def initialize
      super(:item)
    end

    def grants_for(entry, quantity, _context = {})
      item_id = entry.raw.is_a?(Hash) ? (entry.raw["item"] || entry.raw[:item] || entry.id) : entry.id
      [{ :item_id => item_id, :quantity => quantity.to_i }]
    end
  end

  class BundleEntryHandler < EntryHandler
    def initialize(kind = :bundle)
      super(kind)
    end

    def grants_for(entry, quantity, _context = {})
      return mystery_grants_for(entry, quantity) if mystery_box?(entry)
      grants = []
      Array(entry.grants).each do |grant|
        if pokevial_grant?(grant)
          kind = pokevial_grant_kind(grant)
          amount = pokevial_quantity(grant).to_i
          if kind == :pokevial_refill
            quantity.to_i.times { grants << { :type => :pokevial_refill } }
          elsif kind == :pokevial_max_uses
            grants << { :type => :pokevial_max_uses, :amount => amount }
          else
            grants << { :type => :pokevial, :quantity => amount * quantity.to_i }
          end
          next
        end
        item_id, count = grant_item_and_quantity(grant)
        next if item_id.nil? || item_id.to_s.empty?
        grants << { :item_id => item_id, :quantity => count.to_i * quantity.to_i }
      end
      grants
    end

    def validate(line, _context = {})
      grants = Array(line&.grants)
      return TransactionResult.new(false, :empty_bundle, "This bundle is unavailable.") if grants.empty?
      grants.each do |grant|
        if pokevial_grant?(grant)
          quantity = pokevial_quantity(grant).to_i
          return TransactionResult.new(false, :invalid_bundle_grant, "This bundle is unavailable.") if quantity <= 0
          next
        end
        item_id = grant[:item_id] || grant["item_id"] || grant[:id] || grant["id"] || grant[:item] || grant["item"]
        quantity = (grant[:quantity] || grant["quantity"] || grant[:qty] || grant["qty"] || 1).to_i
        return TransactionResult.new(false, :invalid_bundle_grant, "This bundle is unavailable.") if item_id.nil? || item_id.to_s.empty? || quantity <= 0
        data = GameData::Item.try_get(item_id) rescue nil
        return TransactionResult.new(false, :missing_item, "One of the items is unavailable.", :item_id => item_id) unless data
      end
      TransactionResult.new(true, :ok, "")
    rescue Exception => e
      ReloadedMart.log_exception("Bundle grant validation failed", e)
      TransactionResult.new(false, :bundle_validation_failed, "This bundle is unavailable.")
    end

    def mystery_box?(entry)
      return false unless entry
      display = entry.display.is_a?(Hash) ? entry.display : {}
      raw = entry.raw.is_a?(Hash) ? entry.raw : {}
      ReloadedMart::Rules.truthy?(display["mystery_box"] || display[:mystery_box] || raw["mystery_box"] || raw[:mystery_box])
    rescue
      false
    end

    def mystery_grants_for(entry, quantity)
      pool = Array(entry.grants).select { |grant| mystery_grant_weight(grant) > 0 }
      pool = Array(entry.grants) if pool.empty?
      return [] if pool.empty?
      grants = []
      count = [quantity.to_i, 1].max
      count.times do |index|
        grant, roll_details = weighted_mystery_grant(pool)
        if pokevial_grant?(grant)
          kind = pokevial_grant_kind(grant)
          amount = [pokevial_quantity(grant).to_i, 1].max
          ReloadedMart.log_info(
            "Mystery reward roll entry=#{entry&.id} roll_index=#{index + 1} type=#{kind} quantity=#{amount} rarity=#{mystery_grant_rarity(grant) || "none"} weight=#{mystery_grant_weight(grant)} mode=#{roll_details[:mode]} roll=#{roll_details[:roll]}/#{roll_details[:total]} threshold=#{roll_details[:threshold] || "-"}"
          )
          reward = { :type => kind, :rarity => mystery_grant_rarity(grant) }
          reward[:quantity] = amount if kind == :pokevial
          reward[:amount] = amount if kind == :pokevial_max_uses
          grants << reward
          next
        end
        item_id, count = grant_item_and_quantity(grant)
        next if item_id.nil? || item_id.to_s.empty?
        log_mystery_reward_roll(entry, index + 1, item_id, count, grant, roll_details)
        grants << {
          :item_id => item_id,
          :quantity => [count.to_i, 1].max,
          :rarity => mystery_grant_rarity(grant)
        }
      end
      grants
    end

    def weighted_mystery_grant(pool)
      total = pool.inject(0) { |sum, grant| sum + mystery_grant_weight(grant) }
      if total <= 0
        index = rand(pool.length)
        return [pool[index], { :mode => :uniform, :roll => index + 1, :total => pool.length }]
      end
      roll = rand(total)
      running = 0
      pool.each do |grant|
        running += mystery_grant_weight(grant)
        return [grant, { :mode => :weighted, :roll => roll + 1, :total => total, :threshold => running }] if roll < running
      end
      [pool.last, { :mode => :fallback_last, :roll => roll + 1, :total => total, :threshold => running }]
    end

    def log_mystery_reward_roll(entry, index, item_id, quantity, grant, details)
      rarity = mystery_grant_rarity(grant)
      weight = mystery_grant_weight(grant)
      ReloadedMart.log_info(
        "Mystery reward roll entry=#{entry&.id} roll_index=#{index} item=#{item_id} quantity=#{[quantity.to_i, 1].max} rarity=#{rarity || "none"} weight=#{weight} mode=#{details[:mode]} roll=#{details[:roll]}/#{details[:total]} threshold=#{details[:threshold] || "-"}"
      )
    rescue Exception => e
      ReloadedMart.log_exception("Mystery reward roll logging failed", e)
    end

    def mystery_grant_weight(grant)
      return 0 unless grant.is_a?(Hash)
      value = grant["probability"] || grant[:probability] || grant["chance"] || grant[:chance] || grant["weight"] || grant[:weight]
      [value.to_i, 0].max
    end

    def mystery_grant_rarity(grant)
      return nil unless grant.is_a?(Hash)
      value = grant["rarity"] || grant[:rarity]
      value.to_s.empty? ? nil : value.to_s
    end

    def grant_item_and_quantity(grant)
      if grant.is_a?(Hash)
        item_id = grant["id"] || grant[:id] || grant["item"] || grant[:item]
        count = grant["qty"] || grant[:qty] || grant["quantity"] || grant[:quantity] || 1
      else
        item_id = grant
        count = 1
      end
      [item_id, count]
    end

    def pokevial_grant?(grant)
      return false unless grant.is_a?(Hash)
      marker = grant["type"] || grant[:type] || grant["kind"] || grant[:kind] || grant["grant_type"] || grant[:grant_type]
      marker ||= grant["id"] || grant[:id] || grant["item"] || grant[:item] || grant["item_id"] || grant[:item_id]
      pokevial_grant_markers.include?(marker.to_s)
    rescue
      false
    end

    def pokevial_grant_kind(grant)
      marker = grant["type"] || grant[:type] || grant["kind"] || grant[:kind] || grant["grant_type"] || grant[:grant_type]
      marker ||= grant["id"] || grant[:id] || grant["item"] || grant[:item] || grant["item_id"] || grant[:item_id]
      text = marker.to_s
      return :pokevial_refill if ["pokevial_refill", "poke_vial_refill", "POKEVIAL_REFILL", "refill_pokevial"].include?(text)
      return :pokevial_max_uses if ["pokevial_max", "pokevial_max_uses", "POKEVIAL_MAX_USES", "pokevial_unlock", "poke_vial_unlock"].include?(text)
      :pokevial
    rescue
      :pokevial
    end

    def pokevial_grant_markers
      ["pokevial", "poke_vial", "pokevial_charge", "POKEVIAL_CHARGE", "pokevial_uses", "POKEVIAL_USES", "pokevial_refill", "poke_vial_refill",
       "POKEVIAL_REFILL", "refill_pokevial", "pokevial_max", "pokevial_max_uses", "POKEVIAL_MAX_USES",
       "pokevial_unlock", "poke_vial_unlock"]
    end

    def pokevial_quantity(grant)
      return 0 unless grant.is_a?(Hash)
      value = grant["max_uses"] || grant[:max_uses] || grant["max"] || grant[:max]
      value ||= grant["pokevial_uses"] || grant[:pokevial_uses] || grant["uses"] || grant[:uses] || grant["qty"] || grant[:qty] || grant["quantity"] || grant[:quantity] || 1
      value
    rescue
      0
    end
  end

  class CouponEntryHandler < EntryHandler
    def initialize
      super(:coupon)
    end

    def apply(line, _context = {})
      coupon_code = if line.entry.raw.is_a?(Hash)
                      line.entry.raw["coupon_code"] || line.entry.raw[:coupon_code] || line.entry.id
                    else
                      line.entry.id
                    end
      ReloadedMart.activate_coupon(coupon_code)
      if _context.is_a?(Hash)
        _context[:activated_coupons] ||= []
        _context[:activated_coupons] << coupon_code.to_s
      end
      TransactionResult.new(true, :ok, "")
    end
  end

  class ValidationFailure
    attr_reader :code, :message, :details

    def initialize(code, message, details = {})
      @code = code.to_sym
      @message = message.to_s
      @details = details || {}
    end
  end

  class ValidationReport
    attr_reader :catalog_version, :source, :accepted, :skipped, :issues

    def initialize(catalog_version: DEFAULT_CATALOG_VERSION, source: :unknown)
      @catalog_version = catalog_version.to_s
      @source = source.to_sym
      @accepted = []
      @skipped = []
      @issues = []
    end

    def accept(entry)
      @accepted << entry
    end

    def skip(entry_id, reason, details = {})
      record(:warning, entry_id, reason, details)
      @skipped << { :entry_id => entry_id.to_s, :reason => reason.to_s, :details => details || {} }
    end

    def error(entry_id, reason, details = {})
      record(:error, entry_id, reason, details)
    end

    def record(level, entry_id, reason, details = {})
      @issues << {
        :level => level.to_sym,
        :entry_id => entry_id.to_s,
        :reason => reason.to_s,
        :details => details || {}
      }
    end

    def ok?
      !@issues.any? { |issue| issue[:level] == :error }
    end

    def summary
      {
        :catalog_version => @catalog_version,
        :source => @source,
        :accepted => @accepted.length,
        :skipped => @skipped.length,
        :issues => @issues.length,
        :errors => @issues.count { |issue| issue[:level] == :error },
        :warnings => @issues.count { |issue| issue[:level] == :warning }
      }
    end
  end

  class TransactionResult
    attr_reader :ok, :code, :message, :details

    def initialize(ok, code, message = nil, details = {})
      @ok = ok ? true : false
      @code = code.to_sym
      @message = message.to_s
      @details = details || {}
    end

    def ok?
      @ok
    end
  end

  def self.bag_max_per_slot
    if defined?(Settings) && Settings.const_defined?(:BAG_MAX_PER_SLOT, false)
      return Settings::BAG_MAX_PER_SLOT.to_i
    end
    DEFAULT_BAG_MAX_PER_SLOT
  rescue
    DEFAULT_BAG_MAX_PER_SLOT
  end

  class << self
    def install
      Reloaded::MartFeature.install if defined?(Reloaded::MartFeature)
    end

    def register_patch_points
      return if @patches_registered
      @patches_registered = true
      return unless defined?(Reloaded::Patches)
      Reloaded::Patches.register(
        :reloaded_mart_entry_point,
        :target => "pbOpenReloadedMart",
        :type => :append,
        :file => __FILE__,
        :owner => :reloaded,
        :priority => 100,
        :reason => "Adds the standalone Reloaded Mart entry point used by REPM and scripts.",
        :recommended_fix => "If another system defines pbOpenReloadedMart, route through ReloadedMart.open or register a Mart event handler.",
        :allow_multiple => true
      )
      Reloaded::Patches.register(
        :reloaded_mart_vanilla_mart_ui,
        :target => "pbPokemonMart",
        :type => :wrap,
        :file => "Reloaded/Modules/003a_ReloadedMartUI.rb",
        :owner => :reloaded,
        :priority => 100,
        :reason => "Routes vanilla NPC marts through the Reloaded REX buy/sell UI while preserving vanilla stock, prices, and dialogue.",
        :recommended_fix => "If another system wraps pbPokemonMart, keep vanilla stock/prices isolated and fall back to the original mart on failure.",
        :conflict_group => "pokemon_mart_ui"
      )
    rescue Exception => e
      log_exception("Failed to register Reloaded Mart patch points", e)
    end

    def register_builtin_entry_handlers
      register_entry_handler(:item, ItemEntryHandler.new)
      register_entry_handler(:bundle, BundleEntryHandler.new(:bundle))
      register_entry_handler(:gift, BundleEntryHandler.new(:gift))
      service_handler = defined?(ServiceEntryHandler) ? ServiceEntryHandler.new : EntryHandler.new(:service)
      register_entry_handler(:service, service_handler)
      register_entry_handler(:unlock, EntryHandler.new(:unlock))
      register_entry_handler(:coupon, CouponEntryHandler.new)
    end

    def register_entry_handler(kind, handler)
      kind_sym = kind.to_sym
      return false unless ENTRY_KINDS.include?(kind_sym)
      @entry_handlers[kind_sym] = handler
      true
    rescue Exception => e
      log_exception("Failed to register Mart entry handler #{kind}", e)
      false
    end

    def entry_handler(kind)
      @entry_handlers[kind.to_sym]
    rescue
      nil
    end

    def register_price_modifier(id, priority: 100, &block)
      return false unless block
      @price_modifier_handlers.delete_if { |entry| entry[:id] == id.to_sym }
      @price_modifier_handlers << { :id => id.to_sym, :priority => priority.to_i, :block => block }
      @price_modifier_handlers.sort_by! { |entry| [entry[:priority], entry[:id].to_s] }
      true
    rescue Exception => e
      log_exception("Failed to register Mart price modifier #{id}", e)
      false
    end

    def price_modifier_handlers
      @price_modifier_handlers
    end

    def data
      return Reloaded::SaveData.system(SAVE_SYSTEM) if defined?(Reloaded::SaveData)
      @fallback_data ||= {}
    end

    def ensure_state!
      defaults = {
        "schema_version" => SCHEMA_VERSION,
        "favorites" => [],
        "stock" => {},
        "stock_resets" => {},
        "claims" => {},
        "limits" => {},
        "limits_daily" => {},
        "stats" => Stats.empty,
        "catalog" => {},
        "cache" => {},
        "seen_catalog_versions" => [],
        "active_coupons" => [],
        "promo_codes" => { "active" => {}, "used" => [], "last_seen_at" => 0 },
        "daily_featured" => {}
      }
      bucket = data
      defaults.each { |key, value| bucket[key] = value unless bucket.has_key?(key) }
      bucket
    rescue Exception => e
      log_exception("Failed to initialize Reloaded Mart state", e)
      data
    end

    def state(key, default = nil)
      bucket = ensure_state!
      key_s = key.to_s
      bucket.has_key?(key_s) ? bucket[key_s] : default
    rescue
      default
    end

    def set_state(key, value)
      if defined?(Reloaded::SaveData)
        Reloaded::SaveData.set(SAVE_SYSTEM, key, value, section: :systems)
      else
        data[key.to_s] = value
      end
      true
    rescue Exception => e
      log_exception("Failed to store Mart state #{key}", e)
      false
    end

    def favorites
      list = state(:favorites, [])
      list.is_a?(Array) ? list : []
    end

    def set_favorites(list)
      set_state(:favorites, Array(list).map { |entry| entry.to_s }.uniq)
    end

    def favorite?(entry_id)
      favorites.include?(entry_id.to_s)
    end

    def toggle_favorite(entry_id)
      list = favorites
      id = entry_id.to_s
      if list.include?(id)
        list.delete(id)
        set_favorites(list)
        false
      else
        list << id
        set_favorites(list)
        true
      end
    end

    def active_coupons
      active_promo_codes
    end

    def activate_coupon(code)
      result = redeem_promo_code(code)
      result.ok?
    end

    def deactivate_coupon(code)
      key = promo_code_key(code)
      value = promo_codes_state
      value["active"].delete(key)
      set_promo_codes_state(value)
    end

    def promo_codes_state
      value = state(:promo_codes, {})
      value = {} unless value.is_a?(Hash)
      value["active"] = {} unless value["active"].is_a?(Hash)
      value["used"] = [] unless value["used"].is_a?(Array)
      value["last_seen_at"] = value["last_seen_at"].to_i
      cleanup_promo_codes(value)
    end

    def set_promo_codes_state(value)
      set_state(:promo_codes, value.is_a?(Hash) ? value : {})
    end

    def promo_code_key(code)
      code.to_s.strip.upcase.gsub(/\s+/, "")
    end

    def active_promo_codes
      promo_codes_state["active"].keys
    rescue
      []
    end

    def active_promo_code_remaining_seconds
      value = promo_codes_state
      key = value["active"].keys.first
      return nil unless key
      info = value["active"][key]
      expires_at = info.is_a?(Hash) ? info["expires_at"].to_i : 0
      remaining = expires_at - promo_clock_now
      remaining > 0 ? remaining : nil
    rescue
      nil
    end

    def active_promo_code_remaining_text
      Rules.format_duration(active_promo_code_remaining_seconds)
    rescue
      nil
    end

    def promo_code_active?(code)
      promo_codes_state["active"].has_key?(promo_code_key(code))
    rescue
      false
    end

    def catalog_version
      Source.active_report&.catalog_version || DEFAULT_CATALOG_VERSION
    rescue
      DEFAULT_CATALOG_VERSION
    end

    def redeem_promo_code(code)
      key = promo_code_key(code)
      return TransactionResult.new(false, :blank_promo_code, "Enter a promo code.") if key.empty?
      value = promo_codes_state
      active_key = value["active"].keys.first
      if active_key
        remaining = Rules.format_duration(active_promo_code_remaining_seconds)
        suffix = remaining ? " #{remaining}." : "."
        if active_key == key
          return TransactionResult.new(false, :promo_code_active, "That promo code is already active.#{suffix}")
        end
        return TransactionResult.new(false, :promo_code_active, "Only one promo code can be active at a time.#{suffix}")
      end
      return TransactionResult.new(false, :promo_code_used, "That promo code has already been used.") if value["used"].include?(key)
      promo = promo_code_entry(key)
      return TransactionResult.new(false, :promo_code_not_found, "That promo code is invalid.") unless promo
      return TransactionResult.new(false, :promo_code_disabled, "That promo code is unavailable.") unless promo_code_enabled?(promo)
      return TransactionResult.new(false, :promo_code_unavailable, "That promo code is not available right now.") unless promo_code_available?(promo)
      now = promo_clock_now
      value["active"][key] = {
        "activated_at" => now,
        "expires_at" => now + PROMO_CODE_DURATION_SECONDS,
        "catalog_version" => catalog_version
      }
      value["used"] << key
      value["used"].uniq!
      value["last_seen_at"] = now
      set_promo_codes_state(value)
      log_info("Mart promo code activated code=#{key} expires_at=#{value["active"][key]["expires_at"]}")
      TransactionResult.new(true, :ok, "Promo code applied for 5 minutes.", :code => key, :expires_at => value["active"][key]["expires_at"])
    rescue Exception => e
      log_exception("Promo code activation failed", e)
      TransactionResult.new(false, :promo_code_failed, "That promo code could not be applied.")
    end

    def matching_promo_modifiers(entry, context = {})
      active_promo_codes.map do |code|
        promo = promo_code_entry(code)
        next nil unless promo
        modifier = promo_code_modifier(promo, code)
        next nil unless Economy.modifier_applies?(modifier, entry, context)
        Economy.normalize_modifier(modifier, { "id" => "promo:#{code}", "label" => promo["label"] || code })
      end.compact
    rescue Exception => e
      log_exception("Promo code modifier lookup failed", e)
      []
    end

    def promo_code_entry(code)
      key = promo_code_key(code)
      Array(Source.active_raw && Source.active_raw["promo_codes"]).find do |entry|
        next false unless entry.is_a?(Hash)
        promo_code_key(entry["code"] || entry["id"]) == key
      end
    rescue
      nil
    end

    def promo_code_enabled?(promo)
      return false unless promo.is_a?(Hash)
      return false if promo["enabled"] == false || promo["active"] == false
      true
    end

    def promo_code_available?(promo)
      return false unless promo.is_a?(Hash)
      return false unless Rules.reached?(promo["available_from"] || promo[:available_from], {})
      return false if Rules.past?(promo["available_until"] || promo[:available_until], {})
      true
    end

    def promo_code_modifier(promo, code = nil)
      modifier = promo["modifier"].is_a?(Hash) ? promo["modifier"].each_with_object({}) { |(key, val), memo| memo[key.to_s] = val } : {}
      %w[type value mode entry_id entry_ids item_id item_ids category category_id category_ids tag tags kind].each do |key|
        modifier[key] = promo[key] if modifier[key].nil? && promo.has_key?(key)
      end
      modifier["type"] ||= "percent"
      modifier["value"] ||= -10
      modifier["mode"] ||= "buy"
      %w[entry_id entry_ids item_id item_ids category category_id category_ids tag tags kind].each do |key|
        value = modifier[key]
        modifier.delete(key) if value.respond_to?(:empty?) && value.empty?
      end
      modifier["promo_code"] = promo_code_key(code || promo["code"] || promo["id"])
      modifier["label"] ||= promo["label"] || modifier["promo_code"]
      modifier
    end

    def cleanup_promo_codes(value)
      now = promo_clock_now
      last = value["last_seen_at"].to_i
      changed = false
      if last > 0 && now < last
        value["active"] = {}
        changed = true
        log_warning("Mart promo codes expired because system time moved backward")
      else
        value["active"].delete_if do |_code, info|
          expires_at = info.is_a?(Hash) ? info["expires_at"].to_i : 0
          expired = expires_at <= now
          changed ||= expired
          expired
        end
      end
      if value["active"].length > 1
        keep = value["active"].max_by { |_code, info| info.is_a?(Hash) ? info["activated_at"].to_i : 0 }
        value["active"] = keep ? { keep[0] => keep[1] } : {}
        changed = true
        log_warning("Mart promo codes collapsed to one active code")
      end
      if now > last
        value["last_seen_at"] = now
        changed = true
      end
      set_promo_codes_state(value) if changed
      value
    end

    def promo_clock_now
      Time.now.to_i
    rescue
      0
    end

    def cache
      value = state(:cache, {})
      value.is_a?(Hash) ? value : {}
    end

    def set_cache(value)
      set_state(:cache, value.is_a?(Hash) ? value : {})
    end

    def catalog_metadata
      value = state(:catalog, {})
      value.is_a?(Hash) ? value : {}
    end

    def set_catalog_metadata(value)
      set_state(:catalog, value.is_a?(Hash) ? value : {})
    end

    def seen_catalog_versions
      list = state(:seen_catalog_versions, [])
      list.is_a?(Array) ? list : []
    end

    def mark_catalog_seen(version)
      version_s = version.to_s
      return false if version_s.empty?
      list = seen_catalog_versions
      list << version_s unless list.include?(version_s)
      set_state(:seen_catalog_versions, list)
    end

    def new_catalog_version?(version)
      version_s = version.to_s
      !version_s.empty? && !seen_catalog_versions.include?(version_s)
    end

    def available?
      true
    end

    def open
      log_info("Opening Reloaded Mart")
      Source.load_for_open(blocking: true)
      if ui_ready?
        open_ui
      else
        Kernel.pbMessage(_INTL("The Reloaded Mart is being prepared.")) if defined?(Kernel) && Kernel.respond_to?(:pbMessage)
        log_warning("Reloaded Mart UI is unavailable")
      end
    rescue Exception => e
      raise if e.is_a?(SystemExit)
      log_exception("Reloaded Mart open failed", e)
      Kernel.pbMessage(_INTL("The Reloaded Mart is unavailable right now.")) rescue nil
    end

    def open_options
      return unless defined?(ReloadedMart::OptionsScene)
      pbFadeOutIn do
        scene = ReloadedMart::OptionsScene.new
        screen = PokemonOptionScreen.new(scene)
        screen.pbStartScreen
      end
    rescue Exception => e
      log_exception("Reloaded Mart options failed", e)
      Kernel.pbMessage(_INTL("Reloaded Mart options are unavailable right now.")) rescue nil
    end

    def box_animation_enabled?
      ($PokemonSystem.hr_mart_box_animation rescue 1).to_i == 1
    end

    def ui_ready?
      false
    end

    def open_ui
      false
    end

    def format_currency(amount, currency = :money)
      symbol = currency_symbol(currency)
      "#{symbol}#{amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    end

    def currency_symbol(currency)
      CURRENCY_SYMBOLS[currency.to_sym] || CURRENCY_SYMBOLS[:money] || "$"
    end

    def emit(event_name, context = {})
      Reloaded::Events.emit(event_name, context) if defined?(Reloaded::Events)
    rescue Exception => e
      log_exception("Reloaded Mart event #{event_name} failed", e)
    end

    def log_info(message)
      Reloaded::Log.info(message, :modules) if defined?(Reloaded::Log)
    rescue
    end

    def log_warning(message)
      Reloaded::Log.warning(message, :modules) if defined?(Reloaded::Log)
    rescue
    end

    def log_exception(message, error)
      Reloaded::Log.exception(message, error, channel: :modules) if defined?(Reloaded::Log)
    rescue
    end

    def log_debug(message)
      Reloaded::Log.debug(message, :modules) if defined?(Reloaded::Log)
    rescue
    end
  end

  class OptionsScene < PokemonOption_Scene
    def initUIElements
      super
      @sprites["title"].text = _INTL("Reloaded Mart") rescue nil
    end

    def pbGetOptions(_inloadscreen = false)
      [
        EnumOption.new(
          _INTL("Remove Confirm Prompt"),
          [_INTL("Off"), _INTL("On")],
          proc { ($PokemonSystem.hr_mart_confirm rescue 1).to_i == 0 ? 1 : 0 },
          proc { |value| $PokemonSystem.hr_mart_confirm = value.to_i == 1 ? 0 : 1 if $PokemonSystem },
          _INTL("On: Skip purchase and sale confirmation prompts.\nOff: Confirm mart transactions before completing them.")
        ),
        EnumOption.new(
          _INTL("Box Animation"),
          [_INTL("Off"), _INTL("On")],
          proc { ReloadedMart.box_animation_enabled? ? 1 : 0 },
          proc { |value| $PokemonSystem.hr_mart_box_animation = value.to_i if $PokemonSystem },
          _INTL("Controls whether Mystery Boxes play the reveal animation after purchase.")
        )
      ]
    end
  end

  module Source
    @active_catalog = nil
    @active_report = nil
    @active_source = nil
    @active_raw = nil
    @fetch_thread = nil

    class << self
      attr_reader :active_catalog, :active_report, :active_source, :active_raw

      def online_url
        ONLINE_CATALOG_URL
      end

      def load_for_open(blocking: true)
        if @fetch_thread && @fetch_thread.alive?
          @fetch_thread.join rescue nil
          @fetch_thread = nil
        end
        refresh_online(blocking: true)
      end

      def current
        {
          :catalog => @active_catalog,
          :report => @active_report,
          :source => @active_source,
          :raw => @active_raw
        }
      end

      def cached_catalog
        raw = last_good_catalog
        return nil unless raw.is_a?(Hash)
        result = Catalog.load(raw, source: :last_good_cache)
        return nil unless result[:report]&.ok?
        raw
      rescue
        nil
      end

      def last_good_catalog
        ReloadedMart.cache["last_good_catalog"]
      rescue
        nil
      end

      def last_good_metadata
        ReloadedMart.cache["last_good_metadata"] || {}
      rescue
        {}
      end

      def store_last_good(raw_catalog, metadata = {})
        cache = ReloadedMart.cache
        cache["last_good_catalog"] = raw_catalog
        cache["last_good_metadata"] = metadata || {}
        cache["cached_at"] = Time.now.to_i rescue 0
        ReloadedMart.set_cache(cache)
      end

      def clear_cache
        ReloadedMart.set_cache({})
      end

      def start_online_refresh
        return false if @fetch_thread && @fetch_thread.alive?
        if defined?(Thread)
          @fetch_thread = Thread.new { refresh_online(blocking: true) } rescue nil
          return true if @fetch_thread
        end
        refresh_online(blocking: true)
        true
      rescue Exception => e
        ReloadedMart.log_exception("Reloaded Mart online refresh could not start", e)
        false
      end

      def finish_online_refresh
        return nil unless @fetch_thread
        return nil if @fetch_thread.alive?
        @fetch_thread.join rescue nil
        @fetch_thread = nil
        current
      end

      def refresh_online(blocking: true)
        url = online_url.to_s
        if url.empty?
          ReloadedMart.log_warning("Mart catalog fetch skipped: online URL is blank")
          return load_cached_or_fail(:blank_url)
        end
        ReloadedMart.log_info("Mart catalog fetch started")
        raw_text = fetch_url(url)
        unless raw_text && !raw_text.to_s.strip.empty?
          ReloadedMart.log_warning("Mart catalog fetch failed: empty response")
          return load_cached_or_fail(:empty_response)
        end
        raw = parse_json(raw_text)
        unless raw.is_a?(Hash)
          ReloadedMart.log_warning("Mart catalog fetch failed: parsed data was not a Hash")
          return load_cached_or_fail(:invalid_json_root)
        end
        result = load_raw(raw, source: :online_fresh)
        if result[:report] && result[:report].ok?
          metadata = {
            "source" => "online_fresh",
            "catalog_version" => result[:report].catalog_version,
            "fetched_at" => Time.now.to_i,
            "url" => url
          }
          store_last_good(raw, metadata)
          ReloadedMart.emit(EVENT_CATALOG_LOADED, {
            :source => :online_fresh,
            :catalog_version => result[:report].catalog_version,
            :entries => result[:entries].length
          })
          ReloadedMart.log_info("Mart catalog fetch complete version=#{result[:report].catalog_version} entries=#{result[:entries].length}")
          return current
        end
        ReloadedMart.log_warning("Mart catalog fetch produced invalid catalog")
        load_cached_or_fail(:invalid_catalog)
      rescue Exception => e
        ReloadedMart.log_exception("Mart catalog fetch failed", e)
        load_cached_or_fail(:exception)
      end

      def load_raw(raw, source: :unknown)
        result = Catalog.load(raw, source: source)
        @active_catalog = result[:entries]
        @active_report = result[:report]
        @active_source = source.to_sym
        @active_raw = result[:raw]
        ReloadedMart.set_catalog_metadata({
          "source" => @active_source.to_s,
          "catalog_version" => (@active_report.catalog_version rescue DEFAULT_CATALOG_VERSION),
          "stock_epoch" => (@active_raw["stock_epoch"] rescue nil),
          "loaded_at" => Time.now.to_i
        })
        log_daily_featured_probe(result[:entries], source)
        result
      end

      def log_daily_featured_probe(entries, source)
        return unless defined?(ReloadedMart::Economy)
        rows = ReloadedMart::Economy.daily_featured_entries(entries, { :source => :reloaded_mart, :mode => :buy })
        ReloadedMart.log_info("Daily featured probe source=#{source} generated=#{rows.length} entries=#{rows.map(&:id).join(",")}")
      rescue Exception => e
        ReloadedMart.log_exception("Daily featured probe failed", e)
      end

      def load_cached_or_fail(reason)
        cached = last_good_catalog
        if cached.is_a?(Hash)
          ReloadedMart.log_warning("Mart catalog falling back to last-good cache reason=#{reason}")
          return load_raw(cached, source: :last_good_cache)
        end
        ReloadedMart.log_warning("Mart catalog unavailable reason=#{reason}; no last-good cache available")
        report = ValidationReport.new(source: :none)
        report.error("catalog", reason.to_s)
        @active_catalog = []
        @active_report = report
        @active_source = :none
        ReloadedMart.emit(EVENT_CATALOG_FAILED, {
          :reason => reason,
          :source => :none
        })
        { :entries => [], :report => report }
      end

      def fetch_url(url)
        request_url = cache_busted_url(url)
        if defined?(HTTPLite)
          response = HTTPLite.get(request_url, {
            "Cache-Control" => "no-cache",
            "Proxy-Connection" => "Close",
            "Pragma" => "no-cache",
            "User-Agent" => "Hoenn Reloaded Mart"
          }) rescue nil
          return response[:body].to_s if response.is_a?(Hash) && response[:status].to_i == 200
        end
        if defined?(pbDownloadToString)
          data = pbDownloadToString(request_url) rescue ""
          return data.to_s unless data.to_s.empty?
        end
        nil
      end

      def cache_busted_url(url)
        joiner = url.to_s.include?("?") ? "&" : "?"
        "#{url}#{joiner}rld_mart=#{Time.now.to_i}_#{rand(100000)}"
      end

      def parse_json(raw)
        raise "JSON parser is not available" unless defined?(JSON)
        stringify_json_keys(JSON.parse(json_for_runtime_parser(raw.to_s.sub("\xEF\xBB\xBF", ""))))
      end

      def json_for_runtime_parser(raw)
        text = raw.to_s
        output = +""
        in_string = false
        escaped = false
        index = 0
        while index < text.length
          char = text[index]
          if in_string
            output << char
            if escaped
              escaped = false
            elsif char == "\\"
              escaped = true
            elsif char == "\""
              in_string = false
            end
            index += 1
            next
          end
          if char == "\""
            in_string = true
            output << char
            index += 1
            next
          end
          if text[index, 4] == "null" && json_token_boundary?(text[index - 1]) && json_token_boundary?(text[index + 4])
            output << "nil"
            index += 4
            next
          end
          output << char
          index += 1
        end
        output
      end

      def json_token_boundary?(char)
        char.nil? || char !~ /[A-Za-z0-9_]/
      end

      def stringify_json_keys(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, child), memo| memo[key.to_s] = stringify_json_keys(child) }
        when Array
          value.map { |child| stringify_json_keys(child) }
        else
          value
        end
      end
    end
  end

  module Rules
    class << self
      def now(context = {})
        context[:now] || Time.now
      rescue
        Time.now
      end

      def today_key(context = {})
        time = now(context)
        "%04d-%02d-%02d" % [time.year, time.month, time.day]
      rescue
        "unknown"
      end

      def week_key(context = {})
        time = now(context)
        if time.respond_to?(:strftime)
          time.strftime("%Y-W%U")
        else
          today_key(context)
        end
      rescue
        "unknown"
      end

      def month_key(context = {})
        time = now(context)
        "%04d-%02d" % [time.year, time.month]
      rescue
        "unknown"
      end

      def parse_time(value)
        return nil if value.nil? || value.to_s.strip.empty?
        text = value.to_s.strip
        if text =~ /\A(\d{1,2})-(\d{1,2})-(\d{2,4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\z/
          month = $1.to_i
          day = $2.to_i
          year = $3.to_i
          year += 2000 if year < 100
          hour = ($4 || 0).to_i
          min = ($5 || 0).to_i
          sec = ($6 || 0).to_i
          return Time.new(year, month, day, hour, min, sec) rescue nil
        end
        Time.parse(text) rescue nil
      end

      def seconds_until(value, context = {})
        target = parse_time(value)
        return nil unless target
        remaining = target.to_i - now(context).to_i
        remaining > 0 ? remaining : nil
      rescue
        nil
      end

      def format_duration(seconds)
        return nil unless seconds && seconds > 0
        days = seconds / 86_400
        hours = (seconds % 86_400) / 3_600
        mins = (seconds % 3_600) / 60
        return "#{days}d #{hours}h Remaining" if days > 0
        return "#{hours}h #{mins}m Remaining" if hours > 0
        "#{[mins, 1].max}m Remaining"
      rescue
        nil
      end

      def reached?(value, context = {})
        target = parse_time(value)
        return true unless target
        now(context).to_i >= target.to_i
      rescue
        true
      end

      def past?(value, context = {})
        target = parse_time(value)
        return false unless target
        now(context).to_i > target.to_i
      rescue
        false
      end

      def truthy?(value)
        value == true || ["1", "true", "yes", "on"].include?(value.to_s.strip.downcase)
      end

      def difficulty(context = {})
        return context[:difficulty] if context.has_key?(:difficulty)
        $Trainer ? $Trainer.selected_difficulty : nil
      rescue
        nil
      end

      def badge_count
        $Trainer ? $Trainer.badge_count.to_i : 0
      rescue
        0
      end

      def switch_on?(switch_id)
        return false if switch_id.nil? || !defined?($game_switches) || !$game_switches
        $game_switches[switch_id.to_i] ? true : false
      rescue
        false
      end

      def variable_value(variable_id)
        return nil if variable_id.nil? || !defined?($game_variables) || !$game_variables
        $game_variables[variable_id.to_i]
      rescue
        nil
      end

      def active_mod?(mod_id)
        id = mod_id.to_s
        return false if id.empty?
        if defined?(Reloaded::ModManager)
          active = Reloaded::ModManager.active_mods rescue []
          return active.any? { |mod| (mod.respond_to?(:id) ? mod.id : mod["id"]).to_s == id }
        end
        false
      rescue
        false
      end

      def item_owned?(item_id, quantity = 1)
        return false unless defined?($PokemonBag) && $PokemonBag
        $PokemonBag.pbQuantity(item_id).to_i >= quantity.to_i
      rescue
        false
      end

      def normalized_array(value)
        Array(value).compact
      end

      def includes_any?(haystack, needles)
        values = normalized_array(haystack).map { |entry| entry.to_s }
        normalized_array(needles).any? { |needle| values.include?(needle.to_s) }
      end
    end
  end

  module Economy
    class << self
      def catalog
        Source.active_raw || {}
      end

      def events
        Array(catalog["economy_events"] || catalog[:economy_events]).select { |event| event.is_a?(Hash) }
      rescue
        []
      end

      def profile_tuning(context = {})
        return [] unless automation_enabled?("profile_tuning")
        tuning = catalog["profile_tuning"] || catalog[:profile_tuning] || {}
        return [] unless tuning.is_a?(Hash)
        key = profile_key(context)
        Array(tuning[key] || tuning[key.to_s])
      rescue
        []
      end

      def matching_price_modifiers(entry, context = {})
        modifiers = []
        if automation_enabled?("economy_events")
          events.each do |event|
            next unless event_active?(event, context)
            Array(event["modifiers"] || event[:modifiers]).each do |modifier|
              next unless modifier.is_a?(Hash)
              next unless modifier_applies?(modifier, entry, context)
              modifiers << normalize_modifier(modifier, event)
            end
          end
        end
        profile_tuning(context).each do |modifier|
          next unless modifier.is_a?(Hash)
          next unless modifier_applies?(modifier, entry, context)
          modifiers << normalize_modifier(modifier, { "id" => "profile_tuning" })
        end
        modifiers << daily_featured_modifier(entry, context) if daily_featured_automation_enabled? && daily_featured?(entry, context)
        modifiers.compact
      end

      def automation_config
        configured = catalog["automation"] || catalog[:automation]
        return DEFAULT_AUTOMATION.merge("enabled" => false) if configured == false
        return DEFAULT_AUTOMATION unless configured.is_a?(Hash)
        DEFAULT_AUTOMATION.merge(stringify_hash(configured))
      rescue
        DEFAULT_AUTOMATION
      end

      def automation_enabled?(key = nil)
        config = automation_config
        return false unless Rules.truthy?(config["enabled"])
        return true unless key
        key = key.to_s
        return true unless config.has_key?(key)
        Rules.truthy?(config[key])
      rescue
        true
      end

      def event_active?(event, context = {})
        availability = event["availability"] || event[:availability] || event
        return false unless Rules.reached?(availability["available_from"] || availability[:available_from], context)
        return false if Rules.past?(availability["available_until"] || availability[:available_until], context)
        true
      end

      def modifier_applies?(modifier, entry, context = {})
        return false unless entry
        mode = modifier["mode"] || modifier[:mode]
        context_mode = (context[:mode] || :buy).to_s
        return false if mode && mode.to_s != context_mode && mode.to_s != "both"
        entry_targets = modifier_target_values(modifier, "entry_id", "entry_ids")
        return false if entry_targets.any? && !entry_targets.include?(entry.id.to_s)
        item_targets = modifier_target_values(modifier, "item", "items", "item_id", "item_ids")
        return false if item_targets.any? && !item_targets.include?(modifier_entry_item_id(entry))
        return false if modifier["kind"] && modifier["kind"].to_s != entry.kind.to_s
        categories = modifier_target_values(modifier, "category", "categories", "category_id", "category_ids")
        if categories.any?
          names = [entry.category_name.to_s]
          return false unless categories.any? { |category| entry.in_category?(category) || names.include?(category) }
        end
        if modifier["tag"] || modifier[:tag]
          tag = modifier["tag"] || modifier[:tag]
          return false unless entry.tags.map { |t| t.to_s }.include?(tag.to_s)
        end
        if modifier["tags"] || modifier[:tags]
          return false unless Rules.includes_any?(entry.tags, modifier["tags"] || modifier[:tags])
        end
        if modifier["coupon"] || modifier[:coupon]
          coupon = modifier["coupon"] || modifier[:coupon]
          return false unless ReloadedMart.active_coupons.include?(ReloadedMart.promo_code_key(coupon))
        end
        if modifier["promo_code"] || modifier[:promo_code]
          promo_code = modifier["promo_code"] || modifier[:promo_code]
          return false unless ReloadedMart.promo_code_active?(promo_code)
        end
        if modifier["min_loyalty_spend"] || modifier[:min_loyalty_spend]
          min = (modifier["min_loyalty_spend"] || modifier[:min_loyalty_spend]).to_i
          return false if Stats.total_spent < min
        end
        true
      end

      def modifier_target_values(modifier, *keys)
        keys.flat_map do |key|
          value = modifier[key] || modifier[key.to_sym]
          value.is_a?(Array) ? value : [value]
        end.map { |value| value.to_s.strip }.reject(&:empty?).uniq
      rescue
        []
      end

      def modifier_entry_item_id(entry)
        raw = entry.raw.is_a?(Hash) ? entry.raw : {}
        (raw["item"] || raw[:item] || entry.id).to_s
      rescue
        entry.id.to_s
      end

      def normalize_modifier(modifier, event = {})
        id = modifier["id"] || modifier[:id] || event["id"] || event[:id] || "modifier"
        {
          :id => id.to_s,
          :label => (modifier["label"] || modifier[:label] || event["label"] || event[:name] || id).to_s,
          :type => (modifier["type"] || modifier[:type] || "percent").to_s,
          :value => (modifier["value"] || modifier[:value] || 0),
          :source => (event["id"] || event[:id] || "catalog").to_s
        }
      end

      def daily_featured_entries(entries = nil, context = {})
        config = daily_featured_config
        unless daily_featured_automation_enabled?
          log_daily_featured_skip(:automation_disabled, config)
          return []
        end
        unless daily_featured_enabled?(config)
          log_daily_featured_skip(:daily_featured_disabled, config)
          return []
        end
        unless daily_featured_game_item_pool?(config)
          log_daily_featured_skip(:unsupported_pool, config)
          return []
        end
        cache_key = daily_featured_cache_key(config, context)
        if @daily_featured_entries_cache && @daily_featured_entries_cache[:key] == cache_key
          return Array(@daily_featured_entries_cache[:entries])
        end
        entries ||= Source.active_catalog || []
        item_ids = daily_featured_item_ids(entries, context)
        generated = item_ids.map do |item_id|
          data = GameData::Item.try_get(item_id) rescue nil
          next nil unless data
          raw = {
            "id" => daily_featured_entry_id_for(data.id),
            "kind" => "item",
            "item" => data.id.to_s,
            "name" => data.name,
            "category_id" => daily_featured_category_id(config),
            "category_name" => daily_featured_category_name(config),
            "tags" => ["featured", "daily_featured"],
            "daily_featured_pool" => true,
            "stock" => daily_featured_stock(config),
            "stock_reset" => daily_featured_stock_reset(config)
          }
          CatalogEntry.new(
            :id => raw["id"],
            :kind => raw["kind"],
            :name => raw["name"],
            :category_id => raw["category_id"],
            :category_name => raw["category_name"],
            :tags => raw["tags"],
            :stock => raw["stock"],
            :stock_reset => raw["stock_reset"],
            :currency => :money,
            :raw => raw
          )
        end.compact
        log_daily_featured_generation(config, item_ids, generated)
        @daily_featured_entries_cache = { :key => cache_key, :entries => generated }
        generated
      rescue Exception => e
        ReloadedMart.log_exception("Daily featured entry generation failed", e)
        []
      end

      def daily_featured_automation_enabled?
        config = automation_config
        key_enabled = !config.has_key?("daily_featured") || Rules.truthy?(config["daily_featured"])
        return true if key_enabled
        false
      rescue
        true
      end

      def daily_featured_game_item_pool?(config)
        pool = (config["pool"] || config[:pool] || DEFAULT_DAILY_FEATURED["pool"]).to_s
        key = pool.strip.downcase.gsub(/[\s\-]+/, "_")
        key.empty? || key == "game_items"
      rescue
        true
      end

      def daily_featured_item_ids(entries = nil, context = {})
        config = daily_featured_config
        cache_key = daily_featured_cache_key(config, context)
        if @daily_featured_item_ids_cache && @daily_featured_item_ids_cache[:key] == cache_key
          return Array(@daily_featured_item_ids_cache[:item_ids])
        end
        count = [(config["count"] || DEFAULT_DAILY_FEATURED["count"]).to_i, 1].max
        candidates = daily_featured_item_pool(config)
        return [] if candidates.empty?
        seed = "#{Source.active_report&.catalog_version || DEFAULT_CATALOG_VERSION}:#{daily_featured_day_key(context)}:daily_featured"
        item_ids = candidates.sort_by { |item_id| deterministic_score("#{seed}:#{item_id}") }.first(count)
        @daily_featured_item_ids_cache = { :key => cache_key, :item_ids => item_ids }
        item_ids
      rescue Exception => e
        ReloadedMart.log_exception("Daily featured item selection failed", e)
        []
      end

      def daily_featured_day_key(context = {})
        Rules.today_key(context)
      end

      def daily_featured_entry_ids(entries = nil, context = {})
        daily_featured_entries(entries, context).map(&:id)
      rescue
        []
      end

      def daily_featured_entry_id(entries = nil, context = {})
        daily_featured_entry_ids(entries, context).first
      rescue
        nil
      end

      def daily_featured?(entry, context = {})
        return false unless entry
        return false unless daily_featured_automation_enabled?
        return false unless daily_featured_enabled?(daily_featured_config)
        return true if entry.raw.is_a?(Hash) && Rules.truthy?(entry.raw["daily_featured_pool"] || entry.raw[:daily_featured_pool])
        daily_featured_entry_ids(nil, context).include?(entry.id.to_s)
      rescue
        false
      end

      def daily_featured_modifier(entry, context = {})
        config = daily_featured_config
        value = daily_featured_discount_percent(config, context, entry)
        return nil if value.to_i <= 0
        {
          :id => "daily_featured",
          :label => "Daily Featured",
          :type => "percent",
          :value => -value.to_i.abs,
          :source => "daily_featured"
        }
      end

      def daily_featured_config
        configured = catalog.key?("daily_featured") ? catalog["daily_featured"] : catalog[:daily_featured]
        return DEFAULT_DAILY_FEATURED.merge("enabled" => false) if configured == false
        return DEFAULT_DAILY_FEATURED unless configured.is_a?(Hash)
        config = DEFAULT_DAILY_FEATURED.merge(stringify_hash(configured))
        if config.key?("discount_percent") && !config.key?("discount_min_percent")
          config["discount_min_percent"] = config["discount_percent"].to_i
        end
        if config.key?("discount_percent") && !config.key?("discount_max_percent")
          config["discount_max_percent"] = config["discount_percent"].to_i
        end
        config
      rescue
        DEFAULT_DAILY_FEATURED
      end

      def daily_featured_discount_percent(config, context = {}, entry = nil)
        min = (config["discount_min_percent"] || 10).to_i
        max = (config["discount_max_percent"] || 40).to_i
        min, max = max, min if min > max
        min = [[min, 10].max, 40].min
        max = [[max, 10].max, 40].min
        max = min if max < min
        span = max - min + 1
        item_key = daily_featured_discount_key(entry)
        seed = "#{Source.active_report&.catalog_version || DEFAULT_CATALOG_VERSION}:#{daily_featured_day_key(context)}:daily_featured_discount:#{item_key}"
        min + (deterministic_score(seed) % span)
      rescue
        10
      end

      def daily_featured_discount_key(entry)
        return "global" unless entry
        raw = entry.raw.is_a?(Hash) ? entry.raw : {}
        (raw["item"] || raw[:item] || entry.id || "global").to_s
      rescue
        "global"
      end

      def daily_featured_enabled?(config)
        return false if config == false
        return true unless config.is_a?(Hash) && config.key?("enabled")
        Rules.truthy?(config["enabled"])
      rescue
        false
      end

      def daily_featured_category_id(config)
        (config["category_id"] || DEFAULT_DAILY_FEATURED["category_id"]).to_s
      end

      def daily_featured_category_name(config)
        (config["category_name"] || DEFAULT_DAILY_FEATURED["category_name"]).to_s
      end

      def daily_featured_stock(config)
        value = config["stock"] || config[:stock]
        return nil if value.nil? || value.to_s.empty?
        [value.to_i, 0].max
      rescue
        nil
      end

      def daily_featured_stock_reset(config)
        value = (config["stock_reset"] || config[:stock_reset] || DEFAULT_DAILY_FEATURED["stock_reset"]).to_s
        STOCK_RESET_RULES.include?(value.to_sym) ? value : DEFAULT_DAILY_FEATURED["stock_reset"]
      rescue
        DEFAULT_DAILY_FEATURED["stock_reset"]
      end

      def daily_featured_entry_id_for(item_id)
        "daily_featured:#{item_id}"
      end

      def daily_featured_item_pool(config)
        blacklist = daily_featured_blacklist(config)
        cache_key = daily_featured_item_pool_cache_key(config, blacklist)
        if @daily_featured_item_pool_cache && @daily_featured_item_pool_cache[:key] == cache_key
          return Array(@daily_featured_item_pool_cache[:items])
        end
        items = []
        each_game_item do |item|
          items << item.id.to_s if daily_featured_item_allowed?(item, blacklist)
        end
        log_daily_featured_pool(items.length, blacklist.length)
        @daily_featured_item_pool_cache = { :key => cache_key, :items => items }
        items
      rescue Exception => e
        ReloadedMart.log_exception("Daily featured item pool failed", e)
        []
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

      def daily_featured_item_allowed?(item, blacklist)
        return false unless item
        return false if blacklist.include?(item.id.to_s)
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

      def daily_featured_blacklist(config)
        values = DAILY_FEATURED_ITEM_BLACKLIST.map { |item| item.to_s }
        values += Array(config["blacklist"] || config[:blacklist]).map { |item| item.to_s }
        values.uniq
      end

      def log_daily_featured_pool(count, blacklist_count)
        key = "#{Source.active_report&.catalog_version}:#{daily_featured_day_key}:pool:#{count}:#{blacklist_count}"
        return if @daily_featured_pool_log_key == key
        @daily_featured_pool_log_key = key
        if count.to_i <= 0
          ReloadedMart.log_warning("Daily featured item pool is empty blacklist=#{blacklist_count}")
        else
          ReloadedMart.log_debug("Daily featured item pool count=#{count} blacklist=#{blacklist_count}")
        end
      rescue
      end

      def log_daily_featured_generation(config, item_ids, generated)
        key = "#{Source.active_report&.catalog_version}:#{daily_featured_day_key}:generated:#{Array(item_ids).join(",")}:#{generated.length}"
        return if @daily_featured_generation_log_key == key
        @daily_featured_generation_log_key = key
        if generated.empty?
          ReloadedMart.log_warning("Daily featured generated no entries pool=#{config["pool"].inspect} selected=#{Array(item_ids).inspect}")
        else
          ReloadedMart.log_info("Daily featured generated entries=#{generated.length} selected=#{generated.map(&:id).join(",")}")
        end
      rescue
      end

      def daily_featured_cache_key(config, context = {})
        [
          Source.active_report&.catalog_version || DEFAULT_CATALOG_VERSION,
          daily_featured_day_key(context),
          daily_featured_config_cache_key(config)
        ].join("|")
      rescue
        "#{DEFAULT_CATALOG_VERSION}|unknown"
      end

      def daily_featured_config_cache_key(config)
        keys = %w[
          enabled count discount_min_percent discount_max_percent category_id
          category_name pool stock stock_reset
        ]
        parts = keys.map { |key| "#{key}=#{config[key].inspect}" }
        parts << "blacklist=#{daily_featured_blacklist(config).sort.join(",")}"
        parts.join(";")
      rescue
        config.inspect
      end

      def daily_featured_item_pool_cache_key(config, blacklist)
        [
          (config["pool"] || config[:pool] || DEFAULT_DAILY_FEATURED["pool"]).to_s,
          Array(blacklist).map(&:to_s).sort.join(",")
        ].join("|")
      rescue
        "game_items"
      end

      def log_daily_featured_skip(reason, config)
        key = "#{Source.active_report&.catalog_version}:#{daily_featured_day_key}:skip:#{reason}:#{automation_config.inspect}:#{config.inspect}"
        return if @daily_featured_skip_log_key == key
        @daily_featured_skip_log_key = key
        ReloadedMart.log_warning("Daily featured skipped reason=#{reason} automation=#{automation_config.inspect} config=#{config.inspect}")
      rescue
      end

      def catalog_item_ids(entries)
        Array(entries).map do |entry|
          next nil unless entry && entry.kind == :item
          raw = entry.raw.is_a?(Hash) ? entry.raw : {}
          (raw["item"] || raw[:item] || entry.id).to_s
        end.compact.uniq
      rescue
        []
      end

      def deterministic_score(text)
        text.to_s.bytes.inject(2_166_136_261) do |hash, byte|
          ((hash ^ byte) * 16_777_619) & 0xffffffff
        end
      end

      def stringify_hash(hash)
        hash.each_with_object({}) do |(key, value), memo|
          memo[key.to_s] = value
        end
      rescue
        {}
      end

      def profile_key(context = {})
        return context[:profile].to_s if context[:profile]
        return $Trainer.selected_difficulty.to_s if $Trainer && $Trainer.respond_to?(:selected_difficulty)
        "default"
      rescue
        "default"
      end

      def countdowns(context = {})
        events.map do |event|
          until_value = event["available_until"] || event[:available_until]
          seconds = Rules.seconds_until(until_value, context)
          next nil unless seconds
          {
            :id => (event["id"] || event[:id]).to_s,
            :label => (event["label"] || event["name"] || event[:label] || event[:name]).to_s,
            :seconds => seconds,
            :text => Rules.format_duration(seconds)
          }
        end.compact
      end
    end
  end

  module Stock
    class << self
      def data
        value = ReloadedMart.state(:stock, {})
        value.is_a?(Hash) ? value : {}
      end

      def remaining(entry)
        return nil unless entry
        reset_if_needed(entry)
        configured = normalize_stock(entry.stock)
        return nil if configured.nil?
        [configured - purchased(entry.id), 0].max
      end

      def purchased(entry_id)
        data[entry_id.to_s].to_i
      end

      def reset_data
        value = ReloadedMart.state(:stock_resets, {})
        value.is_a?(Hash) ? value : {}
      end

      def unlimited?(entry)
        remaining(entry).nil?
      end

      def sold_out?(entry)
        value = remaining(entry)
        !value.nil? && value <= 0
      end

      def can_take?(entry, quantity = 1)
        value = remaining(entry)
        value.nil? || value >= quantity.to_i
      end

      def record_purchase(entry_id, quantity = 1)
        stock = data
        id = entry_id.to_s
        stock[id] = stock[id].to_i + quantity.to_i
        ReloadedMart.set_state(:stock, stock)
        ReloadedMart.emit(EVENT_STOCK_CHANGED, {
          :entry_id => id,
          :purchased => stock[id],
          :quantity => quantity.to_i
        })
        true
      rescue Exception => e
        ReloadedMart.log_exception("Failed to record Mart stock for #{entry_id}", e)
        false
      end

      def reset_entry(entry_id)
        stock = data
        stock.delete(entry_id.to_s)
        ReloadedMart.set_state(:stock, stock)
      end

      def reset_all
        ReloadedMart.set_state(:stock, {})
        ReloadedMart.set_state(:stock_resets, {})
      end

      def normalize_stock(value)
        return nil if value.nil? || value.to_s.strip.empty?
        [value.to_i, 0].max
      end

      def reset_if_needed(entry, context = {})
        return false if defined?(Economy) && !Economy.automation_enabled?("restocks")
        rule = (entry.stock_reset || :never).to_sym
        return false if rule == :never
        period = reset_period(rule, context)
        return false if period.to_s.empty?
        resets = reset_data
        key = entry.id.to_s
        return false if resets[key].to_s == period.to_s
        reset_entry(key)
        resets = reset_data
        resets[key] = period.to_s
        ReloadedMart.set_state(:stock_resets, resets)
        ReloadedMart.log_info("Mart stock reset entry=#{key} rule=#{rule} period=#{period}")
        true
      rescue Exception => e
        ReloadedMart.log_exception("Failed to apply Mart stock reset for #{entry&.id}", e)
        false
      end

      def reset_period(rule, context = {})
        case rule.to_sym
        when :daily then Rules.today_key(context)
        when :weekly then Rules.week_key(context)
        when :monthly then Rules.month_key(context)
        when :catalog_version then (Source.active_report&.catalog_version || DEFAULT_CATALOG_VERSION).to_s
        when :stock_epoch then (Source.active_raw && Source.active_raw["stock_epoch"]).to_s
        else ""
        end
      end

      def restock_seconds(entry, context = {})
        return nil unless entry
        rule = (entry.stock_reset || :never).to_sym
        time = Rules.now(context)
        case rule
        when :daily
          tomorrow = Time.new(time.year, time.month, time.day) + 86_400 rescue nil
          tomorrow ? tomorrow.to_i - time.to_i : nil
        when :weekly
          days = 7 - time.wday
          days = 7 if days <= 0
          target = Time.new(time.year, time.month, time.day) + days * 86_400 rescue nil
          target ? target.to_i - time.to_i : nil
        when :monthly
          year = time.month == 12 ? time.year + 1 : time.year
          month = time.month == 12 ? 1 : time.month + 1
          target = Time.new(year, month, 1) rescue nil
          target ? target.to_i - time.to_i : nil
        else
          nil
        end
      rescue
        nil
      end
    end
  end

  module Claims
    class << self
      def data
        value = ReloadedMart.state(:claims, {})
        value.is_a?(Hash) ? value : {}
      end

      def claimed?(entry_id)
        data[entry_id.to_s].to_i > 0
      end

      def count(entry_id)
        data[entry_id.to_s].to_i
      end

      def record(entry_id, quantity = 1)
        claims = data
        id = entry_id.to_s
        claims[id] = claims[id].to_i + quantity.to_i
        ReloadedMart.set_state(:claims, claims)
      end
    end
  end

  module Limits
    class << self
      def data
        value = ReloadedMart.state(:limits, {})
        value.is_a?(Hash) ? value : {}
      end

      def daily_data
        value = ReloadedMart.state(:limits_daily, {})
        value.is_a?(Hash) ? value : {}
      end

      def purchased(entry_id)
        data[entry_id.to_s].to_i
      end

      def daily_purchased(entry_id, context = {})
        bucket = daily_data[Rules.today_key(context)] || {}
        bucket[entry_id.to_s].to_i
      end

      def max_per_purchase(entry)
        value = entry && entry.limits ? (entry.limits["max_per_purchase"] || entry.limits[:max_per_purchase]) : nil
        value.nil? ? nil : [value.to_i, 1].max
      end

      def max_per_save(entry)
        value = entry && entry.limits ? (entry.limits["max_per_save"] || entry.limits[:max_per_save]) : nil
        value.nil? ? nil : [value.to_i, 0].max
      end

      def max_per_day(entry)
        value = entry && entry.limits ? (entry.limits["max_per_day"] || entry.limits[:max_per_day]) : nil
        value.nil? ? nil : [value.to_i, 0].max
      end

      def one_time?(entry)
        return false unless entry && entry.limits
        value = if entry.limits.key?("one_time")
                  entry.limits["one_time"]
                elsif entry.limits.key?(:one_time)
                  entry.limits[:one_time]
                else
                  nil
                end
        return true if entry.kind == :gift && value.nil?
        value == true || value.to_s.downcase == "true" || value.to_s == "1"
      end

      def can_purchase?(entry, quantity = 1, context = {})
        return TransactionResult.new(false, :missing_entry, "This entry is unavailable.") unless entry
        max_qty = max_per_purchase(entry)
        if max_qty && quantity.to_i > max_qty
          return TransactionResult.new(false, :over_purchase_limit, "You can't buy that many at once.", :max => max_qty)
        end
        if one_time?(entry) && Claims.claimed?(entry.id)
          return TransactionResult.new(false, :already_claimed, "This has already been claimed.")
        end
        max_save = max_per_save(entry)
        if max_save && purchased(entry.id) + quantity.to_i > max_save
          return TransactionResult.new(false, :over_save_limit, "You can't buy any more of this.", :max => max_save)
        end
        max_day = max_per_day(entry)
        if max_day && daily_purchased(entry.id, context) + quantity.to_i > max_day
          return TransactionResult.new(false, :over_daily_limit, "You can't buy any more of this today.", :max => max_day)
        end
        TransactionResult.new(true, :ok, "")
      end

      def record_purchase(entry_id, quantity = 1, context = {})
        limits = data
        id = entry_id.to_s
        limits[id] = limits[id].to_i + quantity.to_i
        ReloadedMart.set_state(:limits, limits)
        daily = daily_data
        day = Rules.today_key(context)
        daily[day] ||= {}
        daily[day][id] = daily[day][id].to_i + quantity.to_i
        ReloadedMart.set_state(:limits_daily, daily)
      end
    end
  end

  module Stats
    class << self
      def empty
        {
          "total_spent" => 0,
          "total_earned" => 0,
          "transactions" => 0,
          "items_bought" => {},
          "items_sold" => {},
          "by_currency" => {},
          "by_kind" => {},
          "by_category" => {},
          "by_tag" => {},
          "catalog_versions" => {}
        }
      end

      def data
        value = ReloadedMart.state(:stats, nil)
        value.is_a?(Hash) ? value : empty
      end

      def total_spent
        data["total_spent"].to_i
      end

      def save(value)
        ReloadedMart.set_state(:stats, value.is_a?(Hash) ? value : empty)
      end

      def record_purchase(cart, context = {})
        stats = data
        total = cart ? cart.total_price.to_i : 0
        currency = (context[:currency] || :money).to_s
        version = (context[:catalog_version] || DEFAULT_CATALOG_VERSION).to_s
        stats["total_spent"] = stats["total_spent"].to_i + total
        stats["transactions"] = stats["transactions"].to_i + 1
        stats["by_currency"] ||= {}
        stats["by_currency"][currency] = stats["by_currency"][currency].to_i + total
        stats["catalog_versions"] ||= {}
        stats["catalog_versions"][version] = stats["catalog_versions"][version].to_i + 1
        Array(cart&.lines).each { |line| record_line(stats, line) }
        save(stats)
      rescue Exception => e
        ReloadedMart.log_exception("Failed to record Mart purchase stats", e)
        false
      end

      def record_sale(item_id, quantity, total, context = {})
        stats = data
        id = item_id.to_s
        currency = (context[:currency] || :money).to_s
        stats["total_earned"] = stats["total_earned"].to_i + total.to_i
        stats["transactions"] = stats["transactions"].to_i + 1
        stats["by_currency"] ||= {}
        stats["by_currency"][currency] = stats["by_currency"][currency].to_i + total.to_i
        stats["items_sold"] ||= {}
        stats["items_sold"][id] ||= { "count" => 0, "earned" => 0 }
        stats["items_sold"][id]["count"] = stats["items_sold"][id]["count"].to_i + quantity.to_i
        stats["items_sold"][id]["earned"] = stats["items_sold"][id]["earned"].to_i + total.to_i
        save(stats)
      rescue Exception => e
        ReloadedMart.log_exception("Failed to record Mart sale stats", e)
        false
      end

      def record_line(stats, line)
        entry = line.entry
        return unless entry
        id = entry.id.to_s
        stats["items_bought"] ||= {}
        stats["items_bought"][id] ||= { "count" => 0, "spent" => 0, "kind" => entry.kind.to_s }
        stats["items_bought"][id]["count"] = stats["items_bought"][id]["count"].to_i + line.quantity.to_i
        stats["items_bought"][id]["spent"] = stats["items_bought"][id]["spent"].to_i + line.total_price.to_i
        stats["by_kind"] ||= {}
        stats["by_kind"][entry.kind.to_s] = stats["by_kind"][entry.kind.to_s].to_i + line.total_price.to_i
        stats["by_category"] ||= {}
        stats["by_category"][entry.category_id.to_s] = stats["by_category"][entry.category_id.to_s].to_i + line.total_price.to_i
        stats["by_tag"] ||= {}
        entry.tags.each do |tag|
          stats["by_tag"][tag.to_s] = stats["by_tag"][tag.to_s].to_i + line.total_price.to_i
        end
      end
    end
  end

  module Inventory
    class << self
      def money
        return 0 unless defined?($Trainer) && $Trainer
        $Trainer.money.to_i
      rescue
        0
      end

      def set_money(value)
        return false unless defined?($Trainer) && $Trainer
        $Trainer.money = value.to_i
        true
      rescue Exception => e
        ReloadedMart.log_exception("Failed to set Mart money", e)
        false
      end

      def can_afford?(amount)
        money >= amount.to_i
      end

      def charge(amount)
        price = amount.to_i
        return TransactionResult.new(false, :not_enough_money, "You don't have enough money.") unless can_afford?(price)
        return TransactionResult.new(false, :money_write_failed, "The transaction could not be completed.") unless set_money(money - price)
        TransactionResult.new(true, :ok, "")
      end

      def refund(amount)
        set_money(money + amount.to_i)
      end

      def quantity(item_id)
        return 0 unless defined?($PokemonBag) && $PokemonBag
        data = resolve_item(item_id)
        data ? $PokemonBag.pbQuantity(data.id).to_i : 0
      rescue
        0
      end

      def remove_item(item_id, quantity)
        data = resolve_item(item_id)
        return TransactionResult.new(false, :missing_item, "That item is unavailable.") unless data
        return TransactionResult.new(false, :not_enough_items, "You don't have enough of that item.") if self.quantity(data.id) < quantity.to_i
        return TransactionResult.new(false, :remove_failed, "The transaction could not be completed.") unless $PokemonBag.pbDeleteItem(data.id, quantity.to_i)
        TransactionResult.new(true, :ok, "", :item_id => data.id, :quantity => quantity.to_i)
      rescue Exception => e
        ReloadedMart.log_exception("Mart item removal failed", e)
        TransactionResult.new(false, :remove_exception, "The transaction could not be completed.")
      end

      def resolve_item(item_id)
        return nil if item_id.nil? || item_id.to_s.empty?
        GameData::Item.try_get(item_id) rescue nil
      end

      def normalize_grants(grants)
        totals = {}
        pokevial_total = 0
        special = []
        Array(grants).each do |grant|
          next unless grant.is_a?(Hash)
          if pokevial_grant?(grant)
            kind = pokevial_grant_kind(grant)
            qty = pokevial_quantity(grant).to_i
            if kind == :pokevial_refill
              special << { :type => :pokevial_refill }
            elsif kind == :pokevial_max_uses
              next if qty <= 0
              special << { :type => :pokevial_max_uses, :amount => qty }
            else
              next if qty <= 0
              pokevial_total += qty
            end
            next
          end
          data = resolve_item(grant[:item_id] || grant["item_id"] || grant[:id] || grant["id"] || grant[:item] || grant["item"])
          return { :ok => false, :code => :missing_item, :message => "One of the items is unavailable.", :item_id => grant.inspect } unless data
          qty = (grant[:quantity] || grant["quantity"] || grant[:qty] || grant["qty"] || 1).to_i
          next if qty <= 0
          totals[data.id] = totals[data.id].to_i + qty
        end
        special << { :type => :pokevial, :quantity => pokevial_total } if pokevial_total > 0
        { :ok => true, :grants => totals.map { |item_id, quantity| { :item_id => item_id, :quantity => quantity } }, :special_grants => special }
      rescue Exception => e
        ReloadedMart.log_exception("Failed to normalize Mart item grants", e)
        { :ok => false, :code => :grant_error, :message => "The transaction could not be completed." }
      end

      def can_store_grants?(grants)
        normalized = normalize_grants(grants)
        return TransactionResult.new(false, normalized[:code], normalized[:message], :item_id => normalized[:item_id]) unless normalized[:ok]
        if Array(normalized[:special_grants]).any? { |grant| [:pokevial, :pokevial_refill, :pokevial_max_uses].include?(grant[:type]) }
          unless defined?(ReloadedPokeVial)
            return TransactionResult.new(false, :pokevial_unavailable, "The PokeVial is unavailable.")
          end
          effective_max = ReloadedPokeVial.respond_to?(:configured_max_uses) ? ReloadedPokeVial.configured_max_uses : 0
          effective_uses = ReloadedPokeVial.respond_to?(:uses) ? ReloadedPokeVial.uses : 0
          Array(normalized[:special_grants]).sort_by { |grant| grant[:type] == :pokevial_max_uses ? 0 : grant[:type] == :pokevial_refill ? 1 : 2 }.each do |grant|
            if grant[:type] == :pokevial
              amount = grant[:quantity].to_i
              unless amount > 0 && effective_uses + amount <= effective_max
                return TransactionResult.new(false, :pokevial_full, "The PokeVial does not have enough empty charge slots.")
              end
              effective_uses += amount
            elsif grant[:type] == :pokevial_refill
              unless effective_uses < effective_max
                return TransactionResult.new(false, :pokevial_full, "The PokeVial is already full.")
              end
              effective_uses = effective_max
            elsif grant[:type] == :pokevial_max_uses
              unless grant[:amount].to_i > effective_max
                return TransactionResult.new(false, :pokevial_maxed, "The PokeVial is already upgraded enough.")
              end
              effective_max = grant[:amount].to_i
            end
          end
        end
        if normalized[:grants].empty?
          return TransactionResult.new(true, :ok, "", :grants => [], :special_grants => normalized[:special_grants])
        end
        return TransactionResult.new(false, :bag_unavailable, "The Bag is unavailable.") unless defined?($PokemonBag) && $PokemonBag
        pockets = duplicate_pockets
        normalized[:grants].each do |grant|
          data = resolve_item(grant[:item_id])
          return TransactionResult.new(false, :missing_item, "One of the items is unavailable.", :item_id => grant[:item_id]) unless data
          maxsize = simulated_max_size(pockets, data.pocket)
          unless ItemStorageHelper.pbStoreItem(pockets[data.pocket], maxsize, Settings::BAG_MAX_PER_SLOT, data.id, grant[:quantity].to_i, false)
            return TransactionResult.new(false, :bag_full, "There isn't enough room in the Bag.", :item_id => data.id, :quantity => grant[:quantity])
          end
        end
        TransactionResult.new(true, :ok, "", :grants => normalized[:grants], :special_grants => normalized[:special_grants])
      rescue Exception => e
        ReloadedMart.log_exception("Mart bag preflight failed", e)
        TransactionResult.new(false, :bag_preflight_failed, "There isn't enough room in the Bag.")
      end

      def apply_grants(grants)
        normalized = normalize_grants(grants)
        return TransactionResult.new(false, normalized[:code], normalized[:message], :item_id => normalized[:item_id]) unless normalized[:ok]
        applied = []
        normalized[:grants].each do |grant|
          data = resolve_item(grant[:item_id])
          unless data && $PokemonBag.pbStoreAllOrNone(data.id, grant[:quantity].to_i)
            rollback_grants(applied)
            return TransactionResult.new(false, :grant_failed, "The transaction could not be completed.", :item_id => grant[:item_id], :applied => applied)
          end
          applied << { :item_id => data.id, :quantity => grant[:quantity].to_i }
        end
        Array(normalized[:special_grants]).sort_by { |grant| grant[:type] == :pokevial_max_uses ? 0 : grant[:type] == :pokevial_refill ? 1 : 2 }.each do |grant|
          if grant[:type] == :pokevial_max_uses
            unless defined?(ReloadedPokeVial) && ReloadedPokeVial.unlock_max_uses(grant[:amount].to_i, source: :reloaded_mart, refill: false, notify: false)
              rollback_grants(applied)
              return TransactionResult.new(false, :pokevial_grant_failed, "The transaction could not be completed.", :applied => applied)
            end
            applied << { :type => :pokevial_max_uses, :amount => grant[:amount].to_i }
          elsif grant[:type] == :pokevial_refill
            unless defined?(ReloadedPokeVial) && ReloadedPokeVial.grant_full_refill(source: :reloaded_mart, notify: false)
              rollback_grants(applied)
              return TransactionResult.new(false, :pokevial_grant_failed, "The transaction could not be completed.", :applied => applied)
            end
            applied << { :type => :pokevial_refill }
          elsif grant[:type] == :pokevial
            added = ReloadedPokeVial.add_uses(grant[:quantity].to_i, source: :reloaded_mart, notify: false) if defined?(ReloadedPokeVial)
            if added.to_i <= 0
              rollback_grants(applied)
              return TransactionResult.new(false, :pokevial_grant_failed, "The transaction could not be completed.", :applied => applied)
            end
            applied << { :type => :pokevial, :quantity => added.to_i }
          end
        end
        register_tm_vault_grants(applied)
        TransactionResult.new(true, :ok, "", :applied => applied)
      rescue Exception => e
        ReloadedMart.log_exception("Mart grant application failed", e)
        rollback_grants(applied || [])
        TransactionResult.new(false, :grant_exception, "The transaction could not be completed.")
      end

      def rollback_grants(grants)
        return true unless defined?($PokemonBag) && $PokemonBag
        Array(grants).reverse_each do |grant|
          data = resolve_item(grant[:item_id] || grant["item_id"])
          $PokemonBag.pbDeleteItem(data.id, grant[:quantity].to_i) if data
        end
        true
      rescue Exception => e
        ReloadedMart.log_exception("Mart grant rollback failed", e)
        false
      end

      def register_tm_vault_grants(grants)
        return false unless defined?(TMVault)
        Array(grants).each do |grant|
          next if grant[:type] || grant["type"]
          data = resolve_item(grant[:item_id] || grant["item_id"])
          next unless data && data.respond_to?(:is_machine?) && data.is_machine? && data.move
          TMVault.register(data.move, notify: false, source: :reloaded_mart)
        end
        true
      rescue Exception => e
        ReloadedMart.log_exception("Mart TM Vault grant registration failed", e)
        false
      end

      def pokevial_grant?(grant)
        return false unless grant.is_a?(Hash)
        marker = grant[:type] || grant["type"] || grant[:kind] || grant["kind"] || grant[:grant_type] || grant["grant_type"]
        marker ||= grant[:id] || grant["id"] || grant[:item] || grant["item"] || grant[:item_id] || grant["item_id"]
        pokevial_grant_markers.include?(marker.to_s)
      rescue
        false
      end

      def pokevial_grant_kind(grant)
        marker = grant[:type] || grant["type"] || grant[:kind] || grant["kind"] || grant[:grant_type] || grant["grant_type"]
        marker ||= grant[:id] || grant["id"] || grant[:item] || grant["item"] || grant[:item_id] || grant["item_id"]
        text = marker.to_s
        return :pokevial_refill if ["pokevial_refill", "poke_vial_refill", "POKEVIAL_REFILL", "refill_pokevial"].include?(text)
        return :pokevial_max_uses if ["pokevial_max", "pokevial_max_uses", "POKEVIAL_MAX_USES", "pokevial_unlock", "poke_vial_unlock"].include?(text)
        :pokevial
      rescue
        :pokevial
      end

      def pokevial_grant_markers
        ["pokevial", "poke_vial", "pokevial_charge", "POKEVIAL_CHARGE", "pokevial_uses", "POKEVIAL_USES", "pokevial_refill", "poke_vial_refill",
         "POKEVIAL_REFILL", "refill_pokevial", "pokevial_max", "pokevial_max_uses", "POKEVIAL_MAX_USES",
         "pokevial_unlock", "poke_vial_unlock"]
      end

      def pokevial_quantity(grant)
        value = grant[:max_uses] || grant["max_uses"] || grant[:max] || grant["max"]
        value ||= grant[:pokevial_uses] || grant["pokevial_uses"] || grant[:uses] || grant["uses"] || grant[:qty] || grant["qty"] || grant[:quantity] || grant["quantity"] || 1
        value
      rescue
        0
      end

      def duplicate_pockets
        source = $PokemonBag.pockets
        source.map do |pocket|
          Array(pocket).map { |slot| slot ? [slot[0], slot[1]] : nil }
        end
      end

      def simulated_max_size(pockets, pocket)
        maxsize = $PokemonBag.maxPocketSize(pocket)
        maxsize = pockets[pocket].length + 1 if maxsize < 0
        maxsize
      end
    end
  end

  module Catalog
    class << self
      def load(raw, source: :unknown)
        migrated = Migrations.migrate(raw)
        result = normalize(migrated, source: source)
        result[:raw] = migrated
        result
      end

      def normalize(raw, source: :unknown)
        report = ValidationReport.new(
          catalog_version: catalog_version(raw),
          source: source
        )
        validate_schema(raw, report)
        entries = []
        raw_entries(raw).each do |entry_raw|
          entry = normalize_entry(entry_raw, report)
          if entry
            report.accept(entry)
            entries << entry
          end
        end
        log_report(report)
        { :entries => entries, :report => report, :raw => raw }
      rescue Exception => e
        ReloadedMart.log_exception("Catalog normalization failed", e)
        report = ValidationReport.new(source: source)
        report.error("catalog", "normalization_failed", :error => e.message)
        { :entries => [], :report => report, :raw => Migrations.empty_catalog }
      end

      def catalog_version(raw)
        return DEFAULT_CATALOG_VERSION unless raw.is_a?(Hash)
        (raw["catalog_version"] || raw[:catalog_version] || raw["version"] || DEFAULT_CATALOG_VERSION).to_s
      end

      def schema_version(raw)
        return 0 unless raw.is_a?(Hash)
        (raw["schema_version"] || raw[:schema_version] || 0).to_i
      end

      def validate_schema(raw, report)
        version = schema_version(raw)
        if version > SCHEMA_VERSION
          report.error("catalog", "unsupported_schema_version", :schema_version => version, :supported => SCHEMA_VERSION)
        elsif version <= 0
          report.record(:warning, "catalog", "missing_schema_version")
        end
      end

      def raw_entries(raw)
        return [] unless raw.is_a?(Hash)
        entries = raw["entries"] || raw[:entries]
        return entries if entries.is_a?(Array)
        legacy = []
        Array(raw["items"] || raw[:items]).each { |item| legacy << { "kind" => "item", "item" => item } }
        Array(raw["bundles"] || raw[:bundles]).each { |bundle| legacy << bundle.merge("kind" => "bundle") if bundle.is_a?(Hash) }
        Array(raw["gifts"] || raw[:gifts]).each { |gift| legacy << gift.merge("kind" => "gift") if gift.is_a?(Hash) }
        legacy
      end

      def normalize_entry(raw, report)
        unless raw.is_a?(Hash)
          report.skip("unknown", "entry_not_hash")
          return nil
        end
        kind = (raw["kind"] || raw[:kind] || raw["type"] || raw[:type] || "item").to_s
        id = raw["id"] || raw[:id] || raw["item"] || raw[:item]
        id = id.to_s
        if id.empty?
          report.skip("unknown", "missing_entry_id")
          return nil
        end
        unless ENTRY_KINDS.include?(kind.downcase.to_sym)
          report.skip(id, "unknown_entry_kind", :kind => kind)
          return nil
        end
        entry = CatalogEntry.new(
          :id => id,
          :kind => kind,
          :name => raw["name"] || raw[:name] || id,
          :category_id => raw["category_id"] || raw[:category_id] || raw["category"] || raw[:category] || "items",
          :category_ids => raw["category_ids"] || raw[:category_ids] || raw["categories"] || raw[:categories],
          :category_name => raw["category_name"] || raw[:category_name] || raw["category"] || raw[:category] || "ITEMS",
          :tags => raw["tags"] || raw[:tags],
          :price => raw["price"] || raw[:price],
          :sell_price => raw["sell_price"] || raw[:sell_price],
          :currency => raw["currency"] || raw[:currency] || :money,
          :stock => raw["stock"] || raw[:stock],
          :stock_reset => raw["stock_reset"] || raw[:stock_reset] || :never,
          :availability => raw["availability"] || raw[:availability] || {},
          :limits => raw["limits"] || raw[:limits] || {},
          :display => raw["display"] || raw[:display] || {},
          :dependencies => raw["dependencies"] || raw[:dependencies] || raw["requires"] || raw[:requires] || {},
          :grants => raw["grants"] || raw[:grants] || raw["items"] || raw[:items],
          :raw => raw
        )
        return nil unless validate_entry_fields(entry, report)
        return nil unless dependencies_available?(entry, report)
        entry
      end

      def validate_entry_fields(entry, report)
        if !entry.stock.nil? && entry.stock.to_i < 0
          report.skip(entry.id, "invalid_stock", :stock => entry.stock)
          return false
        end
        if entry.bundle_like?
          grant_result = validate_bundle_grants(entry)
          unless grant_result[:ok]
            report.skip(entry.id, grant_result[:reason], grant_result[:details])
            return false
          end
        end
        if entry.stock_reset && !STOCK_RESET_RULES.include?(entry.stock_reset.to_sym)
          report.record(:warning, entry.id, "unknown_stock_reset_rule", :stock_reset => entry.stock_reset)
        end
        if mystery_box_entry?(entry)
          total = entry.grants.inject(0) do |sum, grant|
            next sum unless grant.is_a?(Hash)
            sum + (grant["probability"] || grant[:probability] || grant["chance"] || grant[:chance] || grant["weight"] || grant[:weight]).to_i
          end
          report.record(:warning, entry.id, "mystery_probability_total_not_100", :total => total) if total != 100
        end
        true
      end

      def validate_bundle_grants(entry)
        grants = Array(entry.grants)
        return { :ok => false, :reason => "empty_bundle_grants", :details => {} } if grants.empty?
        grants.each_with_index do |grant, index|
          if pokevial_grant?(grant)
            quantity = pokevial_grant_kind(grant) == :pokevial_refill ? 1 : pokevial_quantity(grant).to_i
            if quantity <= 0
              return { :ok => false, :reason => "invalid_bundle_grant", :details => { :index => index, :item => "pokevial", :field => "quantity" } }
            end
            next
          end
          item_id, quantity = grant_item_and_quantity(grant)
          if item_id.nil? || item_id.to_s.empty?
            return { :ok => false, :reason => "invalid_bundle_grant", :details => { :index => index, :field => "item" } }
          end
          if quantity.to_i <= 0
            return { :ok => false, :reason => "invalid_bundle_grant", :details => { :index => index, :item => item_id.to_s, :field => "quantity" } }
          end
        end
        { :ok => true, :reason => nil, :details => {} }
      rescue Exception => e
        ReloadedMart.log_exception("Mart bundle grant validation failed for #{entry&.id}", e)
        { :ok => false, :reason => "bundle_grant_validation_failed", :details => { :error => e.message } }
      end

      def mystery_box_entry?(entry)
        return false unless entry && entry.kind == :bundle
        display = entry.display.is_a?(Hash) ? entry.display : {}
        raw = entry.raw.is_a?(Hash) ? entry.raw : {}
        Rules.truthy?(display["mystery_box"] || display[:mystery_box] || raw["mystery_box"] || raw[:mystery_box])
      rescue
        false
      end

      def dependencies_available?(entry, report)
        missing_items = []
        required_items = Array(entry.dependencies["items"] || entry.dependencies[:items])
        required_items.each do |item_id|
          missing_items << item_id unless item_exists?(item_id)
        end
        if entry.bundle_like?
          entry.grants.each do |grant|
            next if pokevial_grant?(grant)
            grant_id, = grant_item_and_quantity(grant)
            missing_items << grant_id unless item_exists?(grant_id)
          end
        elsif entry.kind == :item
          item_id = entry.raw.is_a?(Hash) ? (entry.raw["item"] || entry.raw[:item] || entry.id) : entry.id
          missing_items << item_id unless item_exists?(item_id)
        end
        missing_items.compact!
        missing_items.uniq!
        return true if missing_items.empty?
        report.skip(entry.id, "missing_required_items", :items => missing_items.map { |item| item.to_s })
        false
      end

      def item_exists?(item_id)
        return false if item_id.nil? || item_id.to_s.empty?
        GameData::Item.exists?(item_id) rescue !!(GameData::Item.try_get(item_id) rescue nil)
      end

      def pokevial_grant?(grant)
        return false unless grant.is_a?(Hash)
        marker = grant["type"] || grant[:type] || grant["kind"] || grant[:kind] || grant["grant_type"] || grant[:grant_type]
        marker ||= grant["id"] || grant[:id] || grant["item"] || grant[:item] || grant["item_id"] || grant[:item_id]
        pokevial_grant_markers.include?(marker.to_s)
      rescue
        false
      end

      def pokevial_grant_kind(grant)
        marker = grant["type"] || grant[:type] || grant["kind"] || grant[:kind] || grant["grant_type"] || grant[:grant_type]
        marker ||= grant["id"] || grant[:id] || grant["item"] || grant[:item] || grant["item_id"] || grant[:item_id]
        text = marker.to_s
        return :pokevial_refill if ["pokevial_refill", "poke_vial_refill", "POKEVIAL_REFILL", "refill_pokevial"].include?(text)
        return :pokevial_max_uses if ["pokevial_max", "pokevial_max_uses", "POKEVIAL_MAX_USES", "pokevial_unlock", "poke_vial_unlock"].include?(text)
        :pokevial
      rescue
        :pokevial
      end

      def pokevial_grant_markers
        ["pokevial", "poke_vial", "pokevial_charge", "POKEVIAL_CHARGE", "pokevial_uses", "POKEVIAL_USES", "pokevial_refill", "poke_vial_refill",
         "POKEVIAL_REFILL", "refill_pokevial", "pokevial_max", "pokevial_max_uses", "POKEVIAL_MAX_USES",
         "pokevial_unlock", "poke_vial_unlock"]
      end

      def pokevial_quantity(grant)
        return 0 unless grant.is_a?(Hash)
        value = grant["max_uses"] || grant[:max_uses] || grant["max"] || grant[:max]
        value ||= grant["pokevial_uses"] || grant[:pokevial_uses] || grant["uses"] || grant[:uses] || grant["qty"] || grant[:qty] || grant["quantity"] || grant[:quantity] || 1
        value
      rescue
        0
      end

      def grant_item_and_quantity(grant)
        if grant.is_a?(Hash)
          item_id = grant["id"] || grant[:id] || grant["item"] || grant[:item] || grant["item_id"] || grant[:item_id]
          quantity = grant["qty"] || grant[:qty] || grant["quantity"] || grant[:quantity] || 1
        else
          item_id = grant
          quantity = 1
        end
        [item_id, quantity]
      end

      def item_data(item_id)
        GameData::Item.try_get(item_id) rescue nil
      end

      def log_report(report)
        summary = report.summary
        ReloadedMart.log_info(
          "Mart catalog #{summary[:catalog_version]} source=#{summary[:source]} accepted=#{summary[:accepted]} skipped=#{summary[:skipped]} issues=#{summary[:issues]}"
        )
        report.skipped.each do |skip|
          ReloadedMart.log_warning("Mart catalog skipped entry=#{skip[:entry_id]} reason=#{skip[:reason]} details=#{skip[:details].inspect}")
        end
        report.issues.each do |issue|
          next unless issue[:level] == :error
          ReloadedMart.log_warning("Mart catalog issue entry=#{issue[:entry_id]} reason=#{issue[:reason]} details=#{issue[:details].inspect}")
        end
        if defined?(Reloaded::Log) && Reloaded::Log.respond_to?(:debug)
          report.issues.each do |issue|
            next if issue[:level] == :error
            ReloadedMart.log_debug("Mart catalog issue entry=#{issue[:entry_id]} reason=#{issue[:reason]} details=#{issue[:details].inspect}")
          end
        end
      end
    end
  end

  module Migrations
    class << self
      def migrate(raw)
        return empty_catalog unless raw.is_a?(Hash)
        return normalize_new_schema(raw) if raw["entries"].is_a?(Array) || raw[:entries].is_a?(Array)
        return migrate_reference_schema(raw) if reference_schema?(raw)
        normalize_new_schema(raw)
      rescue Exception => e
        ReloadedMart.log_exception("Mart catalog migration failed", e)
        empty_catalog
      end

      def empty_catalog
        {
          "schema_version" => SCHEMA_VERSION,
          "catalog_version" => DEFAULT_CATALOG_VERSION,
          "entries" => [],
          "categories" => [],
          "promo_codes" => [],
          "banner" => {}
        }
      end

      def normalize_new_schema(raw)
        data = stringify_json_keys(raw)
        data["schema_version"] ||= SCHEMA_VERSION
        data["catalog_version"] ||= data["version"] || DEFAULT_CATALOG_VERSION
        data["entries"] ||= []
        data["promo_codes"] ||= []
        data
      end

      def reference_schema?(raw)
        raw.key?("active_preset") || raw.key?("active") || raw.key?("presets") || raw.key?("special_categories") || raw.key?("featured_items")
      end

      def migrate_reference_schema(raw)
        source = stringify_json_keys(raw)
        active = active_preset(source)
        entries = []
        entries.concat(entries_from_special_categories(source))
        entries.concat(entries_from_preset(active)) if active
        {
          "schema_version" => SCHEMA_VERSION,
          "catalog_version" => source["catalog_version"] || source["version"] || active && active["name"] || DEFAULT_CATALOG_VERSION,
          "banner" => banner_from_preset(active),
          "categories" => categories_from_reference(source, active),
          "entries" => entries,
          "economy_events" => source["economy_events"] || [],
          "promo_codes" => source["promo_codes"] || [],
          "stock_epoch" => source["stock_epoch"]
        }
      end

      def active_preset(source)
        presets = Array(source["presets"]).select { |entry| entry.is_a?(Hash) }
        name = source["active_preset"] || source["active"]
        presets.find { |entry| entry["name"].to_s == name.to_s } || presets.first
      end

      def entries_from_special_categories(source)
        entries = []
        Array(source["special_categories"]).each do |cat|
          next unless cat.is_a?(Hash)
          cat_id = cat["id"].to_s.empty? ? safe_id(cat["name"]) : cat["id"].to_s
          cat_name = cat["name"].to_s.empty? ? cat_id.upcase : cat["name"].to_s
          prices = cat["prices"].is_a?(Hash) ? cat["prices"] : {}
          stocks = cat["item_stock"].is_a?(Hash) ? cat["item_stock"] : {}
          currencies = cat["item_currencies"].is_a?(Hash) ? cat["item_currencies"] : {}
          Array(cat["items"]).each do |item_id|
            id_s = item_id.to_s
            entries << item_entry_hash(
              item_id,
              :category_id => cat_id,
              :category_name => cat_name,
              :price => price_buy(prices[id_s]),
              :sell_price => price_sell(prices[id_s]),
              :stock => stocks.key?(id_s) ? stocks[id_s] : nil,
              :currency => currencies[id_s],
              :tags => ["featured", "legacy_special"]
            )
          end
        end
        entries
      end

      def entries_from_preset(preset)
        entries = []
        prices = preset["prices"].is_a?(Hash) ? preset["prices"] : {}
        stocks = preset["item_stock"].is_a?(Hash) ? preset["item_stock"] : {}
        currencies = preset["item_currencies"].is_a?(Hash) ? preset["item_currencies"] : {}
        timed = timed_item_map(preset)
        Array(preset["items"]).each do |item_id|
          id_s = item_id.to_s
          entries << item_entry_hash(
            item_id,
            :category_id => "items",
            :category_name => "ITEMS",
            :price => price_buy(prices[id_s]),
            :sell_price => price_sell(prices[id_s]),
            :stock => stocks.key?(id_s) ? stocks[id_s] : nil,
            :currency => currencies[id_s],
            :availability => timed[id_s] || {}
          )
        end
        Array(preset["bundles"]).each do |bundle|
          next unless bundle.is_a?(Hash)
          entries << bundle_entry_hash(bundle)
        end
        entries
      end

      def item_entry_hash(item_id, attrs = {})
        id_s = item_id.to_s
        {
          "id" => "item:#{id_s}",
          "kind" => "item",
          "item" => item_id,
          "name" => attrs[:name] || id_s,
          "category_id" => attrs[:category_id] || "items",
          "category_name" => attrs[:category_name] || "ITEMS",
          "tags" => attrs[:tags] || [],
          "price" => attrs[:price],
          "sell_price" => attrs[:sell_price],
          "currency" => attrs[:currency] || "money",
          "stock" => attrs[:stock],
          "availability" => attrs[:availability] || {},
          "requires" => attrs[:requires] || {}
        }
      end

      def bundle_entry_hash(bundle)
        mystery = truthy?(bundle["mystery_box"] || bundle["mystery"] || bundle["hidden_contents"])
        {
          "id" => bundle["id"].to_s,
          "kind" => truthy?(bundle["gift"]) ? "gift" : "bundle",
          "name" => bundle["name"].to_s,
          "category_id" => safe_id(bundle["category"] || "bundles"),
          "category_name" => (bundle["category"] || "BUNDLES").to_s.upcase,
          "price" => bundle["price"].to_i,
          "stock" => bundle["stock"],
          "availability" => {
            "available_from" => bundle["available_from"],
            "available_until" => bundle["available_until"]
          },
          "display" => {
            "description" => mystery ? "???" : bundle["description"],
            "mystery_box" => mystery
          },
          "tags" => Array(bundle["tags"]) + [truthy?(bundle["gift"]) ? "gift" : "bundle"] + (mystery ? ["mystery_box"] : []),
          "grants" => Array(bundle["items"])
        }
      end

      def categories_from_reference(source, active)
        categories = []
        Array(active && active["categories_snapshot"]).each do |cat|
          next unless cat.is_a?(Hash)
          categories << {
            "id" => cat["id"].to_s,
            "name" => cat["name"].to_s,
            "enabled" => cat["enabled"] != false,
            "tags" => []
          }
        end
        Array(source["special_categories"]).each do |cat|
          next unless cat.is_a?(Hash)
          categories << {
            "id" => cat["id"].to_s.empty? ? safe_id(cat["name"]) : cat["id"].to_s,
            "name" => cat["name"].to_s,
            "enabled" => true,
            "tags" => ["featured"]
          }
        end
        categories.uniq { |cat| cat["id"] }
      end

      def banner_from_preset(preset)
        return {} unless preset.is_a?(Hash)
        {
          "active" => truthy?(preset["banner_active"]),
          "text" => preset["banner_text"].to_s
        }
      end

      def timed_item_map(preset)
        result = {}
        Array(preset["timed_items"]).each do |entry|
          next unless entry.is_a?(Hash)
          id = entry["id"].to_s
          result[id] = {
            "available_from" => entry["available_from"],
            "available_until" => entry["available_until"]
          }
        end
        result
      end

      def price_buy(value)
        value.is_a?(Array) ? value[0] : nil
      end

      def price_sell(value)
        value.is_a?(Array) ? value[1] : nil
      end

      def safe_id(value)
        text = value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_+|_+$/, "")
        text.empty? ? "items" : text
      end

      def truthy?(value)
        value == true || ["1", "true", "yes", "on"].include?(value.to_s.strip.downcase)
      end

      def stringify_json_keys(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, child), memo| memo[key.to_s] = stringify_json_keys(child) }
        when Array
          value.map { |child| stringify_json_keys(child) }
        else
          value
        end
      end
    end
  end

  module Pricing
    class << self
      def price_for(entry, context = {})
        base = base_price(entry, context)
        catalog = catalog_price(entry, base, context)
        modifiers = collect_modifiers(entry, context)
        final = apply_modifiers(catalog, modifiers, entry, context)
        PriceResult.new(
          base: base,
          catalog: catalog,
          modifiers: modifiers,
          final: final,
          currency: entry.currency
        )
      end

      def base_price(entry, _context = {})
        return 0 unless entry
        return entry.price.to_i if entry.kind == :bundle || entry.kind == :gift
        item_id = entry.raw.is_a?(Hash) ? (entry.raw["item"] || entry.raw[:item] || entry.id) : entry.id
        data = GameData::Item.try_get(item_id) rescue nil
        data ? data.price.to_i : 0
      end

      def catalog_price(entry, base, context = {})
        return 0 if entry.kind == :gift && entry.price.nil?
        if (context[:mode] || :buy).to_sym == :sell
          return entry.sell_price.to_i unless entry.sell_price.nil?
          return (base.to_i / 2).floor
        end
        entry.price.nil? ? base.to_i : entry.price.to_i
      end

      def apply_modifiers(amount, modifiers, _entry, _context)
        modifiers.inject(amount.to_i) do |value, modifier|
          apply_modifier(value, modifier)
        end
      end

      def apply_modifier(amount, modifier)
        return amount unless modifier.is_a?(Hash)
        case (modifier[:type] || modifier["type"]).to_s
        when "flat" then amount + (modifier[:value] || modifier["value"]).to_i
        when "percent" then (amount * (100 + (modifier[:value] || modifier["value"]).to_i) / 100.0).round
        when "set", "set_price" then (modifier[:value] || modifier["value"]).to_i
        when "min" then [amount, (modifier[:value] || modifier["value"]).to_i].max
        when "max" then [amount, (modifier[:value] || modifier["value"]).to_i].min
        else amount
        end
      end

      def collect_modifiers(entry, context = {})
        modifiers = []
        modifiers.concat(entry_modifiers(entry, context))
        modifiers.concat(Economy.matching_price_modifiers(entry, context))
        modifiers.concat(ReloadedMart.matching_promo_modifiers(entry, context))
        ReloadedMart.price_modifier_handlers.each do |handler|
          result = handler[:block].call(entry, context) rescue nil
          modifiers.concat(Array(result).compact)
        end
        modifiers
      end

      def entry_modifiers(entry, context = {})
        raw = entry.raw.is_a?(Hash) ? entry.raw : {}
        list = raw["modifiers"] || raw[:modifiers] || []
        Array(list).select { |modifier| modifier.is_a?(Hash) && Economy.modifier_applies?(modifier, entry, context) }.map do |modifier|
          Economy.normalize_modifier(modifier, { "id" => "entry:#{entry.id}" })
        end
      end
    end
  end

  module Availability
    class << self
      def available?(entry, context = {})
        result = check(entry, context)
        result.ok?
      end

      def hidden?(entry, context = {})
        result = check(entry, context)
        return false if result.ok?
        policy = display_policy(entry)
        policy == "hidden"
      rescue
        false
      end

      def locked?(entry, context = {})
        result = check(entry, context)
        !result.ok? && display_policy(entry) != "hidden"
      end

      def lock_text(entry, context = {})
        result = check(entry, context)
        return "" if result.ok?
        availability = entry && entry.availability.is_a?(Hash) ? entry.availability : {}
        (availability["lock_text"] || availability[:lock_text] || result.message || "This is unavailable.").to_s
      end

      def check(entry, context = {})
        return TransactionResult.new(false, :missing_entry, "This entry is unavailable.") unless entry
        availability = entry.availability.is_a?(Hash) ? entry.availability : {}
        return fail_result(:not_started, availability, "This is not available yet.") unless Rules.reached?(availability["available_from"] || availability[:available_from], context)
        return fail_result(:expired, availability, "This is no longer available.") if Rules.past?(availability["available_until"] || availability[:available_until], context)
        return fail_result(:not_enough_badges, availability, "This is not unlocked yet.") unless badges_ok?(availability)
        return fail_result(:missing_switch, availability, "This is not unlocked yet.") unless switches_ok?(availability)
        return fail_result(:variable_requirement, availability, "This is not unlocked yet.") unless variables_ok?(availability)
        return fail_result(:difficulty_blocked, availability, "This is not available in this mode.") unless difficulty_ok?(availability, context)
        return fail_result(:missing_mod, availability, "This requires another mod.") unless mods_ok?(entry)
        return fail_result(:missing_item, availability, "This requires another item.") unless items_ok?(entry)
        return fail_result(:already_claimed, availability, "This has already been claimed.") if Limits.one_time?(entry) && Claims.claimed?(entry.id)
        return TransactionResult.new(false, :sold_out, "This is sold out.") if Stock.sold_out?(entry)
        TransactionResult.new(true, :ok, "")
      end

      def fail_result(code, availability, default_message)
        message = availability["lock_text"] || availability[:lock_text] || default_message
        TransactionResult.new(false, code, message)
      end

      def display_policy(entry)
        availability = entry && entry.availability.is_a?(Hash) ? entry.availability : {}
        return "hidden" if Rules.truthy?(availability["hidden"] || availability[:hidden])
        return "locked" if Rules.truthy?(availability["visible_when_locked"] || availability[:visible_when_locked])
        (availability["display"] || availability[:display] || "hidden").to_s
      end

      def badges_ok?(availability)
        required = availability["requires_badges"] || availability[:requires_badges] || availability["min_badges"] || availability[:min_badges]
        return true if required.nil?
        Rules.badge_count >= required.to_i
      end

      def switches_ok?(availability)
        switches = availability["requires_switches"] || availability[:requires_switches]
        return true if switches.nil?
        Array(switches).all? do |entry|
          if entry.is_a?(Hash)
            id = entry["id"] || entry[:id]
            expected = entry.key?("value") ? entry["value"] : entry[:value]
            expected = true if expected.nil?
            Rules.switch_on?(id) == Rules.truthy?(expected)
          else
            Rules.switch_on?(entry)
          end
        end
      end

      def variables_ok?(availability)
        variables = availability["requires_variables"] || availability[:requires_variables]
        return true if variables.nil?
        Array(variables).all? do |entry|
          next false unless entry.is_a?(Hash)
          id = entry["id"] || entry[:id]
          op = (entry["op"] || entry[:op] || ">=").to_s
          target = entry["value"] || entry[:value] || 1
          compare_value(Rules.variable_value(id).to_i, op, target.to_i)
        end
      end

      def compare_value(actual, op, expected)
        case op
        when ">", "gt" then actual > expected
        when ">=", "gte" then actual >= expected
        when "<", "lt" then actual < expected
        when "<=", "lte" then actual <= expected
        when "=", "==", "eq" then actual == expected
        when "!=", "not" then actual != expected
        else actual >= expected
        end
      end

      def difficulty_ok?(availability, context = {})
        diff = Rules.difficulty(context)
        allow = availability["difficulty_allowlist"] || availability[:difficulty_allowlist]
        block = availability["difficulty_blocklist"] || availability[:difficulty_blocklist]
        return false if block && Array(block).map { |entry| entry.to_s }.include?(diff.to_s)
        return false if allow && !Array(allow).map { |entry| entry.to_s }.include?(diff.to_s)
        true
      end

      def mods_ok?(entry)
        required = entry.dependencies["mods"] || entry.dependencies[:mods]
        return true if required.nil?
        Array(required).all? { |mod_id| Rules.active_mod?(mod_id) }
      end

      def items_ok?(entry)
        required = entry.dependencies["owned_items"] || entry.dependencies[:owned_items]
        return true if required.nil?
        Array(required).all? do |item|
          if item.is_a?(Hash)
            Rules.item_owned?(item["id"] || item[:id], item["qty"] || item[:qty] || 1)
          else
            Rules.item_owned?(item, 1)
          end
        end
      end

      def remaining_time(entry, context = {})
        availability = entry && entry.availability.is_a?(Hash) ? entry.availability : {}
        Rules.seconds_until(availability["available_until"] || availability[:available_until], context)
      end

      def remaining_time_text(entry, context = {})
        Rules.format_duration(remaining_time(entry, context))
      end
    end
  end

  module Transactions
    class << self
      def build_cart(entry, quantity = 1, context = {})
        cart = Cart.new(source: context[:source] || :reloaded_mart)
        handler = ReloadedMart.entry_handler(entry.kind) || EntryHandler.new(entry.kind)
        grants = handler.grants_for(entry, quantity, context)
        price = Pricing.price_for(entry, context)
        cart.add(entry, quantity, grants, price)
      end

      def validate_cart(cart, context = {})
        return TransactionResult.new(false, :empty_cart, "There is nothing to buy.") if !cart || cart.empty?
        currency = cart_currency(cart)
        return TransactionResult.new(false, :unsupported_currency, "This currency is unavailable.") unless currency == :money
        cart.lines.each do |line|
          availability = Availability.check(line.entry, context)
          return availability unless availability.ok?
          limits = Limits.can_purchase?(line.entry, line.quantity, context)
          return limits unless limits.ok?
          unless Stock.can_take?(line.entry, line.quantity)
            return TransactionResult.new(false, :not_enough_stock, "There isn't enough stock left.")
          end
          handler = ReloadedMart.entry_handler(line.entry.kind) || EntryHandler.new(line.entry.kind)
          handler_result = handler.validate(line, context)
          return handler_result unless handler_result.ok?
        end
        unless Inventory.can_afford?(cart.total_price)
          return TransactionResult.new(false, :not_enough_money, "You don't have enough money.", :needed => cart.total_price, :available => Inventory.money)
        end
        storage = Inventory.can_store_grants?(cart.grant_items)
        return storage unless storage.ok?
        TransactionResult.new(true, :ok, "")
      rescue Exception => e
        ReloadedMart.log_exception("Cart validation failed", e)
        TransactionResult.new(false, :exception, "The transaction could not be completed.")
      end

      def complete_cart(cart, context = {})
        validation = validate_cart(cart, context)
        unless validation.ok?
          log_purchase_failure(cart, validation, :validation, context)
          ReloadedMart.emit(EVENT_PURCHASE_FAILED, event_context(cart, validation, context))
          return validation
        end
        ReloadedMart.emit(EVENT_PURCHASE_VALIDATED, event_context(cart, validation, context))
        amount = cart.total_price
        charge_amount = immediate_charge_amount(cart, context)
        charge = Inventory.charge(charge_amount)
        unless charge.ok?
          log_purchase_failure(cart, charge, :charge, context)
          ReloadedMart.emit(EVENT_PURCHASE_FAILED, event_context(cart, charge, context))
          return charge
        end
        grants = Inventory.apply_grants(cart.grant_items)
        unless grants.ok?
          Inventory.refund(charge_amount)
          log_purchase_failure(cart, grants, :grant, context)
          ReloadedMart.emit(EVENT_PURCHASE_FAILED, event_context(cart, grants, context))
          return grants
        end
        apply = apply_handlers(cart, context)
        unless apply.ok?
          Inventory.rollback_grants(grants.details[:applied])
          rollback_handler_side_effects(context)
          Inventory.refund(charge_amount)
          log_purchase_failure(cart, apply, :handler, context)
          ReloadedMart.emit(EVENT_PURCHASE_FAILED, event_context(cart, apply, context))
          return apply
        end
        record_success(cart, context)
        clear_handler_side_effect_bookkeeping(context)
        result = TransactionResult.new(true, :ok, "Purchase complete.", :applied => grants.details[:applied], :revealed => cart.grant_items)
        ReloadedMart.emit(EVENT_PURCHASE_COMPLETED, event_context(cart, result, context))
        log_purchase_success(cart, result, amount, context)
        result
      rescue Exception => e
        ReloadedMart.log_exception("Mart purchase failed unexpectedly", e)
        result = TransactionResult.new(false, :exception, "The transaction could not be completed.")
        ReloadedMart.emit(EVENT_PURCHASE_FAILED, event_context(cart, result, context))
        result
      end

      def complete_sale(item_id, quantity = 1, unit_price = nil, context = {})
        data = Inventory.resolve_item(item_id)
        unless data
          result = TransactionResult.new(false, :missing_item, "That item is unavailable.")
          ReloadedMart.emit(EVENT_SALE_FAILED, sale_context(item_id, quantity, 0, result, context))
          return result
        end
        qty = [quantity.to_i, 1].max
        price = unit_price.nil? ? (data.price.to_i / 2).floor : unit_price.to_i
        price = [price, 0].max
        total = price * qty
        removal = Inventory.remove_item(data.id, qty)
        unless removal.ok?
          ReloadedMart.emit(EVENT_SALE_FAILED, sale_context(data.id, qty, total, removal, context))
          return removal
        end
        unless Inventory.refund(total)
          Inventory.apply_grants([{ :item_id => data.id, :quantity => qty }])
          result = TransactionResult.new(false, :money_write_failed, "The transaction could not be completed.")
          ReloadedMart.emit(EVENT_SALE_FAILED, sale_context(data.id, qty, total, result, context))
          return result
        end
        Stats.record_sale(data.id, qty, total, context.merge(:currency => :money))
        result = TransactionResult.new(true, :ok, "Sale complete.", :item_id => data.id, :quantity => qty, :total => total)
        ReloadedMart.emit(EVENT_SALE_COMPLETED, sale_context(data.id, qty, total, result, context))
        ReloadedMart.log_info("Mart sale complete item=#{data.id} quantity=#{qty} total=#{total}")
        result
      rescue Exception => e
        ReloadedMart.log_exception("Mart sale failed unexpectedly", e)
        result = TransactionResult.new(false, :exception, "The transaction could not be completed.")
        ReloadedMart.emit(EVENT_SALE_FAILED, sale_context(item_id, quantity, 0, result, context))
        result
      end

      def apply_handlers(cart, context = {})
        cart.lines.each do |line|
          handler = ReloadedMart.entry_handler(line.entry.kind) || EntryHandler.new(line.entry.kind)
          result = handler.apply(line, context)
          return result unless result.ok?
        end
        TransactionResult.new(true, :ok, "")
      rescue Exception => e
        ReloadedMart.log_exception("Mart handler application failed", e)
        TransactionResult.new(false, :handler_exception, "The transaction could not be completed.")
      end

      def immediate_charge_amount(cart, context = {})
        Array(cart&.lines).inject(0) do |sum, line|
          handler = ReloadedMart.entry_handler(line.entry.kind) || EntryHandler.new(line.entry.kind)
          handler.defer_charge?(line, context) ? sum : sum + line.total_price.to_i
        end
      rescue Exception => e
        ReloadedMart.log_exception("Mart immediate charge calculation failed", e)
        cart ? cart.total_price.to_i : 0
      end

      def rollback_handler_side_effects(context = {})
        Array(context[:activated_coupons]).each { |code| ReloadedMart.deactivate_coupon(code) }
        context[:activated_coupons] = []
        Array(context[:deferred_charges]).each { |amount| Inventory.refund(amount.to_i) }
        context[:deferred_charges] = []
      rescue Exception => e
        ReloadedMart.log_exception("Mart handler rollback failed", e)
      end

      def clear_handler_side_effect_bookkeeping(context = {})
        context[:activated_coupons] = []
        context[:deferred_charges] = []
      rescue Exception => e
        ReloadedMart.log_exception("Mart handler bookkeeping cleanup failed", e)
      end

      def record_success(cart, context = {})
        cart.lines.each do |line|
          Stock.record_purchase(line.entry.id, line.quantity)
          Limits.record_purchase(line.entry.id, line.quantity, context)
          Claims.record(line.entry.id, line.quantity) if Limits.one_time?(line.entry)
        end
        Stats.record_purchase(cart, context.merge(:currency => cart_currency(cart), :catalog_version => catalog_version))
        true
      end

      def cart_currency(cart)
        currencies = Array(cart&.lines).map { |line| line.price_result ? line.price_result.currency : line.entry.currency }.compact.uniq
        return :money if currencies.empty?
        return currencies.first.to_sym if currencies.length == 1
        :mixed
      rescue
        :money
      end

      def log_purchase_success(cart, result, amount, context = {})
        applied = Array(result.details[:applied] || result.details["applied"])
        ReloadedMart.log_info(
          "Mart purchase complete source=#{cart.source rescue :unknown} catalog=#{catalog_version} entries=#{entry_log_summary(cart)} total=#{amount.to_i} grants=#{grant_log_summary(applied)}"
        )
      rescue Exception => e
        ReloadedMart.log_exception("Mart purchase success logging failed", e)
      end

      def log_purchase_failure(cart, result, stage, context = {})
        ReloadedMart.log_warning(
          "Mart purchase failed stage=#{stage} code=#{result.code} source=#{cart&.source || context[:source] || :unknown} catalog=#{catalog_version} entries=#{entry_log_summary(cart)} total=#{cart ? cart.total_price : 0} details=#{safe_details(result.details)}"
        )
      rescue Exception => e
        ReloadedMart.log_exception("Mart purchase failure logging failed", e)
      end

      def entry_log_summary(cart)
        entries = Array(cart&.lines).map do |line|
          "#{line.entry_id}:#{line.entry_kind}x#{line.quantity}@#{line.total_price}"
        end
        entries.empty? ? "none" : entries.join("|")
      rescue
        "unavailable"
      end

      def grant_log_summary(grants)
        rows = Array(grants).map do |grant|
          item_id = grant[:item_id] || grant["item_id"] || grant[:id] || grant["id"] || grant[:item] || grant["item"]
          qty = grant[:quantity] || grant["quantity"] || grant[:qty] || grant["qty"] || 1
          "#{item_id}x#{qty}"
        end
        rows.empty? ? "none" : rows.join("|")
      rescue
        "unavailable"
      end

      def safe_details(details)
        return "{}" unless details.is_a?(Hash)
        details.map { |key, value| "#{key}=#{value.inspect}" }.join(",")
      rescue
        "{}"
      end

      def catalog_version
        Source.active_report&.catalog_version || DEFAULT_CATALOG_VERSION
      rescue
        DEFAULT_CATALOG_VERSION
      end

      def event_context(cart, result, context)
        {
          :source => (cart.source rescue :unknown),
          :catalog_version => catalog_version,
          :currency => cart ? cart_currency(cart) : :money,
          :lines => cart ? cart.lines.length : 0,
          :entries => cart ? cart.lines.map { |line| { :id => line.entry_id, :kind => line.entry_kind, :quantity => line.quantity, :price => line.total_price } } : [],
          :grants => cart ? cart.grant_items : [],
          :total_price => cart ? cart.total_price : 0,
          :result => result.code,
          :message => result.message,
          :details => result.details,
          :context => context || {}
        }
      end

      def sale_context(item_id, quantity, total, result, context)
        {
          :source => context[:source] || :reloaded_mart,
          :catalog_version => catalog_version,
          :currency => :money,
          :item_id => item_id,
          :quantity => quantity.to_i,
          :total_price => total.to_i,
          :result => result.code,
          :message => result.message,
          :details => result.details,
          :context => context || {}
        }
      end
    end
  end
end

ReloadedMart.install if defined?(ReloadedMart)

def pbOpenReloadedMart
  ReloadedMart.open if defined?(ReloadedMart)
end
