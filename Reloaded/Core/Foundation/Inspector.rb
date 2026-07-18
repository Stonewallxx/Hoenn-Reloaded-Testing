#======================================================
# Reloaded Foundation Inspector
# Author: Stonewall
#======================================================
# Read-only developer inspection for Reloaded foundation registries and saves.
#======================================================

module Reloaded
  module FoundationInspector
    class << self
      def open
        loop do
          choice = choose("Foundation Inspector", [
            ["Overview", :overview],
            ["Systems", :systems],
            ["Save & Migrations", :save],
            ["Features", :features],
            ["Events & Hooks", :events],
            ["Validators", :validators],
            ["Safe Actions", :actions]
          ])
          break if choice.nil?
          case choice
          when :overview then show_overview
          when :systems then browse_systems
          when :save then browse_save
          when :features then browse_features
          when :events then browse_events
          when :validators then browse_validators
          when :actions then browse_actions
          end
        end
        true
      rescue Exception => e
        Reloaded::Log.exception("Foundation Inspector failed", e, channel: :framework) if defined?(Reloaded::Log)
        notify("Foundation Inspector failed.", :error)
        false
      end

      private

      def show_overview
        systems = defined?(Reloaded::Systems) ? Reloaded::Systems.summary : {}
        features = defined?(Reloaded::Features) ? Reloaded::Features.features : []
        validation = defined?(Reloaded::Validation) ? Reloaded::Validation.summary : {}
        lines = []
        lines << "Reloaded: #{defined?(Reloaded::Versioning) ? Reloaded::Versioning.current : Reloaded.version}"
        lines << "Platform: #{defined?(Reloaded::Platform) ? Reloaded::Platform.label : 'Unknown'}"
        lines << "Systems: #{systems[:total].to_i} total, #{systems[:active].to_i} active, #{systems[:degraded].to_i} degraded"
        lines << "Features: #{features.length} total, #{features.count { |entry| entry[:active] }} active"
        lines << "Validation: #{validation[:findings].to_i} finding(s), #{validation[:error].to_i} error(s), #{validation[:critical].to_i} critical"
        lines << "Save writes: #{save_write_status}"
        message(lines.join("\n"))
      end

      def browse_systems
        return notify("The System Registry is unavailable.", :warning) unless defined?(Reloaded::Systems)
        rows = Reloaded::Systems.systems
        labeler = proc { |entry| [entry[:name], entry[:id], entry[:state].to_s.upcase] }
        detailer = proc do |entry|
          lines = []
          lines << entry[:name].to_s
          lines << "ID: #{entry[:id]}"
          lines << "State: #{entry[:state]}"
          lines << "Owner: #{entry[:owner]}"
          lines << "Load Phase: #{entry[:load_phase]}"
          lines << "Required: #{list(entry[:required_systems])}"
          lines << "Optional: #{list(entry[:optional_systems])}"
          lines << "Save Keys: #{list(entry[:save_keys])}"
          lines << "Features: #{list(entry[:feature_flags])}"
          lines << "Reason: #{entry[:reason]}" unless entry[:reason].to_s.empty?
          lines.join("\n")
        end
        browse("Systems", rows, labeler, detailer)
      end

      def browse_save
        choice = choose("Save & Migrations", [
          ["Save Metadata", :metadata],
          ["Migration Registry", :migrations],
          ["Write Protection", :protection]
        ])
        case choice
        when :metadata
          metadata = defined?(Reloaded::SaveData) ? Reloaded::SaveData.metadata : {}
          lines = metadata.keys.sort.map { |key| "#{titleize(key)}: #{format_value(metadata[key])}" }
          message(lines.empty? ? "No Reloaded save metadata is loaded." : lines.join("\n"))
        when :migrations
          migrations = defined?(Reloaded::SaveMigrations) ? Reloaded::SaveMigrations.migrations : []
          lines = migrations.map { |entry| "#{entry[:from]} -> #{entry[:to]}  #{entry[:id]}" }
          message(lines.empty? ? "No Reloaded migrations are registered." : lines.join("\n"))
        when :protection
          message("Save writes: #{save_write_status}\nCurrent slot: #{current_save_slot_label}")
        end
      end

      def browse_features
        return notify("The Feature Registry is unavailable.", :warning) unless defined?(Reloaded::Features)
        labeler = proc { |entry| [entry[:name], entry[:id], entry[:active] ? "ACTIVE" : "INACTIVE"] }
        detailer = proc do |entry|
          [
            entry[:name],
            "ID: #{entry[:id]}",
            "State: #{entry[:active] ? 'Active' : 'Inactive'}",
            "Classification: #{entry[:classification]}",
            "Owner: #{entry[:owner]}",
            "Required Systems: #{list(entry[:required_systems])}",
            "Required Capabilities: #{list(entry[:required_capabilities])}",
            "Reason: #{entry[:reason]}"
          ].join("\n")
        end
        browse("Features", Reloaded::Features.features, labeler, detailer)
      end

      def browse_events
        return notify("The Event Registry is unavailable.", :warning) unless defined?(Reloaded::Events)
        contracts = Reloaded::Events.contracts
        labeler = proc do |entry|
          count = Reloaded::Events.handlers(entry[:event]).length
          [entry[:event].to_s, entry[:event], "#{count} HANDLER#{count == 1 ? '' : 'S'}"]
        end
        detailer = proc do |entry|
          handlers = Reloaded::Events.handlers(entry[:event])
          owners = handlers.map { |handler| handler[:owner] }.uniq
          [
            entry[:event].to_s,
            "Mode: #{entry[:mode]}",
            "Owner: #{entry[:owner]}",
            "Handlers: #{handlers.length}",
            "Handler Owners: #{list(owners)}",
            "Required Context: #{list(entry[:required_context])}",
            "Optional Context: #{list(entry[:optional_context])}",
            entry[:description].to_s
          ].reject { |line| line.empty? }.join("\n")
        end
        browse("Events & Hooks", contracts, labeler, detailer)
      end

      def browse_validators
        return notify("The Validation Registry is unavailable.", :warning) unless defined?(Reloaded::Validation)
        labeler = proc do |entry|
          findings = Reloaded::Validation.results.select { |row| row[:check] == entry[:id] }
          [entry[:id].to_s, entry[:id], "#{findings.length} FINDING#{findings.length == 1 ? '' : 'S'}"]
        end
        detailer = proc do |entry|
          findings = Reloaded::Validation.results.select { |row| row[:check] == entry[:id] }
          counts = findings.group_by { |row| row[:severity] }
          [
            entry[:id].to_s,
            "Phase: #{entry[:phase]}",
            "Category: #{entry[:category]}",
            "Owner: #{entry[:owner]}",
            "Findings: #{findings.length}",
            "Warnings: #{Array(counts[:warning]).length}",
            "Errors: #{Array(counts[:error]).length}",
            "Critical: #{Array(counts[:critical]).length}",
            entry[:description].to_s
          ].reject { |line| line.empty? }.join("\n")
        end
        browse("Validators", Reloaded::Validation.checks, labeler, detailer)
      end

      def browse_actions
        choice = choose("Safe Actions", [
          ["Create Save Backup", :backup],
          ["Refresh Validation Report", :validation]
        ])
        case choice
        when :backup then create_current_backup
        when :validation then refresh_validation
        end
      end

      def create_current_backup
        path = current_save_path
        return notify("No current save file is available to back up.", :warning) if path.to_s.empty? || !File.file?(path)
        slot = File.basename(path, File.extname(path))
        if Reloaded::SaveProtection.backup_savefile(path, slot)
          notify("Save backup created.", :success)
        else
          notify("The save backup could not be created.", :error)
        end
      end

      def refresh_validation
        return notify("The Validation Registry is unavailable.", :warning) unless defined?(Reloaded::Validation)
        path = Reloaded::Validation.refresh_report
        if path
          notify("Validation report refreshed.", :success)
        else
          notify("The validation report could not be refreshed.", :error)
        end
      rescue Exception => e
        Reloaded::Log.exception("Validation report refresh failed", e, channel: :framework) if defined?(Reloaded::Log)
        notify("The validation report could not be refreshed.", :error)
      end

      def browse(title, rows, labeler, detailer)
        if defined?(Reloaded::ListPicker)
          entries = rows.map do |entry|
            label, value, status = labeler.call(entry)
            {
              :label => label.to_s,
              :value => value,
              :status => status.to_s,
              :detail => detailer.call(entry),
              :search_text => "#{label} #{value} #{status}"
            }
          end
          start_value = nil
          loop do
            selected = Reloaded::ListPicker.fullscreen(
              title.to_s,
              entries,
              :search => true,
              :details => true,
              :add_back => true,
              :start_value => start_value
            )
            break if selected.nil?
            start_value = selected
            entry = rows.find { |row| row[:id] == selected || row[:event] == selected }
            message(detailer.call(entry)) if entry
          end
          return
        end
        loop do
          options = rows.map do |entry|
            label, value, status = labeler.call(entry)
            text = status.to_s.empty? ? label.to_s : "#{label} - #{status}"
            [text, value]
          end
          selected = choose(title, options)
          break if selected.nil?
          entry = rows.find { |row| row[:id] == selected || row[:event] == selected }
          message(detailer.call(entry)) if entry
        end
      end

      def choose(title, rows)
        return nil unless Reloaded.respond_to?(:choice)
        choices = rows.map { |label, value| { :label => label.to_s, :value => value } }
        choices << { :label => "Back", :value => -1, :back => true }
        result = Reloaded.choice(title.to_s, choices, :add_back => false)
        result == -1 ? nil : result
      end

      def message(text)
        if Reloaded.respond_to?(:message)
          Reloaded.message(text.to_s)
        elsif defined?(Kernel) && Kernel.respond_to?(:pbMessage)
          Kernel.pbMessage(text.to_s)
        end
      end

      def notify(text, theme)
        if defined?(Reloaded::Toast)
          Reloaded::Toast.show(text.to_s, :theme => theme)
        else
          message(text)
        end
      rescue
        message(text)
      end

      def current_save_path
        if defined?($Trainer) && $Trainer && $Trainer.respond_to?(:save_slot) && defined?(::SaveData) && ::SaveData.respond_to?(:get_full_path)
          return ::SaveData.get_full_path($Trainer.save_slot)
        end
        return ::SaveData::FILE_PATH if defined?(::SaveData::FILE_PATH)
        nil
      rescue
        nil
      end

      def current_save_slot_label
        path = current_save_path
        path.to_s.empty? ? "None" : File.basename(path)
      end

      def save_write_status
        return "Unavailable" unless defined?(Reloaded::SaveData)
        return "Allowed" unless Reloaded::SaveData.write_blocked?
        "Blocked (#{Reloaded::SaveData.write_block_reason})"
      end

      def list(values)
        rows = Array(values).map(&:to_s)
        rows.empty? ? "None" : rows.join(", ")
      end

      def format_value(value)
        case value
        when Array
          return "None" if value.empty?
          value.map { |entry| entry.is_a?(Hash) ? format_hash(entry) : entry.to_s }.join(", ")
        when Hash then format_hash(value)
        else value.to_s
        end
      end

      def format_hash(value)
        value.keys.sort_by(&:to_s).map { |key| "#{key}=#{value[key]}" }.join(" ")
      end

      def titleize(value)
        value.to_s.split("_").map { |part| part[0, 1].upcase + part[1..-1].to_s }.join(" ")
      end
    end
  end
end
