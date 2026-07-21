#======================================================
# Reloaded Mart Economy Events
# Author: Stonewall
#======================================================
# Owns curated, themed, and generated Economy Events.
# Only the winning event can affect the Mart at a time.
#======================================================

begin
  require "date"
  require "time"
rescue Exception
end

module ReloadedMart
  module EconomyEvents
    TYPE_PRIORITY = {
      "curated" => 300,
      "themed" => 200,
      "automated" => 100
    }.freeze
    DEFAULT_CYCLE_ANCHOR = "2026-01-01"
    EVENT_DAYS = 2
    OFF_DAYS = 1
    CYCLE_DAYS = EVENT_DAYS + OFF_DAYS
    LOCAL_AUTOMATION_FILE = File.expand_path(
      File.join(File.dirname(__FILE__), "..", "Data", "AutomatedEvents.json")
    )
    MAX_AUTOMATED_PERCENT = 50
    SUPPORTED_OPERATIONS = %w[
      discount_percent markup_percent subtract_flat add_flat
      percent flat set set_price min max
    ].freeze

    class << self
      def events(context = {})
        result = []
        result.concat(manual_events) if online_available?
        generated = generated_event(context)
        result << generated if generated
        result
      rescue Exception => e
        log_exception("Economy Event collection failed", e)
        []
      end

      def manual_events
        raw = active_raw
        Array(raw["economy_events"] || raw[:economy_events]).each_with_index.map do |event, index|
          normalize_event(event, index)
        end.compact
      rescue
        []
      end

      def automation_config
        return @automation_override if @automation_override.is_a?(Hash)
        @local_automation_config ||= load_local_automation
      rescue Exception => e
        log_exception("Local Economy Event automation access failed", e)
        {}
      end

      def local_automation_path
        LOCAL_AUTOMATION_FILE
      end

      def reload_local_automation!
        @local_automation_config = nil
        clear_cache
        automation_config
      end

      def with_automation_config(config)
        previous = @automation_override
        @automation_override = sanitize_local_automation(config)
        clear_cache
        yield
      ensure
        @automation_override = previous
        clear_cache
      end

      def generated_event(context = {})
        config = automation_config
        return nil unless truthy?(config["enabled"])
        templates = Array(config["templates"]).select { |template| template.is_a?(Hash) }
        return nil if templates.empty?
        position = cycle_position(context, config)
        return nil if position.nil? || position >= EVENT_DAYS
        cycle = cycle_index(context, config)
        template = template_for_cycle(templates, cycle, config)
        return nil unless template
        event = stringify_hash(deep_copy(template))
        event["id"] = "auto_cycle_#{cycle}"
        event["template_id"] = template_id(template)
        event["event_type"] = "automated"
        event["enabled"] = true
        event["generated"] = true
        event["priority"] = (event["priority"] || config["priority"] || 0).to_i
        event["available_from"] = format_time(cycle_start_time(cycle, config))
        event["available_until"] = format_time(cycle_end_time(cycle, config))
        event["label"] = event["name"] if event["label"].to_s.empty?
        event["name"] = event["label"] if event["name"].to_s.empty?
        event
      rescue Exception => e
        log_exception("Automated Economy Event generation failed", e)
        nil
      end

      def active_event(context = {})
        cache_key = active_event_cache_key(context)
        if @active_event_cache && @active_event_cache[:key] == cache_key
          return @active_event_cache[:event]
        end
        candidates = events(context).select { |event| scheduled_active?(event, context) }
        winner = candidates.sort_by { |event| winner_sort_key(event) }.first
        @active_event_cache = { :key => cache_key, :event => winner }
        winner
      rescue Exception => e
        log_exception("Economy Event winner selection failed", e)
        nil
      end

      def event_status(event, context = {})
        return :invalid unless event.is_a?(Hash)
        return :disabled unless event_enabled?(event)
        start_time = event_start_time(event)
        end_time = event_end_time(event)
        return :invalid unless start_time && end_time && end_time > start_time
        now = trusted_time(context)
        return :upcoming if now < start_time
        return :expired if now >= end_time
        winner = active_event(context)
        return :active if winner && event_id(winner) == event_id(event)
        return :scheduled unless winner
        winner_end = event_end_time(winner)
        return :superseded if winner_end.nil? || winner_end >= end_time
        :suspended
      rescue
        :invalid
      end

      def active?(event, context = {})
        winner = active_event(context)
        winner && event_id(winner) == event_id(event)
      rescue
        false
      end

      def matching_modifier(entry, context = {})
        event = active_event(context)
        return nil unless event && entry
        rule = matching_rule(event, entry, context)
        rule ? normalize_rule(rule, event) : nil
      rescue Exception => e
        log_exception("Economy Event price matching failed", e)
        nil
      end

      def matching_rule(event, entry, context = {})
        rules = pricing_rules(event)
        matches = []
        rules.each_with_index do |rule, index|
          next unless rule.is_a?(Hash)
          next unless rule_applies?(rule, entry, context)
          matches << [-(rule["priority"] || rule[:priority] || 0).to_i, index, rule]
        end
        row = matches.sort_by { |match| [match[0], match[1]] }.first
        row && row[2]
      rescue
        nil
      end

      def pricing_rules(event)
        return [] unless event.is_a?(Hash)
        Array(event["pricing_rules"] || event[:pricing_rules] || event["modifiers"] || event[:modifiers])
      end

      def rule_applies?(rule, entry, context = {})
        normalized = stringify_hash(rule)
        return false unless ReloadedMart::Economy.modifier_applies?(normalized, entry, context)
        currencies = target_values(normalized, "currency", "currencies")
        return false if currencies.any? && !currencies.include?(entry.currency.to_s)
        kinds = target_values(normalized, "kind", "kinds")
        return false if kinds.any? && !kinds.include?(entry.kind.to_s)
        exclusions = normalized["exclusions"]
        return false if exclusions.is_a?(Hash) && selector_defined?(exclusions) &&
                        selector_matches?(exclusions, entry, context)
        true
      rescue
        false
      end

      def normalize_rule(rule, event)
        source = stringify_hash(rule)
        operation = (source["operation"] || source["type"] || "discount_percent").to_s
        amount = source["value"].to_i
        type = operation
        value = amount
        case operation
        when "discount_percent"
          type = "percent"
          value = -amount.abs
        when "markup_percent"
          type = "percent"
          value = amount.abs
        when "subtract_flat"
          type = "flat"
          value = -amount.abs
        when "add_flat"
          type = "flat"
          value = amount.abs
        end
        {
          :id => (source["id"] || event_id(event)).to_s,
          :label => (source["label"] || event_label(event)).to_s,
          :type => type.to_s,
          :value => value,
          :source => "economy_event:#{event_id(event)}",
          :event_id => event_id(event),
          :event_type => event_type(event)
        }
      end

      def temporary_entries(context = {})
        event = active_event(context)
        return [] unless event
        raw_entries = Array(event["temporary_entries"] || event[:temporary_entries])
        return [] if raw_entries.empty?
        key = temporary_cache_key(event, raw_entries)
        return @temporary_cache[:entries] if @temporary_cache && @temporary_cache[:key] == key
        prepared = raw_entries.each_with_index.map do |entry, index|
          next nil unless entry.is_a?(Hash)
          row = stringify_hash(deep_copy(entry))
          row["id"] = "event:#{event_id(event)}:#{index + 1}" if row["id"].to_s.empty?
          row["source_type"] = "economy_event"
          row["event_id"] = event_id(event)
          row
        end.compact
        result = ReloadedMart::Catalog.normalize(
          {
            "schema_version" => ReloadedMart::SCHEMA_VERSION,
            "catalog_version" => "event:#{event_id(event)}",
            "entries" => prepared
          },
          :source => :economy_event
        )
        @temporary_cache = { :key => key, :entries => Array(result[:entries]) }
        @temporary_cache[:entries]
      rescue Exception => e
        log_exception("Economy Event temporary content failed", e)
        []
      end

      def clear_cache
        @temporary_cache = nil
        @active_event_cache = nil
        @winner_log_key = nil
        true
      end

      def banner_text(context = {})
        event = active_event(context)
        return "" unless event
        display = event["display"] || event[:display]
        display = {} unless display.is_a?(Hash)
        value = display["banner_text"] || display[:banner_text] ||
                event["banner_text"] || event[:banner_text]
        value.to_s
      rescue
        ""
      end

      def countdowns(context = {})
        event = active_event(context)
        return [] unless event
        display = event["display"] || event[:display]
        display = {} unless display.is_a?(Hash)
        show = display.key?("show_countdown") ? display["show_countdown"] : display[:show_countdown]
        return [] if show == false
        finish = event_end_time(event)
        return [] unless finish
        seconds = [(finish.to_f - trusted_time(context).to_f).floor, 0].max
        [{
          :id => event_id(event),
          :label => event_label(event),
          :seconds => seconds,
          :text => ReloadedMart::Rules.format_duration(seconds)
        }]
      rescue
        []
      end

      def summary_lines(context = {})
        event = active_event(context)
        return [] unless event
        lines = []
        lines << event_label(event)
        description = event_description(event)
        lines << description unless description.empty?
        lines << "Type: #{humanize(event_type(event))}"
        timer = countdowns(context).first
        lines << "Time Remaining: #{timer[:text]}" if timer
        pricing_rules(event).each do |rule|
          text = rule_summary(rule)
          lines << text unless text.empty?
        end
        count = Array(event["temporary_entries"] || event[:temporary_entries]).length
        lines << "Temporary Offerings: #{count}" if count > 0
        lines
      rescue
        []
      end

      def validate_catalog(raw, report)
        return true unless raw.is_a?(Hash) && report
        ids = {}
        catalog_entry_ids = Array(raw["entries"] || raw[:entries]).map do |entry|
          entry.is_a?(Hash) ? (entry["id"] || entry[:id]).to_s : ""
        end.reject(&:empty?)
        Array(raw["economy_events"] || raw[:economy_events]).each_with_index do |event, index|
          unless event.is_a?(Hash)
            report.error("economy_event_#{index + 1}", "event_not_hash")
            next
          end
          normalized = stringify_hash(event)
          id = normalized["id"].to_s
          if id.empty?
            id = "economy_event_#{index + 1}"
            report.error(id, "missing_economy_event_id")
          end
          report.error(id, "duplicate_economy_event_id") if ids[id]
          ids[id] = true
          next unless event_enabled?(normalized)
          type = event_type(normalized)
          report.error(id, "unknown_economy_event_type", :type => type) unless TYPE_PRIORITY.key?(type)
          start_time = event_start_time(normalized)
          end_time = event_end_time(normalized)
          report.error(id, "missing_or_invalid_event_start") unless start_time
          report.error(id, "missing_or_invalid_event_end") unless end_time
          report.error(id, "event_end_not_after_start") if start_time && end_time && end_time <= start_time
          rules = pricing_rules(normalized)
          temporary = Array(normalized["temporary_entries"])
          report.error(id, "event_has_no_effect") if rules.empty? && temporary.empty?
          rule_ids = {}
          rules.each_with_index do |rule, rule_index|
            validate_rule(id, rule, rule_index, report)
            next unless rule.is_a?(Hash)
            rule_id = (rule["id"] || rule[:id]).to_s
            next if rule_id.empty?
            report.error("#{id}:#{rule_id}", "duplicate_economy_rule_id") if rule_ids[rule_id]
            rule_ids[rule_id] = true
          end
          validate_temporary_entries(id, temporary, catalog_entry_ids, report)
        end
        validate_automation(
          raw["economy_event_automation"] || raw[:economy_event_automation],
          report,
          catalog_entry_ids
        )
        true
      rescue Exception => e
        log_exception("Economy Event catalog validation failed", e)
        report.error("economy_events", "economy_event_validation_failed", :error => e.message) rescue nil
        false
      end

      def event_id(event)
        (event["id"] || event[:id]).to_s
      rescue
        ""
      end

      def event_type(event)
        value = event["event_type"] || event[:event_type] || event["type"] || event[:type] || "curated"
        value.to_s.strip.downcase
      rescue
        "curated"
      end

      def event_label(event)
        (event["label"] || event[:label] || event["name"] || event[:name] || event_id(event)).to_s
      rescue
        ""
      end

      def event_description(event)
        display = event["display"] || event[:display]
        display = {} unless display.is_a?(Hash)
        (display["description"] || display[:description] ||
          event["description"] || event[:description]).to_s
      rescue
        ""
      end

      def event_start_time(event)
        availability = event["availability"] || event[:availability]
        value = availability["available_from"] || availability[:available_from] if availability.is_a?(Hash)
        value ||= event["available_from"] || event[:available_from]
        parse_eastern_time(value)
      rescue
        nil
      end

      def event_end_time(event)
        availability = event["availability"] || event[:availability]
        value = availability["available_until"] || availability[:available_until] if availability.is_a?(Hash)
        value ||= event["available_until"] || event[:available_until]
        parse_eastern_time(value)
      rescue
        nil
      end

      def trusted_time(context = {})
        return context[:now] if context[:now]
        if defined?(ReloadedMart::DailyFeatured) && ReloadedMart::DailyFeatured.respond_to?(:trusted_time)
          return ReloadedMart::DailyFeatured.trusted_time
        end
        Time.now
      rescue
        Time.now
      end

      def eastern_wall_time(context = {})
        value = trusted_time(context)
        if defined?(ReloadedMart::DailyFeatured) && ReloadedMart::DailyFeatured.respond_to?(:eastern_time)
          return ReloadedMart::DailyFeatured.eastern_time(value)
        end
        value
      rescue
        Time.now
      end

      def parse_eastern_time(value)
        return value if value.is_a?(Time)
        text = value.to_s.strip
        return nil if text.empty?
        if text =~ /(Z|[+\-]\d{2}:?\d{2})\z/i
          return Time.parse(text) rescue nil
        end
        match = text.match(/\A(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?\z/)
        match ||= text.match(/\A(\d{1,2})-(\d{1,2})-(\d{2,4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\z/)
        return Time.parse(text) rescue nil unless match
        if match[1].to_i > 31
          year, month, day = match[1].to_i, match[2].to_i, match[3].to_i
        else
          month, day, year = match[1].to_i, match[2].to_i, match[3].to_i
          year += 2000 if year < 100
        end
        eastern_local_time(year, month, day, (match[4] || 0).to_i, (match[5] || 0).to_i, (match[6] || 0).to_i)
      rescue
        nil
      end

      private

      def load_local_automation
        unless File.file?(LOCAL_AUTOMATION_FILE)
          ReloadedMart.log_warning("Local Economy Event automation file is missing") if defined?(ReloadedMart)
          return {}
        end
        text = File.read(LOCAL_AUTOMATION_FILE)
        raw = if defined?(Reloaded::RemoteData) && Reloaded::RemoteData.respond_to?(:parse_json_document)
                Reloaded::RemoteData.parse_json_document(text)
              else
                JSON.parse(text)
              end
        sanitize_local_automation(raw)
      rescue Exception => e
        log_exception("Local Economy Event automation load failed", e)
        {}
      end

      def sanitize_local_automation(value)
        return {} unless value.is_a?(Hash)
        config = deep_copy(value)
        config = config["automation"] if config["automation"].is_a?(Hash)
        config = stringify_hash(config)
        config["automation_id"] = "economy" if config["automation_id"].to_s.empty?
        config["cycle_anchor"] = DEFAULT_CYCLE_ANCHOR unless cycle_anchor_valid?(config["cycle_anchor"])
        config["revision"] = [config["revision"].to_i, 1].max
        config["priority"] = config["priority"].to_i
        config["templates"] = Array(config["templates"]).map do |template|
          sanitize_automated_template(template)
        end.compact
        config["enabled"] = false if config["templates"].empty?
        config
      end

      def sanitize_automated_template(value)
        return nil unless value.is_a?(Hash)
        template = deep_copy(value)
        remove_editor_fields!(template)
        return nil if template_id(template).empty?
        rules = pricing_rules(template).map { |rule| sanitize_automated_rule(rule) }.compact
        temporary = Array(template["temporary_entries"] || template[:temporary_entries]).select { |entry| entry.is_a?(Hash) }
        return nil if rules.empty? && temporary.empty?
        template["pricing_rules"] = rules
        template.delete("modifiers")
        template["temporary_entries"] = temporary
        template["event_type"] = "automated"
        template["enabled"] = true
        template
      end

      def sanitize_automated_rule(value)
        return nil unless value.is_a?(Hash)
        rule = stringify_hash(deep_copy(value))
        operation = (rule["operation"] || rule["type"]).to_s
        return nil unless SUPPORTED_OPERATIONS.include?(operation)
        return nil if rule["value"].nil?
        amount = rule["value"].to_i
        case operation
        when "discount_percent", "markup_percent"
          amount = [[amount.abs, 0].max, MAX_AUTOMATED_PERCENT].min
        when "percent"
          amount = [[amount, -MAX_AUTOMATED_PERCENT].max, MAX_AUTOMATED_PERCENT].min
        when "flat"
          amount = amount
        when "set", "set_price", "min", "max"
          amount = [amount, 1].max
        else
          amount = amount.abs
        end
        rule["value"] = amount
        rule
      end

      def remove_editor_fields!(value)
        case value
        when Hash
          value.keys.each do |key|
            name = key.to_s
            if name == "internal_notes" || name.start_with?("__")
              value.delete(key)
            else
              remove_editor_fields!(value[key])
            end
          end
        when Array
          value.each { |child| remove_editor_fields!(child) }
        end
        value
      end

      def active_raw
        ReloadedMart::Source.active_raw || {}
      rescue
        {}
      end

      def online_available?
        ReloadedMart::Source.curated_available?
      rescue
        false
      end

      def normalize_event(event, index)
        return nil unless event.is_a?(Hash)
        value = stringify_hash(event)
        value["id"] = "economy_event_#{index + 1}" if value["id"].to_s.empty?
        value["event_type"] = event_type(value)
        value["enabled"] = true unless value.key?("enabled")
        value
      end

      def event_enabled?(event)
        return true unless event.key?("enabled") || event.key?(:enabled)
        truthy?(event["enabled"] || event[:enabled])
      rescue
        false
      end

      def scheduled_active?(event, context)
        return false unless event_enabled?(event)
        start_time = event_start_time(event)
        end_time = event_end_time(event)
        return false unless start_time && end_time && end_time > start_time
        now = trusted_time(context)
        now >= start_time && now < end_time
      rescue
        false
      end

      def winner_sort_key(event)
        [
          -(TYPE_PRIORITY[event_type(event)] || 0),
          -(event["priority"] || event[:priority] || 0).to_i,
          event_id(event)
        ]
      end

      def active_event_cache_key(context)
        now = trusted_time(context)
        raw = active_raw
        [
          now.to_i,
          online_available?,
          raw.object_id,
          automation_config.object_id
        ]
      rescue
        nil
      end

      def cycle_anchor(config)
        text = (config["cycle_anchor"] || DEFAULT_CYCLE_ANCHOR).to_s
        parse_cycle_date(text) || parse_cycle_date(DEFAULT_CYCLE_ANCHOR)
      end

      def current_eastern_date(context = {})
        time = eastern_wall_time(context)
        Time.utc(time.year, time.month, time.day)
      end

      def cycle_day_number(context, config)
        ((current_eastern_date(context) - cycle_anchor(config)) / 86_400).floor
      rescue
        0
      end

      def cycle_index(context, config)
        days = cycle_day_number(context, config)
        (days.to_f / CYCLE_DAYS).floor
      end

      def cycle_position(context, config)
        days = cycle_day_number(context, config)
        days % CYCLE_DAYS
      end

      def cycle_start_date(cycle, config)
        cycle_anchor(config) + (cycle.to_i * CYCLE_DAYS * 86_400)
      end

      def cycle_start_time(cycle, config)
        date = cycle_start_date(cycle, config)
        eastern_local_time(date.year, date.month, date.day, 0, 0, 0)
      end

      def cycle_end_time(cycle, config)
        date = cycle_start_date(cycle, config) + (EVENT_DAYS * 86_400)
        eastern_local_time(date.year, date.month, date.day, 0, 0, 0)
      end

      def template_for_cycle(templates, cycle, config)
        return templates.first if templates.length == 1
        index = template_index(templates, cycle, config)
        if cycle.to_i > 0
          previous = template_index(templates, cycle.to_i - 1, config)
          index = (index + 1) % templates.length if index == previous
        end
        templates[index]
      end

      def template_index(templates, cycle, config)
        seed = [
          config["automation_id"] || "economy",
          config["revision"] || 1,
          cycle.to_i
        ].join(":")
        deterministic_score(seed) % templates.length
      end

      def template_id(template)
        value = template["id"] || template[:id] || template["name"] || template[:name]
        value.to_s
      end

      def deterministic_score(text)
        text.to_s.bytes.inject(2_166_136_261) do |hash, byte|
          ((hash ^ byte) * 16_777_619) & 0xffffffff
        end
      end

      def selector_defined?(selector)
        keys = %w[
          entry_id entry_ids item items item_id item_ids kind kinds
          category categories category_id category_ids tag tags currency currencies
        ]
        keys.any? do |key|
          value = selector[key] || selector[key.to_sym]
          value.is_a?(Array) ? !value.empty? : !value.to_s.empty?
        end
      end

      def selector_matches?(selector, entry, context)
        normalized = stringify_hash(selector)
        return false unless ReloadedMart::Economy.modifier_applies?(normalized, entry, context)
        currencies = target_values(normalized, "currency", "currencies")
        return false if currencies.any? && !currencies.include?(entry.currency.to_s)
        kinds = target_values(normalized, "kind", "kinds")
        return false if kinds.any? && !kinds.include?(entry.kind.to_s)
        true
      rescue
        false
      end

      def target_values(hash, *keys)
        keys.flat_map do |key|
          value = hash[key] || hash[key.to_sym]
          value.is_a?(Array) ? value : [value]
        end.map { |value| value.to_s.strip }.reject(&:empty?).uniq
      rescue
        []
      end

      def validate_rule(event_id_value, rule, index, report)
        id = "#{event_id_value}:rule_#{index + 1}"
        unless rule.is_a?(Hash)
          report.error(id, "economy_rule_not_hash")
          return
        end
        normalized = stringify_hash(rule)
        operation = (normalized["operation"] || normalized["type"]).to_s
        report.error(id, "unknown_economy_rule_operation", :operation => operation) unless SUPPORTED_OPERATIONS.include?(operation)
        report.error(id, "missing_economy_rule_value") if normalized["value"].nil?
        mode = (normalized["mode"] || "buy").to_s
        report.error(id, "unknown_economy_rule_mode", :mode => mode) unless %w[buy sell both].include?(mode)
        value = normalized["value"].to_i
        if operation == "discount_percent" && (value < 0 || value > 100)
          report.error(id, "invalid_economy_discount_percent", :value => value)
        elsif value < 0
          report.error(id, "negative_economy_rule_value", :value => value)
        end
      end

      def validate_temporary_entries(event_id_value, entries, catalog_entry_ids, report)
        ids = {}
        Array(entries).each_with_index do |entry, index|
          row_id = "#{event_id_value}:temporary_#{index + 1}"
          unless entry.is_a?(Hash)
            report.error(row_id, "temporary_entry_not_hash")
            next
          end
          normalized = stringify_hash(entry)
          id = normalized["id"].to_s
          if id.empty?
            report.error(row_id, "missing_temporary_entry_id")
            next
          end
          report.error(id, "duplicate_temporary_entry_id") if ids[id]
          report.error(id, "temporary_entry_conflicts_with_catalog") if catalog_entry_ids.include?(id)
          ids[id] = true
          kind = (normalized["kind"] || normalized["type"] || "item").to_s.downcase
          unless ReloadedMart::ENTRY_KINDS.include?(kind.to_sym)
            report.error(id, "unknown_temporary_entry_kind", :kind => kind)
          end
          normalized_entry = ReloadedMart::Catalog.normalize_entry(entry, report, :economy_event)
          report.error(id, "invalid_temporary_entry") unless normalized_entry
        end
      end

      def validate_automation(value, report, catalog_entry_ids = [])
        return true if value.nil?
        unless value.is_a?(Hash)
          report.error("economy_event_automation", "automation_not_hash")
          return false
        end
        config = stringify_hash(value)
        return true unless truthy?(config["enabled"])
        report.error("economy_event_automation", "invalid_cycle_anchor") unless cycle_anchor_valid?(config["cycle_anchor"])
        templates = Array(config["templates"])
        report.error("economy_event_automation", "automation_has_no_templates") if templates.empty?
        ids = {}
        templates.each_with_index do |template, index|
          unless template.is_a?(Hash)
            report.error("economy_template_#{index + 1}", "template_not_hash")
            next
          end
          id = template_id(template)
          id = "economy_template_#{index + 1}" if id.empty?
          report.error(id, "duplicate_economy_template_id") if ids[id]
          ids[id] = true
          rules = pricing_rules(template)
          temporary = Array(template["temporary_entries"] || template[:temporary_entries])
          report.error(id, "template_has_no_effect") if rules.empty? && temporary.empty?
          rules.each_with_index { |rule, rule_index| validate_rule(id, rule, rule_index, report) }
          validate_temporary_entries(id, temporary, catalog_entry_ids, report)
        end
        true
      end

      def cycle_anchor_valid?(value)
        !parse_cycle_date((value || DEFAULT_CYCLE_ANCHOR).to_s).nil?
      end

      def parse_cycle_date(value)
        match = /\A(\d{4})-(\d{2})-(\d{2})\z/.match(value.to_s.strip)
        return nil unless match
        year = match[1].to_i
        month = match[2].to_i
        day = match[3].to_i
        date = Time.utc(year, month, day)
        return nil unless date.year == year && date.month == month && date.day == day
        date
      rescue
        nil
      end

      def temporary_cache_key(event, rows)
        [event_id(event), rows.hash, ReloadedMart::Source.active_report.catalog_version].join(":")
      rescue
        [event_id(event), rows.hash].join(":")
      end

      def rule_summary(rule)
        source = stringify_hash(rule)
        operation = (source["operation"] || source["type"]).to_s
        value = source["value"].to_i
        label = source["label"].to_s
        effect = case operation
                 when "discount_percent" then "#{value.abs}% off"
                 when "markup_percent" then "#{value.abs}% markup"
                 when "subtract_flat" then "#{value.abs} less"
                 when "add_flat" then "#{value.abs} more"
                 when "set", "set_price" then "Price set to #{value}"
                 when "min" then "Minimum price #{value}"
                 when "max" then "Maximum price #{value}"
                 when "percent" then value < 0 ? "#{value.abs}% off" : "#{value}% markup"
                 when "flat" then value < 0 ? "#{value.abs} less" : "#{value} more"
                 else ""
                 end
        return effect if label.empty?
        effect.empty? ? label : "#{label}: #{effect}"
      rescue
        ""
      end

      def humanize(value)
        value.to_s.split("_").map { |part| part.capitalize }.join(" ")
      end

      def format_time(value)
        value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
      rescue
        value.to_s
      end

      def eastern_local_time(year, month, day, hour, minute, second)
        local_wall_time = Time.utc(year, month, day, hour, minute, second)
        probe = local_wall_time + (5 * 60 * 60)
        daylight = if defined?(ReloadedMart::DailyFeatured) &&
                      ReloadedMart::DailyFeatured.respond_to?(:eastern_daylight_time?)
                     ReloadedMart::DailyFeatured.eastern_daylight_time?(probe)
                   else
                     false
                   end
        offset = daylight ? 4 : 5
        local_wall_time + (offset * 60 * 60)
      rescue
        nil
      end

      def truthy?(value)
        return value if value == true || value == false
        %w[1 true yes on enabled].include?(value.to_s.strip.downcase)
      end

      def stringify_hash(hash)
        return {} unless hash.is_a?(Hash)
        hash.each_with_object({}) { |(key, value), memo| memo[key.to_s] = value }
      end

      def deep_copy(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, child), memo| memo[key.to_s] = deep_copy(child) }
        when Array
          value.map { |child| deep_copy(child) }
        else
          value
        end
      end

      def log_exception(message, error)
        ReloadedMart.log_exception(message, error) if defined?(ReloadedMart)
      rescue
      end
    end
  end

  # Preserve the established Mart-facing Economy API while moving event
  # ownership into the dedicated automation module.
  module Economy
    class << self
      def events
        ReloadedMart::EconomyEvents.events
      end

      def event_active?(event, context = {})
        ReloadedMart::EconomyEvents.active?(event, context)
      end

      def matching_price_modifiers(entry, context = {})
        event_modifier = ReloadedMart::EconomyEvents.matching_modifier(entry, context)
        return [event_modifier] if event_modifier
        modifiers = []
        modifiers << daily_featured_modifier(entry, context) if daily_featured?(entry, context)
        modifiers.compact
      end

      def countdowns(context = {})
        ReloadedMart::EconomyEvents.countdowns(context)
      end

      def active_event(context = {})
        ReloadedMart::EconomyEvents.active_event(context)
      end

      def temporary_entries(context = {})
        ReloadedMart::EconomyEvents.temporary_entries(context)
      end
    end
  end
end
