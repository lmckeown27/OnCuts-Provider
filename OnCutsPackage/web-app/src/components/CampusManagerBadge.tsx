/**
 * Campus Manager Badge Component
 * 
 * Non-intrusive badge displayed under barber name
 * Only visible when barber.isCampusManager === true
 */

import React from 'react';
import { Shield } from 'lucide-react';

interface CampusManagerBadgeProps {
  campusName: string;
}

export const CampusManagerBadge: React.FC<CampusManagerBadgeProps> = ({ campusName }) => {
  return (
    <div className="flex items-center gap-2 mt-2">
      <div className="inline-flex items-center gap-1.5 px-3 py-1 bg-primary-50 border border-primary-200 rounded-full">
        <Shield className="w-3.5 h-3.5 text-primary-600" />
        <span className="text-sm font-medium text-primary-700">
          Campus Manager
        </span>
        <span className="text-sm text-gray-500">—</span>
        <span className="text-sm text-gray-700">{campusName}</span>
      </div>
    </div>
  );
};

export const CampusManagerTooltip: React.FC = () => {
  return (
    <div className="text-sm text-gray-600 max-w-xs">
      <p className="font-medium text-gray-900 mb-1">Campus Manager</p>
      <p>Leads barber onboarding and content for CampusCut at this campus.</p>
      <p className="mt-2 text-xs text-gray-500">
        Campus Managers are still active barbers and compete fairly in rankings and pricing.
      </p>
    </div>
  );
};

