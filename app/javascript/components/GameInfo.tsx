import React from 'react';
import useGameStore from '../store';

interface GameInfoProps {
  className?: string;
  style?: React.CSSProperties;
}

const GameInfo: React.FC<GameInfoProps> = ({ className, style }) => {
  const { gameState, performAction, characterId, error, lastMessage, gameId } = useGameStore();

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
      <h4>Game Info</h4>
      {gameId && <p>Game ID: {gameId}...</p>}
      {gameState && (
        <>
          <p>Current Turn: Character {gameState.current_character_id}...</p>
          <p>My Character ID: {characterId}...</p>
          {gameState.last_event && <p>Last Event: {gameState.last_event}</p>}
          {gameState.current_character_id === characterId && (
            <button onClick={handlePassAction} style={{marginTop: '10px', padding: '8px 12px'}}>Pass Turn/Action</button>
          )}
        </>
      )}
      {error && <p style={{ color: 'red', fontWeight: 'bold' }}>Error: {error}</p>}
      {lastMessage && <p style={{ color: 'blue' }}>Last Message: {lastMessage}</p>}
    </div>
  );
};

export default GameInfo;