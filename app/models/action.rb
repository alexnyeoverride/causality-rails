class Action < ApplicationRecord
  belongs_to :game
  belongs_to :card
  belongs_to :source, class_name: 'Character', foreign_key: 'source_id', inverse_of: :actions_taken
  belongs_to :trigger, class_name: 'Action', foreign_key: 'trigger_id', optional: true, inverse_of: :reactions

  has_many :reactions, class_name: 'Action', foreign_key: 'trigger_id', dependent: :nullify, inverse_of: :trigger

  has_many :action_character_targets, dependent: :destroy
  has_many :character_targets, through: :action_character_targets, source: :target_character

  has_many :action_card_targets, dependent: :destroy
  has_many :card_targets, through: :action_card_targets, source: :target_card

  validates :phase, presence: true
  validates :declarability_key, presence: true
  validates :tick_condition_key, presence: true
  validates :tick_effect_key, presence: true
  validates :max_tick_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

  def can_declare?
    BehaviorRegistry.execute(self.declarability_key, self.game, self)
  end

  def can_tick?
    BehaviorRegistry.execute(self.tick_condition_key, self.game, self)
  end

  def on_tick!
    BehaviorRegistry.execute(self.tick_effect_key, self.game, self)
  end

  def initialize_from_template_and_attributes(template_instance, source_character, custom_attributes = {})
    self.card = custom_attributes[:card] if custom_attributes.key?(:card)
    self.resolution_timing = template_instance.resolution_timing
    self.is_free = template_instance.is_free
    self.max_tick_count = template_instance.max_tick_count

    self.declarability_key = template_instance.declarability_key
    self.tick_condition_key = template_instance.tick_condition_key
    self.tick_effect_key = template_instance.tick_effect_key

    self.source = source_character
    self.game = source_character.game
    self.phase ||= 'declared'

    assign_attributes(custom_attributes.except(:target_character_ids, :target_card_ids, :card))

    if custom_attributes[:target_character_ids].present?
      self.character_target_ids = custom_attributes[:target_character_ids].reject(&:blank?)
    end
    if custom_attributes[:target_card_ids].present?
      self.card_target_ids = custom_attributes[:target_card_ids].reject(&:blank?)
    end
    self
  end
end
