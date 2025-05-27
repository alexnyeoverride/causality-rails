import React, { useEffect } from 'react';

interface DiscardPileProps {
  cardCount: number;
  onClick?: () => void;
  className?: string;
}

const DiscardPile: React.FC<DiscardPileProps> = ({ cardCount, onClick, className }) => {
  useEffect(() => {
    // TODO: animate cardCount changes (e.g., visual indication of discarding)
  }, [cardCount]);

  return (
    <div
      onClick={onClick}
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
      <p>{cardCount} cards</p>
    </div>
  );
};

export default DiscardPile;
