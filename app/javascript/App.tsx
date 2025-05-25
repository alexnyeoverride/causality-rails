import React from 'react';
import ReactDOM from 'react-dom/client';
import Game from './components/Game';
import { createConsumer } from '@rails/actioncable';

const cableUrl = "/cable";
const consumer = createConsumer(cableUrl);

export default consumer;

const AppRoot: React.FC = () => {
  return (
    <Game websocket={consumer} />
  );
};

const container = document.getElementById('react-app-root');
if (container) {
  const root = ReactDOM.createRoot(container);
  root.render(
    <React.StrictMode>
      <AppRoot />
    </React.StrictMode>
  );
}