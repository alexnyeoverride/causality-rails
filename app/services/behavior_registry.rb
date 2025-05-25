module BehaviorRegistry
  BEHAVIORS = {
    'default_declarability' => ->(game, _action_or_params) { true },
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

    'declarable_if_target_is_damaged' => ->(game, params_hash) {
      return false unless params_hash.is_a?(Hash) && params_hash[:target_ids].is_a?(Array)
      params_hash[:target_ids].any? do |target_id|
        target = game.characters.find_by(id: target_id)
        target && target.health < 100
      end
    },
    'declarable_if_trigger_targets_self' => ->(game, params_hash) {
      return false unless params_hash.is_a?(Hash) && params_hash[:trigger_id] && params_hash[:source_character_id]
      trigger_action = game.actions.find_by(id: params_hash[:trigger_id])
      return false unless trigger_action
      trigger_action.target_ids.include?(params_hash[:source_character_id])
    },
    'declarable_if_self_health_below_percentage' => ->(game, params_hash) {
      return false unless params_hash.is_a?(Hash) && params_hash[:source_character_id] && params_hash[:health_percentage_threshold].is_a?(Numeric)
      source_char = game.characters.find_by(id: params_hash[:source_character_id])
      return false unless source_char
      (source_char.health.to_f / 100.0) * 100 < params_hash[:health_percentage_threshold]
    },
    'declarable_if_trigger_is_card_name' => ->(game, params_hash) {
      return false unless params_hash.is_a?(Hash) && params_hash[:trigger_id] && params_hash[:expected_card_name]
      trigger_action = game.actions.find_by(id: params_hash[:trigger_id])
      return false unless trigger_action&.card&.template
      trigger_action.card.template.name == params_hash[:expected_card_name]
    },
    'declarable_as_meta_reaction' => ->(game, params_hash) {
      return false unless params_hash.is_a?(Hash) && params_hash[:trigger_id] && params_hash[:source_character_id]
      boosted_reaction = game.actions.find_by(id: params_hash[:trigger_id])
      source_char = game.characters.find_by(id: params_hash[:source_character_id])
      return false unless boosted_reaction && source_char
      boosted_reaction.trigger_id.present? && boosted_reaction.source_id == source_char.id && source_char.reactions_remaining >= 2
    },
    'declarable_if_trigger_action_not_resolved_or_failed' => ->(game, params_hash) {
      return false unless params_hash.is_a?(Hash) && params_hash[:trigger_id]
      trigger_action = game.actions.find_by(id: params_hash[:trigger_id])
      return false unless trigger_action
      !['resolved', 'failed'].include?(trigger_action.phase.to_s)
    },
    'declarable_if_trigger_is_after_timing' => ->(game, params_hash) {
      return false unless params_hash.is_a?(Hash) && params_hash[:trigger_id]
      trigger_action = game.actions.find_by(id: params_hash[:trigger_id])
      return false unless trigger_action
      trigger_action.resolution_timing.to_s == 'after'
    },

    'tick_if_target_still_alive' => ->(game, action) {
      return false unless BEHAVIORS['default_tick_condition'].call(game, action)
      action.targets.all?(&:alive?)
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
      action.targets.each do |target_character|
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
      max_pos = owner.cards.where(location: 'hand').maximum(:position)
      new_pos = (max_pos || -1) + 1
      card_to_return.update!(location: 'hand', position: new_pos)
    },
    'deal_variadic_damage_to_targets_and_fixed_to_source' => ->(game, action) {
      target_damage = action.max_tick_count > 0 ? action.max_tick_count : 1
      source_damage = 1
      action.targets.each do |target|
        target.update!(health: [0, target.health - target_damage].max) if target.alive?
      end
      if action.source.alive?
        action.source.update!(health: [0, action.source.health - source_damage].max)
      end
    },
    'apply_anticipation_buff_to_source' => ->(game, action) { BEHAVIORS['default_tick_effect'].call(game, action) },
    'redirect_trigger_action_to_its_source' => ->(game, action) {
      trigger = action.trigger
      return unless trigger && trigger.source
      trigger.action_targets.destroy_all
      ActionTarget.create!(action: trigger, target_character: trigger.source)
    },
    'boost_triggered_reaction_effects' => ->(game, action) { BEHAVIORS['default_tick_effect'].call(game, action) },
    'apply_reactive_stance_buff_to_source' => ->(game, action) { BEHAVIORS['default_tick_effect'].call(game, action) },
    'apply_feedback_spines_aura' => ->(game, action) { BEHAVIORS['default_tick_effect'].call(game, action) },
    'change_trigger_timing_to_before' => ->(game, action) {
      trigger = action.trigger
      return unless trigger && trigger.resolution_timing.to_s == 'after'
      trigger.update!(resolution_timing: 'before')
    },

  }.freeze

  def self.execute(key, game_context, subject)
    behavior_lambda = BEHAVIORS[key]
    behavior_lambda.call(game_context, subject)
  end
end
