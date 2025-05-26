require 'rails_helper'

RSpec.describe Initiative, type: :integration do
  let!(:game) { Game.create! }
  let!(:char_a) { game.characters.create!(id: 1, name: 'A', actions_remaining: 2, reactions_remaining: 2) }
  let!(:char_b) { game.characters.create!(id: 2, name: 'B', actions_remaining: 2, reactions_remaining: 2) }
  let!(:char_c) { game.characters.create!(id: 3, name: 'C', actions_remaining: 0, reactions_remaining: 2) }

  let(:initiative) { Initiative.new(game) }

  describe '#current_character' do
    it 'sets and returns the first character by ID if no current character' do
      expect(initiative.current_character).to eq(char_a)
      expect(game.reload.current_character).to eq(char_a)
    end
  end

  describe '#advance!' do
    before do
      game.update!(current_character: char_a)
    end

    context 'during action phase (is_reaction_phase: false)' do
      it 'advances to the next character with actions_remaining > 0' do
        next_char = initiative.advance!(is_reaction_phase: false)
        expect(next_char).to eq(char_b)
        expect(game.reload.current_character).to eq(char_b)
      end

      it 'resets resources for all alive characters when completing a full turn cycle' do
        char_a.update!(actions_remaining: 0, reactions_remaining: 0)
        next_char_is_b = initiative.advance!(is_reaction_phase: false)
        expect(next_char_is_b).to eq(char_b)

        char_b.update!(actions_remaining: 0, reactions_remaining: 0)
        next_char_is_a_after_reset = initiative.advance!(is_reaction_phase: false)

        expect(next_char_is_a_after_reset).to eq(char_a)
        expect(char_a.reload.actions_remaining).to eq(Character::DEFAULT_ACTIONS)
        expect(char_b.reload.actions_remaining).to eq(Character::DEFAULT_ACTIONS)
        expect(char_c.reload.actions_remaining).to eq(Character::DEFAULT_ACTIONS)
      end

      it 'does not reset resources when advancing to a character with actions remaining' do
        game.update!(current_character: char_a)
        char_b.update!(actions_remaining: 1, reactions_remaining: 1)

        expect(char_a).not_to receive(:reset_turn_resources!)
        expect(char_b).not_to receive(:reset_turn_resources!)
        expect(char_c).not_to receive(:reset_turn_resources!)

        next_char = initiative.advance!(is_reaction_phase: false)
        expect(next_char).to eq(char_b)

        expect(char_a.reload.actions_remaining).to eq(2)
        expect(char_b.reload.actions_remaining).to eq(1)
        expect(char_b.reload.reactions_remaining).to eq(1)
      end
    end

    context 'during reaction phase (is_reaction_phase: true)' do
      it 'advances to the next character with reactions_remaining > 0' do
        next_char = initiative.advance!(is_reaction_phase: true)
        expect(next_char).to eq(char_b)
        next_char = initiative.advance!(is_reaction_phase: true)
        expect(next_char).to eq(char_c)
      end

      it 'does not reset resources when cycling in reaction phase' do
        char_a.update!(reactions_remaining: 1)
        char_b.update!(reactions_remaining: 1)
        char_c.update!(reactions_remaining: 1)

        initiative.advance!(is_reaction_phase: true)
        initiative.advance!(is_reaction_phase: true)
        initiative.advance!(is_reaction_phase: true)

        expect(char_a.reload.reactions_remaining).to eq(1)
      end
    end
  end
end
