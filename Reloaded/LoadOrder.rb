#======================================================
# Reloaded Load Order
# Author: Stonewall
#======================================================
# Explicit manifest for built-in Reloaded runtime files.
#
# External mods are loaded by Reloaded::ModManager and must not be added here.
# Admin Tools and ModDev Tools are never runtime manifest entries.
#======================================================

module Reloaded
  module LoadOrder
    PHASES = [
      {
        :id => :early,
        :scope => :core,
        :files => [
          "Core/Foundation/Logging.rb",
          "Core/Foundation/Settings.rb",
          "Core/Foundation/WindowTitle.rb"
        ]
      },
      {
        :id => :foundation,
        :scope => :core,
        :files => [
          "Core/Foundation/Versioning.rb",
          "Core/Foundation/APIContracts.rb",
          "Core/Foundation/Events.rb",
          "Core/Foundation/EventBridges.rb",
          "Core/Foundation/Patches.rb",
          "Core/Foundation/SaveMigrations.rb",
          "Core/Foundation/SaveData.rb",
          "Core/Foundation/SaveProtection.rb",
          "Core/Foundation/Assets.rb",
          "Core/Foundation/SpritePacks.rb",
          "Core/Foundation/Platform.rb",
          "Core/Foundation/Download.rb",
          "Core/Foundation/Archive.rb",
          "Core/Foundation/FileActions.rb",
          "Core/Foundation/RemoteData.rb",
          "Core/Foundation/TempCleanup.rb",
          "Core/Foundation/Task.rb",
          "Core/Foundation/SpriteImport.rb",
          "Core/Foundation/Rewards.rb",
          "Core/Foundation/RewardTypes.rb",
          "Core/Foundation/Systems.rb",
          "Core/Foundation/Features.rb",
          "Core/Foundation/Validation.rb",
          "Core/Foundation/Inspector.rb"
        ]
      },
      {
        :id => :modding,
        :scope => :core,
        :files => [
          "Core/Modding/ModManager.rb",
          "Core/Modding/Profiles.rb",
          "Core/Modding/ModManagerUI.rb",
          "Core/Modding/ModSettings.rb",
          "Core/Modding/ProfileCodes.rb",
          "Core/Modding/ModBrowser.rb",
          "Core/Modding/Publisher.rb",
          "Core/Modding/ModSettingsUI.rb",
          "Core/Modding/ModTools.rb"
        ]
      },
      {
        :id => :ui,
        :scope => :core,
        :files => [
          "Core/UI/Options.rb",
          "Core/UI/ReloadedAPIs.rb",
          "Core/UI/ActionMenu.rb",
          "Core/UI/ListState.rb",
          "Core/UI/ProgressWindow.rb",
          "Core/UI/ListPicker.rb",
          "Core/UI/GameDataPicker.rb",
          "Core/UI/NumberPicker.rb",
          "Core/UI/Form.rb",
          "Core/UI/TitleMenu.rb"
        ]
      },
      {
        :id => :data_patches,
        :scope => :core,
        :files => [
          "Core/DataPatches/Registry.rb",
          "Core/DataPatches/Outfits.rb",
          "Core/DataPatches/Items.rb",
          "Core/DataPatches/Moves.rb",
          "Core/DataPatches/AbilityAPI.rb",
          "Core/DataPatches/Abilities.rb",
          "Core/DataPatches/Species.rb",
          "Core/DataPatches/Trainers.rb",
          "Core/DataPatches/Encounters.rb",
          "Core/DataPatches/Quests.rb",
          "Core/DataPatches/TrainerTypes.rb"
        ]
      },
      {
        :id => :compatibility,
        :scope => :core,
        :files => [
          "Core/Compatibility/CoreFixes.rb"
        ]
      },
      {
        :id => :menus,
        :scope => :modules,
        :files => [
          "Modules/PauseMenu.rb",
          "Modules/TMVault.rb",
          "Modules/ReloadedMart/Backend.rb",
          "Modules/ReloadedMart/UI.rb",
          "Modules/ReloadedMart/Services.rb",
          "Modules/OverworldMenu.rb",
          "Modules/PCModule.rb",
          "Modules/PokeVial.rb",
          "Modules/IVBoundaries.rb",
          "Modules/ReloadedUI.rb",
          "Modules/HiddenPower.rb",
          "Modules/Fusion.rb",
          "Modules/ReloadedBag.rb"
        ]
      }
    ].freeze

    class << self
      def phases(scope = nil)
        return PHASES if scope.nil?
        PHASES.select { |phase| phase[:scope] == scope.to_sym }
      end

      def files(scope = nil)
        phases(scope).inject([]) { |result, phase| result.concat(Array(phase[:files])) }
      end
    end
  end
end
