import React, { useEffect } from 'react';
import Card from './Card';
import type { ActionData, CardData } from '../store';

interface PlayAreaProps {
  activeActions: ActionData[];
  // TODO: func can depend on phase, owner, and targeting state.
  onCardClick: (cardId: string) => void;
  className?: string;
  style?: React.CSSProperties;
}

const PlayArea: React.FC<PlayAreaProps> = ({ activeActions = [], onCardClick, className, style }) => {
  useEffect(() => {
    // TODO: animate appearance/disappearance/phase changes of activeActionsFromStore
  }, [activeActions.length]);

  const actionTree = useMemo(() => {
    const nodeMap = new Map<string, ActionNode>();
    
    activeActions.forEach(action => {
      nodeMap.set(action.id, {
        action,
        children: []
      });
    });

    const rootNode = nodeMap.get(activeActions[0].id)!;
    
    for (let i = 1; i < activeActions.length; i++) {
      const action = activeActions[i];
      const node = nodeMap.get(action.id)!;
      const parentNode = nodeMap.get(action.trigger_id!)!;
      parentNode.children.push(node);
    }
    
    return [rootNode];
  }, [activeActions]);

  const combinedStyles: React.CSSProperties = {
    padding: '20px',
    border: '2px solid purple',
    borderRadius: '8px',
    minHeight: '300px',
    backgroundColor: 'rgba(128,0,128,0.05)',
    overflowY: 'auto',
    ...style,
  };

  const renderActionNode = (node: ActionNode): React.ReactNode => {
    const { action } = node;

    return (
      <div key={action.id} className="action-subtree">
        {/* The action node itself */}
        <div className="action-node" style={{ 
          display: 'flex', 
          alignItems: 'center', 
          gap: '10px',
          padding: '5px',
          marginBottom: '10px',
          backgroundColor: 'rgba(255,255,255,0.1)',
          borderRadius: '4px',
          border: `1px solid ${getPhaseColor(action.phase)}`,
        }}>
          <Card
            cardData={action.card}
            onClick={() => onCardClick(action.card.id)}
          />
          <div style={{ fontSize: '0.9em', color: '#555' }}>
            <div><strong>Action {action.id.substring(0, 8)}</strong></div>
            <div>Phase: <span style={{ color: getPhaseColor(action.phase) }}>{action.phase}</span></div>
            <div>Source: {action.source_name || action.source_id.substring(0, 8)}</div>
            {action.trigger_id && (
              <div>Triggered by: {action.trigger_id.substring(0, 8)}</div>
            )}
            {action.target_character_ids.length > 0 && (
              <div>Character Targets: {action.target_character_ids.length}</div>
            )}
            {action.target_card_ids.length > 0 && (
              <div>Card Targets: {action.target_card_ids.length}</div>
            )}
          </div>
        </div>
        
        {/* Children container - markup reflects tree structure */}
        {node.children.length > 0 && (
          <!-- TODO: display flex ? -->
          <div className="action-children">
            {node.children.map(childNode => renderActionNode(childNode))}
          </div>
        )}
      </div>
    );
  };

  const getPhaseColor = (phase: string): string => {
    switch (phase) {
      case 'declared': return '#ff9500';
      case 'reacted_to': return '#007bff';
      case 'started': return '#28a745';
      case 'resolved': return '#6c757d';
      case 'failed': return '#dc3545';
      default: return '#6c757d';
    }
  };

  return (
    <div style={combinedStyles} className={className}>
      <h4 style={{ marginTop: 0, marginBottom: '15px' }}>Active Actions</h4>
      {actionTree.length > 0 ? (
        <div>
          {actionTree.map(node => renderActionNode(node))}
        </div>
      ) : (
        <div style={{ 
          textAlign: 'center', 
          color: '#666', 
          fontStyle: 'italic',
          paddingTop: '50px' 
        }}>
          No active actions
        </div>
      )}
    </div>
  );
};
