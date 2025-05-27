import React from 'react';
import Card from './Card';
import type { CardData } from '../store';

interface DiscardPileProps {
  numCards: number;
  className?: string;
}

const DiscardPile: React.FC<DiscardPileProps> = ({ numCards, className }) => {
  const topCard = cards.length > 0 ? cards[cards.length - 1] : null;

  return (
    <div
      style={{
        border: '1px solid orange',
        padding: '10px',
        margin: '5px',
        width: '120px',
        minHeight: '180px',
        textAlign: 'center',
        backgroundColor: 'rgba(255,165,0,0.1)',
        cursor: onClick ? 'pointer' : 'default',
        borderRadius: '8px',
        boxShadow: '2px 2px 5px rgba(0,0,0,0.2)',
      }}
      className={className}
    >
      <h4>Discard Pile</h4>
      <p>{numCards} cards</p>
      {topCard && (
        <div style={{ marginTop: '10px', fontSize: '0.8em', opacity: 0.7 }}>
        </div>
      )}
    </div>
  );
};

export default DiscardPile;
