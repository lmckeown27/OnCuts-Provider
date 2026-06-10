/**
 * Campus Manager Barber Profile View
 * 
 * Similar to Admin view but with limited powers:
 * - Can view all barber information
 * - Can report barber to admin
 * - Cannot block, ban, or modify barber account
 */

import React, { useState, useEffect } from 'react';
import { 
  ChevronLeft,
  DollarSign, 
  Flag,
  Instagram,
  Mail,
  Clock,
  Loader2,
  XCircle,
  Eye,
  EyeOff
} from 'lucide-react';
import Card from './Card';
import Button from './Button';
import barberService from '../services/barber.service';
import type { Barber } from '../types';

interface CampusManagerBarberViewProps {
  barberId: string;
  onClose: () => void;
  onRemove?: () => void;
}

export const CampusManagerBarberView: React.FC<CampusManagerBarberViewProps> = ({ 
  barberId, 
  onClose,
  onRemove
}) => {
  const [barber, setBarber] = useState<Barber | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isVisible, setIsVisible] = useState(false);
  const [isClosing, setIsClosing] = useState(false);

  // Animate in on mount
  useEffect(() => {
    const timer = setTimeout(() => setIsVisible(true), 10);
    return () => clearTimeout(timer);
  }, []);

  // Handle smooth close
  const handleClose = () => {
    setIsClosing(true);
    setIsVisible(false);
    setTimeout(() => {
      onClose();
    }, 150);
  };

  useEffect(() => {
    const fetchBarber = async () => {
      try {
        setLoading(true);
        setError(null);
        const data = await barberService.getBarberById(barberId);
        setBarber(data);
      } catch (err) {
        console.error('Failed to fetch barber:', err);
        setError('Failed to load barber profile');
      } finally {
        setLoading(false);
      }
    };

    fetchBarber();
  }, [barberId]);

  // Helper to get barber name
  const getBarberName = () => {
    if (!barber) return 'Unknown';
    if (barber.display_name) return barber.display_name;
    if (barber.name) return barber.name;
    if (barber.first_name || barber.last_name) {
      return `${barber.first_name || ''} ${barber.last_name || ''}`.trim();
    }
    if (barber.user?.first_name || barber.user?.last_name) {
      return `${barber.user.first_name || ''} ${barber.user.last_name || ''}`.trim();
    }
    return 'Unknown Barber';
  };

  // Helper to get email - backend returns email directly on barber object from JOIN
  const getEmail = () => {
    return (barber as any)?.email || barber?.user?.email || 'Not available';
  };


  if (loading) {
    return (
      <div className="space-y-4">
        <button
          onClick={handleClose}
          className="flex items-center gap-2 text-gray-600 hover:text-gray-900 transition-colors"
        >
          <ChevronLeft className="w-5 h-5" />
          <span className="text-sm font-medium">Back to Barbers</span>
        </button>
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 animate-spin text-primary-600" />
          <span className="ml-3 text-gray-600">Loading barber profile...</span>
        </div>
      </div>
    );
  }

  if (error || !barber) {
    return (
      <div className="space-y-4">
        <button
          onClick={handleClose}
          className="flex items-center gap-2 text-gray-600 hover:text-gray-900 transition-colors"
        >
          <ChevronLeft className="w-5 h-5" />
          <span className="text-sm font-medium">Back to Barbers</span>
        </button>
        <div className="text-center py-12">
          <p className="text-red-600 mb-4">{error || 'Barber not found'}</p>
          <Button variant="outline" onClick={handleClose}>Go Back</Button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Back Button */}
      <button
        onClick={handleClose}
        className="flex items-center gap-2 text-gray-600 hover:text-gray-900 transition-colors"
      >
        <ChevronLeft className="w-5 h-5" />
        <span className="text-sm font-medium">Back to Barbers</span>
      </button>

      {/* Basic Info */}
      <Card className="p-4">
        <div className="flex items-start gap-4 mb-4">
          {/* Profile Photo */}
          {(barber.profile_photo_url || barber.profile_picture_url) && (
            <img
              src={barber.profile_photo_url || barber.profile_picture_url}
              alt={getBarberName()}
              className="w-16 h-16 rounded-full object-cover flex-shrink-0"
            />
          )}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <h3 className="text-lg font-bold text-gray-900">{getBarberName()}</h3>
            </div>
            {barber.bio && (
              <p className="text-sm text-gray-600">{barber.bio}</p>
            )}
          </div>
        </div>

        <div className="space-y-2 text-sm">
          <div className="flex items-center gap-2 text-gray-700">
            <Mail className="w-4 h-4 text-gray-500 flex-shrink-0" />
            {getEmail() !== 'Not available' ? (
              <a href={`mailto:${getEmail()}`} className="text-primary-600 hover:underline">
                {getEmail()}
              </a>
            ) : (
              <span className="text-gray-500">Email not available</span>
            )}
          </div>
          {barber.instagram_handle && (
            <div className="flex items-center gap-2 text-gray-700">
              <Instagram className="w-4 h-4 text-gray-500 flex-shrink-0" />
              <a
                href={`https://www.instagram.com/${barber.instagram_handle.replace('@', '')}/`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-600 hover:underline"
              >
                @{barber.instagram_handle.replace('@', '')}
              </a>
            </div>
          )}
        </div>
      </Card>

      {/* Profile Visibility Status */}
      <Card className={`p-4 ${barber.is_active === false ? 'bg-amber-50 border-amber-200' : 'bg-green-50 border-green-200'}`}>
        <div className="flex items-center gap-3">
          {barber.is_active === false ? (
            <>
              <EyeOff className="w-5 h-5 text-amber-600" />
              <div>
                <h4 className="font-semibold text-amber-900 text-sm">Profile Hidden</h4>
                <p className="text-xs text-amber-700">This barber has hidden their profile from consumers</p>
              </div>
            </>
          ) : (
            <>
              <Eye className="w-5 h-5 text-green-600" />
              <div>
                <h4 className="font-semibold text-green-900 text-sm">Profile Visible</h4>
                <p className="text-xs text-green-700">This barber's profile is visible to consumers</p>
              </div>
            </>
          )}
        </div>
      </Card>

        {/* Services & Pricing */}
        {barber.pricing && barber.pricing.length > 0 && (
          <Card className="p-4">
            <h4 className="font-semibold text-gray-900 mb-2 flex items-center gap-2 text-sm">
              <DollarSign className="w-4 h-4 text-primary-600" />
              Services & Pricing
            </h4>
            <div className="flex flex-wrap gap-2">
              {barber.pricing.map((service) => (
                <span
                  key={service.name}
                  className="px-3 py-1 bg-primary-50 text-primary-700 rounded-full text-sm font-medium"
                >
                  {service.name} • ${service.price}
                </span>
              ))}
            </div>
          </Card>
        )}

        {/* Weekly Schedule */}
        {barber.weekly_schedule && (
          <Card className="p-4">
            <h4 className="font-semibold text-gray-900 mb-3 flex items-center gap-2 text-sm">
              <Clock className="w-4 h-4 text-primary-600" />
              Weekly Schedule
            </h4>
            <div className="grid grid-cols-7 gap-2">
              {['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'].map((day) => {
                const schedule = (barber.weekly_schedule as any)?.[day];
                const formatTime = (time: string | undefined | null): string => {
                  if (!time || typeof time !== 'string' || !time.includes(':')) {
                    return 'N/A';
                  }
                  const [hours, minutes] = time.split(':').map(Number);
                  if (isNaN(hours)) return 'N/A';
                  const period = hours >= 12 ? 'PM' : 'AM';
                  const hour12 = hours % 12 || 12;
                  return `${hour12}${period}`;
                };
                
                // Get display times - handle both new intervals format and legacy start/end format
                const getScheduleDisplay = (): string[] => {
                  if (!schedule?.enabled) return ['Off'];
                  
                  // New intervals format
                  if (schedule.intervals && Array.isArray(schedule.intervals) && schedule.intervals.length > 0) {
                    const validIntervals = schedule.intervals.filter(
                      (i: any) => i && i.start && i.end
                    );
                    if (validIntervals.length === 0) return ['Available'];
                    return validIntervals.map((i: any) => 
                      `${formatTime(i.start)}-${formatTime(i.end)}`
                    );
                  }
                  
                  // Legacy format
                  if (schedule.start && schedule.end) {
                    return [`${formatTime(schedule.start)}-${formatTime(schedule.end)}`];
                  }
                  
                  return ['Available'];
                };
                
                const timeSlots = getScheduleDisplay();
                
                return (
                  <div key={day} className="text-center">
                    <span className="font-medium text-gray-900 text-xs uppercase">{day.slice(0, 3)}</span>
                    <div className={`text-xs mt-1 ${schedule?.enabled ? 'text-gray-600' : 'text-gray-400'}`}>
                      {timeSlots.map((slot, idx) => (
                        <p key={idx}>{slot}</p>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          </Card>
        )}

      {/* Campus Manager Actions */}
      <Card className="p-4 bg-yellow-50 border-yellow-200">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Flag className="w-5 h-5 text-yellow-600" />
            <div>
              <h4 className="font-semibold text-yellow-900 text-sm">Report Issues</h4>
              <p className="text-xs text-yellow-700">Flag concerns to platform administrators</p>
            </div>
          </div>
          <a
            href={`mailto:campuscuthelp@gmail.com?subject=Barber Report: ${encodeURIComponent(getBarberName())}&body=${encodeURIComponent(`I would like to report a concern about the following barber:\n\nBarber Name: ${getBarberName()}\nBarber ID: ${barberId}\nEmail: ${getEmail()}\n\nConcern:\n[Please describe your concern here]`)}`}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center justify-center font-medium rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2 border-2 px-3 py-1.5 text-sm border-yellow-600 text-yellow-700 hover:bg-yellow-100"
          >
            <Flag className="w-4 h-4 mr-1" />
            Report
          </a>
        </div>
      </Card>

      {/* Remove Barber */}
      {onRemove && (
        <Card className="p-4 bg-red-50 border-red-200">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <XCircle className="w-5 h-5 text-red-600" />
              <div>
                <h4 className="font-semibold text-red-900 text-sm">Remove Barber</h4>
                <p className="text-xs text-red-700">Remove this barber from your campus</p>
              </div>
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={onRemove}
              className="text-red-600 border-red-300 hover:bg-red-100"
            >
              <XCircle className="w-4 h-4 mr-1" />
              Remove
            </Button>
          </div>
        </Card>
      )}

    </div>
  );
};
