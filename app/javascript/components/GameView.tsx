import React from 'react';
import useGameStore from '../store';
import PlayerArea from './PlayerArea';
import PlayArea from './PlayArea';
import GameInfo from './GameInfo';

const GameView: React.FC = () => {
  const { gameState, characterId, isConnected } = useGameStore();

  if (!isConnected) {
    return (
      <div style={{ padding: '20px', textAlign: 'center' }}>
        <h2>Connecting to Game...</h2>
        <p>Please ensure you have joined or created a game.</p>
        <GameInfo />
      </div>
    );
  }

  if (!gameState) {
    return (
      <div style={{ padding: '20px', textAlign: 'center' }}>
        <h2>Loading game state...</h2>
        <GameInfo />
      </div>
    );
  }

  const currentPlayer = gameState.characters.find(c => c.id === characterId);
  const opponents = gameState.characters.filter(c => c.id !== characterId);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', padding: '10px', boxSizing: 'border-box' }}>
      <div style={{ display: 'flex', justifyContent: 'space-around', flexShrink: 0 }}>
        {opponents.map(op => (
          <PlayerArea key={op.id} player={op} isCurrentPlayer={false} />
        ))}
      </div>

      <PlayArea
        activeActions={gameState.active_actions || []}
        cardsOnTable={gameState.cards_on_table || []}
        className="play-area"
        style={{ flexGrow: 1, margin: '10px 0' }}
      />

      {currentPlayer && (
        <PlayerArea player={currentPlayer} isCurrentPlayer={true} className="current-player-area" style={{ flexShrink: 0 }} />
      )}

      <GameInfo style={{ flexShrink: 0, marginTop: '10px' }} />
    </div>
  );
};

export default GameView;