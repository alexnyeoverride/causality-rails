import React from 'react';
import useGameStore from '../store';
import type { CardData } from '../store';

export type CardPlayStep = 'idle' | 'cardSelected' | 'characterTargetsSelected' | 'cardTargetsSelected' | 'confirming';

export interface CardPlayMachineState {
  step: CardPlayStep;
  selectedCard: CardData | null;
  selectedCharacterTargetIds: string[];
  selectedCardTargetIds: string[];
}

export interface CardPlayMachineAPI {
  state: CardPlayMachineState;
  selectCard: (card: CardData) => void;
  toggleTarget: (targetId: string) => void;
  proceedToTargetingOrConfirm: () => void;
  confirmPlay: () => void;
  cancel: () => void;
}

const initialState: CardPlayMachineState = {
  step: 'idle',
  selectedCard: null,
  selectedCharacterTargetIds: [],
  selectedCardTargetIds: [],
};

export function useCardStateMachine(): CardPlayMachineAPI {
  const [state, setState] = React.useState<CardPlayMachineState>(initialState);
  const { performAction } = useGameStore.getState();

  const selectCard = (card: CardData) => {
    setState({
      step: 'cardSelected',
      selectedCard: card,
      selectedCharacterTargetIds: [],
      selectedCardTargetIds: [],
    });
  };

  const toggleTarget = (targetId: string) => {
    setState(s => {
      if (!s.selectedCard || (s.step !== 'characterTargetsSelected' && s.step !== 'cardTargetsSelected')) return s;

      let currentTargets: string[];
      let maxTargets = 0;

      if (s.selectedCard.target_type_enum === 'enemy' || s.selectedCard.target_type_enum === 'ally' || s.selectedCard.target_type_enum === 'self') {
        currentTargets = s.selectedCharacterTargetIds;
        maxTargets = s.selectedCard.target_count_max;
      } else if (s.selectedCard.target_type_enum === 'card') {
        currentTargets = s.selectedCardTargetIds;
        maxTargets = s.selectedCard.target_count_max;
      } else {
        return s;
      }

      const newTargets = currentTargets.includes(targetId)
        ? currentTargets.filter(id => id !== targetId)
        : [...currentTargets, targetId];

      if (maxTargets > 0 && newTargets.length > maxTargets) {
        return s;
      }

      if (s.selectedCard.target_type_enum === 'enemy' || s.selectedCard.target_type_enum === 'ally' || s.selectedCard.target_type_enum === 'self') {
        return { ...s, selectedCharacterTargetIds: newTargets };
      } else if (s.selectedCard.target_type_enum === 'card') {
        return { ...s, selectedCardTargetIds: newTargets };
      }
      return s;
    });
  };

  const proceedToTargetingOrConfirm = () => {
    setState(s => {
      if (s.step !== 'cardSelected' || !s.selectedCard) return s;
      const card = s.selectedCard;
      if ((card.target_type_enum === 'enemy' || card.target_type_enum === 'ally' || card.target_type_enum === 'self') && card.target_count_max > 0) {
        return { ...s, step: 'characterTargetsSelected' };
      } else if (card.target_type_enum === 'card' && card.target_count_max > 0) {
        return { ...s, step: 'cardTargetsSelected' };
      }
      return { ...s, step: 'confirming' };
    });
  };

  const confirmPlay = () => {
    setState(s => {
      if (!s.selectedCard || (s.step !== 'characterTargetsSelected' && s.step !== 'cardTargetsSelected' && s.step !== 'confirming')) {
        return s;
      }
      const card = s.selectedCard;
      let meetsMinTargets = true;
      if ((card.target_type_enum === 'enemy' || card.target_type_enum === 'ally' || card.target_type_enum === 'self') && card.target_count_min > 0) {
        if (s.selectedCharacterTargetIds.length < card.target_count_min) meetsMinTargets = false;
      } else if (card.target_type_enum === 'card' && card.target_count_min > 0) {
        if (s.selectedCardTargetIds.length < card.target_count_min) meetsMinTargets = false;
      }

      if (!meetsMinTargets) {
        console.error("Minimum target count not met.");
        return s;
      }

      performAction('declare_action', {
        card_id: card.id,
        target_character_ids: s.selectedCharacterTargetIds,
        target_card_ids: s.selectedCardTargetIds,
      });
      return initialState;
    });
  };

  const cancel = () => {
    setState(initialState);
  };

  return { state, selectCard, toggleTarget, proceedToTargetingOrConfirm, confirmPlay, cancel };
}
