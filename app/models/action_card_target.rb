class ActionCardTarget < ApplicationRecord
  belongs_to :action
  belongs_to :target_card, class_name: 'Card'
end
