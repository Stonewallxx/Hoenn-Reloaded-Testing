#======================================================
# Reloaded Data Patch Moves
# Author: Stonewall
#======================================================
# Direct runtime data patch target for base-game move data.
#
# Responsibilities:
#   - Register the move data patch target.
#   - Apply patched move entries to GameData::Move::DATA.
#   - Refresh the move target after GameData.load_all refreshes base data.
#   - Restore Reloaded-managed move entries before each rebuild.
#   - Provide safe text fallbacks for modded move names and descriptions.
#   - Register the move data patch bridge with Reloaded::Patches.
#
#======================================================

module Reloaded
  module DataPatchMoves
    TARGET = "moves".freeze

    MOVE_FIELDS = [
      "id",
      "id_number",
      "name",
      "function_code",
      "base_damage",
      "type",
      "category",
      "accuracy",
      "total_pp",
      "effect_chance",
      "target",
      "priority",
      "flags",
      "description"
    ].freeze

    CATEGORY_VALUES = {
      "physical" => 0,
      "special" => 1,
      "status" => 2
    }.freeze

    @base_entries = {}
    @managed_symbols = []
    @managed_numbers = []

    class << self
      def install
        install_text_fallbacks
        register_target
        register_events
        register_patch_point
        Reloaded::Log.info("Installed Reloaded move data patch bridge", :mods) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Move data patch bridge install failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def register_target
        return unless defined?(Reloaded::DataPatches)
        refresh_base_entries
        Reloaded::DataPatches.register_target(
          TARGET,
          @base_entries,
          owner: :reloaded,
          description: "Runtime move data patch target."
        )
      end

      def apply_all
        return false unless defined?(GameData::Move)
        restore_managed_entries
        touched_ids = patched_move_ids
        applied = 0
        touched_ids.each do |id|
          raw_data = Reloaded::DataPatches.entry(TARGET, id)
          applied += 1 if apply_entry(id, raw_data)
        end
        log_applied(applied) if applied > 0
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to apply move data patches", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      private

      def refresh_base_entries
        @base_entries = {}
        return unless defined?(GameData::Move)
        GameData::Move::DATA.each do |key, move|
          next if key.is_a?(Integer)
          next unless move.is_a?(GameData::Move)
          @base_entries[key.to_s] = move_to_hash(move)
        end
        @base_entries
      end

      def move_to_hash(move)
        {
          "id" => move.id.to_s,
          "id_number" => move.id_number,
          "name" => move.real_name,
          "function_code" => move.function_code,
          "base_damage" => move.base_damage,
          "type" => move.type ? move.type.to_s : nil,
          "category" => move.category,
          "accuracy" => move.accuracy,
          "total_pp" => move.total_pp,
          "effect_chance" => move.effect_chance,
          "target" => move.target ? move.target.to_s : nil,
          "priority" => move.priority,
          "flags" => move.flags,
          "description" => move.real_description
        }
      end

      def restore_managed_entries
        return unless defined?(GameData::Move)
        Array(@managed_numbers).each { |key| GameData::Move::DATA.delete(key) }
        Array(@managed_symbols).each do |key|
          if @base_entries.key?(key.to_s)
            restore_base_entry(key.to_s)
          else
            GameData::Move::DATA.delete(key)
          end
        end
        @managed_symbols = []
        @managed_numbers = []
      end

      def restore_base_entry(id)
        data = normalize_data(id, @base_entries[id])
        move = GameData::Move.new(data)
        GameData::Move::DATA[data[:id]] = move
        GameData::Move::DATA[data[:id_number]] = move
      end

      def apply_entry(id, raw_data)
        data = normalize_data(id, raw_data)
        id_symbol = data[:id]
        id_number = data[:id_number]
        existing_number_owner = GameData::Move::DATA[id_number]
        if existing_number_owner && existing_number_owner.id != id_symbol && !managed_number?(id_number)
          log_error("Move patch #{id_symbol} cannot use id_number #{id_number}; it already belongs to #{existing_number_owner.id}.")
          return false
        end

        move = GameData::Move.new(data)
        move.instance_variable_set(:@reloaded_data_patch, true)
        GameData::Move::DATA[id_symbol] = move
        GameData::Move::DATA[id_number] = move
        @managed_symbols << id_symbol unless @managed_symbols.include?(id_symbol)
        @managed_numbers << id_number unless @managed_numbers.include?(id_number)
        true
      rescue Exception => e
        Reloaded::Log.exception("Failed to apply move patch #{id}", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def normalize_data(id, raw_data)
        raw = stringify_keys(raw_data.is_a?(Hash) ? raw_data : {})
        base = base_entry(id)
        data = {}
        MOVE_FIELDS.each { |field| data[field] = raw.key?(field) ? raw[field] : base[field] }
        data["id"] = id if blank?(data["id"])
        data["id_number"] = next_id_number if blank?(data["id_number"])
        data["name"] = data["id"].to_s if blank?(data["name"])
        data["function_code"] = "000" if blank?(data["function_code"])
        data["base_damage"] = 0 if blank?(data["base_damage"])
        data["type"] = "NORMAL" if blank?(data["type"])
        data["category"] = data["base_damage"].to_i == 0 ? 2 : 0 if blank?(data["category"])
        data["accuracy"] = 100 if blank?(data["accuracy"])
        data["total_pp"] = 5 if blank?(data["total_pp"])
        data["effect_chance"] = 0 if blank?(data["effect_chance"])
        data["target"] = "NearOther" if blank?(data["target"])
        data["priority"] = 0 if blank?(data["priority"])
        data["flags"] = "" if data["flags"].nil?
        data["description"] = "???" if blank?(data["description"])

        {
          :id => normalize_symbol(data["id"]),
          :id_number => data["id_number"].to_i,
          :name => data["name"].to_s,
          :function_code => normalize_function_code(data["function_code"]),
          :base_damage => data["base_damage"].to_i,
          :type => normalize_symbol(data["type"]),
          :category => normalize_category(data["category"]),
          :accuracy => data["accuracy"].to_i,
          :total_pp => data["total_pp"].to_i,
          :effect_chance => data["effect_chance"].to_i,
          :target => resolve_data_id("GameData::Target", data["target"], :NearOther),
          :priority => data["priority"].to_i,
          :flags => data["flags"].to_s,
          :description => data["description"].to_s
        }
      end

      def base_entry(id)
        key = normalize_symbol(id).to_s
        @base_entries[key] || {}
      end

      def next_id_number
        keys = []
        GameData::Move::DATA.each_key { |key| keys << key if key.is_a?(Integer) }
        value = keys.empty? ? 1 : keys.max + 1
        value += 1 while GameData::Move::DATA.key?(value)
        value
      end

      def patched_move_ids
        return [] unless defined?(Reloaded::DataPatches)
        Reloaded::DataPatches.applied(TARGET).map { |patch| patch[:id] }.uniq
      rescue
        []
      end

      def managed_number?(key)
        @managed_numbers.include?(key)
      end

      def normalize_symbol(value)
        value.to_s.strip.upcase.gsub(/[^A-Z0-9_]+/, "_").to_sym
      end

      def normalize_function_code(value)
        value.to_s.strip.upcase
      end

      def normalize_category(value)
        return value.to_i if value.to_s =~ /\A-?\d+\z/
        CATEGORY_VALUES[value.to_s.strip.downcase] || 0
      end

      def stringify_keys(hash)
        result = {}
        hash.each { |key, value| result[key.to_s] = value }
        result
      rescue
        {}
      end

      def resolve_data_id(class_name, value, default = nil)
        return default if blank?(value)
        klass = resolve_class(class_name)
        exact = value.is_a?(Symbol) ? value : value.to_s.to_sym
        return exact if klass && klass.const_defined?(:DATA) && klass::DATA.key?(exact)
        normalized_value = normalize_lookup_key(value)
        if klass && klass.const_defined?(:DATA)
          klass::DATA.keys.each do |key|
            next if key.is_a?(Integer)
            return key if normalize_lookup_key(key) == normalized_value
          end
        end
        normalize_symbol(value)
      rescue
        blank?(value) ? default : normalize_symbol(value)
      end

      def resolve_class(class_name)
        class_name.to_s.split("::").inject(Object) do |scope, name|
          return nil unless scope.const_defined?(name)
          scope.const_get(name)
        end
      rescue
        nil
      end

      def normalize_lookup_key(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "")
      end

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def log_applied(count)
        message = "Applied #{count} move data patch entr#{count == 1 ? 'y' : 'ies'}"
        if defined?(Reloaded::Log)
          if Reloaded::Log.respond_to?(:info_once)
            Reloaded::Log.info_once(message, :mods, key: "move_data_patch_applied:#{count}")
          else
            Reloaded::Log.info(message, :mods)
          end
        end
      end

      def log_error(message)
        if defined?(Reloaded::Log)
          if Reloaded::Log.respond_to?(:error_once)
            Reloaded::Log.error_once(message, :mods, key: "move_data_patch_error:#{message}")
          else
            Reloaded::Log.error(message, :mods)
          end
        end
      end

      def register_events
        return unless defined?(Reloaded::Events)
        Reloaded::Events.on(:game_data_loaded, :move_data_patch_target_refresh, priority: 50) do |_context|
          Reloaded::DataPatchMoves.register_target if defined?(Reloaded::DataPatchMoves)
        end
        Reloaded::Events.on(:data_patches_loaded, :move_data_patch_bridge, priority: 100) do |_context|
          Reloaded::DataPatchMoves.apply_all if defined?(Reloaded::DataPatchMoves)
        end
      end

      def install_text_fallbacks
        return unless defined?(GameData::Move)
        return if GameData::Move.method_defined?(:reloaded_data_patch_move_name)

        GameData::Move.class_eval do
          alias_method :reloaded_data_patch_move_name, :name
          alias_method :reloaded_data_patch_move_description, :description

          def reloaded_data_patch_move?
            !!@reloaded_data_patch
          end

          def name
            return @real_name if reloaded_data_patch_move?
            reloaded_data_patch_move_name
          end

          def description
            return @real_description if reloaded_data_patch_move?
            reloaded_data_patch_move_description
          end
        end
      end

      def register_patch_point
        return unless defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          :move_data_patch_bridge,
          :target => "GameData::Move::DATA",
          :type => :runtime_data_bridge,
          :file => __FILE__,
          :owner => :reloaded,
          :priority => 100,
          :reason => "Applies Reloaded move data patches after enabled mods are scanned.",
          :recommended_fix => "Review Reloaded::DataPatchMoves if patched moves fail to appear.",
          :conflict_group => "game_data_moves"
        )
      end
    end
  end
end

Reloaded::DataPatchMoves.install if defined?(Reloaded::DataPatchMoves)
