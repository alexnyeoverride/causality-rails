class DiscardPile
  include CardBulkOperations
  attr_reader :character

  def initialize(character)
    @character = character
  end

  def cards
    character.cards.where(location: 'discard').order(:position)
  end

  def count
    cards.size
  end

  def empty?
    cards.empty?
  end

  def add!(cards_to_add)
    return Card.none if cards_to_add.blank?
    card_ids_to_process = cards_to_add.map(&:id).uniq
    return Card.none if card_ids_to_process.empty?

    updated_ids = []
    Card.transaction do
      max_discard_pos = self.cards.maximum(:position) || -1
      new_positions_map = card_ids_to_process.map.with_index do |card_id, index|
        [card_id, max_discard_pos + 1 + index]
      end.to_h

      updated_ids = bulk_update_cards(
        card_ids_to_update: card_ids_to_process,
        new_positions_map: new_positions_map,
        target_location_name: 'discard'
      )
    end
    Card.where(id: updated_ids).order(:position)
  end

  def retrieve_all_for_reshuffle!
    cards.to_a
  end
end
