import React from 'react';
import ReactDOM from 'react-dom/client';
import HelloWorld from './components/HelloWorld';

const AppRoot: React.FC = () => {
  return (
    <HelloWorld greeting='sadf' />
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