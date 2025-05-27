import React, { useEffect, useState, useRef } from 'react';
import useGameStore from '../store';
import type { Consumer, Subscription } from '@rails/actioncable';
import GameView from './GameView';

interface GameProps {
  websocket: Consumer;
}

const Game: React.FC<GameProps> = ({ websocket }) => {
  const {
    isConnected,
    gameId,
    characterId,
    playerSecret,
    error,
    lastMessage,
    setSubscription,
    setConnected,
    setGameDetails,
    setGameState,
    setError,
    setLastMessage,
    resetConnection,
    performAction,
  } = useGameStore();

  const [playerName, setPlayerName] = useState<string>('Player' + Math.floor(Math.random() * 1000));
  const [joinGameIdInput, setJoinGameIdInput] = useState<string>('');
  const currentSubscriptionRef = useRef<Subscription | null>(null);

  useEffect(() => {
    if (!websocket) {
      return;
    }
    if (currentSubscriptionRef.current && currentSubscriptionRef.current.consumer === websocket){
        return;
    }

    const subParams: { channel: string; game_id?: string; player_secret?: string } = {
      channel: 'GameChannel',
    };

    const newSub = websocket.subscriptions.create(subParams, {
      connected: () => {
        setConnected(true);
        setLastMessage('Socket connected. Create, join or rejoin a game.');
      },
      disconnected: () => {
        setConnected(false);
        setLastMessage('Socket disconnected.');
        if (currentSubscriptionRef.current === newSub) {
          currentSubscriptionRef.current = null;
          setSubscription(null);
        }
      },
      received: (data: any) => {
        setLastMessage(JSON.stringify(data, null, 2));
        switch (data.type) {
          case 'joined':
          case 'rejoined':
            setGameDetails({
              gameId: data.game_id,
              characterId: data.character_id,
              playerSecret: data.player_secret || useGameStore.getState().playerSecret || '',
            });
            if (data.game_state) {
                 setGameState(data.game_state);
            }
            setLastMessage(data.message);
            setError(null);
            break;
          case 'game_state':
            setGameState(data.game_state);
            break;
          case 'error':
            setError(data.message);
            break;
          case 'left_game':
            setLastMessage(data.message);
            const subToUnsubscribe = useGameStore.getState().subscription;
            if (subToUnsubscribe && subToUnsubscribe === currentSubscriptionRef.current) {
              subToUnsubscribe.unsubscribe();
            }
            resetConnection();
            currentSubscriptionRef.current = null;
            setSubscription(null);
            break;
          default:
            setLastMessage(`Received unhandled data type: ${data.type}`);
            break;
        }
      },
    });

    currentSubscriptionRef.current = newSub;
    setSubscription(newSub);

    return () => {
      if (newSub) {
        newSub.unsubscribe();
        if (currentSubscriptionRef.current === newSub) {
          currentSubscriptionRef.current = null;
        }
      }
    };
  }, [websocket, setSubscription, setConnected, setGameDetails, setGameState, setError, setLastMessage, resetConnection]);


  const handleCreateGame = () => {
    if(currentSubscriptionRef.current) {
        currentSubscriptionRef.current.perform('create_game', { player_name: playerName });
    } else {
        setError("Websocket subscription not available to create game.");
    }
  }
  const handleJoinGame = () => {
    if (joinGameIdInput && currentSubscriptionRef.current) {
      currentSubscriptionRef.current.perform('join_game', { game_id: joinGameIdInput, player_name: playerName });
    } else {
      setError("Please enter a Game ID to join or subscription not available.");
    }
  };

  const handleRejoinGame = () => {
    const storedGameId = useGameStore.getState().gameId;
    const storedPlayerSecret = useGameStore.getState().playerSecret;

    if (storedGameId && storedPlayerSecret && currentSubscriptionRef.current) {
      currentSubscriptionRef.current.perform('rejoin_game', { game_id: storedGameId, player_secret: storedPlayerSecret });
    } else {
      setError("Need Game ID and Player Secret to rejoin, or subscription not available.");
    }
  };

  const handleLeaveGame = () => {
    performAction('leave_game');
  };


  if (isConnected && gameId && characterId) {
    return <GameView />;
  }

  return (
    <div style={{padding: '20px', maxWidth: '600px', margin: 'auto', fontFamily: 'Arial, sans-serif'}}>
      <h2>Game Lobby</h2>
      <p>Status: {isConnected ? 'Socket Connected' : 'Socket Disconnected'}</p>
      {error && <p style={{ color: 'red' }}>Error: {error}</p>}
      {lastMessage && <p style={{color: 'gray', fontSize: '0.9em'}}>Last Message: {lastMessage}</p>}

      <div>
        <label>Player Name: </label>
        <input type="text" value={playerName} onChange={(e) => setPlayerName(e.target.value)} style={{margin: '5px', padding: '8px'}} />
      </div>
      <button onClick={handleCreateGame} disabled={!isConnected} style={{margin: '5px', padding: '10px'}}>Create Game</button>
      <hr style={{margin: '20px 0'}} />
      <div>
        <label>Game ID to Join: </label>
        <input type="text" value={joinGameIdInput} onChange={(e) => setJoinGameIdInput(e.target.value)} style={{margin: '5px', padding: '8px'}}/>
      </div>
      <button onClick={handleJoinGame} disabled={!isConnected} style={{margin: '5px', padding: '10px'}}>Join Game</button>
      <hr style={{margin: '20px 0'}} />
       <button onClick={handleRejoinGame} disabled={!isConnected || !useGameStore.getState().gameId || !useGameStore.getState().playerSecret } style={{margin: '5px', padding: '10px'}}>Rejoin Last Game</button>
      {gameId && <button onClick={handleLeaveGame} disabled={!isConnected} style={{margin: '5px', padding: '10px', backgroundColor: 'darkred', color: 'white'}}>Leave Current Game</button>}
    </div>
  );
};

export default Game;