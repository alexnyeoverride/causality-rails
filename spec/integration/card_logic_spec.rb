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
  let!(:player1) { game.characters.create!(name: 'Player 1', health: 50) } 
  let!(:player2) { game.characters.create!(name: 'Player 2', health: 50) } 
  let!(:player3) { game.characters.create!(name: 'Player 3', health: 50) } 

  let!(:quick_shot_card_p1) { player1.cards.create!(template: Template.find_by!(name: 'Quick Shot'), location: 'hand', position: 0) }
  let!(:heavy_blast_card_p1) { player1.cards.create!(template: Template.find_by!(name: 'Heavy Blast'), location: 'hand', position: 1) }
  let!(:exploit_opening_card_p1) { player1.cards.create!(template: Template.find_by!(name: 'Exploit Opening'), location: 'hand', position: 2) }
  let!(:retort_card_p1) { player1.cards.create!(template: Template.find_by!(name: 'Retort'), location: 'hand', position: 3) }
  let!(:pass_card_p1) { player1.cards.create!(template: Template.find_by!(name: 'Pass'), location: 'hand', position: 4)}


  let!(:deflection_card_p2) { player2.cards.create!(template: Template.find_by!(name: 'Deflection Shield'), location: 'hand', position: 0) }
  let!(:emergency_card_p2) { player2.cards.create!(template: Template.find_by!(name: 'Emergency Return'), location: 'hand', position: 1) }
  let!(:pass_card_p2) { player2.cards.create!(template: Template.find_by!(name: 'Pass'), location: 'hand', position: 2)}


  let!(:pass_card_p3) { player3.cards.create!(template: Template.find_by!(name: 'Pass'), location: 'hand', position: 0) }

  def create_dummy_trigger(source_player, opposing_player_pass_card, tick_count_for_trigger = 0)
    action = build_action('Pass', source_player, { card: opposing_player_pass_card })
    action.max_tick_count = tick_count_for_trigger 
    action.save! 
    action
  end


  before(:each) do
    [player1, player2, player3].each do |p|
      p.reload.update!(actions_remaining: Character::DEFAULT_ACTIONS, reactions_remaining: Character::DEFAULT_REACTIONS, health: 50)
    end
    game.actions.destroy_all 
    game.update!(current_character: player1) 
  end

  def build_action(card_template_name_or_template_object, source_character, custom_attributes = {})
    template = card_template_name_or_template_object.is_a?(String) ? Template.find_by!(name: card_template_name_or_template_object) : card_template_name_or_template_object
    
    card_instance = custom_attributes[:card] 
    unless card_instance
        card_instance = source_character.cards.find_by(template_id: template.id, location: 'hand') ||
                        source_character.cards.create!(
                          template: template,
                          location: 'hand',
                          position: (source_character.cards.where(location: 'hand').maximum(:position) || -1) + 1
                        )
    end

    if card_instance.target_type_enum.nil? && template.target_type_enum.present?
        card_instance.update_columns(
            target_type_enum: template.target_type_enum,
            target_count_min: template.target_count_min,
            target_count_max: template.target_count_max,
            target_condition_key: template.target_condition_key
        )
    end

    action = Action.new(game: game, source: source_character, card: card_instance) 
    action_attributes_for_init = custom_attributes.merge(card: card_instance)
    action.initialize_from_template_and_attributes(template, source_character, action_attributes_for_init)
    action 
  end


  describe 'Quick Shot Card' do
    it 'deals 1 damage to the target' do
      dummy_trigger = create_dummy_trigger(player2, pass_card_p2, 1) 
      action = build_action('Quick Shot', player1, { 
        target_character_ids: [player2.id], 
        card: quick_shot_card_p1,
        trigger_id: dummy_trigger.id 
      })
      action.save!
      action.update!(phase: 'reacted_to') 

      initial_health = player2.health
      game.process_actions! 
      expect(player2.reload.health).to eq(initial_health) 
      expect(action.reload.phase).to eq('resolved')
    end
  end

  describe 'Heavy Blast Card' do
    it 'deals 3 damage to the target' do
      dummy_trigger = create_dummy_trigger(player2, pass_card_p2, 3)
      action = build_action('Heavy Blast', player1, { 
        target_character_ids: [player2.id], 
        card: heavy_blast_card_p1,
        trigger_id: dummy_trigger.id 
      })
      action.save!
      action.update!(phase: 'reacted_to')

      initial_health = player2.health
      game.process_actions!
      expect(player2.reload.health).to eq(initial_health) 
      expect(action.reload.phase).to eq('resolved')
    end
  end
  
  describe 'Exploit Opening Card' do
    context 'when target is damaged' do
      before { player2.update!(health: 90) }
      it 'deals 2 damage to the target' do
        action_check = build_action('Exploit Opening', player1, { 
            target_character_ids: [player2.id], 
            card: exploit_opening_card_p1
        })
        expect(action_check.can_declare?).to be true

        dummy_trigger = create_dummy_trigger(player2, pass_card_p2, 2)
        action = build_action('Exploit Opening', player1, { 
            target_character_ids: [player2.id], 
            card: exploit_opening_card_p1,
            trigger_id: dummy_trigger.id 
        })
        action.save!
        action.update!(phase: 'reacted_to')
        
        initial_health = player2.health
        game.process_actions!
        expect(player2.reload.health).to eq(initial_health) 
        expect(action.reload.phase).to eq('resolved')
      end
    end

    context 'when target is not damaged' do
      before { player2.update!(health: 100) } 
      it 'is not declarable' do
        action = build_action('Exploit Opening', player1, { target_character_ids: [player2.id], card: exploit_opening_card_p1 })
        expect(action.can_declare?).to be false
      end
    end
  end

  describe 'Deflection Shield Card (Reaction)' do
    let!(:root_action_qs) {
      dummy_trigger = create_dummy_trigger(player2, pass_card_p2, 1) 
      action = build_action('Quick Shot', player1, { 
        target_character_ids: [player2.id], 
        card: quick_shot_card_p1,
        trigger_id: dummy_trigger.id 
      })
      action.save!
      action 
    }
    
    it 'redirects the trigger action to target the trigger source' do
      root_action_qs.update!(phase: 'declared') 

      reaction_deflect = build_action('Deflection Shield', player2, { trigger_id: root_action_qs.id, card: deflection_card_p2 })
      reaction_deflect.save!
      reaction_deflect.update!(phase: 'reacted_to') 
      
      root_action_qs.update!(phase: 'reacted_to')

      game.process_actions! 

      expect(reaction_deflect.reload.phase).to eq('resolved')
      
      updated_qs_targets = ActionCharacterTarget.where(action_id: root_action_qs.id)
      expect(updated_qs_targets.count).to eq(1)
      expect(updated_qs_targets.first.target_character_id).to eq(player1.id) 
      expect(root_action_qs.reload.phase).to eq('resolved') 
    end
  end

  describe 'Emergency Return Card (Reaction)' do
    let!(:root_action_hb) {
      dummy_trigger = create_dummy_trigger(player2, pass_card_p2, 3) 
      action = build_action('Heavy Blast', player1, { 
        target_character_ids: [player2.id], 
        card: heavy_blast_card_p1,
        trigger_id: dummy_trigger.id 
      })
      action.card.update!(location: 'table') 
      action.save!
      action
    }
    let!(:card_for_hb) { root_action_hb.card } 

    context 'declarability' do
      it 'is declarable if self health is below 25 (e.g. 24)' do
        player2.update!(health: 24)
        root_action_hb.update!(phase: 'declared') 
        
        reaction = build_action('Emergency Return', player2, { trigger_id: root_action_hb.id, card: emergency_card_p2 })
        expect(reaction.can_declare?).to be true
      end

      it 'is not declarable if self health is 25 or above' do
        player2.update!(health: 25)
        root_action_hb.update!(phase: 'declared')

        reaction = build_action('Emergency Return', player2, { trigger_id: root_action_hb.id, card: emergency_card_p2 })
        expect(reaction.can_declare?).to be false
      end
    end

    context 'effect' do
      it 'returns the trigger actions card to its owners hand' do
        player2.update!(health: 20) 
        root_action_hb.update!(phase: 'declared')

        reaction_return = build_action('Emergency Return', player2, { trigger_id: root_action_hb.id, card: emergency_card_p2 })
        reaction_return.save!
        reaction_return.update!(phase: 'reacted_to')
        root_action_hb.update!(phase: 'reacted_to') 

        expect(card_for_hb.reload.location).to eq('table') 
        
        game.process_actions!

        expect(reaction_return.reload.phase).to eq('resolved')
        expect(root_action_hb.reload.phase).to eq('failed') 
        expect(card_for_hb.reload.location).to eq('hand')
        expect(card_for_hb.owner).to eq(player1)
      end
    end
  end
  
  describe 'Reaction Tree Processing with Game#process_actions!' do
    context 'Scenario: P1 Quick Shots P2, P2 Deflects, P1 Retorts the Deflection' do
      it 'processes actions correctly: Retort (P1->P2), then Deflection (P2->P1), then Quick Shot (P1->P1)' do
        player1.update!(actions_remaining: 1, reactions_remaining: 1)
        player2.update!(reactions_remaining: 1)

        dummy_trigger_for_qs = create_dummy_trigger(player2, pass_card_p2, 1) 
        action_quick_shot = build_action('Quick Shot', player1, { 
            target_character_ids: [player2.id], 
            card: quick_shot_card_p1,
            trigger_id: dummy_trigger_for_qs.id 
        })
        action_quick_shot.save!
        action_quick_shot.card.update!(location: 'table') 

        action_deflection = build_action('Deflection Shield', player2, { trigger_id: action_quick_shot.id, card: deflection_card_p2 })
        action_deflection.save!
        action_deflection.card.update!(location: 'table')

        action_retort = build_action('Retort', player1, { trigger_id: action_deflection.id, card: retort_card_p1 })
        action_retort.save!
        action_retort.card.update!(location: 'table')
        
        action_retort.update!(phase: 'reacted_to')
        action_deflection.update!(phase: 'reacted_to')
        action_quick_shot.update!(phase: 'reacted_to')
        
        action_retort.update!(max_tick_count: 1)

        initial_p1_health = player1.reload.health 
        initial_p2_health = player2.reload.health 

        game.process_actions!
        
        final_p1_health = player1.reload.health
        final_p2_health = player2.reload.health

        expect(final_p1_health).to eq(initial_p1_health) 
        expect(final_p2_health).to eq(initial_p2_health - 1) 

        expect(action_retort.reload.phase).to eq('resolved')
        expect(action_deflection.reload.phase).to eq('resolved')
        expect(action_quick_shot.reload.phase).to eq('resolved')

        expect(quick_shot_card_p1.reload.location).to eq('discard')
        expect(deflection_card_p2.reload.location).to eq('discard')
        expect(retort_card_p1.reload.location).to eq('discard')
      end
    end
  end
end

