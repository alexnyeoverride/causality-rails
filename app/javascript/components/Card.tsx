import React from 'react';
import type { CardData } from '../store';

interface CardProps {
  cardData: CardData;
  onClick?: (cardId: string) => void;
  className?: string;
}

const Card: React.FC<CardProps> = ({ cardData, onClick, className }) => {
  const handleClick = () => {
    if (onClick) {
      onClick(cardData.id);
    }
  };

  return (
    <div
      onClick={handleClick}
      style={{
        border: '1px solid black',
        padding: '10px',
        margin: '5px',
        width: '120px',
        minHeight: '180px',
        backgroundColor: 'white',
        cursor: onClick ? 'pointer' : 'default',
        boxShadow: '2px 2px 5px rgba(0,0,0,0.2)',
        borderRadius: '8px',
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'space-between'
      }}
      className={className}
    >
      <div>
        <h4 style={{ margin: '0 0 5px 0', fontSize: '0.9em' }}>{cardData.name}</h4>
        <p style={{ fontSize: '0.75em', margin: '0 0 10px 0', whiteSpace: 'pre-wrap' }}>
          {cardData.description}
        </p>
      </div>
      <div style={{ fontSize: '0.7em', borderTop: '1px solid #eee', paddingTop: '5px' }}>
        <p style={{ margin: '2px 0' }}>Type: {cardData.resolution_timing}</p>
        <p style={{ margin: '2px 0' }}>Cost: {cardData.is_free ? 'Free' : '1 Action'}</p>
        <p style={{ margin: '2px 0' }}>ID: {cardData.id}... ({cardData.template_id})</p>
      </div>
    </div>
  );
};

export default Card;