/**
 * Barber Profile Editor Component
 * 
 * Allows barbers to customize all information visible to consumers:
 * - Profile photo
 * - Bio/description
 * - Availability settings
 * - Instant booking toggle
 */

import { useState, useEffect, useRef } from 'react';
import { Upload, Image as ImageIcon } from 'lucide-react';
import Button from './Button';
import Card from './Card';
import Loading from './Loading';
import MobilePhotoUpload from './MobilePhotoUpload';
import toast from 'react-hot-toast';
import barberService from '../services/barber.service';
import userService from '../services/user.service';
import { useAuthStore } from '../store/useAuthStore';
import { SPECIALTY_OPTIONS } from '../config/services';
import type { Barber } from '../types';

// Detect if user is on a mobile device (for camera/gallery picker)
const isMobileDevice = () => {
  if (typeof window === 'undefined') return false;
  return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) ||
    (window.innerWidth <= 768);
};

interface BarberProfileEditorProps {
  barberId?: string;
  userId?: string; // Alternative: fetch barber by user ID
  onClose?: () => void;
}

export default function BarberProfileEditor({ barberId, userId, onClose }: BarberProfileEditorProps) {
  const { user, setUser } = useAuthStore();
  const [barber, setBarber] = useState<Barber | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  
  // Form state
  const [displayName, setDisplayName] = useState('');
  const [bio, setBio] = useState('');
  const [instagramHandle, setInstagramHandle] = useState('');
  const [profilePhoto, setProfilePhoto] = useState<string>('');
  const [specialties, setSpecialties] = useState<string[]>([]);
  const [isHidden, setIsHidden] = useState(false); // Hide profile from consumers
  
  // Available specialty options from shared config
  const availableSpecialties = SPECIALTY_OPTIONS;

  useEffect(() => {
    loadBarberProfile();
  }, [barberId, userId]);

  const loadBarberProfile = async () => {
    try {
      setIsLoading(true);
      let data: Barber | null = null;
      
      if (barberId) {
        data = await barberService.getBarberById(barberId);
      } else if (userId) {
        data = await barberService.getBarberByUserId(userId);
      } else {
        // Try to get current user's barber profile
        data = await barberService.getMyBarberProfile();
      }
      
      if (!data) {
        toast.error('No barber profile found');
        setIsLoading(false);
        return;
      }
      
      setBarber(data);
      
      // Populate form fields
      setDisplayName(data.name || data.display_name || `${data.first_name || ''} ${data.last_name || ''}`.trim() || '');
      setBio(data.bio || '');
      setInstagramHandle(data.instagram_handle || '');
      setProfilePhoto(data.profile_photo_url || data.profile_picture_url || '');
      setSpecialties(data.specialties || []);
      setIsHidden(!data.is_active); // is_active=false means hidden
      
      setIsLoading(false);
    } catch (error: any) {
      console.error('Failed to load barber profile:', error);
      toast.error('Failed to load profile');
      setIsLoading(false);
    }
  };

  const handleSaveProfile = async () => {
    if (!barber) {
      toast.error('No barber profile loaded');
      return;
    }
    
    try {
      setIsSaving(true);

      const updateData: Partial<Barber> = {
        display_name: displayName,
        bio,
        instagram_handle: instagramHandle,
        specialties,
        is_active: !isHidden, // Hidden = not active
      };

      await barberService.updateBarberProfile(barber.id, updateData);
      
      toast.success('Profile updated successfully!');
      await loadBarberProfile();
    } catch (error: any) {
      console.error('Failed to update profile:', error);
      toast.error('Failed to update profile');
    } finally {
      setIsSaving(false);
    }
  };
  
  const toggleSpecialty = async (specialty: string) => {
    if (!barber) return;
    
    const newSpecialties = specialties.includes(specialty)
      ? specialties.filter(s => s !== specialty)
      : [...specialties, specialty];
    
    // Optimistically update UI
    setSpecialties(newSpecialties);
    
    try {
      // Save immediately to keep in sync with BarberServiceSpecialties
      await barberService.updateBarberProfile(barber.id, {
        specialties: newSpecialties,
      });
    } catch (error) {
      console.error('Failed to update specialties:', error);
      toast.error('Failed to update specialty');
      // Revert on error
      setSpecialties(specialties);
    }
  };

  const handleFileSelect = async (event: React.ChangeEvent<HTMLInputElement>) => {
    console.log('[ProfileEditor] File input changed');
    const file = event.target.files?.[0];
    if (!file) {
      console.log('[ProfileEditor] No file selected');
      return;
    }

    console.log('[ProfileEditor] File selected:', { 
      name: file.name, 
      size: file.size, 
      type: file.type,
      lastModified: file.lastModified 
    });

    // Validate file type - must be an image
    if (!file.type.startsWith('image/')) {
      console.warn('[ProfileEditor] File rejected: not an image type:', file.type);
      toast.error('Please select an image file');
      return;
    }

    // Validate specific allowed formats
    // Note: 'image/jpg' is not standard but some browsers may report it
    const allowedFormats = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
    if (!allowedFormats.includes(file.type)) {
      console.warn('[ProfileEditor] File rejected: unsupported format:', file.type);
      toast.error('Only JPG, PNG, and WebP images are allowed. Please convert your image and try again.');
      return;
    }

    // Validate file size (5MB max)
    if (file.size > 5 * 1024 * 1024) {
      console.warn('[ProfileEditor] File rejected: too large:', file.size);
      toast.error('Image must be less than 5MB');
      return;
    }

    console.log('[ProfileEditor] File validation passed, proceeding with upload');

    try {
      setIsUploading(true);
      
      const uploadUserId = userId || barber?.user_id || '';
      console.log('[ProfileEditor] Starting upload for userId:', uploadUserId);
      console.log('[ProfileEditor] File details:', { name: file.name, size: file.size, type: file.type });
      
      if (!uploadUserId) {
        console.error('[ProfileEditor] No userId available for upload');
        toast.error('Unable to upload: User ID not found. Please refresh the page.');
        return;
      }
      
      // Upload the file
      const response = await userService.uploadProfilePhoto(uploadUserId, file);
      console.log('[ProfileEditor] Upload response:', response);
      
      if (response.url) {
        setProfilePhoto(response.url);
        
        // Update the auth store so all components get the new profile picture
        if (user) {
          setUser({
            ...user,
            profile_picture_url: response.url,
          });
        }
        
        toast.success('Photo uploaded successfully!');
      } else {
        console.error('[ProfileEditor] No URL in response:', response);
        toast.error('Upload completed but no image URL received');
      }
    } catch (error: any) {
      console.error('[ProfileEditor] Failed to upload photo:', error);
      console.error('[ProfileEditor] Error details:', error.response?.data || error.message);
      const errorMessage = error.response?.data?.error?.message || error.message || 'Failed to upload photo';
      toast.error(errorMessage);
    } finally {
      setIsUploading(false);
      // Reset the input so the same file can be selected again
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }
    }
  };

  // Mobile photo upload handler - receives file directly from MobilePhotoUpload component
  const handleMobilePhotoUpload = async (file: File) => {
    try {
      setIsUploading(true);
      
      const uploadUserId = userId || barber?.user_id || '';
      console.log('[ProfileEditor] Mobile upload for userId:', uploadUserId);
      
      if (!uploadUserId) {
        console.error('[ProfileEditor] No userId available for upload');
        toast.error('Unable to upload: User ID not found. Please refresh the page.');
        return;
      }
      
      // Upload the file
      const response = await userService.uploadProfilePhoto(uploadUserId, file);
      console.log('[ProfileEditor] Upload response:', response);
      
      if (response.url) {
        setProfilePhoto(response.url);
        
        // Update the auth store so all components get the new profile picture
        if (user) {
          setUser({
            ...user,
            profile_picture_url: response.url,
          });
        }
        
        toast.success('Photo uploaded successfully!');
      } else {
        console.error('[ProfileEditor] No URL in response:', response);
        toast.error('Upload completed but no image URL received');
      }
    } catch (error: any) {
      console.error('[ProfileEditor] Failed to upload photo:', error);
      const errorMessage = error.response?.data?.error?.message || error.message || 'Failed to upload photo';
      toast.error(errorMessage);
    } finally {
      setIsUploading(false);
    }
  };

  if (isLoading) {
    return <Loading />;
  }

  return (
    <div className="space-y-6">
      {/* Profile Photo - matches barber card dimensions */}
      <Card>
        <h3 className="text-lg font-semibold mb-4">Profile Photo</h3>
        <p className="text-sm text-gray-600 mb-3">This is how your photo appears on your barber card</p>
        {isMobileDevice() ? (
          /* Mobile: Use camera/gallery picker with square shape for barbers */
          <MobilePhotoUpload
            currentPhotoUrl={profilePhoto}
            onPhotoSelected={handleMobilePhotoUpload}
            isUploading={isUploading}
            shape="square"
          />
        ) : (
          /* Desktop: Standard file upload */
          <>
            <div className="flex justify-center mb-4">
              <div className="relative w-48 sm:w-56 aspect-square overflow-hidden rounded-lg bg-gray-200">
                {profilePhoto ? (
                  <img src={profilePhoto} alt="Profile" className="w-full h-full object-cover" />
                ) : (
                  <div className="w-full h-full flex items-center justify-center">
                    <ImageIcon className="w-12 h-12 text-gray-400" />
                  </div>
                )}
              </div>
            </div>
            <div className="flex flex-col sm:flex-row items-center justify-center gap-2 sm:gap-4">
              <input
                ref={fileInputRef}
                type="file"
                accept="image/jpeg,image/jpg,image/png,image/webp,.jpg,.jpeg,.png,.webp"
                onChange={handleFileSelect}
                className="hidden"
              />
              <Button 
                variant="secondary" 
                size="sm" 
                onClick={() => fileInputRef.current?.click()}
                disabled={isUploading}
                className="whitespace-nowrap px-6"
              >
                <Upload className="w-4 h-4 mr-2" />
                {isUploading ? 'Uploading...' : 'Upload Photo'}
              </Button>
              <div className="text-xs text-gray-500 text-center sm:text-left">
                <p>Max size: 5MB</p>
                <p>Formats: JPG, PNG</p>
              </div>
            </div>
          </>
        )}
      </Card>

      {/* Display Name */}
      <Card>
        <h3 className="text-lg font-semibold mb-2">Display Name</h3>
        <p className="text-sm text-gray-600 mb-4">This is the name shown on your barber card</p>
        <input
          type="text"
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
          placeholder="Your name"
          className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
          maxLength={50}
        />
      </Card>

      {/* Bio */}
      <Card>
        <h3 className="text-lg font-semibold mb-4">Bio</h3>
        <textarea
          value={bio}
          onChange={(e) => setBio(e.target.value)}
          placeholder="Tell students about yourself, your style, and what makes you unique..."
          rows={5}
          className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
          maxLength={500}
        />
        <p className="text-xs text-gray-500 mt-2">{bio.length}/500 characters</p>
      </Card>

      {/* Specialties */}
      <Card>
        <h3 className="text-lg font-semibold mb-2">Specialties</h3>
        <p className="text-sm text-gray-600 mb-4">Select the services you specialize in</p>
        <div className="flex flex-wrap gap-2">
          {availableSpecialties.map((specialty) => (
            <button
              key={specialty}
              type="button"
              onClick={() => toggleSpecialty(specialty)}
              className={`px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${
                specialties.includes(specialty)
                  ? 'bg-primary-500 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              {specialty}
            </button>
          ))}
        </div>
      </Card>

      {/* Instagram Handle (Optional) */}
      <Card>
        <h3 className="text-lg font-semibold mb-2">Instagram (Portfolio)</h3>
        <p className="text-sm text-gray-600 mb-4">Link your Instagram to showcase your work</p>
        <div className="flex items-center gap-2">
          <span className="text-gray-600">@</span>
          <input
            type="text"
            value={instagramHandle}
            onChange={(e) => setInstagramHandle(e.target.value.replace('@', ''))}
            placeholder="yourusername"
            className="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
            maxLength={30}
          />
        </div>
        <p className="text-xs text-gray-500 mt-2">Your Instagram serves as your portfolio - students can view your work there</p>
      </Card>

      {/* Profile Visibility */}
      <Card>
        <h3 className="text-lg font-semibold mb-2">Profile Visibility</h3>
        <div className="space-y-3">
          <label className="flex items-start gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={isHidden}
              onChange={(e) => setIsHidden(e.target.checked)}
              className="mt-1 w-5 h-5 accent-primary-600 border-gray-300 rounded focus:ring-primary-500"
            />
            <div>
              <span className="font-medium text-gray-900">Hide my profile from consumers</span>
              <p className="text-sm text-gray-500">Your barber card will not appear in search results</p>
            </div>
          </label>
          
          {isHidden && (
            <div className="p-3 bg-primary-50 border border-primary-200 rounded-lg">
              <p className="text-sm font-medium text-primary-800">Warning: Profile Hidden</p>
              <p className="text-sm text-primary-700 mt-1">
                It will be virtually impossible for consumers to book a service with you while your profile is hidden. 
                Only enable this if you need a temporary break from taking bookings.
              </p>
            </div>
          )}
        </div>
      </Card>

      {/* Action Buttons (Bottom) */}
      <div className="flex justify-between pt-4 border-t border-gray-200">
        <Button variant="secondary" onClick={onClose} size="lg">
          Cancel
        </Button>
        <Button onClick={handleSaveProfile} disabled={isSaving} size="lg" className="min-w-[100px]">
          {isSaving ? 'Saving...' : 'Save'}
        </Button>
      </div>
    </div>
  );
}

