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
* **Resolution:** The game loop determines when an action should resolve based on the reaction tree and whether each reaction resolves before or after its trigger.

### 4. Characters & Resources
Characters have health, action points, and reaction points. They manage their cards through a `CharacterCardManager` which handles drawing from a deck, moving cards to hand, and discarding. The default health is 100, with 2 actions and 2 reactions per turn typically.

### 5. Cards
Cards are instances derived from **Templates**. Each character has their own deck, hand, and discard pile. Playing a card moves it from the hand to the "table" (representing an active action) and eventually to the discard pile.
