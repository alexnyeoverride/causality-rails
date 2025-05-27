require 'rails_helper'

RSpec.describe 'Card Logic, Behaviors, and Action Processing', type: :integration do
  before(:all) do
    DatabaseCleaner.clean_with(:truncation, except: %w(ar_internal_metadata schema_migrations))
    Rails.application.load_seed
  end

  after(:all) do
    DatabaseCleaner.clean_with(:truncation, except: %w(ar_internal_metadata schema_migrations))
  end

  let!(:game) { Game.create! }
  let!(:player1) { game.characters.create!(name: 'Player 1', health: 100, actions_remaining: 2, reactions_remaining: 2) }
  let!(:player2) { game.characters.create!(name: 'Player 2', health: 100, actions_remaining: 2, reactions_remaining: 2) }
  let!(:player3) { game.characters.create!(name: 'Player 3', health: 100, actions_remaining: 2, reactions_remaining: 2) }

  def create_and_prepare_action(card_template_name, source_character, custom_attributes = {})
    template = Template.find_by!(name: card_template_name)
    card_instance = source_character.cards.find_by(template_id: template.id, location: 'hand') ||
                    source_character.cards.create!(
                      template: template,
                      location: 'hand',
                      position: (source_character.hand.cards.maximum(:position) || -1) + 1,
                      target_type_enum: template.target_type_enum,
                      target_count_min: template.target_count_min,
                      target_count_max: template.target_count_max,
                      target_condition_key: template.target_condition_key
                    )

    action = Action.new(game: game, source: source_character)
    action_attributes = { card: card_instance }.merge(custom_attributes)
    action.initialize_from_template_and_attributes(template, source_character, action_attributes)
    action.save!
    action.card.update!(location: 'table', position: Card.maximum(:position) + 1)
    action
  end

  def build_action_for_declarability_check(card_template_name, source_character, custom_attributes = {})
    template = Template.find_by!(name: card_template_name)
    card_instance = source_character.cards.find_by(template_id: template.id, location: 'hand') ||
                    source_character.cards.create!(template: template, location: 'hand', position: 0)

    action = Action.new(game: game, source: source_character)
    action_attributes = { card: card_instance }.merge(custom_attributes)
    action.initialize_from_template_and_attributes(template, source_character, action_attributes)
    action
  end

  describe 'Pass Card' do
    let(:card_template_name) { 'Pass' }

    it 'is always declarable' do
      action = build_action_for_declarability_check(card_template_name, player1)
      expect(action.can_declare?).to be true
    end

    it 'has a "pass_effect"' do
      action = create_and_prepare_action(card_template_name, player1)
      action.update!(phase: 'reacted_to')
      expect(action.tick_effect_key).to eq('pass_effect')
      expect { BehaviorRegistry.execute(action.tick_effect_key, game, action) }.not_to raise_error
    end
  end

  describe 'Quick Shot Card' do
    let(:card_template_name) { 'Quick Shot' }

    it 'is declarable by default' do
      action = build_action_for_declarability_check(card_template_name, player1, { target_character_ids: [player2.id] })
      expect(action.can_declare?).to be true
    end

    it 'deals 1 damage to the target' do
      action = create_and_prepare_action(card_template_name, player1, { target_character_ids: [player2.id] })
      action.update!(phase: 'reacted_to')
      expect { BehaviorRegistry.execute(action.tick_effect_key, game, action) }.to change { player2.reload.health }.by(-1)
    end

    it 'tick condition is "tick_if_target_still_alive"' do
      action = create_and_prepare_action(card_template_name, player1, { target_character_ids: [player2.id] })
      action.update!(phase: 'reacted_to')
      expect(action.tick_condition_key).to eq('tick_if_target_still_alive')
      expect(BehaviorRegistry.execute(action.tick_condition_key, game, action)).to be true
      player2.update!(health: 0)
      expect(BehaviorRegistry.execute(action.reload.tick_condition_key, game, action.reload)).to be false
    end
  end

  describe 'Heavy Blast Card' do
    let(:card_template_name) { 'Heavy Blast' }

    it 'is declarable by default' do
      action = build_action_for_declarability_check(card_template_name, player1, { target_character_ids: [player2.id] })
      expect(action.can_declare?).to be true
    end

    it 'deals 3 damage to the target' do
      action = create_and_prepare_action(card_template_name, player1, { target_character_ids: [player2.id] })
      action.update!(phase: 'reacted_to')
      expect { BehaviorRegistry.execute(action.tick_effect_key, game, action) }.to change { player2.reload.health }.by(-3)
    end
  end

  describe 'Exploit Opening Card' do
    let(:card_template_name) { 'Exploit Opening' }

    context 'declarability' do
      it 'is declarable if target has < 100 health' do
        player2.update!(health: 90)
        action = build_action_for_declarability_check(card_template_name, player1, { target_character_ids: [player2.id] })
        expect(action.can_declare?).to be true
      end

      it 'is not declarable if target has 100 health' do
        player2.update!(health: 100)
        action = build_action_for_declarability_check(card_template_name, player1, { target_character_ids: [player2.id] })
        expect(action.can_declare?).to be false
      end
    end

    it 'deals 2 damage to the target' do
      player2.update!(health: 90)
      action = create_and_prepare_action(card_template_name, player1, { target_character_ids: [player2.id] })
      action.update!(phase: 'reacted_to')
      expect { BehaviorRegistry.execute(action.tick_effect_key, game, action) }.to change { player2.reload.health }.by(-2)
    end
  end

  describe 'Deflection Shield Card (Reaction)' do
    let(:card_template_name) { 'Deflection Shield' }
    let!(:trigger_template) { Template.find_by!(name: 'Quick Shot') }
    let!(:trigger_action_instance) do
        create_and_prepare_action(trigger_template.name, player1, { target_character_ids: [player2.id] })
    end

    context 'declarability' do
      it 'is declarable if trigger targets self (player2)' do
        reaction = build_action_for_declarability_check(card_template_name, player2, { trigger_id: trigger_action_instance.id })
        expect(reaction.can_declare?).to be true
      end

      it 'is not declarable if trigger does not target self' do
        trigger_action_instance.action_character_targets.destroy_all
        trigger_action_instance.action_character_targets.create!(target_character: player3)
        reaction = build_action_for_declarability_check(card_template_name, player2, { trigger_id: trigger_action_instance.id })
        expect(reaction.can_declare?).to be false
      end
    end

    it 'redirects the trigger action to target its source (player1)' do
      reaction = create_and_prepare_action(card_template_name, player2, { trigger_id: trigger_action_instance.id })
      reaction.update!(phase: 'reacted_to')

      expect(trigger_action_instance.reload.character_targets).to include(player2)
      BehaviorRegistry.execute(reaction.tick_effect_key, game, reaction)
      expect(trigger_action_instance.reload.character_targets).to contain_exactly(player1)
      expect(trigger_action_instance.character_targets).not_to include(player2)
    end

    it 'tick condition checks if trigger action is not resolved or failed' do
      reaction = create_and_prepare_action(card_template_name, player2, { trigger_id: trigger_action_instance.id })
      reaction.update!(phase: 'reacted_to')
      expect(BehaviorRegistry.execute(reaction.tick_condition_key, game, reaction)).to be true
      trigger_action_instance.update!(phase: 'resolved')
      expect(BehaviorRegistry.execute(reaction.reload.tick_condition_key, game, reaction.reload)).to be false
    end
  end

  describe 'Sacrificial Blow Card' do
    let(:card_template_name) { 'Sacrificial Blow' }

    it 'deals 4 damage to target and 1 damage to source' do
      action = create_and_prepare_action(card_template_name, player1, { target_character_ids: [player2.id] })
      action.update!(phase: 'reacted_to')
      initial_p1_health = player1.health
      initial_p2_health = player2.health

      BehaviorRegistry.execute(action.tick_effect_key, game, action)

      expect(player1.reload.health).to eq(initial_p1_health - 1)
      expect(player2.reload.health).to eq(initial_p2_health - 4)
    end
  end

  describe 'Timing Shift Card (Reaction)' do
    let(:card_template_name) { 'Timing Shift' }
    let!(:after_template) { Template.find_by!(name: "Retort") }
    let!(:trigger_action_instance) do
      action = create_and_prepare_action(after_template.name, player1, { target_character_ids: [player2.id] })
      action.update!(resolution_timing: 'after')
      action
    end


    context 'declarability' do
      it 'is declarable if trigger action has "after" timing' do
        trigger_action_instance.update!(resolution_timing: 'after')
        reaction = build_action_for_declarability_check(card_template_name, player2, { trigger_id: trigger_action_instance.id })
        expect(reaction.can_declare?).to be true
      end

      it 'is not declarable if trigger action has "before" timing' do
        trigger_action_instance.update!(resolution_timing: 'before')
        reaction = build_action_for_declarability_check(card_template_name, player2, { trigger_id: trigger_action_instance.id })
        expect(reaction.can_declare?).to be false
      end
    end

    it 'changes trigger action timing to "before"' do
      trigger_action_instance.update!(resolution_timing: 'after')
      reaction = create_and_prepare_action(card_template_name, player2, { trigger_id: trigger_action_instance.id })
      reaction.update!(phase: 'reacted_to')
      expect(trigger_action_instance.reload.resolution_timing).to eq('after')
      BehaviorRegistry.execute(reaction.tick_effect_key, game, reaction)
      expect(trigger_action_instance.reload.resolution_timing).to eq('before')
    end
  end

  describe 'Retort Card (Reaction)' do
    let(:card_template_name) { 'Retort' }
    let!(:trigger_template) { Template.find_by!(name: 'Quick Shot') }
     let!(:trigger_action_instance) do
        create_and_prepare_action(trigger_template.name, player2, { target_character_ids: [player1.id] })
    end

    context 'declarability' do
      it 'is declarable if trigger targets self (player1)' do
        reaction = build_action_for_declarability_check(card_template_name, player1, { trigger_id: trigger_action_instance.id })
        expect(reaction.can_declare?).to be true
      end
    end

    it 'deals 2 damage to the trigger action source (player2)' do
      reaction = create_and_prepare_action(card_template_name, player1, { trigger_id: trigger_action_instance.id })
      reaction.update!(phase: 'reacted_to')
      expect { BehaviorRegistry.execute(reaction.tick_effect_key, game, reaction) }.to change { player2.reload.health }.by(-2)
    end
  end

  describe 'Emergency Return Card (Reaction)' do
    let(:card_template_name) { 'Emergency Return' }
    let!(:trigger_template) { Template.find_by!(name: 'Heavy Blast') }
    let!(:trigger_action_instance) do
        action = create_and_prepare_action(trigger_template.name, player2, { target_character_ids: [player1.id] })
        action.card.update!(location: 'table')
        action
    end


    context 'declarability' do
      it 'is declarable if self health is below 25 (e.g. 24)' do
        player1.update!(health: 24)
        reaction = build_action_for_declarability_check(card_template_name, player1, { trigger_id: trigger_action_instance.id })
        expect(reaction.can_declare?).to be true
      end

      it 'is not declarable if self health is 25 or above' do
        player1.update!(health: 25)
        reaction = build_action_for_declarability_check(card_template_name, player1, { trigger_id: trigger_action_instance.id })
        expect(reaction.can_declare?).to be false
      end
    end

    it 'returns the trigger actions card to its owners hand' do
      player1.update!(health: 20)
      reaction = create_and_prepare_action(card_template_name, player1, { trigger_id: trigger_action_instance.id })
      reaction.update!(phase: 'reacted_to')

      trigger_card = trigger_action_instance.card.reload
      expect(trigger_card.location).to eq('table')
      initial_hand_pos = player2.hand.cards.maximum(:position) || -1

      BehaviorRegistry.execute(reaction.tick_effect_key, game, reaction)

      trigger_card.reload
      expect(trigger_card.location).to eq('hand')
      expect(trigger_card.owner).to eq(player2)
      expect(trigger_card.position).to eq(initial_hand_pos + 1)
    end
  end

  describe 'Reaction Tree Processing with Game#process_actions!' do
    let!(:quick_shot_card_p1) { player1.cards.create!(template: Template.find_by!(name: 'Quick Shot'), location: 'hand', position: 0) }
    let!(:deflection_card_p2) { player2.cards.create!(template: Template.find_by!(name: 'Deflection Shield'), location: 'hand', position: 0) }
    let!(:retort_card_p1) { player1.cards.create!(template: Template.find_by!(name: 'Retort'), location: 'hand', position: 1) }
    let!(:pass_card_p3) { player3.cards.create!(template: Template.find_by!(name: 'Pass'), location: 'hand', position: 0) }


    before do
      player1.update!(actions_remaining: 1, reactions_remaining: 1, health: 50)
      player2.update!(actions_remaining: 1, reactions_remaining: 1, health: 50)
      player3.update!(actions_remaining: 1, reactions_remaining: 1, health: 50)
      game.update!(current_character: player1)
    end

    context 'Scenario: P1 Quick Shots P2, P2 Deflects, P1 Retorts the Deflection' do
      it 'processes actions correctly: Retort (P1->P2), then Deflection (P2->P1), then Quick Shot (P1->P1)' do
        quick_shot_action = create_and_prepare_action('Quick Shot', player1, { target_character_ids: [player2.id] })
        quick_shot_action.update!(phase: 'declared')
        player1.update!(actions_remaining: player1.actions_remaining - 1)

        deflection_action = create_and_prepare_action('Deflection Shield', player2, { trigger_id: quick_shot_action.id })
        deflection_action.update!(phase: 'declared')
        player2.update!(reactions_remaining: player2.reactions_remaining - 1)

        retort_action = create_and_prepare_action('Retort', player1, { trigger_id: deflection_action.id })
        retort_action.update!(phase: 'declared')
        player1.update!(reactions_remaining: player1.reactions_remaining - 1)

        pass_action_p3_on_retort = create_and_prepare_action('Pass', player3, { trigger_id: retort_action.id })
        pass_action_p3_on_retort.update!(phase: 'declared')
        player3.update!(reactions_remaining: player3.reactions_remaining - 1)

        retort_action.reload.update!(phase: 'reacted_to')

        pass_action_p3_on_deflection = create_and_prepare_action('Pass', player3, { trigger_id: deflection_action.id })
        pass_action_p3_on_deflection.update!(phase: 'declared')

        deflection_action.reload.update!(phase: 'reacted_to')

        pass_action_p3_on_quick_shot = create_and_prepare_action('Pass', player3, { trigger_id: quick_shot_action.id })
        pass_action_p3_on_quick_shot.update!(phase: 'declared')

        quick_shot_action.reload.update!(phase: 'reacted_to')

        initial_p1_health = player1.health
        initial_p2_health = player2.health

        game.process_actions!

        expect(player1.reload.health).to eq(initial_p1_health - 1)
        expect(player2.reload.health).to eq(initial_p2_health - 2)

        expect(retort_action.reload.phase).to eq('resolved')
        expect(deflection_action.reload.phase).to eq('resolved')
        expect(quick_shot_action.reload.phase).to eq('resolved')

        expect(quick_shot_card_p1.reload.location).to eq('discard')
        expect(deflection_card_p2.reload.location).to eq('discard')
        expect(retort_card_p1.reload.location).to eq('discard')
      end
    end

    context 'Scenario: P1 Heavy Blasts P2; P2 uses Emergency Return; P1 uses Timing Shift on Emergency Return (invalid, but for testing)' do
      let!(:heavy_blast_card_p1) { player1.cards.create!(template: Template.find_by!(name: 'Heavy Blast'), location: 'hand', position: player1.hand.cards.count) }
      let!(:emergency_return_card_p2) { player2.cards.create!(template: Template.find_by!(name: 'Emergency Return'), location: 'hand', position: player2.hand.cards.count) }
      let!(:timing_shift_card_p1) { player1.cards.create!(template: Template.find_by!(name: 'Timing Shift'), location: 'hand', position: player1.hand.cards.count) }


      it 'processes P1 Timing Shift (no real effect on "before" ER), then P2 Emergency Return (returns Heavy Blast)' do
        player2.update!(health: 20)
        player1.update!(actions_remaining: 1, reactions_remaining: 2)
        player2.update!(reactions_remaining: 1)
        player3.update!(reactions_remaining: 1)

        heavy_blast_action = create_and_prepare_action('Heavy Blast', player1, { target_character_ids: [player2.id] })
        heavy_blast_action.update!(phase: 'declared')
        player1.update!(actions_remaining: 0)

        emergency_return_action = create_and_prepare_action('Emergency Return', player2, { trigger_id: heavy_blast_action.id })
        emergency_return_action.update!(phase: 'declared')
        player2.update!(reactions_remaining: 0)

        timing_shift_action = create_and_prepare_action('Timing Shift', player1, { trigger_id: emergency_return_action.id })
        allow(timing_shift_action).to receive(:can_declare?).and_return(true)
        timing_shift_action.update!(phase: 'declared')
        player1.update!(reactions_remaining: player1.reactions_remaining - 1)

        pass_p3_on_timing_shift = create_and_prepare_action('Pass', player3, { trigger_id: timing_shift_action.id })
        pass_p3_on_timing_shift.update!(phase: 'declared')
        player3.update!(reactions_remaining: 0)
        timing_shift_action.reload.update!(phase: 'reacted_to')

        emergency_return_action.reload.update!(phase: 'reacted_to')

        heavy_blast_action.reload.update!(phase: 'reacted_to')

        initial_p1_health = player1.health
        initial_p2_health = player2.health
        expect(heavy_blast_card_p1.reload.location).to eq('table')

        game.process_actions!

        expect(timing_shift_action.reload.phase).to eq('resolved')
        expect(emergency_return_action.reload.phase).to eq('resolved')
        expect(heavy_blast_action.reload.phase).to eq('failed')

        expect(heavy_blast_card_p1.reload.location).to eq('hand')
        expect(player1.hand.cards).to include(heavy_blast_card_p1)

        expect(player1.reload.health).to eq(initial_p1_health)
        expect(player2.reload.health).to eq(initial_p2_health)

        expect(emergency_return_card_p2.reload.location).to eq('discard')
        expect(timing_shift_card_p1.reload.location).to eq('discard')
      end
    end
  end
end
