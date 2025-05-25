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

    if !is_reaction_phase
      game.characters.alive.each do |character|
        character.reset_turn_resources!
      end

      first_eligible_after_reset = game.characters.alive.order(:id).find do |char|
        can_take_action?(char, false)
      end

      if first_eligible_after_reset
        game.update!(current_character: first_eligible_after_reset)
        return first_eligible_after_reset
      else
        return nil
      end
    end
    return nil
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
