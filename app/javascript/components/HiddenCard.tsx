import React from 'react';

interface HiddenCardProps {
  className?: string;
}

const HiddenCard: React.FC<HiddenCardProps> = ({ className }) => {
  return (
    <div
      style={{
        border: '1px solid #666',
        padding: '10px',
        margin: '5px',
        width: '120px',
        height: '180px',
        backgroundColor: '#ccc',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        borderRadius: '8px',
        boxShadow: '2px 2px 5px rgba(0,0,0,0.2)',
      }}
      className={className}
    >
      <span style={{ color: '#444', fontWeight: 'bold' }}>Card Back</span>
    </div>
  );
};

export default HiddenCard;