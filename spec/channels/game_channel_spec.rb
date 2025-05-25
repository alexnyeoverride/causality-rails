require 'rails_helper'

RSpec.describe GameChannel, type: :channel do
  let!(:template1) { Template.create!(name: "Test Card 1", description: "desc", resolution_timing: "before", declarability_key: "always", tick_condition_key: "always", tick_effect_key: "none", max_tick_count: 0) }
  let!(:template2) { Template.create!(name: "Test Card 2", description: "desc", resolution_timing: "after", declarability_key: "always", tick_condition_key: "always", tick_effect_key: "none", max_tick_count: 0) }
  let!(:pass_template) { Template.create!(name: "Pass", description: "Pass the turn or reaction window.", resolution_timing: "before", declarability_key: "always", tick_condition_key: "always", tick_effect_key: "pass", max_tick_count: 0, is_free: true) }

  before do
    allow_any_instance_of(GameChannel).to receive(:puts)
    allow(ActionCable.server).to receive(:broadcast)
  end

  it "successfully subscribes" do
    subscribe
    expect(subscription).to be_confirmed
    expect(subscription.instance_variable_get(:@connection_uuid)).not_to be_nil
  end

  describe "#create_game" do
    it "creates a new game and character, sets up the game, and transmits/broadcasts" do
      subscribe
      expect { perform(:create_game, player_name: "Creator") }
        .to change(Game, :count).by(1)
        .and change(Character, :count).by(1)

      expect(subscription).to be_confirmed
      game = Game.last
      character = Character.last

      expect(character.name).to eq("Creator")
      expect(game.characters.first).to eq(character)
      expect(game.current_character_id).to eq(character.id)
      expect(character.hand.count).to eq(Game::STARTING_HAND_SIZE)

      transmitted_data = transmissions.last
      expect(transmitted_data).to include(
        type: "joined",
        game_id: game.id,
        player_secret: character.id,
        character_id: character.id,
        message: "Game created successfully. You are Character #{character.id} ('Creator')."
      )
      expect(subscription).to have_stream_from("game_#{game.id}")
      
      expect(ActionCable.server).to have_received(:broadcast).with("game_#{game.id}", anything)
    end
  end

  describe "#join_game" do
    let!(:game) { Game.create! }
    let!(:existing_character) do
        char = game.characters.create!(name: "Player 1")
        game.setup_new_game! 
        game.reload
        char
    end

    context "when game is not full" do
      it "allows a player to join, creates a character, transmits and broadcasts" do
        
        joiner_connection = stub_connection
        joiner_subscription = subscribe(connection: joiner_connection)
        
        expect { joiner_subscription.perform(:join_game, game_id: game.id, player_name: "Joiner") }
          .to change { game.characters.count }.by(1)

        new_character = game.characters.order(:id).last
        expect(new_character.name).to eq("Joiner")

        # Access transmissions from the joiner_subscription
        transmitted_data = joiner_subscription.transmissions.last
        expect(transmitted_data).to include(
          type: "joined",
          game_id: game.id,
          player_secret: new_character.id,
          character_id: new_character.id,
          message: "Successfully joined Game #{game.id} as Character #{new_character.id} ('Joiner')."
        )
        expect(joiner_subscription).to have_stream_from("game_#{game.id}")
        expect(ActionCable.server).to have_received(:broadcast).with("game_#{game.id}", anything)
      end
    end

    context "when game is full" do
      before do
        (GameChannel::MAX_PLAYERS_PER_GAME - game.characters.count).times do |i|
          game.characters.create!(name: "Filler #{i+1}")
        end
      end

      it "does not allow a player to join and transmits an error" do
        subscribe
        expect { perform(:join_game, game_id: game.id, player_name: "Late Joiner") }
          .not_to change { game.characters.count }

        transmitted_data = transmissions.last
        expect(transmitted_data).to include(
          type: "error",
          message: "Cannot join game: Game is full."
        )
      end
    end

    it "transmits an error if game_id is invalid" do
      subscribe
      perform(:join_game, game_id: "invalid_id", player_name: "Joiner")
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(
        type: "error",
        message: "Game not found: invalid_id"
      )
    end
    
    it "transmits an error if player is already in a game" do
      subscribe
      perform(:create_game, player_name: "Creator")
      
      another_game = Game.create!
      
      perform(:join_game, game_id: another_game.id, player_name: "Joiner Attempt")
      expect(subscription.transmissions.last).to match(hash_including(type: "error", message: /You are already in a game/))
    end
  end

  describe "#rejoin_game" do
    let!(:game) { Game.create! }
    let!(:character) { game.characters.create!(name: "Player 1") }
    before { game.setup_new_game!; game.reload }

    it "allows a player to rejoin successfully" do
      subscribe
      perform(:rejoin_game, game_id: game.id, player_secret: character.id)

      transmitted_data = transmissions.last
      expect(transmitted_data).to include(
        type: "rejoined",
        game_id: game.id,
        character_id: character.id,
        message: "Successfully rejoined Game #{game.id} as Character #{character.id} ('Player 1')."
      )
      expect(subscription).to have_stream_from("game_#{game.id}")
      expect(ActionCable.server).to have_received(:broadcast).with("game_#{game.id}", anything)
    end

    it "transmits error for invalid game_id" do
      subscribe
      perform(:rejoin_game, game_id: "invalid_id", player_secret: character.id)
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(type: "error", message: "Could not rejoin game. Game or character not found.")
    end

    it "transmits error for invalid player_secret (character_id)" do
      subscribe
      perform(:rejoin_game, game_id: game.id, player_secret: "invalid_char_id")
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(type: "error", message: "Could not rejoin game. Game or character not found.")
    end
  end

  describe "#declare_action" do
    let!(:game) { Game.create! }
    let!(:character) { game.characters.create!(name: "Player 1") }
    let!(:card_in_hand) { character.cards.create!(template: template1, location: 'hand', position: 0)}

    before do
      game.setup_new_game!
      game.update!(current_character_id: character.id) 
      character.reload
      unless character.hand.cards.any? { |c| c.template_id == template1.id && c.location == 'hand' }
         character.cards.create!(template: template1, location: 'hand', position: (character.hand.cards.maximum(:position) || -1) + 1)
         character.reload
      end
      @card_to_play = character.hand.cards.first 
      character.update!(actions_remaining: 1) 

      subscribe
      perform(:rejoin_game, game_id: game.id, player_secret: character.id) 
      subscription.transmissions.clear 
    end

    it "successfully declares an action" do
      expect { perform(:declare_action, card_id: @card_to_play.id) }
        .to change(Action, :count).by(1)
      expect(ActionCable.server).to have_received(:broadcast).with("game_#{game.id}", anything)
    end

    it "transmits an error if card_id is missing" do
      perform(:declare_action, {}) 
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(type: "error", message: "Card ID must be provided to declare an action.")
    end
    
    it "transmits an error if action declaration fails preconditions (returns nil from game.declare_action)" do
      current_game_in_test = Game.find(game.id) 
      allow(current_game_in_test).to receive(:declare_action).and_return(nil)
      allow(Game).to receive(:find_by).with(id: game.id).and_return(current_game_in_test)
      
      perform(:declare_action, card_id: @card_to_play.id)
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(type: "error", message: "Failed to declare action. Preconditions not met or action invalid.")
    end
    
    it "transmits an error if action declaration returns AR object with errors" do
        mock_action_with_errors = Action.new
        mock_action_with_errors.errors.add(:base, "Custom validation failed")
        
        current_game_in_test = Game.find(game.id)
        allow(current_game_in_test).to receive(:declare_action).and_return(mock_action_with_errors)
        allow(Game).to receive(:find_by).with(id: game.id).and_return(current_game_in_test)

        perform(:declare_action, card_id: @card_to_play.id)
        transmitted_data = transmissions.last
        expect(transmitted_data).to include(type: "error", message: "Failed to declare action: Base Custom validation failed")
    end

    it "transmits an error if player is not in a game" do
      subscription.instance_variable_set(:@current_game_id, nil)
      subscription.instance_variable_set(:@current_character_id, nil)
      
      perform(:declare_action, card_id: @card_to_play.id)
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(type: "error", message: "You are not in a game. Please join or create one.")
    end
  end

  describe "#leave_game" do
    let!(:game) { Game.create! }
    let!(:character) { game.characters.create!(name: "Player 1") }
    
    before do
      game.setup_new_game!
      subscribe
      perform(:rejoin_game, game_id: game.id, player_secret: character.id) 
      subscription.transmissions.clear
    end

    it "allows a player to leave, transmits and broadcasts" do
      perform(:leave_game, {})
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(
        type: "left_game",
        game_id: game.id,
        message: "You have left the game."
      )
      expect(subscription.instance_variable_get(:@current_game_id)).to be_nil
      expect(subscription.instance_variable_get(:@current_character_id)).to be_nil
      expect(ActionCable.server).to have_received(:broadcast).with("game_#{game.id}", anything)
    end

    it "transmits an error if player is not in a game" do
      subscription.instance_variable_set(:@current_game_id, nil)
      subscription.instance_variable_set(:@current_character_id, nil)
      
      perform(:leave_game, {})
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(type: "error", message: "You are not in a game to leave.")
    end
  end
end
