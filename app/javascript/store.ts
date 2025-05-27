import { create } from 'zustand';
import type { Subscription } from '@rails/actioncable';

export interface CardData {
  id: string;
  owner_character_id: string;
  location: 'deck' | 'hand' | 'discard' | 'table';
  position: number;
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
  game_id: string;
  card_id: string;
  source_id: string;
  trigger_id: string | null;
  phase: 'declared' | 'reacted_to' | 'started' | 'resolved' | 'failed';
  resolution_timing: 'before' | 'after' | null;
  is_free: boolean;
  target_character_ids: string[];
  target_card_ids: string[];
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
  setGameDetails: (details: { gameId: any; characterId: any; playerSecret: any }) => void;
  setGameState: (rawGameState: any) => void;
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
    gameId: details.gameId === null || details.gameId === undefined ? null : String(details.gameId),
    characterId: details.characterId === null || details.characterId === undefined ? null : String(details.characterId),
    playerSecret: details.playerSecret === null || details.playerSecret === undefined ? null : String(details.playerSecret),
  }),
  setGameState: (rawGameState: any) => {
    if (!rawGameState) {
      set({ gameState: null, error: null });
      return;
    }

    const myCharacterId = get().characterId;

    const convertCardData = (card: any): CardData | undefined => {
      if (!card) return undefined;
      return {
        ...card,
        id: String(card.id),
        owner_character_id: card.owner_character_id ? String(card.owner_character_id) : '',
      };
    };

    const convertedCharacters: CharacterInGameState[] = (rawGameState.characters || []).map((char: any) => {
      const charIdAsString = String(char.id);
      let processedHandCards: CardData[] | undefined = undefined;

      if (charIdAsString === myCharacterId) {
        if (char.hand_cards && Array.isArray(char.hand_cards)) {
          processedHandCards = char.hand_cards.map(convertCardData).filter((c: CardData | undefined): c is CardData => c !== undefined);
        } else {
          processedHandCards = [];
        }
      } else {
        processedHandCards = undefined;
      }
      return {
        ...char,
        id: charIdAsString,
        hand_cards: processedHandCards,
      };
    });

    const convertedActiveActions: ActionData[] = (rawGameState.active_actions || []).map((action: any) => {
      const processedCard = action.card ? convertCardData(action.card) : undefined;
      return {
        ...action,
        id: String(action.id),
        game_id: action.game_id ? String(action.game_id) : '',
        card_id: String(action.card_id),
        source_id: String(action.source_id),
        trigger_id: action.trigger_id === null || action.trigger_id === undefined ? null : String(action.trigger_id),
        target_character_ids: (action.target_character_ids || []).map(String),
        target_card_ids: (action.target_card_ids || []).map(String),
        card: processedCard,
      };
    });

    const convertedCardsOnTable: CardData[] = (rawGameState.cards_on_table || []).map(convertCardData).filter((c: CardData | undefined): c is CardData => c !== undefined);

    const processedGameState: GameState = {
      ...rawGameState,
      id: rawGameState.id === null || rawGameState.id === undefined ? null : String(rawGameState.id),
      current_character_id: rawGameState.current_character_id === null || rawGameState.current_character_id === undefined ? null : String(rawGameState.current_character_id),
      characters: convertedCharacters,
      active_actions: convertedActiveActions,
      cards_on_table: convertedCardsOnTable,
    };

    set({ gameState: processedGameState, error: null });
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
    } else {
      set({ error: "Not connected to game channel." });
    }
  },
}));

export default useGameStore;