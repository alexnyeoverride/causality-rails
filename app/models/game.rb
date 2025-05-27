class Game < ApplicationRecord
  has_many :characters, dependent: :destroy
  has_many :actions, dependent: :destroy

  belongs_to :current_character, class_name: 'Character', foreign_key: 'current_character_id', optional: true
  belongs_to :next_main_turn_character_stashed, class_name: 'Character', foreign_key: 'next_main_turn_character_id_stashed_id', optional: true

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

      total_cards_for_character = CARDS_PER_TEMPLATE_IN_DECK * all_templates.count
      cards_to_create = []
      characters.each do |character|
        shuffle = (0...total_cards_for_character).to_a.shuffle
        current_position = 0
        CARDS_PER_TEMPLATE_IN_DECK.times do
          all_templates.each do |template|
            shuffled_position = shuffle[current_position]
            location = shuffled_position < STARTING_HAND_SIZE ? :hand : :deck
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

      if self.current_character_id.nil? && characters.any?
        first_player = characters.order(:id).first
        self.update!(current_character: first_player, next_main_turn_character_id_stashed_id: first_player.id)
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

    # TODO: validate source_character is current_character

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

    is_root_action = action_to_process.trigger_id.nil?

    ActiveRecord::Base.transaction do
      if is_root_action
        update(next_main_turn_character_id_stashed_id: current_character.id)
      end

      causality.add(action_to_save: action_to_process)
      spent_last_action_point_for_turn = source_character.spend_resource_for_action!(action_to_process)
      all_characters_out_of_reactions = self.characters.alive.where.not(reactions_remaining: 0).none?

      just_finished_reaction_phase = false
      if all_characters_out_of_reactions
        process_actions!
        just_finished_reaction_phase = true
      end

      source_character.card_manager.transfer_card_to_location!(card_record, :table)

      initiative.advance!(is_reaction_phase: causality.get_next_trigger, just_finished_reaction_phase: just_finished_reaction_phase)
      self.reload
    end
    return action_to_process
  end

  def process_actions!
    loop do
      tickable_action = causality.get_next_tickable
      unless tickable_action
        stranded_declared_action = causality.get_next_trigger
        if stranded_declared_action
          can_anyone_react = self.characters.reload.alive.any? { |c| c.reactions_remaining > 0 }
          if !can_anyone_react
            stranded_declared_action.update_column(:phase, :reacted_to)
            next
          else
            break
          end
        else
          break
        end
      end
      
      break unless tickable_action

      tickable_action.on_tick!

      if tickable_action.max_tick_count.present? && tickable_action.max_tick_count > 0
        tickable_action.decrement!(:max_tick_count)
      end

      can_tick_again = tickable_action.can_tick?
      should_resolve_due_to_completion = !can_tick_again ||
        (tickable_action.max_tick_count.present? && tickable_action.max_tick_count <= 0)

      if tickable_action.card.template.name == 'Pass'
        should_resolve_due_to_completion = true
      end

      if should_resolve_due_to_completion && tickable_action.phase.to_s != 'failed'
        tickable_action.update(phase: :resolved)
        if tickable_action.card.location == 'table'
          tickable_action.source.card_manager.transfer_card_to_location!(tickable_action.card, :discard)
        end
      end

      if tickable_action.phase.to_s == 'failed'
        causality.fail_recursively!(tickable_action.id)
      end
    end
  end

  def is_over?
    self.characters.alive.count <= 1
  end
end
