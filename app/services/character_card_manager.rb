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
end

