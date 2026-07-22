# Hoenn Reloaded Expanded Dex ability handlers.
# Adapted from the AFI PokeAPI-derived compatibility implementation.
# Ability records are supplied by Reloaded/Data/ExpandedDex/ExpandedDex.dat.
# Follows the same BattleHandlers pattern as 011_Battle/003_BattleHandlers_Abilities.rb
# and 659_Multiplayer/008_Family/010_BoostedTalents.rb.
#
# Type Infusion compatibility (011_TypeInfusion.rb):
#   Type-converting abilities (Aerilate, Galvanize, etc.) are automatically compatible.
#   pbCalcType returns the post-conversion type, so STAB checks fire correctly and
#   Family type infusion triggers on converted STAB moves without any special handling.
#
# NOTE: Some abilities here already have handlers in the base engine
#   (011_Battle/003_BattleHandlers_Abilities.rb). Declaring them here is safe —
#   BattleHandlers.add stores by symbol key, so this overwrites with identical logic.
#   The 005_Abilities.rb stub registration is what makes these handlers actually fire.

#===============================================================================
# AERILATE
# Normal-type moves become Flying-type. Power boosted by 1.2x.
#
# Base engine already implements this in 003_BattleHandlers_Abilities.rb.
# Declared here explicitly so 007 is self-contained and documents all NPT abilities.
#
# Type Infusion: Aerilate-converted moves are Flying-type. If the user has Flying
# type, pbCalcType returns :FLYING → pbHasType? returns true → infusion triggers
# automatically. No extra code needed.
#===============================================================================

# Step 1: Convert Normal-type moves to Flying and flag them for the power boost.
if defined?(BattleHandlers) && defined?(BattleHandlers::MoveBaseTypeModifierAbility)
  BattleHandlers::MoveBaseTypeModifierAbility.add(:AERILATE,
    proc { |ability, user, move, type|
      next if type != :NORMAL || !GameData::Type.exists?(:FLYING)
      move.powerBoost = true
      next :FLYING
    }
  )
end

# Step 2: Apply 1.2x damage multiplier when powerBoost was set by the conversion.
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:AERILATE,
    proc { |ability, user, target, move, mults, baseDmg, type|
      mults[:base_damage_multiplier] *= 1.2 if move.powerBoost
    }
  )
end

# Step 3: Visual feedback — ability splash + message on real move use.
# MoveBaseTypeModifierAbility fires inside pbCalcType which is also called
# during AI damage prediction, so we hook pbUseMove instead (real moves only).
class PokeBattle_Battler
  alias npt_aerilate_original_pbUseMove pbUseMove if !method_defined?(:npt_aerilate_original_pbUseMove)

  def pbUseMove(choice, specialUsage = false)
    move = choice[2]

    if move && @ability_id == :AERILATE && !move.callsAnotherMove? && !move.snatched
      if move.type == :NORMAL && GameData::Type.exists?(:FLYING)
        @battle.pbShowAbilitySplash(self)
        @battle.pbDisplay(_INTL("{1}'s Aerilate turned the Normal-type move into a Flying-type move!", self.pbThis))
        @battle.pbHideAbilitySplash(self)
      end
    end

    npt_aerilate_original_pbUseMove(choice, specialUsage)
  end
end

#===============================================================================
# AROMA VEIL
# Protects the bearer and its allies from move-restriction effects
# (Taunt, Encore, Torment, Disable, Heal Block, Attract, etc.).
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   pbMoveFailedAromaVeil? in 011_Battle/002_Move/002_Move_Usage.rb checks
#   hasActiveAbility?(:AROMAVEIL) on the target AND its allies.
#   Attract immunity in 004_Battler_Statuses.rb includes :AROMAVEIL.
#   Registering :AROMAVEIL in 005_Abilities.rb is sufficient.
#
# Type Infusion: Defensive/protective ability — no interaction with outgoing moves.
#===============================================================================

#===============================================================================
# ANGER SHELL
# When the Pokémon's HP drops from above half to half or below due to a hit:
#   Raises Attack, Sp. Atk, Speed by 1 stage.
#   Lowers Defense, Sp. Def by 1 stage.
#
# Same HP-crossing trigger as Berserk (initialHP >= half, current hp < half).
# Type Infusion: triggers on incoming damage, not outgoing — no interaction.
#   The boosted Attack/Sp.Atk/Speed benefit future moves normally, infusion
#   activates on those moves if they are STAB, as usual.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityAfterMoveUse)
  BattleHandlers::TargetAbilityAfterMoveUse.add(:ANGERSHELL,
    proc { |ability, target, user, move, switched, battle|
      next if !move.damagingMove?
      # Trigger only when HP crosses the halfway threshold this hit
      next if target.damageState.initialHP < target.totalhp / 2 || target.hp >= target.totalhp / 2

      battle.pbShowAbilitySplash(target)

      # Offensive boosts
      target.pbRaiseStatStage(:ATTACK,         1, target) if target.pbCanRaiseStatStage?(:ATTACK,         target)
      target.pbRaiseStatStage(:SPECIAL_ATTACK, 1, target) if target.pbCanRaiseStatStage?(:SPECIAL_ATTACK, target)
      target.pbRaiseStatStage(:SPEED,          1, target) if target.pbCanRaiseStatStage?(:SPEED,          target)

      # Defensive drops
      target.pbLowerStatStage(:DEFENSE,         1, target) if target.pbCanLowerStatStage?(:DEFENSE,         target)
      target.pbLowerStatStage(:SPECIAL_DEFENSE, 1, target) if target.pbCanLowerStatStage?(:SPECIAL_DEFENSE, target)

      battle.pbHideAbilitySplash(target)
    }
  )
end

#===============================================================================
# ARMOR TAIL UNTESTED
# Prevents opposing Pokémon from using priority moves against the bearer's side.
# Identical mechanic to Dazzling / Queenly Majesty (MoveBlockingAbility).
# Protects all allies: the handler loops through all targets and blocks if any
# target is on the bearer's side.
#
# Type Infusion: Defensive/reactive ability — no interaction with outgoing moves.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::MoveBlockingAbility)
  BattleHandlers::MoveBlockingAbility.add(:ARMORTAIL,
    proc { |ability, bearer, user, targets, move, battle|
      next false if battle.choices[user.index][4] <= 0  # Not a priority move
      next false if !bearer.opposes?(user)               # Bearer must oppose the attacker
      ret = false
      targets.each do |b|
        next if !b.opposes?(user)  # Only care about targets on the bearer's side
        ret = true
      end
      next ret
    }
  )
end

#===============================================================================
# AURA BREAK
# Reverses Fairy Aura and Dark Aura: their 4/3x boost becomes a 3/4x reduction.
#
# AbilityOnSwitchIn announcement already exists in the base engine.
# The reversal is passive — FAIRYAURA and DARKAURA handlers check the field for
# AURABREAK and apply 3/4 instead of 4/3 when it is present.
#
# Base engine has switch-in handlers for FAIRYAURA and DARKAURA (announcement
# only, no damage calc). Damage calc for both auras is added here alongside
# AURABREAK so all three work together as a unit.
#
# Coverage (four handler types for full field-wide effect):
#   DamageCalcUserAbility       — aura holder attacks with Fairy/Dark move
#   DamageCalcTargetAbility     — aura holder is hit by a Fairy/Dark move
#   DamageCalcUserAllyAbility   — aura holder's ally attacks with Fairy/Dark move
#   DamageCalcTargetAllyAbility — enemy attacks holder's ally with Fairy/Dark move
#     (ability = :FAIRYAURA/:DARKAURA is the holder's; target = the attacked ally.
#      All four cases boost the incoming Fairy/Dark move unless AURABREAK is up.)
#
# Type Infusion: Aura boosts the PRIMARY move type. Type infusion adds a
# secondary effectiveness multiplier via pbCalcTypeModSingle — both systems
# operate on separate multipliers and compose naturally.
#===============================================================================

# ── Helper: check if AURABREAK is active on the field ──────────────────────
# Used inside every aura handler below.
def npt_aura_break_active?(battle)
  battle.battlers.any? { |b| b && !b.fainted? && b.hasActiveAbility?(:AURABREAK) }
end

# ── DamageCalcUserAbility: fires when the AURA HOLDER attacks ───────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:FAIRYAURA,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next if type != :FAIRY
      mults[:base_damage_multiplier] *= npt_aura_break_active?(user.battle) ? (3.0 / 4) : (4.0 / 3)
    }
  )

  BattleHandlers::DamageCalcUserAbility.add(:DARKAURA,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next if type != :DARK
      mults[:base_damage_multiplier] *= npt_aura_break_active?(user.battle) ? (3.0 / 4) : (4.0 / 3)
    }
  )
end

# ── DamageCalcTargetAbility: fires when the AURA HOLDER is targeted ─────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAbility)
  BattleHandlers::DamageCalcTargetAbility.add(:FAIRYAURA,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next if type != :FAIRY
      mults[:base_damage_multiplier] *= npt_aura_break_active?(target.battle) ? (3.0 / 4) : (4.0 / 3)
    }
  )

  BattleHandlers::DamageCalcTargetAbility.add(:DARKAURA,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next if type != :DARK
      mults[:base_damage_multiplier] *= npt_aura_break_active?(target.battle) ? (3.0 / 4) : (4.0 / 3)
    }
  )
end

# ── DamageCalcUserAllyAbility: fires when the AURA HOLDER's ALLY attacks ────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAllyAbility)
  BattleHandlers::DamageCalcUserAllyAbility.add(:FAIRYAURA,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next if type != :FAIRY
      mults[:base_damage_multiplier] *= npt_aura_break_active?(user.battle) ? (3.0 / 4) : (4.0 / 3)
    }
  )

  BattleHandlers::DamageCalcUserAllyAbility.add(:DARKAURA,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next if type != :DARK
      mults[:base_damage_multiplier] *= npt_aura_break_active?(user.battle) ? (3.0 / 4) : (4.0 / 3)
    }
  )
end

# ── DamageCalcTargetAllyAbility: enemy attacks HOLDER's ALLY with Fairy/Dark ─
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAllyAbility)
  BattleHandlers::DamageCalcTargetAllyAbility.add(:FAIRYAURA,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next if type != :FAIRY
      mults[:base_damage_multiplier] *= npt_aura_break_active?(target.battle) ? (3.0 / 4) : (4.0 / 3)
    }
  )

  BattleHandlers::DamageCalcTargetAllyAbility.add(:DARKAURA,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next if type != :DARK
      mults[:base_damage_multiplier] *= npt_aura_break_active?(target.battle) ? (3.0 / 4) : (4.0 / 3)
    }
  )
end

#===============================================================================
# BALL FETCH
# In a wild battle, when the first Poké Ball throw fails, a Pokémon with Ball
# Fetch that is not holding an item retrieves the ball (adds it back to the bag).
# Only triggers once per battle.
#
# Coop wild battle compatibility:
#   Each human player's client handles only their OWN Ball Fetch.
#   In coop, the local player's battlers are pbOwnedByPlayer?==true;
#   the remote ally's battlers are NPCTrainers (pbOwnedByPlayer?==false).
#   We only run Ball Fetch if:
#     (a) the throw was from the LOCAL player (pbOwnedByPlayer?(idxBattler))
#     (b) the Ball Fetch holder is ALSO owned by the local player
#   This ensures each client independently handles their own Pokémon's ability
#   without interfering with the ally's ball throws or bag.
#
# $PokemonBag is the local player's bag — returning to it is always correct
#   when the local player is the thrower.
#
# Type Infusion: Utility/field ability — no interaction with combat moves.
# Multiplayer note: Trainer battles block ball throws before this code runs,
#   so Ball Fetch never fires in PvP battles.
#===============================================================================

if defined?(PokeBattle_Battle)
  class PokeBattle_Battle
    alias npt_ballfetch_original_pbThrowPokeBall pbThrowPokeBall if !method_defined?(:npt_ballfetch_original_pbThrowPokeBall)

    def pbThrowPokeBall(idxBattler, ball, catch_rate = nil, showPlayer = false)
      pre_caught = @caughtPokemon ? @caughtPokemon.length : 0
      is_wild    = !trainerBattle?
      # Only track for local player's throws — coop allies handle their own Ball Fetch
      is_player_throw = is_wild && pbOwnedByPlayer?(idxBattler)

      npt_ballfetch_original_pbThrowPokeBall(idxBattler, ball, catch_rate, showPlayer)

      return unless is_player_throw
      return if @npt_ballfetch_used

      # Failure check: caught count unchanged after the throw
      post_caught = @caughtPokemon ? @caughtPokemon.length : 0
      return if post_caught > pre_caught

      # Check only LOCAL PLAYER'S active battlers for Ball Fetch with no held item.
      # pbOwnedByPlayer?(battler.index) filters out the coop ally's battlers on the
      # same side, ensuring we don't double-activate in coop battles.
      allSameSideBattlers(idxBattler).each do |battler|
        next unless battler.hasActiveAbility?(:BALLFETCH)
        next if battler.pokemon&.hasItem?
        next unless pbOwnedByPlayer?(battler.index)  # Coop: skip ally's battlers

        $PokemonBag.pbStoreItem(ball) if defined?($PokemonBag)
        pbShowAbilitySplash(battler)
        pbDisplay(_INTL("{1}'s Ball Fetch returned the {2}!",
                        battler.pbThis, GameData::Item.get(ball).name))
        pbHideAbilitySplash(battler)
        @npt_ballfetch_used = true
        break
      end
    end
  end
end

#===============================================================================
# BATTERY
# Boosts the power of ally Pokémon's special moves by 1.3x.
# The holder itself does NOT benefit from its own Battery.
#
# DamageCalcUserAllyAbility fires when an ALLY of the holder uses a move.
# Only special moves (category 1) are boosted.
#
# AbilityOnSwitchIn announces the ability on entry so players know the field
# effect is active — mirrors how Fairy Aura / Dark Aura are announced.
#
# Type Infusion: Battery boosts base damage; infusion adds a secondary type
# effectiveness multiplier via pbCalcTypeModSingle. Both compose naturally
# (Battery fires in DamageCalc, infusion fires in pbCalcTypeModSingle) —
# no special handling needed.
#===============================================================================

# Switch-in announcement
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:BATTERY,
    proc { |ability, battler, battle|
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1} is charging up its allies' special moves!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    }
  )
end

# 1.3x boost to allies' special moves
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAllyAbility)
  BattleHandlers::DamageCalcUserAllyAbility.add(:BATTERY,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.specialMove?
      mults[:base_damage_multiplier] *= 1.3
    }
  )
end

#===============================================================================
# BEADS OF RUIN
# Reduces the Special Defense of all other Pokémon on the field by 25%.
# The holder itself is unaffected.
#
# Field-wide passive, same architecture as Fairy Aura / Dark Aura.
# Coverage (three handler types for full field-wide effect):
#   DamageCalcUserAbility       — holder attacks → target's Sp. Def -25%
#   DamageCalcUserAllyAbility   — holder's ally attacks → target's Sp. Def -25%
#   DamageCalcTargetAllyAbility — enemy attacks holder's ally → ally's Sp. Def -25%
#     (ability = :BEADSOFRUIN is the holder's; target = the attacked ally.
#      The holder is always the ALLY in this handler, never the target —
#      so no self-exemption check is needed.)
#
# DamageCalcTargetAbility is intentionally OMITTED: when the holder is the
# target, its own Sp. Def must NOT be reduced (the ability exempts the holder).
# Exemption also applies to OTHER Beads of Ruin holders: target.hasActiveAbility?
# (:BEADSOFRUIN) guard in each handler skips the reduction for fellow holders.
#
# defense_multiplier is generic — applies to whichever defense stat the move
# uses. Restricting to specialMove? ensures only Sp. Def (not Def) is affected.
#
# Type Infusion: defense_multiplier and infused-type effectiveness are separate
# multipliers — compose naturally with no extra code.
#===============================================================================

# Switch-in announcement
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:BEADSOFRUIN,
    proc { |ability, battler, battle|
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1}'s Beads of Ruin weakened all other Pokémon's Special Defense!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    }
  )
end

# Holder attacks: target's Sp. Def -25% (skip if target also has Beads of Ruin)
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:BEADSOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.specialMove?
      next if target.hasActiveAbility?(:BEADSOFRUIN)
      mults[:defense_multiplier] *= 0.75
    }
  )
end

# Holder's ally attacks: target's Sp. Def -25% (skip if target also has Beads of Ruin)
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAllyAbility)
  BattleHandlers::DamageCalcUserAllyAbility.add(:BEADSOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.specialMove?
      next if target.hasActiveAbility?(:BEADSOFRUIN)
      mults[:defense_multiplier] *= 0.75
    }
  )
end

# Enemy attacks holder's ally: ally's Sp. Def -25% (skip if ally also has Beads of Ruin)
# DamageCalcTargetAllyAbility fires when the TARGET's ALLY has the ability.
# Here: target = the attacked ally, ability = :BEADSOFRUIN from the holder.
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAllyAbility)
  BattleHandlers::DamageCalcTargetAllyAbility.add(:BEADSOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.specialMove?
      next if target.hasActiveAbility?(:BEADSOFRUIN)
      mults[:defense_multiplier] *= 0.75
    }
  )
end

#===============================================================================
# BEAST BOOST
# When the holder knocks out a Pokémon, raises its own highest base stat by 1.
#
# Uses UserAbilityEndOfMove (same handler as Moxie) which fires after the user's
# move resolves. Checks targets.damageState.fainted to confirm a KO happened.
#
# Stat selection: compares the five battling stats (Attack, Defense, Sp. Atk,
# Sp. Def, Speed) by BASE value. HP is excluded — it cannot be raised as a
# stage. Ties are broken by priority: Atk > Def > SpAtk > SpDef > Speed.
#
# user.pokemon.baseStats returns the hash for both fused and standard Pokémon
# (fusions compute averaged base stats dynamically in KIF).
#
# pbRaiseStatStageByAbility handles the ability splash + message internally,
# matching the Moxie pattern — no manual Show/HideAbilitySplash needed.
#
# Type Infusion: Beast Boost fires post-move and raises a stat stage. Future
# STAB moves benefit from the boost normally; infusion triggers on those if
# they meet the STAB check. No special handling needed.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::UserAbilityEndOfMove)
  BattleHandlers::UserAbilityEndOfMove.add(:BEASTBOOST,
    proc { |ability, user, targets, move, battle|
      next if battle.pbAllFainted?(user.idxOpposingSide)
      next unless targets.any? { |b| b.damageState.fainted }

      base = user.pokemon.baseStats rescue nil
      next unless base

      # Priority order for ties: Attack > Defense > Sp. Atk > Sp. Def > Speed
      stat_order = [:ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]
      max_val     = stat_order.map { |s| base[s] || 0 }.max
      stat        = stat_order.find { |s| (base[s] || 0) == max_val }

      next unless stat && user.pbCanRaiseStatStage?(stat, user)
      user.pbRaiseStatStageByAbility(stat, 1, user, GameData::Ability.get(ability).real_name)
    }
  )
end

#===============================================================================
# BERSERK
# When the Pokémon's HP drops from above half to half or below due to a hit,
# raises its Special Attack by 1 stage.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   TargetAbilityAfterMoveUse.add(:BERSERK) in 003_BattleHandlers_Abilities.rb
#   checks initialHP >= half and current hp < half, then calls
#   pbRaiseStatStageByAbility(:SPECIAL_ATTACK, 1, ...).
#   Registering :BERSERK in 005_Abilities.rb is sufficient.
#
# Type Infusion: triggers on incoming damage — no interaction during the hit.
#   The Sp. Atk boost benefits future special STAB moves normally.
#===============================================================================

#===============================================================================
# CHEEK POUCH
# When the holder eats a Berry, restores 1/3 of its max HP in addition to the
# Berry's normal effect.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   pbHeldItemTriggered in 001_Battler/006_Battler_AbilityAndItem.rb checks
#   hasActiveAbility?(:CHEEKPOUCH) && item.is_berry? && canHeal?, then calls
#   pbRecoverHP(totalhp / 3) with the ability splash.
#   Registering :CHEEKPOUCH in 005_Abilities.rb is sufficient.
#
# Type Infusion: utility/recovery ability — no interaction with outgoing moves.
#===============================================================================

#===============================================================================
# CHILLING NEIGH
# When the holder knocks out a Pokémon, raises its own Attack by 1 stage.
# Identical mechanic to Moxie (which also raises Attack by 1 on KO).
#
# Uses UserAbilityEndOfMove — same handler as Moxie (confirmed in base engine:
#   003_BattleHandlers_Abilities.rb). Fires after the move resolves; checks
#   targets array for fainted Pokémon.
#
# pbRaiseStatStageByAbility handles ability splash + message internally.
#
# Type Infusion: post-KO stat boost — no interaction with outgoing moves.
#   Future STAB moves benefit from the Attack boost normally.
#===============================================================================
if defined?(BattleHandlers) && defined?(BattleHandlers::UserAbilityEndOfMove)
  BattleHandlers::UserAbilityEndOfMove.add(:CHILLINGNEIGH,
    proc { |ability, user, targets, move, battle|
      next if battle.pbAllFainted?(user.idxOpposingSide)
      next unless targets.any? { |b| b.damageState.fainted }
      next unless user.pbCanRaiseStatStage?(:ATTACK, user)
      user.pbRaiseStatStageByAbility(:ATTACK, 1, user, GameData::Ability.get(ability).real_name)
    }
  )
end
#===============================================================================
# COMATOSE
# The Pokémon is always in a drowsy (pseudo-sleep) state and cannot be
# afflicted by any other status condition.
#
# Base engine handles this but hardcodes isSpecies?(:KOMALA) in two handlers,
# so non-Komala NPT Pokémon with the ability are unaffected.
# HandlerHash2.add replaces — loading here (990_NPT, after 011_Battle) overwrites
# the Komala-locked procs with universal ones.
#
# Three handlers replaced/confirmed:
#   StatusCheckAbilityNonIgnorable — allows pseudo-sleep (Sleep Talk / Snore).
#     Original: next false if !isSpecies?(:KOMALA). Removed — any holder qualifies.
#   StatusImmunityAbilityNonIgnorable — blocks all status conditions.
#     Original: next true if isSpecies?(:KOMALA). Removed — any holder is immune.
#   AbilityOnSwitchIn — announces "is drowsing!".
#     Original has NO species check; already fires for any COMATOSE holder.
#     Overwritten here anyway to keep all three in one place for clarity.
#
# Type Infusion: status/defensive ability — no interaction with outgoing moves.
#===============================================================================

if defined?(BattleHandlers)
  # Allows the holder to be treated as asleep for move purposes (pseudo-sleep).
  # status nil = "check if holder has a status at all"; :SLEEP = normal sleep query.
  if defined?(BattleHandlers::StatusCheckAbilityNonIgnorable)
    BattleHandlers::StatusCheckAbilityNonIgnorable.add(:COMATOSE,
      proc { |ability, battler, status|
        next true if status.nil? || status == :SLEEP
      }
    )
  end

  # Blocks ALL status conditions for any COMATOSE holder.
  if defined?(BattleHandlers::StatusImmunityAbilityNonIgnorable)
    BattleHandlers::StatusImmunityAbilityNonIgnorable.add(:COMATOSE,
      proc { |ability, battler, status|
        next true
      }
    )
  end

  # Switch-in announcement (already species-agnostic in the base engine;
  # overwritten here for consistency — no behaviour change).
  if defined?(BattleHandlers::AbilityOnSwitchIn)
    BattleHandlers::AbilityOnSwitchIn.add(:COMATOSE,
      proc { |ability, battler, battle|
        battle.pbShowAbilitySplash(battler)
        battle.pbDisplay(_INTL("{1} is drowsing!", battler.pbThis))
        battle.pbHideAbilitySplash(battler)
      }
    )
  end
end

#===============================================================================
# CORROSION
# The holder can inflict the Poison status on Steel-type and Poison-type
# Pokémon that would normally be immune.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   pbCanInflictStatus?(:POISON, ...) in 001_Battler/004_Battler_Statuses.rb
#   checks `user.hasActiveAbility?(:CORROSION)` by symbol (no species lock)
#   and skips the Poison/Steel type immunity when it is present.
#   Registering :CORROSION in 005_Abilities.rb is sufficient.
#
# Type Infusion: status-infliction ability — no interaction with outgoing moves.
#===============================================================================

#===============================================================================
# COSTAR
# When the holder switches in, it copies all of its ally's current stat stages.
# If there is no ally, or the ally has no stat boosts or drops, nothing happens.
#
# Implementation: AbilityOnSwitchIn — battler.eachAlly yields unfainted allies.
# Copies each stat stage value from the ally to self (stages hash key by key).
# Only fires message if at least one stage is non-zero.
#
# Type Infusion: switch-in ability — no interaction with outgoing moves.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:COSTAR,
    proc { |ability, battler, battle|
      # In 3v3 there may be multiple allies — pick the one with the most total
      # stat change magnitude so we always copy the most boosted partner.
      # In 2v2 co-op there is exactly one ally, so this reduces to the simple case.
      ally       = nil
      best_boost = 0
      battler.eachAlly do |b|
        total = b.stages.values.sum { |v| v.abs }
        if total > best_boost
          best_boost = total
          ally       = b
        end
      end
      next unless ally
      next unless best_boost > 0
      ally.stages.each { |stat, val| battler.stages[stat] = val }
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1} copied {2}'s stat changes!", battler.pbThis, ally.pbThis(true)))
      battle.pbHideAbilitySplash(battler)
    }
  )
end

#===============================================================================
# COTTON DOWN
# When the holder is hit by a damaging move, it scatters cotton and lowers the
# Speed of ALL other battlers (allies and foes) by 1 stage.
# The holder itself is unaffected.
#
# Handler: TargetAbilityOnHit — fires after the holder takes a hit.
# Iterates all non-fainted battlers except the holder and attempts the Speed drop.
# Ability splash + announcement shown once regardless of how many are lowered.
#
# 3v3 / 2v2 co-op: iterates @battle.battlers — works for any field size.
# Multi-hit moves: fires once per hit (standard TargetAbilityOnHit behaviour).
#
# Type Infusion: triggered on taking damage — no interaction with outgoing moves.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.add(:COTTONDOWN,
    proc { |ability, user, target, move, battle|
      next unless move.damagingMove?
      battle.pbShowAbilitySplash(target)
      battle.pbDisplay(_INTL("{1} scattered cotton fluff everywhere!", target.pbThis))
      battle.battlers.each do |b|
        next unless b && !b.fainted? && b.index != target.index
        next unless b.pbCanLowerStatStage?(:SPEED, target)
        b.pbLowerStatStage(:SPEED, 1, target)
      end
      battle.pbHideAbilitySplash(target)
    }
  )
end

#===============================================================================
# CUD CHEW
# When the holder eats a Berry, it will eat that Berry again at the end of the
# NEXT turn (one full turn after consumption, not the same turn).
#
# Implementation uses a two-state flag stored as instance variables:
#   @cudchew_berry  — symbol ID of the berry to replay
#   @cudchew_state  — :waiting (consumed this turn) → :ready (replay next EOR)
#
# Step 1: Alias pbHeldItemTriggered to detect own-berry consumption.
#   own_item=true means the battler ate its OWN held item.
#   own_item=false (Bug Bite / Fling / Cud Chew replay) is ignored — prevents
#   infinite re-queuing and correctly excludes stolen berries.
#
# Step 2: EORGainItemAbility fires each end-of-round.
#   - :waiting → :ready  (first EOR after eating, just advance the state)
#   - :ready   → fire    (second EOR, replay the berry via pbHeldItemTriggerCheck)
#   pbHeldItemTriggerCheck(berry_id) passes forced=true, so HP berries
#   (Sitrus, Oran, Figy…) bypass their HP-threshold requirement on replay.
#   It also calls pbHeldItemTriggered with own_item=false, so pbConsumeItem
#   is skipped (berry was already consumed) and the alias does not re-queue.
#
# Type Infusion: item-consumption ability — no interaction with outgoing moves.
#===============================================================================

class PokeBattle_Battler
  alias npt_cudchew_original_pbHeldItemTriggered pbHeldItemTriggered
  def pbHeldItemTriggered(item_to_use, own_item = true, fling = false)
    # Detect own-berry consumption (not Bug Bite / Fling / Cud Chew replay).
    if own_item && !fling && hasActiveAbility?(:CUDCHEW)
      berry_id = item_to_use || @item_id
      if berry_id && GameData::Item.get(berry_id).is_berry?
        @cudchew_berry = berry_id
        @cudchew_state = :waiting
      end
    end
    npt_cudchew_original_pbHeldItemTriggered(item_to_use, own_item, fling)
  end
end

if defined?(BattleHandlers) && defined?(BattleHandlers::EORGainItemAbility)
  BattleHandlers::EORGainItemAbility.add(:CUDCHEW,
    proc { |ability, battler, battle|
      state = battler.instance_variable_get(:@cudchew_state)
      if state == :ready
        berry = battler.instance_variable_get(:@cudchew_berry)
        battler.instance_variable_set(:@cudchew_berry, nil)
        battler.instance_variable_set(:@cudchew_state, nil)
        next unless berry && GameData::Item.exists?(berry)
        battle.pbShowAbilitySplash(battler)
        battle.pbDisplay(_INTL("{1} chewed its {2} again!",
                               battler.pbThis, GameData::Item.get(berry).name))
        battle.pbHideAbilitySplash(battler)
        battler.pbHeldItemTriggerCheck(berry)
      elsif state == :waiting
        battler.instance_variable_set(:@cudchew_state, :ready)
      end
    }
  )
end

#===============================================================================
# CURIOUS MEDICINE
# When the holder switches in, it resets all stat stage changes on its ALLIES
# to zero. The holder itself and all foes are unaffected.
#
# Handler: AbilityOnSwitchIn.
# Uses eachAlly to iterate allies; resets stages hash in-place.
# Only shows the message if at least one ally had a non-zero stage.
#
# 3v3 / 2v2 co-op: eachAlly yields all unfainted allies — works for any size.
# Type Infusion: switch-in ability — no interaction with outgoing moves.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:CURIOUSMEDICINE,
    proc { |ability, battler, battle|
      affected = false
      battler.eachAlly do |b|
        next unless b.stages.any? { |_stat, val| val != 0 }
        b.stages.each_key { |stat| b.stages[stat] = 0 }
        affected = true
      end
      next unless affected
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1} reset its allies' stat changes!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    }
  )
end

#===============================================================================
# DARK AURA  (also covers FAIRY AURA and AURA BREAK)
# Dark Aura: boosts Dark-type moves by 4/3x for all Pokémon on the field.
# Fairy Aura: same for Fairy-type moves.
# Aura Break: reverses both auras to 2/3x instead of 4/3x.
#
# BASE ENGINE ALREADY HANDLES ALL THREE — no handlers needed here.
#   AbilityOnSwitchIn for :DARKAURA, :FAIRYAURA, :AURABREAK are in
#   003_BattleHandlers_Abilities.rb (announcements, no species lock).
#   The damage multiplier is in pbCalcDamageMultipliers
#   (002_Move/003_Move_Usage_Calculations.rb:273) via pbCheckGlobalAbility,
#   which checks all battlers by symbol — no species lock.
#   Registering all three in 005_Abilities.rb is sufficient.
#
# Type Infusion: field-wide damage boost — no special interaction needed.
#===============================================================================

#===============================================================================
# DAUNTLESS SHIELD
# When the holder enters battle, its Defense is raised by 1 stage.
# Paired with Intrepid Sword (raises Attack) — same pattern, different stat.
#
# pbRaiseStatStageByAbility handles the ability splash, the can-raise check
# (respects Clear Body, Full Incense, etc.), and the stat-change message.
#
# Type Infusion: switch-in stat boost — no interaction with outgoing moves.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:DAUNTLESSSHIELD,
    proc { |ability, battler, battle|
      battler.pbRaiseStatStageByAbility(:DEFENSE, 1, battler,
                                        GameData::Ability.get(ability).real_name)
    }
  )
end

#===============================================================================
# DEFEATIST
# When the holder's HP drops to 50% or below, its offensive damage is halved.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   DamageCalcUserAbility for :DEFEATIST in 003_BattleHandlers_Abilities.rb:894
#   halves :attack_multiplier when user.hp <= user.totalhp / 2.
#   No species lock — works for any holder.
#   Registering :DEFEATIST in 005_Abilities.rb is sufficient.
#
# Type Infusion: damage-calc ability — no interaction with type assignment.
#===============================================================================

#===============================================================================
# DELTA STREAM
# When the holder enters battle, it summons Strong Winds weather.
# Strong Winds reduces moves normally super effective against Flying to neutral.
# The weather ends when no Pokémon with Delta Stream remains on the field.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   AbilityOnSwitchIn for :DELTASTREAM in 003_BattleHandlers_Abilities.rb:2130
#   calls pbBattleWeatherAbility(:StrongWinds, ...) — no species lock.
#   Strong Winds type-effectiveness reduction is in 003_Move_Usage_Calculations.rb:48.
#   End-of-weather cleanup (pbEndPrimordialWeather) checks pbCheckGlobalAbility
#   by symbol — no species lock.
#   Registering :DELTASTREAM in 005_Abilities.rb is sufficient.
#
# Also covers DESOLATE LAND (:DESOLATELAND, Harsh Sun) and PRIMORDIAL SEA
# (:PRIMORDIALSEA, Heavy Rain) — identical base-engine pattern.
#
# Type Infusion: weather-setting ability — no interaction with outgoing moves.
#===============================================================================

#===============================================================================
# DESOLATE LAND
# When the holder enters battle, it summons Harsh Sun (Extremely Harsh Sunlight).
# Harsh Sun powers up Fire moves, nullifies Water moves, and cannot be replaced
# by regular weather moves (e.g. Rain Dance, Sandstorm).
# The weather ends when no Pokémon with Desolate Land remains on the field.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   AbilityOnSwitchIn for :DESOLATELAND in 003_BattleHandlers_Abilities.rb:2136
#   calls pbBattleWeatherAbility(:HarshSun, ...) — no species lock.
#   Harsh Sun move nullification and fire boost are in damage/weather calculations
#   checked via pbCheckGlobalAbility by symbol — no species lock.
#   See also: DELTA STREAM note above for the full primal-weather pattern.
#   Registering :DESOLATELAND in 005_Abilities.rb is sufficient.
#
# Type Infusion: weather-setting ability — no interaction with outgoing moves.
#===============================================================================

#===============================================================================
# DRAGON'S MAW
# Powers up Dragon-type moves by 1.5x.
# Identical pattern to Steelworker (:STEEL) and Transistor (:ELECTRIC).
#
# Uses :attack_multiplier (applies before crit, after base power calculation),
# matching how all single-type-boost abilities work in this engine.
#
# Type Infusion: Dragon-type boost — if the holder has Dragon type, STAB Dragon
# moves also get the Family type infusion. Dragon's Maw multiplier stacks
# multiplicatively with the infused type's effectiveness on the target.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:DRAGONSMAW,
    proc { |ability, user, target, move, mults, baseDmg, type|
      mults[:attack_multiplier] *= 1.5 if type == :DRAGON
    }
  )
end

#===============================================================================
# EARTH EATER
# The holder is immune to Ground-type moves. When hit by one, it restores 25%
# of its max HP instead of taking damage.
# Identical pattern to Water Absorb (:WATER) and Volt Absorb (:ELECTRIC).
#
# pbBattleMoveImmunityHealAbility handles the immunity check, HP restoration,
# ability splash, and message in one call.
# The existing Levitate/airborne? ground immunity is a SEPARATE check that fires
# earlier (in pbMoveFailedAgainstTarget). Earth Eater fires via
# MoveImmunityTargetAbility which runs after airborne? — both can coexist.
#
# Type Infusion: immunity/heal ability — no interaction with outgoing moves.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::MoveImmunityTargetAbility)
  BattleHandlers::MoveImmunityTargetAbility.add(:EARTHEATER,
    proc { |ability, user, target, move, type, battle|
      next pbBattleMoveImmunityHealAbility(user, target, move, type, :GROUND, battle)
    }
  )
end

#===============================================================================
# ELECTRIC SURGE  (also covers GRASSY SURGE, MISTY SURGE, PSYCHIC SURGE)
# When the holder enters battle, it sets the corresponding terrain:
#   Electric Surge  → Electric Terrain
#   Grassy Surge    → Grassy Terrain
#   Misty Surge     → Misty Terrain
#   Psychic Surge   → Psychic Terrain
#
# BASE ENGINE ALREADY HANDLES ALL FOUR — no handlers needed here.
#   AbilityOnSwitchIn for :ELECTRICSURGE (line 2166), :GRASSYSURGE (2246),
#   :MISTYSURGE (2285), and :PSYCHICSURGE (2316) in 003_BattleHandlers_Abilities.rb
#   all call pbStartTerrain — no species lock on any of them.
#   Terrain effects on damage, immunity, and healing are in move calculations
#   checked by battle.field.terrain symbol — no species lock.
#   Registering each in 005_Abilities.rb is sufficient.
#
# Type Infusion: terrain-setting ability — no interaction with outgoing moves.
#===============================================================================

#===============================================================================
# ELECTROMORPHOSIS
# When the holder is hit by a damaging move, it becomes Charged.
# While Charged, the next Electric-type move used by the holder deals 2x damage.
#
# Handler: TargetAbilityOnHit — fires after the holder takes a hit.
# Sets PBEffects::Charge to 2, which the existing Charge infrastructure handles:
#   - 003_Move_Usage_Calculations.rb:327: doubles Electric damage when Charge > 0
#   - 007_Battler_UseMove.rb:119: clears Charge to 0 after an Electric move is used
#   - 012_Battle_Phase_EndOfRound.rb:648: decrements Charge by 1 each end-of-round
# Triggering again while already Charged resets the counter to 2 (refreshes).
#
# Type Infusion: Electric STAB moves that consume Charge will also get the
# Family type infusion applied multiplicatively. No special handling needed.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.add(:ELECTROMORPHOSIS,
    proc { |ability, user, target, move, battle|
      next unless move.damagingMove?
      target.effects[PBEffects::Charge] = 2
      battle.pbShowAbilitySplash(target)
      battle.pbDisplay(_INTL("{1} became charged up!", target.pbThis))
      battle.pbHideAbilitySplash(target)
    }
  )
end

#===============================================================================
# EMBODY ASPECT ONLY GRASS REGISTERED
# When the holder switches in, it raises one stat by 1 stage based on its type1:
#   Grass (Teal Mask)        → Speed
#   Water (Wellspring Mask)  → Special Defense
#   Fire  (Hearthflame Mask) → Attack
#   Rock  (Cornerstone Mask) → Defense
#   Any other type           → Speed (base-form default)
#
# Only one Ogerpon form is registered in 001_Registration.rb (Grass / Teal Mask).
# The mapping covers fused Pokémon that might inherit this ability with other types.
#
# pbRaiseStatStageByAbility handles splash, can-raise guard, and message.
#
# Type Infusion: switch-in stat boost — no interaction with outgoing moves.
#===============================================================================

NPT_EMBODY_ASPECT_STAT = {
  :GRASS => :SPEED,
  :WATER => :SPECIAL_DEFENSE,
  :FIRE  => :ATTACK,
  :ROCK  => :DEFENSE
}

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:EMBODYASPECT,
    proc { |ability, battler, battle|
      stat = NPT_EMBODY_ASPECT_STAT[battler.type1] || :SPEED
      battler.pbRaiseStatStageByAbility(stat, 1, battler,
                                        GameData::Ability.get(ability).real_name)
    }
  )
end

#===============================================================================
# FAIRY AURA
# Boosts the power of Fairy-type moves by 4/3x for all Pokémon on the field.
# Reversed to 2/3x if Aura Break is also active.
#
# BASE ENGINE ALREADY HANDLES THIS — see DARK AURA note above.
#   AbilityOnSwitchIn for :FAIRYAURA in 003_BattleHandlers_Abilities.rb:2175.
#   Damage multiplier in pbCalcDamageMultipliers via pbCheckGlobalAbility.
#   No species lock. Registering :FAIRYAURA in 005_Abilities.rb is sufficient.
#===============================================================================

#===============================================================================
# FLOWER GIFT
# In Sun / Harsh Sun weather:
#   - Raises the holder's physical Attack by 1.5x (DamageCalcUserAbility:916)
#   - Raises an ally's physical Attack by 1.5x (DamageCalcUserAllyAbility:1122)
#   - Raises the holder's Special Defense by 1.5x (DamageCalcTargetAbility:1150)
#   - Raises an ally's Special Defense by 1.5x (DamageCalcTargetAllyAbility:1235)
# Also triggers a form change on Cherrim (003_Battler_ChangeSelf.rb:198).
#
# BASE ENGINE ALREADY HANDLES ALL OF THIS — no handler needed here.
#   All four DamageCalc handlers use pure symbol checks — no species lock.
#   Form change in pbUpdate checks hasActiveAbility?(:FLOWERGIFT) by symbol.
#   Registering :FLOWERGIFT in 005_Abilities.rb is sufficient.
#   Non-Cherrim holders will get the Attack/Sp. Def boosts but no form change.
#
# Type Infusion: weather-conditional damage boost — no interaction with type.
#===============================================================================

#===============================================================================
# FLOWER VEIL
# Prevents Grass-type Pokémon on the holder's side from having stats lowered or
# being inflicted with status conditions by opponents.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   Four symbol-based handlers in 003_BattleHandlers_Abilities.rb, all gated on
#   pbHasType?(:GRASS) — no species lock:
#     StatusImmunityAbility:128      — protects the holder if Grass-type
#     StatusImmunityAllyAbility:194  — protects allies that are Grass-type
#     StatLossImmunityAbility:397    — prevents stat drops on Grass-type holder
#     StatLossImmunityAllyAbility:470 — prevents stat drops on Grass-type allies
#   Registering :FLOWERVEIL in 005_Abilities.rb is sufficient.
#   Any holder (including fusions) with a Grass type in type1/type2 benefits.
#
# Type Infusion: status/stat-immunity ability — no interaction with outgoing moves.
#===============================================================================

#===============================================================================
# FORECAST
# The holder's type changes to match the weather:
#   Normal → clear weather (no special weather)
#   Fire   → harsh sunlight / Sun
#   Water  → rain / Heavy Rain
#   Ice    → hail
# The type reverts to Normal when weather ends or the ability is suppressed.
#
# BASE ENGINE PARTIALLY HANDLES THIS — species-locked to isSpecies?(:CASTFORM).
#   pbCheckFormOnWeatherChange in 003_Battler_ChangeSelf.rb:179 calls
#   pbChangeForm(1/2/3,...) to update the battler, then pbUpdate(true) reads
#   @pokemon.type1 to set the battler's @type1.  However, Pokemon#form= is a
#   NO-OP in this engine (commented out at 014_Pokemon/001_Pokemon.rb:784), so
#   @pokemon.type1 always returns species_data.type1 (Normal for our single-form
#   Castform).  The visual form change fires, but the type change silently fails.
#
#   We alias pbCheckFormOnWeatherChange to call pbChangeTypes directly after the
#   base engine code, overriding @type1/@type2 regardless of form-change outcome.
#   For non-Castform FORECAST holders (fusions with FORECAST inherited), the base
#   engine block is skipped entirely, so our alias is the sole handler — it also
#   shows a splash + message in that case.
#
# Trigger points (all routed through pbCheckFormOnWeatherChange):
#   • Switch-in        : pbCheckForm(false) → pbCheckFormOnWeatherChange
#   • Weather change   : pbStartWeather → eachBattler { |b| b.pbCheckFormOnWeatherChange }
#   • Ability lost     : pbOnAbilityChanged → pbCheckFormOnWeatherChange (reverts form)
#   • End-of-round weather tick: 012_Battle_Phase_EndOfRound.rb:56
#
# Type Infusion: weather-conditional type override — critical for Weather Ball
#   type calculation (move already reads pbWeather directly, so no extra patch).
#===============================================================================
class PokeBattle_Battler
  alias npt_forecast_pbCheckFormOnWeatherChange pbCheckFormOnWeatherChange
  def pbCheckFormOnWeatherChange
    npt_forecast_pbCheckFormOnWeatherChange   # base engine (Castform form anim)
    return if fainted? || @effects[PBEffects::Transform]
    return unless hasActiveAbility?(:FORECAST)
    newType = case @battle.pbWeather
              when :Sun, :HarshSun   then :FIRE
              when :Rain, :HeavyRain then :WATER
              when :Hail             then :ICE
              else                        :NORMAL
              end
    return if @type1 == newType && @type2 == newType
    pbChangeTypes(newType)
    # Non-Castform FORECAST holders (e.g. fusions) need an explicit message;
    # Castform already received "X transformed!" from pbChangeForm above.
    unless isSpecies?(:CASTFORM)
      typeName = GameData::Type.get(newType).name
      @battle.pbShowAbilitySplash(self)
      @battle.pbDisplay(_INTL("{1} transformed into the {2} type!", pbThis, typeName))
      @battle.pbHideAbilitySplash(self)
    end
  end
end

#===============================================================================
# FULL METAL BODY
# Prevents the holder's stat stages from being lowered by opponents' moves or
# abilities.  Unlike Clear Body / White Smoke, this protection cannot be
# bypassed by Mold Breaker, Turboblaze, or Teravolt.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   StatLossImmunityAbilityNonIgnorable handler in
#   003_BattleHandlers_Abilities.rb:451 — pure symbol check, no species lock.
#   Registering :FULLMETALBODY in 005_Abilities.rb is sufficient.
#
# Contrast with CLEARBODY / WHITESMOKE (StatLossImmunityAbility:380/395) which
# share the same effect but CAN be bypassed by Mold Breaker-class abilities.
#===============================================================================

#===============================================================================
# FUR COAT
# Halves damage taken from physical moves by doubling the effective Defense stat
# during damage calculation.  Also applies to Psyshock / Psystrike (function
# "122"), which deal physical damage based on the target's Defense.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   DamageCalcTargetAbility handler in 003_BattleHandlers_Abilities.rb:1165.
#   Pure symbol check — no species lock.
#   Registering :FURCOAT in 005_Abilities.rb is sufficient.
#===============================================================================

#===============================================================================
# GALVANIZE
# Normal-type moves used by the holder become Electric-type and gain a 1.2×
# power boost.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   Two pure symbol-based handlers, no species lock:
#     MoveBaseTypeModifierAbility:722 — converts Normal → Electric, sets
#       move.powerBoost = true.
#     DamageCalcUserAbility:874 — copied from :AERILATE; multiplies
#       mults[:base_damage_multiplier] × 1.2 when move.powerBoost is set.
#   Registering :GALVANIZE in 005_Abilities.rb is sufficient.
#
#   Same two-handler pattern used by AERILATE (→Flying), PIXILATE (→Fairy),
#   and REFRIGERATE (→Ice).
#===============================================================================

#===============================================================================
# GOOD AS GOLD
# The holder is immune to all status moves used by other Pokémon (opponents AND
# allies in doubles).  Self-targeting status moves are not blocked.
#
# BASE ENGINE DOES NOT HANDLE THIS — full implementation below.
#   No existing handler covers a blanket "status move" category immunity.
#   Uses MoveImmunityTargetAbility — the same bucket as Bulletproof/Flash Fire.
#   Signature: |ability, user, target, move, type, battle|
#
# Design notes:
#   • statusMove? returns true when move.category == 2 (all Status-category moves).
#   • user.index == target.index guards against blocking self-targeted status
#     moves (e.g. a Pokémon using Swords Dance on itself via Sleep Talk — rare,
#     but correct to allow).
#   • Does NOT check user.opposes? — the game description says "used by other
#     Pokémon", which includes ally moves (Helping Hand, Decorate, etc.).
#===============================================================================
if defined?(BattleHandlers) && defined?(BattleHandlers::MoveImmunityTargetAbility)
  BattleHandlers::MoveImmunityTargetAbility.add(:GOODASGOLD,
    proc { |ability, user, target, move, type, battle|
      next false if user.index == target.index
      next false if !move.statusMove?
      battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} made {3} ineffective!",
                               target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
      next true
    }
  )
end

#===============================================================================
# GORILLA TACTICS
# Boosts the holder's Attack by 1.5× but restricts it to using only the first
# move it selects each time it enters battle (identical to Choice Band locking).
#
# BASE ENGINE DOES NOT HANDLE THIS — full implementation below.
#
# Implementation uses two aliases on PokeBattle_Battler:
#
# 1. DamageCalcUserAbility — 1.5× attack_multiplier for physical moves.
#
# 2. pbEndTurn alias — after each turn, if GORILLATACTICS is active and no
#    lock is stored yet, record @npt_gorilla_move = the move just used.
#    The engine's existing ChoiceBand locking (PBEffects::ChoiceBand) is
#    item-specific and clears itself immediately when no Choice item is held,
#    so we must track the lock in a separate instance variable.
#
# 3. pbCanChooseMove? alias — before a move is selected/used, if
#    @npt_gorilla_move is set and GORILLATACTICS is active, block any move
#    other than the locked one (same message format as Choice Band).
#
# 4. pbInitEffects alias — clears @npt_gorilla_move on every switch-in so
#    the lock resets when the Pokémon leaves and re-enters battle (matching
#    real-game behaviour and preventing slot-reuse pollution).
#
# Edge cases handled:
#   • Ability suppressed mid-battle (Gastro Acid): pbCanChooseMove? checks
#     hasActiveAbility?(:GORILLATACTICS) → false → lock not enforced.
#   • Locked move becomes unavailable (Disable/Encore PP drain): the lock is
#     cleared so the battler can choose freely, same as Choice Band.
#   • Baton Pass: pbInitEffects(batonPass=true) still clears the lock —
#     intentional, the new Pokémon is not constrained.
#===============================================================================
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:GORILLATACTICS,
    proc { |ability, user, target, move, mults, baseDmg, type|
      mults[:attack_multiplier] *= 1.5 if move.physicalMove?
    }
  )
end

class PokeBattle_Battler
  alias npt_gorilla_pbInitEffects pbInitEffects
  def pbInitEffects(batonPass)
    npt_gorilla_pbInitEffects(batonPass)
    @npt_gorilla_move = nil
  end

  alias npt_gorilla_pbEndTurn pbEndTurn
  def pbEndTurn(choice)
    npt_gorilla_pbEndTurn(choice)
    return unless hasActiveAbility?(:GORILLATACTICS)
    return if @npt_gorilla_move   # already locked
    if @lastMoveUsed && pbHasMove?(@lastMoveUsed)
      @npt_gorilla_move = @lastMoveUsed
    elsif @lastRegularMoveUsed && pbHasMove?(@lastRegularMoveUsed)
      @npt_gorilla_move = @lastRegularMoveUsed
    end
  end

  alias npt_gorilla_pbCanChooseMove? pbCanChooseMove?
  def pbCanChooseMove?(move, commandPhase, showMessages = true, specialUsage = false)
    if @npt_gorilla_move && hasActiveAbility?(:GORILLATACTICS)
      if pbHasMove?(@npt_gorilla_move)
        if move.id != @npt_gorilla_move
          if showMessages
            msg = _INTL("{1} allows the use of only {2}!",
                        abilityName,
                        GameData::Move.get(@npt_gorilla_move).name)
            commandPhase ? @battle.pbDisplayPaused(msg) : @battle.pbDisplay(msg)
          end
          return false
        end
      else
        @npt_gorilla_move = nil   # locked move no longer available — unlock
      end
    end
    npt_gorilla_pbCanChooseMove?(move, commandPhase, showMessages, specialUsage)
  end
end

#===============================================================================
# GRASS PELT
# Raises the holder's Defense by 1.5× when Grassy Terrain is active.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   DamageCalcTargetAbility handler in 003_BattleHandlers_Abilities.rb:1171.
#   Checks battle.field.terrain == :Grassy — pure symbol check, no species lock.
#   Registering :GRASSPELT in 005_Abilities.rb is sufficient.
#===============================================================================

#===============================================================================
# GRASSY SURGE
# Sets Grassy Terrain when the holder enters battle.
#
# BASE ENGINE ALREADY HANDLES THIS — no handler needed here.
#   AbilityOnSwitchIn handler in 003_BattleHandlers_Abilities.rb:2246 calls
#   battle.pbStartTerrain(battler, :Grassy) — pure symbol check, no species lock.
#   Registering :GRASSYSURGE in 005_Abilities.rb is sufficient.
#   See ELECTRIC SURGE note above for the full four-terrain-surge pattern.
#===============================================================================

#===============================================================================
# GRIM NEIGH
# When the holder knocks out a Pokémon, raises its Sp. Atk by 1 stage.
# Identical to Moxie but for Special Attack.
#
# Uses UserAbilityEndOfMove (same as Moxie) — fires after a damaging move,
# counts targets that fainted from it (damageState.fainted), raises stat once
# per KO. Handles multi-target moves correctly (e.g. Surf knocking out 2).
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::UserAbilityEndOfMove)
  BattleHandlers::UserAbilityEndOfMove.add(:GRIMNEIGH,
    proc { |ability, user, targets, move, battle|
      next if battle.pbAllFainted?(user.idxOpposingSide)
      numFainted = 0
      targets.each { |b| numFainted += 1 if b.damageState.fainted }
      next if numFainted == 0 || !user.pbCanRaiseStatStage?(:SPECIAL_ATTACK, user)
      user.pbRaiseStatStageByAbility(:SPECIAL_ATTACK, numFainted, user,
                                     GameData::Ability.get(ability).real_name)
    }
  )
end

#===============================================================================
# GUARD DOG
# 1. Intimidate immunity: when the holder would have its Attack lowered by
#    Intimidate, it raises its Attack by 1 stage instead.
# 2. Force-switch immunity: prevents Roar/Whirlwind (0EB), Dragon Tail/Circle
#    Throw (0EC), Red Card, and Eject Button from forcing the holder out.
#    The force-switch block can be bypassed by Mold Breaker; the Intimidate
#    boost cannot (it is an ability reaction, not a move target effect).
#===============================================================================

# ── Part 1: Intimidate → Attack boost ─────────────────────────────────────────
class PokeBattle_Battler
  alias npt_guarddog_pbLowerAttackStatStageIntimidate pbLowerAttackStatStageIntimidate
  def pbLowerAttackStatStageIntimidate(user)
    if hasActiveAbility?(:GUARDDOG)
      return false if fainted?
      pbRaiseStatStageByAbility(:ATTACK, 1, self) if pbCanRaiseStatStage?(:ATTACK, self)
      return false   # block the Intimidate drop
    end
    npt_guarddog_pbLowerAttackStatStageIntimidate(user)
  end
end

# ── Part 2a: Roar / Whirlwind (0EB) — move fails against Guard Dog ────────────
class PokeBattle_Move_0EB
  alias npt_guarddog_0eb_pbFailsAgainstTarget? pbFailsAgainstTarget?
  def pbFailsAgainstTarget?(user, target)
    if target.hasActiveAbility?(:GUARDDOG) && !@battle.moldBreaker
      @battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        @battle.pbDisplay(_INTL("{1} anchors itself!", target.pbThis))
      else
        @battle.pbDisplay(_INTL("{1} anchors itself with {2}!", target.pbThis, target.abilityName))
      end
      @battle.pbHideAbilitySplash(target)
      return true
    end
    npt_guarddog_0eb_pbFailsAgainstTarget?(user, target)
  end
end

# ── Part 2b: Dragon Tail / Circle Throw (0EC) — damage lands, switch blocked ──
# NOTE: This redefines pbSwitchOutTargetsEffect rather than aliasing because the
# GUARDDOG check must be injected inside the targets loop alongside SUCTIONCUPS.
# The method is short and stable; keep in sync if the base engine changes.
class PokeBattle_Move_0EC
  def pbSwitchOutTargetsEffect(user, targets, numHits, switchedBattlers)
    return if @battle.wildBattle?
    return if user.fainted? || numHits == 0
    roarSwitched = []
    targets.each do |b|
      next if b.fainted? || b.damageState.unaffected || b.damageState.substitute
      next if switchedBattlers.include?(b.index)
      next if b.effects[PBEffects::Ingrain]
      next if b.hasActiveAbility?(:SUCTIONCUPS) && !@battle.moldBreaker
      next if b.hasActiveAbility?(:GUARDDOG)    && !@battle.moldBreaker
      newPkmn = @battle.pbGetReplacementPokemonIndex(b.index, true)   # Random
      next if newPkmn < 0
      @battle.pbRecallAndReplace(b.index, newPkmn, true)
      @battle.pbDisplay(_INTL("{1} was dragged out!", b.pbThis))
      @battle.pbClearChoice(b.index)
      switchedBattlers.push(b.index)
      roarSwitched.push(b.index)
    end
    if roarSwitched.length > 0
      @battle.moldBreaker = false if roarSwitched.include?(user.index)
      @battle.pbPriority(true).each do |b|
        b.pbEffectsOnSwitchIn(true) if roarSwitched.include?(b.index)
      end
    end
  end
end

# ── Part 2c: Eject Button — Guard Dog holder is not switched out ───────────────
# Re-declares the handler (BattleHandlers.add overwrites by key) so we can
# prepend the Guard Dog guard before the original effect fires.
if defined?(BattleHandlers) && defined?(BattleHandlers::TargetItemAfterMoveUse)
  BattleHandlers::TargetItemAfterMoveUse.add(:EJECTBUTTON,
    proc { |item, battler, user, move, switched, battle|
      next if battler.hasActiveAbility?(:GUARDDOG)   # block; item not consumed
      next if battle.pbAllFainted?(battler.idxOpposingSide)
      next if !battle.pbCanChooseNonActive?(battler.index)
      battle.pbCommonAnimation("UseItem", battler)
      battle.pbDisplay(_INTL("{1} is switched out with the {2}!", battler.pbThis, battler.itemName))
      battler.pbConsumeItem(true, false)
      newPkmn = battle.pbGetReplacementPokemonIndex(battler.index)   # Owner chooses
      next if newPkmn < 0
      battle.pbRecallAndReplace(battler.index, newPkmn)
      battle.pbClearChoice(battler.index)
      switched.push(battler.index)
    }
  )
end

# ── Part 2d: Red Card — Guard Dog attacker is not forced out ──────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::TargetItemAfterMoveUse)
  BattleHandlers::TargetItemAfterMoveUse.add(:REDCARD,
    proc { |item, battler, user, move, switched, battle|
      next if user.hasActiveAbility?(:GUARDDOG)   # block; item not consumed
      next if user.fainted? || switched.include?(user.index)
      newPkmn = battle.pbGetReplacementPokemonIndex(user.index, true)   # Random
      next if newPkmn < 0
      battle.pbCommonAnimation("UseItem", battler)
      battle.pbDisplay(_INTL("{1} held up its {2} against {3}!",
                             battler.pbThis, battler.itemName, user.pbThis(true)))
      battler.pbConsumeItem
      battle.pbRecallAndReplace(user.index, newPkmn, true)
      battle.pbDisplay(_INTL("{1} was dragged out!", user.pbThis))
      battle.pbClearChoice(user.index)
      switched.push(user.index)
    }
  )
end

#===============================================================================
# GULP MISSILE
# Using Surf sets state 1 (Gulping — Pikachu prey).
# Using Dive (turn 2, when surfacing) sets state 2 (Gorging — Arrokuda prey).
# When the holder takes a damaging hit while holding prey, it fires the missile:
#   State 1 (Gulping): deals 1/4 holder's max HP to attacker + paralyze
#   State 2 (Gorging): deals 1/4 holder's max HP to attacker + lower Def -1
# Prey is consumed on fire. State resets on switch-out (pbInitEffects).
#
# Implementation notes:
#   - form= is a NO-OP in this engine; Gulping/Gorging tracked as @npt_gulp_state
#   - Dive charging turn is detected via inTwoTurnAttack?("0CB"); state is only
#     set on turn 2 when the holder surfaces and attacks
#   - nil.to_i == 0, so npt_gulp_state is nil-safe if ability is gained mid-battle
#===============================================================================

class PokeBattle_Battler
  def npt_gulp_state;    @npt_gulp_state.to_i; end   # nil-safe read
  def npt_gulp_state=(v); @npt_gulp_state = v; end

  alias npt_gulpmissile_pbInitEffects pbInitEffects
  def pbInitEffects(batonPass)
    npt_gulpmissile_pbInitEffects(batonPass)
    @npt_gulp_state = 0
  end

  alias npt_gulpmissile_pbEndTurn pbEndTurn
  def pbEndTurn(choice)
    npt_gulpmissile_pbEndTurn(choice)
    return unless hasActiveAbility?(:GULPMISSILE)
    if @lastMoveUsed == :SURF
      @npt_gulp_state = 1              # caught Pikachu  → Gulping
    elsif @lastMoveUsed == :DIVE && !inTwoTurnAttack?("0CB")
      @npt_gulp_state = 2              # caught Arrokuda → Gorging
    end
  end
end

if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.add(:GULPMISSILE,
    proc { |ability, user, target, move, battle|
      next if target.npt_gulp_state == 0
      next unless user.takesIndirectDamage?
      state = target.npt_gulp_state
      target.npt_gulp_state = 0        # prey consumed — reset before effects
      battle.pbShowAbilitySplash(target)
      battle.scene.pbDamageAnimation(user)
      user.pbReduceHP((target.totalhp / 4.0).round, false)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} spit out its prey!", target.pbThis))
      else
        battle.pbDisplay(_INTL("{1}'s {2} spat its prey at {3}!",
                               target.pbThis, target.abilityName, user.pbThis(true)))
      end
      if state == 1   # Gulping — Pikachu prey → paralyze
        user.pbParalyze(target) if user.pbCanInflictStatus?(:PARALYSIS, target, false)
      else            # Gorging — Arrokuda prey → lower Defense
        user.pbLowerStatStageByAbility(:DEFENSE, 1, target, false)
      end
      battle.pbHideAbilitySplash(target)
    }
  )
end


#===============================================================================
# HADRON ENGINE
# Sets Electric Terrain on switch-in (same as Electric Surge).
# While Electric Terrain is active and the holder is grounded, boosts the
# holder's Sp. Atk by 4/3 (≈1.333×) on special moves — a passive multiplier,
# not a stat stage, so it stacks independently with stage changes.
#===============================================================================

# ── Part 1: Set Electric Terrain on switch-in ─────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:HADRONENGINE,
    proc { |ability, battler, battle|
      next if battle.field.terrain == :Electric
      battle.pbShowAbilitySplash(battler)
      battle.pbStartTerrain(battler, :Electric)
      # NOTE: pbStartTerrain hides the ability splash internally.
    }
  )
end

# ── Part 2: Sp. Atk ×4/3 while Electric Terrain is active and grounded ────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:HADRONENGINE,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.specialMove?
      next unless user.battle.field.terrain == :Electric
      next if user.airborne?
      mults[:attack_multiplier] *= 4.0 / 3
    }
  )
end

#===============================================================================
# HEATPROOF
# Halves damage from Fire-type moves. Halves burn damage each end-of-round.
#
# BASE ENGINE ALREADY HANDLES BOTH — no handler needed here.
#   Fire damage:  DamageCalcTargetAbility in 003_BattleHandlers_Abilities.rb:1179.
#                 Checks type == :FIRE — fires on any move whose final computed
#                 type is Fire, including Type-Infusion-converted moves.
#   Burn damage:  012_Battle_Phase_EndOfRound.rb:403 checks
#                 hasActiveAbility?(:HEATPROOF) — pure symbol check, no species lock.
#   Registering :HEATPROOF in 005_Abilities.rb is sufficient.
#
# Type Infusion: type in DamageCalcTargetAbility is post-conversion (from
#   pbCalcType). If a move is converted to Fire by any ability or infusion,
#   Heatproof halves it automatically — no extra code needed.
# Co-op: Heatproof triggers on any hit to the holder regardless of attacker
#   side (ally or foe). This is the correct behaviour in co-op.
#===============================================================================

#===============================================================================
# HOSPITALITY
# On switch-in, restores 1/4 of one ally's max HP.
# Does nothing in singles (no ally). Respects Heal Block (via canHeal?).
#
# Co-op: eachAlly yields all same-side non-self battlers, so co-op partners
#   receive the heal just like local allies — no special handling needed.
# Type Infusion: no relevance (pure HP restoration, no type interaction).
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:HOSPITALITY,
    proc { |ability, battler, battle|
      battler.eachAlly do |b|
        next unless b.canHeal?
        battle.pbShowAbilitySplash(battler)
        b.pbRecoverHP(b.totalhp / 4)
        if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          battle.pbDisplay(_INTL("{1}'s HP was restored.", b.pbThis))
        else
          battle.pbDisplay(_INTL("{1}'s {2} restored {3}'s HP !",
                                 battler.pbThis, battler.abilityName, b.pbThis(true)))
        end
        battle.pbHideAbilitySplash(battler)
        break   # heal only one ally (Gen 9 behaviour)
      end
    }
  )
end

#===============================================================================
# HUNGER SWITCH
# At the end of every turn, toggles the holder between Full Belly Mode (0) and
# Hangry Mode (1). The Pokémon's types (Electric/Dark) do not change between
# forms. The state is read by Aura Wheel to determine its type:
#   Full Belly (state 0) → Aura Wheel is Electric-type
#   Hangry     (state 1) → Aura Wheel is Dark-type
# Aura Wheel's type-switching is implemented in the move code (004_Moves.rb).
#
# form= is a NO-OP in this engine; state is tracked as @npt_hunger_state.
# Co-op: toggle fires per battler's EOR tick — no special co-op handling needed.
# Type Infusion: no relevance (no type change on the holder itself).
#===============================================================================

class PokeBattle_Battler
  def npt_hunger_state;    @npt_hunger_state.to_i; end   # 0=Full Belly, 1=Hangry
  def npt_hunger_state=(v); @npt_hunger_state = v; end

  alias npt_hungerswitch_pbInitEffects pbInitEffects
  def pbInitEffects(batonPass)
    npt_hungerswitch_pbInitEffects(batonPass)
    @npt_hunger_state = 0   # always start in Full Belly Mode
  end
end

if defined?(BattleHandlers) && defined?(BattleHandlers::EOREffectAbility)
  BattleHandlers::EOREffectAbility.add(:HUNGERSWITCH,
    proc { |ability, battler, battle|
      next if battler.fainted?
      battler.npt_hunger_state = (battler.npt_hunger_state == 0) ? 1 : 0
      battle.pbShowAbilitySplash(battler)
      if battler.npt_hunger_state == 1
        battle.pbDisplay(_INTL("{1} became Hangry!", battler.pbThis))
      else
        battle.pbDisplay(_INTL("{1} filled its belly!", battler.pbThis))
      end
      battle.pbHideAbilitySplash(battler)
    }
  )
end

#===============================================================================
# ICE FACE
# The holder's icy head blocks ONE physical damaging hit (0 damage, no HP lost).
# After breaking, the ice is restored when it hails (on switch-in or EOR).
# Can be bypassed by Mold Breaker.
#
# Implementation:
#   @npt_ice_face_intact: true = ice intact, false = broken ("Noice Face")
#   Reuses damageState.disguise so all downstream logic fires automatically:
#     pbCalcDamage → calcDamage = 1, pbReduceDamage → 0 HP lost,
#     pbEffectivenessMessage/pbHitEffectivenessMessages → suppressed.
#   pbEndureKOMessage alias distinguishes ICEFACE from Mimikyu Disguise by
#   checking hasActiveAbility?(:ICEFACE) before calling the original.
#
# Co-op: blocks physical hits from any attacker (ally or foe) — correct.
# Type Infusion: Ice Face checks move category (physical), not type — correct.
#===============================================================================

class PokeBattle_Battler
  def npt_ice_face_intact;     @npt_ice_face_intact.nil? ? true : @npt_ice_face_intact; end
  def npt_ice_face_intact=(v); @npt_ice_face_intact = v; end

  alias npt_iceface_pbInitEffects pbInitEffects
  def pbInitEffects(batonPass)
    npt_iceface_pbInitEffects(batonPass)
    @npt_ice_face_intact = true
  end
end

# ── Physical hit absorption ────────────────────────────────────────────────────
class PokeBattle_Move
  alias npt_iceface_pbCheckDamageAbsorption pbCheckDamageAbsorption
  def pbCheckDamageAbsorption(user, target)
    if !@battle.moldBreaker &&
       target.hasActiveAbility?(:ICEFACE) &&
       target.npt_ice_face_intact &&
       physicalMove?
      target.damageState.disguise = true
      return
    end
    npt_iceface_pbCheckDamageAbsorption(user, target)
  end

  alias npt_iceface_pbEndureKOMessage pbEndureKOMessage
  def pbEndureKOMessage(target)
    if target.damageState.disguise && target.hasActiveAbility?(:ICEFACE)
      @battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        @battle.pbDisplay(_INTL("Its icy face took the hit!"))
      else
        @battle.pbDisplay(_INTL("{1}'s icy face took the hit!", target.pbThis))
      end
      @battle.pbHideAbilitySplash(target)
      target.npt_ice_face_intact = false
      @battle.pbDisplay(_INTL("{1}'s ice face shattered!", target.pbThis))
      return
    end
    npt_iceface_pbEndureKOMessage(target)
  end
end

# ── Ice restoration on switch-in while hailing ─────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:ICEFACE,
    proc { |ability, battler, battle|
      next if battler.npt_ice_face_intact
      next unless battle.pbWeather == :Hail
      battle.pbShowAbilitySplash(battler)
      battler.npt_ice_face_intact = true
      battle.pbDisplay(_INTL("{1} restored its ice face!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    }
  )
end

# ── Ice restoration at end of round while hailing ─────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::EOREffectAbility)
  BattleHandlers::EOREffectAbility.add(:ICEFACE,
    proc { |ability, battler, battle|
      next if battler.fainted? || battler.npt_ice_face_intact
      next unless battle.pbWeather == :Hail
      battle.pbShowAbilitySplash(battler)
      battler.npt_ice_face_intact = true
      battle.pbDisplay(_INTL("{1} restored its ice face!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    }
  )
end
# ────────────────────────────────────────────────────────────────────────────────
# ICE SCALES
# Halves damage taken from special moves. Not suppressible by Mold Breaker.
# Co-op: fires for any attacker regardless of side.
# Type Infusion: move.specialMove? checks category (unaffected by type conversion).
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAbilityNonIgnorable)
  BattleHandlers::DamageCalcTargetAbilityNonIgnorable.add(:ICESCALES,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.specialMove?
      mults[:final_damage_multiplier] *= 0.5
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# INTREPID SWORD
# Raises Attack by 1 stage on switch-in (once per battle, enforced by
# pbRaiseStatStageByAbility — returns false if already at +6 or suppressed).
# Co-op: fires for each holder on their own switch-in.
# Type Infusion: stat boosts are category-neutral.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:INTREPIDSWORD,
    proc { |ability, battler, battle|
      next unless battler.pbCanRaiseStatStage?(:ATTACK, battler)
      battler.pbRaiseStatStageByAbility(:ATTACK, 1, battler,
                                        GameData::Ability.get(ability).real_name)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# LIBERO
# Identical to Protean: changes user's type to match the move before it is used
# (granting STAB). Implemented by aliasing pbUseMove and performing the type
# change before the original method runs. pbHasOtherType? prevents double-firing
# on turn 2 of two-turn moves since the user is already the correct type.
# Co-op: fires for each LIBERO holder on their own turn; no cross-player effect.
# Type Infusion: move.pbCalcType(self) returns post-conversion type, so
# type-infused moves will set the infused type (same as Protean behaviour).
# ────────────────────────────────────────────────────────────────────────────────
class PokeBattle_Battler
  alias npt_libero_pbUseMove pbUseMove
  def pbUseMove(choice, specialUsage = false)
    move = choice[2]
    if move && hasActiveAbility?(:LIBERO) && !move.callsAnotherMove? && !move.snatched
      calcType = move.pbCalcType(self)
      if pbHasOtherType?(calcType) && !GameData::Type.get(calcType).pseudo_type
        @battle.pbShowAbilitySplash(self)
        pbChangeTypes(calcType)
        typeName = GameData::Type.get(calcType).name
        @battle.pbDisplay(_INTL("{1} transformed into the {2} type!", pbThis, typeName))
        @battle.pbHideAbilitySplash(self)
      end
    end
    npt_libero_pbUseMove(choice, specialUsage)
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# LINGERING AROMA
# On contact hit, replaces attacker's ability with Lingering Aroma.
# Mechanically identical to Mummy — handler uses `ability` symbol dynamically,
# so .copy is sufficient.
# Co-op: fires for any attacker regardless of side.
# Type Infusion: contact check is category-based, unaffected by type conversion.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.copy(:MUMMY, :LINGERINGAROMA)
end

# ────────────────────────────────────────────────────────────────────────────────
# LIQUID VOICE
# Already handled by base engine (003_BattleHandlers_Abilities.rb:730).
# MoveBaseTypeModifierAbility converts all sound-based moves to Water-type.
# No powerBoost (unlike -ate abilities). No NPT code needed.
# Co-op/Type Infusion: handled automatically via pbCalcType pipeline.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# LONG REACH
# Already handled by base engine (002_Move_Usage.rb:37).
# pbContactMove?(user) returns false when user has :LONGREACH, suppressing all
# contact-triggered effects (Rough Skin, Static, Mummy, Rocky Helmet, etc.).
# No NPT code needed.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# MEGA LAUNCHER
# Already handled by base engine (003_BattleHandlers_Abilities.rb:952).
# DamageCalcUserAbility multiplies base damage by 1.5 for pulse moves (flag m).
# No NPT code needed.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# MIMICRY
# Changes the holder's type to match the active terrain. Reverts to species
# type when terrain ends.
# Hooks:
#   - AbilityOnSwitchIn: apply on entry (terrain may already be up)
#   - Alias pbStartTerrain: fires immediately when any terrain activates
#   - Alias pbEORTerrain: fires after terrain expires (catches :None revert)
# Co-op: npt_mimicry_updateType iterates all battlers via eachBattler, so all
#   co-op MIMICRY holders are updated at once on terrain change.
# Type Infusion: type change affects the battler's actual types; type-converted
#   moves will use the new type for STAB checks automatically.
# ────────────────────────────────────────────────────────────────────────────────
class PokeBattle_Battler
  def npt_mimicry_updateType
    return unless hasActiveAbility?(:MIMICRY)
    return if fainted?
    terrain = @battle.field.terrain
    newType = case terrain
              when :Electric then :ELECTRIC
              when :Grassy   then :GRASS
              when :Misty    then :FAIRY
              when :Psychic  then :PSYCHIC
              else nil
              end
    if newType
      return if pbHasType?(newType) && @type1 == newType && @type2 == newType
      @battle.pbShowAbilitySplash(self)
      pbChangeTypes(newType)
      typeName = GameData::Type.get(newType).name
      @battle.pbDisplay(_INTL("{1} transformed into the {2} type!", pbThis, typeName))
      @battle.pbHideAbilitySplash(self)
    else
      # Revert to species original types
      origType1 = @pokemon.type1
      origType2 = @pokemon.type2
      return if @type1 == origType1 && @type2 == origType2
      @battle.pbShowAbilitySplash(self)
      @type1 = origType1
      @type2 = origType2
      @effects[PBEffects::Type3] = nil
      @effects[PBEffects::BurnUp] = false
      @effects[PBEffects::Roost]  = false
      @battle.pbDisplay(_INTL("{1} returned to its original type!", pbThis))
      @battle.pbHideAbilitySplash(self)
    end
  end
end

class PokeBattle_Battle
  alias npt_mimicry_pbStartTerrain pbStartTerrain
  def pbStartTerrain(user, newTerrain, fixedDuration = true)
    npt_mimicry_pbStartTerrain(user, newTerrain, fixedDuration)
    eachBattler { |b| b.npt_mimicry_updateType }
  end

  alias npt_mimicry_pbEORTerrain pbEORTerrain
  def pbEORTerrain
    npt_mimicry_pbEORTerrain
    eachBattler { |b| b.npt_mimicry_updateType }
  end
end

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:MIMICRY,
    proc { |ability, battler, battle|
      battler.npt_mimicry_updateType
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# MIND'S EYE
# 1. Accuracy cannot be lowered — copied from Keen Eye.
# 2. Normal- and Fighting-type moves hit Ghost types normally — same as Scrappy,
#    but Scrappy's check is hardcoded in PokeBattle_Move#pbCalcTypeModSingle.
#    We alias that method to add :MINDSEYE alongside :SCRAPPY.
# Co-op: fires for any user regardless of side.
# Type Infusion: Ghost bypass uses the post-conversion moveType, so a
#   type-infused Normal→Fire move would NOT gain the bypass (correct behaviour).
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::StatLossImmunityAbility)
  BattleHandlers::StatLossImmunityAbility.copy(:KEENEYE, :MINDSEYE)
end

class PokeBattle_Move
  alias npt_mindseye_pbCalcTypeModSingle pbCalcTypeModSingle
  def pbCalcTypeModSingle(moveType, defType, user, target)
    ret = npt_mindseye_pbCalcTypeModSingle(moveType, defType, user, target)
    # Mind's Eye: Normal/Fighting bypass Ghost immunity (same as Scrappy)
    if user.hasActiveAbility?(:MINDSEYE) && defType == :GHOST &&
       Effectiveness.ineffective_type?(moveType, defType)
      ret = Effectiveness::NORMAL_EFFECTIVE_ONE
    end
    ret
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# MIRROR ARMOR
# Reflects any externally-caused stat drop back onto the attacker at the same
# stage increment. Mold Breaker bypasses it.
# Implemented by aliasing pbLowerStatStage and pbLowerStatStageByCause — both
# have a `user` parameter — before the actual stage change is applied.
# StatLossImmunityAbility is NOT used because its handler receives no `user`.
# Co-op: fires for any attacker regardless of side.
# Type Infusion: stat drops are category-neutral.
# ────────────────────────────────────────────────────────────────────────────────
class PokeBattle_Battler
  # Shared reflection helper (not public API, prefixed to avoid collisions)
  def npt_mirrorarmor_reflect(stat, increment, user, showAnim)
    @battle.pbShowAbilitySplash(self)
    if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      @battle.pbDisplay(_INTL("{1}'s stat changes were reflected!", pbThis))
    else
      @battle.pbDisplay(_INTL("{1}'s {2} reflected the stat change!", pbThis, abilityName))
    end
    @battle.pbHideAbilitySplash(self)
    user.pbLowerStatStage(stat, increment, self, showAnim) if user.pbCanLowerStatStage?(stat, self)
  end

  def npt_mirrorarmor_active?(user)
    return hasActiveAbility?(:MIRRORARMOR) && !@battle.moldBreaker &&
           user && user.index != @index && abilityActive? && !fainted?
  end

  alias npt_mirrorarmor_pbLowerStatStage pbLowerStatStage
  def pbLowerStatStage(stat, increment, user, showAnim = true, ignoreContrary = false)
    if npt_mirrorarmor_active?(user)
      npt_mirrorarmor_reflect(stat, increment, user, showAnim)
      return false
    end
    npt_mirrorarmor_pbLowerStatStage(stat, increment, user, showAnim, ignoreContrary)
  end

  alias npt_mirrorarmor_pbLowerStatStageByCause pbLowerStatStageByCause
  def pbLowerStatStageByCause(stat, increment, user, cause, showAnim = true, ignoreContrary = false)
    if npt_mirrorarmor_active?(user)
      npt_mirrorarmor_reflect(stat, increment, user, showAnim)
      return false
    end
    npt_mirrorarmor_pbLowerStatStageByCause(stat, increment, user, cause, showAnim, ignoreContrary)
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# MYCELIUM MIGHT
# 1. Status moves always go last within their priority bracket (like Stall).
# 2. Status moves bypass the target's ability (like Mold Breaker).
#
# Effect 1: PriorityBracketChangeAbility — checks move via battle.choices.
# Effect 2: Override hasMoldBreaker? via a per-turn flag set in a pbUseMove
#   wrapper. battle.moldBreaker is set at line 258 of 007_Battler_UseMove.rb via
#   hasMoldBreaker?, so the flag causes moldBreaker=true for the entire move.
#   The ensure block guarantees cleanup even if the move raises an exception.
#
# Co-op: each holder's flag is independent; no cross-player interference.
# Type Infusion: moldBreaker affects all ability checks during the move;
#   type-converted moves still benefit if the base move is a status move.
# ────────────────────────────────────────────────────────────────────────────────
class PokeBattle_Battler
  alias npt_myceliummight_hasMoldBreaker? hasMoldBreaker?
  def hasMoldBreaker?
    return true if @npt_myceliummight_override
    npt_myceliummight_hasMoldBreaker?
  end

  alias npt_myceliummight_pbUseMove pbUseMove
  def pbUseMove(choice, specialUsage = false)
    move = choice[2]
    @npt_myceliummight_override = move && hasActiveAbility?(:MYCELIUMMIGHT) && move.statusMove?
    npt_myceliummight_pbUseMove(choice, specialUsage)
  ensure
    @npt_myceliummight_override = false
  end
end

if defined?(BattleHandlers) && defined?(BattleHandlers::PriorityBracketChangeAbility)
  BattleHandlers::PriorityBracketChangeAbility.add(:MYCELIUMMIGHT,
    proc { |ability, battler, subPri, battle|
      next if subPri != 0
      move = battle.choices[battler.index][2]
      next unless move && move.statusMove?
      next -1
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# NEUTRALIZING GAS
# While the holder is on the field, all other Pokémon's abilities are
# suppressed (unless unstoppable). The holder's own ability is never suppressed.
# When the holder leaves (switch-out or faint), abilities are restored and
# all remaining battlers re-trigger their switch-in ability effects.
#
# Implementation:
#   - Alias abilityActive?: directly scans for an active gas holder each call.
#     No flags needed — automatically applies to battlers entering mid-gas and
#     handles multiple gas holders (any remaining holder keeps gas active).
#   - AbilityOnSwitchIn: activation message.
#   - AbilityOnSwitchOut: dissipation message (fires before holder is marked gone).
#   - Alias pbAbilitiesOnSwitchOut: re-triggers pbEffectsOnSwitchIn for all
#     remaining battlers AFTER the holder is marked as gone (@fainted=true).
#   - Alias pbFaint: same as above for the faint case + dissipation message.
#
# Co-op: the direct scan covers all battler positions on all sides.
# Type Infusion: abilityActive? returning false blocks all ability handlers,
#   including type-modifying ones — infused type logic in DamageCalcUserAbility
#   etc. is suppressed for affected battlers.
# ────────────────────────────────────────────────────────────────────────────────
#===============================================================================
# pbCheckForm hook — Schooling (Wishiwashi)
#
# The core pbCheckForm uses `self.ability == :SCHOOLING` which compares a
# GameData::Ability object to a symbol.  On some engine versions this can fail.
# This alias re-runs the Schooling check using @ability_id (guaranteed symbol)
# after the original, so it fires even if the core check silently misses.
# The @form guard prevents double-triggering when the core check already worked.
#===============================================================================
class PokeBattle_Battler
  alias npt_schooling_pbCheckForm pbCheckForm

  def pbCheckForm(endOfRound = false)
    # For Wishiwashi/Schooling: pre-compute the desired form, then pre-set the
    # battler's @form so the core engine's guards (@form!=1 / @form!=0) are
    # already false — silencing the core's own splash entirely.
    # We fire our own logic only when there is an actual form transition.
    want_form = nil
    old_form  = nil
    is_wishiwashi = (isSpecies?(:WISHIWASHI) rescue false) ||
                    (isFusionOf(:WISHIWASHI) rescue false)
    is_fusion = (@pokemon.isFusion? rescue false)
    if !fainted? && !@effects[PBEffects::Transform] &&
       is_wishiwashi && @ability_id == :SCHOOLING
      want_form = (@level >= 20 && @hp > @totalhp / 4) ? 1 : 0
      old_form  = is_fusion ? (@pokemon.instance_variable_get(:@schooling_form) || 0) : @form
      @form     = want_form unless is_fusion  # silence core's Wishiwashi block (pure only)
    end

    npt_schooling_pbCheckForm(endOfRound)

    # Power Construct fusion check (runs regardless of Schooling state)
    npt_check_power_construct_fusion(endOfRound)

    return if fainted? || @effects[PBEffects::Transform]

    if defined?(MultiplayerDebug) && !want_form.nil?
      MultiplayerDebug.info("SCHOOLING", "species=#{@pokemon.species} old=#{old_form} want=#{want_form} level=#{@level} hp=#{@hp}/#{@totalhp} fusion=#{is_fusion}")
    end

    # Only animate/refresh when the form actually changes
    return if want_form.nil? || old_form == want_form

    @battle.pbShowAbilitySplash(self, true)
    @battle.pbHideAbilitySplash(self)

    if is_fusion
      # Fusion: swap Wishiwashi component for School form (stats only, no sprite change)
      if want_form == 1
        @pokemon.changeFormSpecies(:WISHIWASHI, :WISHIWASHI_1)
        @pokemon.instance_variable_set(:@schooling_form, 1)
      else
        @pokemon.changeFormSpecies(:WISHIWASHI_1, :WISHIWASHI)
        @pokemon.instance_variable_set(:@schooling_form, 0)
      end
      pbUpdate(true)
    else
      # Pure Wishiwashi: form change with sprite swap
      @pokemon.form_simple = want_form
      pbUpdate(true)
      @battle.scene.pbChangePokemon(self, @pokemon)
    end

    msg = want_form == 1 ? _INTL("{1} formed a school!", pbThis) \
                         : _INTL("{1} stopped schooling!", pbThis)
    @battle.pbDisplay(msg)
    return  # Schooling handled — skip Power Construct below
  end

  # ── Power Construct (Zygarde fusion) ──
  # Core engine handles pure Zygarde (isSpecies?(:ZYGARDE)).
  # For fusions containing Zygarde, we handle it here.
  private def npt_check_power_construct_fusion(endOfRound)
    return unless endOfRound
    return if fainted? || @effects[PBEffects::Transform]
    return unless @ability_id == :POWERCONSTRUCT
    is_fusion = (@pokemon.isFusion? rescue false)
    return unless is_fusion
    # Check which Zygarde form is in the fusion (50% or 10%)
    has_50 = (@pokemon.isFusionOf(:ZYGARDE) rescue false)
    has_10 = (@pokemon.isFusionOf(:ZYGARDE_1) rescue false)
    return unless has_50 || has_10

    pc_state = @pokemon.instance_variable_get(:@power_construct_state) || 0
    # Transform when HP <= 50% and not already in Complete Forme
    if @hp <= @totalhp / 2 && pc_state == 0
      @battle.pbDisplay(_INTL("You sense the presence of many!"))
      @battle.pbShowAbilitySplash(self, true)
      @battle.pbHideAbilitySplash(self)
      # Swap Zygarde component → Complete Forme for stats
      if has_50
        @pokemon.changeFormSpecies(:ZYGARDE, :ZYGARDE_2)
        @pokemon.instance_variable_set(:@power_construct_from, :ZYGARDE)
      elsif has_10
        @pokemon.changeFormSpecies(:ZYGARDE_1, :ZYGARDE_3)
        @pokemon.instance_variable_set(:@power_construct_from, :ZYGARDE_1)
      end
      @pokemon.instance_variable_set(:@power_construct_state, 1)
      pbUpdate(true)
      @battle.pbDisplay(_INTL("{1} transformed into its Complete Forme!", pbThis))
    end
  end
end

class PokeBattle_Battler
  alias npt_neutgas_abilityActive? abilityActive?
  def abilityActive?(ignore_fainted = false)
    return false unless npt_neutgas_abilityActive?(ignore_fainted)
    return true if @ability_id == :NEUTRALIZINGGAS # holder never suppressed
    return true if unstoppableAbility?
    @battle.battlers.each do |b|
      next unless b && !b.fainted? && b.index != @index
      next unless b.ability_id == :NEUTRALIZINGGAS
      return false unless b.effects[PBEffects::GastroAcid] # holder suppressed by Gastro Acid?
    end
    true
  end
end

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:NEUTRALIZINGGAS,
    proc { |ability, battler, battle|
      battle.pbShowAbilitySplash(battler)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("All Pokémon's abilities have been suppressed!"))
      else
        battle.pbDisplay(_INTL("{1}'s {2} suppressed all other abilities!",
                               battler.pbThis, battler.abilityName))
      end
      battle.pbHideAbilitySplash(battler)
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchOut)
  BattleHandlers::AbilityOnSwitchOut.add(:NEUTRALIZINGGAS,
    proc { |ability, battler, endOfBattle|
      next if endOfBattle
      battler.battle.pbDisplay(_INTL("The neutralizing gas faded away!"))
    }
  )
end

# Re-trigger switch-in abilities for remaining battlers after gas holder switches out.
# pbAbilitiesOnSwitchOut fires AbilityOnSwitchOut (message) then marks holder as gone.
# At that point our check in abilityActive? no longer finds an active gas holder.
class PokeBattle_Battler
  alias npt_neutgas_pbAbilitiesOnSwitchOut pbAbilitiesOnSwitchOut
  def pbAbilitiesOnSwitchOut
    had_gas = (@ability_id == :NEUTRALIZINGGAS)
    npt_neutgas_pbAbilitiesOnSwitchOut
    if had_gas
      another_gas = @battle.battlers.any? { |b| b && !b.fainted? && b.ability_id == :NEUTRALIZINGGAS }
      unless another_gas
        @battle.pbPriority(true).each { |b| b.pbEffectsOnSwitchIn(false) unless b.fainted? }
      end
    end
  end
end

# Same for faint case — holder is marked @fainted=true inside original pbFaint.
class PokeBattle_Battler
  alias npt_neutgas_pbFaint pbFaint
  def pbFaint(showMessage = true)
    had_gas = (@ability_id == :NEUTRALIZINGGAS)
    npt_neutgas_pbFaint(showMessage)
    if had_gas
      another_gas = @battle.battlers.any? { |b| b && !b.fainted? && b.ability_id == :NEUTRALIZINGGAS }
      unless another_gas
        @battle.pbDisplay(_INTL("The neutralizing gas faded away!"))
        @battle.pbPriority(true).each { |b| b.pbEffectsOnSwitchIn(false) unless b.fainted? }
      end
    end
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# OPPORTUNIST
# When an opposing Pokémon's stat is raised, the holder copies that stat raise.
# AbilityOnStatGain fires on the stat-GAINER's ability — wrong side for us.
# Instead, alias pbRaiseStatStage + pbRaiseStatStageByCause to check opposing
# battlers after any successful raise.
# Recursion guard @npt_opportunist_copying prevents A→B→A infinite loops when
# both sides have Opportunist.
# Co-op: eachOtherSideBattler covers all opposing positions, so multiple
#   Opportunist holders on the same side each copy independently.
# Type Infusion: stat boosts are category-neutral.
# ────────────────────────────────────────────────────────────────────────────────
class PokeBattle_Battler
  def npt_opportunist_check(stat, increment)
    return if @npt_opportunist_copying
    @battle.eachOtherSideBattler(@index) do |b|
      next unless b.hasActiveAbility?(:OPPORTUNIST)
      next unless b.pbCanRaiseStatStage?(stat, b)
      b.instance_variable_set(:@npt_opportunist_copying, true)
      b.pbRaiseStatStageByAbility(stat, increment, b,
                                   GameData::Ability.get(:OPPORTUNIST).real_name)
      b.instance_variable_set(:@npt_opportunist_copying, false)
    end
  end

  alias npt_opportunist_pbRaiseStatStage pbRaiseStatStage
  def pbRaiseStatStage(stat, increment, user, showAnim = true, ignoreContrary = false)
    result = npt_opportunist_pbRaiseStatStage(stat, increment, user, showAnim, ignoreContrary)
    npt_opportunist_check(stat, increment) if result
    result
  end

  alias npt_opportunist_pbRaiseStatStageByCause pbRaiseStatStageByCause
  def pbRaiseStatStageByCause(stat, increment, user, cause, showAnim = true, ignoreContrary = false)
    result = npt_opportunist_pbRaiseStatStageByCause(stat, increment, user, cause, showAnim, ignoreContrary)
    npt_opportunist_check(stat, increment) if result
    result
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# ORICHALCUM PULSE
# 1. Sets harsh sunlight on switch-in (identical to Drought).
# 2. In harsh sunlight, boosts the holder's Attack by 4/3× on physical moves
#    (mirrors Hadron Engine's Sp. Atk boost under Electric Terrain).
# No grounded check — mainline grants the boost regardless of airborne status.
# Co-op: fires for each holder independently; sun benefits all allies as usual.
# Type Infusion: move.physicalMove? checks category (unaffected by type conv.).
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.copy(:DROUGHT, :ORICHALCUMPULSE)
end

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:ORICHALCUMPULSE,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.physicalMove?
      next unless [:Sun, :HarshSun].include?(user.battle.pbWeather)
      mults[:attack_multiplier] *= 4.0 / 3
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# PARENTAL BOND
# Already handled by base engine (002_Move_Usage.rb:44).
# pbNumHits returns 2 for single-target damaging moves; second hit deals 25%
# damage via PBEffects::ParentalBond. No NPT code needed.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# PASTEL VEIL
# 1. Holder is immune to poison and bad poison.
# 2. Allies are immune to poison and bad poison (StatusImmunityAllyAbility).
# 3. On switch-in, cures poison/bad poison on all allies.
# Co-op: StatusImmunityAllyAbility covers all same-side battlers via eachAlly;
#   switch-in cure uses eachAlly so co-op partners are healed.
# Type Infusion: status effects are type-neutral.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::StatusImmunityAbility)
  BattleHandlers::StatusImmunityAbility.add(:PASTELVEIL,
    proc { |ability, battler, status|
      next true if status == :POISON
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::StatusImmunityAllyAbility)
  BattleHandlers::StatusImmunityAllyAbility.add(:PASTELVEIL,
    proc { |ability, battler, status|
      next true if status == :POISON
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:PASTELVEIL,
    proc { |ability, battler, battle|
      battler.eachAlly do |b|
        next unless b.status == :POISON
        battle.pbShowAbilitySplash(battler)
        b.pbCureStatus(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
        unless PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          battle.pbDisplay(_INTL("{1}'s {2} cured {3}'s poisoning!",
                                 battler.pbThis, battler.abilityName, b.pbThis(true)))
        end
        battle.pbHideAbilitySplash(battler)
      end
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# PERISH BODY MUST REMEMBER TO BLOCK IT FOR BOSS FIGHTS
# When hit by a contact move, both the holder and the attacker begin a
# Perish Song countdown (count 3 → 0, then faint). Only triggers if neither
# battler already has a Perish count active.
# Sets PerishSong = 4 (decrements to 3 on first EOR display, same as the move).
# Co-op: fires for any attacker regardless of side — contact from an ally
#   would also trigger it (same as mainline doubles behaviour).
# Type Infusion: contact check is category-based, unaffected by type conversion.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.add(:PERISHBODY,
    proc { |ability, user, target, move, battle|
      next unless move.pbContactMove?(user)
      next if user.fainted?
      next if user.effects[PBEffects::PerishSong] > 0
      next if target.effects[PBEffects::PerishSong] > 0
      battle.pbShowAbilitySplash(target)
      [user, target].each do |b|
        b.effects[PBEffects::PerishSong]     = 4
        b.effects[PBEffects::PerishSongUser] = target.index
      end
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("All Pokémon that hear the song will faint in three turns!"))
      else
        battle.pbDisplay(_INTL("{1}'s {2} afflicted both with a perish count!",
                               target.pbThis, target.abilityName))
      end
      battle.pbHideAbilitySplash(target)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# POISON PUPPETEER
# When the holder poisons or badly poisons a target with a move, the target
# also becomes confused. Implemented by aliasing pbPoison — fires after the
# original call; checks that poisoning actually succeeded (status == :POISON)
# and that the user has POISONPUPPETEER before confusing.
# Co-op: alias fires for any user regardless of side.
# Type Infusion: status infliction and confusion are type-neutral.
# ────────────────────────────────────────────────────────────────────────────────
class PokeBattle_Battler
  alias npt_poisonpuppeteer_pbPoison pbPoison
  def pbPoison(user = nil, msg = nil, toxic = false)
    was_poisoned = (self.status == :POISON)
    npt_poisonpuppeteer_pbPoison(user, msg, toxic)
    return unless self.status == :POISON && !was_poisoned
    return unless user && user.index != @index
    return unless user.hasActiveAbility?(:POISONPUPPETEER)
    return unless pbCanConfuse?(user, false)
    user.battle.pbShowAbilitySplash(user)
    pbConfuse
    unless PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      user.battle.pbDisplay(_INTL("{1}'s {2} confused {3}!",
                                  user.pbThis, user.abilityName, pbThis(true)))
    end
    user.battle.pbHideAbilitySplash(user)
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# POWER OF ALCHEMY
# Already handled by base engine (003_BattleHandlers_Abilities.rb:2398).
# AbilityChangeOnBattlerFainting copies a fainted ally's ability to the holder.
# No NPT code needed.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# POWER SPOT
# Boosts the power of allies' moves by 1.3× (all categories, same multiplier
# as Battery). Battery only boosts special moves; Power Spot boosts everything.
# Co-op: DamageCalcUserAllyAbility fires for every ally attacker automatically.
# Type Infusion: final_damage_multiplier applies after type calc — works for
#   all type-converted moves without special handling.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAllyAbility)
  BattleHandlers::DamageCalcUserAllyAbility.add(:POWERSPOT,
    proc { |ability, user, target, move, mults, baseDmg, type|
      mults[:final_damage_multiplier] *= 1.3
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# PRIMORDIAL SEA
# ────────────────────────────────────────────────────────────────────────────────
# Fully handled by base engine:
#   AbilityOnSwitchIn → pbBattleWeatherAbility(:HeavyRain, battler, battle, true)
#   pbEORWeather (Battle_Phase_EndOfRound) → pbCheckGlobalAbility(:PRIMORDIALSEA)
#     keeps :HeavyRain active as long as any battler has PRIMORDIAL SEA.
# No code needed here.
# Co-op: pbCheckGlobalAbility scans all battlers — naturally covers co-op slots.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# PROPELLER TAIL
# ────────────────────────────────────────────────────────────────────────────────
# Ignores all redirection effects (Follow Me, Rage Powder, Spotlight,
# Lightning Rod, Storm Drain).
# pbChangeTargets in 008_Battler_UseMove_Targeting.rb short-circuits on
# move.cannotRedirect? (per-move flag). PROPELLER TAIL is per-user (ability),
# so alias pbChangeTargets to return original targets unchanged when user holds it.
# Co-op: works for all attacker positions naturally.
# Type Infusion: no interaction — target selection is unaffected by move type.
# ────────────────────────────────────────────────────────────────────────────────
class PokeBattle_Battler
  alias npt_propellertail_pbChangeTargets pbChangeTargets
  def pbChangeTargets(move, user, targets)
    return targets if user.hasActiveAbility?([:PROPELLERTAIL, :STALWART])
    npt_propellertail_pbChangeTargets(move, user, targets)
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# PROTOSYNTHESIS
# ────────────────────────────────────────────────────────────────────────────────
# Activates in harsh sunlight (:Sun or :HarshSun).
# Boosts the holder's highest base stat (excl. HP) by 30%, or 50% if Speed.
# Booster Energy item interaction is not implemented (item not in engine).
#
# Three handlers:
#   SpeedCalcAbility     — 1.5× Speed when Speed is highest stat.
#   DamageCalcUserAbility  — 1.3× attack_multiplier for physical (ATK highest)
#                            or special (SP.ATK highest) moves.
#   DamageCalcTargetAbility — 1.3× defense_multiplier for incoming physical
#                             (DEF highest) or special (SP.DEF highest) moves.
#
# Highest stat comparison uses raw base stats (@attack etc.) matching Gen 9.
# Co-op: each handler fires per-battler — all attacker/defender positions covered.
# Type Infusion: attack_multiplier applies post-type-calc; works for all types.
# ────────────────────────────────────────────────────────────────────────────────
class PokeBattle_Battler
  def npt_protosynthesis_highest_stat
    candidates = [
      [:ATTACK,          @attack],
      [:DEFENSE,         @defense],
      [:SPECIAL_ATTACK,  @spatk],
      [:SPECIAL_DEFENSE, @spdef],
      [:SPEED,           @speed]
    ]
    candidates.max_by { |_, v| v }[0]
  end
end

if defined?(BattleHandlers) && defined?(BattleHandlers::SpeedCalcAbility)
  BattleHandlers::SpeedCalcAbility.add(:PROTOSYNTHESIS,
    proc { |ability, battler, speedMult|
      next unless [:Sun, :HarshSun].include?(battler.battle.pbWeather)
      next unless battler.npt_protosynthesis_highest_stat == :SPEED
      next speedMult * 1.5
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:PROTOSYNTHESIS,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless [:Sun, :HarshSun].include?(user.battle.pbWeather)
      stat = user.npt_protosynthesis_highest_stat
      if stat == :ATTACK && move.physicalMove?
        mults[:attack_multiplier] *= 1.3
      elsif stat == :SPECIAL_ATTACK && move.specialMove?
        mults[:attack_multiplier] *= 1.3
      end
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAbility)
  BattleHandlers::DamageCalcTargetAbility.add(:PROTOSYNTHESIS,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless [:Sun, :HarshSun].include?(user.battle.pbWeather)
      stat = target.npt_protosynthesis_highest_stat
      if stat == :DEFENSE && move.physicalMove?
        mults[:defense_multiplier] *= 1.3
      elsif stat == :SPECIAL_DEFENSE && move.specialMove?
        mults[:defense_multiplier] *= 1.3
      end
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# PUNK ROCK
# ────────────────────────────────────────────────────────────────────────────────
# Boosts sound-based moves used by the holder by 30%.
# Halves damage received from sound-based moves.
# soundMove? checks flag "k" on the move — covers all sound moves.
# Co-op: DamageCalcUserAbility fires per attacker; DamageCalcTargetAbility fires
#   per defender — both co-op positions covered automatically.
# Type Infusion: base_damage_multiplier applies before type calc; still correct
#   since it scales the move's power uniformly.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:PUNKROCK,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.soundMove?
      mults[:base_damage_multiplier] *= 1.3
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAbility)
  BattleHandlers::DamageCalcTargetAbility.add(:PUNKROCK,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.soundMove?
      mults[:final_damage_multiplier] *= 0.5
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# PURIFYING SALT
# ────────────────────────────────────────────────────────────────────────────────
# Grants full immunity to all non-volatile status conditions (burn, freeze,
# paralysis, poison, sleep).
# Halves damage received from Ghost-type moves.
# Co-op: StatusImmunityAbility is checked per-battler; DamageCalcTargetAbility
#   fires per defender — both co-op positions covered automatically.
# Type Infusion: Ghost type is checked against the post-infusion calcType, so
#   a move infused into Ghost will still trigger the reduction correctly.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::StatusImmunityAbility)
  BattleHandlers::StatusImmunityAbility.add(:PURIFYINGSALT,
    proc { |ability, battler, status|
      next true  # immune to all non-volatile statuses
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAbility)
  BattleHandlers::DamageCalcTargetAbility.add(:PURIFYINGSALT,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless type == :GHOST
      mults[:final_damage_multiplier] *= 0.5
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# QUARK DRIVE
# ────────────────────────────────────────────────────────────────────────────────
# Identical mechanic to PROTOSYNTHESIS but activates in Electric Terrain
# instead of harsh sunlight. Boosts the holder's highest base stat (excl. HP)
# by 30%, or 50% if Speed.
# Booster Energy item interaction not implemented (item not in engine).
# Reuses npt_protosynthesis_highest_stat helper defined for PROTOSYNTHESIS.
# Co-op / Type Infusion: same notes as PROTOSYNTHESIS.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::SpeedCalcAbility)
  BattleHandlers::SpeedCalcAbility.add(:QUARKDRIVE,
    proc { |ability, battler, speedMult|
      next unless battler.battle.field.terrain == :Electric
      next unless battler.npt_protosynthesis_highest_stat == :SPEED
      next speedMult * 1.5
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:QUARKDRIVE,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless user.battle.field.terrain == :Electric
      stat = user.npt_protosynthesis_highest_stat
      if stat == :ATTACK && move.physicalMove?
        mults[:attack_multiplier] *= 1.3
      elsif stat == :SPECIAL_ATTACK && move.specialMove?
        mults[:attack_multiplier] *= 1.3
      end
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAbility)
  BattleHandlers::DamageCalcTargetAbility.add(:QUARKDRIVE,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless user.battle.field.terrain == :Electric
      stat = target.npt_protosynthesis_highest_stat
      if stat == :DEFENSE && move.physicalMove?
        mults[:defense_multiplier] *= 1.3
      elsif stat == :SPECIAL_DEFENSE && move.specialMove?
        mults[:defense_multiplier] *= 1.3
      end
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# QUEENLY MAJESTY
# ────────────────────────────────────────────────────────────────────────────────
# Fully handled by base engine:
#   MoveBlockingAbility.copy(:DAZZLING, :QUEENLYMAJESTY) at line 579 of
#   003_BattleHandlers_Abilities.rb — prevents opponents from using priority
#   moves against the holder's side. No code needed here.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# QUICK DRAW
# ────────────────────────────────────────────────────────────────────────────────
# 30% chance each turn to move first within the holder's priority bracket
# (identical mechanic to Quick Claw item, which is 20%).
# PriorityBracketChangeAbility sets subPri = 1 when proc fires; the engine then
# sets PBEffects::PriorityAbility = true, triggering PriorityBracketUseAbility
# to display the "moved first" message on the attack phase.
# Note: PriorityBracketChangeAbility has no move parameter, so the check fires
# for all move categories (same limitation as Quick Claw).
# Co-op: priority is computed per-battler — works for all co-op slots.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::PriorityBracketChangeAbility)
  BattleHandlers::PriorityBracketChangeAbility.add(:QUICKDRAW,
    proc { |ability, battler, subPri, battle|
      next 1 if subPri < 1 && battle.pbRandom(10) < 3
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::PriorityBracketUseAbility)
  BattleHandlers::PriorityBracketUseAbility.add(:QUICKDRAW,
    proc { |ability, battler, battle|
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1}'s {2} let it move first!", battler.pbThis, battler.abilityName))
      battle.pbHideAbilitySplash(battler)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# RIPEN
# ────────────────────────────────────────────────────────────────────────────────
# Doubles the effect of berries consumed in battle:
#   - HP-healing berries (Sitrus, Oran, confusion berries): double HP restored.
#     Implemented via pbItemHPHealCheck alias that sets @npt_ripen_active, and
#     pbRecoverHP alias that doubles amt when the flag is set.
#   - Stat-boosting pinch berries (Liechi, Salac, etc.): double stage increment.
#     Implemented by redefining the global pbBattleStatIncreasingBerry helper.
#   - Type-weakening berries (Occa, Passho, etc.): double damage reduction
#     (/4 total instead of /2). Implemented by redefining pbBattleTypeWeakingBerry
#     to apply an extra /2 after the original halving.
# Status-curing, Micle, Custap, and other binary-effect berries are unaffected
# (their effects cannot be meaningfully doubled).
# Co-op: all hooks are per-battler — all co-op slots covered.
# ────────────────────────────────────────────────────────────────────────────────
class PokeBattle_Battler
  alias npt_ripen_pbItemHPHealCheck pbItemHPHealCheck
  def pbItemHPHealCheck(item_to_use = nil, fling = false)
    @npt_ripen_active = hasActiveAbility?(:RIPEN)
    npt_ripen_pbItemHPHealCheck(item_to_use, fling)
  ensure
    @npt_ripen_active = false
  end

  alias npt_ripen_pbRecoverHP pbRecoverHP
  def pbRecoverHP(amt, anim = true, anyAnim = true)
    amt *= 2 if @npt_ripen_active && amt > 0
    npt_ripen_pbRecoverHP(amt, anim, anyAnim)
  end
end

alias npt_ripen_old_pbBattleStatIncreasingBerry pbBattleStatIncreasingBerry
def pbBattleStatIncreasingBerry(battler, battle, item, forced, stat, increment = 1)
  increment *= 2 if battler.hasActiveAbility?(:RIPEN)
  npt_ripen_old_pbBattleStatIncreasingBerry(battler, battle, item, forced, stat, increment)
end

alias npt_ripen_old_pbBattleTypeWeakingBerry pbBattleTypeWeakingBerry
def pbBattleTypeWeakingBerry(type, moveType, target, mults)
  npt_ripen_old_pbBattleTypeWeakingBerry(type, moveType, target, mults)
  # RIPEN: apply an additional /2 if the berry reduction actually triggered
  if target.hasActiveAbility?(:RIPEN) && target.damageState.berryWeakened
    mults[:final_damage_multiplier] /= 2
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# ROCKY PAYLOAD
# ────────────────────────────────────────────────────────────────────────────────
# Boosts the power of Rock-type moves by 50%.
# Identical pattern to STEELWORKER (Steel-type boost) in base engine.
# Co-op: DamageCalcUserAbility fires per attacker — all co-op slots covered.
# Type Infusion: `type` is the post-infusion calcType; a move converted to Rock
#   will trigger the boost correctly.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:ROCKYPAYLOAD,
    proc { |ability, user, target, move, mults, baseDmg, type|
      mults[:attack_multiplier] *= 1.5 if type == :ROCK
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# SAND SPIT
# ────────────────────────────────────────────────────────────────────────────────
# Triggers a sandstorm when the holder is hit by a move that deals damage.
# pbBattleWeatherAbility handles the ability splash, display message, and
# duration (5 turns fixed, or extended by Smooth Rock item).
# Skip if sandstorm is already active to avoid redundant messages.
# Co-op: TargetAbilityOnHit fires per defending battler — all positions covered.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.add(:SANDSPIT,
    proc { |ability, user, target, move, battle|
      next if target.fainted?
      next if battle.field.weather == :Sandstorm
      pbBattleWeatherAbility(:Sandstorm, target, battle)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# SCREEN CLEANER
# ────────────────────────────────────────────────────────────────────────────────
# On switch-in, removes Aurora Veil, Light Screen, and Reflect from BOTH sides.
# Uses the same display strings as the Defog move handler.
# Co-op: AbilityOnSwitchIn fires once per switch-in event; clears field-wide
#   effects so all co-op positions benefit automatically.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:SCREENCLEANER,
    proc { |ability, battler, battle|
      removed_any = false
      sides = [[battler.pbOwnSide, battler.pbTeam],
               [battler.pbOpposingSide, battler.pbOpposingTeam]]
      sides.each do |side, teamName|
        if side.effects[PBEffects::AuroraVeil] > 0
          side.effects[PBEffects::AuroraVeil] = 0
          battle.pbDisplay(_INTL("{1}'s Aurora Veil wore off!", teamName))
          removed_any = true
        end
        if side.effects[PBEffects::LightScreen] > 0
          side.effects[PBEffects::LightScreen] = 0
          battle.pbDisplay(_INTL("{1}'s Light Screen wore off!", teamName))
          removed_any = true
        end
        if side.effects[PBEffects::Reflect] > 0
          side.effects[PBEffects::Reflect] = 0
          battle.pbDisplay(_INTL("{1}'s Reflect wore off!", teamName))
          removed_any = true
        end
      end
      if removed_any
        battle.pbShowAbilitySplash(battler)
        battle.pbHideAbilitySplash(battler)
      end
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# SEED SOWER
# ────────────────────────────────────────────────────────────────────────────────
# Sets up Grassy Terrain when the holder is hit by a damaging move.
# Mirrors SAND SPIT but triggers terrain instead of weather.
# pbStartTerrain handles the splash hide internally (see GRASSY SURGE note).
# Skip if Grassy Terrain is already active.
# Co-op: TargetAbilityOnHit fires per defending battler — all positions covered.
# Type Infusion / MIMICRY: terrain change will trigger npt_mimicry_updateType
#   on all battlers automatically via the pbStartTerrain alias.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.add(:SEEDSOWER,
    proc { |ability, user, target, move, battle|
      next if target.fainted?
      next if battle.field.terrain == :Grassy
      battle.pbShowAbilitySplash(target)
      battle.pbStartTerrain(target, :Grassy)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# SHADOW SHIELD
# ────────────────────────────────────────────────────────────────────────────────
# Fully handled by base engine:
#   DamageCalcTargetAbilityNonIgnorable at line 1223 of
#   003_BattleHandlers_Abilities.rb — halves damage when holder is at full HP.
#   Uses NonIgnorable so Mold Breaker cannot bypass it (same as Multiscale).
# No code needed here.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# SHARPNESS
# ────────────────────────────────────────────────────────────────────────────────
# Boosts the power of slicing moves by 50%.
# This engine has no "slicing" move flag (flags only go up to 'o'/danceMove?),
# so slicingMove? is defined here as a symbol-set lookup covering all moves from
# the official Gen 9 Sharpness move list (both tables).
# Moves not present in this engine simply never match — no errors.
# Co-op: DamageCalcUserAbility fires per attacker — all co-op slots covered.
# Type Infusion: base_damage_multiplier applies uniformly — works for all types.
# ────────────────────────────────────────────────────────────────────────────────
NPT_SLICING_MOVES = [
  :AERIALACE, :AIRCUTTER, :AIRSLASH, :AQUACUTTER, :CEASELESSEDGE,
  :FURYCUTTER, :LEAFBLADE, :NIGHTSLASH, :PSYCHOCUT, :RAZORSHELL,
  :SACREDSWORD, :SLASH, :SOLARBLADE, :STONEAXE, :XSCISSOR,
  :BEHEMOTHBLADE, :BITTERBLADE, :CROSSPOISON, :CUT, :KOWTOWCLEAVE,
  :MIGHTYCLEAVE, :POPULATIONBOMB, :PSYBLADE, :RAZORLEAF,
  :SECRETSWORD, :TACHYONCUTTER
].freeze

class PokeBattle_Move
  def slicingMove?
    NPT_SLICING_MOVES.include?(@id)
  end
end

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:SHARPNESS,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.slicingMove?
      mults[:base_damage_multiplier] *= 1.5
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# SOUL-HEART
# ────────────────────────────────────────────────────────────────────────────────
# Fully handled by base engine:
#   AbilityOnBattlerFainting at line 2417 of 003_BattleHandlers_Abilities.rb —
#   raises the holder's Special Attack by 1 stage whenever any Pokémon faints.
# No code needed here.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# STAKEOUT
# ────────────────────────────────────────────────────────────────────────────────
# Fully handled by base engine:
#   DamageCalcUserAbility at line 1042 of 003_BattleHandlers_Abilities.rb —
#   doubles attack_multiplier when the target's choice is :SwitchOut (i.e. the
#   target switched in this turn).
# No code needed here.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# STALWART
# ────────────────────────────────────────────────────────────────────────────────
# Ignores all redirection effects — identical mechanic to PROPELLER TAIL.
# Handled by extending the npt_propellertail_pbChangeTargets alias above to also
# check :STALWART via hasActiveAbility?([:PROPELLERTAIL, :STALWART]).
# No separate handler needed.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# STAMINA
# ────────────────────────────────────────────────────────────────────────────────
# Fully handled by base engine:
#   TargetAbilityOnHit at line 1561 of 003_BattleHandlers_Abilities.rb —
#   raises the holder's Defense by 1 stage when hit by a damaging move.
# No code needed here.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# STEAM ENGINE
# ────────────────────────────────────────────────────────────────────────────────
# Raises the holder's Speed by 6 stages when hit by a Fire- or Water-type move.
# move.calcType is the post-infusion type — correct for Type Infusion.
# Co-op: TargetAbilityOnHit fires per defending battler — all positions covered.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.add(:STEAMENGINE,
    proc { |ability, user, target, move, battle|
      next unless [:FIRE, :WATER].include?(move.calcType)
      target.pbRaiseStatStageByAbility(:SPEED, 6, target,
                                       GameData::Ability.get(ability).real_name)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# STEELY SPIRIT
# ────────────────────────────────────────────────────────────────────────────────
# Boosts Steel-type moves used by the holder AND its allies by 50%.
# DamageCalcUserAbility covers the holder's own moves.
# DamageCalcUserAllyAbility covers moves used by co-op/double battle partners
#   while the holder is on the field.
# Co-op: both handlers naturally cover all relevant attacker/ally positions.
# Type Infusion: `type` is post-infusion calcType — a move converted to Steel
#   triggers the boost correctly.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:STEELYSPIRIT,
    proc { |ability, user, target, move, mults, baseDmg, type|
      mults[:attack_multiplier] *= 1.5 if type == :STEEL
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAllyAbility)
  BattleHandlers::DamageCalcUserAllyAbility.add(:STEELYSPIRIT,
    proc { |ability, user, target, move, mults, baseDmg, type|
      mults[:attack_multiplier] *= 1.5 if type == :STEEL
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# SUPERSWEET SYRUP
# ────────────────────────────────────────────────────────────────────────────────
# On the holder's FIRST switch-in this battle, lowers all opposing Pokémon's
# evasion by 1 stage. Does not activate on subsequent switch-ins.
# @npt_syrup_used is set on the battler object (lives for the whole battle).
# Co-op: eachOtherSideBattler iterates all foes — covers all opponent positions.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:SUPERSWEETSYRUP,
    proc { |ability, battler, battle|
      next if battler.instance_variable_defined?(:@npt_syrup_used) && battler.instance_variable_get(:@npt_syrup_used)
      battler.instance_variable_set(:@npt_syrup_used, true)
      battle.pbShowAbilitySplash(battler)
      battle.eachOtherSideBattler(battler.index) do |b|
        next unless b.pbCanLowerStatStage?(:EVASION, battler)
        b.pbLowerStatStageByCause(:EVASION, 1, battler, battler.abilityName)
      end
      battle.pbHideAbilitySplash(battler)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# SUPREME OVERLORD
# ────────────────────────────────────────────────────────────────────────────────
# Boosts the holder's move power by 10% for each ally that has fainted this
# battle, up to a maximum of 5 fainted allies (+50% max).
# Counts fainted Pokémon in the holder's party (excluding the holder itself).
# Co-op: DamageCalcUserAbility fires per attacker. pbParty returns the relevant
#   trainer's party, so each battler counts their own side's fainted Pokémon.
# Type Infusion: base_damage_multiplier applies uniformly across all types.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:SUPREMEOVERLORD,
    proc { |ability, user, target, move, mults, baseDmg, type|
      fainted_count = user.battle.pbParty(user.index).count { |p| p != user.pokemon && p.fainted? }
      fainted_count = [fainted_count, 5].min
      next if fainted_count == 0
      mults[:base_damage_multiplier] *= 1.0 + (fainted_count * 0.1)
    }
  )
end

#===============================================================================
# SWORD OF RUIN
# Reduces the Defense of all other Pokémon on the field by 25%.
# The holder itself is unaffected. Other Sword of Ruin holders are also exempt.
#
# Identical architecture to BEADS OF RUIN — only differences:
#   - move.physicalMove? instead of specialMove? (Defense, not Sp. Def)
#   - exemption checks :SWORDOFRUIN instead of :BEADSOFRUIN
#   - switch-in message references Defense
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:SWORDOFRUIN,
    proc { |ability, battler, battle|
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1}'s Sword of Ruin weakened all other Pokémon's Defense!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:SWORDOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.physicalMove?
      next if target.hasActiveAbility?(:SWORDOFRUIN)
      mults[:defense_multiplier] *= 0.75
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAllyAbility)
  BattleHandlers::DamageCalcUserAllyAbility.add(:SWORDOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.physicalMove?
      next if target.hasActiveAbility?(:SWORDOFRUIN)
      mults[:defense_multiplier] *= 0.75
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# SYMBIOSIS
# ────────────────────────────────────────────────────────────────────────────────
# Fully handled by base engine:
#   pbSymbiosis in 006_Battler_AbilityAndItem.rb (line 170) — called from
#   pbConsumeItem whenever an ally uses or loses their held item. The holder
#   passes its own item to the itemless ally.
# No code needed here.
# ────────────────────────────────────────────────────────────────────────────────

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAllyAbility)
  BattleHandlers::DamageCalcTargetAllyAbility.add(:SWORDOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.physicalMove?
      next if target.hasActiveAbility?(:SWORDOFRUIN)
      mults[:defense_multiplier] *= 0.75
    }
  )
end

#===============================================================================
# TABLETS OF RUIN
# Reduces the Attack of all other Pokémon on the field by 25%.
# The holder itself is unaffected. Other Tablets of Ruin holders are also exempt.
#
# Mirror of BEADS OF RUIN — but Attack (physical) instead of Sp. Def.
# Because Attack is an attacker-side stat, the handler set flips:
#   attack_multiplier on the user is reduced (not defense_multiplier on target).
#
# Coverage:
#   DamageCalcTargetAbility     — enemy attacks the HOLDER → user's Atk -25%
#   DamageCalcTargetAllyAbility — enemy attacks HOLDER'S ALLY → user's Atk -25%
#   DamageCalcUserAllyAbility   — HOLDER'S ALLY attacks → ally's own Atk -25%
#     (ally doesn't have TABLETS, so their Attack is reduced)
#
# DamageCalcUserAbility intentionally OMITTED: holder's own Attack is not reduced.
# Exemption guard skips fellow TABLETS OF RUIN holders.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:TABLETSOFRUIN,
    proc { |ability, battler, battle|
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1}'s Tablets of Ruin weakened all other Pokémon's Attack!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    }
  )
end

# Enemy attacks the holder: reduce attacker's physical attack
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAbility)
  BattleHandlers::DamageCalcTargetAbility.add(:TABLETSOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.physicalMove?
      next if user.hasActiveAbility?(:TABLETSOFRUIN)
      mults[:attack_multiplier] *= 0.75
    }
  )
end

# Enemy attacks holder's ally: reduce attacker's physical attack
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAllyAbility)
  BattleHandlers::DamageCalcTargetAllyAbility.add(:TABLETSOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.physicalMove?
      next if user.hasActiveAbility?(:TABLETSOFRUIN)
      mults[:attack_multiplier] *= 0.75
    }
  )
end

# Holder's ally attacks: reduce ally's own physical attack if ally lacks TABLETS
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAllyAbility)
  BattleHandlers::DamageCalcUserAllyAbility.add(:TABLETSOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.physicalMove?
      next if user.hasActiveAbility?(:TABLETSOFRUIN)
      mults[:attack_multiplier] *= 0.75
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# TANGLING HAIR
# ────────────────────────────────────────────────────────────────────────────────
# Fully handled by base engine:
#   TargetAbilityOnHit.copy(:GOOEY, :TANGLINGHAIR) at line 1453 of
#   003_BattleHandlers_Abilities.rb — lowers the attacker's Speed by 1 stage
#   when they make contact with the holder.
# No code needed here.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# TERA SHELL
# ────────────────────────────────────────────────────────────────────────────────
# While at full HP, all damaging moves that hit the holder are treated as
# not very effective (0.5x), regardless of type matchup.
# Immunities (typeMod = 0) are preserved — TERA SHELL does not override them.
# Already-resisted moves (typeMod < NORMAL_EFFECTIVE) are also unchanged.
# Uses NonIgnorable so Mold Breaker cannot bypass it (same as Shadow Shield).
#
# Implementation: sets target.damageState.typeMod = NORMAL_EFFECTIVE / 2 (= 4)
# directly. Since NonIgnorable fires at line 298 of 003_Move_Usage_Calculations,
# before line 429 where typeMod is applied to final_damage_multiplier, this
# correctly caps the type contribution to 4/8 = 0.5x. The engine's effectiveness
# message system also reads typeMod, so "not very effective" displays automatically.
#
# Co-op: DamageCalcTargetAbilityNonIgnorable fires per defender — all positions.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAbilityNonIgnorable)
  BattleHandlers::DamageCalcTargetAbilityNonIgnorable.add(:TERASHELL,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless target.hp == target.totalhp
      next if Effectiveness.ineffective?(target.damageState.typeMod)
      next if Effectiveness.not_very_effective?(target.damageState.typeMod)
      # Neutral or super effective → cap typeMod to give 0.5x (not very effective)
      target.damageState.typeMod = Effectiveness::NORMAL_EFFECTIVE / 2
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# THERMAL EXCHANGE
# ────────────────────────────────────────────────────────────────────────────────
# Grants immunity to burns.
# Raises the holder's Attack by 1 stage when hit by a Fire-type move.
# Co-op: both handlers fire per-battler — all positions covered.
# Type Infusion: move.calcType is post-infusion — a move converted to Fire
#   triggers the Attack boost correctly.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::StatusImmunityAbility)
  BattleHandlers::StatusImmunityAbility.add(:THERMALEXCHANGE,
    proc { |ability, battler, status|
      next true if status == :BURN
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.add(:THERMALEXCHANGE,
    proc { |ability, user, target, move, battle|
      next unless move.calcType == :FIRE
      target.pbRaiseStatStageByAbility(:ATTACK, 1, target,
                                       GameData::Ability.get(ability).real_name)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# TOUGH CLAWS
# ────────────────────────────────────────────────────────────────────────────────
# Boosts the power of contact moves by 1.3x.
# Co-op: fires per-user battler — all positions covered.
# Type Infusion: no interaction; multiplier applies regardless of type.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:TOUGHCLAWS,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.contactMove?
      mults[:base_damage_multiplier] *= 1.3
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# TOXIC BOOST
# ────────────────────────────────────────────────────────────────────────────────
# Boosts the power of physical moves by 1.5x when the user is poisoned or
# badly poisoned. Mirror of Flare Boost (special/burn).
# Co-op: fires per-user battler — all positions covered.
# Type Infusion: no interaction; multiplier applies regardless of type.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:TOXICBOOST,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.physicalMove?
      next unless [:POISON, :TOXIC].include?(user.status)
      mults[:base_damage_multiplier] *= 1.5
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# TOXIC CHAIN
# ────────────────────────────────────────────────────────────────────────────────
# 30% chance to badly poison the target on any hit (not contact-only).
# Respects Shield Dust. Pattern mirrors Poison Touch but with toxic = true
# and no contact move requirement.
# Co-op: UserAbilityOnHit fires per-user battler — all positions covered.
# Type Infusion: no interaction.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::UserAbilityOnHit)
  BattleHandlers::UserAbilityOnHit.add(:TOXICCHAIN,
    proc { |ability, user, target, move, battle|
      next if battle.pbRandom(100) >= 30
      battle.pbShowAbilitySplash(user)
      if target.hasActiveAbility?(:SHIELDDUST) && !battle.moldBreaker
        battle.pbShowAbilitySplash(target)
        battle.pbDisplay(_INTL("{1} is unaffected!", target.pbThis)) if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbHideAbilitySplash(target)
      elsif target.pbCanPoison?(user, PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
        msg = nil
        if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          msg = _INTL("{1}'s {2} badly poisoned {3}!", user.pbThis, user.abilityName, target.pbThis(true))
        end
        target.pbPoison(user, msg, true)
      end
      battle.pbHideAbilitySplash(user)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# TOXIC DEBRIS
# ────────────────────────────────────────────────────────────────────────────────
# When the holder is hit by a physical move, scatters Toxic Spikes on the
# attacker's side (up to 2 layers). Silent if already at 2 layers.
# Co-op: TargetAbilityOnHit fires per-target battler — all positions covered.
# Type Infusion: no interaction.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.add(:TOXICDEBRIS,
    proc { |ability, user, target, move, battle|
      next unless move.physicalMove?
      next if user.pbOwnSide.effects[PBEffects::ToxicSpikes] >= 2
      battle.pbShowAbilitySplash(target)
      user.pbOwnSide.effects[PBEffects::ToxicSpikes] += 1
      battle.pbDisplay(_INTL("Poison spikes were scattered all around {1}'s feet!", user.pbTeam(true)))
      battle.pbHideAbilitySplash(target)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# TRANSISTOR
# ────────────────────────────────────────────────────────────────────────────────
# Boosts the power of Electric-type moves by 1.5x.
# Co-op: fires per-user battler — all positions covered.
# Type Infusion: type parameter is post-infusion — a move converted to Electric
#   (e.g. Galvanize) receives the boost correctly.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:TRANSISTOR,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless type == :ELECTRIC
      mults[:base_damage_multiplier] *= 1.5
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# UNSEEN FIST
# ────────────────────────────────────────────────────────────────────────────────
# Contact moves bypass protection (Protect, King's Shield, Spiky Shield,
# Baneful Bunker, Mat Block, Quick Guard, Wide Guard).
#
# Implementation: alias pbSuccessCheckAgainstTarget on PokeBattle_Battler.
# Before calling the original, set @npt_unseen_fist_bypass on the move object
# when user has UNSEENFIST and move is contact. canProtectAgainst? is also
# aliased to return false when that flag is set — the entire protect block
# in the original method is then skipped. Flag is cleared via ensure.
#
# Co-op: pbSuccessCheckAgainstTarget is called per user/target pair —
#   all positions covered naturally.
# Type Infusion: no interaction.
# ────────────────────────────────────────────────────────────────────────────────
class PokeBattle_Move
  alias npt_unseenfist_old_canProtectAgainst canProtectAgainst?
  def canProtectAgainst?
    return false if instance_variable_defined?(:@npt_unseen_fist_bypass) && @npt_unseen_fist_bypass
    npt_unseenfist_old_canProtectAgainst
  end
end

class PokeBattle_Battler
  alias npt_unseenfist_pbSuccessCheckAgainstTarget pbSuccessCheckAgainstTarget
  def pbSuccessCheckAgainstTarget(move, user, target)
    move.instance_variable_set(:@npt_unseen_fist_bypass,
      user.hasActiveAbility?(:UNSEENFIST) && move.contactMove?)
    npt_unseenfist_pbSuccessCheckAgainstTarget(move, user, target)
  ensure
    move.instance_variable_set(:@npt_unseen_fist_bypass, false)
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# TRIAGE
# ────────────────────────────────────────────────────────────────────────────────
# Gives healing moves +3 priority.
#
# Base engine already implements this:
#   003_BattleHandlers_Abilities.rb line 530
#   PriorityChangeAbility.add(:TRIAGE) { next pri+3 if move.healingMove? }
# No additional code needed.
# ────────────────────────────────────────────────────────────────────────────────

#===============================================================================
# VESSEL OF RUIN
# Reduces the Sp. Atk of all other Pokémon on the field by 25%.
# The holder itself is unaffected. Other Vessel of Ruin holders are also exempt.
#
# Mirror of TABLETS OF RUIN — but Sp. Atk (special) instead of Attack (physical).
# Coverage:
#   DamageCalcTargetAbility     — enemy attacks the HOLDER → user's SpAtk -25%
#   DamageCalcTargetAllyAbility — enemy attacks HOLDER'S ALLY → user's SpAtk -25%
#   DamageCalcUserAllyAbility   — HOLDER'S ALLY attacks → ally's own SpAtk -25%
#     (ally doesn't have VESSEL, so their Sp. Atk is reduced)
#
# DamageCalcUserAbility intentionally OMITTED: holder's own Sp. Atk is not reduced.
# Exemption guard skips fellow Vessel of Ruin holders.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:VESSELOFRUIN,
    proc { |ability, battler, battle|
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1}'s Vessel of Ruin weakened all other Pokémon's Sp. Atk!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    }
  )
end

# Enemy attacks the holder: reduce attacker's special attack
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAbility)
  BattleHandlers::DamageCalcTargetAbility.add(:VESSELOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.specialMove?
      next if user.hasActiveAbility?(:VESSELOFRUIN)
      mults[:attack_multiplier] *= 0.75
    }
  )
end

# Enemy attacks holder's ally: reduce attacker's special attack
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAllyAbility)
  BattleHandlers::DamageCalcTargetAllyAbility.add(:VESSELOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.specialMove?
      next if user.hasActiveAbility?(:VESSELOFRUIN)
      mults[:attack_multiplier] *= 0.75
    }
  )
end

# Holder's ally attacks: reduce ally's own special attack if ally lacks VESSEL
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAllyAbility)
  BattleHandlers::DamageCalcUserAllyAbility.add(:VESSELOFRUIN,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless move.specialMove?
      next if user.hasActiveAbility?(:VESSELOFRUIN)
      mults[:attack_multiplier] *= 0.75
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# WANDERING SPIRIT
# ────────────────────────────────────────────────────────────────────────────────
# When the holder is hit by a contact move, it swaps its ability with the
# attacker's ability. The attacker gains Wandering Spirit; the holder gains
# the attacker's original ability.
#
# Based on MUMMY (TargetAbilityOnHit pattern) but bidirectional:
#   user.ability  ← :WANDERINGSPIRIT
#   target.ability ← user's old ability
# Both sides get pbOnAbilityChanged called after the swap.
#
# Skip conditions (matching Mummy):
#   - Non-contact move
#   - Attacker fainted
#   - Attacker's ability is unstoppable (can't be overwritten)
#   - Attacker already has Wandering Spirit
#   - Attacker is not affected by contact effects (Shield Dust etc.)
#
# Co-op: TargetAbilityOnHit fires per-target battler — all positions covered.
# Type Infusion: no interaction.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.add(:WANDERINGSPIRIT,
    proc { |ability, user, target, move, battle|
      next unless move.pbContactMove?(user)
      next if user.fainted?
      next if user.unstoppableAbility? || user.ability == ability
      next unless user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      old_user_abil = user.ability
      battle.pbShowAbilitySplash(target) if user.opposes?(target)
      battle.pbShowAbilitySplash(user, true, false) if user.opposes?(target)
      user.ability = ability
      target.ability = old_user_abil
      battle.pbReplaceAbilitySplash(user) if user.opposes?(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s Ability became {2}!", user.pbThis, user.abilityName))
        battle.pbDisplay(_INTL("{1}'s Ability became {2}!", target.pbThis, target.abilityName))
      else
        battle.pbDisplay(_INTL("{1}'s and {2}'s Abilities were swapped!", user.pbThis, target.pbThis(true)))
      end
      battle.pbHideAbilitySplash(user) if user.opposes?(target)
      battle.pbHideAbilitySplash(target) if user.opposes?(target)
      user.pbOnAbilityChanged(ability)
      target.pbOnAbilityChanged(:WANDERINGSPIRIT)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# WIND POWER
# ────────────────────────────────────────────────────────────────────────────────
# The holder becomes charged (PBEffects::Charge = 2) when:
#   a) Hit by a wind move (TargetAbilityOnHit)
#   b) Uses a wind move itself, e.g. Tailwind (UserAbilityEndOfMove)
# While charged, the engine's existing Charge logic in
#   003_Move_Usage_Calculations.rb line 327 doubles the next Electric-type move.
#
# Wind moves (from Gen 9 list; Sandstorm excluded):
#   Aeroblast, Air Cutter, Bleakwind Storm, Blizzard, Fairy Wind, Gust,
#   Heat Wave, Hurricane, Icy Wind, Petal Blizzard, Sandsear Storm,
#   Springtide Storm, Tailwind, Twister, Whirlwind, Wildbolt Storm
#
# No windMove? method exists in the base engine — defined here on PokeBattle_Move.
# Co-op: both handlers fire per-battler — all positions covered.
# Type Infusion: no interaction (charge is move-agnostic once set).
# ────────────────────────────────────────────────────────────────────────────────
NPT_WIND_MOVES = [
  :AEROBLAST, :AIRCUTTER, :BLEAKWINDSTORM, :BLIZZARD, :FAIRYWIND,
  :GUST, :HEATWAVE, :HURRICANE, :ICYWIND, :PETALBLIZZARD,
  :SANDSEARSTORM, :SPRINGTIDESTORM, :TAILWIND, :TWISTER,
  :WHIRLWIND, :WILDBOLTSTORM
].freeze

class PokeBattle_Move
  def windMove?
    NPT_WIND_MOVES.include?(@id)
  end
end

# Triggered when the holder is hit by a wind move
if defined?(BattleHandlers) && defined?(BattleHandlers::TargetAbilityOnHit)
  BattleHandlers::TargetAbilityOnHit.add(:WINDPOWER,
    proc { |ability, user, target, move, battle|
      next unless move.windMove?
      next if target.effects[PBEffects::Charge] > 0
      battle.pbShowAbilitySplash(target)
      target.effects[PBEffects::Charge] = 2
      battle.pbDisplay(_INTL("{1} became charged due to its {2}!", target.pbThis, target.abilityName))
      battle.pbHideAbilitySplash(target)
    }
  )
end

# Triggered when the holder uses a wind move (e.g. Tailwind)
if defined?(BattleHandlers) && defined?(BattleHandlers::UserAbilityEndOfMove)
  BattleHandlers::UserAbilityEndOfMove.add(:WINDPOWER,
    proc { |ability, user, targets, move, battle|
      next unless move.windMove?
      next if user.effects[PBEffects::Charge] > 0
      battle.pbShowAbilitySplash(user)
      user.effects[PBEffects::Charge] = 2
      battle.pbDisplay(_INTL("{1} became charged due to its {2}!", user.pbThis, user.abilityName))
      battle.pbHideAbilitySplash(user)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# WIND RIDER
# ────────────────────────────────────────────────────────────────────────────────
# Two effects:
#   1. Immune to wind moves; when hit by one, raises Attack by 1 stage.
#   2. When Tailwind takes effect on the holder's side (holder OR ally uses it),
#      raises the holder's Attack by 1 stage.
#
# Effect 1: MoveImmunityTargetAbility — checks windMove?, boosts Attack, blocks.
# Effect 2: Alias PokeBattle_Move_05B#pbEffectGeneral (the Tailwind move class).
#   After Tailwind is set, iterate eachSameSideBattler for Wind Rider holders
#   and boost their Attack. Covers both holder-uses and ally-uses cases.
#
# Co-op: MoveImmunityTargetAbility fires per-target; Tailwind alias iterates all
#   same-side battlers — all positions covered.
# Type Infusion: windMove? checks @id (move identity), not type — immune to
#   any wind move regardless of type conversion.
# ────────────────────────────────────────────────────────────────────────────────

# Effect 1: immune to wind moves, Attack +1
if defined?(BattleHandlers) && defined?(BattleHandlers::MoveImmunityTargetAbility)
  BattleHandlers::MoveImmunityTargetAbility.add(:WINDRIDER,
    proc { |ability, user, target, move, type, battle|
      next false unless move.windMove?
      battle.pbShowAbilitySplash(target)
      if target.pbCanRaiseStatStage?(:ATTACK, target)
        if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          target.pbRaiseStatStage(:ATTACK, 1, target)
        else
          target.pbRaiseStatStageByCause(:ATTACK, 1, target, target.abilityName)
        end
      else
        if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
        else
          battle.pbDisplay(_INTL("{1}'s {2} made {3} ineffective!",
                                 target.pbThis, target.abilityName, move.name))
        end
      end
      battle.pbHideAbilitySplash(target)
      next true
    }
  )
end

# Effect 2: Tailwind on holder's side boosts Attack of all Wind Rider holders
class PokeBattle_Move_05B
  alias npt_windrider_pbEffectGeneral pbEffectGeneral
  def pbEffectGeneral(user)
    npt_windrider_pbEffectGeneral(user)
    @battle.eachSameSideBattler(user.index) do |b|
      next unless b.hasActiveAbility?(:WINDRIDER)
      next unless b.pbCanRaiseStatStage?(:ATTACK, b)
      @battle.pbShowAbilitySplash(b)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        b.pbRaiseStatStage(:ATTACK, 1, b)
      else
        b.pbRaiseStatStageByCause(:ATTACK, 1, b, b.abilityName)
      end
      @battle.pbHideAbilitySplash(b)
    end
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# WELL-BAKED BODY
# ────────────────────────────────────────────────────────────────────────────────
# Immune to Fire-type moves. When hit by one, raises Defense by 2 stages.
# Pattern identical to Motor Drive (:ELECTRIC/:SPEED/+1) but Fire/Defense/+2.
# Co-op: MoveImmunityTargetAbility fires per-target — all positions covered.
# Type Infusion: type parameter is post-infusion — a move converted to Fire
#   triggers the immunity and Defense boost correctly.
# ────────────────────────────────────────────────────────────────────────────────
if defined?(BattleHandlers) && defined?(BattleHandlers::MoveImmunityTargetAbility)
  BattleHandlers::MoveImmunityTargetAbility.add(:WELLBAKEDBODY,
    proc { |ability, user, target, move, type, battle|
      next pbBattleMoveImmunityStatAbility(user, target, move, type, :FIRE, :DEFENSE, 2, battle)
    }
  )
end

# ────────────────────────────────────────────────────────────────────────────────
# WATER BUBBLE
# ────────────────────────────────────────────────────────────────────────────────
# Halves damage from Fire-type moves; doubles power of Water-type moves;
# prevents and cures burn.
#
# Base engine already implements all effects:
#   003_BattleHandlers_Abilities.rb line 172
#   StatusImmunityAbility.copy(:WATERVEIL, :WATERBUBBLE)   — burn immunity
#   StatusCureAbility.copy(:WATERVEIL, :WATERBUBBLE)       — cure burn on gain
#   DamageCalcUserAbility.add(:WATERBUBBLE)  line 1105     — Water moves ×2
#   DamageCalcTargetAbility.add(:WATERBUBBLE) line 1205    — Fire moves ×0.5
# No additional code needed.
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
# VICTORY STAR
# ────────────────────────────────────────────────────────────────────────────────
# Boosts the accuracy of moves used by the holder and its allies by 1.1x.
#
# Base engine already implements this:
#   003_BattleHandlers_Abilities.rb line 794
#   AccuracyCalcUserAbility.add(:VICTORYSTAR)  { mods[:accuracy_multiplier] *= 1.1 }
#   AccuracyCalcUserAllyAbility.add(:VICTORYSTAR) { mods[:accuracy_multiplier] *= 1.1 }
# No additional code needed.
# ────────────────────────────────────────────────────────────────────────────────

#===============================================================================
# AS ONE
# Both variants block opposing Berry use. Calyrex-Ice receives Chilling
# Neigh's Attack boost after a knockout, while Calyrex-Shadow receives Grim
# Neigh's Special Attack boost.
#
# Co-op: canConsumeBerry? already loops opponents via pbCheckOpposingAbility.
# Type Infusion: post-KO stat boost — no interaction.
#===============================================================================

# Unnerve component — block berry consumption when opponent has As One
class PokeBattle_Battler
  alias reloaded_as_one_canConsumeBerry? canConsumeBerry? unless method_defined?(:reloaded_as_one_canConsumeBerry?)
  def canConsumeBerry?
    return false if @battle.pbCheckOpposingAbility(:ASONEGLASTRIER, @index)
    return false if @battle.pbCheckOpposingAbility(:ASONESPECTRIER, @index)
    reloaded_as_one_canConsumeBerry?
  end
end

# Switch-in announcement
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  as_one_switch_handler = proc { |ability, battler, battle|
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1} has two Abilities!", battler.pbThis))
      battle.pbDisplay(_INTL("{1} is too nervous to eat Berries!", battler.pbOpposingTeam))
      battle.pbHideAbilitySplash(battler)
    }
  BattleHandlers::AbilityOnSwitchIn.add(:ASONEGLASTRIER, as_one_switch_handler)
  BattleHandlers::AbilityOnSwitchIn.add(:ASONESPECTRIER, as_one_switch_handler)
end

# Chilling Neigh component — Atk +1 on KO (same as Chilling Neigh handler)
if defined?(BattleHandlers) && defined?(BattleHandlers::UserAbilityEndOfMove)
  BattleHandlers::UserAbilityEndOfMove.add(:ASONEGLASTRIER,
    proc { |ability, user, targets, move, battle|
      next if battle.pbAllFainted?(user.idxOpposingSide)
      next unless targets.any? { |b| b.damageState.fainted }
      next unless user.pbCanRaiseStatStage?(:ATTACK, user)
      user.pbRaiseStatStageByAbility(:ATTACK, 1, user)
    }
  )
  BattleHandlers::UserAbilityEndOfMove.add(:ASONESPECTRIER,
    proc { |ability, user, targets, move, battle|
      next if battle.pbAllFainted?(user.idxOpposingSide)
      next unless targets.any? { |b| b.damageState.fainted }
      next unless user.pbCanRaiseStatStage?(:SPECIAL_ATTACK, user)
      user.pbRaiseStatStageByAbility(:SPECIAL_ATTACK, 1, user)
    }
  )
end

#===============================================================================
# BATTLE BOND (Greninja)
# After KOing a Pokémon, Greninja form 1 → form 2 (Ash-Greninja).
#
# The base engine handles this in 010_Battler_UseMove_TriggerEffects.rb:103-118
# but uses pbChangeForm which calls the NO-OP form=.
# Fix: The FORM CHANGE FIX alias below patches pbChangeForm to use form_simple=.
#===============================================================================

#===============================================================================
# ZEN MODE (Darmanitan)
# Below 50% HP → form 1 (Zen Mode). Above 50% → form 0 (Standard).
#
# Base engine handles this in 003_Battler_ChangeSelf.rb:219-232.
# Same pbChangeForm NO-OP issue — fixed by the shared alias below.
#===============================================================================

#===============================================================================
# POWER CONSTRUCT (Zygarde)
# At ≤50% HP at end of round, Zygarde transforms to Complete Forme (form +2).
#
# Base engine handles this in 003_Battler_ChangeSelf.rb:264-273.
# Same pbChangeForm NO-OP issue — fixed by the shared alias below.
#===============================================================================

#===============================================================================
# FORM CHANGE FIX — pbChangeForm alias
# The base engine's pbChangeForm calls `self.form = newForm` which delegates to
# Pokemon#form= — a NO-OP (all code commented out). This breaks ALL in-battle
# form changes (Zen Mode, Power Construct, Battle Bond, Minior, etc.).
#
# Fix: alias pbChangeForm to also call form_simple= on the underlying Pokemon
# object, which directly writes @form and calls calc_stats.
#
# Note: The Schooling fix above pre-sets @form before calling the original
# pbCheckForm, then calls form_simple= manually. This alias is a general fix
# for all OTHER pbChangeForm calls (Zen Mode, Power Construct, Minior, etc.).
#===============================================================================
class PokeBattle_Battler
  alias npt_formfix_pbChangeForm pbChangeForm
  def pbChangeForm(newForm, msg)
    return if fainted? || @effects[PBEffects::Transform] || @form == newForm
    # Call original (sets @form on battler, displays message, refreshes scene)
    npt_formfix_pbChangeForm(newForm, msg)
    # Fix: also write form to the underlying Pokemon via form_simple=
    @pokemon.form_simple = newForm if @pokemon
  end
end

#===============================================================================
# COMMANDER (Tatsugiri + Dondozo)  —  Fully faithful implementation
#
# When Tatsugiri switches in alongside Dondozo:
#   1. Tatsugiri "enters" Dondozo (sprite + databox hidden)
#   2. Tatsugiri becomes untargetable (all moves auto-miss)
#   3. Tatsugiri cannot switch out
#   4. Dondozo gets +2 to Atk/Def/SpA/SpD/Spe
#   5. When Dondozo faints, Tatsugiri is released (sprite returns)
#   6. Tatsugiri can still select and use moves from inside Dondozo
#
# Co-op: Uses eachSameSideBattler so cross-player pairs work.
#
# Tracking: We use instance variables on the battler objects rather than
# PBEffects to avoid touching the core effects table:
#   @npt_commander_host  = index of Dondozo (set on Tatsugiri)
#   @npt_commander_rider = index of Tatsugiri (set on Dondozo)
#===============================================================================

# --- Add accessors to PokeBattle_Battler ---
class PokeBattle_Battler
  attr_accessor :npt_commander_host   # Tatsugiri stores Dondozo's battler index
  attr_accessor :npt_commander_rider  # Dondozo stores Tatsugiri's battler index

  def npt_inside_commander?
    return !@npt_commander_host.nil?
  end

  def npt_has_commander_rider?
    return !@npt_commander_rider.nil?
  end
end

# --- Helper: hide Tatsugiri sprite + databox ---
def npt_commander_hide_battler(battler, battle)
  scene = battle.scene
  idx = battler.index
  # Hide sprite
  sprite = scene.sprites["pokemon_#{idx}"] rescue nil
  if sprite
    sprite.visible = false
    sprite.instance_variable_set(:@spriteVisible, false) if sprite.respond_to?(:visible=)
  end
  # Hide shadow
  shadow = scene.sprites["shadow_#{idx}"] rescue nil
  shadow.visible = false if shadow
  # Hide databox
  databox = scene.sprites["dataBox_#{idx}"] rescue nil
  databox.visible = false if databox
end

# --- Helper: show Tatsugiri sprite + databox ---
def npt_commander_show_battler(battler, battle)
  return if battler.fainted?
  scene = battle.scene
  idx = battler.index
  # Show sprite
  sprite = scene.sprites["pokemon_#{idx}"] rescue nil
  if sprite
    sprite.visible = true
    sprite.instance_variable_set(:@spriteVisible, true) if sprite.respond_to?(:visible=)
  end
  # Show shadow
  shadow = scene.sprites["shadow_#{idx}"] rescue nil
  shadow.visible = true if shadow
  # Show databox
  databox = scene.sprites["dataBox_#{idx}"] rescue nil
  databox.visible = true if databox
end

# --- 1. Switch-in: Tatsugiri enters Dondozo ---
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:COMMANDER,
    proc { |ability, battler, battle|
      # Only Tatsugiri (or a fusion containing Tatsugiri) activates Commander
      is_tatsugiri = (battler.isSpecies?(:TATSUGIRI) rescue false) ||
                     (battler.isFusionOf(:TATSUGIRI) rescue false)
      next unless is_tatsugiri
      # Don't activate if already inside a Dondozo
      next if battler.npt_inside_commander?
      # Find allied Dondozo (or fusion containing Dondozo) that doesn't already have a rider
      ally = nil
      battle.eachSameSideBattler(battler.index) do |b|
        next if b.index == battler.index
        is_dondozo = (b.isSpecies?(:DONDOZO) rescue false) ||
                     (b.isFusionOf(:DONDOZO) rescue false)
        next unless is_dondozo
        next if b.fainted?
        next if b.npt_has_commander_rider?
        ally = b
        break
      end
      next unless ally
      # Link the pair
      battler.npt_commander_host  = ally.index
      ally.npt_commander_rider    = battler.index
      # Show ability splash + message
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1} went inside {2}!", battler.pbThis, ally.pbThis(true)))
      battle.pbHideAbilitySplash(battler)
      # Hide Tatsugiri sprite + databox
      npt_commander_hide_battler(battler, battle)
      # Boost Dondozo's stats by +2
      [:ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED].each do |stat|
        ally.pbRaiseStatStage(stat, 2, battler, false) if ally.pbCanRaiseStatStage?(stat, battler)
      end
    }
  )
end

# --- 2. Release Tatsugiri when Dondozo faints ---
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnBattlerFainting)
  BattleHandlers::AbilityOnBattlerFainting.add(:COMMANDER,
    proc { |ability, battler, fainted, battle|
      # battler = the one with this ability (Tatsugiri)
      # fainted = the battler that just fainted
      next unless battler.npt_inside_commander?
      next unless battler.npt_commander_host == fainted.index
      # Dondozo fainted — release Tatsugiri
      battler.npt_commander_host = nil
      fainted.npt_commander_rider = nil
      npt_commander_show_battler(battler, battle)
      battle.pbDisplay(_INTL("{1} came out of {2}!", battler.pbThis, fainted.pbThis(true)))
    }
  )
end

# --- 3. Make Tatsugiri untargetable while inside Dondozo ---
# Override accuracy check: all moves auto-miss Tatsugiri while commanding
class PokeBattle_Battler
  alias _npt_commander_pbSuccessCheckAgainstTarget pbSuccessCheckAgainstTarget
  def pbSuccessCheckAgainstTarget(move, user, target)
    if target.npt_inside_commander? && target.index != user.index
      @battle.pbDisplay(_INTL("{1} avoided the attack by hiding inside Dondozo!", target.pbThis))
      return false
    end
    return _npt_commander_pbSuccessCheckAgainstTarget(move, user, target)
  end
end

# --- 4. Prevent Tatsugiri from being switched out while inside ---
class PokeBattle_Battle
  alias _npt_commander_canswitch pbCanSwitch?
  def pbCanSwitch?(idxBattler, idxParty = -1, partyScene = nil)
    battler = @battlers[idxBattler]
    if battler && !battler.fainted? && battler.npt_inside_commander?
      partyScene.pbDisplay(_INTL("{1} can't be switched out while inside Dondozo!",
                                  battler.pbThis)) if partyScene
      return false
    end
    return _npt_commander_canswitch(idxBattler, idxParty, partyScene)
  end
end

# --- 5. Release Tatsugiri when Dondozo is recalled/replaced ---
class PokeBattle_Battle
  alias _npt_commander_pbReplace pbReplace
  def pbReplace(idxBattler, idxParty, batonPass = false)
    old_battler = @battlers[idxBattler]
    if old_battler && old_battler.npt_has_commander_rider?
      rider_idx = old_battler.npt_commander_rider
      rider = @battlers[rider_idx]
      if rider && !rider.fainted? && rider.npt_inside_commander?
        rider.npt_commander_host = nil
        old_battler.npt_commander_rider = nil
        npt_commander_show_battler(rider, self)
        pbDisplay(_INTL("{1} came out of {2}!", rider.pbThis, old_battler.pbThis(true)))
      end
    end
    _npt_commander_pbReplace(idxBattler, idxParty, batonPass)
  end
end

# --- 6. Keep Tatsugiri hidden after end-of-round sprite refreshes ---
# The battle scene can re-show sprites on refresh; override update to re-hide
class PokeBattle_Battler
  alias _npt_commander_pbUpdate pbUpdate
  def pbUpdate(fullChange = false)
    _npt_commander_pbUpdate(fullChange)
    if npt_inside_commander?
      npt_commander_hide_battler(self, @battle)
    end
  end
end

# --- 7. Clean up Commander state when battle ends ---
# (pbEndOfBattle resets pokemon forms; we just clear the ivars)
class PokeBattle_Battler
  alias _npt_commander_pbInitEffects pbInitEffects
  def pbInitEffects(batonPass)
    _npt_commander_pbInitEffects(batonPass)
    @npt_commander_host  = nil
    @npt_commander_rider = nil
  end
end

#===============================================================================
# RKS SYSTEM (Silvally)
# Changes Silvally's type based on held Memory item.
# Fully handled by MultipleForms.register(:SILVALLY) in 001_FormHandlers.rb.
# The overworld form handler sets the form, and battler initialization reads it.
# No battle handler needed.
#===============================================================================

#===============================================================================
# TERA SHIFT (Terapagos)
# On switch-in, Terapagos changes from Normal Form (form 0) to Terastal Form
# (form 1).
#===============================================================================
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:TERASHIFT,
    proc { |ability, battler, battle|
      next unless (battler.isSpecies?(:TERAPAGOS) rescue false)
      next if battler.form != 0
      battle.pbShowAbilitySplash(battler)
      battler.pbChangeForm(1, _INTL("{1} transformed!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    }
  )
end

#===============================================================================
# TERAFORM ZERO (Terapagos)
# On switch-in, clears all weather and terrain effects.
#===============================================================================
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:TERAFORMZERO,
    proc { |ability, battler, battle|
      changed = false
      # Clear weather
      if battle.field.weather != :None
        battle.pbShowAbilitySplash(battler)
        battle.field.weather         = :None
        battle.field.weatherDuration = 0
        battle.pbDisplay(_INTL("The effects of the weather disappeared."))
        changed = true
      end
      # Clear terrain
      if battle.field.terrain != :None
        battle.pbShowAbilitySplash(battler) unless changed
        battle.field.terrain         = :None
        battle.field.terrainDuration = 0
        battle.pbDisplay(_INTL("The effects of the terrain disappeared."))
        changed = true
      end
      battle.pbHideAbilitySplash(battler) if changed
    }
  )
end

#===============================================================================
# ZERO TO HERO (Palafin)
# Palafin changes from Zero Form (form 0) to Hero Form (form 1) when it
# switches in after having been switched out at least once during the battle.
# Tracks switch-out via an instance variable on the Pokemon object.
#===============================================================================
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchOut)
  BattleHandlers::AbilityOnSwitchOut.add(:ZEROTOHERO,
    proc { |ability, battler, endOfBattle|
      next if endOfBattle
      # Mark that this Pokemon has been switched out
      battler.pokemon.instance_variable_set(:@zero_to_hero_switched, true) if battler.pokemon
    }
  )
end

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:ZEROTOHERO,
    proc { |ability, battler, battle|
      # Only transform if previously switched out
      next unless (battler.pokemon.instance_variable_get(:@zero_to_hero_switched) rescue false)
      is_fusion = (battler.pokemon.isFusion? rescue false)
      is_palafin = (battler.isSpecies?(:PALAFIN) rescue false) ||
                   (battler.isFusionOf(:PALAFIN) rescue false)
      next unless is_palafin
      if is_fusion
        # Fusion: swap Palafin component → Palafin Hero (PALAFIN_1) for stats
        # Sprite stays unchanged (fusion sprite)
        next if battler.pokemon.instance_variable_get(:@zero_hero_transformed)
        battler.pokemon.instance_variable_set(:@zero_hero_transformed, true)
        battle.pbShowAbilitySplash(battler)
        battler.pokemon.changeFormSpecies(:PALAFIN, :PALAFIN_1)
        battler.pbUpdate(true)
        battle.pbDisplay(_INTL("{1} underwent a heroic transformation!", battler.pbThis))
        battle.pbHideAbilitySplash(battler)
      else
        # Pure Palafin: form 0 → 1, sprite changes
        next if battler.form != 0
        battle.pbShowAbilitySplash(battler)
        battler.pbChangeForm(1, _INTL("{1} underwent a heroic transformation!", battler.pbThis))
        battle.pbHideAbilitySplash(battler)
      end
    }
  )
end

#===============================================================================
# RECEIVER
# When an ally faints, the holder copies the fainted ally's ability.
# Base engine already handles this — AbilityChangeOnBattlerFainting.copy copies
# the POWEROFALCHEMY handler to RECEIVER (003_BattleHandlers_Abilities.rb:2411).
# No additional code needed.
#===============================================================================

#===============================================================================
# MERCILESS — guaranteed critical hit on poisoned targets
#
# The base engine registers a CriticalCalcUserAbility handler for :MERCILESS
# (003_BattleHandlers_Abilities.rb:1253) that sets c=99, caught by the
# `return true if c>50` check in pbIsCritical?.
#
# BUG: triggerCriticalCalcUserAbility receives `user.ability` which is a
# GameData::Ability object, but the handler hash is keyed by Symbol
# (:MERCILESS). GameData::Ability doesn't override eql?/hash, so Ruby's
# Hash#[] never finds the handler. This affects all CriticalCalcUserAbility
# handlers but is only noticeable for Merciless (guaranteed crit vs.
# probability boost).
#
# Fix: directly alias pbIsCritical? to check for Merciless before the
# normal flow. This bypasses the broken handler lookup entirely.
#===============================================================================
class PokeBattle_Move
  alias _npt_merciless_orig_pbIsCritical pbIsCritical? if !method_defined?(:_npt_merciless_orig_pbIsCritical)

  def pbIsCritical?(user, target)
    if user.abilityActive? && user.ability_id == :MERCILESS && target.poisoned?
      return true
    end
    _npt_merciless_orig_pbIsCritical(user, target)
  end
end
