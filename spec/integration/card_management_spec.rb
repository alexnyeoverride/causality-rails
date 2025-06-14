require 'rails_helper'

RSpec.describe CharacterCardManager, type: :integration do
  let!(:game) { Game.create! }
  let!(:character) { game.characters.create!(name: 'CardPlayer') }
  let!(:template) {
    Template.create!(
      name: 'Generic Card',
      description: 'A card',
      resolution_timing: 'before',
      declarability_key: 'default_declarability_key',
      tick_condition_key: 'default_tick_condition_key',
      tick_effect_key: 'default_tick_effect_key',
      max_tick_count: 1,
      target_type_enum: 'enemy',
      target_count_min: 0,
      target_count_max: 0
    )
  }

  let!(:card_deck1) { character.cards.create!(template: template, location: 'deck', position: 0) }
  let!(:card_deck2) { character.cards.create!(template: template, location: 'deck', position: 1) }
  let!(:card_hand1) { character.cards.create!(template: template, location: 'hand', position: 0) }
  let!(:card_discard1) { character.cards.create!(template: template, location: 'discard', position: 0) }
  let!(:card_deck3) { character.cards.create!(template: template, location: 'deck', position: 2) }

  let(:manager) { character.card_manager }

  describe '#draw_cards_from_deck!' do
    it 'moves specified number of cards from deck to hand' do
      drawn_cards_relation = manager.draw_cards_from_deck!(2)
      drawn_cards = drawn_cards_relation.to_a

      expect(drawn_cards.map(&:id)).to match_array([card_deck1.id, card_deck2.id])
      expect(character.deck.count).to eq(1)
      expect(character.hand.count).to eq(3)

      expect(card_deck1.reload.location).to eq('hand')
      expect(card_deck2.reload.location).to eq('hand')
      expect(card_deck1.position).to be > card_hand1.position
      expect(character.hand.cards.map(&:id)).to include(card_deck1.id, card_deck2.id, card_hand1.id)
    end

    context 'when deck is empty but discard pile has cards' do
      before do
        character.deck.cards.destroy_all
        character.cards.create!(template: template, location: 'discard', position: 1, id: 101)
        character.reload
      end

      it 'reshuffles discard pile into deck and then draws cards' do
        expect(character.deck.count).to eq(0)
        expect(character.discard_pile.count).to eq(2)
        initial_hand_count = character.hand.count

        drawn_cards = manager.draw_cards_from_deck!(1)
        character.reload

        expect(drawn_cards.count).to eq(1)
        expect(character.hand.count).to eq(initial_hand_count + 1)
        expect(character.hand.cards.pluck(:id)).to include(drawn_cards.first.id)
        expect(character.deck.count).to eq(1)
        expect(character.discard_pile.count).to eq(0)
      end

      it 'draws all cards if requested number is greater than total cards after reshuffle' do
        initial_hand_count = character.hand.count
        drawn_cards = manager.draw_cards_from_deck!(5)
        character.reload

        expect(drawn_cards.count).to eq(2)
        expect(character.hand.count).to eq(initial_hand_count + 2)
        expect(character.deck.count).to eq(0)
        expect(character.discard_pile.count).to eq(0)
      end

      it 'does nothing and returns empty relation if both deck and discard are empty' do
        character.discard_pile.cards.destroy_all
        character.reload
        initial_hand_count = character.hand.count

        drawn_cards = manager.draw_cards_from_deck!(1)
        expect(drawn_cards.count).to eq(0)
        expect(character.hand.count).to eq(initial_hand_count)
      end
    end
  end

  describe '#reshuffle_discard_into_deck!' do
    let!(:card_discard2) { character.cards.create!(template: template, location: 'discard', position: 1) }

    it 'moves all cards from discard pile to deck and shuffles the deck' do
      character.reload
      initial_deck_count = character.deck.count
      initial_discard_count = character.discard_pile.count
      expect(initial_discard_count).to eq(2)

      expect(manager.deck).to receive(:shuffle!).and_call_original
      manager.reshuffle_discard_into_deck!

      expect(character.discard_pile.count).to eq(0)
      expect(character.deck.count).to eq(initial_deck_count + initial_discard_count)
      expect(card_discard1.reload.location).to eq('deck')
      expect(card_discard2.reload.location).to eq('deck')
    end
  end

  describe 'Deck#shuffle!' do
    it 'randomizes positions of cards in deck' do
      initial_deck_card_ids = character.deck.cards.order(:position).pluck(:id)
      original_positions_for_these_ids = character.deck.cards.where(id: initial_deck_card_ids).order(:position).pluck(:position)

      expect(original_positions_for_these_ids.size).to eq(3), "Test setup assumes 3 cards in deck for this specific shuffle assertion"

      guaranteed_shuffled_positions = original_positions_for_these_ids.rotate(1)
      if guaranteed_shuffled_positions == original_positions_for_these_ids && original_positions_for_these_ids.size > 1
        guaranteed_shuffled_positions = original_positions_for_these_ids.reverse
      end
      expect(guaranteed_shuffled_positions).not_to eq(original_positions_for_these_ids), "Stubbed shuffle order should be different from original for the test to be meaningful."

      array_to_be_shuffled = (0...initial_deck_card_ids.size).to_a
      allow(array_to_be_shuffled).to receive(:shuffle).and_return(guaranteed_shuffled_positions)

      expect_any_instance_of(Array).to receive(:shuffle) do |array_instance|
        if array_instance == (0...initial_deck_card_ids.size).to_a
          guaranteed_shuffled_positions
        else
          array_instance.shuffle
        end
      end

      manager.deck.shuffle!

      new_positions_map = character.cards.where(id: initial_deck_card_ids).order(:id).pluck(:id, :position).to_h

      new_positions_ordered_by_initial_ids = initial_deck_card_ids.map { |id| new_positions_map[id] }

      expected_new_positions = []
      initial_deck_card_ids.each_with_index do |card_id, index|
        expected_new_positions << guaranteed_shuffled_positions[index]
      end

      expect(new_positions_ordered_by_initial_ids).to eq(expected_new_positions)
      expect(new_positions_ordered_by_initial_ids).not_to eq(original_positions_for_these_ids)
    end
  end
end

