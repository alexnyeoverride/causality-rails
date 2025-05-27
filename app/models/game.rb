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
      causality.add(action_to_save: action_to_process)

      if action_to_process.persisted?
        source_character.card_manager.transfer_card_to_location!(card_record, :table)
        spent_last_action_point_for_turn = source_character.spend_resource_for_action!(action_to_process)

        if is_root_action
          current_game_state_for_stash_check = Game.find(self.id)
          initiative_for_peeking = Initiative.new(current_game_state_for_stash_check)
          actor_for_stash_check = characters.alive.find { |c| c.id == source_character_id }

          if actor_for_stash_check
            if spent_last_action_point_for_turn || actor_for_stash_check.actions_remaining == 0
              next_main_actor = initiative_for_peeking.find_next_character_for_phase(actor_for_stash_check, false)
              self.next_main_turn_character_id_stashed_id = next_main_actor&.id
            else
              self.next_main_turn_character_id_stashed_id = actor_for_stash_check.id
            end
            self.save!(touch: false) if self.changed_for_autosave?
          end
        end

        initiative.advance!(is_reaction_phase: !is_root_action)
        self.reload
      else
        return action_to_process
      end
    end

    if action_to_process.persisted?
      no_pending_triggers = causality.get_next_trigger.nil?
      all_characters_out_of_reactions = self.characters.reload.alive.all? { |c| c.reactions_remaining == 0 }

      if no_pending_triggers || all_characters_out_of_reactions
        process_actions!

        is_reaction_cascade_fully_complete = causality.get_next_trigger.nil? &&
                                            self.characters.reload.alive.all? { |c| c.reactions_remaining == 0 } &&
                                            !self.actions.where.not(phase: ['resolved', 'failed']).exists?

        if is_reaction_cascade_fully_complete
          stashed_id = self.next_main_turn_character_id_stashed_id
          if stashed_id
            stashed_next_player = self.characters.reload.find_by(id: stashed_id)
            if stashed_next_player&.alive? && stashed_next_player.actions_remaining > 0
              self.update!(current_character: stashed_next_player)
            else
              self.initiative.advance!(is_reaction_phase: false)
            end
          else
            self.initiative.advance!(is_reaction_phase: false)
          end
          self.update!(next_main_turn_character_id_stashed_id: nil)
        end
      end
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
