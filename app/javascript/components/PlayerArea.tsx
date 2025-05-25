import React from 'react';
import Hand from './Hand';
import Deck from './Deck';
import DiscardPile from './DiscardPile';
import useGameStore from '../store';
import type { CharacterInGameState } from '../store';

interface PlayerAreaProps {
  player: CharacterInGameState;
  isCurrentPlayer: boolean;
  className?: string;
  style?: React.CSSProperties;
}

const PlayerArea: React.FC<PlayerAreaProps> = ({ player, isCurrentPlayer, className, style }) => {
  const { performAction } = useGameStore();

  const handlePlayCardFromHand = (cardId: string) => {
    performAction('declare_action', { card_id: cardId });
  };

  const combinedStyles: React.CSSProperties = {
    border: `2px solid ${isCurrentPlayer ? 'dodgerblue' : 'grey'}`,
    margin: '10px',
    padding: '15px',
    borderRadius: '8px',
    backgroundColor: isCurrentPlayer ? 'rgba(30,144,255,0.05)' : 'rgba(128,128,128,0.05)',
    ...style,
  };

  return (
    <div
      style={combinedStyles}
      className={className}
    >
      <h3 style={{ marginTop: 0 }}>
        {player.name} {isCurrentPlayer ? "(You)" : "(Opponent)"}
      </h3>
      <div style={{ marginBottom: '5px' }}>
        Health: {player.health} | Actions: {player.actions_remaining} | Reactions: {player.reactions_remaining}
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-around', alignItems: 'flex-start' }}>
        <Deck cardCount={player.deck_count} />
        <Hand
          cards={player.hand_cards}
          cardCount={player.hand_card_count}
          revealed={isCurrentPlayer}
          onCardClick={isCurrentPlayer ? handlePlayCardFromHand : undefined}
        />
        <DiscardPile cards={player.discard_pile || []} />
      </div>
    </div>
  );
};

export default PlayerArea;