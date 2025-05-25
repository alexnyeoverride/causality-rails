import React from 'react';
import Card from './Card';
import type { ActionData, CardData } from '../store';

interface PlayAreaProps {
  activeActions: ActionData[];
  cardsOnTable: CardData[];
  onCardClick?: (cardId: string) => void;
  className?: string;
  style?: React.CSSProperties;
}

const PlayArea: React.FC<PlayAreaProps> = ({ activeActions, cardsOnTable, onCardClick, className, style }) => {
  const renderAction = (action: ActionData, allActions: ActionData[], level: number = 0) => {
    const reactions = allActions.filter(a => a.trigger_id === action.id);
    const cardForAction = action.card || cardsOnTable.find(c => c.id === action.card_id);

    return (
      <div key={action.id} style={{ marginLeft: `${level * 30}px`, marginBottom: '10px', padding: '10px', border: '1px solid #ccc', borderRadius: '4px', backgroundColor: '#f9f9f9' }}>
        <div style={{ fontWeight: 'bold' }}>
          Action: {action.id} ({action.phase})
          {cardForAction && ` - Card: ${cardForAction.name}`}
        </div>
        {cardForAction && <Card cardData={cardForAction} onClick={onCardClick ? () => onCardClick(cardForAction.id) : undefined} />}
        <div>Source: {action.source_id}</div>
        {action.target_character_ids && action.target_character_ids.length > 0 && (
          <div>Targets: {action.target_character_ids.map(tId => `${tId}`).join(', ')}</div>
        )}
        {reactions.length > 0 && (
          <div style={{ marginTop: '5px' }}>
            {reactions.map(reaction => renderAction(reaction, allActions, level + 1))}
          </div>
        )}
      </div>
    );
  };

  const rootActions = activeActions.filter(action => !action.trigger_id || !activeActions.find(a => a.id === action.trigger_id));

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
      <h3 style={{textAlign: 'center', marginTop: 0}}>Play Area (Causality Chains)</h3>
      {rootActions.length > 0 ? (
        rootActions.map(action => renderAction(action, activeActions))
      ) : (
        <p style={{textAlign: 'center'}}>No active actions.</p>
      )}
       <h4 style={{textAlign: 'center', marginTop: '20px', borderTop: '1px dashed purple', paddingTop: '10px'}}>Other Cards on Table:</h4>
      {cardsOnTable.filter(ct => !activeActions.some(aa => aa.card_id === ct.id)).map(card => (
        <Card key={card.id} cardData={card} onClick={onCardClick ? () => onCardClick(card.id) : undefined } />
      ))}
    </div>
  );
};

export default PlayArea;