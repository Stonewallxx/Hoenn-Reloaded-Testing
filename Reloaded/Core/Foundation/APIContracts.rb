#======================================================
# Reloaded API Contracts
# Author: Stonewall
#======================================================
# Classifies public, compatibility, developer, and internal APIs.
#======================================================

module Reloaded
  module API
    CLASSIFICATIONS = [:stable, :compatibility, :developer, :internal].freeze

    CONTRACTS = {
      :log             => { :classification => :stable,        :constant => "Reloaded::Log" },
      :events          => { :classification => :stable,        :constant => "Reloaded::Events" },
      :patches         => { :classification => :stable,        :constant => "Reloaded::Patches" },
      :save_data       => { :classification => :stable,        :constant => "Reloaded::SaveData" },
      :save_migrations => { :classification => :stable,        :constant => "Reloaded::SaveMigrations" },
      :assets          => { :classification => :stable,        :constant => "Reloaded::Assets" },
      :platform        => { :classification => :stable,        :constant => "Reloaded::Platform" },
      :download        => { :classification => :stable,        :constant => "Reloaded::Download" },
      :archive         => { :classification => :stable,        :constant => "Reloaded::Archive" },
      :file_actions    => { :classification => :stable,        :constant => "Reloaded::FileActions" },
      :remote_data     => { :classification => :stable,        :constant => "Reloaded::RemoteData" },
      :task            => { :classification => :stable,        :constant => "Reloaded::Task" },
      :rewards         => { :classification => :stable,        :constant => "Reloaded::Rewards" },
      :systems         => { :classification => :stable,        :constant => "Reloaded::Systems" },
      :features        => { :classification => :stable,        :constant => "Reloaded::Features" },
      :validation      => { :classification => :stable,        :constant => "Reloaded::Validation" },
      :data_patches    => { :classification => :stable,        :constant => "Reloaded::DataPatches" },
      :abilities       => { :classification => :stable,        :constant => "Reloaded::Abilities" },
      :mod_settings    => { :classification => :stable,        :constant => "Reloaded::ModSettings" },
      :popup_window    => { :classification => :stable,        :constant => "Reloaded::PopupWindow" },
      :action_menu     => { :classification => :stable,        :constant => "Reloaded::ActionMenu" },
      :progress_window => { :classification => :stable,        :constant => "Reloaded::ProgressWindow" },
      :text_input      => { :classification => :stable,        :constant => "Reloaded::TextInput" },
      :list_state      => { :classification => :stable,        :constant => "Reloaded::ListState" },
      :list_picker     => { :classification => :stable,        :constant => "Reloaded::ListPicker" },
      :game_data_picker => { :classification => :stable,       :constant => "Reloaded::GameDataPicker" },
      :number_picker   => { :classification => :stable,        :constant => "Reloaded::NumberPicker" },
      :form            => { :classification => :stable,        :constant => "Reloaded::Form" },
      :toast           => { :classification => :stable,        :constant => "Reloaded::Toast" },
      :hint_text       => { :classification => :stable,        :constant => "Reloaded::HintText" },
      :hooks           => { :classification => :compatibility, :constant => "Reloaded::Hooks", :replacement => "Reloaded::Events" },
      :modder_tools    => { :classification => :compatibility, :constant => "Reloaded::ModderTools", :replacement => "Reloaded::Diagnostics" },
      :diagnostics     => { :classification => :developer,     :constant => "Reloaded::Diagnostics" },
      :mod_archives    => { :classification => :developer,     :constant => "Reloaded::ModArchives" },
      :mod_development => { :classification => :developer,     :constant => "Reloaded::ModDevelopment" },
      :publisher       => { :classification => :developer,     :constant => "Reloaded::Publisher" }
    }.freeze

    class << self
      def contract(name)
        entry = CONTRACTS[name.to_sym]
        entry ? copy_contract(name, entry) : nil
      rescue
        nil
      end

      def contracts
        result = {}
        CONTRACTS.each { |name, entry| result[name] = copy_contract(name, entry) }
        result
      end

      def public?(name)
        entry = CONTRACTS[name.to_sym]
        !!entry && entry[:classification] == :stable
      rescue
        false
      end

      def available?(name)
        entry = CONTRACTS[name.to_sym]
        !!entry && constant_available?(entry[:constant])
      rescue
        false
      end

      private

      def copy_contract(name, entry)
        entry.merge(:name => name.to_sym)
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
    end
  end

  class << self
    def deprecate(name, replacement: nil, removal_version: nil)
      return false unless defined?(Reloaded::Log) && Reloaded::Log.developer?
      message = "Deprecated API used: #{name}"
      message += ". Use #{replacement} instead" if replacement && !replacement.to_s.empty?
      message += ". Planned removal: #{removal_version}" if removal_version && !removal_version.to_s.empty?
      Reloaded::Log.warning_once(message, :framework, key: "deprecated_api:#{name}")
      true
    rescue
      false
    end
  end
end
