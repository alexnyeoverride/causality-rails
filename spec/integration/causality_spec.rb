require 'rails_helper'

RSpec.describe Causality, type: :integration do
  let!(:game) { Game.create! }
  let(:causality) { Causality.new(game) }
  let!(:char1) { game.characters.create!(name: 'Alice', health: 100, actions_remaining: 2, reactions_remaining: 2) }
  let!(:char2) { game.characters.create!(name: 'Bob', health: 100, actions_remaining: 2, reactions_remaining: 2) }

  let!(:template_attack) {
    Template.create!(
      name: 'Attack',
      description: 'Deal damage',
      resolution_timing: 'before',
      declarability_key: 'default_declarability',
      tick_condition_key: 'default_tick_condition',
      tick_effect_key: 'default_tick_effect',
      max_tick_count: 1
    )
  }
  let!(:template_react_before) {
    Template.create!(
      name: 'Dodge',
      description: 'Avoid attack',
      resolution_timing: 'before',
      declarability_key: 'default_declarability',
      tick_condition_key: 'default_tick_condition',
      tick_effect_key: 'default_tick_effect',
      max_tick_count: 1
    )
  }
  let!(:template_react_after) {
    Template.create!(
      name: 'Retaliate',
      description: 'Hit back',
      resolution_timing: 'after',
      declarability_key: 'default_declarability',
      tick_condition_key: 'default_tick_condition',
      tick_effect_key: 'default_tick_effect',
      max_tick_count: 1
    )
  }
  let!(:template_pass) {
    Template.create!(
      name: 'Pass',
      description: 'Pass',
      resolution_timing: 'before',
      declarability_key: 'default_declarability',
      tick_condition_key: 'default_tick_condition',
      tick_effect_key: 'default_tick_effect',
      max_tick_count: 1
    )
  }

  let!(:card_attack_c1) { char1.cards.create!(template: template_attack, location: 'hand', position: 0) }
  let!(:card_react_c2) { char2.cards.create!(template: template_react_before, location: 'hand', position: 0) }
  let!(:card_react_after_c2) { char2.cards.create!(template: template_react_after, location: 'hand', position: 1) }
  let!(:card_pass_c1) { char1.cards.create!(template: template_pass, location: 'hand', position: 1) }

  let(:game_context) { { game: game } }

  describe '#add' do
    before(:each) do
      game.update!(current_character: char1)
    end

    it 'adds an action successfully' do
      action = causality.add(source_character_id: char1.id, card_id: card_attack_c1.id, target_ids: [char2.id])
      expect(action).to be_a(Action)
      expect(action).to be_persisted
      expect(action.source).to eq(char1)
      expect(action.card).to eq(card_attack_c1)
      expect(action.targets.map(&:id)).to eq([char2.id])
    end

    it 'returns nil if card not in hand' do
      card_attack_c1.update!(location: 'deck')
      action = causality.add(source_character_id: char1.id, card_id: card_attack_c1.id)
      expect(action).to be_nil
    end
  end

  describe '#get_next_trigger' do
    before(:each) do
      game.update!(current_character: char1)
    end

    it 'returns the earliest non-Pass declared action' do
      action1 = causality.add(source_character_id: char1.id, card_id: card_attack_c1.id)
      pass_action = char1.actions_taken.build(card: card_pass_c1, source: char1, phase: 'declared')
      pass_action.initialize_from_template_and_attributes(template_pass, char1)
      pass_action.save!

      expect(causality.get_next_trigger).to eq(action1)
    end
  end

  describe '#get_next_tickable' do
    before(:each) do
      game.update!(current_character: char1)
    end

    context 'basic cases' do
      it 'returns a "reacted_to" action that can tick' do
        action = char1.actions_taken.build(card: card_attack_c1, source: char1, phase: 'reacted_to')
        action.initialize_from_template_and_attributes(template_attack, char1)
        action.save!
        expect(causality.get_next_tickable).to eq(action)
      end

      it 'returns a "Pass" action in "declared" phase that can tick' do
        pass_action = char1.actions_taken.build(card: card_pass_c1, source: char1, phase: 'declared')
        pass_action.initialize_from_template_and_attributes(template_pass, char1)
        pass_action.save!
        expect(causality.get_next_tickable).to eq(pass_action)
      end
    end

    context 'with triggers and reactions' do
      let!(:main_action) {
        a = char1.actions_taken.build(card: card_attack_c1, source: char1, phase: 'reacted_to', resolution_timing: 'before')
        a.initialize_from_template_and_attributes(template_attack, char1)
        a.save!
        a
      }

      it 'returns a "before" reaction if its trigger is not yet resolved and it can tick' do
        reaction_before = char2.actions_taken.build(card: card_react_c2, source: char2, trigger: main_action, phase: 'reacted_to', resolution_timing: 'before')
        reaction_before.initialize_from_template_and_attributes(template_react_before, char2, {trigger_id: main_action.id})
        reaction_before.save!
        expect(causality.get_next_tickable).to eq(reaction_before)
      end

      it 'returns an "after" reaction only if its trigger is resolved' do
        reaction_after = char2.actions_taken.build(card: card_react_after_c2, source: char2, trigger: main_action, phase: 'reacted_to', resolution_timing: 'after')
        reaction_after.initialize_from_template_and_attributes(template_react_after, char2, {trigger_id: main_action.id})
        reaction_after.save!

        expect(causality.get_next_tickable).to eq(main_action)
        main_action.resolve!
        expect(causality.get_next_tickable).to eq(reaction_after)
      end
    end
  end

  describe '#fail_recursively!' do
    let!(:actionA_card) { char1.cards.create!(template: template_attack, location: 'hand', position: 10)}
    let!(:reactionB_card) { char2.cards.create!(template: template_react_before, location: 'hand', position: 10)}

    before(:each) do
      game.update!(current_character: char1)
    end

    let!(:actionA) {
      a = char1.actions_taken.build(card: actionA_card, source: char1, phase: 'reacted_to')
      a.initialize_from_template_and_attributes(template_attack, char1); a.save!; a
    }
    let!(:reactionB) {
      b = char2.actions_taken.build(card: reactionB_card, source: char2, trigger: actionA, phase: 'reacted_to')
      b.initialize_from_template_and_attributes(template_react_before, char2, {trigger_id: actionA.id}); b.save!; b
    }

    it 'marks the root action and its non-resolved/failed reactions as "failed"' do
      returned_data = causality.fail_recursively!(actionA.id)

      expect(actionA.reload.phase).to eq('failed')
      expect(reactionB.reload.phase).to eq('failed')

      expect(returned_data.map { |d| d['id'] }).to match_array([actionA.id, reactionB.id])
    end
  end
end
