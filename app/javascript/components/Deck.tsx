import React, { useEffect } from 'react';

interface DeckProps {
  cardCount: number;
  onClick?: () => void;
  className?: string;
}

const Deck: React.FC<DeckProps> = ({ cardCount, onClick, className }) => {
  useEffect(() => {
    // TODO: animate cardCount changes (e.g., visual indication of drawing)
  }, [cardCount]);

  return (
    <div
      onClick={onClick}
      style={{
        border: '1px solid green',
        padding: '10px',
        margin: '5px',
        width: '120px',
        height: '180px',
        textAlign: 'center',
        backgroundColor: 'rgba(0,128,0,0.1)',
        cursor: onClick ? 'pointer' : 'default',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        borderRadius: '8px',
        boxShadow: '2px 2px 5px rgba(0,0,0,0.2)',
      }}
      className={className}
    >
      <h4>Deck</h4>
      <p>{cardCount} cards</p>
    </div>
  );
};

export default Deck;
