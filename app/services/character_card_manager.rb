class CharacterCardManager
  include CardBulkOperations
  attr_reader :character, :deck, :hand, :discard_pile

  def initialize(character)
    @character = character
    @deck = Deck.new(character)
    @hand = Hand.new(character)
    @discard_pile = DiscardPile.new(character)
  end

  def draw_cards_from_deck!(number_to_draw = 1)
    return Card.none if number_to_draw <= 0

    cards_drawn = []
    remaining_to_draw = number_to_draw

    popped_from_deck = deck.pop!(remaining_to_draw)
    cards_drawn.concat(popped_from_deck)
    remaining_to_draw -= popped_from_deck.length

    if remaining_to_draw > 0 && deck.empty? && !discard_pile.empty?
      reshuffle_discard_into_deck!
      popped_after_reshuffle = deck.pop!(remaining_to_draw)
      cards_drawn.concat(popped_after_reshuffle)
    end

    return Card.none if cards_drawn.empty?

    hand.add!(cards_drawn)
  end

  def reshuffle_discard_into_deck!
    cards_from_discard = discard_pile.retrieve_all_for_reshuffle!
    return if cards_from_discard.empty?

    deck.add!(cards_from_discard)
    deck.shuffle!
  end

  def transfer_card_to_location!(card_to_move, target_location_name_sym)
    target_location_name = target_location_name_sym.to_s
    current_location_name = card_to_move.location.to_s

    Card.transaction do
      ActiveRecord::Base.connection.execute('SET CONSTRAINTS index_cards_on_owner_loc_pos_uniqueness DEFERRED')

      cards_in_current_location_to_shift = character.cards
                                                   .where(location: current_location_name)
                                                   .where('position > ?', card_to_move.position)
                                                   .order(:position)

      shift_updates = cards_in_current_location_to_shift.map do |card|
        "WHEN #{card.id} THEN #{card.position - 1}"
      end.join(' ')

      if shift_updates.present?
        Card.where(id: cards_in_current_location_to_shift.map(&:id))
            .update_all(["position = CASE id #{shift_updates} ELSE position END, updated_at = ?", Time.current])
      end

      max_pos_in_target_location = character.cards.where(location: target_location_name).maximum(:position) || -1
      new_position = max_pos_in_target_location + 1

      card_to_move.update!(location: target_location_name, position: new_position)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to transfer card #{card_to_move.id} for character #{character.id} to #{target_location_name}: #{e.message}"
    false
  end

  def deal_initial_cards!
    return unless character && character.cards.empty?
    game = character.game
    all_templates = Template.all.to_a
    return if all_templates.empty?

    cards_to_create = []
    total_cards_for_character = Game::CARDS_PER_TEMPLATE_IN_DECK * all_templates.count
    shuffle = (0...total_cards_for_character).to_a.shuffle
    current_idx = 0

    Game::CARDS_PER_TEMPLATE_IN_DECK.times do
      all_templates.each do |template|
        shuffled_position_overall = shuffle[current_idx]
        location = shuffled_position_overall < Game::STARTING_HAND_SIZE ? :hand : :deck
        position_in_location = location == :deck ? shuffled_position_overall - Game::STARTING_HAND_SIZE : shuffled_position_overall

        cards_to_create << {
          owner_character_id: character.id,
          template_id: template.id,
          location: location.to_s,
          position: position_in_location,
          target_type_enum: template.target_type_enum,
          target_count_min: template.target_count_min,
          target_count_max: template.target_count_max,
          target_condition_key: template.target_condition_key,
          created_at: Time.current,
          updated_at: Time.current
        }
        current_idx += 1
      end
    end
    Card.insert_all(cards_to_create, unique_by: :id) if cards_to_create.any?
    character.reload
  end
end
