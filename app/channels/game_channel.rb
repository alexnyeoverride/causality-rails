class GameChannel < ApplicationCable::Channel
  MAX_PLAYERS_PER_GAME = 3

  def subscribed
    @connection_uuid = SecureRandom.uuid
    puts "Client #{@connection_uuid} attempting to subscribe to GameChannel."
  end

  def unsubscribed
    if @current_character_id && @current_game_id
      character = Character.find_by(id: @current_character_id)
      game = Game.find_by(id: @current_game_id) 

      if character && game
        puts "Player Character #{@current_character_id} (Connection #{@connection_uuid}) unsubscribed from Game #{@current_game_id}."
      else
        puts "Client #{@connection_uuid} (Character #{@current_character_id}, Game #{@current_game_id}) unsubscribed, but character or game not found."
      end
    else
      puts "Client #{@connection_uuid} unsubscribed (was not in a game)."
    end
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

      stream_from "game_#{@current_game_id}"

      transmit({
        type: "joined",
        game_id: @current_game_id,
        player_secret: @current_character_id,
        character_id: @current_character_id,
        message: "Game created successfully. You are Character #{character.id} ('#{character.name}')."
      })
      puts "Game #{@current_game_id} created by Character #{@current_character_id} (Connection #{@connection_uuid})"
      broadcast_game_state(@current_game_id)
    end
  rescue ActiveRecord::RecordInvalid => e
    transmit_error("Failed to create game: #{e.message}")
    puts "Error creating game for Connection #{@connection_uuid}: #{e.message}"
  end

  def join_game(data)
    game_id = data["game_id"]
    game = Game.find_by(id: game_id)

    unless game
      transmit_error("Game not found: #{game_id}")
      return
    end

    if @current_game_id
      transmit_error("You are already in a game (Game #{@current_game_id}). Leave it before joining another.")
      return
    end
    
    if game.characters.count >= MAX_PLAYERS_PER_GAME
      transmit_error("Cannot join game: Game is full.")
      return
    end
    
    ActiveRecord::Base.transaction do
      player_name = data.fetch("player_name", "Player #{SecureRandom.hex(2)}")
      character = game.characters.create!(name: player_name)
      character.reset_turn_resources!
      
      @current_game_id = game.id
      @current_character_id = character.id

      stream_from "game_#{@current_game_id}"

      transmit({
        type: "joined",
        game_id: @current_game_id,
        player_secret: @current_character_id,
        character_id: @current_character_id,
        message: "Successfully joined Game #{game.id} as Character #{character.id} ('#{character.name}')."
      })
      puts "Character #{@current_character_id} (Connection #{@connection_uuid}) joined Game #{@current_game_id}"
      broadcast_game_state(@current_game_id)
    end
  rescue ActiveRecord::RecordInvalid => e
    transmit_error("Failed to join game: #{e.message}")
    puts "Error joining game for Connection #{@connection_uuid} to Game #{game_id}: #{e.message}"
  end

  def rejoin_game(data)
    game_id = data["game_id"]
    character_id = data["player_secret"] 

    game = Game.find_by(id: game_id)
    character = game&.characters&.find_by(id: character_id)

    if game && character
      @current_game_id = game.id
      @current_character_id = character.id

      stream_from "game_#{@current_game_id}"

      transmit({
        type: "rejoined",
        game_id: @current_game_id,
        character_id: @current_character_id,
        message: "Successfully rejoined Game #{game.id} as Character #{character.id} ('#{character.name}')."
      })
      puts "Character #{@current_character_id} (Connection #{@connection_uuid}) rejoined Game #{@current_game_id}"
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
    target_ids = data.fetch("target_character_ids", [])
    trigger_action_id = data["trigger_id"] 

    unless card_id
        transmit_error("Card ID must be provided to declare an action.")
        return
    end
    
    begin
      declared_action = game.declare_action(
        source_character_id: @current_character_id,
        card_id: card_id,
        target_ids: target_ids,
        trigger_action_id: trigger_action_id
      )

      if declared_action&.persisted? 
        source_character_name = Character.find(@current_character_id).name
        puts "Character #{@current_character_id} in Game #{@current_game_id} successfully declared Action #{declared_action.id}."
        broadcast_game_state(@current_game_id, "Action #{declared_action.id} declared by #{source_character_name}.")
      elsif declared_action.is_a?(Action) && !declared_action.persisted? && declared_action.errors.any?
        transmit_error("Failed to declare action: #{declared_action.errors.full_messages.join(', ')}")
      else
        transmit_error("Failed to declare action. Preconditions not met or action invalid.")
        puts "Action declaration by Character #{@current_character_id} in Game #{@current_game_id} failed or was invalid."
      end
    rescue StandardError => e
      transmit_error("An unexpected error occurred while declaring action: #{e.message}")
      puts "Unexpected error in declare_action for Character #{@current_character_id}: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    end
  end

  def leave_game(_data)
    unless @current_game_id && @current_character_id
      transmit_error("You are not in a game to leave.")
      return
    end

    game = Game.find_by(id: @current_game_id)
    character = Character.find_by(id: @current_character_id) 

    if game && character 
      puts "Character #{@current_character_id} (#{character.name}, Connection #{@connection_uuid}) is leaving Game #{@current_game_id}."
      
      stop_stream_from "game_#{@current_game_id}"
      
      old_game_id = @current_game_id
      character_name_left = character.name 

      @current_game_id = nil
      @current_character_id = nil

      transmit({ type: "left_game", game_id: old_game_id, message: "You have left the game."})
      broadcast_game_state(old_game_id, "Player #{character_name_left} has left the game.")
    else
      transmit_error("Error leaving game: Game or character not found.")
      @current_game_id = nil 
      @current_character_id = nil
    end
  end

  private

  def broadcast_game_state(game_id, event_message = nil)
    game = Game.includes(
      characters: [:cards], 
      actions: [:card, :source, :action_targets, :trigger]
    ).find_by(id: game_id)
    return unless game

    game_state_payload = {
      id: game.id,
      current_character_id: game.current_character_id,
      characters: game.characters.map do |char|
        {
          id: char.id,
          name: char.name,
          health: char.health,
          actions_remaining: char.actions_remaining,
          reactions_remaining: char.reactions_remaining,
          hand_card_count: char.hand.count,
          deck_card_count: char.deck.count,
          discard_pile_card_count: char.discard_pile.count,
          is_current_player: game.current_character_id == char.id,
          is_alive: char.alive?
        }
      end,
      active_actions: game.actions.where(phase: ['declared', 'reacted_to', 'started']).order(id: :asc).map do |action|
        {
          id: action.id,
          card_id: action.card_id,
          card_name: action.card&.name,
          source_id: action.source_id,
          source_name: action.source&.name,
          phase: action.phase,
          trigger_id: action.trigger_id,
          resolution_timing: action.resolution_timing,
          is_free: action.is_free,
          max_tick_count: action.max_tick_count,
          target_character_ids: action.action_targets.pluck(:target_character_id)
        }
      end,
      is_over: game.is_over?,
      last_event: event_message
    }
    
    ActionCable.server.broadcast("game_#{game_id}", {
      type: "game_state",
      game_state: game_state_payload
    })
    puts "Broadcasted game state for Game #{game_id}."
  end

  def transmit_error(message)
    transmit({ type: "error", message: message })
    error_context = "Client #{@connection_uuid}"
    if @current_character_id
      error_context += " (Character #{@current_character_id}, Game #{@current_game_id || 'N/A'})"
    end
    puts "Error for #{error_context}: #{message}"
  end
end
