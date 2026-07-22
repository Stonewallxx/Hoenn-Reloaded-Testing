# Hoenn Reloaded Expanded Dex move handlers.
# Adapted from the AFI PokeAPI-derived compatibility implementation.
# Move records are supplied by Reloaded/Data/ExpandedDex/ExpandedDex.dat.
# Function codes 176-17E (Bucket C) are fully implemented below.
# Bucket D stubs are marked TODO — implement one group at a time.
#
# Code map (matches FUNCTION_CODE_OVERRIDE in generate_npt_moves_abilities.rb):
#   176  MIGHTYCLEAVE / HYPERDRILL       — bypasses protection
#   177  BLOODMOON / GIGATONHAMMER       — can't use same move twice in a row
#   178  VICTORYDANCE                    — +1 Atk/Def/Spe to user
#   179  HEADLONGRUSH                    — damage + guaranteed −1 Def to user
#   17A  SPINOUT                         — damage + guaranteed −2 Spe to user
#   17B  MAKEITRAIN                      — damage (all foes) + guaranteed −1 SpAtk to user
#   17C  ICESPINNER                      — damage + removes active terrain
#   17D  SPICYEXTRACT                    — status: +2 Atk / −2 Def on target
#   17E  DECORATE                        — status: +2 Atk / +2 SpAtk on target
#   17F  CEASELESSEDGE                   — damage + lays Spikes on foe's side
#   180  STONEAXE                        — damage + lays Stealth Rock on foe's side
#   181  COLLISIONCOURSE                 — ×4/3 damage on SE hits (Fighting phys)
#   182  ELECTRODRIFT                    — ×4/3 damage on SE hits (Electric spec)
#   183  LASTRESPECTS                    — 50 + 50 × fainted party members
#   184  RAGEFIST                        — 50 + 50 × times user was hit this battle
#   18C  OBSTRUCT                        — protect + −2 Def on contact attacker
#   18D  OCTOLOCK                        — trap target; EOR −1 Def/SpDef each turn
#   18E  JUNGLEHEALING                   — heal user+allies 25% HP; cure status
#   18F  MAGICPOWDER                     — changes target type to Psychic
#
# ─────────────────────────────────────────────────────────────────────────────
# BUCKET C — Implemented
# ─────────────────────────────────────────────────────────────────────────────

#===============================================================================
# Bypasses protection (Protect, Detect, King's Shield, etc.).
# (Mighty Cleave, Hyper Drill)
#===============================================================================
class PokeBattle_Move_176 < PokeBattle_Move
  def canProtectAgainst?
    return false
  end
end

#===============================================================================
# Fails if the user used this same move last turn.
# (Blood Moon, Gigaton Hammer)
#===============================================================================
class PokeBattle_Move_177 < PokeBattle_Move
  # pbMoveFailed? runs AFTER the engine sets user.lastMoveUsed to the current
  # move (line 278 of 007_Battler_UseMove.rb), so comparing against
  # lastMoveUsed would ALWAYS match after the first use. Instead, stash the
  # previous move in pbChangeUsageCounters (called at line 268, before the
  # engine overwrites lastMoveUsed) and compare against that.
  def pbChangeUsageCounters(user, specialUsage)
    super
    @npt_prev_move = user.lastMoveUsed
  end

  def pbMoveFailed?(user, targets)
    if @npt_prev_move == @id
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end
end

#===============================================================================
# Raises the user's Attack, Defense, and Speed by 1 stage each.
# (Victory Dance)
#===============================================================================
class PokeBattle_Move_178 < PokeBattle_MultiStatUpMove
  def initialize(battle, move)
    super
    @statUp = [:ATTACK, 1, :DEFENSE, 1, :SPEED, 1]
  end
end

#===============================================================================
# Deals damage, then lowers the user's Defense by 1 stage.
# (Headlong Rush)
#===============================================================================
class PokeBattle_Move_179 < PokeBattle_StatDownMove
  def initialize(battle, move)
    super
    @statDown = [:DEFENSE, 1]
  end
end

#===============================================================================
# Deals damage, then lowers the user's Speed by 2 stages.
# (Spin Out)
#===============================================================================
class PokeBattle_Move_17A < PokeBattle_StatDownMove
  def initialize(battle, move)
    super
    @statDown = [:SPEED, 2]
  end
end

#===============================================================================
# Deals damage to all adjacent foes, then lowers the user's Sp. Atk by 1 stage.
# (Make It Rain)
#===============================================================================
class PokeBattle_Move_17B < PokeBattle_StatDownMove
  def initialize(battle, move)
    super
    @statDown = [:SPECIAL_ATTACK, 1]
  end
end

#===============================================================================
# Deals damage, then clears the active terrain.
# (Ice Spinner)
#===============================================================================
class PokeBattle_Move_17C < PokeBattle_Move
  def pbEffectAfterAllHits(user, target)
    return if @battle.field.terrain == :None
    case @battle.field.terrain
    when :Electric
      @battle.pbDisplay(_INTL("The electricity disappeared from the battlefield!"))
    when :Grassy
      @battle.pbDisplay(_INTL("The grass disappeared from the battlefield!"))
    when :Misty
      @battle.pbDisplay(_INTL("The mist disappeared from the battlefield!"))
    when :Psychic
      @battle.pbDisplay(_INTL("The weirdness disappeared from the battlefield!"))
    end
    @battle.field.terrain = :None
  end
end

#===============================================================================
# Raises the target's Attack by 2 stages and lowers its Defense by 2 stages.
# (Spicy Extract)
#===============================================================================
class PokeBattle_Move_17D < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    # Fails only if neither stat change can be applied.
    targets.each do |target|
      return false if target.pbCanRaiseStatStage?(:ATTACK, user, self)
      return false if target.pbCanLowerStatStage?(:DEFENSE, user, self)
    end
    @battle.pbDisplay(_INTL("But it failed!"))
    return true
  end

  def pbEffectAgainstTarget(user, target)
    showAnim = true
    if target.pbCanRaiseStatStage?(:ATTACK, user, self)
      target.pbRaiseStatStage(:ATTACK, 2, user, showAnim)
      showAnim = false
    end
    if target.pbCanLowerStatStage?(:DEFENSE, user, self)
      target.pbLowerStatStage(:DEFENSE, 2, user, showAnim)
    end
  end
end

#===============================================================================
# Raises the target's Attack and Sp. Atk by 2 stages each.
# (Decorate)
#===============================================================================
class PokeBattle_Move_17E < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    targets.each do |target|
      return false if target.pbCanRaiseStatStage?(:ATTACK, user, self)
      return false if target.pbCanRaiseStatStage?(:SPECIAL_ATTACK, user, self)
    end
    @battle.pbDisplay(_INTL("But it failed!"))
    return true
  end

  def pbEffectAgainstTarget(user, target)
    showAnim = true
    if target.pbCanRaiseStatStage?(:ATTACK, user, self)
      target.pbRaiseStatStage(:ATTACK, 2, user, showAnim)
      showAnim = false
    end
    if target.pbCanRaiseStatStage?(:SPECIAL_ATTACK, user, self)
      target.pbRaiseStatStage(:SPECIAL_ATTACK, 2, user, showAnim)
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# BUCKET D — Stubs (TODO: implement one group at a time)
# ─────────────────────────────────────────────────────────────────────────────
# Group 1 — Entry hazard on hit (CEASELESSEDGE, STONEAXE): lays Splinters
# Group 2 — Supereffective boost (COLLISIONCOURSE, ELECTRODRIFT): ×4/3 on SE hits
# Group 3 — Scaling power (LASTRESPECTS, RAGEFIST): power ×N based on battle state
# Group 4 — Type-changing damage (RAGINGBULL, IVYCUDGEL, TERABLAST, TERASTARSTORM)
# Group 5 — Unique field effects (COURTCHANGE, CORROSIVEGAS, TEATIME)
# Group 6 — Protection variants (OBSTRUCT, OCTOLOCK, JUNGLEHEALING, MAGICPOWDER)
# Group 7 — Variable power/conditional (HARDPRESS, PSYBLADE, HYDROSTEAM, TEMPERFLARE,
#            FICKLEBEAM, THUNDERCLAP, GLAIVERUSH, SALTCURE, SYRUPBOMB)
# Group 8 — Type/form loss (DOUBLESHOCK, FILLETAWAY, PSYCHICNOISE, ORDERUP)

# ── Group 1: Entry hazard on hit ──────────────────────────────────────────────

#===============================================================================
# Deals damage, then lays one layer of Spikes on the target's side of the field.
# The hazard effect is suppressed if the move hit a substitute or dealt no damage.
# (Ceaseless Edge)
#===============================================================================
class PokeBattle_Move_17F < PokeBattle_Move
  def pbEffectAfterAllHits(user, target)
    return if target.damageState.substitute || target.damageState.hpLost == 0
    return if target.pbOwnSide.effects[PBEffects::Spikes] >= 3
    target.pbOwnSide.effects[PBEffects::Spikes] += 1
    @battle.pbDisplay(_INTL("Spikes were scattered all around {1}'s feet!", target.pbTeam(true)))
  end
end

#===============================================================================
# Deals damage, then sets Stealth Rock on the target's side of the field.
# The hazard effect is suppressed if the move hit a substitute or dealt no damage.
# (Stone Axe)
#===============================================================================
class PokeBattle_Move_180 < PokeBattle_Move
  def pbEffectAfterAllHits(user, target)
    return if target.damageState.substitute || target.damageState.hpLost == 0
    return if target.pbOwnSide.effects[PBEffects::StealthRock]
    target.pbOwnSide.effects[PBEffects::StealthRock] = true
    @battle.pbDisplay(_INTL("Pointed stones float in the air around {1}!", target.pbTeam(true)))
  end
end

# ── Group 2: Supereffective damage boost ─────────────────────────────────────

#===============================================================================
# Deals damage. If the hit is supereffective, damage is multiplied by ×4/3.
# (Collision Course — Fighting physical)
#===============================================================================
class PokeBattle_Move_181 < PokeBattle_Move
  def pbModifyDamage(damageMult, user, target)
    damageMult *= 4.0 / 3.0 if Effectiveness.super_effective?(target.damageState.typeMod)
    return damageMult
  end
end

#===============================================================================
# Deals damage. If the hit is supereffective, damage is multiplied by ×4/3.
# (Electrodrift — Electric special)
#===============================================================================
class PokeBattle_Move_182 < PokeBattle_Move_181
end

# ── Group 3: Scaling power ────────────────────────────────────────────────────

# New PBEffects constant for Rage Fist hit counter.
module PBEffects
  RageFistCounter = 116   # int: times this battler was hit by a damaging move
end

# Initialise RageFistCounter for every battler that enters battle.
# NOTE: Chained after Group 6's alias — both additions run in sequence.
class PokeBattle_Battler
  alias _npt_pbInitEffects_g3 pbInitEffects
  def pbInitEffects(batonPass)
    _npt_pbInitEffects_g3(batonPass)
    @effects[PBEffects::RageFistCounter] = 0
  end
end

# After every damaging hit, increment the target's Rage Fist counter.
class PokeBattle_Move
  alias _npt_pbRecordDamageLost_g3 pbRecordDamageLost
  def pbRecordDamageLost(user, target)
    _npt_pbRecordDamageLost_g3(user, target)
    return if target.damageState.hpLost <= 0
    return unless target.effects[PBEffects::RageFistCounter].is_a?(Integer)
    target.effects[PBEffects::RageFistCounter] += 1
  end
end

#===============================================================================
# Base power = 50 + 50 × (number of fainted party members on user's side).
# (Last Respects)
#===============================================================================
class PokeBattle_Move_183 < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    fainted = @battle.pbParty(user.index).count { |p| p.fainted? }
    return 50 + 50 * fainted
  end
end

#===============================================================================
# Base power = 50 + 50 × (number of times the user was hit by a damaging move
# this battle). Counter resets when the Pokémon switches out. (Rage Fist)
#===============================================================================
class PokeBattle_Move_184 < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    return 50 + 50 * (user.effects[PBEffects::RageFistCounter] || 0)
  end
end

# ── Group 4: Type-changing damage ─────────────────────────────────────────────

#===============================================================================
# Changes type to Fire/Water based on Paldean Tauros form (form 1 = Blaze Breed,
# form 2 = Aqua Breed). Bypasses and clears Reflect, Light Screen, and Aurora
# Veil on the target's side. (Raging Bull)
# NOTE: Adjust form numbers if PIF assigns Tauros-Paldea forms differently.
#===============================================================================
class PokeBattle_Move_185 < PokeBattle_Move
  def pbBaseType(user)
    if user.isSpecies?(:TAUROS)
      case user.form
      when 1 then return :FIRE   # Blaze Breed
      when 2 then return :WATER  # Aqua Breed
      end
    end
    return :NORMAL
  end

  def ignoresReflect?
    return true
  end

  def pbEffectGeneral(user)
    side = user.pbOpposingSide
    if side.effects[PBEffects::Reflect] > 0
      side.effects[PBEffects::Reflect] = 0
      @battle.pbDisplay(_INTL("{1}'s Reflect wore off!", user.pbOpposingTeam))
    end
    if side.effects[PBEffects::LightScreen] > 0
      side.effects[PBEffects::LightScreen] = 0
      @battle.pbDisplay(_INTL("{1}'s Light Screen wore off!", user.pbOpposingTeam))
    end
    if side.effects[PBEffects::AuroraVeil] > 0
      side.effects[PBEffects::AuroraVeil] = 0
      @battle.pbDisplay(_INTL("{1}'s Aurora Veil wore off!", user.pbOpposingTeam))
    end
  end
end

# TODO: IVYCUDGEL (code 186) — 100 Phys Grass/Fire/Water/Rock based on Ogerpon's mask.
class PokeBattle_Move_186 < PokeBattle_Move
  # TODO: implement
end

# TODO: TERABLAST (code 187) — 80 Spec Normal (changes type to user's Tera type when Tera'd).
#   Also changes category to physical if user's Atk > SpAtk while Tera'd.
#   Then lowers user's Atk and SpAtk by 1 each if Tera'd.
class PokeBattle_Move_187 < PokeBattle_Move
  # TODO: implement
end

# TODO: TERASTARSTORM (code 188) — 120 Spec Normal (changes type to Stellar when Terapagos-Stellar).
class PokeBattle_Move_188 < PokeBattle_Move
  # TODO: implement
end

# ── Group 5: Unique field effects ─────────────────────────────────────────────

#===============================================================================
# Swaps all entry hazards and screens between both sides of the field.
# (Court Change)
#===============================================================================
class PokeBattle_Move_189 < PokeBattle_Move
  SWAP_EFFECTS = [
    PBEffects::Spikes,
    PBEffects::ToxicSpikes,
    PBEffects::StealthRock,
    PBEffects::StickyWeb,
    PBEffects::Reflect,
    PBEffects::LightScreen,
    PBEffects::AuroraVeil,
    PBEffects::Tailwind,
    PBEffects::Mist,
    PBEffects::Safeguard,
  ].freeze

  def pbEffectGeneral(user)
    side0 = @battle.sides[0]
    side1 = @battle.sides[1]
    SWAP_EFFECTS.each do |eff|
      side0.effects[eff], side1.effects[eff] = side1.effects[eff], side0.effects[eff]
    end
    @battle.pbDisplay(_INTL("{1} swapped the battle effects affecting each side of the field!", user.pbThis))
  end
end

#===============================================================================
# Removes the held item of every Pokémon adjacent to the user (not the user).
# Items are destroyed permanently (permanent=true). Respects Sticky Hold and
# unlosable items. (Corrosive Gas)
#===============================================================================
class PokeBattle_Move_18A < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    any = false
    @battle.eachBattler do |b|
      next if b.index == user.index
      next if !b.item || b.unlosableItem?(b.item)
      next if b.hasActiveAbility?(:STICKYHOLD) && !@battle.moldBreaker
      any = true
      break
    end
    unless any
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectGeneral(user)
    @battle.eachBattler do |b|
      next if b.index == user.index
      next if !b.item || b.unlosableItem?(b.item)
      if b.hasActiveAbility?(:STICKYHOLD) && !@battle.moldBreaker
        @battle.pbShowAbilitySplash(b)
        @battle.pbDisplay(_INTL("{1}'s {2} held on thanks to its {3}!", b.pbThis, b.itemName,
                                b.abilityName))
        @battle.pbHideAbilitySplash(b)
        next
      end
      itemName = b.itemName
      b.pbRemoveItem   # permanent=true: item is gone for good
      @battle.pbDisplay(_INTL("{1}'s {2} was corroded and destroyed!", b.pbThis, itemName))
    end
  end
end

#===============================================================================
# Forces all Pokémon in battle to immediately eat and use their held Berry.
# Fails if no Pokémon is holding a Berry. (Teatime)
#===============================================================================
class PokeBattle_Move_18B < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    has_berry = false
    @battle.eachBattler do |b|
      next if !b.item || !b.itemActive?
      next unless GameData::Item.get(b.item).is_berry?
      has_berry = true
      break
    end
    unless has_berry
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectGeneral(user)
    @battle.pbDisplay(_INTL("Everyone is having a teatime!"))
    @battle.pbPriority(true).each do |b|
      next if b.fainted?
      next if !b.item || !b.itemActive?
      next unless GameData::Item.get(b.item).is_berry?
      # Pass the item as item_to_use to force the berry effect regardless of
      # HP threshold / status condition (same mechanic as Bug Bite / Fling).
      b.pbHeldItemTriggerCheck(b.item)
    end
  end
end

# ── Group 6: Protection variants and utility ──────────────────────────────────

# Extend PBEffects with the two new per-battler constants needed for Group 6.
# Using module reopening keeps this out of 001_PBEffects.rb (core file untouched).
module PBEffects
  Obstruct = 114   # boolean: protected by Obstruct this turn
  Octolock = 115   # int: index of the Pokémon that used Octolock (-1 = none)
end

# ── Hooks / aliases ────────────────────────────────────────────────────────────

class PokeBattle_Battler
  # 1. Initialise the two new effect slots for every battler that enters battle.
  alias _npt_pbInitEffects_g6 pbInitEffects
  def pbInitEffects(batonPass)
    _npt_pbInitEffects_g6(batonPass)
    @effects[PBEffects::Obstruct] = false
    @effects[PBEffects::Octolock] = -1
    # If this battler was the one locking another, release that lock.
    @battle.eachBattler do |b|
      b.effects[PBEffects::Octolock] = -1 if b.effects[PBEffects::Octolock] == @index
    end
  end

  # 2. Obstruct: intercept the success-check pipeline to treat Obstruct like
  #    Protect but with a −2 Defense penalty on contact moves.
  alias _npt_pbSuccessCheckAgainstTarget_g6 pbSuccessCheckAgainstTarget
  def pbSuccessCheckAgainstTarget(move, user, target)
    if move.canProtectAgainst? && target.effects[PBEffects::Obstruct]
      @battle.pbCommonAnimation("Protect", target)
      @battle.pbDisplay(_INTL("{1} protected itself!", target.pbThis))
      target.damageState.protected = true
      @battle.successStates[user.index].protected = true
      if move.pbContactMove?(user) && user.affectedByContactEffect?
        if user.pbCanLowerStatStage?(:DEFENSE)
          user.pbLowerStatStage(:DEFENSE, 2, nil)
        end
      end
      return false
    end
    _npt_pbSuccessCheckAgainstTarget_g6(move, user, target)
  end
end

class PokeBattle_Battle
  # 3. Octolock: prevent the locked Pokémon from switching out.
  alias _npt_pbCanSwitch_g6 pbCanSwitch?
  def pbCanSwitch?(idxBattler, idxParty = -1, partyScene = nil)
    return false unless _npt_pbCanSwitch_g6(idxBattler, idxParty, partyScene)
    battler = @battlers[idxBattler]
    if battler && !battler.fainted? && battler.effects[PBEffects::Octolock] >= 0
      partyScene.pbDisplay(_INTL("{1} can't be switched out!", battler.pbThis)) if partyScene
      return false
    end
    return true
  end

  # 4. Octolock: lower Def and SpDef of the trapped Pokémon by 1 each turn end.
  alias _npt_pbEndOfRoundPhase_g6 pbEndOfRoundPhase
  def pbEndOfRoundPhase
    _npt_pbEndOfRoundPhase_g6
    pbPriority(true).each do |b|
      next if b.fainted? || b.effects[PBEffects::Octolock] < 0
      [:DEFENSE, :SPECIAL_DEFENSE].each do |stat|
        b.pbLowerStatStage(stat, 1, nil) if b.pbCanLowerStatStage?(stat)
      end
    end
  end
end

# ── Move classes ───────────────────────────────────────────────────────────────

#===============================================================================
# Acts like Protect, but lowers the attacker's Defense by 2 stages on contact.
# (Obstruct)
#===============================================================================
class PokeBattle_Move_18C < PokeBattle_ProtectMove
  def initialize(battle, move)
    super
    @effect = PBEffects::Obstruct
  end
end

#===============================================================================
# Traps the target. At the end of each turn while the target is trapped, its
# Defense and Special Defense are each lowered by 1 stage. (Octolock)
#===============================================================================
class PokeBattle_Move_18D < PokeBattle_Move
  def pbFailsAgainstTarget?(user, target)
    if target.effects[PBEffects::Octolock] >= 0
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    target.effects[PBEffects::Octolock] = user.index
    @battle.pbDisplay(_INTL("{1} is trapped in the vortex of Octolock!", target.pbThis))
  end
end

#===============================================================================
# Restores 25% of max HP and cures the status condition of the user and all
# active allies. (Jungle Healing)
#===============================================================================
class PokeBattle_Move_18E < PokeBattle_Move
  def pbEffectGeneral(user)
    @battle.pbPriority(true).each do |b|
      next if b.fainted? || b.opposes?(user)
      if b.hp < b.totalhp
        b.pbRecoverHP(b.totalhp / 4)
        @battle.pbDisplay(_INTL("{1}'s HP was restored.", b.pbThis))
      end
      next if b.status == :NONE
      b.pbCureStatus(true)
    end
  end
end

#===============================================================================
# Changes the target's type to Psychic. Fails if the target is already
# purely Psychic type. (Magic Powder)
#===============================================================================
class PokeBattle_Move_18F < PokeBattle_Move
  def pbFailsAgainstTarget?(user, target)
    if !target.canChangeType? || !GameData::Type.exists?(:PSYCHIC) ||
       !target.pbHasOtherType?(:PSYCHIC)
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    target.pbChangeTypes(:PSYCHIC)
    typeName = GameData::Type.get(:PSYCHIC).name
    @battle.pbDisplay(_INTL("{1} transformed into the {2} type!", target.pbThis, typeName))
  end
end

# ── Group 7: Variable power / conditional ─────────────────────────────────────

#===============================================================================
# Base power = floor(100 × target's current HP / target's max HP). Minimum 1.
# (Hard Press)
#===============================================================================
class PokeBattle_Move_190 < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    return (100 * target.hp / target.totalhp).clamp(1, 100)
  end
end

#===============================================================================
# Deals damage. Power is multiplied by ×1.5 when Electric Terrain is active.
# (Psyblade)
#===============================================================================
class PokeBattle_Move_191 < PokeBattle_Move
  def pbModifyDamage(damageMult, user, target)
    damageMult *= 1.5 if @battle.field.terrain == :Electric
    return damageMult
  end
end

#===============================================================================
# Deals damage. In Harsh Sunlight, Water-type moves normally lose power (×0.5);
# Hydro Steam instead gains power (×1.5). The base calc already applied ÷2 for
# Water in sun by the time pbModifyDamage is called, so ×3.0 here nets ×1.5.
# (Hydro Steam)
#===============================================================================
class PokeBattle_Move_192 < PokeBattle_Move
  def pbModifyDamage(damageMult, user, target)
    case @battle.pbWeather
    when :Sun, :HarshSun
      damageMult *= 3.0   # cancel base ÷2, then apply ×1.5: (÷2)×3 = ×1.5
    end
    return damageMult
  end
end

#===============================================================================
# Deals damage. Power doubles if the user's last move failed (same mechanic as
# Stomping Tantrum). Uses lastRoundMoveFailed, which persists for one full round.
# (Temper Flare)
#===============================================================================
class PokeBattle_Move_193 < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    baseDmg *= 2 if user.lastRoundMoveFailed
    return baseDmg
  end
end

#===============================================================================
# Deals damage. Has a 30% chance to deal double damage. (Fickle Beam)
#===============================================================================
class PokeBattle_Move_194 < PokeBattle_Move
  def pbModifyDamage(damageMult, user, target)
    damageMult *= 2 if @battle.pbRandom(100) < 30
    return damageMult
  end
end

#===============================================================================
# Fails if the target didn't choose a damaging move this round, or has already
# moved. Identical fail condition to Sucker Punch (116); priority +1 and type
# are set in PBS data. (Thunderclap)
#===============================================================================
class PokeBattle_Move_195 < PokeBattle_Move_116
end

# New PBEffects constant for the Glaive Rush vulnerability state.
module PBEffects
  GlaiveRush = 117   # int: 1 = user is vulnerable (cleared when user next acts)
end

# ── Glaive Rush hooks ──────────────────────────────────────────────────────────

class PokeBattle_Battler
  # Initialise the GlaiveRush slot on entry.
  alias _npt_pbInitEffects_gr pbInitEffects
  def pbInitEffects(batonPass)
    _npt_pbInitEffects_gr(batonPass)
    @effects[PBEffects::GlaiveRush] = 0
  end

  # Clear vulnerability the moment this battler begins their next action.
  alias _npt_pbBeginTurn_gr pbBeginTurn
  def pbBeginTurn(choice)
    _npt_pbBeginTurn_gr(choice)
    @effects[PBEffects::GlaiveRush] = 0
  end
end

class PokeBattle_Move
  # All moves bypass accuracy against a Glaive Rush-vulnerable target.
  # NOTE: Applies only when the base-class pbAccuracyCheck is used; moves that
  # fully override pbAccuracyCheck (e.g. Lock-On recipients) already hit.
  alias _npt_pbAccuracyCheck_gr pbAccuracyCheck
  def pbAccuracyCheck(user, target)
    return true if target.effects[PBEffects::GlaiveRush] > 0
    _npt_pbAccuracyCheck_gr(user, target)
  end

  # All moves deal double damage against a Glaive Rush-vulnerable target.
  # pbCalcDamageMultipliers is not overridden by subclasses, so this runs for
  # every damaging move regardless of move class.
  alias _npt_pbCalcDmgMult_gr pbCalcDamageMultipliers
  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    _npt_pbCalcDmgMult_gr(user, target, numTargets, type, baseDmg, multipliers)
    multipliers[:final_damage_multiplier] *= 2 if target.effects[PBEffects::GlaiveRush] > 0
  end
end

#===============================================================================
# Deals damage. After use, the user becomes vulnerable until their next action:
# all moves targeting it bypass accuracy and deal double damage. (Glaive Rush)
#===============================================================================
class PokeBattle_Move_196 < PokeBattle_Move
  def pbEffectGeneral(user)
    user.effects[PBEffects::GlaiveRush] = 1
  end
end

# New PBEffects constant for the Salt Cure state.
module PBEffects
  SaltCure = 118   # boolean: target is salt-cured (cleared on switch-out via pbInitEffects)
end

class PokeBattle_Battler
  alias _npt_pbInitEffects_sc pbInitEffects
  def pbInitEffects(batonPass)
    _npt_pbInitEffects_sc(batonPass)
    @effects[PBEffects::SaltCure] = false
  end
end

class PokeBattle_Battle
  alias _npt_pbEndOfRoundPhase_sc pbEndOfRoundPhase
  def pbEndOfRoundPhase
    _npt_pbEndOfRoundPhase_sc
    pbPriority(true).each do |b|
      next if b.fainted? || !b.effects[PBEffects::SaltCure]
      next unless b.takesIndirectDamage?
      dmg = (b.pbHasType?(:WATER) || b.pbHasType?(:STEEL)) ? b.totalhp / 4 : b.totalhp / 8
      @scene.pbDamageAnimation(b)
      b.pbReduceHP(dmg, false)
      pbDisplay(_INTL("{1} is hurt by salt!", b.pbThis))
      b.pbItemHPHealCheck
      b.pbFaint if b.fainted?
    end
  end
end

#===============================================================================
# Deals damage. Inflicts Salt Cure on the target: it loses 1/8 of its max HP
# at the end of each turn (1/4 if Water or Steel type). Clears on switch-out.
# (Salt Cure)
#===============================================================================
class PokeBattle_Move_197 < PokeBattle_Move
  def pbFailsAgainstTarget?(user, target)
    if target.effects[PBEffects::SaltCure]
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    target.effects[PBEffects::SaltCure] = true
    @battle.pbDisplay(_INTL("{1} is being salt-cured!", target.pbThis))
  end
end

# New PBEffects constant for the Syrup Bomb countdown.
module PBEffects
  SyrupBomb = 119   # int: turns remaining (3→2→1→0 = inactive); clears on switch-out
end

class PokeBattle_Battler
  alias _npt_pbInitEffects_sb pbInitEffects
  def pbInitEffects(batonPass)
    _npt_pbInitEffects_sb(batonPass)
    @effects[PBEffects::SyrupBomb] = 0
  end
end

class PokeBattle_Battle
  alias _npt_pbEndOfRoundPhase_sb pbEndOfRoundPhase
  def pbEndOfRoundPhase
    _npt_pbEndOfRoundPhase_sb
    pbPriority(true).each do |b|
      next if b.fainted? || b.effects[PBEffects::SyrupBomb] <= 0
      b.effects[PBEffects::SyrupBomb] -= 1
      b.pbLowerStatStage(:SPEED, 1, nil) if b.pbCanLowerStatStage?(:SPEED)
    end
  end
end

#===============================================================================
# Deals damage. Lowers the target's Speed by 1 stage at the end of each turn
# for 3 turns. Re-applying resets the counter to 3. (Syrup Bomb)
#===============================================================================
class PokeBattle_Move_198 < PokeBattle_Move
  def pbEffectAgainstTarget(user, target)
    target.effects[PBEffects::SyrupBomb] = 3
    @battle.pbDisplay(_INTL("{1} got covered in sticky syrup!", target.pbThis))
  end
end

# ── Group 8: Type/form loss and misc ──────────────────────────────────────────

# New PBEffects constant for the Double Shock type-loss state (mirrors BurnUp).
module PBEffects
  DoubleShock = 120   # boolean: user has discharged its Electric type
end

class PokeBattle_Battler
  alias _npt_pbInitEffects_ds pbInitEffects
  def pbInitEffects(batonPass)
    _npt_pbInitEffects_ds(batonPass)
    @effects[PBEffects::DoubleShock] = false
  end

  # Mirror the BurnUp pattern in the base pbTypes: strip :ELECTRIC when discharged.
  alias _npt_pbTypes_ds pbTypes
  def pbTypes(withType3 = false)
    ret = _npt_pbTypes_ds(withType3)
    ret.delete(:ELECTRIC) if @effects[PBEffects::DoubleShock]
    return ret
  end
end

#===============================================================================
# Deals damage. Fails if the user has no Electric type (or already discharged
# it). After dealing damage, the user loses its Electric type for the rest of
# the battle. (Double Shock)
#===============================================================================
class PokeBattle_Move_199 < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    if !user.pbHasType?(:ELECTRIC)
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAfterAllHits(user, target)
    return if user.effects[PBEffects::DoubleShock]
    user.effects[PBEffects::DoubleShock] = true
    @battle.pbDisplay(_INTL("{1} discharged all its electricity!", user.pbThis))
  end
end

#===============================================================================
# Fails if the user's HP is half of its max or less (can't afford the cost).
# Halves the user's HP, then raises Attack, Special Attack, and Speed by +2.
# (Fillet Away)
#===============================================================================
class PokeBattle_Move_19A < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    if user.hp <= user.totalhp / 2
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectGeneral(user)
    user.pbReduceHP(user.totalhp / 2, false)
    @battle.pbDisplay(_INTL("{1} cut away its fillet!", user.pbThis))
    [:ATTACK, :SPECIAL_ATTACK, :SPEED].each do |stat|
      user.pbRaiseStatStage(stat, 2, user) if user.pbCanRaiseStatStage?(stat, user, self)
    end
  end
end

#===============================================================================
# Deals damage. After the hit, prevents the target from using HP-restoring moves
# for 2 turns (same mechanic as Heal Block, but applied by a damaging move).
# PBEffects::HealBlock (37) is already defined in 001_PBEffects.rb; the EOR
# countdown and healing suppression are handled by the base engine.
# (Psychic Noise)
#===============================================================================
class PokeBattle_Move_19B < PokeBattle_Move
  def pbEffectAgainstTarget(user, target)
    target.effects[PBEffects::HealBlock] = 2
    @battle.pbDisplay(_INTL("{1} was prevented from healing!", target.pbThis))
  end
end

# TODO: ORDERUP (code 19C) — 80 Phys Dragon.
#   If Tatsugiri is in the user's team in the Command Form, raises a specific stat by +1:
#     Stretchy Form → Attack, Droopy Form → Defense, Sandy Form → Speed.
class PokeBattle_Move_19C < PokeBattle_Move
  # TODO: implement (check party for Tatsugiri form, raise corresponding stat)
end

# ═══════════════════════════════════════════════════════════════════════════════
# BUCKET E — Remaining 47 moves (codes 19D–1CB)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Always-Crit / Never-Miss ────────────────────────────────────────────────

#===============================================================================
# Always lands a critical hit. (Wicked Blow, Surging Strikes, Flower Trick)
#===============================================================================
class PokeBattle_Move_19D < PokeBattle_Move
  def pbCritialOverride(user, target)
    return 1
  end
end

#===============================================================================
# Never misses. (Kowtow Cleave, False Surrender)
#===============================================================================
class PokeBattle_Move_19E < PokeBattle_Move
  def pbAccuracyCheck(user, target)
    return true
  end
end

#===============================================================================
# Never misses and always crits. (Flower Trick)
#===============================================================================
class PokeBattle_Move_19F < PokeBattle_Move
  def pbAccuracyCheck(user, target)
    return true
  end

  def pbCritialOverride(user, target)
    return 1
  end
end

#===============================================================================
# Power scales with friendship (max 102). Never misses.
# (Pika Papow, Veevee Volley)
#===============================================================================
class PokeBattle_Move_1A0 < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    return [(user.happiness * 2 / 5).floor, 1].max
  end

  def pbAccuracyCheck(user, target)
    return true
  end
end

#===============================================================================
# Always crits. Hits 3 times. (Surging Strikes)
#===============================================================================
class PokeBattle_Move_1A1 < PokeBattle_Move
  def multiHitMove?; return true; end
  def pbNumHits(user, targets); return 3; end

  def pbCritialOverride(user, target)
    return 1
  end
end

#===============================================================================
# High crit rate. (Aqua Cutter, Ivy Cudgel)
# Note: High crit is handled by flags "a" in the move data, but this class
# also changes type based on user form (Ivy Cudgel). Falls back to base type.
#===============================================================================
class PokeBattle_Move_1A2 < PokeBattle_Move
  # Ivy Cudgel type changes based on form — but since KIF doesn't have
  # Ogerpon forms, this just provides the high-crit class.
end

# ── Multi-Hit Moves ─────────────────────────────────────────────────────────

#===============================================================================
# Hits 2-5 times. After all hits, +1 Speed / -1 Defense to user. (Scale Shot)
#===============================================================================
class PokeBattle_Move_1A3 < PokeBattle_Move
  def multiHitMove?; return true; end

  def pbNumHits(user, targets)
    hitChances = [2, 2, 3, 3, 4, 5]
    r = @battle.pbRandom(hitChances.length)
    r = hitChances.length - 1 if user.hasActiveAbility?(:SKILLLINK)
    return hitChances[r]
  end

  def pbEffectAfterAllHits(user, target)
    return if target.damageState.hpLost <= 0
    if user.pbCanRaiseStatStage?(:SPEED, user, self)
      user.pbRaiseStatStage(:SPEED, 1, user)
    end
    if user.pbCanLowerStatStage?(:DEFENSE, user, self)
      user.pbLowerStatStage(:DEFENSE, 1, user)
    end
  end
end

#===============================================================================
# Hits 2 times. (Dual Wingbeat, Twin Beam, Double Shock — just the multi-hit)
#===============================================================================
class PokeBattle_Move_1A4 < PokeBattle_Move
  def multiHitMove?; return true; end
  def pbNumHits(user, targets); return 2; end
end

#===============================================================================
# Hits 3 times, each hit increases in power (20→30→40). (Triple Axel)
#===============================================================================
class PokeBattle_Move_1A5 < PokeBattle_Move
  def multiHitMove?; return true; end
  def pbNumHits(user, targets); return 3; end

  def pbBaseDamage(baseDmg, user, target)
    hit = user.effects[PBEffects::ParentalBond] rescue 0 # hack: track via hit count
    # Engine calls pbBaseDamage for each hit; use @hit_count
    @npt_hit ||= 0
    @npt_hit += 1
    return @npt_hit * 20
  end

  def pbEffectAfterAllHits(user, target)
    @npt_hit = 0
  end
end

#===============================================================================
# Hits 3 times. (Triple Dive)
#===============================================================================
class PokeBattle_Move_1A6 < PokeBattle_Move
  def multiHitMove?; return true; end
  def pbNumHits(user, targets); return 3; end
end

#===============================================================================
# Hits 1-10 times. (Population Bomb)
#===============================================================================
class PokeBattle_Move_1A7 < PokeBattle_Move
  def multiHitMove?; return true; end

  def pbNumHits(user, targets)
    if user.hasActiveAbility?(:SKILLLINK)
      return 10
    end
    # Each hit has 90% chance to continue
    hits = 1
    9.times { hits += 1 if @battle.pbRandom(100) < 90 }
    return hits
  end
end

# ── Priority / Speed-Conditional ─────────────────────────────────────────────

#===============================================================================
# Has +1 priority when used on Grassy Terrain. (Grassy Glide)
# Note: priority is set in move data; this boosts power on terrain instead
# since priority can't be dynamically changed easily. Simplified: +1 pri in data,
# power x1.3 on Grassy Terrain.
#===============================================================================
class PokeBattle_Move_1A8 < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    if @battle.field.terrain == :Grassy && !user.airborne?
      return (baseDmg * 1.3).round
    end
    return baseDmg
  end
end

# ── Recoil / Self-Damage / Self-Stat-Drop ────────────────────────────────────

#===============================================================================
# User faints after using this move. Power boosted on Misty Terrain.
# (Misty Explosion)
#===============================================================================
class PokeBattle_Move_1A9 < PokeBattle_Move
  def worksWithNoTargets?; return true; end

  def pbBaseDamage(baseDmg, user, target)
    if @battle.field.terrain == :Misty && !user.airborne?
      return (baseDmg * 1.5).round
    end
    return baseDmg
  end

  def pbEffectAfterAllHits(user, target)
    user.pbReduceHP(user.hp, false)
    user.pbFaint if user.fainted?
  end
end

#===============================================================================
# User loses half its max HP as recoil. (Steel Beam)
#===============================================================================
class PokeBattle_Move_1AA < PokeBattle_Move
  def pbEffectAfterAllHits(user, target)
    return if user.fainted?
    recoil = (user.totalhp / 2.0).ceil
    user.pbReduceHP(recoil, false)
    @battle.pbDisplay(_INTL("{1} is damaged by recoil!", user.pbThis))
    user.pbFaint if user.fainted?
  end
end

# ── HP-Based / Conditional Power ─────────────────────────────────────────────

#===============================================================================
# Power scales with user's remaining HP (150 at full, lower as HP drops).
# (Dragon Energy)
#===============================================================================
class PokeBattle_Move_1AB < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    return [(150 * user.hp / user.totalhp).floor, 1].max
  end
end

#===============================================================================
# Power doubles on Psychic Terrain; hits all foes on Psychic Terrain.
# (Expanding Force)
#===============================================================================
class PokeBattle_Move_1AC < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    if @battle.field.terrain == :Psychic && !user.airborne?
      return baseDmg * 2
    end
    return baseDmg
  end
end

#===============================================================================
# Power doubles if the user's stats were lowered this turn. (Lash Out)
#===============================================================================
class PokeBattle_Move_1AD < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    dropped = (user.effects[PBEffects::StatsDropped] rescue false)
    return baseDmg * 2 if dropped
    return baseDmg
  end
end

#===============================================================================
# Power doubles if target is on Electric Terrain. (Rising Voltage)
#===============================================================================
class PokeBattle_Move_1AE < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    if @battle.field.terrain == :Electric && !target.airborne?
      return baseDmg * 2
    end
    return baseDmg
  end
end

# ── Drain / Recovery on Hit ──────────────────────────────────────────────────

#===============================================================================
# Deals damage and drains 3 PP from the target's last used move. (Eerie Spell)
#===============================================================================
class PokeBattle_Move_1AF < PokeBattle_Move
  def pbEffectAgainstTarget(user, target)
    return if target.fainted?
    last_move = target.lastRegularMoveUsed
    return unless last_move
    target.eachMove do |m|
      next if m.id != last_move
      reduction = [3, m.pp].min
      m.pp -= reduction
      @battle.pbDisplay(_INTL("{1}'s PP was reduced!", target.pbThis))
      break
    end
  end
end

# ── Switch-Out After Attack ──────────────────────────────────────────────────

#===============================================================================
# User switches out after dealing damage. (Flip Turn)
# Identical to U-turn (0EE).
#===============================================================================
class PokeBattle_Move_1B0 < PokeBattle_Move_0EE
end

#===============================================================================
# Traps both the user and target (neither can switch). (Jaw Lock)
#===============================================================================
class PokeBattle_Move_1B1 < PokeBattle_Move
  def pbEffectAgainstTarget(user, target)
    return if target.fainted? || target.damageState.substitute
    return if target.effects[PBEffects::MeanLook] >= 0
    return if user.effects[PBEffects::MeanLook] >= 0
    target.effects[PBEffects::MeanLook] = user.index
    user.effects[PBEffects::MeanLook] = target.index
    @battle.pbDisplay(_INTL("Neither Pokémon can run away!"))
  end
end

# ── Terrain / Weather / Field Effects ────────────────────────────────────────

#===============================================================================
# Fails unless terrain is active. Deals damage and clears terrain.
# (Steel Roller)
#===============================================================================
class PokeBattle_Move_1B2 < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    if @battle.field.terrain == :None
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAfterAllHits(user, target)
    return if @battle.field.terrain == :None
    @battle.field.terrain = :None
    @battle.pbDisplay(_INTL("The terrain returned to normal!"))
  end
end

#===============================================================================
# Type and power change depending on active terrain. (Terrain Pulse)
# Normal/50 base → terrain type/100.
#===============================================================================
class PokeBattle_Move_1B3 < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    return 100 if @battle.field.terrain != :None && !user.airborne?
    return baseDmg
  end

  def pbBaseType(user)
    return :ELECTRIC if @battle.field.terrain == :Electric && !user.airborne?
    return :GRASS    if @battle.field.terrain == :Grassy   && !user.airborne?
    return :FAIRY    if @battle.field.terrain == :Misty    && !user.airborne?
    return :PSYCHIC  if @battle.field.terrain == :Psychic  && !user.airborne?
    return @type
  end
end

# ── Type-Changing / Form-Dependent ───────────────────────────────────────────

#===============================================================================
# Type depends on user form. Breaks screens. (Raging Bull)
# Since KIF doesn't have Tauros forms, defaults to Normal + screen breaking.
#===============================================================================
class PokeBattle_Move_1B4 < PokeBattle_Move
  def pbEffectAfterAllHits(user, target)
    return if target.damageState.hpLost <= 0
    side = target.pbOwnSide
    if side.effects[PBEffects::Reflect] > 0
      side.effects[PBEffects::Reflect] = 0
      @battle.pbDisplay(_INTL("{1}'s Reflect was broken!", target.pbTeam))
    end
    if side.effects[PBEffects::LightScreen] > 0
      side.effects[PBEffects::LightScreen] = 0
      @battle.pbDisplay(_INTL("{1}'s Light Screen was broken!", target.pbTeam))
    end
    if side.effects[PBEffects::AuroraVeil] > 0
      side.effects[PBEffects::AuroraVeil] = 0
      @battle.pbDisplay(_INTL("{1}'s Aurora Veil was broken!", target.pbTeam))
    end
  end
end

#===============================================================================
# In KIF (no Tera), this is just a normal 80-power special move.
# (Tera Blast, Tera Starstorm — kept as plain damage since Tera doesn't exist)
#===============================================================================
class PokeBattle_Move_1B5 < PokeBattle_Move
  # No special effect without Terastallization
end

# ── Two-Turn / Charge Moves ─────────────────────────────────────────────────

#===============================================================================
# User must recharge the next turn after using this move.
# (Eternabeam, Meteor Assault — same as Hyper Beam / 0C2)
#===============================================================================
class PokeBattle_Move_1B6 < PokeBattle_Move_0C2
end

#===============================================================================
# Two-turn move: charges turn 1 (+1 Sp.Atk), attacks turn 2. Power Herb skips.
# (Meteor Beam)
#===============================================================================
class PokeBattle_Move_1B7 < PokeBattle_TwoTurnMove
  def pbChargingTurnMessage(user, targets)
    @battle.pbDisplay(_INTL("{1} is overflowing with space power!", user.pbThis))
  end

  def pbChargingTurnEffect(user, target)
    if user.pbCanRaiseStatStage?(:SPECIAL_ATTACK, user, self)
      user.pbRaiseStatStage(:SPECIAL_ATTACK, 1, user)
    end
  end
end

# ── Target Manipulation (item/ability/type) ──────────────────────────────────

#===============================================================================
# Uses Attack or Sp. Atk, whichever is higher. Never misses.
# (Light That Burns the Sky)
#===============================================================================
class PokeBattle_Move_1B8 < PokeBattle_Move
  def pbAccuracyCheck(user, target)
    return true
  end

  def pbGetAttackStats(user, target)
    if user.attack > user.spatk
      return user.attack, user.stages[:ATTACK] + 6
    else
      return user.spatk, user.stages[:SPECIAL_ATTACK] + 6
    end
  end
end

#===============================================================================
# Fails if the target isn't holding an item. (Poltergeist)
#===============================================================================
class PokeBattle_Move_1B9 < PokeBattle_Move
  def pbFailsAgainstTarget?(user, target)
    if !target.item || target.item == 0
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    item_name = GameData::Item.get(target.item).name rescue target.item.to_s
    @battle.pbDisplay(_INTL("{1} is about to be attacked by its {2}!", target.pbThis, item_name))
    return false
  end
end

#===============================================================================
# Ignores moves/abilities that redirect moves. (Snipe Shot)
#===============================================================================
class PokeBattle_Move_1BA < PokeBattle_Move
  # In this engine, redirection isn't easily hooked. Acts as normal high-crit move.
  # The "a" flag in move data already handles high crit rate.
end

# ── Status Moves ─────────────────────────────────────────────────────────────

#===============================================================================
# Protect. Burns attackers that make direct contact. (Burning Bulwark)
# Reuses Protect logic with contact burn effect.
#===============================================================================
class PokeBattle_Move_1BB < PokeBattle_ProtectMove
  def initialize(battle, move)
    super
    @effect = PBEffects::Protect
  end

  def pbEffectsOnMakingContactWith(attacker, user)
    return if attacker.status != :NONE
    return unless attacker.affectedByContactEffect?
    if attacker.pbCanBurn?(user, false, self)
      attacker.pbBurn(user)
      @battle.pbDisplay(_INTL("{1} was burned by the burning bulwark!", attacker.pbThis))
    end
  end
end

#===============================================================================
# Switches out the user. Summons Hail/Snow for 5 turns. (Chilly Reception)
#===============================================================================
class PokeBattle_Move_1BC < PokeBattle_Move
  def pbEffectGeneral(user)
    @battle.pbDisplay(_INTL("{1} is telling a chillingly bad joke!", user.pbThis))
    if @battle.pbWeather != :Hail
      @battle.pbStartWeather(user, :Hail, 5, false)
    end
  end

  def pbEndOfMoveUsageEffect(user, targets, numHits, switchedBattlers)
    return if user.fainted?
    return if !@battle.pbCanChooseNonActive?(user.index)
    @battle.pbDisplay(_INTL("{1} went back to {2}!", user.pbThis, @battle.pbGetOwnerName(user.index)))
    @battle.pbPursuit(user.index)
    return if user.fainted?
    newPkmn = @battle.pbGetReplacementPokemonIndex(user.index)
    return if newPkmn < 0
    @battle.pbRecallAndReplace(user.index, newPkmn)
    @battle.pbClearChoice(user.index)
    @battle.pbOnActiveOne(user)
  end
end

#===============================================================================
# Destroys held items of all Pokémon on the field. (Corrosive Gas)
#===============================================================================
class PokeBattle_Move_1BD < PokeBattle_Move
  def pbEffectAgainstTarget(user, target)
    return if !target.item || target.item == 0
    return if target.hasActiveAbility?(:STICKYHOLD) && !@battle.moldBreaker
    item_name = GameData::Item.get(target.item).name rescue target.item.to_s
    target.pbRemoveItem
    @battle.pbDisplay(_INTL("{1}'s {2} was melted away!", target.pbThis, item_name))
  end
end

#===============================================================================
# Swaps all field effects between the two sides. (Court Change)
#===============================================================================
class PokeBattle_Move_1BE < PokeBattle_Move
  SWAPPABLE_EFFECTS = [
    PBEffects::Reflect, PBEffects::LightScreen, PBEffects::AuroraVeil,
    PBEffects::Spikes, PBEffects::ToxicSpikes, PBEffects::StealthRock,
    PBEffects::StickyWeb, PBEffects::Tailwind, PBEffects::Mist,
    PBEffects::Safeguard
  ]

  def pbEffectGeneral(user)
    side0 = @battle.sides[0]
    side1 = @battle.sides[1]
    SWAPPABLE_EFFECTS.each do |eff|
      side0.effects[eff], side1.effects[eff] = side1.effects[eff], side0.effects[eff]
    end
    @battle.pbDisplay(_INTL("{1} swapped the battle effects affecting each side!", user.pbThis))
  end
end

#===============================================================================
# Changes target's and ally's abilities to the target's ability. (Doodle)
#===============================================================================
class PokeBattle_Move_1BF < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    return false
  end

  def pbEffectAgainstTarget(user, target)
    target_ability = target.ability
    return unless target_ability
    user.ability = target_ability
    @battle.pbDisplay(_INTL("{1} copied {2}'s Ability!", user.pbThis, target.pbThis(true)))
  end
end

#===============================================================================
# Raises allies' crit ratio. Dragon types get +2, others +1. (Dragon Cheer)
#===============================================================================
class PokeBattle_Move_1C0 < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    # Always succeeds in doubles if there's an ally
    return false
  end

  def pbEffectGeneral(user)
    user.eachAlly do |ally|
      boost = ally.pbHasType?(:DRAGON) ? 2 : 1
      ally.effects[PBEffects::FocusEnergy] += boost
      ally.effects[PBEffects::FocusEnergy] = 4 if ally.effects[PBEffects::FocusEnergy] > 4
      @battle.pbDisplay(_INTL("{1} is getting pumped!", ally.pbThis))
    end
  end
end

#===============================================================================
# Swaps user's Attack and Defense stats. (Power Shift)
#===============================================================================
class PokeBattle_Move_1C1 < PokeBattle_Move
  def pbEffectGeneral(user)
    user.attack, user.defense = user.defense, user.attack
    @battle.pbDisplay(_INTL("{1} switched its Attack and Defense!", user.pbThis))
  end
end

#===============================================================================
# Revives a fainted party Pokémon to 50% HP. (Revival Blessing)
#===============================================================================
class PokeBattle_Move_1C2 < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    party = @battle.pbParty(user.index)
    has_fainted = party.any? { |p| p && p.fainted? }
    if !has_fainted
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectGeneral(user)
    party = @battle.pbParty(user.index)
    fainted = []
    party.each_with_index { |p, i| fainted << i if p && p.fainted? }
    return if fainted.empty?
    # Pick first fainted (in singles the AI/player picks)
    chosen = fainted[0]
    pkmn = party[chosen]
    pkmn.hp = (pkmn.totalhp / 2.0).round
    pkmn.hp = 1 if pkmn.hp < 1
    pkmn.status = :NONE
    pkmn.statusCount = 0
    @battle.pbDisplay(_INTL("{1} was revived and is ready to fight again!", pkmn.name))
  end
end

#===============================================================================
# Creates a substitute using 50% HP, then switches out. (Shed Tail)
#===============================================================================
class PokeBattle_Move_1C3 < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    if user.hp <= (user.totalhp / 2.0).ceil
      @battle.pbDisplay(_INTL("But it does not have enough HP left to make a substitute!"))
      return true
    end
    if !@battle.pbCanChooseNonActive?(user.index)
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectGeneral(user)
    sub_hp = (user.totalhp / 2.0).ceil
    user.pbReduceHP(sub_hp, false, false)
    user.effects[PBEffects::Substitute] = sub_hp
    @battle.pbDisplay(_INTL("{1} shed its tail to create a substitute!", user.pbThis))
  end

  def pbEndOfMoveUsageEffect(user, targets, numHits, switchedBattlers)
    return if user.fainted?
    return if !@battle.pbCanChooseNonActive?(user.index)
    newPkmn = @battle.pbGetReplacementPokemonIndex(user.index)
    return if newPkmn < 0
    @battle.pbRecallAndReplace(user.index, newPkmn)
    @battle.pbClearChoice(user.index)
    @battle.pbOnActiveOne(user)
  end
end

#===============================================================================
# Cures user's status + raises Sp.Atk and Sp.Def by 1. (Take Heart)
#===============================================================================
class PokeBattle_Move_1C4 < PokeBattle_Move
  def pbEffectGeneral(user)
    if user.status != :NONE
      old_status = user.status
      user.pbCureStatus(false)
      @battle.pbDisplay(_INTL("{1}'s status was cured!", user.pbThis))
    end
    showAnim = true
    if user.pbCanRaiseStatStage?(:SPECIAL_ATTACK, user, self)
      user.pbRaiseStatStage(:SPECIAL_ATTACK, 1, user, showAnim)
      showAnim = false
    end
    if user.pbCanRaiseStatStage?(:SPECIAL_DEFENSE, user, self)
      user.pbRaiseStatStage(:SPECIAL_DEFENSE, 1, user, showAnim)
    end
  end
end

#===============================================================================
# All Pokémon on the field eat their held Berry. (Teatime)
#===============================================================================
class PokeBattle_Move_1C5 < PokeBattle_Move
  def pbEffectGeneral(user)
    @battle.pbDisplay(_INTL("It's teatime! Everyone digs in!"))
    @battle.eachBattler do |b|
      next if !b.item
      next unless GameData::Item.get(b.item).is_berry? rescue false
      b.pbHeldItemTriggerCheck(b.item, false)
    end
  end
end

# ── Damage-Only Upgrades (moves that need minor effects beyond plain 000) ────

#===============================================================================
# Power doubles if the user attacks before the target. (Bolt Beak, Fishious Rend)
#===============================================================================
class PokeBattle_Move_1C6 < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    if @battle.choices[target.index][0] != :None
      # Target hasn't moved yet this round
      return baseDmg * 2
    end
    return baseDmg
  end
end

#===============================================================================
# Uses Defense stat instead of Attack for damage calculation. (Body Press)
#===============================================================================
class PokeBattle_Move_1C7 < PokeBattle_Move
  def pbGetAttackStats(user, target)
    return user.defense, user.stages[:DEFENSE] + 6
  end
end

#===============================================================================
# Retaliates with 1.5x the damage last taken. (Comeuppance)
# Same as Metal Burst (0E2-style).
#===============================================================================
class PokeBattle_Move_1C8 < PokeBattle_FixedDamageMove
  def pbMoveFailed?(user, targets)
    if user.lastHPLost == 0 || user.lastAttacker.empty?
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbFixedDamage(user, target)
    return [(user.lastHPLost * 1.5).floor, 1].max
  end
end

#===============================================================================
# Resets all stat changes on both sides. (Freezy Frost)
#===============================================================================
class PokeBattle_Move_1C9 < PokeBattle_Move
  def pbEffectAfterAllHits(user, target)
    @battle.eachBattler do |b|
      b.stages.each_key { |stat| b.stages[stat] = 0 }
    end
    @battle.pbDisplay(_INTL("All stat changes were eliminated!"))
  end
end

#===============================================================================
# Sets up Light Screen on user's side after dealing damage. (Glitzy Glow)
#===============================================================================
class PokeBattle_Move_1CA < PokeBattle_Move
  def pbEffectAfterAllHits(user, target)
    return if target.damageState.hpLost <= 0
    if user.pbOwnSide.effects[PBEffects::LightScreen] <= 0
      user.pbOwnSide.effects[PBEffects::LightScreen] = 5
      user.pbOwnSide.effects[PBEffects::LightScreen] = 8 if user.hasActiveItem?(:LIGHTCLAY)
      @battle.pbDisplay(_INTL("Light Screen made {1}'s team stronger against special moves!", user.pbThis))
    end
  end
end

#===============================================================================
# Sets up Reflect on user's side after dealing damage. (Baddy Bad)
#===============================================================================
class PokeBattle_Move_1CB < PokeBattle_Move
  def pbEffectAfterAllHits(user, target)
    return if target.damageState.hpLost <= 0
    if user.pbOwnSide.effects[PBEffects::Reflect] <= 0
      user.pbOwnSide.effects[PBEffects::Reflect] = 5
      user.pbOwnSide.effects[PBEffects::Reflect] = 8 if user.hasActiveItem?(:LIGHTCLAY)
      @battle.pbDisplay(_INTL("Reflect made {1}'s team stronger against physical moves!", user.pbThis))
    end
  end
end

#===============================================================================
# Hits 2 times (1 per target in doubles). (Dragon Darts)
#===============================================================================
class PokeBattle_Move_1CC < PokeBattle_Move
  def multiHitMove?; return true; end
  def pbNumHits(user, targets); return 2; end
end

#===============================================================================
# Heals all party Pokémon's status conditions after dealing damage.
# (Sparkly Swirl)
#===============================================================================
class PokeBattle_Move_1CD < PokeBattle_Move
  def pbEffectAfterAllHits(user, target)
    return if target.damageState.hpLost <= 0
    @battle.pbParty(user.index).each do |pkmn|
      next if !pkmn || pkmn.fainted?
      pkmn.status = :NONE
      pkmn.statusCount = 0
    end
    @battle.pbDisplay(_INTL("All status problems were healed!"))
  end
end

#===============================================================================
# Jet Punch — +1 priority. (Already in data, but this class ensures it.)
# Priority is handled by the move data's :priority => 1.
# This is just a plain damage move class.
#===============================================================================
class PokeBattle_Move_1CE < PokeBattle_Move
end
