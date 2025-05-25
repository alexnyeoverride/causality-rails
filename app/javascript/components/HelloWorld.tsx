import React from 'react';

interface HelloWorldProps {
  greeting: string;
  target?: string; // Optional prop
}

const HelloWorld: React.FC<HelloWorldProps> = ({ greeting, target = "World" }) => {
  return (
    <h1>
      {greeting}, {target}!
    </h1>
  );
};

export default HelloWorld;
