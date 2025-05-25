import React from 'react';
import useGameStore from '../store';

export type CardPlayStep = 'idle' | 'cardSelected' | 'targetsSelected' | 'confirming';

export interface CardPlayMachineState {
  step: CardPlayStep;
  selectedCardId: string | null;
  selectedCardRequiresTargets: boolean;
  maxTargets: number;
  selectedTargetIds: string[];
}

export interface CardPlayMachineAPI {
  state: CardPlayMachineState;
  selectCard: (cardId: string, requiresTargets?: boolean, maxTargets?: number) => void;
  toggleTarget: (targetId: string) => void;
  proceedToTargetingOrConfirm: () => void;
  confirmPlay: () => void;
  cancel: () => void;
}

const initialState: CardPlayMachineState = {
  step: 'idle',
  selectedCardId: null,
  selectedCardRequiresTargets: false,
  maxTargets: 0,
  selectedTargetIds: [],
};

export function useCardStateMachine(): CardPlayMachineAPI {
  const [state, setState] = React.useState<CardPlayMachineState>(initialState);
  const { performAction } = useGameStore();

  const selectCard = (cardId: string, requiresTargets: boolean = false, maxTargets: number = 0) => {
    setState({
      step: 'cardSelected',
      selectedCardId: cardId,
      selectedCardRequiresTargets: requiresTargets,
      maxTargets: requiresTargets ? (maxTargets > 0 ? maxTargets : 1) : 0,
      selectedTargetIds: [],
    });
  };

  const toggleTarget = (targetId: string) => {
    setState(s => {
      if (s.step !== 'targetsSelected') return s;
      const newTargets = s.selectedTargetIds.includes(targetId)
        ? s.selectedTargetIds.filter(id => id !== targetId)
        : [...s.selectedTargetIds, targetId];

      if (s.maxTargets > 0 && newTargets.length > s.maxTargets) {
        return s; 
      }
      return { ...s, selectedTargetIds: newTargets };
    });
  };

  const proceedToTargetingOrConfirm = () => {
    setState(s => {
      if (s.step !== 'cardSelected' || !s.selectedCardId) return s;
      if (s.selectedCardRequiresTargets) {
        return { ...s, step: 'targetsSelected' };
      }
      return { ...s, step: 'confirming' };
    });
  };

  const confirmPlay = () => {
    setState(s => {
      if ((s.step !== 'targetsSelected' && s.step !== 'confirming') || !s.selectedCardId) return s;
      if (s.selectedCardRequiresTargets && s.selectedTargetIds.length === 0 && s.maxTargets > 0) {
        return s; 
      }

      performAction('declare_action', {
        card_id: s.selectedCardId,
        target_character_ids: s.selectedTargetIds,
      });
      return initialState;
    });
  };

  const cancel = () => {
    setState(initialState);
  };

  return { state, selectCard, toggleTarget, proceedToTargetingOrConfirm, confirmPlay, cancel };
}