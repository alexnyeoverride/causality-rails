Hybrid system for detecting how good and how interesting a card is.

# Hook into Game#process_actions! 
# - Before each action.on_tick!: capture board state
# - After each action.on_tick!: capture effects, measure impact
# - Track cascade failures when actions fail recursively
# - Measure tree depth and breadth of influence

# Hook into Game#declare_action
# - Record what cards are in same character's hand when action declared
# - Track round-level combo opportunities

AI acts randomly from the set of actions it can play at any given time.

Genetic Algorithm for Deck Evolution
Population Management

Each deck composition = chromosome (Template ID → count mapping)
Fitness = win rate
Crossover: blend successful deck compositions
Mutation: random card additions/removals within constraints

Card Fitness Inference

High-fitness deck frequency = card utility
Present in >80% of successful decks = potentially overpowered
Rarely in any successful deck = potentially underpowered

Interestingness Metrics
1. Action Tree Influence
Measurement: During process_actions!, track how each action affects:

Direct descendants (reactions to this action)
Cascade failures (actions that fail because this one failed)
Tree depth from this action

Total actions influenced directly or indirectly

Interestingness: Cards causing deeper, broader influence trees

2. Board State Dependency
Measurement: For each card usage, for each card on board, record (card played, card on board)

3. Same-Round Combo Analysis
Individual card effectiveness baselines
Combined effectiveness when played together
Delta combination versus sum of individual plays

4. Temporal Impact Distance
Measurement: Track how many resolution steps ahead each card's effects reach:

Immediate effects (damage, status changes)
Secondary effects (triggered reactions)
Tertiary+ effects (reactions to reactions, cascade patterns)
Effects on other cards:  affected card's effectiveness versus the average effectiveness of the affected card without the additional effect.

Interestingness: Cards with long-term, multi-step consequences
5. Circumstantial Utility Patterns
Detection of problematic patterns:

Win-more cards: Only effective when already ahead
Dead cards: Rarely useful in any measurable situation
Must-have cards: Present in every successful deck (boring)
Feast-or-famine: Either extremely effective or completely useless
