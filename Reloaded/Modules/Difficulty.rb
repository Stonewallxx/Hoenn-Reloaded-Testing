#======================================================
# Reloaded Difficulty Rules
# Author: Stonewall
#======================================================

module ReloadedDifficulty
  NORMAL_INDEX = 1
  HARD_INDEX = 2

  class << self
    def current_index
      if game_switches_ready?
        return HARD_INDEX if switch_enabled?(:SWITCH_GAME_DIFFICULTY_HARD)
        return NORMAL_INDEX
      end
      value = ($Trainer.selected_difficulty rescue nil)
      value.to_i == HARD_INDEX ? HARD_INDEX : NORMAL_INDEX
    rescue
      NORMAL_INDEX
    end

    def hard?
      return switch_enabled?(:SWITCH_GAME_DIFFICULTY_HARD) if game_switches_ready?
      ($Trainer.selected_difficulty rescue nil).to_i == HARD_INDEX
    rescue
      false
    end

    def prepare_change(index)
      target = index.to_i == HARD_INDEX ? HARD_INDEX : NORMAL_INDEX
      current = current_index
      if hard? && target != HARD_INDEX
        show_locked_warning
        return nil
      end
      if target == HARD_INDEX && current != HARD_INDEX
        return nil unless consume_hard_authorization || confirm_hard_selection
      end
      target
    rescue Exception => e
      log_exception("Difficulty change failed", e)
      nil
    end

    def confirm_hard_selection
      message = _INTL(
        "Hard difficulty is permanent for this save and cannot be changed later. Select Hard?"
      )
      if defined?(Reloaded) && Reloaded.respond_to?(:confirm)
        return Reloaded.confirm(message, :theme => :warning)
      end
      return pbConfirmMessage(message) if defined?(pbConfirmMessage)
      false
    rescue
      false
    end

    def show_locked_warning
      message = _INTL("Hard difficulty is permanent for this save and cannot be changed.")
      if defined?(Reloaded) && Reloaded.respond_to?(:toast_warning)
        Reloaded.toast_warning(message)
      elsif defined?(pbMessage)
        pbMessage(message)
      end
      false
    rescue
      false
    end

    def authorize_hard_selection
      return false unless confirm_hard_selection
      @hard_selection_authorized = true
      true
    rescue
      false
    end

    def consume_hard_authorization
      authorized = @hard_selection_authorized == true
      @hard_selection_authorized = false
      authorized
    rescue
      false
    end

    def normalize_loaded_difficulty
      return false unless defined?($Trainer) && $Trainer
      changed = false
      if game_switches_ready?
        easy_id = constant_value(:SWITCH_GAME_DIFFICULTY_EASY)
        hard_id = constant_value(:SWITCH_GAME_DIFFICULTY_HARD)
        if easy_id && $game_switches[easy_id]
          $game_switches[easy_id] = false
          $game_switches[hard_id] = false if hard_id
          changed = true
        end
      end
      target = hard? ? HARD_INDEX : NORMAL_INDEX
      if ($Trainer.selected_difficulty rescue nil).to_i != target
        $Trainer.selected_difficulty = target
        changed = true
      end
      lowest = ($Trainer.lowest_difficulty rescue nil)
      if lowest.nil? || lowest.to_i < NORMAL_INDEX
        $Trainer.lowest_difficulty = NORMAL_INDEX
        changed = true
      end
      log_info("Converted disabled Easy difficulty to Normal") if changed
      changed
    rescue Exception => e
      log_exception("Difficulty normalization failed", e)
      false
    end

    def replace_gameplay_option(scene, options)
      rows = Array(options)
      index = rows.index { |option| option.respond_to?(:name) && option.name.to_s == _INTL("Difficulty").to_s }
      return rows unless index && defined?(DifficultyOption)
      description = rows[index].description rescue ""
      if description.is_a?(Array)
        description = [description[NORMAL_INDEX], description[HARD_INDEX]]
      end
      rows[index] = DifficultyOption.new(scene, description)
      rows
    rescue Exception => e
      log_exception("Difficulty option replacement failed", e)
      Array(options)
    end

    def apply_option_value(scene, value)
      target = value.to_i == 1 ? HARD_INDEX : NORMAL_INDEX
      before = current_index
      scene.send(:setDifficulty, target)
      after = current_index
      scene.instance_variable_set(:@manually_changed_difficulty, true) if before != after
      after
    rescue Exception => e
      log_exception("Difficulty option change failed", e)
      current_index
    end

    def game_switches_ready?
      defined?($game_switches) && $game_switches
    rescue
      false
    end

    def switch_enabled?(constant_name)
      return false unless game_switches_ready?
      switch_id = constant_value(constant_name)
      switch_id ? !!$game_switches[switch_id] : false
    rescue
      false
    end

    def constant_value(constant_name)
      return nil unless Object.const_defined?(constant_name)
      Object.const_get(constant_name)
    rescue
      nil
    end

    def log_info(message)
      Reloaded::Log.info(message, :modules) if defined?(Reloaded::Log)
    rescue
    end

    def log_exception(message, error)
      Reloaded::Log.exception(message, error, channel: :modules) if defined?(Reloaded::Log)
    rescue
    end
  end
end

module ReloadedDifficultySetDifficultyPatch
  private

  def setDifficulty(index)
    target = ReloadedDifficulty.prepare_change(index)
    return ReloadedDifficulty.current_index if target.nil?
    super(target)
  end
end

unless Object.ancestors.include?(ReloadedDifficultySetDifficultyPatch)
  Object.send(:prepend, ReloadedDifficultySetDifficultyPatch)
end

if defined?(EnumOption)
  class ReloadedDifficulty::DifficultyOption < EnumOption
    def initialize(scene, description)
      @scene = scene
      super(
        _INTL("Difficulty"),
        [_INTL("Normal"), _INTL("Hard")],
        proc { ReloadedDifficulty.hard? ? 1 : 0 },
        proc { |value| ReloadedDifficulty.apply_option_value(@scene, value) },
        description
      )
    end

    def prev(current)
      if ReloadedDifficulty.hard?
        ReloadedDifficulty.show_locked_warning if current.to_i > 0
        return 1
      end
      super(current)
    end

    def next(current)
      return super(current) if current.to_i > 0
      return current unless ReloadedDifficulty.authorize_hard_selection
      1
    end
  end
end

if defined?(GameplayOptionsScene)
  module ReloadedDifficultyGameplayOptionsPatch
    def pbGetOptions(inloadscreen = false)
      ReloadedDifficulty.replace_gameplay_option(self, super(inloadscreen))
    end
  end

  unless GameplayOptionsScene.ancestors.include?(ReloadedDifficultyGameplayOptionsPatch)
    GameplayOptionsScene.send(:prepend, ReloadedDifficultyGameplayOptionsPatch)
  end
end

module ReloadedDifficultyEnsureCorrectPatch
  private

  def ensureCorrectDifficulty(*args)
    result = super(*args)
    ReloadedDifficulty.normalize_loaded_difficulty
    result
  end
end

unless Object.ancestors.include?(ReloadedDifficultyEnsureCorrectPatch)
  Object.send(:prepend, ReloadedDifficultyEnsureCorrectPatch)
end
