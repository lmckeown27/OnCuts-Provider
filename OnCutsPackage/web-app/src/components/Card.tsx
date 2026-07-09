import type { ReactNode } from 'react';

interface CardProps {
  children: ReactNode;
  className?: string;
  onClick?: () => void;
  hoverable?: boolean;
}

export default function Card({ children, className = '', onClick, hoverable = false }: CardProps) {
  const hoverClass = hoverable ? 'hover:shadow-lg cursor-pointer transition-shadow' : '';
  
  return (
    <div 
      className={`card ${hoverClass} ${className}`}
      onClick={onClick}
    >
      {children}
    </div>
  );
}

