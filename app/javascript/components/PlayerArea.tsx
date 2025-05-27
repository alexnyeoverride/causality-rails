import React, { useEffect, useRef } from 'react';
import Hand from './Hand';
import Deck from './Deck';
import DiscardPile from './DiscardPile';
import useGameStore from '../store';
import type { CharacterInGameState, CardData } from '../store';
import { useCardStateMachine } from '../hooks/useCardStateMachine';

interface PlayerAreaProps {
  player: CharacterInGameState;
  isCurrentTurnPlayer: boolean; 
  isSelf: boolean;
  className?: string;
  style?: React.CSSProperties;
  cardPlayMachine: ReturnType<typeof useCardStateMachine>;
}

const PlayerArea: React.FC<PlayerAreaProps> = ({ player, isCurrentTurnPlayer, isSelf, className, style, cardPlayMachine }) => {
  const { selectCard: selectMachineCard, toggleTarget: toggleMachineTarget, state: cardMachineState } = cardPlayMachine;

  useEffect(() => {
    // TODO: animate player.health changes
  }, [player.health]);

  useEffect(() => {
    // TODO: animate player.actions_remaining changes
  }, [player.actions_remaining]);

  useEffect(() => {
    // TODO: animate player.reactions_remaining changes
  }, [player.reactions_remaining]);

  useEffect(() => {
    // TODO: animate player.hand_card_count changes (e.g., area pulse)
  }, [player.hand_card_count]);

  useEffect(() => {
    // TODO: animate player.deck_card_count changes (e.g., area pulse)
  }, [player.deck_card_count]);

  useEffect(() => {
    // TODO: animate player.discard_pile_card_count changes (e.g., area pulse)
  }, [player.discard_pile_card_count]);

  const handleCardClickInHand = (cardId: string, card: CardData) => {
    if (isSelf && isCurrentTurnPlayer && cardMachineState.step === 'idle') {
      selectMachineCard(card);
    }
  };

  const handleCharacterTargetClick = (targetPlayerId: string) => {
    if (cardMachineState.step === 'characterTargetsSelected') {
      toggleMachineTarget(targetPlayerId);
    }
  };

  const canAffordCard = (card: CardData): boolean => {
    if (!isCurrentTurnPlayer) return false;
    if (card.is_free) return true;
    return player.actions_remaining > 0;
  };
  
  const isTargetableCharacter = cardMachineState.step === 'characterTargetsSelected' &&
                                cardMachineState.selectedCard &&
                                (cardMachineState.selectedCard.target_type_enum === 'enemy' || cardMachineState.selectedCard.target_type_enum === 'ally') &&
                                !cardMachineState.selectedCharacterTargetIds.includes(player.id) &&
                                cardMachineState.selectedCharacterTargetIds.length < (cardMachineState.selectedCard.target_count_max || 0);

  const isSelectedTargetCharacter = cardMachineState.step === 'characterTargetsSelected' &&
                                    cardMachineState.selectedCharacterTargetIds.includes(player.id);


  const combinedStyles: React.CSSProperties = {
    border: `2px solid ${isCurrentTurnPlayer ? 'dodgerblue' : (isSelectedTargetCharacter ? 'gold' : (isTargetableCharacter ? 'lightblue': 'grey'))}`,
    margin: '10px',
    padding: '15px',
    borderRadius: '8px',
    backgroundColor: isCurrentTurnPlayer ? 'rgba(30,144,255,0.05)' : (isSelectedTargetCharacter ? '#fffacd' : 'rgba(128,128,128,0.05)'),
    cursor: isTargetableCharacter ? 'pointer' : 'default',
    ...style,
  };

  return (
    <div
      style={combinedStyles}
      className={className}
      onClick={() => isTargetableCharacter && handleCharacterTargetClick(player.id)}
    >
      <h3 style={{ marginTop: 0, textDecoration: !player.is_alive ? 'line-through' : 'none' }}>
        {player.name} {isSelf ? "(You)" : ""} {isCurrentTurnPlayer && !isSelf ? "(Current Turn)" : ""}
      </h3>
      <div style={{ marginBottom: '5px' }}>
        Health: {player.health} | Actions: {player.actions_remaining} | Reactions: {player.reactions_remaining}
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-around', alignItems: 'flex-start' }}>
        <Deck cardCount={player.deck_card_count} />
        <Hand
          cards={player.hand_cards}
          cardCount={player.hand_card_count}
          revealed={isSelf}
          onCardClick={isSelf && isCurrentTurnPlayer ? handleCardClickInHand : undefined}
          canAffordCard={isSelf && isCurrentTurnPlayer ? canAffordCard : undefined}
          cardPlayMachineState={cardMachineState}
        />
        <DiscardPile cardCount={player.discard_pile_card_count} />
      </div>
    </div>
  );
};

export default PlayerArea;
