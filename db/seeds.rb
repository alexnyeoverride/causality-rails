# db/seeds.rb

# --- Standard Behaviors ---
# Default declarability: Can always declare (unless other conditions prevent it).
# Default tick condition: Can tick if not already resolved/failed, and if it's an 'after' reaction, its trigger has resolved.
# Default tick effect: Does nothing on its own.
# Pass effect: Same as default tick effect.

# --- New Effect Key for Direct Damage Actions ---
# 'deal_direct_damage_based_on_template': Deals damage to targets.
#   Magnitude is taken from the action's card's template's max_tick_count.
#   Action instance should be initialized with max_tick_count = 1 to tick once.

Template.find_or_create_by!(name: "Pass") do |template|
  template.description = "Action or Reaction\nCost: Free\nTake no action this turn, or choose not to react."
  template.resolution_timing = "before"
  template.is_free = true
  template.declarability_key = "default_declarability"
  template.tick_condition_key = "default_tick_condition"
  template.tick_effect_key = "pass_effect"
  template.max_tick_count = 0
end

Template.find_or_create_by!(name: "Quick Shot") do |template|
  template.description = "Action\nTarget an opponent. Deal 1 damage."
  template.resolution_timing = "before"
  template.is_free = false
  template.declarability_key = "default_declarability"
  template.tick_condition_key = "tick_if_target_still_alive"
  template.tick_effect_key = "deal_direct_damage_based_on_template"
  template.max_tick_count = 1
end

Template.find_or_create_by!(name: "Heavy Blast") do |template|
  template.description = "Action\nTarget an opponent. Deal 3 damage."
  template.resolution_timing = "before"
  template.is_free = false
  template.declarability_key = "default_declarability"
  template.tick_condition_key = "tick_if_target_still_alive"
  template.tick_effect_key = "deal_direct_damage_based_on_template"
  template.max_tick_count = 3
end

Template.find_or_create_by!(name: "Exploit Opening") do |template|
  template.description = "Action\nPlay only if target character has less than maximum health. Deal 2 damage."
  template.resolution_timing = "before"
  template.is_free = false
  template.declarability_key = "declarable_if_target_is_damaged"
  template.tick_condition_key = "tick_if_target_still_alive"
  template.tick_effect_key = "deal_direct_damage_based_on_template"
  template.max_tick_count = 2
end

Template.find_or_create_by!(name: "Deflection Shield") do |template|
  template.description = "Reaction\nWhen an opponent's action targets you: redirect that action to target them instead."
  template.resolution_timing = "before"
  template.is_free = false
  template.declarability_key = "declarable_if_trigger_targets_self"
  template.tick_condition_key = "declarable_if_trigger_action_not_resolved_or_failed"
  template.tick_effect_key = "redirect_trigger_action_to_its_source"
  template.max_tick_count = 1
end

Template.find_or_create_by!(name: "Sacrificial Blow") do |template|
  template.description = "Action\nTarget an opponent. Deal 4 damage to the target. You take 1 damage."
  template.resolution_timing = "before"
  template.is_free = false
  template.declarability_key = "default_declarability"
  template.tick_condition_key = "tick_if_target_still_alive"
 
 
  template.tick_effect_key = "deal_variadic_damage_to_targets_and_fixed_to_source" 
  template.max_tick_count = 4
end

Template.find_or_create_by!(name: "Timing Shift") do |template|
  template.description = "Reaction\nWhen an opponent declares an \"after\" timing action: change that action's timing to \"before\", if it has not yet resolved or failed."
  template.resolution_timing = "before"
  template.is_free = false
  template.declarability_key = "declarable_if_trigger_is_after_timing"
  template.tick_condition_key = "declarable_if_trigger_action_not_resolved_or_failed"
  template.tick_effect_key = "change_trigger_timing_to_before"
  template.max_tick_count = 1
end

Template.find_or_create_by!(name: "Retort") do |template|
  template.description = "Reaction\nWhen an opponent targets you with an Action card (not \"Pass\"): deal 2 damage back to that opponent."
  template.resolution_timing = "before"
  template.is_free = false
  template.declarability_key = "declarable_if_trigger_targets_self"
  template.tick_condition_key = "tick_if_target_still_alive"
 
  template.tick_effect_key = "deal_damage_to_trigger_source_from_max_tick_count" 
  template.max_tick_count = 2
end

Template.find_or_create_by!(name: "Emergency Return") do |template|
  template.description = "Reaction\nCost: Free\nPlay only if your health is below 25%. When an opponent's action targets you, if that action has not yet resolved or failed, return its card to their hand."
  template.resolution_timing = "before"
  template.is_free = true
  template.declarability_key = "declarable_if_self_health_below_percentage"
  template.tick_condition_key = "declarable_if_trigger_action_not_resolved_or_failed"
  template.tick_effect_key = "return_trigger_card_to_hand"
  template.max_tick_count = 1
end
