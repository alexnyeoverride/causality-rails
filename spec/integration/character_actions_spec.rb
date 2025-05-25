require 'rails_helper'

RSpec.describe Character, type: :integration do
  let!(:game) { Game.create! }
  let!(:character) { game.characters.create!(name: 'Hero', actions_remaining: 2, reactions_remaining: 1) }
  let!(:template_free) { Template.create!(name: 'Freebie', description: 'costs nothing', resolution_timing: 'before', is_free: true, declarability_key: 'dk', tick_condition_key: 'tck', tick_effect_key: 'tek', max_tick_count: 1) }
  let!(:template_costly) { Template.create!(name: 'Costly', description: 'costs action', resolution_timing: 'before', is_free: false, declarability_key: 'dk', tick_condition_key: 'tck', tick_effect_key: 'tek', max_tick_count: 1) }

  let!(:card_free) { character.cards.create!(template: template_free, location: 'hand', position: 0) }
  let!(:card_costly) { character.cards.create!(template: template_costly, location: 'hand', position: 1) }

  let(:action_instance_costly) {
    action = Action.new(source: character, card: card_costly)
    action.initialize_from_template_and_attributes(card_costly.template, character)
    action
  }
  let(:action_instance_free) {
    action = Action.new(source: character, card: card_free)
    action.initialize_from_template_and_attributes(card_free.template, character)
    action
  }
  let(:dummy_trigger_action) {
    action = Action.new(source: character, card: card_costly, game: game)
    action.initialize_from_template_and_attributes(card_costly.template, character)
    action.save!
    action
  }
  let(:reaction_instance_costly) {
    reaction = Action.new(source: character, card: card_costly, trigger_id: dummy_trigger_action.id)
    reaction.initialize_from_template_and_attributes(card_costly.template, character, {trigger_id: dummy_trigger_action.id})
    reaction
  }

  describe '#spend_resource_for_action!' do
    context 'for a normal action' do
      it 'decrements actions_remaining and returns false if more actions left' do
        expect(character.spend_resource_for_action!(action_instance_costly)).to be false
        expect(character.reload.actions_remaining).to eq(1)
      end

      it 'decrements actions_remaining and returns true if it was the last action' do
        character.update!(actions_remaining: 1)
        expect(character.spend_resource_for_action!(action_instance_costly)).to be true
        expect(character.reload.actions_remaining).to eq(0)
      end

      it 'does not decrement actions_remaining for a free action' do
        expect(character.spend_resource_for_action!(action_instance_free)).to be false
        expect(character.reload.actions_remaining).to eq(2)
      end
    end

    context 'for a reaction' do
      it 'decrements reactions_remaining and returns true if it was the last reaction' do
        expect(character.spend_resource_for_action!(reaction_instance_costly)).to be true
        expect(character.reload.reactions_remaining).to eq(0)
      end
    end
  end

  describe '#can_afford_action?' do
    it 'returns true for free actions even with 0 resources' do
      character.update!(actions_remaining: 0, reactions_remaining: 0)
      expect(character.can_afford_action?(action_instance_free)).to be true
    end

    it 'returns false for normal costly action if actions_remaining == 0' do
      character.update!(actions_remaining: 0)
      expect(character.can_afford_action?(action_instance_costly)).to be false
    end

    it 'returns false for costly reaction if reactions_remaining == 0' do
      character.update!(reactions_remaining: 0)
      expect(character.can_afford_action?(reaction_instance_costly)).to be false
    end
  end

  describe '#reset_turn_resources!' do
    it 'resets actions_remaining and reactions_remaining to defaults' do
      character.update!(actions_remaining: 0, reactions_remaining: 0)
      character.reset_turn_resources!
      expect(character.reload.actions_remaining).to eq(Character::DEFAULT_ACTIONS)
      expect(character.reactions_remaining).to eq(Character::DEFAULT_REACTIONS)
    end
  end
end
