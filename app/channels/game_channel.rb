class GameChannel < ApplicationCable::Channel
  def subscribed
    @connection_uuid = SecureRandom.uuid
  end

  def unsubscribed
    character = Character.find_by(id: @current_character_id) if @current_character_id
    game = Game.find_by(id: @current_game_id) if @current_game_id
    stop_all_streams
  end

  def create_game(data)
    ActiveRecord::Base.transaction do
      game = Game.create!
      player_name = data.fetch("player_name", "Player #{SecureRandom.hex(2)}")
      character = game.characters.create!(name: player_name)

      @current_game_id = game.id
      @current_character_id = character.id

      game.setup_new_game!
      game.reload

      stream_from "game_#{@current_game_id}_character_#{@current_character_id}"

      transmit({
        type: "joined",
        game_id: game.id,
        player_secret: character.id, 
        character_id: character.id,
        message: "Game created successfully. You are Character #{character.id} ('#{character.name}')."
      })
      broadcast_game_state(@current_game_id)
    end
  rescue ActiveRecord::RecordInvalid => e
    transmit_error("Failed to create game: #{e.message}")
  end

  def join_game(data)
    game_id = data["game_id"]
    game = Game.find_by(id: game_id)

    unless game
      transmit_error("Game not found: #{game_id}")
      return
    end

    if @current_game_id && @current_game_id == game.id && @current_character_id
      rejoin_game({ "game_id" => game_id, "player_secret" => @current_character_id })
      return
    elsif @current_game_id
      transmit_error("You are already in a game (Game #{@current_game_id}). Leave it before joining another.")
      return
    end

    if game.characters.count >= Game::MAX_PLAYERS
      transmit_error("Cannot join game: Game is full.")
      return
    end

    ActiveRecord::Base.transaction do
      player_name = data.fetch("player_name", "Player #{SecureRandom.hex(2)}")
      character = game.characters.create!(name: player_name)
      if game.characters.joins(:cards).distinct.count < game.characters.count || character.cards.empty?
         deal_initial_cards_to_character(character) unless character.cards.any?
      end
      character.reset_turn_resources!

      @current_game_id = game.id
      @current_character_id = character.id

      stream_from "game_#{@current_game_id}_character_#{@current_character_id}"

      transmit({
        type: "joined",
        game_id: game.id,
        player_secret: character.id,
        character_id: character.id,
        message: "Successfully joined Game #{game.id} as Character #{character.id} ('#{character.name}')."
      })
      broadcast_game_state(@current_game_id)
    end
  rescue ActiveRecord::RecordInvalid => e
    transmit_error("Failed to join game: #{e.message}")
  end

  def rejoin_game(data)
    game_id = data["game_id"]
    character_id = data["player_secret"]

    game = Game.find_by(id: game_id)
    character = game&.characters&.find_by(id: character_id)

    if game && character
      @current_game_id = game.id
      @current_character_id = character.id

      stream_from "game_#{@current_game_id}_character_#{@current_character_id}"

      transmit({
        type: "rejoined",
        game_id: game.id,
        character_id: character.id,
        message: "Successfully rejoined Game #{game.id} as Character #{character.id} ('#{character.name}')."
      })
      broadcast_game_state(@current_game_id)
    else
      transmit_error("Could not rejoin game. Game or character not found.")
    end
  end

  def declare_action(data)
    unless @current_game_id && @current_character_id
      transmit_error("You are not in a game. Please join or create one.")
      return
    end

    game = Game.find_by(id: @current_game_id)
    unless game
      transmit_error("Current game not found. Please rejoin.")
      return
    end
    
    card_id = data["card_id"]
    target_character_ids = Array(data.fetch("target_character_ids", [])).reject(&:blank?)
    target_card_ids = Array(data.fetch("target_card_ids", [])).reject(&:blank?)
    trigger_action_id = data["trigger_id"]

    unless card_id
        transmit_error("Card ID must be provided to declare an action.")
        return
    end

    begin
      declared_action = game.declare_action(
        source_character_id: @current_character_id,
        card_id: card_id,
        target_character_ids: target_character_ids,
        target_card_ids: target_card_ids,
        trigger_action_id: trigger_action_id
      )

      if declared_action.persisted?
        source_character_name = Character.find(@current_character_id).name
        broadcast_game_state(@current_game_id, "Action #{declared_action.id} declared by #{source_character_name}.")
      elsif declared_action.errors.any?
        transmit_error("Failed to declare action: #{declared_action.errors.full_messages.join(', ')}")
      else
        transmit_error("Failed to declare action. Action was not persisted and had no errors. This indicates a potential issue in the action declaration logic.")
      end
    rescue StandardError => e
      Rails.logger.error "Declare Action Error: #{e.message}\n#{e.backtrace.join("\n")}"
      transmit_error("An unexpected error occurred while declaring action: #{e.message}")
    end
  end

  def leave_game(_data)
    unless @current_game_id && @current_character_id
      transmit_error("You are not in a game to leave.")
      return
    end

    game = Game.find_by(id: @current_game_id)
    character = Character.find_by(id: @current_character_id)

    if game && character && character.game_id == game.id
      stop_stream_from "game_#{@current_game_id}_character_#{@current_character_id}"

      old_game_id = @current_game_id
      character_name_left = character.name

      @current_game_id = nil
      @current_character_id = nil

      transmit({ type: "left_game", game_id: old_game_id, message: "You have left the game."})
      broadcast_game_state(old_game_id, "Player #{character_name_left} has left the game.")
    else
      transmit_error("Error leaving game: Game or character not found, or character not in this game.")
      @current_game_id = nil
      @current_character_id = nil
    end
  end

  private

  def serialize_card(card)
    return nil unless card && card.template
    {
      id: card.id,
      owner_character_id: card.owner_character_id,
      location: card.location.to_s,
      position: card.position,
      name: card.template.name,
      description: card.template.description,
      resolution_timing: card.template.resolution_timing.to_s,
      is_free: card.template.is_free,
      target_type_enum: card.target_type_enum.to_s,
      target_count_min: card.target_count_min,
      target_count_max: card.target_count_max,
      target_condition_key: card.target_condition_key
    }
  end
  
  def deal_initial_cards_to_character(character)
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

  def broadcast_game_state(game_id, event_message = nil)
    game = Game.includes(
      { characters: { cards: :template } },
      { actions: [:source, :trigger, :action_character_targets, :action_card_targets, { card: :template }] }
    ).find_by(id: game_id)

    return unless game

    game.characters.each do |recipient_character|
      game_state_payload = {
        id: game.id,
        current_character_id: game.current_character_id,
        characters: game.characters.map do |char_to_serialize|
          serialized_char = {
            id: char_to_serialize.id,
            name: char_to_serialize.name,
            health: char_to_serialize.health,
            actions_remaining: char_to_serialize.actions_remaining,
            reactions_remaining: char_to_serialize.reactions_remaining,
            hand_card_count: char_to_serialize.hand.count,
            hand_cards: (char_to_serialize.id == recipient_character.id) ? char_to_serialize.hand.cards.map { |card| serialize_card(card) } : [],
            deck_card_count: char_to_serialize.deck.count,
            discard_pile_card_count: char_to_serialize.discard_pile.count,
            is_current_player: game.current_character_id == char_to_serialize.id,
            is_alive: char_to_serialize.alive?
          }
          serialized_char
        end,
        active_actions: game.actions
                           .where(phase: ['declared', 'reacted_to'])
                           .order(id: :asc).map do |action|
          {
            id: action.id,
            card_id: action.card_id,
            source_id: action.source_id,
            source_name: action.source&.name,
            phase: action.phase.to_s,
            trigger_id: action.trigger_id,
            resolution_timing: action.resolution_timing&.to_s,
            is_free: action.is_free,
            max_tick_count: action.max_tick_count,
            target_character_ids: action.action_character_targets.map(&:target_character_id),
            target_card_ids: action.action_card_targets.map(&:target_card_id),
            card: serialize_card(action.card)
          }
        end,
        is_over: game.is_over?,
        last_event: event_message
      }

      ActionCable.server.broadcast("game_#{game.id}_character_#{recipient_character.id}", {
        type: "game_state",
        game_state: game_state_payload
      })
    end
  end

  def transmit_error(message)
    transmit({ type: "error", message: message })
  end
end
