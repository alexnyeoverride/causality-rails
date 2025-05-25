import React from 'react';
import Card from './Card';
import HiddenCard from './HiddenCard';
import type { CardData } from '../store';

interface HandProps {
  cards: CardData[] | undefined;
  cardCount: number;
  revealed: boolean;
  onCardClick?: (cardId: string) => void;
  className?: string;
}

const Hand: React.FC<HandProps> = ({ cards, cardCount, revealed, onCardClick, className }) => {
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