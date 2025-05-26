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

  def setup_new_game!
    return unless characters.any?

    ActiveRecord::Base.transaction do
      all_templates = Template.all.to_a
      return if all_templates.empty?

      characters.each do |character|
        deck_cards_to_create = []
        CARDS_PER_TEMPLATE_IN_DECK.times do
          all_templates.each do |template|
            deck_cards_to_create << { owner_character_id: character.id, template_id: template.id, location: 'deck' }
          end
        end
        # TODO: this violates the uniqueness constraint on card (character,location,position)
        Card.insert_all(deck_cards_to_create)

        # TODO: this is n+1
        Card.where(owner_character_id: character.id, location: 'deck').find_each do |card|
          template = all_templates.find { |t| t.id == card.template_id}
          next unless template
          card.target_type_enum = template.target_type_enum
          card.target_count_min = template.target_count_min
          card.target_count_max = template.target_count_max
          card.target_condition_key = template.target_condition_key
          card.save!
        end

        character.shuffle_deck!
        character.draw_cards_from_deck!(STARTING_HAND_SIZE)
        character.reset_turn_resources!
      end

      if characters.any? && self.current_character_id.nil?
        self.update!(current_character_id: characters.order(:id).first.id)
      end
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

    unless source_character.alive?
      action_to_process.errors.add(:base, "Source character is not alive.")
      return action_to_process
    end

    unless source_character.find_card_in_hand(card_record.id)
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
    # TODO: Consider how "enchantments" or "auras" might modify actions before they tick,
    # or react to actions being processed. This might involve checking a game-level
    # list of active global effects or character-specific persistent effects.

    while (tickable_action = causality.get_next_tickable) do
      tickable_action.on_tick!

      if tickable_action.max_tick_count.present? && tickable_action.max_tick_count > 0
        tickable_action.decrement!(:max_tick_count) if tickable_action.persisted?
      end

      tickable_action.reload

      can_tick_again = tickable_action.can_tick?
      should_resolve_due_to_completion = !can_tick_again || \
        (tickable_action.max_tick_count.present? && tickable_action.max_tick_count <= 0)

      if tickable_action.card.name == 'Pass' && !can_tick_again && tickable_action.phase.to_s == 'declared'
        should_resolve_due_to_completion = true
      end

      if should_resolve_due_to_completion && !['resolved', 'failed'].include?(tickable_action.phase.to_s)
        tickable_action.update!(phase: 'resolved')
        if tickable_action.card.location.to_s == 'table'
            tickable_action.source.discard_pile.add!([tickable_action.card])
        end
      end

      tickable_action.reload

      if tickable_action.phase.to_s == 'failed'
        unresolved_reactions_exist = tickable_action.reactions.any? do |r|
          !['resolved', 'failed'].include?(r.phase.to_s)
        end

        if unresolved_reactions_exist
          failed_action_data = causality.fail_recursively!(tickable_action.id)

          if failed_action_data.any?
            cards_to_discard_by_owner_id = failed_action_data.group_by { |data| data["source_id"] }.transform_values do |data_array|
              data_array.map { |data| data["card_id"] }.uniq
            end

            owner_ids = cards_to_discard_by_owner_id.keys
            owners_map = Character.where(id: owner_ids).index_by(&:id)

            owners_map.each do |owner_id, owner|
              card_ids_for_this_owner = cards_to_discard_by_owner_id[owner_id]
              next if card_ids_for_this_owner.blank?

              cards_on_table_to_discard = Card.where(id: card_ids_for_this_owner, location: 'table', owner_character_id: owner_id)

              if cards_on_table_to_discard.any?
                owner.discard_pile.add!(cards_on_table_to_discard.to_a)
              end
            end
          end
        elsif tickable_action.card.location.to_s == 'table'
          tickable_action.source.discard_pile.add!([tickable_action.card])
        end
      end
    end
  end

  def is_over?
    self.characters.alive.count <= 1
  end
end

