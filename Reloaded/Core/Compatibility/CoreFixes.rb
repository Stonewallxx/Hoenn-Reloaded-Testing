#======================================================
# Reloaded Core Fixes
# Author: Stonewall
#======================================================
# Runtime fixes for base game behavior used by Hoenn Reloaded.
#
# Responsibilities:
#   - House focused base-runtime fixes that should not edit vanilla files.
#   - Patch locked overworld Pokemon events so interaction battles can start.
#   - Register fixes with the patch/conflict registry for reports.
#
#======================================================

module Reloaded
  module CoreFixes
    class << self
      def install
        installed = []
        installed << :overworld_pokemon_battle_lock if install_overworld_pokemon_battle_lock_fix
        register_patch_points(installed)
        log_installed(installed)
        !installed.empty?
      rescue Exception => e
        Reloaded::Log.exception("Core fixes install failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      private

      def install_overworld_pokemon_battle_lock_fix
        return false unless defined?(OverworldPokemonEvent)
        return false unless OverworldPokemonEvent.method_defined?(:overworldPokemonBattle)
        return true if OverworldPokemonEvent.method_defined?(:reloaded_orig_overworldPokemonBattle)

        OverworldPokemonEvent.class_eval do
          alias_method :reloaded_orig_overworldPokemonBattle, :overworldPokemonBattle

          def overworldPokemonBattle
            reloaded_was_locked = (lock? rescue false)
            unlock if reloaded_was_locked && respond_to?(:unlock)
            if reloaded_was_locked && defined?(Reloaded::Log)
              Reloaded::Log.debug_once(
                "Unlocked overworld Pokemon event before starting battle",
                :mods,
                key: "overworld_pokemon_battle_unlock"
              )
            end
            reloaded_orig_overworldPokemonBattle
          end
        end
        true
      end

      def register_patch_points(installed)
        return unless defined?(Reloaded::Patches)
        if installed.include?(:overworld_pokemon_battle_lock)
          Reloaded::Patches.register(
            :overworld_pokemon_battle_lock_fix,
            :target => "OverworldPokemonEvent#overworldPokemonBattle",
            :type => :wrap,
            :file => __FILE__,
            :owner => :reloaded,
            :priority => 100,
            :reason => "Base overworld Pokemon interaction can lock the event before battle starts.",
            :recommended_fix => "Review Reloaded::CoreFixes if visible overworld Pokemon cannot start battles.",
            :conflict_group => "overworld_pokemon_battle"
          )
        end
      end

      def log_installed(installed)
        return unless defined?(Reloaded::Log)
        return if installed.empty?
        Reloaded::Log.info("Installed Reloaded core fixes: #{installed.join(", ")}", :mods)
      end
    end
  end
end

Reloaded::CoreFixes.install if defined?(Reloaded::CoreFixes)
