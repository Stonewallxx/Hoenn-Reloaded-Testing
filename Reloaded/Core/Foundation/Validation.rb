#======================================================
# Reloaded Validation
# Author: Stonewall
#======================================================
# Shared lightweight and developer/release validation registry.
#======================================================

module Reloaded
  module Validation
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    REPORT_PATH = File.join(ROOT, "Logging", "ValidationReport.txt")
    MAX_REPORT_FINDINGS = 250
    SEVERITIES = [:info, :warning, :error, :critical].freeze
    PHASES = [:boot, :modules_loaded, :game_data_loaded, :save_loaded, :developer, :release].freeze
    @checks = {}
    @results = {}
    @disabled_checks = {}

    class << self
      def boot
        true
      end

      def register(id, config = nil, override: false, **keywords, &block)
        key = normalize_id(id)
        raise ArgumentError, "Validation ID is empty." if key.to_s.empty?
        raise "Validation already registered: #{key}" if @checks.key?(key) && !override
        raise ArgumentError, "A validation block is required." unless block
        source = config.is_a?(Hash) ? config.dup : {}
        source.merge!(keywords) unless keywords.empty?
        phase = normalize_id(source[:phase] || source["phase"] || :developer)
        raise "Unknown validation phase: #{phase}" unless PHASES.include?(phase)
        @checks[key] = {
          :id => key,
          :category => normalize_id(source[:category] || source["category"] || :foundation),
          :phase => phase,
          :owner => normalize_id(source[:owner] || source["owner"] || current_owner),
          :description => (source[:description] || source["description"] || "").to_s,
          :desktop_only => !!(source[:desktop_only] || source["desktop_only"]),
          :blocking => !!(source[:blocking] || source["blocking"]),
          :block => block
        }
        check(key)
      rescue Exception => e
        Reloaded::Log.exception("Validation registration failed for #{id}", e, channel: :framework) if defined?(Reloaded::Log)
        nil
      end

      def run(phase)
        phase_id = normalize_id(phase)
        raise "Unknown validation phase: #{phase_id}" unless PHASES.include?(phase_id)
        matching = @checks.values.select { |entry| entry[:phase] == phase_id }
        matching.each { |entry| run_entry(entry) }
        emit(:validation_completed, :phase => phase_id, :summary => summary)
        results(:phase => phase_id)
      rescue Exception => e
        Reloaded::Log.exception("Validation phase #{phase} failed", e, channel: :framework) if defined?(Reloaded::Log)
        []
      end

      def run_check(id)
        entry = @checks[normalize_id(id)]
        return [] unless entry
        run_entry(entry)
        Array(@results[entry[:id]]).map(&:dup)
      end

      def run_all(include_release: false)
        @checks.values.each do |entry|
          next if entry[:phase] == :release && !include_release
          run_entry(entry)
        end
        emit(:validation_completed, :phase => :all, :summary => summary)
        results
      end

      def refresh_report(include_release: false)
        run_all(:include_release => include_release)
        write_report
      end

      def check(id)
        entry = @checks[normalize_id(id)]
        entry ? public_check(entry) : nil
      end

      def checks
        @checks.keys.sort_by(&:to_s).map { |id| check(id) }
      end

      def results(options = {})
        phase = options[:phase] && normalize_id(options[:phase])
        check_ids = if phase
                      @checks.values.select { |entry| entry[:phase] == phase }.map { |entry| entry[:id] }
                    else
                      @results.keys
                    end
        check_ids.flat_map { |id| Array(@results[id]).map(&:dup) }
      end

      def summary
        rows = results
        counts = SEVERITIES.each_with_object({}) { |severity, output| output[severity] = rows.count { |row| row[:severity] == severity } }
        counts.merge(:checks => @checks.length, :disabled_checks => @disabled_checks.length, :findings => rows.length)
      end

      def write_report
        directory = File.dirname(REPORT_PATH)
        Dir.mkdir(directory) unless Dir.exist?(directory)
        data = summary
        lines = []
        lines << "[VALIDATION REPORT]"
        lines << "Timestamp: #{Time.now}"
        lines << "Checks: #{data[:checks]}"
        lines << "Disabled Checks: #{data[:disabled_checks]}"
        SEVERITIES.each { |severity| lines << "#{severity.to_s.upcase}: #{data[severity]}" }
        lines << ""
        report_rows, omitted = report_findings
        if report_rows.empty?
          lines << "No validation findings."
        else
          report_rows.each do |row|
            line = "[#{row[:severity].to_s.upcase}] [#{row[:category]}] #{row[:message]}"
            line += " (#{row[:code]})" unless row[:code].to_s.empty?
            lines << line
            lines << "  Owner: #{row[:owner]}" unless row[:owner].to_s.empty?
            lines << "  Fix: #{row[:recommended_fix]}" unless row[:recommended_fix].to_s.empty?
          end
        end
        if omitted > 0
          lines << ""
          lines << "[REPORT NOTICE] #{omitted} duplicate or excess finding(s) were omitted."
        end
        replace_report(sanitize(lines.join("\n")) + "\n")
        REPORT_PATH
      rescue Exception => e
        Reloaded::Log.exception("Validation report write failed", e, channel: :framework) if defined?(Reloaded::Log)
        nil
      end

      private

      def report_findings
        seen = {}
        unique = results.each_with_object([]) do |row, output|
          key = [row[:severity], row[:category], row[:check], row[:code], row[:message]]
          next if seen[key]
          seen[key] = true
          output << row
        end
        sorted = unique.sort_by do |row|
          [severity_rank(row[:severity]), row[:category].to_s, row[:check].to_s, row[:code].to_s]
        end
        shown = sorted.first(MAX_REPORT_FINDINGS)
        [shown, results.length - shown.length]
      end

      def replace_report(content)
        temp_path = "#{REPORT_PATH}.tmp"
        previous_path = "#{REPORT_PATH}.previous"
        File.open(temp_path, "w") { |file| file.write(content) }
        raise "Validation report temporary file is empty." if !File.file?(temp_path) || File.size(temp_path).to_i <= 0
        File.delete(previous_path) if File.exist?(previous_path)
        File.rename(REPORT_PATH, previous_path) if File.exist?(REPORT_PATH)
        begin
          File.rename(temp_path, REPORT_PATH)
          File.delete(previous_path) if File.exist?(previous_path)
        rescue Exception
          File.rename(previous_path, REPORT_PATH) if File.exist?(previous_path) && !File.exist?(REPORT_PATH)
          raise
        end
        true
      ensure
        File.delete(temp_path) rescue nil if defined?(temp_path) && File.exist?(temp_path)
      end

      def run_entry(entry)
        return [] if @disabled_checks[entry[:id]]
        if entry[:desktop_only] && defined?(Reloaded::Platform) && Reloaded::Platform.joiplay?
          @results[entry[:id]] = []
          return []
        end
        value = entry[:block].call(public_check(entry))
        @results[entry[:id]] = normalize_findings(value, entry)
        log_findings(@results[entry[:id]])
        @results[entry[:id]]
      rescue Exception => e
        @disabled_checks[entry[:id]] = true
        finding = normalize_finding({
          :severity => :error,
          :code => :validator_failed,
          :message => "Validator #{entry[:id]} failed: #{e.class}: #{e}",
          :recommended_fix => "Fix or disable the validator before relying on its results."
        }, entry)
        @results[entry[:id]] = [finding]
        Reloaded::Log.exception("Validator #{entry[:id]} failed", e, channel: :framework) if defined?(Reloaded::Log)
        [finding]
      end

      def normalize_findings(value, entry)
        return [] if value.nil? || value == true
        values = value.is_a?(Array) ? value : [value]
        values.map do |finding|
          source = finding.is_a?(Hash) ? finding : { :severity => (finding == false ? :error : :warning), :message => finding.to_s }
          normalize_finding(source, entry)
        end
      end

      def normalize_finding(source, entry)
        severity = normalize_id(source[:severity] || source["severity"] || :warning)
        severity = :warning unless SEVERITIES.include?(severity)
        {
          :severity => severity,
          :code => normalize_id(source[:code] || source["code"] || :validation_finding),
          :message => (source[:message] || source["message"] || "Validation finding").to_s,
          :details => source[:details] || source["details"],
          :recommended_fix => (source[:recommended_fix] || source["recommended_fix"] || "").to_s,
          :owner => normalize_id(source[:owner] || source["owner"] || entry[:owner]),
          :category => normalize_id(source[:category] || source["category"] || entry[:category]),
          :check => entry[:id],
          :phase => entry[:phase],
          :blocking => !!entry[:blocking]
        }
      end

      def log_findings(findings)
        return unless defined?(Reloaded::Log)
        findings.each do |finding|
          message = "Validation #{finding[:check]}: #{finding[:message]}"
          Reloaded::Log.write_once(
            :framework,
            message,
            :level => finding[:severity],
            :key => "validation:#{finding[:check]}:#{finding[:code]}:#{finding[:message]}"
          )
        end
      end

      def public_check(entry)
        entry.reject { |key, _value| key == :block }.dup
      end

      def severity_rank(value)
        { :critical => 0, :error => 1, :warning => 2, :info => 3 }[value] || 9
      end

      def sanitize(value)
        defined?(Reloaded::Log) ? Reloaded::Log.sanitize(value) : value.to_s
      rescue
        value.to_s
      end

      def emit(event, context)
        Reloaded::Events.emit(event, context) if defined?(Reloaded::Events)
      rescue
        nil
      end

      def current_owner
        mod_id = Thread.current[:reloaded_mod_id] rescue nil
        mod_id.to_s.empty? ? :reloaded : mod_id
      end

      def normalize_id(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "").to_sym
      end
    end

    register(:load_manifest, :category => :foundation, :phase => :modules_loaded) do
      next [] unless defined?(Reloaded::LoadOrder)
      files = Reloaded::LoadOrder.files
      findings = []
      duplicates = files.group_by { |path| path.to_s.gsub("\\", "/").downcase }.select { |_path, rows| rows.length > 1 }.keys
      duplicates.each { |path| findings << { :severity => :error, :code => :duplicate_load_entry, :message => "Duplicate load entry: #{path}" } }
      files.each do |path|
        full_path = File.join(ROOT, path)
        findings << { :severity => :critical, :code => :missing_load_file, :message => "Missing Reloaded load file: #{path}" } unless File.file?(full_path)
      end
      findings
    end

    register(:system_registry, :category => :systems, :phase => :modules_loaded) do
      next [] unless defined?(Reloaded::Systems)
      Reloaded::Systems.validate.each_with_object([]) do |row, findings|
        next if [:active, :disabled].include?(row[:state])
        severity = row[:state] == :unavailable ? :error : :warning
        findings << { :severity => severity, :code => "system_#{row[:state]}", :message => "System #{row[:id]} is #{row[:state]}: #{row[:reason]}" }
      end
    end

    register(:feature_registry, :category => :systems, :phase => :modules_loaded) do
      next [] unless defined?(Reloaded::Features)
      Reloaded::Features.features.each_with_object([]) do |feature, findings|
        next unless feature[:classification] == :stable && feature[:enabled] && !feature[:available]
        findings << { :severity => :warning, :code => :stable_feature_unavailable, :message => "Stable feature #{feature[:id]} is unavailable: #{feature[:reason]}" }
      end
    end

    register(:event_contracts, :category => :events, :phase => :modules_loaded) do
      defined?(Reloaded::Events) ? Reloaded::Events.validate : []
    end

    register(:data_patches, :category => :data_patches, :phase => :game_data_loaded) do
      next [] unless defined?(Reloaded::DataPatches)
      data = Reloaded::DataPatches.summary
      findings = []
      findings << { :severity => :error, :code => :data_patch_errors, :message => "Data patches reported #{data[:errors]} error(s)." } if data[:errors].to_i > 0
      findings << { :severity => :warning, :code => :data_patch_warnings, :message => "Data patches reported #{data[:warnings]} warning(s)." } if data[:warnings].to_i > 0
      findings
    end
  end
end

Reloaded::Events.define(:validation_completed, :required_context => [:phase, :summary]) if defined?(Reloaded::Events)
Reloaded::Events.on(:modules_loaded, :run_module_validation, :priority => 950) do |_context|
  Reloaded::Validation.run(:modules_loaded)
end if defined?(Reloaded::Events)
Reloaded::Events.on(:game_data_loaded, :run_game_data_validation, :priority => 950) do |_context|
  Reloaded::Validation.run(:game_data_loaded)
end if defined?(Reloaded::Events)
Reloaded::Events.on(:game_data_loaded, :refresh_completed_bug_report, :priority => 999) do |_context|
  Reloaded::Log.export_bug_report({}, false) if defined?(Reloaded::Log)
end if defined?(Reloaded::Events)
