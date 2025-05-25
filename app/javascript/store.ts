import { create } from 'zustand';
import type { Subscription } from '@rails/actioncable';

export interface CardData {
  id: string;
  owner_character_id: string;
  template_id: string;
  location: 'deck' | 'hand' | 'discard' | 'table';
  position: number;
  name: string;
  description: string;
  resolution_timing: 'before' | 'after';
  is_free: boolean;
}

export interface ActionData {
  id: string;
  game_id: string;
  card_id: string;
  source_id: string;
  trigger_id: string | null;
  phase: 'declared' | 'reacted_to' | 'started' | 'resolved' | 'failed';
  resolution_timing: 'before' | 'after' | null;
  is_free: boolean;
  target_character_ids: string[];
  card?: CardData;
}

export interface CharacterInGameState {
  id: string;
  name: string;
  health: number;
  actions_remaining: number;
  reactions_remaining: number;
  hand_card_count: number;
  hand_cards?: CardData[];
  deck_count: number;
  discard_pile: CardData[];
}

export interface GameState {
  id: string | null;
  current_character_id: string | null;
  characters: CharacterInGameState[];
  active_actions: ActionData[];
  cards_on_table: CardData[];
  last_event: string | null;
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
  setGameState: (gameState: GameState) => void;
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
  setGameState: (gameState) => {
    const currentCharacterId = get().characterId;
    const updatedCharacters = gameState.characters.map(char => {
      if (char.id === currentCharacterId && char.hand_cards) {
        return char;
      }
      const { hand_cards, ...rest } = char;
      return { ...rest, hand_card_count: char.hand_card_count };
    });

    const enrichedActions = gameState.active_actions?.map(action => {
        const actionCard = gameState.cards_on_table?.find(card => card.id === action.card_id) ||
                             gameState.characters.flatMap(c => c.hand_cards || []).find(card => card.id === action.card_id) ||
                             gameState.characters.flatMap(c => c.discard_pile || []).find(card => card.id === action.card_id);
        return { ...action, card: actionCard };
    }) || [];

    set({ gameState: { ...gameState, characters: updatedCharacters, active_actions: enrichedActions }, error: null });
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