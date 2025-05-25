require 'rails_helper'

RSpec.describe GameChannel, type: :channel do
  let!(:template1) { Template.create!(name: "Test Card 1", description: "Desc 1", resolution_timing: "before", declarability_key: "default_declarability", tick_condition_key: "default_tick_condition", tick_effect_key: "default_tick_effect", max_tick_count: 1) }
  let!(:template2) { Template.create!(name: "Test Card 2", description: "Desc 2", resolution_timing: "after", declarability_key: "default_declarability", tick_condition_key: "default_tick_condition", tick_effect_key: "default_tick_effect", max_tick_count: 2, is_free: true) }
  let!(:pass_template) { Template.create!(name: "Pass", description: "Pass the turn or reaction window.", resolution_timing: "before", declarability_key: "default_declarability", tick_condition_key: "default_tick_condition", tick_effect_key: "pass_effect", max_tick_count: 0, is_free: true) }

  it "successfully subscribes" do
    subscribe
    expect(subscription).to be_confirmed
    expect(subscription.instance_variable_get(:@connection_uuid)).not_to be_nil
  end

  describe "#create_game" do
    before do
      allow(ActionCable.server).to receive(:broadcast)
    end

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
      expect(subscription).to have_stream_from("game_#{game.id}_character_#{character.id}")

      expect(ActionCable.server).to have_received(:broadcast).with("game_#{game.id}_character_#{character.id}", anything)
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

    before do
      allow(ActionCable.server).to receive(:broadcast)
    end

    context "when game is not full" do
      it "allows a player to join, creates a character, transmits and broadcasts" do

        joiner_connection = stub_connection
        subscribe(connection: joiner_connection)

        expect { perform(:join_game, game_id: game.id, player_name: "Joiner") }
          .to change { game.characters.count }.by(1)

        new_character = game.characters.order(:id).last
        expect(new_character.name).to eq("Joiner")

        transmitted_data = transmissions.last
        expect(transmitted_data).to include(
          type: "joined",
          game_id: game.id,
          player_secret: new_character.id,
          character_id: new_character.id,
          message: "Successfully joined Game #{game.id} as Character #{new_character.id} ('Joiner')."
        )
        expect(subscription).to have_stream_from("game_#{game.id}_character_#{new_character.id}")

        expect(ActionCable.server).to have_received(:broadcast).with("game_#{game.id}_character_#{new_character.id}", anything)
        expect(ActionCable.server).to have_received(:broadcast).with("game_#{game.id}_character_#{existing_character.id}", anything)
      end
    end

    context "when game is full" do
      before do
        (Game::MAX_PLAYERS - game.characters.count).times do |i|
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
      expect(transmissions.last).to match(hash_including(type: "error", message: /You are already in a game/))
    end
  end

  describe "#rejoin_game" do
    let!(:game) { Game.create! }
    let!(:character) { game.characters.create!(name: "Player 1") }
    before do
      game.setup_new_game!; game.reload
      allow(ActionCable.server).to receive(:broadcast)
    end


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
      expect(subscription).to have_stream_from("game_#{game.id}_character_#{character.id}")
      expect(ActionCable.server).to have_received(:broadcast).with("game_#{game.id}_character_#{character.id}", anything)
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
    let!(:other_character) { game.characters.create!(name: "Player 2") }


    before do
      game.setup_new_game!
      game.update!(current_character_id: character.id)
      character.reload
      other_character.reload


      @card_to_play = character.hand.cards.joins(:template).find_by(templates: { id: template1.id })
      unless @card_to_play
        @card_to_play = character.cards.create!(
          template: template1,
          location: 'hand',
          position: (character.hand.cards.maximum(:position) || -1) + 1
        )
        character.reload
      end
      expect(@card_to_play).not_to be_nil
      character.update!(actions_remaining: 1)

      subscribe(character_id: character.id)
      perform(:rejoin_game, game_id: game.id, player_secret: character.id)
      allow(ActionCable.server).to receive(:broadcast)
    end

    it "successfully declares an action, changes action count, and broadcasts the event to all character streams" do
      subscription.connection.instance_variable_set(:@transmissions, [])
      initial_action_count = Action.count

      perform(:declare_action, card_id: @card_to_play.id)

      action_record_in_db = Action.where(source_id: character.id, card_id: @card_to_play.id).order(created_at: :desc).first

      if Action.count == initial_action_count
        last_direct_transmission = transmissions.last
        expect(last_direct_transmission).not_to be_nil, "Action count did not change, and no direct error transmission was received."
        expect(last_direct_transmission[:type]).to eq("error"), "Action count did not change. Expected direct error, got: #{last_direct_transmission.inspect}"
        fail "Action.count did not change. GameChannel transmitted error: #{last_direct_transmission[:message]}"
      else
        expect(Action.count).to eq(initial_action_count + 1)
        expect(action_record_in_db).not_to be_nil

        source_character_name = character.name
        game.characters.each do |char_in_game|
            expect(ActionCable.server).to have_received(:broadcast).with(
              "game_#{game.id}_character_#{char_in_game.id}",
              hash_including(
                type: "game_state",
                game_state: hash_including(
                  last_event: "Action #{action_record_in_db.id} declared by #{source_character_name}."
                )
              )
            )
        end
        expect(transmissions).to be_empty
      end
    end

    it "transmits an error if card is not in hand" do
      subscription.connection.instance_variable_set(:@transmissions, [])
      original_card_location = @card_to_play.location
      @card_to_play.update!(location: 'deck')
      character.reload

      expect {
        perform(:declare_action, card_id: @card_to_play.id)
      }.not_to change(Action, :count)

      expect(transmissions.last).to include(
        type: "error",
        message: "Failed to declare action: Card not in player's hand."
      )

      @card_to_play.update!(location: original_card_location)
    end

    it "transmits an error if card_id is missing" do
      subscription.connection.instance_variable_set(:@transmissions, [])
      perform(:declare_action, {})
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(type: "error", message: "Card ID must be provided to declare an action.")
    end

    it "transmits an error if character cannot afford action" do
      subscription.connection.instance_variable_set(:@transmissions, [])
      character.update!(actions_remaining: 0)

      perform(:declare_action, card_id: @card_to_play.id)
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(type: "error", message: "Failed to declare action: Character cannot afford this action.")
    end

    it "transmits an error if action save fails (simulated by Game#declare_action returning errors)" do
      subscription.connection.instance_variable_set(:@transmissions, [])
      game_instance = Game.find(game.id)
      allow(Game).to receive(:find_by).with(id: game.id).and_return(game_instance)

      action_with_errors = Action.new(game: game_instance, card: @card_to_play, source: character)
      action_with_errors.errors.add(:base, "Simulated model validation failure from Game#declare_action.")

      allow(game_instance).to receive(:declare_action).with(
        source_character_id: character.id,
        card_id: @card_to_play.id,
        target_ids: [],
        trigger_action_id: nil
      ).and_return(action_with_errors)

      expect {
        perform(:declare_action, card_id: @card_to_play.id)
      }.not_to change(Action, :count)

      transmitted_data = transmissions.last
      expect(transmitted_data).to include(
        type: "error",
        message: "Failed to declare action: Simulated model validation failure from Game#declare_action."
      )
    end

    it "transmits an error if player is not in a game" do
      subscription.connection.instance_variable_set(:@transmissions, [])
      subscription.instance_variable_set(:@current_game_id, nil)
      subscription.instance_variable_set(:@current_character_id, nil)

      perform(:declare_action, card_id: @card_to_play.id)
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(type: "error", message: "You are not in a game. Please join or create one.")
    end
  end

  describe "game state payload" do
    let!(:game) { Game.create! }
    let!(:char1) { game.characters.create!(name: "Alice", health: 80, actions_remaining: 1, reactions_remaining: 0) }
    let!(:char2) { game.characters.create!(name: "Bob", health: 0) }
    let!(:char3) { game.characters.create!(name: "Carol", health: 100) }


    let!(:alice_card1_obj) { char1.cards.create!(template: template1, location: 'hand', position: 0) }
    let!(:alice_card2_obj) { char1.cards.create!(template: template2, location: 'hand', position: 1) }
    let!(:bob_card1_obj) { char2.cards.create!(template: template1, location: 'hand', position: 0) }
    let!(:carol_deck_card) { char3.cards.create!(template: template1, location: 'deck', position: 0) }
    let!(:carol_discard_card) { char3.cards.create!(template: template2, location: 'discard', position: 0) }


    let!(:active_action_on_table) do
      card_for_action = char1.cards.create!(template: template2, location: 'table', position: 0)
      action = game.actions.create!(
        card: card_for_action,
        source: char1,
        phase: 'declared',
        resolution_timing: template2.resolution_timing,
        is_free: template2.is_free,
        max_tick_count: template2.max_tick_count,
        declarability_key: template2.declarability_key,
        tick_condition_key: template2.tick_condition_key,
        tick_effect_key: template2.tick_effect_key
      )
      action.action_targets.create!(target_character: char3)
      action
    end

    let!(:resolved_action) do
        card_for_resolved_action = char1.cards.create!(template: template1, location: 'discard', position: 10)
        game.actions.create!(
            card: card_for_resolved_action,
            source: char1,
            phase: 'resolved',
            resolution_timing: template1.resolution_timing,
            is_free: template1.is_free,
            max_tick_count: template1.max_tick_count,
            declarability_key: template1.declarability_key,
            tick_condition_key: template1.tick_condition_key,
            tick_effect_key: template1.tick_effect_key
        )
    end


    before do
      char1.cards.create!(template: template1, location: 'deck', position: 0)
      char1.cards.create!(template: template1, location: 'deck', position: 1)
      char1.cards.create!(template: template2, location: 'discard', position: 0)


      game.update!(current_character_id: char1.id)
      game.reload
      char1.reload
      char2.reload
      char3.reload

      allow(ActionCable.server).to receive(:broadcast)
    end

    context "when Alice (char1) triggers a broadcast (e.g. by rejoining)" do
      it "broadcasts comprehensive game state to all character streams" do
        subscribe(character_id: char1.id)
        perform(:rejoin_game, game_id: game.id, player_secret: char1.id)

        expected_alice_payload_for_alice = {
          id: char1.id,
          name: "Alice",
          health: 80,
          actions_remaining: 1,
          reactions_remaining: 0,
          hand_card_count: 2,
          deck_card_count: 2,
          discard_pile_card_count: 2,
          is_current_player: true,
          is_alive: true,
          hand_cards: match_array([
            {id: alice_card1_obj.id, name: template1.name, description: template1.description},
            {id: alice_card2_obj.id, name: template2.name, description: template2.description}
          ])
        }

        expected_bob_payload_for_alice = {
          id: char2.id,
          name: "Bob",
          health: 0,
          actions_remaining: Character::DEFAULT_ACTIONS,
          reactions_remaining: Character::DEFAULT_REACTIONS,
          hand_card_count: 1,
          deck_card_count: 0,
          discard_pile_card_count: 0,
          is_current_player: false,
          is_alive: false
        }

        expected_carol_payload_for_alice = {
            id: char3.id,
            name: "Carol",
            health: 100,
            actions_remaining: Character::DEFAULT_ACTIONS,
            reactions_remaining: Character::DEFAULT_REACTIONS,
            hand_card_count: 0,
            deck_card_count: 1,
            discard_pile_card_count: 1,
            is_current_player: false,
            is_alive: true
        }

        expected_active_actions_payload = [
          hash_including(
            id: active_action_on_table.id,
            card_id: active_action_on_table.card_id,
            card_name: template2.name,
            source_id: char1.id,
            source_name: "Alice",
            phase: "declared",
            trigger_id: nil,
            resolution_timing: template2.resolution_timing.to_s,
            is_free: template2.is_free,
            max_tick_count: template2.max_tick_count,
            target_character_ids: [char3.id]
          )
        ]

        expect(ActionCable.server).to have_received(:broadcast).with(
          "game_#{game.id}_character_#{char1.id}",
          lambda { |payload|
            expect(payload[:type]).to eq("game_state")
            game_state = payload[:game_state]
            expect(game_state[:id]).to eq(game.id)
            expect(game_state[:current_character_id]).to eq(char1.id)
            expect(game_state[:characters]).to match_array([
              hash_including(expected_alice_payload_for_alice),
              hash_including(expected_bob_payload_for_alice),
              hash_including(expected_carol_payload_for_alice)
            ])
            game_state[:characters].each do |char_data|
                if char_data[:id] == char2.id || char_data[:id] == char3.id
                    expect(char_data).not_to have_key(:hand_cards)
                end
            end
            expect(game_state[:active_actions]).to match_array(expected_active_actions_payload)
            expect(game_state[:is_over]).to be false
          }
        )

        expected_alice_payload_for_bob = {
          id: char1.id,
          name: "Alice",
          health: 80,
          actions_remaining: 1,
          reactions_remaining: 0,
          hand_card_count: 2,
          deck_card_count: 2,
          discard_pile_card_count: 2,
          is_current_player: true,
          is_alive: true
        }

        expected_bob_payload_for_bob = {
          id: char2.id,
          name: "Bob",
          health: 0,
          actions_remaining: Character::DEFAULT_ACTIONS,
          reactions_remaining: Character::DEFAULT_REACTIONS,
          hand_card_count: 1,
          deck_card_count: 0,
          discard_pile_card_count: 0,
          is_current_player: false,
          is_alive: false,
          hand_cards: match_array([
             {id: bob_card1_obj.id, name: template1.name, description: template1.description}
          ])
        }
        expected_carol_payload_for_bob = {
            id: char3.id,
            name: "Carol",
            health: 100,
            actions_remaining: Character::DEFAULT_ACTIONS,
            reactions_remaining: Character::DEFAULT_REACTIONS,
            hand_card_count: 0,
            deck_card_count: 1,
            discard_pile_card_count: 1,
            is_current_player: false,
            is_alive: true
        }


        expect(ActionCable.server).to have_received(:broadcast).with(
          "game_#{game.id}_character_#{char2.id}",
          lambda { |payload|
            expect(payload[:type]).to eq("game_state")
            game_state = payload[:game_state]
            expect(game_state[:id]).to eq(game.id)
            expect(game_state[:current_character_id]).to eq(char1.id)
            expect(game_state[:characters]).to match_array([
              hash_including(expected_alice_payload_for_bob),
              hash_including(expected_bob_payload_for_bob),
              hash_including(expected_carol_payload_for_bob)
            ])
            game_state[:characters].each do |char_data|
                if char_data[:id] == char1.id || char_data[:id] == char3.id
                    expect(char_data).not_to have_key(:hand_cards)
                end
            end
            expect(game_state[:active_actions]).to match_array(expected_active_actions_payload)
            expect(game_state[:is_over]).to be false
          }
        )
        
        char1.update!(health: 0)
        game.reload
        
        subscribe(character_id: char3.id)
        perform(:rejoin_game, game_id: game.id, player_secret: char3.id)
        
        expect(ActionCable.server).to have_received(:broadcast).with(
          "game_#{game.id}_character_#{char3.id}",
          hash_including(
            type: "game_state",
            game_state: hash_including(
              is_over: true
            )
          )
        )
      end
    end
  end

  describe "#leave_game" do
    let!(:game) { Game.create! }
    let!(:character) { game.characters.create!(name: "Player 1") }
    let!(:other_char) { game.characters.create!(name: "Player 2") }


    before do
      game.setup_new_game!
      game.update!(current_character_id: character.id)
      character.reload
      other_char.reload

      subscribe(character_id: character.id)
      perform(:rejoin_game, game_id: game.id, player_secret: character.id)
      allow(ActionCable.server).to receive(:broadcast)
    end

    it "allows a player to leave, transmits and broadcasts the event to remaining players' streams" do
      subscription.connection.instance_variable_set(:@transmissions, [])
      perform(:leave_game, {})

      transmitted_data = transmissions.last
      expect(transmitted_data).to include(
        type: "left_game",
        game_id: game.id,
        message: "You have left the game."
      )
      expect(subscription.instance_variable_get(:@current_game_id)).to be_nil
      expect(subscription.instance_variable_set(:@current_character_id, nil))

      expect(ActionCable.server).to have_received(:broadcast).with(
        "game_#{game.id}_character_#{other_char.id}",
        hash_including(
          type: "game_state",
          game_state: hash_including(last_event: "Player #{character.name} has left the game.")
        )
      ).once
    end

    it "transmits an error if player is not in a game" do
      subscription.connection.instance_variable_set(:@transmissions, [])
      subscription.instance_variable_set(:@current_game_id, nil)
      subscription.instance_variable_set(:@current_character_id, nil)

      perform(:leave_game, {})
      transmitted_data = transmissions.last
      expect(transmitted_data).to include(type: "error", message: "You are not in a game to leave.")
    end
  end
end