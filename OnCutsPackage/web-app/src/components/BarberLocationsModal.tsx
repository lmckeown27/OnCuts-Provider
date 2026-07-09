/**
 * Barber Locations Modal
 * 
 * Allows barbers to manage their assigned locations
 * - View assigned locations
 * - View pending location requests
 * - Request new locations (pending campus manager approval)
 * - Add from approved campus locations
 */

import React, { useState, useEffect } from 'react';
import { MapPin, Plus, X, RefreshCw, Trash2, Clock, AlertCircle } from 'lucide-react';
import Button from './Button';
import Card from './Card';
import toast from 'react-hot-toast';

interface AssignedLocation {
  assignment_id: string;
  location_id: string;
  name: string;
  description: string | null;
  status: string;
}

interface PendingLocation {
  id: string;
  name: string;
  description: string | null;
  status: string;
  created_at: string;
}

interface AvailableLocation {
  id: string;
  name: string;
  description: string | null;
}

interface LocationsData {
  assigned: AssignedLocation[];
  pending: PendingLocation[];
  available: AvailableLocation[];
}

interface BarberLocationsModalProps {
  isVisible: boolean;
  onClose: () => void;
}

const BarberLocationsModal: React.FC<BarberLocationsModalProps> = ({
  isVisible,
  onClose,
}) => {
  const [data, setData] = useState<LocationsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  
  // New location form state
  const [showRequestForm, setShowRequestForm] = useState(false);
  const [newLocationName, setNewLocationName] = useState('');
  const [newLocationDescription, setNewLocationDescription] = useState('');
  
  // Delete confirmation state
  const [confirmingDeleteId, setConfirmingDeleteId] = useState<string | null>(null);

  const fetchLocations = async () => {
    try {
      setLoading(true);
      const token = localStorage.getItem('accessToken');
      const response = await fetch('/api/locations/my-locations', {
        headers: { Authorization: `Bearer ${token}` },
      });

      if (response.ok) {
        const result = await response.json();
        setData(result.data);
      } else {
        console.error('Failed to fetch locations:', response.status);
        toast.error('Failed to load locations');
      }
    } catch (error) {
      console.error('Failed to fetch locations:', error);
      toast.error('Failed to load locations');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isVisible) {
      fetchLocations();
    }
  }, [isVisible]);

  const handleAssignLocation = async (locationId: string, isPrimary: boolean = false) => {
    try {
      setSaving(true);
      const token = localStorage.getItem('accessToken');
      const response = await fetch('/api/locations/barber/assign', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ locationId, isPrimary }),
      });

      if (response.ok) {
        toast.success('Location added');
        fetchLocations();
      } else {
        const result = await response.json();
        toast.error(result.error || 'Failed to add location');
      }
    } catch (error) {
      console.error('Failed to assign location:', error);
      toast.error('Failed to add location');
    } finally {
      setSaving(false);
    }
  };

  const handleUnassignLocation = async (locationId: string) => {
    try {
      setSaving(true);
      const token = localStorage.getItem('accessToken');
      const response = await fetch(`/api/locations/barber/unassign/${locationId}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
      });

      if (response.ok) {
        toast.success('Location removed');
        fetchLocations();
      } else {
        const result = await response.json();
        toast.error(result.error || 'Failed to remove location');
      }
    } catch (error) {
      console.error('Failed to unassign location:', error);
      toast.error('Failed to remove location');
    } finally {
      setSaving(false);
    }
  };

  const handleRequestLocation = async () => {
    if (!newLocationName.trim()) {
      toast.error('Please enter a location name');
      return;
    }

    try {
      setSaving(true);
      const token = localStorage.getItem('accessToken');
      const response = await fetch('/api/locations/barber/request', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ 
          name: newLocationName.trim(), 
          description: newLocationDescription.trim() || null 
        }),
      });

      if (response.ok) {
        toast.success('Location request submitted for review');
        setNewLocationName('');
        setNewLocationDescription('');
        setShowRequestForm(false);
        fetchLocations();
      } else {
        const result = await response.json();
        toast.error(result.error || 'Failed to submit request');
      }
    } catch (error) {
      console.error('Failed to request location:', error);
      toast.error('Failed to submit request');
    } finally {
      setSaving(false);
    }
  };

  // Get unassigned available locations
  const assignedLocationIds = new Set(data?.assigned.map(a => a.location_id) || []);
  const unassignedLocations = data?.available.filter(loc => !assignedLocationIds.has(loc.id)) || [];

  return (
    <div 
      className="fixed inset-0 min-h-[100dvh] bg-black/50 z-50 flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div 
        className={`bg-white rounded-2xl shadow-2xl max-w-lg w-full max-h-[85vh] overflow-hidden transition-all duration-150 ease-out ${
          isVisible 
            ? 'opacity-100 scale-100 translate-y-0' 
            : 'opacity-0 scale-95 translate-y-4'
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="sticky top-0 bg-gradient-to-r from-primary-500 to-primary-400 text-white px-6 py-4 flex items-center justify-between z-10">
          <div>
            <h2 className="text-2xl font-bold">Locations</h2>
            <p className="text-white/80 text-sm">Manage where you offer services</p>
          </div>
          <button 
            onClick={onClose}
            className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* Content */}
        <div className="overflow-y-auto max-h-[calc(85vh-80px)] p-6">
          {loading ? (
            <div className="text-center py-12">
              <RefreshCw className="w-8 h-8 text-gray-400 mx-auto mb-3 animate-spin" />
              <p className="text-gray-500">Loading locations...</p>
            </div>
          ) : (
            <div className="space-y-6">
              {/* Request New Location Section */}
              <div>
                <div className="flex items-center justify-between mb-3">
                  <h3 className="font-semibold text-gray-900">Your Locations</h3>
                  {!showRequestForm && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setShowRequestForm(true)}
                    >
                      <Plus className="w-4 h-4 mr-1" />
                      Request New
                    </Button>
                  )}
                </div>

                {/* Request Location Form */}
                {showRequestForm && (
                  <Card className="p-4 mb-4 border-primary-200 bg-primary-50">
                    <h4 className="font-medium text-gray-900 mb-2">Request New Location</h4>
                    <p className="text-xs text-gray-500 mb-3">
                      Your request will be reviewed by the campus manager
                    </p>
                    <div className="space-y-3">
                      <div>
                        <label className="block text-sm text-gray-600 mb-1">Location Name *</label>
                        <input
                          type="text"
                          value={newLocationName}
                          onChange={(e) => setNewLocationName(e.target.value)}
                          placeholder="e.g., Dexter Lawn, My Dorm, Student Union"
                          className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent text-base sm:text-sm"
                          autoFocus
                        />
                      </div>
                      <div>
                        <label className="block text-sm text-gray-600 mb-1">Description (optional)</label>
                        <input
                          type="text"
                          value={newLocationDescription}
                          onChange={(e) => setNewLocationDescription(e.target.value)}
                          placeholder="Brief description or directions"
                          className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent text-base sm:text-sm"
                        />
                      </div>
                      <div className="flex gap-2">
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => {
                            setShowRequestForm(false);
                            setNewLocationName('');
                            setNewLocationDescription('');
                          }}
                          disabled={saving}
                          className="flex-1"
                        >
                          Cancel
                        </Button>
                        <Button
                          variant="primary"
                          size="sm"
                          onClick={handleRequestLocation}
                          disabled={saving || !newLocationName.trim()}
                          className="flex-1"
                        >
                          {saving ? (
                            <RefreshCw className="w-4 h-4 animate-spin" />
                          ) : (
                            'Submit Request'
                          )}
                        </Button>
                      </div>
                    </div>
                  </Card>
                )}

                {/* Pending Requests */}
                {data?.pending && data.pending.length > 0 && (
                  <div className="mb-4">
                    <p className="text-xs font-medium text-amber-600 mb-2 flex items-center gap-1">
                      <Clock className="w-3 h-3" />
                      Pending Approval
                    </p>
                    <div className="space-y-2">
                      {data.pending.map((loc) => (
                        <Card key={loc.id} className="p-3 border-amber-200 bg-amber-50">
                          <div className="flex items-center gap-2">
                            <Clock className="w-4 h-4 text-amber-500" />
                            <span className="font-medium text-gray-900 text-sm">{loc.name}</span>
                            <span className="text-xs bg-amber-200 text-amber-700 px-2 py-0.5 rounded-full">
                              Pending
                            </span>
                          </div>
                          {loc.description && (
                            <p className="text-xs text-gray-600 mt-1 ml-6">{loc.description}</p>
                          )}
                        </Card>
                      ))}
                    </div>
                  </div>
                )}

                {/* Assigned Locations List */}
                {data?.assigned.length === 0 ? (
                  <Card className="p-4 text-center bg-gray-50">
                    <MapPin className="w-8 h-8 text-gray-300 mx-auto mb-2" />
                    <p className="text-gray-500 text-sm">No locations assigned yet</p>
                    <p className="text-xs text-gray-400 mt-1">Add locations from below or request a new one</p>
                  </Card>
                ) : (
                  <div className="space-y-2">
                    {data?.assigned.map((loc) => (
                      <Card key={loc.assignment_id} className="p-4">
                        <div className="flex items-start justify-between gap-3">
                          <div className="flex-1">
                            <span className="font-medium text-gray-900">{loc.name}</span>
                            {loc.description && (
                              <p className="text-sm text-gray-600 mt-1">{loc.description}</p>
                            )}
                          </div>
                          {confirmingDeleteId !== loc.location_id && (
                            <button
                              onClick={() => setConfirmingDeleteId(loc.location_id)}
                              disabled={saving}
                              className="p-2 hover:bg-red-50 rounded-lg transition-colors"
                              title="Remove location"
                            >
                              <Trash2 className="w-4 h-4 text-red-500" />
                            </button>
                          )}
                        </div>
                        {confirmingDeleteId === loc.location_id && (
                          <div className="flex items-center justify-end gap-2 mt-3 pt-3 border-t border-gray-100">
                            <button
                              onClick={() => setConfirmingDeleteId(null)}
                              disabled={saving}
                              className="px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
                            >
                              Cancel
                            </button>
                            <button
                              onClick={() => {
                                handleUnassignLocation(loc.location_id);
                                setConfirmingDeleteId(null);
                              }}
                              disabled={saving}
                              className="px-3 py-1.5 text-sm bg-red-500 text-white hover:bg-red-600 rounded-lg transition-colors font-medium"
                            >
                              Delete Location?
                            </button>
                          </div>
                        )}
                      </Card>
                    ))}
                  </div>
                )}
              </div>

              {/* Available Locations to Add */}
              {unassignedLocations.length > 0 && (
                <div>
                  <h3 className="font-semibold text-gray-900 mb-3">Available Locations</h3>
                  <p className="text-sm text-gray-500 mb-3">
                    Approved locations you can add to your profile
                  </p>
                  <div className="space-y-2">
                    {unassignedLocations.map((loc) => (
                      <Card key={loc.id} className="p-4 hover:bg-gray-50 transition-colors">
                        <div className="flex items-center justify-between gap-3">
                          <div className="flex-1">
                            <span className="font-medium text-gray-900">{loc.name}</span>
                            {loc.description && (
                              <p className="text-sm text-gray-600 mt-1">{loc.description}</p>
                            )}
                          </div>
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() => handleAssignLocation(loc.id)}
                            disabled={saving}
                          >
                            <Plus className="w-4 h-4 mr-1" />
                            Add
                          </Button>
                        </div>
                      </Card>
                    ))}
                  </div>
                </div>
              )}

              {/* No Available Locations */}
              {data?.available.length === 0 && data?.assigned.length === 0 && data?.pending.length === 0 && (
                <Card className="p-4 text-center bg-gray-50 border-gray-200">
                  <AlertCircle className="w-8 h-8 text-gray-400 mx-auto mb-2" />
                  <p className="text-gray-600 text-sm font-medium">No locations available yet</p>
                  <p className="text-gray-500 text-xs mt-1">Request a new location to get started</p>
                </Card>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default BarberLocationsModal;
