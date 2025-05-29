Hybrid system for detecting how good and how interesting a card is.

AI uses MCTS.  This requires reimplementing an in-memory representation of the game, because duplicating relational networks is brutal.

Genetic Algorithm for Deck Evolution

Crossover: blend successful deck compositions
Mutation: random card additions/removals within constraints

Card win rate is derived by the win rates of decks containing that card
Present in >80% of successful decks = potentially overpowered
Rarely in any successful deck = potentially underpowered

Interestingness: Cards with long-term, multi-step consequences


"""
Multi-Island NSGA-II System for Evolving Diverse Card Game Decks

Core Philosophy:
- We don't just want the "best" deck, but a diverse population of good decks
- Each deck should perform well against a variety of opposing strategies

Key Components:
Island-based hyperparameter exploration of weights for deck similarity functions
NSGA-II within each island for multi-objective optimization (win-rate, interestingness, and diversity)
Migration system for cross-pollination of successful strategies
"""

    

@dataclass
class Deck:
    cards: Dict[str, int]  # card_name -> count
    
    def to_count_vector(self, all_card_types: List[str]) -> np.ndarray:
        """Convert deck to card count vector for Manhattan distance calculation"""
        return np.array([self.cards.get(card, 0) for card in all_card_types])
    

def calculate_deck_similarity(deck1: Deck, deck2: Deck, card_db: Dict[str, Card], 
                            all_card_types: List[str]) -> float:
    """
    Multi-layered deck similarity combining:
    1. Card count similarity (Manhattan distance baseline)
    2. Strategic profile similarity (functional equivalence)
    3. Card-to-card functional similarity (cards serving similar roles)
    """
    
    # Layer 1: Basic card count similarity (your original Manhattan distance)
    counts1 = deck1.to_count_vector(all_card_types)
    counts2 = deck2.to_count_vector(all_card_types)
    manhattan_similarity = 1.0 / (1.0 + np.sum(np.abs(counts1 - counts2)))
    
    # Weighted combination of similarity layers.  (TODO: Weights should not be static, but per-island)
    return (0.4 * manhattan_similarity + 
            0.4 * profile_similarity + 
            0.2 * functional_similarity)



def crossover_decks(parent1: Deck, parent2: Deck, all_card_types: List[str]) -> Tuple[Deck, Deck]:
    """
    1. Uniform crossover: randomly inherit each card count from either parent
    """
    
    # Strategy 1: Uniform crossover with constraints
    child1_cards = {}
    child2_cards = {}
    max_deck_size = 60  # Game-specific constraint
    
    for card in all_card_types:
        count1 = parent1.cards.get(card, 0)
        count2 = parent2.cards.get(card, 0)
        
        if random.random() < 0.5:
            child1_cards[card] = count1
            child2_cards[card] = count2
        else:
            child1_cards[card] = count2
            child2_cards[card] = count1
    
    # Ensure deck size constraints
    child1 = Deck(normalize_deck_size(child1_cards, max_deck_size))
    child2 = Deck(normalize_deck_size(child2_cards, max_deck_size))
    
    return child1, child2

def mutate_deck(deck: Deck, card_db: Dict[str, Card], mutation_rate: float = 0.1) -> Deck:
    """
    Mutation strategies:
    1. Random card count changes
    """
    new_cards = deck.cards.copy()
    
    for card_name in list(new_cards.keys()):
        if random.random() < mutation_rate:
            current_count = new_cards[card_name]
            change = random.choice([-1, 0, 1])
            new_count = max(0, min(4, current_count + change))  # Assuming max 4 copies
            new_cards[card_name] = new_count
    
    return Deck(new_cards)


@dataclass
class Island:
    population: List[Deck]
    dimension_weights: Dict[str, float]  # Hyperparameter exploration per island # TODO: randomly initialize to a unit vector
    
def evaluate_deck_fitness(deck: Deck, dimension_weights: Dict[str, float], 
                         card_db: Dict[str, Card], opponent_decks: List[Deck]) -> Dict[str, float]:
    """
    Multi-objective fitness evaluation considering:
    1. Performance against diverse opponents (win rate)
    2. Diversity bonus (reward for being different from existing successful decks)
    """
    
    # Objective 1: Performance against opponents
    win_rate = simulate_matches_against_opponents(deck, opponent_decks)
    
    # TODO: objective 2
    
    return {
        "win_rate": win_rate,
    }

def migrate_between_islands(islands: List[Island], migration_rate: float = 0.05):
    """
    Elite migration: send best performers
    """
    
    num_migrants = max(1, int(len(islands[0].population) * migration_rate))
    
    for i, source_island in enumerate(islands):
        # Select migrants based on island's strategic preferences
        migrants = select_migrants(source_island, num_migrants)
        
        # Send migrants to other islands
        for j, target_island in enumerate(islands):
            if i != j:
                # Replace worst performers with migrants
                target_island.population = integrate_migrants(
                    target_island.population, migrants
                )

def evolve_diverse_decks(card_db: Dict[str, Card], all_card_types: List[str],
                        num_islands: int = 5, population_per_island: int = 50,
                        num_generations: int = 100, migration_frequency: int = 10):
    """
    Main evolution system combining:
    - Multiple islands with different weights toward deck similarity measures
    - NSGA-II to optimize each island for both fitness and diversity 
    - Migration for cross-pollination of successful strategies
    """
    
    # TODO

def evolve_island_one_generation(island: Island, card_db: Dict[str, Card], 
                               all_card_types: List[str]):
    """
    Single generation evolution for one island using NSGA-II
    """
    # Create offspring through crossover and mutation
    offspring = []
    for _ in range(len(island.population)):
        parent1, parent2 = random.sample(island.population, 2)
        child1, child2 = crossover_decks(parent1, parent2, all_card_types)
        
        child1 = mutate_deck(child1, card_db)
        child2 = mutate_deck(child2, card_db)
        
        offspring.extend([child1, child2])
    
    # Combined population for selection
    combined_population = island.population + offspring
    
    # Evaluate fitness for all individuals
    fitness_scores = []
    for deck in combined_population:
        # Use other decks in population as opponents for evaluation
        opponents = [d for d in combined_population if d != deck][:10]  # Sample opponents
        fitness = evaluate_deck_fitness(deck, island.dimension_weights, card_db, opponents)
        fitness_scores.append(fitness)
    
    # NSGA-II selection to maintain population fitness, size, and diversity
    # TODO: needs modification to incorporate diversity objective.  (uses per-island-weights dot juxt(deck, similarity_functions))
    island.population = nsga2_selection(combined_population, fitness_scores, len(island.population))

def create_random_deck() -> Deck:
    # Stub implementation

def simulate_matches_against_opponents(deck: Deck, opponents: List[Deck]) -> float:
    """Simulate matches and return win rate - requires game engine"""
    # Stub implementation - would integrate with actual game simulation


We evolve deck populations across multiple islands, each with different hyperparameter weightings for:

Deck similarity function components (card count similarity, strategic profile similarity, functional role similarity)
Interestingness metric weightings (ATI, BSD, CSF, TID, CUV coefficients)
Multi-objective optimization priorities (fitness vs. diversity vs. interestingness trade-offs)

Each island maintains a population of 50 deck compositions represented as card count vectors. We use NSGA-II for multi-objective selection within each island, optimizing simultaneously for:
Competitive Fitness: Win rate against diverse opponent decks
Interestingness Score: Weighted combination of interestingness metrics using island-specific coefficients
