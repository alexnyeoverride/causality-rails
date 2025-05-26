require 'rails_helper'

RSpec.describe Action, type: :model do
  let!(:game_instance) { Game.create! }
  let(:game_context) { { game: game_instance } }
  let!(:template_basic) {
    Template.create!(
      name: 'Test Template Using Defaults',
      description: 'Desc',
      resolution_timing: 'before',
      declarability_key: 'default_declarability',
      tick_condition_key: 'default_tick_condition',
      tick_effect_key: 'default_tick_effect',
      max_tick_count: 3,
      target_type_enum: 'none',
      target_count_min: 0,
      target_count_max: 0,
      target_condition_key: nil
    )
  }
  let!(:character) { game_instance.characters.create!(name: 'Tester') }
  let!(:card_instance_basic) { character.cards.create!(template: template_basic, location: 'hand') }


  describe '#initialize_from_template_and_attributes' do
    let(:action) {
      a = Action.new
      a.initialize_from_template_and_attributes(template_basic, character, {card: card_instance_basic})
      a
    }

    it 'copies relevant attributes from template and sets defaults' do
      expect(action.resolution_timing.to_s).to eq(template_basic.resolution_timing.to_s)
      expect(action.is_free).to eq(template_basic.is_free)
      expect(action.max_tick_count).to eq(template_basic.max_tick_count)
      expect(action.declarability_key).to eq(template_basic.declarability_key)
      expect(action.source).to eq(character)
      expect(action.phase).to eq('declared')
      expect(action.game).to eq(game_instance)
    end

    it 'assigns target_ids and allows saving for association' do
      target_char = game_instance.characters.create!(name: 'Target')
      action_with_targets = Action.new
      action_with_targets.initialize_from_template_and_attributes(template_basic, character, { target_ids: [target_char.id, ''], card: card_instance_basic })
      action_with_targets.save!

      expect(action_with_targets.target_ids).to eq([target_char.id])
      expect(action_with_targets.targets.first).to eq(target_char)
    end
  end

  describe 'phase transitions' do
    let(:action) {
      a = Action.new
      a.initialize_from_template_and_attributes(template_basic, character, {card: card_instance_basic})
      a.save!
      a
    }

    it '#finish_reactions_to! changes phase to "reacted_to"' do
      action.finish_reactions_to!
      expect(action.reload.phase).to eq('reacted_to')
    end

    it '#resolve! changes phase to "resolved"' do
      action.resolve!
      expect(action.reload.phase).to eq('resolved')
    end
  end

  describe 'behavior registry interactions' do
     let(:action) {
      a = Action.new
      a.initialize_from_template_and_attributes(template_basic, character, {card: card_instance_basic})
      a.save!
      a
    }

    it '#can_declare? calls BehaviorRegistry' do
      expect(action.can_declare?(game_context)).to be true
    end

    it '#can_tick? calls BehaviorRegistry' do
      expect(action.can_tick?(game_context)).to be true
    end
  end
end

