require 'rails_helper'

RSpec.describe Card, type: :model do
  let!(:game) { Game.create! }
  let!(:character) { game.characters.create!(name: 'CardOwner') }
  let!(:template_with_targeting) {
    Template.create!(
      name: 'Targeting Template Alpha',
      description: 'Targets one character',
      resolution_timing: 'before',
      declarability_key: 'default_declarability',
      tick_condition_key: 'default_tick_condition',
      tick_effect_key: 'default_tick_effect',
      max_tick_count: 1,
      target_type_enum: 'enemy',
      target_count_min: 1,
      target_count_max: 2,
      target_condition_key: 'is_alive_condition'
    )
  }
  let!(:template_no_targeting) {
    Template.create!(
      name: 'No Target Template Alpha',
      description: 'No targets',
      resolution_timing: 'before',
      declarability_key: 'default_declarability',
      tick_condition_key: 'default_tick_condition',
      tick_effect_key: 'default_tick_effect',
      max_tick_count: 1,
      target_type_enum: 'enemy',
      target_count_min: 0,
      target_count_max: 0,
      target_condition_key: 'none'
    )
  }

  describe 'initialization' do
    it 'copies targeting attributes from its template when a new card is created' do
      card = Card.create!(owner: character, template: template_with_targeting)

      expect(card.target_type_enum).to eq('enemy')
      expect(card.target_count_min).to eq(1)
      expect(card.target_count_max).to eq(2)
      expect(card.target_condition_key).to eq('is_alive_condition')
    end

    it 'copies default targeting attributes from its template' do
      card = Card.create!(owner: character, template: template_no_targeting)

      expect(card.target_type_enum).to eq('enemy')
      expect(card.target_count_min).to eq(0)
      expect(card.target_count_max).to eq(0)
      expect(card.target_condition_key).to eq('none')
    end

    it 'does not override explicitly set attributes during initialization' do
      card = Card.create!(
        owner: character,
        template: template_with_targeting,
        target_count_max: 5
      )
      expect(card.target_count_max).to eq(5)
      expect(card.target_type_enum).to eq('enemy')
    end

    it 'does not re-copy attributes if the record is not new' do
      card = character.cards.create!(
        template: template_with_targeting,
        location: 'deck',
        position: 0
      )

      original_target_count_max = card.target_count_max
      card.template.update!(target_count_max: 10)
      found_card = Card.find(card.id)
      found_card.save!

      expect(found_card.target_count_max).to eq(original_target_count_max)
    end
  end

  describe 'validations' do
    let!(:game) { Game.create! }
    let!(:character1) { game.characters.create!(name: 'Test Character 1') }
    let!(:character2) { game.characters.create!(name: 'Test Character 2') }
    let!(:template) { Template.create!(name: "Validation Test Template", description: "A template", resolution_timing: "before", declarability_key: "dk", tick_condition_key: "tck", tick_effect_key: "tek", max_tick_count: 1) }

    context 'uniqueness of owner_character_id, location, and position' do
      before do
        character1.cards.create!(template: template, location: 'hand', position: 0)
      end

      it 'validates as an error if the constraint is violated for the same character' do
        duplicate_card = character1.cards.build(template: template, location: 'hand', position: 0)
        expect(duplicate_card).not_to be_valid
        expect(duplicate_card.errors[:owner_character_id]).to include("already has a card in that location and position")
      end

      it 'allows a card in the same location and position if the characters are different' do
        other_character_card = character2.cards.build(template: template, location: 'hand', position: 0)
        expect(other_character_card).to be_valid
      end

      it 'allows a card in a different location for the same character and position' do
        different_location_card = character1.cards.build(template: template, location: 'deck', position: 0)
        expect(different_location_card).to be_valid
      end

      it 'allows a card in a different position for the same character and location' do
        different_position_card = character1.cards.build(template: template, location: 'hand', position: 1)
        expect(different_position_card).to be_valid
      end
    end
  end
end
