require 'rails_helper'

RSpec.describe GameChannel, type: :channel do
  let!(:template1) { Template.create!(name: "Test Card 1", description: "Desc 1", resolution_timing: "before", declarability_key: "default_declarability", tick_condition_key: "default_tick_condition", tick_effect_key: "default_tick_effect", max_tick_count: 1, target_type_enum: "enemy", target_count_min: 0, target_count_max: 1, target_condition_key: "") }
  let!(:template2) { Template.create!(name: "Test Card 2", description: "Desc 2", resolution_timing: "after", declarability_key: "default_declarability", tick_condition_key: "default_tick_condition", tick_effect_key: "default_tick_effect", max_tick_count: 2, is_free: true, target_type_enum: "ally", target_count_min: 1, target_count_max: 1, target_condition_key: "is_alive") }
  let!(:pass_template) { Template.create!(name: "Pass", description: "Pass the turn or reaction window.", resolution_timing: "before", declarability_key: "default_declarability", tick_condition_key: "default_tick_condition", tick_effect_key: "pass_effect", max_tick_count: 0, is_free: true, target_type_enum: "enemy", target_count_min: 0, target_count_max: 0, target_condition_key: "" ) }

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
          position: (character.hand.cards.maximum(:position) || -1) + 1,
          target_type_enum: template1.target_type_enum,
          target_count_min: template1.target_count_min,
          target_count_max: template1.target_count_max,
          target_condition_key: template1.target_condition_key
        )
        character.reload
      end
      expect(@card_to_play).not_to be_nil, "Card with template1 should be in character's hand"
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
      @card_to_play.update!(location: 'deck', position: character.deck.cards.count)
      character.reload

      expect {
        perform(:declare_action, card_id: @card_to_play.id)
      }.not_to change(Action, :count)

      expect(transmissions.last).to include(
        type: "error",
        message: "Failed to declare action: Card not in player's hand."
      )
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
        target_character_ids: [],
        target_card_ids: [],
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

    let!(:alice_card1_obj) { char1.cards.create!(template: template1, location: 'hand', position: 0, target_type_enum: template1.target_type_enum, target_count_min: template1.target_count_min, target_count_max: template1.target_count_max, target_condition_key: template1.target_condition_key) }
    let!(:alice_card2_obj) { char1.cards.create!(template: template2, location: 'hand', position: 1, target_type_enum: template2.target_type_enum, target_count_min: template2.target_count_min, target_count_max: template2.target_count_max, target_condition_key: template2.target_condition_key) }
    let!(:alice_pass_card_obj) { char1.cards.create!(template: pass_template, location: 'hand', position: 2, target_type_enum: pass_template.target_type_enum, target_count_min: pass_template.target_count_min, target_count_max: pass_template.target_count_max, target_condition_key: pass_template.target_condition_key) }

    let!(:bob_card1_obj) { char2.cards.create!(template: template1, location: 'hand', position: 0, target_type_enum: template1.target_type_enum, target_count_min: template1.target_count_min, target_count_max: template1.target_count_max, target_condition_key: template1.target_condition_key) }
    let!(:carol_deck_card) { char3.cards.create!(template: template1, location: 'deck', position: 0, target_type_enum: template1.target_type_enum, target_count_min: template1.target_count_min, target_count_max: template1.target_count_max, target_condition_key: template1.target_condition_key) }
    let!(:carol_discard_card) { char3.cards.create!(template: template2, location: 'discard', position: 0, target_type_enum: template2.target_type_enum, target_count_min: template2.target_count_min, target_count_max: template2.target_count_max, target_condition_key: template2.target_condition_key) }

    let!(:active_action_on_table) do
      card_for_action = char1.cards.create!(template: template2, location: 'table', position: 0, target_type_enum: template2.target_type_enum, target_count_min: template2.target_count_min, target_count_max: template2.target_count_max, target_condition_key: template2.target_condition_key)
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
      action.action_character_targets.create!(target_character: char3)
      action
    end

    let!(:resolved_action) do
      card_for_resolved_action = char1.cards.create!(template: template1, location: 'discard', position: 10, target_type_enum: template1.target_type_enum, target_count_min: template1.target_count_min, target_count_max: template1.target_count_max, target_condition_key: template1.target_condition_key)
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
      char1.cards.create!(template: template1, location: 'deck', position: 0, target_type_enum: template1.target_type_enum, target_count_min: template1.target_count_min, target_count_max: template1.target_count_max, target_condition_key: template1.target_condition_key)
      char1.cards.create!(template: template1, location: 'deck', position: 1, target_type_enum: template1.target_type_enum, target_count_min: template1.target_count_min, target_count_max: template1.target_count_max, target_condition_key: template1.target_condition_key)
      char1.cards.create!(template: template2, location: 'discard', position: 0, target_type_enum: template2.target_type_enum, target_count_min: template2.target_count_min, target_count_max: template2.target_count_max, target_condition_key: template2.target_condition_key)

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

        expected_alice_top_level_attributes = {
          id: char1.id,
          name: "Alice",
          health: 80,
          actions_remaining: 1,
          reactions_remaining: 0,
          hand_card_count: 3,
          deck_card_count: 2,
          discard_pile_card_count: 2,
          is_current_player: true,
          is_alive: true
        }

        expected_alice_hand_card_exact_patterns = [
          {
            id: alice_card1_obj.id, name: template1.name, description: template1.description,
            resolution_timing: template1.resolution_timing.to_s, is_free: template1.is_free,
            target_type_enum: template1.target_type_enum.to_s, target_count_min: template1.target_count_min,
            target_count_max: template1.target_count_max, target_condition_key: template1.target_condition_key
          },
          {
            id: alice_card2_obj.id, name: template2.name, description: template2.description,
            resolution_timing: template2.resolution_timing.to_s, is_free: template2.is_free,
            target_type_enum: template2.target_type_enum.to_s, target_count_min: template2.target_count_min,
            target_count_max: template2.target_count_max, target_condition_key: template2.target_condition_key
          },
          {
            id: alice_pass_card_obj.id, name: pass_template.name, description: pass_template.description,
            resolution_timing: pass_template.resolution_timing.to_s, is_free: pass_template.is_free,
            target_type_enum: pass_template.target_type_enum.to_s, target_count_min: pass_template.target_count_min,
            target_count_max: pass_template.target_count_max, target_condition_key: pass_template.target_condition_key
          }
        ]

        expected_bob_attributes = {
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

        expected_carol_attributes = {
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
            source_id: char1.id,
            source_name: "Alice",
            phase: "declared",
            trigger_id: nil,
            resolution_timing: template2.resolution_timing.to_s,
            is_free: template2.is_free,
            max_tick_count: template2.max_tick_count,
            target_character_ids: [char3.id],
            card: hash_including(
                id: active_action_on_table.card.id,
                name: template2.name
            )
          )
        ]

        alice_broadcast_payload = nil
        expect(ActionCable.server).to have_received(:broadcast).with(
          "game_#{game.id}_character_#{char1.id}",
          lambda { |payload|
            alice_broadcast_payload = payload
            true
          }
        )
        expect(alice_broadcast_payload).not_to be_nil, "No broadcast received for Alice (char1)"

        expect(alice_broadcast_payload[:type]).to eq("game_state")
        alice_game_state = alice_broadcast_payload[:game_state]
        expect(alice_game_state[:id]).to eq(game.id)
        expect(alice_game_state[:current_character_id]).to eq(char1.id)

        actual_alice_in_alice_broadcast = alice_game_state[:characters].find { |c| c[:id] == char1.id }
        expect(actual_alice_in_alice_broadcast).not_to be_nil

        expect(actual_alice_in_alice_broadcast).to include(expected_alice_top_level_attributes)
        expect(actual_alice_in_alice_broadcast[:hand_cards]).to match_array(expected_alice_hand_card_exact_patterns)


        actual_bob_in_alice_broadcast = alice_game_state[:characters].find { |c| c[:id] == char2.id }
        expect(actual_bob_in_alice_broadcast).not_to be_nil
        expect(actual_bob_in_alice_broadcast).to include(expected_bob_attributes)
        expect(actual_bob_in_alice_broadcast[:hand_cards]).to eq([])


        actual_carol_in_alice_broadcast = alice_game_state[:characters].find { |c| c[:id] == char3.id }
        expect(actual_carol_in_alice_broadcast).not_to be_nil
        expect(actual_carol_in_alice_broadcast).to include(expected_carol_attributes)
        expect(actual_carol_in_alice_broadcast[:hand_cards]).to eq([])

        expect(alice_game_state[:active_actions]).to match_array(expected_active_actions_payload)
        expect(alice_game_state[:is_over]).to be false

        expected_bob_hand_card_exact_patterns = [
          {
            id: bob_card1_obj.id, name: template1.name, description: template1.description,
            resolution_timing: template1.resolution_timing.to_s, is_free: template1.is_free,
            target_type_enum: template1.target_type_enum.to_s, target_count_min: template1.target_count_min,
            target_count_max: template1.target_count_max, target_condition_key: template1.target_condition_key
          }
        ]

        bob_broadcast_payload = nil
        expect(ActionCable.server).to have_received(:broadcast).with(
          "game_#{game.id}_character_#{char2.id}",
          lambda { |payload|
            bob_broadcast_payload = payload
            true
          }
        )
        expect(bob_broadcast_payload).not_to be_nil, "No broadcast received for Bob (char2)"

        bob_game_state = bob_broadcast_payload[:game_state]
        actual_alice_in_bob_broadcast = bob_game_state[:characters].find { |c| c[:id] == char1.id }
        expect(actual_alice_in_bob_broadcast).not_to be_nil
        expect(actual_alice_in_bob_broadcast).to include(expected_alice_top_level_attributes.except(:hand_cards))
        expect(actual_alice_in_bob_broadcast[:hand_cards]).to eq([])


        actual_bob_in_bob_broadcast = bob_game_state[:characters].find { |c| c[:id] == char2.id }
        expect(actual_bob_in_bob_broadcast).not_to be_nil
        expect(actual_bob_in_bob_broadcast).to include(expected_bob_attributes)
        expect(actual_bob_in_bob_broadcast[:hand_cards]).to match_array(expected_bob_hand_card_exact_patterns)

        actual_carol_in_bob_broadcast = bob_game_state[:characters].find { |c| c[:id] == char3.id }
        expect(actual_carol_in_bob_broadcast).not_to be_nil
        expect(actual_carol_in_bob_broadcast).to include(expected_carol_attributes)
        expect(actual_carol_in_bob_broadcast[:hand_cards]).to eq([])

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
