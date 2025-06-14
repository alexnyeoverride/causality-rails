require 'rails_helper'

RSpec.describe 'Game Flow and Action Declaration', type: :integration do
  let!(:game) { Game.create! }
  let!(:attack_template) { Template.create!(name: 'Attack', description: 'Deal damage', resolution_timing: 'before', declarability_key: 'default_declarability', tick_condition_key: 'default_tick_condition', tick_effect_key: 'default_tick_effect', max_tick_count: 1) }
  let!(:pass_template) { Template.create!(name: 'Pass', description: 'Do nothing', resolution_timing: 'before', declarability_key: 'default_declarability', tick_condition_key: 'default_tick_condition', tick_effect_key: 'default_tick_effect', max_tick_count: 1, is_free: true) }
  let!(:reaction_template) { Template.create!(name: 'Dodge', description: 'Avoid attack', resolution_timing: 'before', declarability_key: 'default_declarability', tick_condition_key: 'default_tick_condition', tick_effect_key: 'default_tick_effect', max_tick_count: 1) }

  let!(:failing_root_action_template) {
    Template.create!(
      name: 'RootActionThatWillBeStubbedToFail',
      description: 'This action will use default keys, but its on_tick! will be stubbed to fail',
      resolution_timing: 'before',
      declarability_key: 'default_declarability',
      tick_condition_key: 'default_tick_condition',
      tick_effect_key: 'default_tick_effect',
      max_tick_count: 1
    )
  }
  let!(:reaction_to_stubbed_fail_template) {
    Template.create!(
      name: 'ReactionToStubbedFailRoot',
      description: 'This reaction is to an action whose on_tick! is stubbed to fail',
      resolution_timing: 'before',
      declarability_key: 'default_declarability',
      tick_condition_key: 'default_tick_condition',
      tick_effect_key: 'default_tick_effect',
      max_tick_count: 1
    )
  }

  let!(:char1) { game.characters.create!(name: 'Alice', health: 100, actions_remaining: 2, reactions_remaining: 2) }
  let!(:char2) { game.characters.create!(name: 'Bob', health: 100, actions_remaining: 2, reactions_remaining: 2) }
  let!(:char3) { game.characters.create!(name: 'Carol', health: 100, actions_remaining: 2, reactions_remaining: 2) }

  let!(:char1_attack_card) { char1.cards.create!(template: attack_template, location: 'hand', position: 0) }
  let!(:char1_pass_card) { char1.cards.create!(template: pass_template, location: 'hand', position: 1) }
  let!(:char2_reaction_card) { char2.cards.create!(template: reaction_template, location: 'hand', position: 0) }
  let!(:char2_pass_card) { char2.cards.create!(template: pass_template, location: 'hand', position: 1) }
  let!(:char3_pass_card) { char3.cards.create!(template: pass_template, location: 'hand', position: 0) }

  let!(:root_action_card_for_stubbed_fail_test) { char1.cards.create!(template: failing_root_action_template, location: 'table', position: 3) }
  let!(:reaction_card_for_stubbed_fail_test) { char2.cards.create!(template: reaction_to_stubbed_fail_template, location: 'table', position: 3) }

  let(:game_context) { { game: game } }

  before(:each) do
    game.update!(current_character: char1)
  end

  describe 'Game#declare_action' do
    context 'when declaring a standard action' do
      it 'successfully declares an action, moves card to table, and spends an action point' do
        declared_action = nil
        expect {
          declared_action = game.declare_action(source_character_id: char1.id, card_id: char1_attack_card.id, target_character_ids: [char2.id])
        }.to change { char1.reload.actions_remaining }.by(-1)
         .and change { Action.count }.by(1)

        expect(declared_action).to be_persisted
        expect(declared_action.errors).to be_empty
        expect(declared_action.source).to eq(char1)
        expect(declared_action.card).to eq(char1_attack_card)
        expect(declared_action.character_targets).to include(char2)
        expect(char1_attack_card.reload.location).to eq('table')
      end

      it 'advances initiative if the character runs out of actions' do
        char1.update!(actions_remaining: 1)
        allow(game).to receive(:process_actions!)
        declared_action = game.declare_action(source_character_id: char1.id, card_id: char1_attack_card.id, target_character_ids: [char2.id])
        expect(declared_action.errors).to be_empty
        expect(declared_action).to be_persisted
        expect(char1.reload.actions_remaining).to eq(0)
        expect(game.reload.current_character).to eq(char2)
      end

      it 'returns an unpersisted action with errors if character cannot afford it' do
        char1.update!(actions_remaining: 0)
        action = nil
        expect {
          action = game.declare_action(source_character_id: char1.id, card_id: char1_attack_card.id, target_character_ids: [char2.id])
        }.not_to change(Action, :count)

        expect(action).not_to be_persisted
        expect(action.errors).not_to be_empty
        expect(action.errors[:base]).to include("Character cannot afford this action.")
        expect(char1_attack_card.reload.location).to eq('hand')
      end

      it 'returns an unpersisted action with errors if card is not in hand' do
        char1_attack_card.update!(location: 'deck')
        action = nil
        expect {
          action = game.declare_action(source_character_id: char1.id, card_id: char1_attack_card.id, target_character_ids: [char2.id])
        }.not_to change(Action, :count)
        expect(action).not_to be_persisted
        expect(action.errors).not_to be_empty
        expect(action.errors[:base]).to include("Card not in player's hand.")
      end

      it 'returns an unpersisted action with errors if declarability check fails' do
        allow_any_instance_of(Action).to receive(:can_declare?).and_return(false)
        action = nil
        expect {
          action = game.declare_action(source_character_id: char1.id, card_id: char1_attack_card.id, target_character_ids: [char2.id])
        }.not_to change(Action, :count)
        expect(action).not_to be_persisted
        expect(action.errors).not_to be_empty
        expect(action.errors[:base]).to include("Action cannot be declared at this time (preconditions failed).")
      end

      it 'triggers process_actions! if no reactions are pending and all other characters are out of reactions' do
        char1.update!(reactions_remaining: 0)
        char2.update!(reactions_remaining: 0)
        char3.update!(reactions_remaining: 0)
        expect_any_instance_of(Game).to receive(:process_actions!).and_call_original
        declared_action = game.declare_action(source_character_id: char1.id, card_id: char1_attack_card.id, target_character_ids: [char2.id])
        expect(declared_action).to be_persisted
        expect(declared_action.errors).to be_empty
      end
    end

    context 'when declaring a reaction' do
      let!(:trigger_action) do
        allow(game).to receive(:process_actions!)
        game.declare_action(source_character_id: char1.id, card_id: char1_attack_card.id, target_character_ids: [char2.id])
      end
      before do
        allow(game).to receive(:process_actions!).and_call_original
        char1.update!(actions_remaining: Character::DEFAULT_ACTIONS)
        allow(game.initiative).to receive(:advance!)
      end
      it 'successfully declares a reaction, spends a reaction point' do
        expect(trigger_action.reload.phase).to eq('declared')
        reaction = nil
        expect {
          reaction = game.declare_action(source_character_id: char2.id, card_id: char2_reaction_card.id, trigger_action_id: trigger_action.id)
        }.to change { char2.reload.reactions_remaining }.by(-1)
         .and change { Action.count }.by(1)

        expect(reaction).to be_persisted
        expect(reaction.errors).to be_empty
        expect(reaction.source).to eq(char2)
        expect(reaction.card).to eq(char2_reaction_card)
        expect(char2_reaction_card.reload.location).to eq('table')
      end

      it 'advances trigger phase to "reacted_to" if all living characters react or pass' do
        game.declare_action(source_character_id: char1.id, card_id: char1_pass_card.id, trigger_action_id: trigger_action.id)
        game.declare_action(source_character_id: char2.id, card_id: char2_reaction_card.id, trigger_action_id: trigger_action.id)
        expect(trigger_action.reload.phase).to eq('declared')
        game.declare_action(source_character_id: char3.id, card_id: char3_pass_card.id, trigger_action_id: trigger_action.id)
        expect(trigger_action.reload.phase).to eq('reacted_to')
      end

      it 'advances trigger phase to "reacted_to" if non-reacting characters are dead' do
        char1.update!(health: 0)

        expect(trigger_action.reload.phase).to eq('declared')
        game.declare_action(source_character_id: char2.id, card_id: char2_reaction_card.id, trigger_action_id: trigger_action.id)
        expect(trigger_action.reload.phase).to eq('declared')
        game.declare_action(source_character_id: char3.id, card_id: char3_pass_card.id, trigger_action_id: trigger_action.id)
        expect(trigger_action.reload.phase).to eq('reacted_to')
      end
    end
  end

  describe 'Game#process_actions!' do
    context 'with a single declared action ready to resolve' do
      let!(:action_to_process) {
        a = Action.new(game: game, card: char1_attack_card, source: char1, phase: 'reacted_to')
        a.initialize_from_template_and_attributes(attack_template, char1)
        a.save!
        a
      }
      before do
        char1_attack_card.update!(location: 'table')
      end
      it 'resolves the action and moves its card to discard' do
        game.process_actions!
        expect(action_to_process.reload.phase).to eq('resolved')
        expect(char1_attack_card.reload.location).to eq('discard')
        expect(char1.discard_pile.cards).to include(char1_attack_card)
      end
    end

    context 'when an action fails and has reactions' do
      let!(:root_action) {
        a = Action.new(card: root_action_card_for_stubbed_fail_test, source: char1, game: game, phase: 'reacted_to')
        a.initialize_from_template_and_attributes(failing_root_action_template, char1)
        a.save!
        a
      }
      let!(:reaction1) {
        r = Action.new(card: reaction_card_for_stubbed_fail_test, source: char2, game: game, trigger: root_action, phase: 'reacted_to', resolution_timing: 'before')
        r.initialize_from_template_and_attributes(reaction_to_stubbed_fail_template, char2, {trigger_id: root_action.id})
        r.save!
        r
      }
      before do
        allow(game.causality).to receive(:get_next_tickable).and_return(root_action, nil)
        allow(root_action).to receive(:on_tick!) { root_action.update_column(:phase, :failed); }
      end

      it 'recursively fails the action and its unresolved reactions, moving cards to discard' do
        game.process_actions!
        expect(root_action.reload.phase).to eq('failed')
        expect(reaction1.reload.phase).to eq('failed')
        expect(root_action_card_for_stubbed_fail_test.reload.location).to eq('discard')
        expect(reaction_card_for_stubbed_fail_test.reload.location).to eq('discard')
        expect(char1.discard_pile.cards).to include(root_action_card_for_stubbed_fail_test)
        expect(char2.discard_pile.cards).to include(reaction_card_for_stubbed_fail_test)
      end
    end
  end

  describe 'Game#is_over?' do
    it 'returns true if 1 or 0 characters are alive' do
      char1.update!(health: 0)
      char2.update!(health: 0)
      expect(game.is_over?).to be true
      char3.update!(health: 0)
      expect(game.is_over?).to be true
    end
  end

  describe 'Multi-Layer Reaction Tree and Initiative' do
    def declare_and_check(source:, expected_trigger:, expected_trigger_phase:, expected_remaining_actions:, expected_remaining_reactions:, expected_next_char:, is_skip:)
      template = is_skip ? pass_template : reaction_template
      card = source.cards.create!(template: template, location: 'hand', position: source.cards.count)
      expect(game.causality.get_next_trigger).to eq expected_trigger
      action = game.declare_action(source_character_id: source.id, card_id: card.id, trigger_action_id: expected_trigger&.id)
      expect(action).to be_persisted
      expected_trigger&.reload
      expect(expected_trigger&.phase).to eq expected_trigger_phase
      expect(source.reload.actions_remaining).to eq expected_remaining_actions
      expect(source.reload.reactions_remaining).to eq expected_remaining_reactions
      expect(game.reload.current_character).to eq expected_next_char
      action
    end

    context "When the initial actor has 1 action point remaining" do
      before do
        char1.update!(actions_remaining: 1, reactions_remaining: 2)
        char2.update!(actions_remaining: 2, reactions_remaining: 2)
        char3.update!(actions_remaining: 2, reactions_remaining: 2)
        game.update!(current_character: char1)
      end

      it 'processes the full tree and sets initiative correctly' do
        # layer 0
	a1 = declare_and_check(
          source: char1,
          expected_trigger: nil,
          expected_trigger_phase: nil,
          expected_remaining_actions: 0,
          expected_remaining_reactions: 2,
          expected_next_char: char2,
          is_skip: false
        )

        # layer 1, row a1
        r1_a1 = declare_and_check(
          source: char2,
          expected_trigger: a1,
          expected_trigger_phase: 'declared',
          expected_remaining_actions: 2,
          expected_remaining_reactions: 1,
          expected_next_char: char3,
          is_skip: false
        )
        r2_a1 = declare_and_check(
          source: char3,
          expected_trigger: a1,
          expected_trigger_phase: 'declared',
          expected_remaining_actions: 2,
          expected_remaining_reactions: 1,
          expected_next_char: char1,
          is_skip: false
        )
        r3_a1 = declare_and_check(
          source: char1,
          expected_trigger: a1,
          expected_trigger_phase: 'reacted_to',
          expected_remaining_actions: 0,
          expected_remaining_reactions: 1,
          expected_next_char: char2,
          is_skip: false
        )

        # layer 2, row r1_a1
        r1_r1_a1 = declare_and_check(
          source: char2,
          expected_trigger: r1_a1,
          expected_trigger_phase: 'declared',
          expected_remaining_actions: 2,
          expected_remaining_reactions: 1,
          expected_next_char: char3,
          is_skip: true
        )
        r2_r1_a1 = declare_and_check(
          source: char3,
          expected_trigger: r1_a1,
          expected_trigger_phase: 'declared',
          expected_remaining_actions: 2,
          expected_remaining_reactions: 1,
          expected_next_char: char1,
          is_skip: true
        )
        r3_r1_a1 = declare_and_check(
          source: char1,
          expected_trigger: r1_a1,
          expected_trigger_phase: 'reacted_to',
          expected_remaining_actions: 0,
          expected_remaining_reactions: 0,
          expected_next_char: char2,
          is_skip: false
        )

        # layer 2, row r2_a1
        r1_r2_a1 = declare_and_check(
          source: char2,
          expected_trigger: r2_a1,
          expected_trigger_phase: 'declared',
          expected_remaining_actions: 2,
          expected_remaining_reactions: 0,
          expected_next_char: char3,
          is_skip: false
        )
        r2_r2_a1 = declare_and_check(
          source: char3,
          expected_trigger: r2_a1,
          expected_trigger_phase: 'reacted_to',
          expected_remaining_actions: 2,
          expected_remaining_reactions: 1,
          expected_next_char: char3,
          is_skip: true
        )
        # char 1 is out of reactions

        # layer 2, row r3_a1
	# char2 is out of reactions
        r1_r3_a1 = declare_and_check(
          source: char3,
          expected_trigger: r3_a1,
          expected_trigger_phase: 'reacted_to',
          expected_remaining_actions: 2,
          expected_remaining_reactions: 1,
          expected_next_char: char3,
          is_skip: true
        )
        # char1 is out of reactions

        # layer 3, row r1_r1_a1
        # passes are not reactable to

        # layer 3, row r2_r1_a1
        # passes are not reactable to

        # layer 3, row r3_r1_a1
        # char2 is out of actions
        r1_r3_r1_a1 = declare_and_check(
          source: char3,
          expected_trigger: r3_r1_a1,
          expected_trigger_phase: 'resolved',
          expected_remaining_actions: 2,
          expected_remaining_reactions: 0,
          expected_next_char: char2,
          is_skip: false
        )
        # char1 is out of reactions

        # the full tree should now resolve
        expect(game.reload.causality.get_next_trigger).to be_nil

        # because char1 has no more action points, initiative goes to char2
        expect(game.reload.current_character).to eq(char2)
      end
    end
  end

  context 'with a complex chain of before and after reactions' do
    let!(:t1_template) { Template.create!(name: 'T1_BaseAction', description: 'Base', resolution_timing: 'before', declarability_key: 'default_declarability', tick_condition_key: 'default_tick_condition', tick_effect_key: 'default_tick_effect', max_tick_count: 1) }
    let!(:t2_template) { Template.create!(name: 'T2_ReactTo1_After', description: 'Reacts to T1, After', resolution_timing: 'after',  declarability_key: 'default_declarability', tick_condition_key: 'default_tick_condition', tick_effect_key: 'default_tick_effect', max_tick_count: 1) }
    let!(:t3_template) { Template.create!(name: 'T3_ReactTo1_Before', description: 'Reacts to T1, Before', resolution_timing: 'before', declarability_key: 'default_declarability', tick_condition_key: 'default_tick_condition', tick_effect_key: 'default_tick_effect', max_tick_count: 1) }
    let!(:t4_template) { Template.create!(name: 'T4_ReactTo2_After', description: 'Reacts to T2, After', resolution_timing: 'after',  declarability_key: 'default_declarability', tick_condition_key: 'default_tick_condition', tick_effect_key: 'default_tick_effect', max_tick_count: 1) }
    let!(:t5_template) { Template.create!(name: 'T5_ReactTo2_After_Other', description: 'Reacts to T2, After (other)', resolution_timing: 'after',  declarability_key: 'default_declarability', tick_condition_key: 'default_tick_condition', tick_effect_key: 'default_tick_effect', max_tick_count: 1) }
    let!(:t6_template) { Template.create!(name: 'T6_ReactTo5_Before', description: 'Reacts to T5, Before', resolution_timing: 'before', declarability_key: 'default_declarability', tick_condition_key: 'default_tick_condition', tick_effect_key: 'default_tick_effect', max_tick_count: 1) }

    before(:each) do
      char1.cards.delete_all
      char2.cards.delete_all
      char3.cards.delete_all
    end

    let!(:c1_card_for_a1) { char1.cards.create!(template: t1_template, location: 'hand', position: 0) }
    let!(:c2_card_for_a2) { char2.cards.create!(template: t2_template, location: 'hand', position: 0) }
    let!(:c3_card_for_a3) { char3.cards.create!(template: t3_template, location: 'hand', position: 0) }
    let!(:c1_card_for_a4) { char1.cards.create!(template: t4_template, location: 'hand', position: 1) }
    let!(:c2_card_for_a5) { char2.cards.create!(template: t5_template, location: 'hand', position: 1) }
    let!(:c3_card_for_a6) { char3.cards.create!(template: t6_template, location: 'hand', position: 1) }

    it 'resolves actions in the correct order: a3, a1, a2, a4, a6, a5' do
      resolved_order_tracker = []

      allow(game).to receive(:process_actions!)

      game.update!(current_character: char1)
      a1 = game.declare_action(source_character_id: char1.id, card_id: c1_card_for_a1.id)
      expect(a1.errors).to be_empty

      game.update!(current_character: char3)
      a3 = game.declare_action(source_character_id: char3.id, card_id: c3_card_for_a3.id, trigger_action_id: a1.id)
      expect(a3.errors).to be_empty

      game.update!(current_character: char2)
      a2 = game.declare_action(source_character_id: char2.id, card_id: c2_card_for_a2.id, trigger_action_id: a1.id)
      expect(a2.errors).to be_empty

      game.update!(current_character: char1)
      a4 = game.declare_action(source_character_id: char1.id, card_id: c1_card_for_a4.id, trigger_action_id: a2.id)
      expect(a4.errors).to be_empty

      game.update!(current_character: char2)
      a5 = game.declare_action(source_character_id: char2.id, card_id: c2_card_for_a5.id, trigger_action_id: a2.id)
      expect(a5.errors).to be_empty

      game.update!(current_character: char3)
      a6 = game.declare_action(source_character_id: char3.id, card_id: c3_card_for_a6.id, trigger_action_id: a5.id)
      expect(a6.errors).to be_empty

      allow(game).to receive(:process_actions!).and_call_original

      actions_in_chain = [a1, a2, a3, a4, a5, a6]
      actions_in_chain.each do |action|
        action.update_column(:phase, 'reacted_to')
        allow_any_instance_of(Action).to receive(:on_tick!) do |action|
          resolved_order_tracker << action.card.template.name.split('_').first.downcase.to_sym
        end
      end

      allow_any_instance_of(Action).to receive(:can_tick?) do |action_instance|
        if action_instance.trigger_id.present? && action_instance.resolution_timing.to_s == 'after'
          trigger = Action.find_by(id: action_instance.trigger_id)
          trigger&.phase.to_s == 'resolved'
        else
          true
        end
      end

      game.update!(current_character: char1)
      game.process_actions!

      expect(resolved_order_tracker).to eq([:t3, :t1, :t2, :t4, :t6, :t5])
    end
  end
end
