module BehaviorRegistry
  BEHAVIORS = {
    'default_declarability' => ->(game, action) { true },
    'default_declaration_effect' => ->(game, action) { },
    'default_tick_condition' => ->(game, action) {
      return false if ['resolved', 'failed'].include?(action.phase.to_s)
      if action.trigger_id.present? && action.resolution_timing.to_s == 'after'
        trigger_action = action.trigger
        return false if trigger_action.nil? || trigger_action.phase.to_s != 'resolved'
      end
      true
    },
    'default_tick_effect' => ->(game, action) { },
    'pass_effect' => ->(game, action) { BEHAVIORS['default_tick_effect'].call(game, action) },

    'declarable_if_target_is_damaged' => ->(game, action) {
      return false unless action.character_target_ids.is_a?(Array)
      action.character_target_ids.any? do |target_id|
        target = game.characters.find_by(id: target_id)
        target && target.health < 100
      end
    },
    'declarable_if_trigger_targets_self' => ->(game, action) {
      return false unless action.trigger_id && action.source_id
      trigger_action = game.actions.find_by(id: action.trigger_id)
      return false unless trigger_action
      trigger_action.character_target_ids.include?(action.source_id)
    },
    'declarable_if_self_health_below_percentage' => ->(game, action) {
      health_percentage_threshold = action.card.template.read_attribute_before_type_cast(:target_count_min) || 25
      return false unless action.source_id && health_percentage_threshold.is_a?(Numeric)
      source_char = game.characters.find_by(id: action.source_id)
      return false unless source_char
      (source_char.health.to_f / 100.0) * 100 < health_percentage_threshold
    },
    'declarable_if_trigger_is_card_name' => ->(game, action) {
      expected_card_name = action.card.template.target_condition_key
      return false unless action.trigger_id && expected_card_name.present?
      trigger_action = game.actions.find_by(id: action.trigger_id)
      return false unless trigger_action&.card&.template
      trigger_action.card.template.name == expected_card_name
    },
    'declarable_if_trigger_action_not_resolved_or_failed' => ->(game, action) {
      return false unless action.trigger_id
      trigger_action = game.actions.find_by(id: action.trigger_id)
      return false unless trigger_action
      !['resolved', 'failed'].include?(trigger_action.phase.to_s)
    },
    'declarable_if_trigger_is_after_timing' => ->(game, action) {
      return false unless action.trigger_id
      trigger_action = game.actions.find_by(id: action.trigger_id)
      return false unless trigger_action
      trigger_action.resolution_timing.to_s == 'after'
    },

    'tick_if_target_still_alive' => ->(game, action) {
      return false unless BEHAVIORS['default_tick_condition'].call(game, action)
      action.character_targets.all?(&:alive?)
    },
    'tick_if_not_echoed_simple_phase_check' => ->(game, action) {
      return false unless BEHAVIORS['default_tick_condition'].call(game, action)
      action.phase.to_s == 'started'
    },
    'active_until_source_next_turn' => ->(game, action) {
      BEHAVIORS['default_tick_condition'].call(game, action)
    },

    'deal_damage_to_targets_from_max_tick_count' => ->(game, action) {
      damage_amount = action.max_tick_count > 0 ? action.max_tick_count : 1
      action.character_targets.each do |target_character|
        if target_character.alive?
          new_health = target_character.health - damage_amount
          target_character.update!(health: [new_health, 0].max)
        end
      end
    },
    'deal_damage_to_trigger_source_from_max_tick_count' => ->(game, action) {
      return unless action.trigger
      target_character = action.trigger.source
      return unless target_character&.alive?
      damage_amount = action.max_tick_count > 0 ? action.max_tick_count : 1
      target_character.update!(health: [0, target_character.health - damage_amount].max)
    },
    'return_trigger_card_to_hand' => ->(game, action) {
      trigger = action.trigger
      return unless trigger && trigger.source && trigger.card
      card_to_return = trigger.card
      owner = trigger.source
      max_pos = owner.cards.where(location: 'hand').maximum(:position) || -1
      new_pos = (max_pos || -1) + 1
      card_to_return.update!(location: 'hand', position: new_pos)
    },
    'deal_variadic_damage_to_targets_and_fixed_to_source' => ->(game, action) {
      target_damage = action.max_tick_count > 0 ? action.max_tick_count : 1
      source_damage = 1
      action.character_targets.each do |target|
        target.update!(health: [0, target.health - target_damage].max) if target.alive?
      end
      if action.source.alive?
        action.source.update!(health: [0, action.source.health - source_damage].max)
      end
    },
    'apply_anticipation_buff_to_source' => ->(game, action) {
      # TODO: Implement actual buff application logic for anticipation.
      # This might involve adding a temporary status to action.source character
      # that modifies their next action or provides a defensive benefit.
    },
    'redirect_trigger_action_to_its_source' => ->(game, action) {
      trigger = action.trigger
      return unless trigger && trigger.source
      trigger.action_character_targets.destroy_all
      ActionCharacterTarget.create!(action: trigger, target_character: trigger.source)
    },
    'apply_reactive_stance_buff_to_source' => ->(game, action) {
      # TODO: Implement actual buff application logic for reactive stance.
      # This could grant extra reactions, improve reaction cards, etc.
    },
    'apply_feedback_spines_aura' => ->(game, action) {
      # TODO: Implement actual aura application for feedback spines.
      # This likely involves adding a game-level or character-level persistent effect
      # that triggers damage when the character is targeted or hit.
    },
    'change_trigger_timing_to_before' => ->(game, action) {
      trigger = action.trigger
      return unless trigger && trigger.resolution_timing.to_s == 'after'
      trigger.update!(resolution_timing: 'before')
    },
    'increase_target_card_max_targets' => ->(game, action) {
      target_card = action.card_targets.first
      return unless target_card
      current_max_targets = target_card.target_count_max || 0
      target_card.update!(target_count_max: current_max_targets + 1)
    },
    'card_is_in_source_hand' => ->(game, action) {
      source_character = action.source
      target_card_id = action.card_target_ids.first
      return false unless source_character && target_card_id
      source_character.cards.where(id: target_card_id, location: 'hand').exists?
    },
    'change_action_phase_to_declared' => ->(game, action_to_reset) {
      if ['resolved', 'failed'].include?(action_to_reset.phase.to_s)
         can_reset = true
         if can_reset
            action_to_reset.update!(phase: 'declared', max_tick_count: action_to_reset.card.template.max_tick_count)
         end
      end
    },
    'shoot_effect' => ->(game, action) {
      action.character_targets.each do |target_character|
        if target_character.alive?
          target_character.update!(health: target_character.health - 1)
        end
      end
    }
  }.freeze

  def self.execute(behavior_key, game, action)
    behavior_lambda = BEHAVIORS[behavior_key]
    if behavior_lambda
      behavior_lambda.call(game, action)
    else
    end
  end
end

