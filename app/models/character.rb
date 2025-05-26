# app/models/character.rb
class Character < ApplicationRecord
  belongs_to :game
  has_many :cards, -> { order(:position) }, foreign_key: 'owner_character_id', dependent: :destroy, inverse_of: :owner
  has_many :actions_taken, class_name: 'Action', foreign_key: 'source_id', dependent: :destroy, inverse_of: :source

  DEFAULT_ACTIONS = 2
  DEFAULT_REACTIONS = 2

  validates :name, presence: true
  validates :health, numericality: { greater_than_or_equal_to: 0 }

  scope :alive, -> { where('health > 0') }

  delegate :draw_cards_from_deck!, :discard_cards_from_hand!, :reshuffle_discard_into_deck!,
           to: :card_manager
  delegate :deck, :hand, :discard_pile, to: :card_manager

  def card_manager
    @card_manager ||= CharacterCardManager.new(self)
  end

  def spend_resource_for_action!(action_instance)
    return false if action_instance.is_free?

    spent_last_resource = false
    if action_instance.trigger_id.present?
      if self.reactions_remaining > 0
        self.reactions_remaining -= 1
        spent_last_resource = (self.reactions_remaining == 0)
      else
        return false
      end
    else
      if self.actions_remaining > 0
        self.actions_remaining -= 1
        spent_last_resource = (self.actions_remaining == 0)
      else
        return false
      end
    end
    save!
    spent_last_resource
  end

  def can_afford_action?(action_to_check)
    return true if action_to_check.is_free?

    if action_to_check.trigger_id.present?
      return self.reactions_remaining > 0
    else
      return self.actions_remaining > 0
    end
  end

  def reset_turn_resources!
    update!(actions_remaining: DEFAULT_ACTIONS, reactions_remaining: DEFAULT_REACTIONS)
  end

  def alive?
    health > 0
  end
end
