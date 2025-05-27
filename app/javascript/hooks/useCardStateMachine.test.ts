// app/javascript/hooks/useCardStateMachine.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useCardStateMachine, CardPlayMachineState, CardPlayStep } from './useCardStateMachine'; // Adjust path as needed
import type { CardData } from '../store'; // Adjust path as needed

// Mock the performAction from the Zustand store
const mockPerformAction = vi.fn();
vi.mock('../store', async (importOriginal) => {
  const actual = await importOriginal() as any;
  return {
    ...actual,
    // Default export is the store hook, we need to mock getState().performAction
    default: {
      ...actual.default,
      getState: () => ({
        ...actual.default.getState(),
        performAction: mockPerformAction,
      }),
    }
  };
});

const upTo1EnemyCard: CardData = {
  id: 'card-quick-shot',
  owner_character_id: 'char1',
  location: 'hand',
  position: 0,
  name: 'Quick Shot',
  description: 'Deal 1 damage.',
  resolution_timing: 'before',
  is_free: false,
  target_type_enum: 'enemy',
  target_count_min: 0, // Crucial for "up to 1"
  target_count_max: 1,
  target_condition_key: '',
};

const exactly1EnemyCard: CardData = {
    id: 'card-precise-shot',
    owner_character_id: 'char1',
    location: 'hand',
    position: 1,
    name: 'Precise Shot',
    description: 'Deal 2 damage, must target 1 enemy.',
    resolution_timing: 'before',
    is_free: false,
    target_type_enum: 'enemy',
    target_count_min: 1, // Requires exactly one
    target_count_max: 1,
    target_condition_key: '',
};


describe('useCardStateMachine', () => {
  beforeEach(() => {
    mockPerformAction.mockClear();
  });

  it('initial state is correct', () => {
    const { result } = renderHook(() => useCardStateMachine());
    expect(result.current.state.step).toBe('idle');
    expect(result.current.state.selectedCard).toBeNull();
    expect(result.current.state.selectedCharacterTargetIds).toEqual([]);
  });

  it('selecting a card transitions to cardSelected state', () => {
    const { result } = renderHook(() => useCardStateMachine());
    act(() => {
      result.current.selectCard(upTo1EnemyCard);
    });
    expect(result.current.state.step).toBe('cardSelected');
    expect(result.current.state.selectedCard).toBe(upTo1EnemyCard);
  });

  it('proceeds to characterTargetsSelected for an enemy-targeting card with target_count_max > 0', () => {
    const { result } = renderHook(() => useCardStateMachine());
    act(() => {
      result.current.selectCard(upTo1EnemyCard);
    });
    act(() => {
      result.current.proceedToTargetingOrConfirm();
    });
    expect(result.current.state.step).toBe('characterTargetsSelected');
  });

  it('toggles a character target correctly', () => {
    const { result } = renderHook(() => useCardStateMachine());
    act(() => {
      result.current.selectCard(upTo1EnemyCard);
      result.current.proceedToTargetingOrConfirm();
    });

    // Select target
    act(() => {
      result.current.toggleTarget('enemy1');
    });
    expect(result.current.state.selectedCharacterTargetIds).toEqual(['enemy1']);

    // Deselect target
    act(() => {
      result.current.toggleTarget('enemy1');
    });
    expect(result.current.state.selectedCharacterTargetIds).toEqual([]);
  });

  it('does not allow selecting more targets than target_count_max', () => {
    const { result } = renderHook(() => useCardStateMachine());
     act(() => {
      result.current.selectCard(upTo1EnemyCard); // max is 1
      result.current.proceedToTargetingOrConfirm();
    });
    act(() => {
      result.current.toggleTarget('enemy1');
    });
    // Try to select another target when max is 1
    act(() => {
      result.current.toggleTarget('enemy2');
    });
    expect(result.current.state.selectedCharacterTargetIds).toEqual(['enemy1']); // Should not add 'enemy2'
  });


  describe('confirmPlay with "up to 1 enemy" card (min:0, max:1)', () => {
    it('commits action with 0 targets selected', () => {
      const { result } = renderHook(() => useCardStateMachine());
      act(() => {
        result.current.selectCard(upTo1EnemyCard);
        result.current.proceedToTargetingOrConfirm(); // Now in 'characterTargetsSelected'
      });
      // No targets selected

      act(() => {
        result.current.confirmPlay();
      });

      expect(mockPerformAction).toHaveBeenCalledTimes(1);
      expect(mockPerformAction).toHaveBeenCalledWith('declare_action', {
        card_id: upTo1EnemyCard.id,
        target_character_ids: [],
        target_card_ids: [],
      });
      expect(result.current.state.step).toBe('idle'); // Resets state
    });

    it('commits action with 1 target selected', () => {
      const { result } = renderHook(() => useCardStateMachine());
      act(() => {
        result.current.selectCard(upTo1EnemyCard);
        result.current.proceedToTargetingOrConfirm();
        result.current.toggleTarget('enemy1');
      });

      act(() => {
        result.current.confirmPlay();
      });

      expect(mockPerformAction).toHaveBeenCalledTimes(1);
      expect(mockPerformAction).toHaveBeenCalledWith('declare_action', {
        card_id: upTo1EnemyCard.id,
        target_character_ids: ['enemy1'],
        target_card_ids: [],
      });
      expect(result.current.state.step).toBe('idle');
    });
  });

  describe('confirmPlay with "exactly 1 enemy" card (min:1, max:1)', () => {
    it('does NOT commit action if 0 targets are selected and min is 1', () => {
      const { result } = renderHook(() => useCardStateMachine());
      act(() => {
        result.current.selectCard(exactly1EnemyCard);
        result.current.proceedToTargetingOrConfirm();
      });
      // No targets selected

      act(() => {
        result.current.confirmPlay();
      });

      expect(mockPerformAction).not.toHaveBeenCalled();
      expect(result.current.state.step).toBe('characterTargetsSelected'); // Stays in targeting
      // You might also check for console.error "Minimum target count not met."
      // but direct assertion on mockPerformAction and state is usually better.
    });

    it('commits action if 1 target is selected and min is 1', () => {
      const { result } = renderHook(() => useCardStateMachine());
      act(() => {
        result.current.selectCard(exactly1EnemyCard);
        result.current.proceedToTargetingOrConfirm();
        result.current.toggleTarget('enemy1');
      });

      act(() => {
        result.current.confirmPlay();
      });
      expect(mockPerformAction).toHaveBeenCalledTimes(1);
      expect(mockPerformAction).toHaveBeenCalledWith('declare_action', {
        card_id: exactly1EnemyCard.id,
        target_character_ids: ['enemy1'],
        target_card_ids: [],
      });
      expect(result.current.state.step).toBe('idle');
    });
  });

  it('cancels play and resets state', () => {
    const { result } = renderHook(() => useCardStateMachine());
    act(() => {
      result.current.selectCard(upTo1EnemyCard);
      result.current.proceedToTargetingOrConfirm();
      result.current.toggleTarget('enemy1');
    });
    expect(result.current.state.step).not.toBe('idle');

    act(() => {
      result.current.cancel();
    });
    expect(result.current.state.step).toBe('idle');
    expect(result.current.state.selectedCard).toBeNull();
    expect(result.current.state.selectedCharacterTargetIds).toEqual([]);
  });
});
