class Action < ApplicationRecord
  belongs_to :game
  belongs_to :card
  belongs_to :source, class_name: 'Character', foreign_key: 'source_id', inverse_of: :actions_taken
  belongs_to :trigger, class_name: 'Action', foreign_key: 'trigger_id', optional: true, inverse_of: :reactions

  has_many :reactions, class_name: 'Action', foreign_key: 'trigger_id', dependent: :nullify, inverse_of: :trigger
  has_many :action_targets, dependent: :destroy, inverse_of: :action
  has_many :targets, through: :action_targets, source: :target_character

  validates :phase, presence: true
  validates :declarability_key, presence: true
  validates :tick_condition_key, presence: true
  validates :tick_effect_key, presence: true
  validates :max_tick_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

  def finish_reactions_to!
    update!(phase: 'reacted_to')
  end

  def resolve!
    update!(phase: 'resolved')
  end

  def fail!
    update!(phase: 'failed')
  end

  def can_declare?(game_context)
    BehaviorRegistry.execute(self.declarability_key, game_context, self)
  end

  def can_tick?(game_context)
    current_game_context = game_context[:game] == self.game ? game_context : { game: self.game }
    BehaviorRegistry.execute(self.tick_condition_key, current_game_context, self)
  end

  def on_tick!(game_context)
    current_game_context = game_context[:game] == self.game ? game_context : { game: self.game }
    BehaviorRegistry.execute(self.tick_effect_key, current_game_context, self)
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

    assign_attributes(custom_attributes.except(:target_ids, :card))

    if custom_attributes[:target_ids].present?
      self.target_ids = custom_attributes[:target_ids].reject(&:blank?)
    end
    self
  end
end
