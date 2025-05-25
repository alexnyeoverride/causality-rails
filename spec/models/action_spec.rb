require 'rails_helper'

RSpec.describe Action, type: :model do
  let!(:game_instance) { Game.create! }
  let(:game_context) { { game: game_instance } }
  let!(:template) {
    Template.create!(
      name: 'Test Template Using Defaults',
      description: 'Desc',
      resolution_timing: 'before',
      declarability_key: 'default_declarability',
      tick_condition_key: 'default_tick_condition',
      tick_effect_key: 'default_tick_effect',
      max_tick_count: 3
    )
  }
  let!(:character) { game_instance.characters.create!(name: 'Tester') }
  let!(:card_instance) { character.cards.create!(template: template, location: 'hand') }

  let(:action) {
    a = Action.new(game: game_instance, card: card_instance, source: character)
    a.initialize_from_template_and_attributes(template, character)
    a
  }

  describe '#initialize_from_template_and_attributes' do
    it 'copies relevant attributes from template and sets defaults' do
      expect(action.resolution_timing.to_s).to eq(template.resolution_timing.to_s)
      expect(action.is_free).to eq(template.is_free)
      expect(action.max_tick_count).to eq(template.max_tick_count)
      expect(action.declarability_key).to eq(template.declarability_key)
      expect(action.source).to eq(character)
      expect(action.phase).to eq('declared')
      expect(action.game).to eq(game_instance)
    end

    it 'assigns target_ids and allows saving for association' do
      target_char = game_instance.characters.create!(name: 'Target')
      action_with_targets = Action.new(game: game_instance, card: card_instance, source: character)
      action_with_targets.initialize_from_template_and_attributes(template, character, { target_ids: [target_char.id, ''] })
      action_with_targets.save!

      expect(action_with_targets.target_ids).to eq([target_char.id])
      expect(action_with_targets.targets.first).to eq(target_char)
    end
  end

  describe 'phase transitions' do
    before { action.save! }

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
    before { action.save! }

    it '#can_declare? calls BehaviorRegistry' do
      expect(action.can_declare?(game_context)).to be true
    end

    it '#can_tick? calls BehaviorRegistry' do
      expect(action.can_tick?(game_context)).to be true
    end
  end
end
