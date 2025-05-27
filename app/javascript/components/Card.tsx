import type { CardData } from '../store';

interface CardProps {
  cardData: CardData;
  onClick?: (cardId: string, card: CardData) => void; 
  isPlayable?: boolean;
  isSelected?: boolean;
  isTargetable?: boolean;
  className?: string;
}

const getTargetingSummary = (card: CardData): string => {
  if (!card.target_type_enum || ((card.target_type_enum !== 'self' && card.target_type_enum !== 'next_draw') && card.target_count_max === 0) ) {
    return "Targets: None";
  }
  if (card.target_type_enum === 'self' && card.target_count_max === 0) return "Targets: Self (implicit)";
  if (card.target_type_enum === 'next_draw' && card.target_count_max === 0) return "Targets: Next Draw (implicit)";

  let countStr = "";
  if (card.target_count_min === card.target_count_max) {
    countStr = `${card.target_count_max}`;
  } else if (card.target_count_min === 0) {
    countStr = `Up to ${card.target_count_max}`;
  } else {
    countStr = `${card.target_count_min}-${card.target_count_max}`;
  }

  let typeStr = card.target_type_enum;
  if (card.target_count_max > 1 && card.target_type_enum !== 'self') {
     if (typeStr === 'enemy') typeStr = 'enemies';
     else if (typeStr === 'ally') typeStr = 'allies';
     else if (typeStr === 'card') typeStr = 'cards';
     else if (typeStr === 'next_draw') typeStr = 'next draws';
  }
  return `Targets: ${countStr} ${typeStr}`;
};

const Card: React.FC<CardProps> = ({ cardData, onClick, isPlayable, isSelected, isTargetable, className }) => {
  const handleClick = () => {
    if (onClick) {
      onClick(cardData.id, cardData);
    }
  };

  const style: React.CSSProperties = {
    border: `1px solid ${isSelected ? 'gold' : (isPlayable ? 'green' : (isTargetable ? 'lightblue' : 'black'))}`,
    padding: '10px',
    margin: '5px',
    width: '120px',
    minHeight: '180px',
    backgroundColor: isSelected ? '#fffacd' : 'white',
    cursor: onClick ? 'pointer' : 'default',
    boxShadow: '2px 2px 5px rgba(0,0,0,0.2)',
    borderRadius: '8px',
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'space-between',
    opacity: isPlayable === false ? 0.7 : 1, 
  };

  return (
    <div
      onClick={handleClick}
      style={style}
      className={className}
    >
      <div>
        <h4 style={{ margin: '0 0 5px 0', fontSize: '0.9em' }}>{cardData.name}</h4>
        <p style={{ fontSize: '0.75em', margin: '0 0 10px 0', whiteSpace: 'pre-wrap' }}>
          {cardData.description}
        </p>
      </div>
      <div style={{ fontSize: '0.7em', borderTop: '1px solid #eee', paddingTop: '5px' }}>
        <p style={{ margin: '2px 0' }}>Timing: {cardData.resolution_timing}</p>
        <p style={{ margin: '2px 0' }}>Cost: {cardData.is_free ? 'Free' : '1 Action'}</p>
        <p style={{ margin: '2px 0' }}>{getTargetingSummary(cardData)}</p>
      </div>
    </div>
  );
};

export default Card;
