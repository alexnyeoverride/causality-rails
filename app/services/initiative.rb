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

  def advance!(is_reaction_phase: false, just_finished_reaction_phase: false)
    alive_characters = game.characters.alive.order(:id).to_a
    return nil if alive_characters.empty?

    current_char_obj = game.current_character

    if just_finished_reaction_phase
      character = Character.alive.where('actions_remaining > 0').where(id: game.next_main_turn_character_id_stashed_id).first
      if character
        game.update(current_character: character)
        return
      elsif game.next_main_turn_character_id_stashed_id
        current_char_obj = Character.find(game.next_main_turn_character_id_stashed_id)
      end
    end

    start_index = current_char_obj ? alive_characters.index(current_char_obj) : -1

    (0...alive_characters.size).each do |i|
      potential_next_character_idx = (start_index + 1 + i) % alive_characters.size
      character_to_check = alive_characters[potential_next_character_idx]

      if can_take_action?(character_to_check, is_reaction_phase)
        game.update!(current_character: character_to_check)
        return character_to_check
      end
    end

    # If it's the action phase, and (as we checked above) no characters have actions left, reset all characters' resources.  It's a new round.
    if !is_reaction_phase
      game.characters.alive.update_all(
        actions_remaining: Character::DEFAULT_ACTIONS,
        reactions_remaining: Character::DEFAULT_REACTIONS,
        updated_at: Time.current
      )

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
