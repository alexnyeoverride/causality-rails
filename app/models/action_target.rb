class ActionTarget < ApplicationRecord
  belongs_to :action, inverse_of: :action_targets
  belongs_to :target_character, class_name: 'Character'

  validates :action_id, uniqueness: { scope: :target_character_id, message: "character is already a target for this action" }
end
