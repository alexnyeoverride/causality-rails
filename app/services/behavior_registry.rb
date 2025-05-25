module BehaviorRegistry
  BEHAVIORS = {
    'default_declarability' => ->(_game_context, _action_or_params) { true },
    'default_declaration_effect' => ->(game_context, action) { },
    'default_tick_condition' => ->(game_context, action) {
      return false if action.phase.to_s == 'resolved' || action.phase.to_s == 'failed'
      if action.trigger_id.present? && action.resolution_timing.to_s == 'after'
        trigger_action = action.trigger
        return false if trigger_action.nil? || trigger_action.phase.to_s != 'resolved'
      end
      true
    },
    'default_tick_effect' => ->(game_context, action) { },
  }.freeze

  def self.execute(key, game_context, subject)
    behavior_lambda = BEHAVIORS[key]
    behavior_lambda.call(game_context, subject)
  end
end
