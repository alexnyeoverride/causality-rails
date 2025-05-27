import React from 'react';
import useGameStore from '../store';
import type { useCardStateMachine } from '../hooks/useCardStateMachine';

interface GameInfoProps {
  className?: string;
  style?: React.CSSProperties;
  cardPlayMachine: ReturnType<typeof useCardStateMachine>;
}

const GameInfo: React.FC<GameInfoProps> = ({ className, style, cardPlayMachine }) => {
  const { gameState, performAction, characterId, error, lastMessage, gameId } = useGameStore();
  const { state: cardMachineState, confirmPlay, cancel: cancelCardPlay } = cardPlayMachine;

  const handlePassAction = () => {
    if (!gameState || !characterId) return;
    const currentPlayerDetails = gameState.characters.find(c => c.id === characterId);
    const passCard = currentPlayerDetails?.hand_cards?.find(card => card.name.toLowerCase() === "pass");

    if (passCard) {
      performAction('declare_action', { card_id: passCard.id });
    } else {
      alert("Pass card not found in hand. Ensure it's dealt or available.");
    }
  };

  const combinedStyles: React.CSSProperties = {
    border: '1px solid lightblue',
    padding: '15px',
    margin: '10px',
    borderRadius: '8px',
    backgroundColor: '#f0f8ff',
    ...style,
  };


  return (
    <div
      style={combinedStyles}
      className={className}
    >
      <h4>Game Info / Controls</h4>
      {gameId && <p>Game ID: {gameId.substring(0,8)}...</p>}
      {gameState && (
        <>
          <p>Current Turn: {gameState.characters.find(c=>c.id === gameState.current_character_id)?.name || gameState.current_character_id?.substring(0,8)}</p>
          <p>My Character ID: {characterId?.substring(0,8)} ({gameState.characters.find(c=>c.id === characterId)?.name})</p>
          {gameState.last_event && <p>Last Event: {gameState.last_event}</p>}
          
          {cardMachineState.step === 'idle' && gameState.current_character_id === characterId && (
            <button onClick={handlePassAction} style={{marginTop: '10px', padding: '8px 12px'}}>Pass Turn/Action</button>
          )}

          {cardMachineState.step === 'cardSelected' && (
            <button onClick={cardPlayMachine.proceedToTargetingOrConfirm} style={{margin: '5px', padding: '8px', backgroundColor: 'lightgreen'}}>
              {cardMachineState.selectedCard?.target_count_max && cardMachineState.selectedCard.target_count_max > 0 && cardMachineState.selectedCard.target_type_enum !== 'self' ? 'Proceed to Targeting' : 'Confirm Play'}
            </button>
          )}
          {cardMachineState.step === 'characterTargetsSelected' || cardMachineState.step === 'cardTargetsSelected' && (
             <button onClick={confirmPlay} style={{margin: '5px', padding: '8px', backgroundColor: 'green', color: 'white'}}>Confirm Targets & Play</button>
          )}
           {cardMachineState.step === 'confirming' && (
             <button onClick={confirmPlay} style={{margin: '5px', padding: '8px', backgroundColor: 'green', color: 'white'}}>Confirm Play</button>
          )}
          {cardMachineState.step !== 'idle' && (
            <button onClick={cancelCardPlay} style={{margin: '5px', padding: '8px', backgroundColor: 'orange'}}>Cancel Card Play</button>
          )}
        </>
      )}
      {error && <p style={{ color: 'red', fontWeight: 'bold' }}>Error: {error}</p>}
      {lastMessage && <p style={{ color: 'blue' }}>Last Message: {lastMessage}</p>}
    </div>
  );
};

export default GameInfo;