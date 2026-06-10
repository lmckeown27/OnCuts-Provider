/**
 * Consumer Profile Editor Component
 * 
 * Allows students to customize their profile information:
 * - Profile photo
 * - Name (first, last)
 * - Bio/About
 * - Campus (read-only, set during registration)
 * - Notification preferences
 * - Privacy settings
 */

import { useState, useEffect, forwardRef, useImperativeHandle } from 'react';
import { Upload, Save, Mail, User as UserIcon, Bell, Lock, Trash2, Image as ImageIcon, Eye, EyeOff, X } from 'lucide-react';
import Button from './Button';
import Card from './Card';
import Loading from './Loading';
import MobilePhotoUpload from './MobilePhotoUpload';
import toast from 'react-hot-toast';
import userService from '../services/user.service';
import { useAuthStore } from '../store/useAuthStore';
import type { User } from '../types';

// Detect if user is on a mobile device (for camera/gallery picker)
const isMobileDevice = () => {
  if (typeof window === 'undefined') return false;
  return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) ||
    (window.innerWidth <= 768);
};

interface ConsumerProfileEditorProps {
  userId: string;
}

export interface ConsumerProfileEditorRef {
  showDeleteModal: () => void;
}

const ConsumerProfileEditor = forwardRef<ConsumerProfileEditorRef, ConsumerProfileEditorProps>(({ userId }, ref) => {
  const { user: authUser, setUser: setAuthUser } = useAuthStore();
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [activeSection, setActiveSection] = useState<'profile' | 'notifications' | 'security' | 'delete'>('profile');
  
  // Profile form state
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [bio, setBio] = useState('');
  const [profilePhoto, setProfilePhoto] = useState('');
  
  // Notification preferences
  const [emailNotifications, setEmailNotifications] = useState(true);
  const [bookingReminders, setBookingReminders] = useState(true);
  const [promotionalEmails, setPromotionalEmails] = useState(false);

  // Security
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showCurrentPassword, setShowCurrentPassword] = useState(false);
  const [showNewPassword, setShowNewPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [currentPasswordError, setCurrentPasswordError] = useState('');
  const [passwordChangeSuccess, setPasswordChangeSuccess] = useState(false);

  // Delete account state
  const [deletePassword, setDeletePassword] = useState('');
  const [showDeletePassword, setShowDeletePassword] = useState(false);
  const [deletePasswordError, setDeletePasswordError] = useState('');
  const [isDeleting, setIsDeleting] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState('');

  // Expose showDeleteModal method to parent via ref (switches to delete section)
  useImperativeHandle(ref, () => ({
    showDeleteModal: () => setActiveSection('delete'),
  }));

  useEffect(() => {
    loadUserProfile();
    loadNotificationPreferences();
  }, [userId]);

  const loadUserProfile = async () => {
    try {
      setIsLoading(true);
      const data = await userService.getUserProfile(userId);
      setUser(data);
      
      // Populate form fields
      setFirstName(data.first_name || '');
      setLastName(data.last_name || '');
      setBio(data.bio || '');
      setProfilePhoto(data.profile_picture_url || '');
      
      setIsLoading(false);
    } catch (error: any) {
      console.error('Failed to load user profile:', error);
      toast.error('Failed to load profile');
      setIsLoading(false);
    }
  };

  const loadNotificationPreferences = async () => {
    try {
      const prefs = await userService.getNotificationPreferences(userId);
      setEmailNotifications(prefs.email_notifications);
      setBookingReminders(prefs.booking_reminders);
      setPromotionalEmails(prefs.promotional_emails);
    } catch (error) {
      console.error('Failed to load notification preferences:', error);
    }
  };

  const handleSaveProfile = async () => {
    try {
      setIsSaving(true);

      const updateData = {
        first_name: firstName,
        last_name: lastName,
        bio,
      };

      await userService.updateUserProfile(userId, updateData);
      
      toast.success('Profile updated successfully!');
      await loadUserProfile();
    } catch (error: any) {
      console.error('Failed to update profile:', error);
      toast.error('Failed to update profile');
    } finally {
      setIsSaving(false);
    }
  };

  const handleSaveNotifications = async () => {
    try {
      setIsSaving(true);

      await userService.updateNotificationPreferences(userId, {
        email_notifications: emailNotifications,
        booking_reminders: bookingReminders,
        promotional_emails: promotionalEmails,
      });
      
      toast.success('Notification preferences updated!');
    } catch (error: any) {
      console.error('Failed to update notifications:', error);
      toast.error('Failed to update preferences');
    } finally {
      setIsSaving(false);
    }
  };

  const handleChangePassword = async () => {
    // Clear previous states
    setCurrentPasswordError('');
    setPasswordChangeSuccess(false);
    
    if (newPassword !== confirmPassword) {
      toast.error('Passwords do not match');
      return;
    }

    if (newPassword.length < 8) {
      toast.error('Password must be at least 8 characters');
      return;
    }

    try {
      setIsSaving(true);
      await userService.changePassword(userId, currentPassword, newPassword);
      
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
      setCurrentPasswordError('');
      setPasswordChangeSuccess(true);
    } catch (error: any) {
      console.error('Failed to change password:', error);
      // Try multiple ways to get the error message from the response
      const errorMessage = error.response?.data?.message || 
                          error.response?.data?.error || 
                          error.message || 
                          'Failed to change password';
      
      // Check if error is related to current password being incorrect (401 status or message match)
      const is401Error = error.response?.status === 401;
      const isPasswordError = errorMessage.toLowerCase().includes('current password') || 
                             errorMessage.toLowerCase().includes('incorrect') ||
                             errorMessage.toLowerCase().includes('wrong password') ||
                             errorMessage.toLowerCase().includes('invalid password');
      
      if (is401Error || isPasswordError) {
        setCurrentPasswordError('Current password is incorrect');
      } else {
        toast.error(errorMessage);
      }
    } finally {
      setIsSaving(false);
    }
  };

  const handleDeleteAccount = async () => {
    setDeletePasswordError('');
    
    if (!deletePassword) {
      setDeletePasswordError('Password is required');
      return;
    }

    if (deleteConfirmText !== 'DELETE') {
      toast.error('Please type DELETE to confirm');
      return;
    }

    try {
      setIsDeleting(true);
      await userService.deleteAccount(userId, deletePassword);
      
      // Clear all auth storage
      localStorage.removeItem('campuscuts_access_token');
      localStorage.removeItem('campuscuts_refresh_token');
      localStorage.removeItem('campuscuts_user');
      
      toast.success('Account deleted successfully');
      
      // Redirect to home page
      window.location.href = '/';
    } catch (error: any) {
      console.error('Failed to delete account:', error);
      const errorMessage = error.response?.data?.message || 
                          error.response?.data?.error || 
                          error.message || 
                          'Failed to delete account';
      
      if (error.response?.status === 401 || errorMessage.toLowerCase().includes('incorrect')) {
        setDeletePasswordError('Incorrect password');
      } else {
        toast.error(errorMessage);
      }
    } finally {
      setIsDeleting(false);
    }
  };

  const handleUploadPhoto = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    // Validate file type - must be an image
    if (!file.type.startsWith('image/')) {
      toast.error('Please upload an image file');
      return;
    }

    // Validate specific allowed formats
    // Note: 'image/jpg' is not standard but some browsers may report it
    const allowedFormats = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
    if (!allowedFormats.includes(file.type)) {
      toast.error('Only JPG, PNG, and WebP images are allowed. Please convert your image and try again.');
      return;
    }

    // Validate file size (max 5MB)
    if (file.size > 5 * 1024 * 1024) {
      toast.error('Image must be less than 5MB');
      return;
    }

    try {
      toast.success('Uploading photo...');
      const result = await userService.uploadProfilePhoto(userId, file);
      setProfilePhoto(result.url);
      
      // Update user profile with new photo URL
      await userService.updateUserProfile(userId, { profile_picture_url: result.url });
      
      // Update auth store so the avatar updates immediately everywhere
      if (authUser) {
        const updatedUser = { ...authUser, profile_picture_url: result.url };
        setAuthUser(updatedUser);
        // Also persist to localStorage
        localStorage.setItem('user', JSON.stringify(updatedUser));
      }
      
      toast.success('Profile photo updated!');
      await loadUserProfile();
    } catch (error: any) {
      console.error('Failed to upload photo:', error);
      toast.error('Failed to upload photo');
    }
  };

  // Mobile photo upload handler - receives file directly from MobilePhotoUpload component
  const handleMobilePhotoUpload = async (file: File) => {
    try {
      toast.success('Uploading photo...');
      const result = await userService.uploadProfilePhoto(userId, file);
      setProfilePhoto(result.url);
      
      // Update user profile with new photo URL
      await userService.updateUserProfile(userId, { profile_picture_url: result.url });
      
      // Update auth store so the avatar updates immediately everywhere
      if (authUser) {
        const updatedUser = { ...authUser, profile_picture_url: result.url };
        setAuthUser(updatedUser);
        // Also persist to localStorage
        localStorage.setItem('user', JSON.stringify(updatedUser));
      }
      
      toast.success('Profile photo updated!');
      await loadUserProfile();
    } catch (error: any) {
      console.error('Failed to upload photo:', error);
      toast.error('Failed to upload photo');
    }
  };

  if (isLoading) {
    return <Loading />;
  }

  return (
    <div className="space-y-6">
      {/* Section Tabs */}
      <div className="border-b border-gray-200">
        <div className="flex gap-4">
          <button
            onClick={() => setActiveSection('profile')}
            className={`pb-3 px-2 border-b-2 font-medium text-sm transition-colors flex flex-col sm:flex-row items-center gap-1 sm:gap-2 ${
              activeSection === 'profile'
                ? 'border-primary-400 text-primary-400'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            <UserIcon className="w-4 h-4" />
            <span className="whitespace-nowrap">Profile Info</span>
          </button>
          <button
            onClick={() => setActiveSection('notifications')}
            className={`pb-3 px-2 border-b-2 font-medium text-sm transition-colors flex flex-col sm:flex-row items-center gap-1 sm:gap-2 ${
              activeSection === 'notifications'
                ? 'border-primary-400 text-primary-400'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            <Bell className="w-4 h-4" />
            <span className="whitespace-nowrap">Notifications</span>
          </button>
          <button
            onClick={() => setActiveSection('security')}
            className={`pb-3 px-2 border-b-2 font-medium text-sm transition-colors flex flex-col sm:flex-row items-center gap-1 sm:gap-2 ${
              activeSection === 'security'
                ? 'border-primary-400 text-primary-400'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            <Lock className="w-4 h-4" />
            <span className="whitespace-nowrap">Security</span>
          </button>
        </div>
      </div>

      {/* Profile Info Section */}
      {activeSection === 'profile' && (
        <div className="space-y-6">
          {/* Profile Photo */}
          <Card>
            <h3 className="text-lg font-semibold mb-4">Profile Photo</h3>
            {isMobileDevice() ? (
              /* Mobile: Use camera/gallery picker */
              <MobilePhotoUpload
                currentPhotoUrl={profilePhoto}
                onPhotoSelected={handleMobilePhotoUpload}
                isUploading={isSaving}
              />
            ) : (
              /* Desktop: Standard file upload */
              <div className="flex items-center gap-6">
                <div className="w-32 h-32 rounded-full overflow-hidden bg-gray-200 flex items-center justify-center">
                  {profilePhoto ? (
                    <img src={profilePhoto} alt="Profile" className="w-full h-full object-cover" />
                  ) : (
                    <ImageIcon className="w-12 h-12 text-gray-400" />
                  )}
                </div>
                <div>
                  <p className="text-sm text-gray-600 mb-2">Upload a profile photo</p>
                  <label className="cursor-pointer">
                    <Button variant="secondary" size="sm" as="span">
                      <Upload className="w-4 h-4 mr-2" />
                      Upload Photo
                    </Button>
                    <input
                      type="file"
                      accept="image/*"
                      onChange={handleUploadPhoto}
                      className="hidden"
                    />
                  </label>
                  <p className="text-xs text-gray-500 mt-2">Max size: 5MB. Formats: JPG, PNG</p>
                </div>
              </div>
            )}
          </Card>

          {/* Basic Info */}
          <Card>
            <h3 className="text-lg font-semibold mb-4">Basic Information</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  First Name <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={firstName}
                  onChange={(e) => setFirstName(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
                  required
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Last Name <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={lastName}
                  onChange={(e) => setLastName(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
                  required
                />
              </div>

            </div>
          </Card>

          {/* Email (Read-only) */}
          <Card>
            <h3 className="text-lg font-semibold mb-4">Email Address</h3>
            <div className="flex items-center gap-3">
              <Mail className="w-5 h-5 text-gray-400" />
              <div className="flex-1">
                <p className="font-medium text-gray-900">{user?.email}</p>
                <p className="text-sm text-gray-500">Verified {user?.is_verified ? '✓' : '✗'}</p>
              </div>
            </div>
          </Card>

          {/* Bio */}
          <Card>
            <h3 className="text-lg font-semibold mb-4">About You</h3>
            <textarea
              value={bio}
              onChange={(e) => setBio(e.target.value)}
              placeholder="Tell barbers about yourself (optional)..."
              rows={4}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
              maxLength={300}
            />
            <p className="text-xs text-gray-500 mt-2">{bio.length}/300 characters</p>
          </Card>

          {/* Save Button */}
          <div className="flex justify-end">
            <Button onClick={handleSaveProfile} disabled={isSaving} size="lg">
              <Save className="w-5 h-5 mr-2" />
              {isSaving ? 'Saving...' : 'Save Profile'}
            </Button>
          </div>
        </div>
      )}

      {/* Notifications Section */}
      {activeSection === 'notifications' && (
        <div className="space-y-6">
          <Card>
            <h3 className="text-lg font-semibold mb-4">Notification Preferences</h3>
            <div className="space-y-4">
              <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                <div>
                  <p className="font-medium text-gray-900">Email Notifications</p>
                  <p className="text-sm text-gray-600">Receive booking updates via email</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={emailNotifications}
                    onChange={(e) => setEmailNotifications(e.target.checked)}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-400"></div>
                </label>
              </div>

              <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                <div>
                  <p className="font-medium text-gray-900">Booking Reminders</p>
                  <p className="text-sm text-gray-600">Remind me before appointments</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={bookingReminders}
                    onChange={(e) => setBookingReminders(e.target.checked)}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-400"></div>
                </label>
              </div>

              {/* Promotional Emails - commented out for now
              <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                <div>
                  <p className="font-medium text-gray-900">Promotional Emails</p>
                  <p className="text-sm text-gray-600">Receive deals and special offers</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={promotionalEmails}
                    onChange={(e) => setPromotionalEmails(e.target.checked)}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-400"></div>
                </label>
              </div>
              */}
            </div>
          </Card>

          {/* Save Button */}
          <div className="flex justify-end">
            <Button onClick={handleSaveNotifications} disabled={isSaving} size="lg">
              <Save className="w-5 h-5 mr-2" />
              {isSaving ? 'Saving...' : 'Save Preferences'}
            </Button>
          </div>
        </div>
      )}

      {/* Security Section */}
      {activeSection === 'security' && (
        <div className="space-y-6">
          <Card>
            <h3 className="text-lg font-semibold mb-4">Change Password</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Current Password
                </label>
                <div className="relative">
                  <input
                    type={showCurrentPassword ? 'text' : 'password'}
                    value={currentPassword}
                    onChange={(e) => {
                      setCurrentPassword(e.target.value);
                      if (currentPasswordError) setCurrentPasswordError('');
                    }}
                    className={`w-full px-3 py-2 pr-10 border rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent ${
                      currentPasswordError ? 'border-red-500' : 'border-gray-300'
                    }`}
                  />
                  <button
                    type="button"
                    onClick={() => setShowCurrentPassword(!showCurrentPassword)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 transition-colors"
                  >
                    {showCurrentPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                  </button>
                </div>
                {currentPasswordError && (
                  <p className="text-xs text-red-500 mt-1">{currentPasswordError}</p>
                )}
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  New Password
                </label>
                <div className="relative">
                  <input
                    type={showNewPassword ? 'text' : 'password'}
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    className="w-full px-3 py-2 pr-10 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
                  />
                  <button
                    type="button"
                    onClick={() => setShowNewPassword(!showNewPassword)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 transition-colors"
                  >
                    {showNewPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                  </button>
                </div>
                <p className="text-xs text-gray-500 mt-1">Minimum 8 characters</p>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Confirm New Password
                </label>
                <div className="relative">
                  <input
                    type={showConfirmPassword ? 'text' : 'password'}
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    className={`w-full px-3 py-2 pr-10 border rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent ${
                      confirmPassword && newPassword && confirmPassword !== newPassword
                        ? 'border-red-500'
                        : 'border-gray-300'
                    }`}
                  />
                  <button
                    type="button"
                    onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 transition-colors"
                  >
                    {showConfirmPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                  </button>
                </div>
                {confirmPassword && newPassword && confirmPassword !== newPassword && (
                  <p className="text-xs text-red-500 mt-1">Passwords do not match</p>
                )}
              </div>

              <div className="flex flex-col items-end gap-2">
                <Button 
                  onClick={handleChangePassword} 
                  disabled={isSaving || !currentPassword || !newPassword || !confirmPassword || newPassword !== confirmPassword}
                >
                  <Lock className="w-4 h-4 mr-2" />
                  Change Password
                </Button>
                {passwordChangeSuccess && (
                  <p className="text-sm text-green-600 font-medium">Password successfully changed</p>
                )}
              </div>
            </div>
          </Card>
        </div>
      )}

      {/* Delete Account Section */}
      {activeSection === 'delete' && (
        <div className="space-y-6">
          {/* Warning Banner */}
          <div className="bg-red-50 border border-red-200 rounded-lg p-4">
            <h3 className="font-semibold text-red-800">Delete Your Account</h3>
            <p className="text-sm text-red-700 mt-1">
              This action is permanent and cannot be undone. All your data, bookings, and account information will be permanently deleted.
            </p>
          </div>

          <Card>
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Confirm Account Deletion</h3>
            
            {/* Password verification */}
            <div className="mb-4">
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Enter your password to confirm
              </label>
              <div className="relative">
                <input
                  type={showDeletePassword ? 'text' : 'password'}
                  value={deletePassword}
                  onChange={(e) => {
                    setDeletePassword(e.target.value);
                    setDeletePasswordError('');
                  }}
                  placeholder="Your password"
                  className={`w-full px-3 py-2 pr-10 border rounded-lg focus:ring-2 focus:ring-red-400 focus:border-transparent ${
                    deletePasswordError ? 'border-red-500' : 'border-gray-300'
                  }`}
                />
                <button
                  type="button"
                  onClick={() => setShowDeletePassword(!showDeletePassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
                >
                  {showDeletePassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                </button>
              </div>
              {deletePasswordError && (
                <p className="text-xs text-red-500 mt-1">{deletePasswordError}</p>
              )}
            </div>

            {/* Type DELETE confirmation */}
            <div className="mb-6">
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Type <span className="font-bold text-red-600">DELETE</span> to confirm
              </label>
              <input
                type="text"
                value={deleteConfirmText}
                onChange={(e) => setDeleteConfirmText(e.target.value)}
                placeholder="DELETE"
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-400 focus:border-transparent"
              />
            </div>

            {/* Actions */}
            <div className="flex gap-3">
              <Button
                variant="secondary"
                onClick={() => {
                  setActiveSection('profile');
                  setDeletePassword('');
                  setDeleteConfirmText('');
                  setDeletePasswordError('');
                }}
                className="flex-1"
              >
                Cancel
              </Button>
              <Button
                variant="primary"
                onClick={handleDeleteAccount}
                disabled={isDeleting || !deletePassword || deleteConfirmText !== 'DELETE'}
                className="flex-1 bg-red-600 hover:bg-red-700 text-white disabled:bg-red-300"
              >
                {isDeleting ? 'Deleting...' : 'Delete My Account'}
              </Button>
            </div>
          </Card>
        </div>
      )}
    </div>
  );
});

ConsumerProfileEditor.displayName = 'ConsumerProfileEditor';

export default ConsumerProfileEditor;
