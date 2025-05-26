class ActionCharacterTarget < ApplicationRecord
  belongs_to :action
  belongs_to :target_character, class_name: 'Character'
end
