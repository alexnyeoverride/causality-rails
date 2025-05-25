import { create } from 'zustand';
import type { Subscription } from '@rails/actioncable';

interface GameState {
  id: string | null;
  current_character_id: string | null;
  characters: Array<{
    id: string;
    name: string;
    hand_card_count: number;
    hand_cards?: Array<{ id: string; name: string; description: string }>;
  }>;
  last_event: string | null;
}

interface StoreState {
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
  setGameState: (gameState) => set({ gameState, error: null }),
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
    } else {
      set({ error: "Not connected to game channel." });
    }
  },
}));

export default useGameStore;