#======================================================
# Reloaded Systems Registry
# Author: Stonewall
#======================================================
# Runtime inventory and dependency validation for Reloaded systems.
#======================================================

module Reloaded
  module Systems
    STATES = [:registered, :available, :active, :disabled, :degraded, :unavailable].freeze
    @systems = {}

    class << self
      def boot
        true
      end

      def register(id, config = nil, override: false, **keywords, &validation)
        key = normalize_id(id)
        raise ArgumentError, "System ID is empty." if key.to_s.empty?
        raise "System already registered: #{key}" if @systems.key?(key) && !override
        source = config.is_a?(Hash) ? config.dup : {}
        source.merge!(keywords) unless keywords.empty?
        entry = {
          :id => key,
          :name => (source[:name] || source["name"] || titleize(key)).to_s,
          :description => (source[:description] || source["description"] || "").to_s,
          :owner => normalize_id(source[:owner] || source["owner"] || :reloaded),
          :constant => blank_to_nil(source[:constant] || source["constant"]),
          :load_phase => normalize_id(source[:load_phase] || source["load_phase"] || :foundation),
          :required_systems => normalize_ids(source[:required_systems] || source["required_systems"]),
          :optional_systems => normalize_ids(source[:optional_systems] || source["optional_systems"]),
          :save_keys => normalize_ids(source[:save_keys] || source["save_keys"]),
          :feature_flags => normalize_ids(source[:feature_flags] || source["feature_flags"]),
          :platform_capabilities => normalize_ids(source[:platform_capabilities] || source["platform_capabilities"]),
          :debug_visible => !!(source.key?(:debug_visible) ? source[:debug_visible] : source["debug_visible"]),
          :validation => validation || source[:validation] || source["validation"]
        }
        @systems[key] = entry
        system(key)
      rescue Exception => e
        Reloaded::Log.exception("System registration failed for #{id}", e, channel: :framework) if defined?(Reloaded::Log)
        nil
      end

      def registered?(id)
        @systems.key?(normalize_id(id))
      end

      def available?(id)
        evaluate(id)[:available]
      end

      def active?(id)
        current_state = evaluate(id)[:state]
        current_state == :active || current_state == :degraded
      end

      def state(id)
        evaluate(id)[:state]
      end

      def reason(id)
        evaluate(id)[:reasons].join("; ")
      end

      def system(id)
        entry = @systems[normalize_id(id)]
        entry ? decorate(entry) : nil
      end

      def systems
        @systems.keys.sort_by(&:to_s).map { |id| system(id) }
      end

      def dependencies(id)
        entry = @systems[normalize_id(id)]
        return nil unless entry
        {
          :required => entry[:required_systems].dup,
          :optional => entry[:optional_systems].dup
        }
      end

      def validate
        systems.map do |entry|
          {
            :id => entry[:id],
            :state => entry[:state],
            :reason => entry[:reason]
          }
        end
      end

      def summary
        rows = systems
        counts = STATES.each_with_object({}) { |state_id, result| result[state_id] = rows.count { |row| row[:state] == state_id } }
        counts.merge(:total => rows.length)
      end

      def write_summary
        result = summary
        text = "System registry total=#{result[:total]} active=#{result[:active]} degraded=#{result[:degraded]} disabled=#{result[:disabled]} unavailable=#{result[:unavailable]}"
        Reloaded::Log.info_once(text, :framework, key: "system_registry:#{result.values.join(':')}") if defined?(Reloaded::Log)
        result
      end

      private

      def decorate(entry)
        result = public_entry(entry)
        evaluation = evaluate(entry[:id])
        result[:state] = evaluation[:state]
        result[:available] = evaluation[:available]
        result[:active] = evaluation[:state] == :active || evaluation[:state] == :degraded
        result[:reason] = evaluation[:reasons].join("; ")
        result
      end

      def evaluate(id, stack = [])
        key = normalize_id(id)
        entry = @systems[key]
        return { :state => :unavailable, :available => false, :reasons => ["System is not registered"] } unless entry
        return { :state => :unavailable, :available => false, :reasons => ["Dependency cycle: #{(stack + [key]).join(' -> ')}"] } if stack.include?(key)

        reasons = []
        optional_missing = []
        reasons << "Runtime constant #{entry[:constant]} is unavailable" if entry[:constant] && !constant_available?(entry[:constant])
        entry[:required_systems].each do |dependency|
          dependency_result = evaluate(dependency, stack + [key])
          reasons << "Required system #{dependency} is unavailable" unless dependency_result[:available]
        end
        entry[:optional_systems].each do |dependency|
          optional_missing << dependency unless evaluate(dependency, stack + [key])[:available]
        end
        entry[:platform_capabilities].each do |capability|
          supported = defined?(Reloaded::Platform) && Reloaded::Platform.supports?(capability)
          reasons << "Platform capability #{capability} is unavailable" unless supported
        end
        unless reasons.empty?
          return { :state => :unavailable, :available => false, :reasons => reasons }
        end

        disabled_flags = entry[:feature_flags].reject do |flag|
          !defined?(Reloaded::Features) || Reloaded::Features.active?(flag, :ignore_systems => true)
        end
        unless disabled_flags.empty?
          return { :state => :disabled, :available => true, :reasons => ["Feature disabled: #{disabled_flags.join(', ')}"] }
        end

        validation_reasons = run_validation(entry)
        all_optional = optional_missing.map { |dependency| "Optional system #{dependency} is unavailable" }
        degraded_reasons = all_optional + validation_reasons
        {
          :state => degraded_reasons.empty? ? :active : :degraded,
          :available => true,
          :reasons => degraded_reasons
        }
      rescue Exception => e
        { :state => :unavailable, :available => false, :reasons => ["Validation failed: #{e.class}: #{e}"] }
      end

      def run_validation(entry)
        callback = entry[:validation]
        return [] unless callback.respond_to?(:call)
        value = callback.call(public_entry(entry))
        return [] if value.nil? || value == true
        return ["System validation returned false"] if value == false
        Array(value).map(&:to_s).reject { |message| message.empty? }
      end

      def constant_available?(path)
        path.to_s.split("::").reject { |part| part.empty? }.inject(Object) do |owner, part|
          return false unless owner.const_defined?(part, false)
          owner.const_get(part, false)
        end
        true
      rescue
        false
      end

      def public_entry(entry)
        entry.reject { |key, _value| key == :validation }.each_with_object({}) do |(key, value), copy|
          copy[key] = value.is_a?(Array) ? value.dup : value
        end
      end

      def normalize_ids(values)
        Array(values).map { |value| normalize_id(value) }.reject { |value| value.to_s.empty? }.uniq
      end

      def normalize_id(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "").to_sym
      end

      def blank_to_nil(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def titleize(value)
        value.to_s.split("_").map { |part| part[0, 1].upcase + part[1..-1].to_s }.join(" ")
      end
    end

    BUILTIN_SYSTEMS = {
      :logging => { :constant => "Reloaded::Log" },
      :settings => { :constant => "Reloaded::Settings" },
      :versioning => { :constant => "Reloaded::Versioning" },
      :api_contracts => { :constant => "Reloaded::API" },
      :events => { :constant => "Reloaded::Events" },
      :systems => { :constant => "Reloaded::Systems" },
      :features => { :constant => "Reloaded::Features", :required_systems => [:systems] },
      :patches => { :constant => "Reloaded::Patches", :required_systems => [:logging] },
      :save_migrations => { :constant => "Reloaded::SaveMigrations" },
      :save_data => { :constant => "Reloaded::SaveData", :required_systems => [:events, :save_migrations], :save_keys => [:reloaded] },
      :save_protection => { :constant => "Reloaded::SaveProtection", :required_systems => [:save_data, :platform] },
      :assets => { :constant => "Reloaded::Assets", :required_systems => [:logging] },
      :platform => { :constant => "Reloaded::Platform" },
      :download => { :constant => "Reloaded::Download", :required_systems => [:platform, :task], :platform_capabilities => [:downloads] },
      :archive => { :constant => "Reloaded::Archive", :required_systems => [:platform], :platform_capabilities => [:archive_extract] },
      :file_actions => { :constant => "Reloaded::FileActions", :required_systems => [:platform] },
      :remote_data => { :constant => "Reloaded::RemoteData", :required_systems => [:platform], :platform_capabilities => [:remote_data] },
      :temp_cleanup => { :constant => "Reloaded::TempCleanup", :required_systems => [:platform, :remote_data, :events] },
      :task => { :constant => "Reloaded::Task", :required_systems => [:platform], :platform_capabilities => [:background_tasks] },
      :rewards => { :constant => "Reloaded::Rewards", :required_systems => [:events] },
      :validation => { :constant => "Reloaded::Validation", :required_systems => [:events, :systems] },
      :foundation_inspector => { :constant => "Reloaded::FoundationInspector", :required_systems => [:systems, :features, :validation, :save_protection] },
      :mod_manager => { :constant => "Reloaded::ModManager", :required_systems => [:assets, :events, :platform] },
      :profiles => { :constant => "Reloaded::Profiles", :required_systems => [:settings] },
      :mod_settings => { :constant => "Reloaded::ModSettings", :required_systems => [:profiles] },
      :mod_browser => { :constant => "Reloaded::ModBrowser", :required_systems => [:mod_manager, :platform, :download, :archive], :platform_capabilities => [:browser_downloads] },
      :publisher => { :constant => "Reloaded::Publisher", :required_systems => [:platform], :platform_capabilities => [:mod_publishing] },
      :shared_ui_apis => { :constant => "Reloaded::PopupWindow", :required_systems => [:platform], :load_phase => :ui },
      :action_menu => { :constant => "Reloaded::ActionMenu", :required_systems => [:shared_ui_apis], :load_phase => :ui },
      :progress_window => { :constant => "Reloaded::ProgressWindow", :required_systems => [:shared_ui_apis, :task], :load_phase => :ui },
      :list_state => { :constant => "Reloaded::ListState", :required_systems => [:shared_ui_apis], :load_phase => :ui },
      :list_picker => { :constant => "Reloaded::ListPicker", :required_systems => [:shared_ui_apis, :list_state], :load_phase => :ui },
      :game_data_picker => { :constant => "Reloaded::GameDataPicker", :required_systems => [:list_picker], :load_phase => :ui },
      :number_picker => { :constant => "Reloaded::NumberPicker", :required_systems => [:shared_ui_apis], :load_phase => :ui },
      :form => { :constant => "Reloaded::Form", :required_systems => [:shared_ui_apis, :list_state, :list_picker, :game_data_picker, :number_picker, :action_menu], :load_phase => :ui },
      :pause_menu => { :constant => "ReloadedPauseMenu", :required_systems => [:save_data, :shared_ui_apis], :save_keys => [:reloaded_pause_menu], :feature_flags => [:pause_menu], :load_phase => :modules },
      :tm_vault => { :constant => "Reloaded::TMVaultFeature", :required_systems => [:save_data], :save_keys => [:tm_vault], :feature_flags => [:tm_vault], :load_phase => :modules },
      :reloaded_mart => { :constant => "ReloadedMart", :required_systems => [:save_data, :events, :assets, :rewards], :optional_systems => [:tm_vault, :poke_vial], :save_keys => [:reloaded_mart], :feature_flags => [:reloaded_mart], :load_phase => :modules },
      :overworld_menu => { :constant => "OverworldMenu", :required_systems => [:save_data], :save_keys => [:overworld_menu], :feature_flags => [:overworld_menu], :load_phase => :modules },
      :pc_module => { :constant => "Reloaded::PCModuleFeature", :required_systems => [:pause_menu], :feature_flags => [:pc_module], :load_phase => :modules },
      :poke_vial => { :constant => "ReloadedPokeVial", :required_systems => [:save_data, :rewards], :save_keys => [:poke_vial], :feature_flags => [:poke_vial], :load_phase => :modules },
      :iv_boundaries => { :constant => "ReloadedIVBoundaries", :required_systems => [:save_data, :rewards], :save_keys => [:iv_boundaries], :feature_flags => [:iv_boundaries], :load_phase => :modules },
      :reloaded_ui => { :constant => "ReloadedUI", :required_systems => [:shared_ui_apis], :feature_flags => [:reloaded_ui], :load_phase => :modules },
      :hidden_power => { :constant => "ReloadedHiddenPower", :feature_flags => [:hidden_power], :load_phase => :modules },
      :fusion_support => { :constant => "ReloadedFusion", :feature_flags => [:fusion_support], :load_phase => :modules },
      :reloaded_bag => { :constant => "ReloadedBag", :required_systems => [:save_data, :shared_ui_apis], :feature_flags => [:reloaded_bag], :load_phase => :modules }
    }.freeze

    BUILTIN_SYSTEMS.each do |id, config|
      register(id, config.merge(:name => config[:name] || id.to_s.split("_").map(&:capitalize).join(" ")))
    end
  end

  class << self
    def register_system(id, config = nil, override: false, **keywords, &block)
      Systems.register(id, config, :override => override, **keywords, &block)
    end
  end
end

if defined?(Reloaded::Events)
  Reloaded::Events.on(:modules_loaded, :validate_registered_systems, :priority => 900) do |_context|
    Reloaded::Systems.write_summary
  end
end
