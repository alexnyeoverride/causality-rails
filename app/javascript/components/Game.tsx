import React, { useEffect, useState, useRef } from 'react';
import useGameStore from '../store';
import type { Consumer, Subscription } from '@rails/actioncable';

interface GameProps {
  websocket: Consumer;
}

const Game: React.FC<GameProps> = ({ websocket }) => {
  const {
    subscription,
    isConnected,
    gameId,
    characterId,
    playerSecret,
    gameState,
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
    if (!websocket || currentSubscriptionRef.current) {
      return;
    }

    const subParams: { channel: string; game_id?: string; player_secret?: string } = {
      channel: 'GameChannel',
    };

    const newSub = websocket.subscriptions.create(subParams, {
      connected: () => {
        setConnected(true);
        setLastMessage('Connected to GameChannel.');
      },
      disconnected: () => {
        setConnected(false);
        setLastMessage('Disconnected from GameChannel.');
        if (currentSubscriptionRef.current === newSub) {
          currentSubscriptionRef.current = null;
          setSubscription(null);
        }
      },
      received: (data: any) => {
        setLastMessage(`Received: ${JSON.stringify(data)}`);
        switch (data.type) {
          case 'joined':
          case 'rejoined':
            setGameDetails({
              gameId: data.game_id,
              characterId: data.character_id,
              playerSecret: data.player_secret || useGameStore.getState().characterId || '',
            });
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
          setSubscription(null);
          setConnected(false);
        }
      }
    };
  }, [websocket, setSubscription, setConnected, setGameDetails, setGameState, setError, setLastMessage, resetConnection]);


  const handleCreateGame = () => performAction('create_game', { player_name: playerName });
  const handleJoinGame = () => {
    if (joinGameIdInput) {
      performAction('join_game', { game_id: joinGameIdInput, player_name: playerName });
    } else {
      setError("Please enter a Game ID to join.");
    }
  };

  const handleRejoinGame = () => {
    if (gameId && playerSecret && websocket) {
      if (currentSubscriptionRef.current) {
        currentSubscriptionRef.current.unsubscribe();
        currentSubscriptionRef.current = null;
        setSubscription(null);
      }

      const rejoinSub = websocket.subscriptions.create({
        channel: 'GameChannel', game_id: gameId, player_secret: playerSecret
      }, {
        connected: () => { setConnected(true); setLastMessage(`Reconnected to Game ${gameId}`); },
        disconnected: () => {
            setConnected(false); setLastMessage('Disconnected.');
            if (currentSubscriptionRef.current === rejoinSub) {
                currentSubscriptionRef.current = null;
                setSubscription(null);
            }
        },
        received: (data: any) => {
          setLastMessage(`Received: ${JSON.stringify(data)}`);
          switch (data.type) {
            case 'joined': case 'rejoined':
              setGameDetails({ gameId: data.game_id, characterId: data.character_id, playerSecret: data.player_secret || useGameStore.getState().playerSecret || '' });
              setLastMessage(data.message); setError(null); break;
            case 'game_state': setGameState(data.game_state); break;
            case 'error': setError(data.message); break;
            case 'left_game': setLastMessage(data.message);
              const subToClose = useGameStore.getState().subscription;
              if (subToClose && subToClose === currentSubscriptionRef.current) {
                subToClose.unsubscribe();
              }
              resetConnection();
              currentSubscriptionRef.current = null;
              setSubscription(null); break;
            default: setLastMessage(`Received unhandled data type: ${data.type}`); break;
          }
        }
      });
      currentSubscriptionRef.current = rejoinSub;
      setSubscription(rejoinSub);
    } else {
      setError("Need Game ID, Player Secret, and websocket connection to rejoin.");
    }
  };

  const handleLeaveGame = () => {
    const sub = useGameStore.getState().subscription;
    if (sub) {
      performAction('leave_game');
    } else {
      setError("Not subscribed to a game to leave.");
    }
  };

  const handleDeclarePassAction = () => {
    const currentCharacter = gameState?.characters.find(c => c.id === characterId);
    const passCard = currentCharacter?.hand_cards?.find(card => card.name === "Pass");
    if (passCard) {
      performAction('declare_action', { card_id: passCard.id });
    } else {
      setError("Pass card not found in hand or not your turn.");
    }
  };
  return (
    <div>
      <h2>Game Component</h2>
      <p>Status: {isConnected ? 'Connected' : 'Disconnected'}</p>
      {error && <p style={{ color: 'red' }}>Error: {error}</p>}
      {lastMessage && <p>Last Message: {lastMessage}</p>}

      {!gameId && (
        <>
          <div>
            <label>Player Name: </label>
            <input type="text" value={playerName} onChange={(e) => setPlayerName(e.target.value)} />
          </div>
          <button onClick={handleCreateGame} disabled={!isConnected || !!gameId || !websocket}>Create Game</button>
          <hr />
          <div>
            <label>Game ID to Join: </label>
            <input type="text" value={joinGameIdInput} onChange={(e) => setJoinGameIdInput(e.target.value)} />
          </div>
          <button onClick={handleJoinGame} disabled={!isConnected || !!gameId || !websocket}>Join Game</button>
        </>
      )}

      {gameId && (
        <div>
          <p>Game ID: {gameId}</p>
          <p>My Character ID: {characterId}</p>
          <p>My Player Secret: {playerSecret}</p>
          <button onClick={handleRejoinGame} disabled={!isConnected || !websocket}>Rejoin with Stored Details</button>
          <button onClick={handleLeaveGame} disabled={!isConnected || !websocket}>Leave Game</button>
          <button onClick={handleDeclarePassAction} disabled={!isConnected || !gameState || gameState.current_character_id !== characterId || !websocket}>Declare Pass Action</button>
        </div>
      )}

      {gameState && (
        <div>
          <h3>Game State</h3>
          <p>Current Turn: Character {gameState.current_character_id}</p>
          <p>Last Event: {gameState.last_event}</p>
          <h4>Players:</h4>
          <ul>
            {gameState.characters.map(char => (
              <li key={char.id} style={{ fontWeight: char.id === characterId ? 'bold' : 'normal' }}>
                {char.name} (ID: {char.id}, Cards: {char.hand_card_count})
                {char.id === characterId && char.hand_cards && (
                  <ul>
                    {char.hand_cards.map(card => <li key={card.id}>{card.name}: {card.description}</li>)}
                  </ul>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
};

export default Game;