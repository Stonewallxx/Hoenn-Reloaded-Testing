#======================================================
# Reloaded Patches
# Author: Stonewall
#======================================================
# Registry and conflict logger for Reloaded patch points.
#
# Responsibilities:
#   - Track systems that alter, wrap, replace, or bridge vanilla behavior.
#   - Detect likely conflicts when multiple patches target the same code/data.
#   - Write patch registrations and conflicts to the Reloaded log.
#   - Provide summaries for bug reports and future mod loader validation.
#
#======================================================

module Reloaded
  module Patches
    PATCH_TYPES = [
      :wrap,
      :replace,
      :append,
      :prepend,
      :alias,
      :event_bridge,
      :data_patch,
      :asset_override
    ].freeze

    HARD_CONFLICT_TYPES = [:replace, :asset_override].freeze
    ORDER_SENSITIVE_TYPES = [:wrap, :alias, :prepend, :append].freeze
    STACKABLE_TYPES = [:event_bridge].freeze
    CONFLICT_LEVELS = [:none, :notice, :warning, :critical].freeze

    @patches = []
    @conflicts = []
    @conflict_index = {}

    class << self
      def register(id, target:, type:, file: nil, owner: :reloaded, priority: 100, reason: nil, recommended_fix: nil, metadata: {}, conflict_group: nil, allow_multiple: false, severity: nil)
        patch = build_patch(
          id,
          target: target,
          type: type,
          file: file,
          owner: owner,
          priority: priority,
          reason: reason,
          recommended_fix: recommended_fix,
          metadata: metadata,
          conflict_group: conflict_group,
          allow_multiple: allow_multiple,
          severity: severity
        )
        existing_index = @patches.index { |entry| entry[:id] == patch[:id] && entry[:owner] == patch[:owner] }
        @patches[existing_index] = patch if existing_index
        @patches << patch unless existing_index
        log_registration(patch)
        detect_conflicts_for(patch)
        patch
      rescue Exception => e
        Reloaded::Log.exception("Patch registration failed", e, channel: :patches) if defined?(Reloaded::Log)
        nil
      end

      def registered(target = nil)
        return sorted_patches if target.nil?
        sorted_patches.select { |patch| patch[:target] == target.to_s }
      end

      def conflicts(target = nil)
        return sorted_conflicts if target.nil?
        @conflicts.select { |conflict| conflict[:target] == target.to_s }
      end

      def conflict?(target)
        !conflicts(target).empty?
      end

      def clear
        @patches.clear
        @conflicts.clear
        @conflict_index.clear
      end

      def summary
        {
          :patches => @patches.length,
          :conflicts => @conflicts.length,
          :critical_conflicts => @conflicts.count { |conflict| conflict[:level] == :critical },
          :warning_conflicts => @conflicts.count { |conflict| conflict[:level] == :warning },
          :targets => @patches.map { |patch| patch[:target] }.uniq.length
        }
      end

      def targets
        @patches.map { |patch| patch[:target] }.uniq.sort
      end

      def target_summary(target)
        entries = registered(target)
        conflicts_for_target = conflicts(target)
        {
          :target => target.to_s,
          :patches => entries.length,
          :owners => entries.map { |patch| patch[:owner] }.uniq,
          :conflicts => conflicts_for_target.length,
          :critical_conflicts => conflicts_for_target.count { |conflict| conflict[:level] == :critical },
          :warning_conflicts => conflicts_for_target.count { |conflict| conflict[:level] == :warning }
        }
      end

      def grouped_by_target
        result = {}
        sorted_patches.each do |patch|
          result[patch[:target]] ||= []
          result[patch[:target]] << patch
        end
        result
      end

      def write_summary
        data = summary
        Reloaded::Log.summary(
          :patches_registered => data[:patches],
          :patch_conflicts => data[:conflicts],
          :critical_patch_conflicts => data[:critical_conflicts],
          :warning_patch_conflicts => data[:warning_conflicts],
          :patch_targets => data[:targets]
        ) if defined?(Reloaded::Log)
        data
      end

      private

      def build_patch(id, target:, type:, file:, owner:, priority:, reason:, recommended_fix:, metadata:, conflict_group:, allow_multiple:, severity:)
        patch_type = normalize_type(type)
        patch_metadata = normalize_metadata(metadata)
        {
          :id => id.to_sym,
          :owner => owner.to_sym,
          :target => target.to_s,
          :type => patch_type,
          :file => file.to_s,
          :priority => priority.to_i,
          :reason => reason.to_s,
          :recommended_fix => recommended_fix.to_s,
          :metadata => patch_metadata,
          :conflict_group => normalize_optional(conflict_group || patch_metadata[:conflict_group]),
          :allow_multiple => truthy?(allow_multiple || patch_metadata[:allow_multiple]),
          :severity => normalize_conflict_level(severity || patch_metadata[:severity]),
          :registered_at => Time.now
        }
      end

      def normalize_type(type)
        patch_type = type.to_s.strip.downcase.to_sym
        return patch_type if PATCH_TYPES.include?(patch_type)
        :wrap
      end

      def normalize_metadata(metadata)
        result = {}
        (metadata || {}).each do |key, value|
          result[key.to_sym] = value
        end
        result
      rescue
        {}
      end

      def normalize_optional(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def truthy?(value)
        case value
        when true then true
        when false, nil then false
        else
          ["1", "true", "yes", "on"].include?(value.to_s.strip.downcase)
        end
      end

      def normalize_conflict_level(value)
        key = value.to_s.strip.downcase.to_sym
        CONFLICT_LEVELS.include?(key) ? key : nil
      end

      def sorted_patches
        @patches.sort_by { |patch| [patch[:target], patch[:priority], patch[:owner].to_s, patch[:id].to_s] }
      end

      def sorted_conflicts
        @conflicts.sort_by { |conflict| [conflict[:target], conflict_rank(conflict[:level]), conflict[:key]] }
      end

      def conflict_rank(level)
        { :critical => 0, :warning => 1, :notice => 2, :none => 3 }[level] || 9
      end

      def log_registration(patch)
        return unless defined?(Reloaded::Log)
        message = "Registered #{patch[:owner]}/#{patch[:id]} target=#{patch[:target]} type=#{patch[:type]} priority=#{patch[:priority]} file=#{patch[:file]}"
        if Reloaded::Log.respond_to?(:debug_once)
          Reloaded::Log.debug_once(message, :patches, key: "patch_registered:#{patch_identity(patch)}")
        else
          Reloaded::Log.debug(message, :patches)
        end
      end

      def detect_conflicts_for(patch)
        matches = @patches.select do |entry|
          next false if entry[:id] == patch[:id] && entry[:owner] == patch[:owner]
          entry[:target] == patch[:target] || shared_conflict_group?(entry, patch)
        end
        matches.each do |other|
          rule = conflict_between(patch, other)
          record_conflict(patch, other, rule) if rule
        end
      end

      def shared_conflict_group?(patch, other)
        return false if patch[:conflict_group].nil? || other[:conflict_group].nil?
        patch[:conflict_group] == other[:conflict_group]
      end

      def conflict_between(patch, other)
        return nil if explicitly_compatible?(patch, other)
        explicit = explicit_conflict(patch, other)
        return explicit if explicit
        hard = hard_conflict(patch, other)
        return hard if hard
        grouped = grouped_conflict(patch, other)
        return grouped if grouped
        ordered = order_conflict(patch, other)
        return ordered if ordered
        nil
      end

      def explicitly_compatible?(patch, other)
        return true if patch[:allow_multiple] || other[:allow_multiple]
        compatible_list(patch).include?(patch_identity(other)) || compatible_list(other).include?(patch_identity(patch))
      end

      def compatible_list(patch)
        Array(patch[:metadata][:compatible_with]).map { |value| value.to_s.strip }.reject(&:empty?)
      rescue
        []
      end

      def explicit_conflict(patch, other)
        return conflict_rule(:critical, "Explicit conflict metadata") if conflict_list(patch).include?(patch_identity(other))
        return conflict_rule(:critical, "Explicit conflict metadata") if conflict_list(other).include?(patch_identity(patch))
        nil
      end

      def conflict_list(patch)
        Array(patch[:metadata][:conflicts_with]).map { |value| value.to_s.strip }.reject(&:empty?)
      rescue
        []
      end

      def hard_conflict(patch, other)
        return conflict_rule(:critical, "Replacement patch shares a target") if patch[:type] == :replace || other[:type] == :replace
        return conflict_rule(:critical, "Asset override shares a target") if patch[:type] == :asset_override || other[:type] == :asset_override
        nil
      end

      def grouped_conflict(patch, other)
        group = patch[:conflict_group]
        return nil if group.nil? || other[:conflict_group].nil?
        return nil unless group == other[:conflict_group]
        level = strongest_level(patch, other, :critical)
        conflict_rule(level, "Exclusive conflict group: #{group}")
      end

      def order_conflict(patch, other)
        return nil if STACKABLE_TYPES.include?(patch[:type]) && STACKABLE_TYPES.include?(other[:type])
        return nil unless patch[:priority] == other[:priority]
        return conflict_rule(:warning, "Same patch type and priority") if patch[:type] == other[:type]
        if ORDER_SENSITIVE_TYPES.include?(patch[:type]) && ORDER_SENSITIVE_TYPES.include?(other[:type])
          return conflict_rule(:warning, "Order-sensitive patches share priority")
        end
        if patch[:type] == :data_patch || other[:type] == :data_patch
          return conflict_rule(:warning, "Data patch shares priority with another patch")
        end
        nil
      end

      def conflict_rule(level, reason)
        {
          :level => normalize_conflict_level(level) || :warning,
          :reason => reason.to_s
        }
      end

      def strongest_level(patch, other, default)
        levels = [patch[:severity], other[:severity], default].compact
        levels.min_by { |level| conflict_rank(level) } || default
      end

      def record_conflict(patch, other, rule)
        key = conflict_key(patch, other)
        return if @conflict_index[key]
        conflict = {
          :key => key,
          :target => patch[:target],
          :patches => [compact_patch(other), compact_patch(patch)],
          :level => strongest_level(patch, other, rule[:level]),
          :reason => rule[:reason],
          :recommended_fix => recommended_fix(patch, other)
        }
        @conflicts << conflict
        @conflict_index[key] = true
        log_conflict(conflict)
      end

      def conflict_key(patch, other)
        ids = [patch, other].map { |entry| patch_identity(entry) }.sort
        "#{patch[:target]}|#{ids.join('|')}"
      end

      def patch_identity(patch)
        "#{patch[:owner]}/#{patch[:id]}"
      end

      def recommended_fix(patch, other)
        explicit = [patch[:recommended_fix], other[:recommended_fix]].find { |value| value && !value.empty? }
        return explicit if explicit
        "Review patch order or move one change to an event hook for #{patch[:target]}."
      end

      def compact_patch(patch)
        {
          :id => patch[:id],
          :owner => patch[:owner],
          :type => patch[:type],
          :priority => patch[:priority],
          :conflict_group => patch[:conflict_group],
          :file => patch[:file],
          :reason => patch[:reason]
        }
      end

      def log_conflict(conflict)
        return unless defined?(Reloaded::Log)
        level = conflict[:level]
        message = "Patch conflict target=#{conflict[:target]} patches=#{conflict[:patches].map { |patch| "#{patch[:owner]}/#{patch[:id]}" }.join(', ')}"
        if Reloaded::Log.respond_to?(:write_once)
          Reloaded::Log.write_once(:patches, "#{message} reason=#{conflict[:reason]}", level: level, key: "patch_conflict:#{conflict[:key]}")
        else
          Reloaded::Log.write(:patches, "#{message} reason=#{conflict[:reason]}", level: level)
        end
        Reloaded::Log.report(
          :type => "Patch Conflict",
          :level => level,
          :file_path => conflict[:patches].map { |patch| patch[:file] }.reject { |file| file.empty? }.join(", "),
          :dependency_status => "Patch target already has another registered change.",
          :recommended_fix => conflict[:recommended_fix],
          :stack_trace => conflict_details(conflict)
        )
      end

      def conflict_details(conflict)
        lines = ["Reason: #{conflict[:reason]}"]
        conflict[:patches].each do |patch|
          details = "#{patch[:owner]}/#{patch[:id]} #{patch[:type]} priority=#{patch[:priority]}"
          details += " group=#{patch[:conflict_group]}" if patch[:conflict_group]
          details += " reason=#{patch[:reason]}" unless patch[:reason].to_s.empty?
          lines << details
        end
        lines
      end
    end
  end
end
