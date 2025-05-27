import React, { useEffect } from 'react';
import Card from './Card';
import type { ActionData, CardData } from '../store';

interface PlayAreaProps {
  activeActions: ActionData[];
  onCardClick: (cardId: string) => void;
  className?: string;
  style?: React.CSSProperties;
}

const PlayArea: React.FC<PlayAreaProps> = ({ activeActions = [], onCardClick, className, style }) => {
  useEffect(() => {
    // TODO: animate appearance/disappearance/phase changes of activeActionsFromStore
  }, [activeActions.length]);

  const combinedStyles: React.CSSProperties = {
    padding: '20px',
    border: '2px solid purple',
    borderRadius: '8px',
    minHeight: '300px',
    backgroundColor: 'rgba(128,0,128,0.05)',
    overflowY: 'auto',
    ...style,
  };

  return (
    <div
      style={combinedStyles}
      className={className}
    >
      {activeActions.map(action => (
        action.card ? <Card
          key={action.card.id}
          cardData={action.card}
          onClick={() => action.card && onCardClick(action.card.id)}
       /> : <></>
      ))}
    </div>
  );
};

export default PlayArea;
