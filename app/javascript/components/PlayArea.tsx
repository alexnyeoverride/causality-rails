import React from 'react';
import Card from './Card';
import useGameStore from '../store';
import type { ActionData, CardData, CharacterInGameState } from '../store';
import { useCardStateMachine } from '../hooks/useCardStateMachine';


interface PlayAreaProps {
  className?: string;
  style?: React.CSSProperties;
  cardPlayMachine: ReturnType<typeof useCardStateMachine>;
}

const PlayArea: React.FC<PlayAreaProps> = ({ className, style, cardPlayMachine }) => {
  const gameState = useGameStore(s => s.gameState);
  const { toggleTarget: toggleMachineTarget } = cardPlayMachine;

  if (!gameState) return null;

  const { active_actions = [], cards_on_table = [] } = gameState;

  const renderAction = (action: ActionData, allActions: ActionData[], level: number = 0) => {
    const reactions = allActions.filter(a => a.trigger_id === action.id);
    const cardForAction = action.card; 
    const sourceCharacter = gameState.characters.find(c => c.id === action.source_id);

    const isCardTargetingStep = cardPlayMachine.state.step === 'cardTargetsSelected';
    const selectedCardIsCardType = cardPlayMachine.state.selectedCard?.target_type_enum === 'card';
    const cardIsTargetable = cardForAction?.id &&
                             !cardPlayMachine.state.selectedCardTargetIds.includes(cardForAction.id) &&
                             cardPlayMachine.state.selectedCardTargetIds.length < (cardPlayMachine.state.selectedCard?.target_count_max || 0);

    const isTargetableCardForMachine = isCardTargetingStep && selectedCardIsCardType && cardIsTargetable;

    const isSelectedTargetCardForMachine = isCardTargetingStep &&
                                 selectedCardIsCardType &&
                                 cardForAction?.id &&
                                 cardPlayMachine.state.selectedCardTargetIds.includes(cardForAction.id);

    return (
      <div key={action.id} style={{ marginLeft: `${level * 30}px`, marginBottom: '10px', padding: '10px', border: '1px solid #ccc', borderRadius: '4px', backgroundColor: '#f9f9f9' }}>
        <div style={{ fontWeight: 'bold' }}>
          Action: {action.id.substring(0,6)} ({action.phase})
          {cardForAction && ` - Card: ${cardForAction.name}`}
        </div>
        {cardForAction && (
          <Card 
            cardData={cardForAction} 
            onClick={isCardTargetingStep ? (_, card) => toggleMachineTarget(card.id) : undefined}
            isTargetable={isTargetableCardForMachine || undefined}
            isSelected={isSelectedTargetCardForMachine || undefined}
          />
        )}
        <div>Source: {sourceCharacter?.name || action.source_id}</div>
        {action.target_character_ids && action.target_character_ids.length > 0 && (
          <div>Character Targets: {action.target_character_ids.map(tId => gameState.characters.find(c=>c.id === tId)?.name || `CharID-${tId}`).join(', ')}</div>
        )}
        {action.target_card_ids && action.target_card_ids.length > 0 && (
          <div>Card Targets: {action.target_card_ids.map(tId => {
            const targetCard = cards_on_table.find(c => c.id === tId) || active_actions.find(a => a.card.id === tId)?.card;
            return targetCard?.name || `CardID-${tId.substring(0,6)}`;
          }).join(', ')}</div>
        )}
        {reactions.length > 0 && (
          <div style={{ marginTop: '5px' }}>
            {reactions.map(reaction => renderAction(reaction, allActions, level + 1))}
          </div>
        )}
      </div>
    );
  };

  const rootActions = active_actions.filter(action => !action.trigger_id || !active_actions.find(a => a.id === action.trigger_id));
  const otherCardsOnTable = cards_on_table.filter(ct => !active_actions.some(aa => aa.card.id === ct.id));


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
        rootActions.map(action => renderAction(action, active_actions))
      ) : (
        <p style={{textAlign: 'center'}}>No active actions.</p>
      )}
       {otherCardsOnTable.length > 0 && (
        <>
          <h4 style={{textAlign: 'center', marginTop: '20px', borderTop: '1px dashed purple', paddingTop: '10px'}}>Other Cards on Table:</h4>
          <div style={{display: 'flex', flexWrap: 'wrap', justifyContent: 'center'}}>
            {otherCardsOnTable.map(card => {
               const isCardTargetingStep = cardPlayMachine.state.step === 'cardTargetsSelected';
               const selectedCardIsCardType = cardPlayMachine.state.selectedCard?.target_type_enum === 'card';
               const cardIsGenerallyTargetable = !cardPlayMachine.state.selectedCardTargetIds.includes(card.id) &&
                                                 cardPlayMachine.state.selectedCardTargetIds.length < (cardPlayMachine.state.selectedCard?.target_count_max || 0);
              
               const isTargetableCardForMachine = isCardTargetingStep && selectedCardIsCardType && cardIsGenerallyTargetable;

               const isSelectedTargetCardForMachine = isCardTargetingStep &&
                                            selectedCardIsCardType &&
                                            cardPlayMachine.state.selectedCardTargetIds.includes(card.id);
              return (
                <Card 
                  key={card.id} 
                  cardData={card} 
                  onClick={isCardTargetingStep ? (_, c) => toggleMachineTarget(c.id) : undefined } 
                  isTargetable={isTargetableCardForMachine || undefined}
                  isSelected={isSelectedTargetCardForMachine || undefined}
                />
              );
            })}
          </div>
        </>
       )}
    </div>
  );
};

export default PlayArea;