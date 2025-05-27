import React, { useEffect } from 'react';
import Card from './Card';
import HiddenCard from './HiddenCard';
import type { CardData } from '../store';
import type { CardPlayMachineState } from '../hooks/useCardStateMachine';

interface HandProps {
  cards: CardData[] | undefined;
  cardCount: number;
  revealed: boolean;
  onCardClick?: (cardId: string, card: CardData) => void;
  canAffordCard?: (card: CardData) => boolean;
  cardPlayMachineState: CardPlayMachineState;
  className?: string;
}

const Hand: React.FC<HandProps> = ({ cards, cardCount, revealed, onCardClick, canAffordCard, cardPlayMachineState, className }) => {
  useEffect(() => {
    // TODO: animate changes to the list of cards (cards appearing/disappearing)
    // This is more complex for list animations; consider libraries like Framer Motion's AnimatePresence
    // Also the animation needs to coordinate between multiple containers, for drawing *from* a deck *into* a hand.
  }, [cards, cardCount]); // Watching both `cards` array (if revealed) and `cardCount`

  return (
    <div
      style={{
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'flex-end',
        padding: '10px',
        minHeight: '200px',
        border: '1px dashed blue',
        borderRadius: '4px',
        backgroundColor: 'rgba(0,0,255,0.05)'
      }}
      className={className}
    >
      {revealed && cards ? (
        cards.map(card => (
          <Card
            key={card.id}
            cardData={card}
            onClick={onCardClick}
            isPlayable={onCardClick && canAffordCard ? canAffordCard(card) : undefined}
            isSelected={cardPlayMachineState.selectedCard?.id === card.id}
          />
        ))
      ) : (
        Array.from({ length: cardCount }).map((_, index) => (
          <HiddenCard key={index} />
        ))
      )}
      {revealed && cards && cards.length === 0 && <div>Hand is empty</div>}
      {!revealed && cardCount === 0 && <div>Hand is empty</div>}
    </div>
  );
};

export default Hand;
