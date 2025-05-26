class Card < ApplicationRecord
  belongs_to :owner, class_name: 'Character', foreign_key: 'owner_character_id', inverse_of: :cards
  belongs_to :template

  validates :location, presence: true
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :owner_character_id, uniqueness: { scope: [:owner_character_id, :location, :position], message: "already has a card in that location and position" }

  before_create :copy_targeting_parameters_from_template

  delegate :name, :description, :resolution_timing, :is_free,
           :declarability_key, :tick_condition_key, :tick_effect_key,
           :max_tick_count,
           to: :template, prefix: false

  def game
    owner.game
  end

  private

  def copy_targeting_parameters_from_template
    # TODO
  end
end
