# Causality Game Engine

Causality is a turn-based, reactive card game engine built with Ruby on Rails. It focuses on intricate action sequencing, reactions, and a dynamic game state driven by player choices and card behaviors.

## Core Game Mechanics

### 1. Game Flow & Initiative
The game progresses in turns, with an initiative system determining the current active character. Characters typically have a set number of actions and reactions they can perform each turn. When a character runs out of their primary resources (like Action Points), initiative may pass to the next eligible character, or a turn reset may occur.

### 2. Actions & Reactions
Players play **Cards** from their hand, which create **Actions** in the game world.
* **Standard Actions:** These are primary moves made by a character on their turn, typically costing an Action Point.
* **Reactions:** Actions can also be played as reactions to other actions (triggers). Reactions have specific timing (e.g., 'before' or 'after' their trigger resolves) and usually cost Reaction Points.
* **Free Actions/Reactions:** Some cards may be designated as 'free', not costing the standard action/reaction resource.

### 3. Action Lifecycle & Causality
Declared actions enter a processing queue managed by the `Causality` service.
* **Phases:** Actions progress through phases: `declared`, `reacted_to` (once all reactions to it have been declared or passed), `started` (if it has multiple ticks), and finally `resolved` or `failed`.
* **Ticking:** Actions can have effects that "tick" multiple times, determined by their `max_tick_count` and a `tick_condition_key`. The `Game#process_actions!` method iterates through tickable actions, executing their effects and updating their state.
* **Resolution:** The game loop determines when an action should resolve based on its tick condition becoming false or its tick count running out.

### 4. Characters & Resources
Characters have health, action points, and reaction points. They manage their cards through a `CharacterCardManager` which handles drawing from a deck, moving cards to hand, and discarding. The default health is 100, with 2 actions and 2 reactions per turn typically.

### 5. Cards
Cards are instances derived from **Templates**. Each character has their own deck, hand, and discard pile. Playing a card moves it from the hand to the "table" (representing an active action) and eventually to the discard pile.

## Architecture Overview

The game is built as a Ruby on Rails 8.0 application.

* **Backend:** Ruby on Rails
* **Database:** PostgreSQL. The database schema is managed via SQL (see `db/structure.sql` and `db/migrate/`).
* **Real-time Communication:** ActionCable is used for real-time updates to clients (e.g., game state changes) via the `GameChannel`.

### Key Components:

* **Models (`app/models/`):**
    * `Game`: Orchestrates game setup, action declaration, and the main processing loop for actions.
    * `Character`: Represents players, manages their resources (health, actions, reactions) and card collections (deck, hand, discard).
    * `Card`: An instance of a `Template` belonging to a character.
    * `Template`: Defines the blueprint for a card, including its name, description, and importantly, keys that link to specific game behaviors.
    * `Action`: Represents a card played in the game, tracking its source, targets, phase, and relationship to other actions (triggers/reactions).
    * `ActionTarget`: A join model linking an `Action` to its `Character` targets.
* **Services (`app/services/`):**
    * `BehaviorRegistry`: A crucial module that maps string keys (from `Template`) to executable Ruby lambdas that define specific game logic (how a card can be played, its conditions for ticking, and its effects).
    * `Causality`: Manages the action stack, determining the order of resolution and identifying the next action to be processed or trigger reactions.
    * `Initiative`: Handles turn order and resource replenishment logic.
* **Channels (`app/channels/`):**
    * `GameChannel`: Manages WebSocket connections for players, handling game creation, joining, action declarations, and broadcasting game state updates.

## Creating New Cards (Templates & Behaviors)

Adding new card types to the game involves two main steps: defining a `Template` and ensuring the corresponding behaviors are defined in the `BehaviorRegistry`.

### 1. Defining a Card Template
Create a new record in the `templates` table (e.g., via `db/seeds.rb` or an admin interface). A `Template` record requires the following key fields:

* `name`: (String) The player-facing name of the card.
* `description`: (Text) The player-facing rules text and flavor text for the card.
* `resolution_timing`: (Enum: 'before' or 'after') Relevant for reactions, determining if they resolve before or after their trigger.
* `is_free`: (Boolean) If `true`, playing this card does not consume a standard action or reaction point.
* `max_tick_count`: (Integer) How many times an action derived from this template can "tick" or have its primary effect. For simple effects that happen once, this is often 1. Can be used by behaviors (e.g., to determine damage amount).
* **Behavior Keys (Strings):** These link to lambdas in the `BehaviorRegistry`.
    * `declarability_key`: Determines if an action based on this template can be declared by a character in a given game context.
    * `tick_condition_key`: Determines if an active action can continue to "tick" or have its effect during the `Game#process_actions!` loop. If this returns false, the action typically moves towards resolution.
    * `tick_effect_key`: Defines what happens when an action "ticks" (i.e., its effect is applied).

When an `Action` is created from a `Card` (which is based on a `Template`), these behavior keys and attributes like `max_tick_count` are copied to the `Action` instance.

### 2. Defining Behaviors
Behaviors are Ruby lambdas stored in the `BEHAVIORS` hash within `app/services/behavior_registry.rb`. Each lambda is associated with a string key that you assign in your `Template` records.

* **Signature:** Behavior lambdas typically receive two arguments:
    1.  `game`: The current `Game` instance, providing access to the entire game state (characters, other actions, etc.).
    2.  `subject`: The object relevant to the behavior.
        * For `declarability_key`: This is often a `params_hash` containing proposed action parameters (like `source_character_id`, `target_ids`, `trigger_id`) before the `Action` object itself is created and saved.
        * For `tick_condition_key` and `tick_effect_key`: This is the `Action` instance itself that is currently being processed.
* **Functionality:**
    * **Declarability Lambdas:** Should return `true` if the action can be declared, `false` otherwise. They can check game state, character resources, target validity, etc.
    * **Tick Condition Lambdas:** Should return `true` if the action can tick again, `false` if it should stop and proceed to resolution or failure. They check things like target status, action phase, or other game conditions. The `default_tick_condition` provides a good base.
    * **Tick Effect Lambdas:** Contain the core logic of what the card does – modifying character health, changing action states, moving cards, etc. These lambdas directly manipulate the models and game state.

**Example Workflow for a New Card:**

1.  **Concept:** "Shield Bash" - Deals damage equal to `max_tick_count`, can only be played if the target is not the character themselves.
2.  **`BehaviorRegistry` - Add/Verify Behaviors:**
    * `declarability_key`: `'declarable_if_target_not_self'`
        ```ruby
        # In behavior_registry.rb
        'declarable_if_target_not_self' => ->(game, params_hash) {
          return false unless params_hash[:target_ids].is_a?(Array) && params_hash[:target_ids].size == 1
          params_hash[:target_ids].first != params_hash[:source_character_id]
        },
        ```
    * `tick_condition_key`: Could use `'tick_if_target_still_alive'` or `'default_tick_condition'`.
    * `tick_effect_key`: Could use `'deal_damage_to_targets_from_max_tick_count'`.
3.  **`Template` - Create Record:**
    * `name`: "Shield Bash"
    * `description`: "Deal damage to target opponent. Cannot target self. Damage equals this card's printed Tick Count."
    * `resolution_timing`: "before"
    * `is_free`: `false`
    * `max_tick_count`: 2 (meaning it deals 2 damage)
    * `declarability_key`: "declarable_if_target_not_self"
    * `tick_condition_key`: "tick_if_target_still_alive"
    * `tick_effect_key`: "deal_damage_to_targets_from_max_tick_count"

By defining these pieces, "Shield Bash" becomes a playable card whose logic is driven by the reusable behaviors in the registry.