class CharacterCardManager
  attr_reader :character, :deck, :hand, :discard_pile

  def initialize(character)
    @character = character
    @deck = Deck.new(character)
    @hand = Hand.new(character)
    @discard_pile = DiscardPile.new(character)
  end

  def draw_cards_from_deck!(number_to_draw = 1)
    return Card.none if number_to_draw <= 0

    cards_popped_from_deck = deck.pop!(number_to_draw)
    return Card.none if cards_popped_from_deck.empty?

    hand.add!(cards_popped_from_deck)
  end

  def discard_cards_from_hand!(card_ids_to_discard)
    return Card.none if card_ids_to_discard.blank?

    actual_cards_removed_from_hand = hand.remove!(card_ids_to_discard)
    return Card.none if actual_cards_removed_from_hand.empty?

    discard_pile.add!(actual_cards_removed_from_hand)
  end

  def reshuffle_discard_into_deck!
    cards_from_discard = discard_pile.retrieve_all_for_reshuffle!
    return if cards_from_discard.empty?

    deck.add!(cards_from_discard)
    deck.shuffle!
  end

  def shuffle_deck!
    deck.shuffle!
  end
end
