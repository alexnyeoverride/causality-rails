require 'rails_helper'

RSpec.describe Game, type: :model do
  describe '#setup_new_game!' do
    let!(:template1) { Template.create!(name: "Alpha Card", description: "A", resolution_timing: "before", declarability_key: "dk", tick_condition_key: "tck", tick_effect_key: "tek", max_tick_count: 1, target_type_enum: "enemy", target_count_min: 0, target_count_max: 1, target_condition_key: "none") }
    let!(:template2) { Template.create!(name: "Beta Card", description: "B", resolution_timing: "before", declarability_key: "dk", tick_condition_key: "tck", tick_effect_key: "tek", max_tick_count: 1, target_type_enum: "ally", target_count_min: 1, target_count_max: 1, target_condition_key: "is_alive") }
    let!(:template3) { Template.create!(name: "Gamma Card", description: "C", resolution_timing: "before", declarability_key: "dk", tick_condition_key: "tck", tick_effect_key: "tek", max_tick_count: 1, target_type_enum: "ally", target_count_min: 1, target_count_max: 1, target_condition_key: "is_alive") }
    let(:game) { Game.create! }
    let!(:char1) { game.characters.create!(name: 'Player 1') }
    let!(:char2) { game.characters.create!(name: 'Player 2') }

    before do
      stub_const("Game::CARDS_PER_TEMPLATE_IN_DECK", 2)
      stub_const("Game::STARTING_HAND_SIZE", 5)
      game.setup_new_game!
      char1.reload
      char2.reload
    end

    it 'assigns STARTING_HAND_SIZE cards to each character hand' do
      expect(char1.hand.cards.count).to eq(Game::STARTING_HAND_SIZE)
      expect(char2.hand.cards.count).to eq(Game::STARTING_HAND_SIZE)
    end

    it 'assigns the remaining cards to each character deck' do
      total_templates = Template.count
      expected_total_cards_per_character = Game::CARDS_PER_TEMPLATE_IN_DECK * total_templates
      expected_deck_size = expected_total_cards_per_character - Game::STARTING_HAND_SIZE

      expect(char1.deck.cards.count).to eq(expected_deck_size)
      expect(char2.deck.cards.count).to eq(expected_deck_size)
    end

    it 'ensures card positions in hand are 0-indexed and contiguous' do
      [char1, char2].each do |character|
        hand_cards = character.hand.cards.order(:position)
        expect(hand_cards.map(&:position)).to eq((0...Game::STARTING_HAND_SIZE).to_a)
      end
    end

    it 'ensures card positions in deck are 0-indexed and contiguous' do
      total_templates = Template.count
      expected_total_cards_per_character = Game::CARDS_PER_TEMPLATE_IN_DECK * total_templates
      expected_deck_size = expected_total_cards_per_character - Game::STARTING_HAND_SIZE

      [char1, char2].each do |character|
        deck_cards = character.deck.cards.order(:position)
        expect(deck_cards.map(&:position)).to eq((0...expected_deck_size).to_a)
      end
    end

    it 'creates cards with attributes copied from templates' do
      card_in_hand = char1.hand.cards.first
      expect(card_in_hand).not_to be_nil
      expect(card_in_hand.target_type_enum).to eq(card_in_hand.template.target_type_enum)
      expect(card_in_hand.target_count_min).to eq(card_in_hand.template.target_count_min)
      expect(card_in_hand.target_count_max).to eq(card_in_hand.template.target_count_max)
      expect(card_in_hand.target_condition_key).to eq(card_in_hand.template.target_condition_key)
    end

    it 'results in a shuffled distribution of cards (probabilistic check)' do
      all_templates_in_creation_order = []
      Game::CARDS_PER_TEMPLATE_IN_DECK.times do
        all_templates_in_creation_order.concat(Template.order(:id).to_a) 
      end

      char1_hand_template_ids = char1.hand.cards.order(:position).map(&:template_id)
      first_n_template_ids_if_not_shuffled = all_templates_in_creation_order.first(Game::STARTING_HAND_SIZE).map(&:id)
      
      total_templates_count = Template.count
      if total_templates_count > 1 && Game::STARTING_HAND_SIZE < (Game::CARDS_PER_TEMPLATE_IN_DECK * total_templates_count) && Game::STARTING_HAND_SIZE > 0
        expect(char1_hand_template_ids).not_to eq(first_n_template_ids_if_not_shuffled)
      end
    end

    it 'sets the current character for the game if it was not set' do
      new_game = Game.create!
      new_char = new_game.characters.create!(name: "Solo Player")
      expect(new_game.current_character_id).to be_nil
      new_game.setup_new_game!
      expect(new_game.current_character_id).to eq(new_char.id)
    end
  end
end
