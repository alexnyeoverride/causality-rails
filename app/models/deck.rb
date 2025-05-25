class Deck
  include CardBulkOperations
  attr_reader :character

  def initialize(character)
    @character = character
  end

  def cards
    character.cards.where(location: 'deck').order(:position)
  end

  def count
    cards.size
  end

  def empty?
    cards.empty?
  end

  def first
    cards.first
  end

  def last
    cards.last
  end

  def shuffle!
    current_deck_cards_scope = cards
    return if current_deck_cards_scope.empty?

    current_deck_card_ids = current_deck_cards_scope.pluck(:id)
    return if current_deck_card_ids.empty?

    new_positions_list = (0...current_deck_card_ids.size).to_a.shuffle
    card_to_new_position_map = current_deck_card_ids.map.with_index do |card_id, index|
      [card_id, new_positions_list[index]]
    end.to_h

    Card.transaction do
      bulk_update_cards(
        card_ids_to_update: card_to_new_position_map.keys,
        new_positions_map: card_to_new_position_map,
        target_location_name: 'deck'
      )
    end
  end

  def pop!(number_to_draw = 1)
    return Card.none if number_to_draw <= 0
    cards_to_pop = cards.limit(number_to_draw).to_a
    cards_to_pop
  end

  def add!(cards_to_add)
    return Card.none if cards_to_add.blank?

    card_ids_to_process = cards_to_add.map(&:id).uniq
    return Card.none if card_ids_to_process.empty?

    updated_ids = []
    Card.transaction do
      max_deck_pos = self.cards.maximum(:position) || -1
      new_positions_map = card_ids_to_process.map.with_index do |card_id, index|
        [card_id, max_deck_pos + 1 + index]
      end.to_h

      updated_ids = bulk_update_cards(
        card_ids_to_update: card_ids_to_process,
        new_positions_map: new_positions_map,
        target_location_name: 'deck'
      )
    end
    Card.where(id: updated_ids).order(:position)
  end
end
