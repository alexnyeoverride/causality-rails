class Initiative
  attr_reader :game

  def initialize(game)
    @game = game
  end

  def current_character
    game.current_character || set_initial_character
  end

  def set_initial_character
    initial_char_candidate = game.characters.alive.order(:id).first
    if initial_char_candidate && game.current_character_id.nil?
      game.update!(current_character: initial_char_candidate)
    end
    initial_char_candidate
  end

  def advance!(is_reaction_phase: false)
    alive_characters = game.characters.alive.order(:id).to_a
    return nil if alive_characters.empty?

    current_char_obj = game.current_character
    start_index = current_char_obj ? alive_characters.index(current_char_obj) : -1

    (0...alive_characters.size).each do |i|
      potential_next_character_idx = (start_index + 1 + i) % alive_characters.size
      character_to_check = alive_characters[potential_next_character_idx]

      if can_take_action?(character_to_check, is_reaction_phase)
        game.update!(current_character: character_to_check)
        return character_to_check
      end
    end

    # TODO: Wrong. Initiative should advance even during reaction phase.  Add a test.  (reaction initiative doesn't have to be a separate integer tracked and persisted on Game, because we loop back to where we started from when reaction phase ends)
    # TODO: A more advanced test that initiative returns to the expected character when not just one layer of reactions, but multiple layers have completed.
    # TODO: Wrong. Turn resources should not be reset every time initiative advances.  Add a test.
    if !is_reaction_phase
      # TODO: n+1
      game.characters.alive.each do |character|
        character.reset_turn_resources!
      end

      first_eligible_after_reset = game.characters.alive.order(:id).find do |char|
        can_take_action?(char, false)
      end

      if first_eligible_after_reset
        game.update!(current_character: first_eligible_after_reset)
        return first_eligible_after_reset
      end
    end
  end

  private

  def can_take_action?(character, is_reaction_phase)
    return false unless character&.alive?

    if is_reaction_phase
      character.reactions_remaining > 0
    else
      character.actions_remaining > 0
    end
  end
end
