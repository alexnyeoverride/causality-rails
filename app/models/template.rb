class Template < ApplicationRecord
  has_many :cards, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :description, presence: true
  validates :resolution_timing, presence: true
  validates :declarability_key, presence: true
  validates :tick_condition_key, presence: true
  validates :tick_effect_key, presence: true
  validates :max_tick_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
