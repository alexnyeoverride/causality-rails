import { create } from 'zustand';
import type { Subscription } from '@rails/actioncable';

export interface CardData {
  id: string;
  name: string;
  description: string;
  resolution_timing: 'before' | 'after';
  is_free: boolean;
  target_type_enum: 'enemy' | 'ally' | 'self' | 'card' | 'next_draw';
  target_count_min: number;
  target_count_max: number;
  target_condition_key: string | null;
}

export interface ActionData {
  id: string;
  card_id: string;
  source_id: string;
  source_name: string;
  trigger_id: string | null;
  phase: 'declared' | 'reacted_to' | 'resolved' | 'failed';
  resolution_timing: 'before' | 'after' | null;
  is_free: boolean;
  max_tick_count: number;
  target_character_ids: string[];
  target_card_ids: string[];
  card: CardData; 
}

export interface CharacterInGameState {
  id: string;
  name: string;
  health: number;
  actions_remaining: number;
  reactions_remaining: number;
  hand_card_count: number;
  hand_cards?: CardData[]; 
  deck_card_count: number;
  discard_pile_card_count: number;
  is_current_player: boolean;
  is_alive: boolean;
}

export interface GameState {
  id: string | null;
  current_character_id: string | null;
  characters: CharacterInGameState[];
  active_actions: ActionData[];
  cards_on_table: CardData[]; 
  last_event: string | null;
  is_over: boolean;
}

export interface StoreState {
  subscription: Subscription | null;
  isConnected: boolean;
  gameId: string | null;
  characterId: string | null;
  playerSecret: string | null;
  gameState: GameState | null;
  error: string | null;
  lastMessage: string | null;

  setSubscription: (subscription: Subscription | null) => void;
  setConnected: (status: boolean) => void;
  setGameDetails: (details: { gameId: string; characterId: string; playerSecret: string }) => void;
  setGameState: (newGameState: GameState) => void;
  setError: (error: string | null) => void;
  setLastMessage: (message: string | null) => void;
  resetConnection: () => void;
  performAction: (action: string, data?: object) => void;
}

const useGameStore = create<StoreState>((set, get) => ({
  subscription: null,
  isConnected: false,
  gameId: null,
  characterId: null,
  playerSecret: null,
  gameState: null,
  error: null,
  lastMessage: null,

  setSubscription: (subscription) => set({ subscription }),
  setConnected: (status) => set({ isConnected: status, error: status ? null : get().error }),
  setGameDetails: (details) => set({
    gameId: details.gameId,
    characterId: details.characterId,
    playerSecret: details.playerSecret,
  }),
  setGameState: (newGameState) => {
    const currentCharacterId = get().characterId;
    const updatedCharacters = newGameState.characters.map(char => {
      if (char.id === currentCharacterId && char.hand_cards) {
        return char;
      }
      const { hand_cards, ...rest } = char;
      return { ...rest, hand_cards: char.id === currentCharacterId ? hand_cards : [] };
    });

    const processedActions = newGameState.active_actions || [];
    
    const cards_on_table_from_actions = processedActions
      .map(action => action.card)
      .filter((card): card is CardData => card !== null && card !== undefined);

    set({ 
      gameState: { 
        ...newGameState, 
        characters: updatedCharacters, 
        active_actions: processedActions,
        cards_on_table: cards_on_table_from_actions
      }, 
      error: null 
    });
  },
  setError: (error) => set({ error }),
  setLastMessage: (message) => set({ lastMessage: message }),
  resetConnection: () => set({
    isConnected: false,
    subscription: null,
    gameId: null,
    characterId: null,
    playerSecret: null,
    gameState: null,
    error: "Disconnected or left game.",
  }),

  performAction: (action, data = {}) => {
    const sub = get().subscription;
    if (sub) {
      sub.perform(action, data);
      set({ lastMessage: `Action performed: ${action}` });
    } else {
      set({ error: "Not connected to game channel." });
    }
  },
}));

export default useGameStore;
