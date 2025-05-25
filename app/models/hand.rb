class Hand
  include CardBulkOperations
  attr_reader :character

  def initialize(character)
    @character = character
  end

  def cards
    character.cards.where(location: 'hand').order(:position)
  end

  def count
    cards.size
  end

  def empty?
    cards.empty?
  end

  def find_card(card_id)
    cards.find_by(id: card_id)
  end

  def add!(cards_to_add)
    return Card.none if cards_to_add.blank?
    card_ids_to_process = cards_to_add.map(&:id).uniq
    return Card.none if card_ids_to_process.empty?

    updated_ids = []
    Card.transaction do
      max_hand_pos = self.cards.maximum(:position) || -1
      new_positions_map = card_ids_to_process.map.with_index do |card_id, index|
        [card_id, max_hand_pos + 1 + index]
      end.to_h

      updated_ids = bulk_update_cards(
        card_ids_to_update: card_ids_to_process,
        new_positions_map: new_positions_map,
        target_location_name: 'hand'
      )
    end
    Card.where(id: updated_ids).order(:position)
  end

  def remove!(card_ids_to_remove)
    return [] if card_ids_to_remove.blank?
    safe_card_ids = card_ids_to_remove.map(&:to_i).uniq
    cards_in_hand_to_remove = self.cards.where(id: safe_card_ids).to_a
    return [] if cards_in_hand_to_remove.empty?
    cards_in_hand_to_remove
  end
end
