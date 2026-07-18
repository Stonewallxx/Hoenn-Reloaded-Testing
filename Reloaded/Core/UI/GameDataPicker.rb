#======================================================
# Reloaded Game Data Picker
#======================================================
# Searchable, canonical-ID selectors built on Reloaded::ListPicker.
#======================================================

module Reloaded
  module API
    module GameDataPicker
      REGISTRIES = {
        :item => "Item",
        :species => "Species",
        :move => "Move",
        :ability => "Ability",
        :type => "Type",
        :trainer_class => "TrainerType"
      }.freeze

      ALIASES = {
        :items => :item,
        :pokemon => :species,
        :pokemons => :species,
        :moves => :move,
        :abilities => :ability,
        :types => :type,
        :map => :map,
        :maps => :map,
        :trainer_type => :trainer_class,
        :trainer_types => :trainer_class,
        :trainer_classes => :trainer_class
      }.freeze

      TITLES = {
        :item => "Select an Item",
        :species => "Select a Pokemon",
        :move => "Select a Move",
        :ability => "Select an Ability",
        :type => "Select a Type",
        :map => "Select a Map",
        :trainer_class => "Select a Trainer Class"
      }.freeze

      KIND_LABELS = {
        :item => "item",
        :species => "Pokemon",
        :move => "move",
        :ability => "ability",
        :type => "type",
        :map => "map",
        :trainer_class => "trainer class"
      }.freeze

      PLACEHOLDER_IDS = [:NONE, :UNKNOWN].freeze

      class << self
        def pick(kind, title = nil, options = {})
          title, options = normalize_title_options(title, options)
          key = normalize_kind(kind)
          return unavailable(kind) unless supported?(key)
          rows = rows_for(key, options)
          picker_options = list_picker_options(key, options)
          result = if picker_options[:layout] == :popup
                     Reloaded::ListPicker.popup(title || TITLES[key], rows, picker_options)
                   else
                     Reloaded::ListPicker.fullscreen(title || TITLES[key], rows, picker_options)
                   end
          return result unless options[:return] == :data
          return Array(result).map { |id| record(key, id) }.compact if result.is_a?(Array)
          result.nil? ? nil : record(key, result)
        rescue Exception => e
          log_exception("GameDataPicker #{kind} failed", e)
          warning(_INTL("That game data list could not be opened."))
          nil
        end

        def item(title = nil, options = {});          pick(:item, title, options); end
        def species(title = nil, options = {});       pick(:species, title, options); end
        def pokemon(title = nil, options = {});       pick(:species, title, options); end
        def move(title = nil, options = {});          pick(:move, title, options); end
        def ability(title = nil, options = {});       pick(:ability, title, options); end
        def type(title = nil, options = {});          pick(:type, title, options); end
        def map(title = nil, options = {});           pick(:map, title, options); end
        def trainer_class(title = nil, options = {}); pick(:trainer_class, title, options); end
        def trainer_type(title = nil, options = {});  pick(:trainer_class, title, options); end

        def supported?(kind)
          key = normalize_kind(kind)
          return !!defined?(pbLoadMapInfos) if key == :map
          return false unless defined?(GameData)
          name = REGISTRIES[key]
          name && GameData.const_defined?(name)
        rescue
          false
        end

        def kinds
          (REGISTRIES.keys + [:map]).select { |kind| supported?(kind) }
        end

        def rows_for(kind, options = {})
          key = normalize_kind(kind)
          records = key == :map ? map_records : registry_records(key)
          rows = []
          records.each do |data|
            id = record_id(key, data)
            next if id.nil?
            callback_data = key == :map && data.is_a?(Array) ? data[1] : data
            next if placeholder?(id, options)
            next unless included?(id, options)
            next unless passes_filter?(callback_data, id, options)
            name = display_name(key, data)
            label = option_value(options[:label], callback_data, id)
            label = default_label(name, id) if label.nil? || label.to_s.empty?
            detail = option_value(options[:detail], callback_data, id)
            detail = record_detail(key, data, id) if detail.nil?
            disabled = !!option_value(options[:disabled], callback_data, id)
            reason = option_value(options[:disabled_reason], callback_data, id).to_s
            rows << {
              :label => label.to_s,
              :value => id,
              :status => record_status(key, data),
              :detail => detail.to_s,
              :disabled => disabled,
              :disabled_reason => reason,
              :search_text => [name, id, record_number(data), detail].compact.join(" ")
            }
          end
          sort_rows(rows, options[:sort])
        rescue Exception => e
          log_exception("GameDataPicker #{kind} rows failed", e)
          []
        end

        def record(kind, id)
          key = normalize_kind(kind)
          if key == :map
            infos = pbLoadMapInfos
            return infos[id.to_i] if infos
            return nil
          end
          klass = registry_class(key)
          klass && klass.respond_to?(:try_get) ? klass.try_get(id) : nil
        rescue
          nil
        end

        private

        def normalize_title_options(title, options)
          if title.is_a?(Hash)
            [nil, title]
          else
            [title, options || {}]
          end
        end

        def normalize_kind(kind)
          key = kind.to_s.downcase.gsub(/\s+/, "_").to_sym
          ALIASES[key] || key
        rescue
          kind
        end

        def registry_class(kind)
          return nil unless defined?(GameData)
          name = REGISTRIES[kind]
          name && GameData.const_defined?(name) ? GameData.const_get(name) : nil
        rescue
          nil
        end

        def registry_records(kind)
          klass = registry_class(kind)
          return [] unless klass && klass.respond_to?(:each)
          values = []
          klass.each { |data| values << data if data }
          values
        end

        def map_records
          infos = pbLoadMapInfos
          return [] unless infos.respond_to?(:keys)
          infos.keys.sort.map { |id| [id.to_i, infos[id]] }.select { |pair| pair[1] }
        rescue
          []
        end

        def record_id(kind, data)
          return data[0].to_i if kind == :map && data.is_a?(Array)
          data.respond_to?(:id) ? data.id : nil
        end

        def record_number(data)
          return data[0].to_i if data.is_a?(Array)
          data.respond_to?(:id_number) ? data.id_number : nil
        rescue
          nil
        end

        def display_name(kind, data)
          source = kind == :map && data.is_a?(Array) ? data[1] : data
          value = source.name if source && source.respond_to?(:name)
          value = source.real_name if (value.nil? || value.to_s.empty?) && source && source.respond_to?(:real_name)
          value = record_id(kind, data) if value.nil? || value.to_s.empty?
          value.to_s
        rescue
          record_id(kind, data).to_s
        end

        def default_label(name, id)
          "#{name}  [#{id}]"
        end

        def record_status(kind, data)
          number = record_number(data)
          return "Map #{number}" if kind == :map
          number.nil? || number.to_i < 0 ? "" : "##{number}"
        rescue
          ""
        end

        def record_detail(kind, data, id)
          source = kind == :map && data.is_a?(Array) ? data[1] : data
          case kind
          when :item
            description = safe_attribute(source, :description)
            parts = ["ID: #{id}", "Pocket: #{safe_attribute(source, :pocket)}", "Price: $#{safe_attribute(source, :price)}"]
            append_description(parts, description)
          when :species
            types = [safe_attribute(source, :type1), safe_attribute(source, :type2)].compact.uniq.map { |type_id| type_name(type_id) }
            entry = safe_attribute(source, :pokedex_entry)
            entry = safe_attribute(source, :real_pokedex_entry) if entry.nil? || entry.to_s.empty?
            parts = ["ID: #{id}", "Types: #{types.join(" / ")}"]
            append_description(parts, entry)
          when :move
            category = move_category(source)
            parts = [
              "ID: #{id}",
              "Type: #{type_name(safe_attribute(source, :type))}",
              "#{category} | Power: #{safe_attribute(source, :base_damage)} | Accuracy: #{safe_attribute(source, :accuracy)} | PP: #{safe_attribute(source, :total_pp)}"
            ]
            append_description(parts, safe_attribute(source, :description))
          when :ability
            append_description(["ID: #{id}"], safe_attribute(source, :description))
          when :type
            pseudo = safe_attribute(source, :pseudo_type)
            "ID: #{id}#{pseudo ? " | Pseudo Type" : ""}"
          when :trainer_class
            gender = { 0 => "Male", 1 => "Female", 2 => "Mixed" }[safe_attribute(source, :gender).to_i] || "Unknown"
            "ID: #{id} | Gender: #{gender} | Base Money: #{safe_attribute(source, :base_money)} | Skill: #{safe_attribute(source, :skill_level)}"
          when :map
            "Map ID: #{id} | #{display_name(kind, data)}"
          else
            "ID: #{id}"
          end
        rescue
          "ID: #{id}"
        end

        def append_description(parts, description)
          text = description.to_s.strip
          parts << text unless text.empty?
          parts.reject { |part| part.to_s.empty? }.join("\n")
        end

        def safe_attribute(data, name)
          data && data.respond_to?(name) ? data.send(name) : nil
        rescue
          nil
        end

        def type_name(id)
          return "?" if id.nil?
          data = GameData::Type.try_get(id) rescue nil
          data && data.respond_to?(:name) ? data.name.to_s : id.to_s
        rescue
          id.to_s
        end

        def move_category(data)
          return "Physical" if data.respond_to?(:physical?) && data.physical?
          return "Special" if data.respond_to?(:special?) && data.special?
          "Status"
        rescue
          "Move"
        end

        def placeholder?(id, options)
          return false if options[:include_placeholders]
          PLACEHOLDER_IDS.include?(id.to_s.upcase.to_sym)
        rescue
          false
        end

        def included?(id, options)
          include_ids = Array(options[:include]).compact
          exclude_ids = Array(options[:exclude]).compact
          return false if !include_ids.empty? && !id_match?(include_ids, id)
          !id_match?(exclude_ids, id)
        end

        def id_match?(values, id)
          values.any? { |value| value == id || value.to_s.casecmp(id.to_s) == 0 }
        rescue
          false
        end

        def passes_filter?(data, id, options)
          filter = options[:filter]
          return true unless filter.respond_to?(:call)
          !!call_option(filter, data, id)
        end

        def option_value(value, data, id)
          value.respond_to?(:call) ? call_option(value, data, id) : value
        end

        def call_option(callable, data, id)
          arity = callable.arity rescue 0
          return callable.call if arity == 0
          return callable.call(data) if arity == 1
          callable.call(data, id)
        end

        def sort_rows(rows, mode)
          key = (mode || :name).to_sym rescue :name
          case key
          when :id
            rows.sort_by { |row| row[:value].to_s.downcase }
          when :number
            rows.sort_by { |row| row[:status].to_s.gsub(/\D/, "").to_i }
          when :registry, :default
            rows
          else
            rows.sort_by { |row| [row[:label].to_s.downcase, row[:value].to_s.downcase] }
          end
        end

        def list_picker_options(kind, options)
          result = {}
          (options || {}).each { |key, value| result[key] = value }
          result[:layout] = (result[:layout] || :fullscreen).to_sym rescue :fullscreen
          result[:search] = true unless result.key?(:search)
          result[:details] = true unless result.key?(:details)
          result[:add_back] = true unless result.key?(:add_back)
          result[:multi_select] = !!(result[:multi_select] || result[:multiple])
          result[:memory_key] ||= [:game_data_picker, kind]
          result[:empty_text] ||= _INTL("No matching game data was found.")
          result
        end

        def unavailable(kind)
          key = normalize_kind(kind)
          warning(_INTL("No {1} data is available.", KIND_LABELS[key] || kind.to_s))
          nil
        end

        def warning(text)
          if Reloaded.respond_to?(:toast_warning)
            Reloaded.toast_warning(text.to_s)
          elsif Reloaded.respond_to?(:message)
            Reloaded.message(text.to_s, :theme => :warning)
          end
        rescue
        end

        def log_exception(message, error)
          if defined?(Reloaded::Log)
            Reloaded::Log.error("#{message}: #{error.class}: #{error}", :api)
            Reloaded::Log.debug(Array(error.backtrace).first(6).join("\n"), :api) rescue nil
          end
        rescue
        end
      end
    end
  end

  GameDataPicker = API::GameDataPicker unless const_defined?(:GameDataPicker, false)

  class << self
    def pick_game_data(kind, title = nil, options = {})
      GameDataPicker.pick(kind, title, options)
    end
  end
end
