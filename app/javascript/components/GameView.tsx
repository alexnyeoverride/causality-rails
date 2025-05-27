import React, { useEffect } from 'react';
import useGameStore from '../store';
import PlayerArea from './PlayerArea';
import PlayArea from './PlayArea';
import GameInfo from './GameInfo';
import { useCardStateMachine } from '../hooks/useCardStateMachine';

const GameView: React.FC = () => {
  const { gameState, characterId, isConnected } = useGameStore();
  const cardPlayMachine = useCardStateMachine();

  useEffect(() => {
    // TODO: animate gameState.current_character_id changes (turn transitions)
  }, [gameState?.current_character_id]);

  useEffect(() => {
    // TODO: animate gameState.is_over changes (game over sequence)
  }, [gameState?.is_over]);

  if (!isConnected) {
    return (
      <div style={{ padding: '20px', textAlign: 'center' }}>
        <h2>Connecting to Game...</h2>
        <p>Please ensure you have joined or created a game.</p>
        <GameInfo cardPlayMachine={cardPlayMachine} />
      </div>
    );
  }

  if (!gameState) {
    return (
      <div style={{ padding: '20px', textAlign: 'center' }}>
        <h2>Loading game state...</h2>
        <GameInfo cardPlayMachine={cardPlayMachine} />
      </div>
    );
  }

  const currentPlayer = gameState.characters.find(c => c.id === characterId);
  const opponents = gameState.characters.filter(c => c.id !== characterId);
  const isCurrentTurnPlayer = gameState.current_character_id === characterId;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', padding: '10px', boxSizing: 'border-box' }}>
      <div style={{ display: 'flex', justifyContent: 'space-around', flexShrink: 0 }}>
        {opponents.map(op => (
          <PlayerArea 
            key={op.id} 
            player={op} 
            isCurrentTurnPlayer={gameState.current_character_id === op.id} 
            isSelf={false}
            cardPlayMachine={cardPlayMachine}
          />
        ))}
      </div>

      <PlayArea
        className="play-area"
        style={{ flexGrow: 1, margin: '10px 0' }}
        cardPlayMachine={cardPlayMachine}
      />

      {currentPlayer && (
        <PlayerArea 
          player={currentPlayer} 
          isCurrentTurnPlayer={isCurrentTurnPlayer} 
          isSelf={true} 
          className="current-player-area" 
          style={{ flexShrink: 0 }} 
          cardPlayMachine={cardPlayMachine}
        />
      )}

      <GameInfo style={{ flexShrink: 0, marginTop: '10px' }} cardPlayMachine={cardPlayMachine} />
    </div>
  );
};

export default GameView;
