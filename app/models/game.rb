class Game < ApplicationRecord
  has_many :characters, dependent: :destroy
  has_many :actions, dependent: :destroy

  belongs_to :current_character, class_name: 'Character', foreign_key: 'current_character_id', optional: true

  STARTING_HAND_SIZE = 5
  CARDS_PER_TEMPLATE_IN_DECK = 2
  MAX_PLAYERS = 3

  def initiative
    @initiative ||= Initiative.new(self)
  end

  def causality
    @causality ||= Causality.new(self)
  end

  # TODO: ensure this is called only after all characters have joined / been created.
  # Otherwise only the creator will have a shuffled deck.  Or cards at all for that matter.
  def setup_new_game!
    return unless characters.any?

    ActiveRecord::Base.transaction do
      all_templates = Template.all.to_a
      return if all_templates.empty?

      # Optimized to bulk create all cards for all characters in one query.
      # This includes ensuring:
      #  - characters have cards in hand and the remainder in their deck
      #  - decks are shuffled
      #  - each card has a unique position in its location
      #  - positions start at 0 for each container
      total_cards_for_character = CARDS_PER_TEMPLATE_IN_DECK * all_templates.count
      cards_to_create = []
      characters.each do |character|
        shuffle = (0...total_cards_for_character).to_a.shuffle
        current_position = 0
        CARDS_PER_TEMPLATE_IN_DECK.times do
          all_templates.each do |template|
            shuffled_position = shuffle[current_position]
            location = shuffled_position < STARTING_HAND_SIZE ? :hand : :deck
            # Reset counting so positions start at 0 in the deck too.
            position = location == :deck ? shuffled_position - STARTING_HAND_SIZE : shuffled_position
            cards_to_create << {
              owner_character_id: character.id,
              template_id: template.id,
              location: location,
              position: position,
              target_type_enum: template.target_type_enum,
              target_count_min: template.target_count_min,
              target_count_max: template.target_count_max,
              target_condition_key: template.target_condition_key,
              created_at: Time.current,
              updated_at: Time.current
            }
            current_position += 1
          end
        end
      end
      Card.insert_all(cards_to_create, unique_by: :id)

      self.update!(current_character_id: characters.order(:id).first.id)
    end
  end

  def declare_action(source_character_id:, card_id:, target_character_ids: [], target_card_ids: [], trigger_action_id: nil)
    action_to_process = Action.new(game: self)

    source_character = self.characters.find_by(id: source_character_id)
    unless source_character
      action_to_process.errors.add(:base, "Source character not found.")
      return action_to_process
    end
    action_to_process.source = source_character

    card_record = source_character.cards.find_by(id: card_id)
    unless card_record
      action_to_process.errors.add(:base, "Card not found for character.")
      return action_to_process
    end
    action_to_process.card = card_record

    action_to_process.initialize_from_template_and_attributes(
      card_record.template,
      source_character,
      {
        trigger_id: trigger_action_id,
        target_character_ids: target_character_ids,
        target_card_ids: target_card_ids
      }
    )

    # TODO: do these belong as validations on `Action` itself?
    unless source_character.alive?
      action_to_process.errors.add(:base, "Source character is not alive.")
      return action_to_process
    end

    unless card_record.location == 'hand'
      action_to_process.errors.add(:base, "Card not in player's hand.")
      return action_to_process
    end

    unless source_character.can_afford_action?(action_to_process)
      action_to_process.errors.add(:base, "Character cannot afford this action.")
      return action_to_process
    end

    unless action_to_process.can_declare?
      action_to_process.errors.add(:base, "Action cannot be declared at this time (preconditions failed).")
      return action_to_process
    end

    ActiveRecord::Base.transaction do
      causality.add(action_to_save: action_to_process)

      if action_to_process.persisted?
        max_pos_on_table = Card.where(owner_character_id: source_character.id, location: 'table').maximum(:position) || -1
        new_pos_on_table = max_pos_on_table + 1
        card_to_move = action_to_process.card
        card_to_move.update!(location: 'table', position: new_pos_on_table)

        spent_last_of_resource = source_character.spend_resource_for_action!(action_to_process)

        if spent_last_of_resource
          is_reaction = !action_to_process.trigger_id.nil?
          initiative.advance!(is_reaction_phase: is_reaction)
          # TODO: notify client of initiative advancement
          self.reload
        end
      end
    end

    if action_to_process.persisted?
      no_pending_triggers = causality.get_next_trigger.nil?
      all_characters_out_of_reactions = self.characters.alive.all? { |c| c.reactions_remaining == 0 }

      if no_pending_triggers || all_characters_out_of_reactions
        process_actions!
      end
    end

    return action_to_process
  end

  def process_actions!
    while (tickable_action = causality.get_next_tickable) do
      tickable_action.on_tick!

      if tickable_action.max_tick_count.present? && tickable_action.max_tick_count > 0
        tickable_action.decrement!(:max_tick_count)
      end

      can_tick_again = tickable_action.can_tick?
      should_resolve_due_to_completion = !can_tick_again ||
        (tickable_action.max_tick_count.present? && tickable_action.max_tick_count <= 0)

      if tickable_action.card.name == 'Pass'
        should_resolve_due_to_completion = true
      end

      if should_resolve_due_to_completion && tickable_action.phase != 'failed'
        tickable_action.update(phase: :resolved)

        # TODO: create reusable repositioning logic for arbitary container-to-container transfers, and put that in the bulk operations concern.
        # `transfer(from: :table, to: :discard, for: action.source)` 
        max_discard_pos = tickable_action.source.cards.where(location: 'discard').maximum(:position) || -1
        new_position_in_discard = max_discard_pos + 1
        tickable_action.card.update(
          location: :discard,
          position: new_position_in_discard
        )
      end

      if tickable_action.phase.to_s == 'failed'
        failed_action_data = causality.fail_recursively!(tickable_action.id)
        # TODO: notify client of card ids to animate as discarded
      end
      # TODO: notify client of cards which were resolved and which were failed.  Also notify of any which ticked but did not finish.
    end
  end

  def is_over?
    self.characters.alive.count <= 1
  end
end

