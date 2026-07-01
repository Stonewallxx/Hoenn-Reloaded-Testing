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

    @patches = []
    @conflicts = []

    class << self
      def register(id, target:, type:, file: nil, owner: :reloaded, priority: 100, reason: nil, recommended_fix: nil, metadata: {})
        patch = build_patch(
          id,
          target: target,
          type: type,
          file: file,
          owner: owner,
          priority: priority,
          reason: reason,
          recommended_fix: recommended_fix,
          metadata: metadata
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
        return @conflicts.dup if target.nil?
        @conflicts.select { |conflict| conflict[:target] == target.to_s }
      end

      def conflict?(target)
        !conflicts(target).empty?
      end

      def clear
        @patches.clear
        @conflicts.clear
      end

      def summary
        {
          :patches => @patches.length,
          :conflicts => @conflicts.length,
          :targets => @patches.map { |patch| patch[:target] }.uniq.length
        }
      end

      def write_summary
        data = summary
        Reloaded::Log.summary(
          :patches_registered => data[:patches],
          :patch_conflicts => data[:conflicts],
          :patch_targets => data[:targets]
        ) if defined?(Reloaded::Log)
        data
      end

      private

      def build_patch(id, target:, type:, file:, owner:, priority:, reason:, recommended_fix:, metadata:)
        patch_type = normalize_type(type)
        {
          :id => id.to_sym,
          :owner => owner.to_sym,
          :target => target.to_s,
          :type => patch_type,
          :file => file.to_s,
          :priority => priority.to_i,
          :reason => reason.to_s,
          :recommended_fix => recommended_fix.to_s,
          :metadata => metadata || {},
          :registered_at => Time.now
        }
      end

      def normalize_type(type)
        patch_type = type.to_s.strip.downcase.to_sym
        return patch_type if PATCH_TYPES.include?(patch_type)
        :wrap
      end

      def sorted_patches
        @patches.sort_by { |patch| [patch[:target], patch[:priority], patch[:owner].to_s, patch[:id].to_s] }
      end

      def log_registration(patch)
        return unless defined?(Reloaded::Log)
        Reloaded::Log.debug(
          "Registered #{patch[:owner]}/#{patch[:id]} target=#{patch[:target]} type=#{patch[:type]} priority=#{patch[:priority]} file=#{patch[:file]}",
          :patches
        )
      end

      def detect_conflicts_for(patch)
        matches = @patches.select do |entry|
          entry[:target] == patch[:target] && !(entry[:id] == patch[:id] && entry[:owner] == patch[:owner])
        end
        matches.each do |other|
          record_conflict(patch, other) if conflict_between?(patch, other)
        end
      end

      def conflict_between?(patch, other)
        return true if HARD_CONFLICT_TYPES.include?(patch[:type])
        return true if HARD_CONFLICT_TYPES.include?(other[:type])
        patch[:type] == other[:type] && patch[:priority] == other[:priority]
      end

      def record_conflict(patch, other)
        key = conflict_key(patch, other)
        return if @conflicts.any? { |conflict| conflict[:key] == key }
        conflict = {
          :key => key,
          :target => patch[:target],
          :patches => [compact_patch(other), compact_patch(patch)],
          :level => conflict_level(patch, other),
          :recommended_fix => recommended_fix(patch, other)
        }
        @conflicts << conflict
        log_conflict(conflict)
      end

      def conflict_key(patch, other)
        ids = [patch, other].map { |entry| "#{entry[:owner]}/#{entry[:id]}" }.sort
        "#{patch[:target]}|#{ids.join('|')}"
      end

      def conflict_level(patch, other)
        return :critical if HARD_CONFLICT_TYPES.include?(patch[:type])
        return :critical if HARD_CONFLICT_TYPES.include?(other[:type])
        :warning
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
          :file => patch[:file],
          :reason => patch[:reason]
        }
      end

      def log_conflict(conflict)
        return unless defined?(Reloaded::Log)
        level = conflict[:level]
        message = "Patch conflict target=#{conflict[:target]} patches=#{conflict[:patches].map { |patch| "#{patch[:owner]}/#{patch[:id]}" }.join(', ')}"
        Reloaded::Log.write(:patches, message, level: level)
        Reloaded::Log.report(
          :type => "Patch Conflict",
          :level => level,
          :file_path => conflict[:patches].map { |patch| patch[:file] }.reject { |file| file.empty? }.join(", "),
          :dependency_status => "Patch target already has another registered change.",
          :recommended_fix => conflict[:recommended_fix],
          :stack_trace => conflict[:patches].map { |patch| "#{patch[:owner]}/#{patch[:id]} #{patch[:type]} priority=#{patch[:priority]} reason=#{patch[:reason]}" }
        )
      end
    end
  end
end
