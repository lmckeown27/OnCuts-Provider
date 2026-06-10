import api from './api.service';
import type { User } from '../types';

interface UpdateUserProfile {
  first_name?: string;
  last_name?: string;
  username?: string;
  profile_picture_url?: string;
  bio?: string;
}

interface NotificationPreferences {
  email_notifications: boolean;
  push_notifications: boolean;
  booking_reminders: boolean;
  promotional_emails: boolean;
}

class UserService {
  async getUserProfile(userId: string): Promise<User> {
    return await api.get<User>(`/users/${userId}`);
  }

  async updateUserProfile(userId: string, data: UpdateUserProfile): Promise<User> {
    return await api.put<User>(`/users/${userId}`, data);
  }

  async uploadProfilePhoto(userId: string, file: File): Promise<{ url: string }> {
    console.log('[UserService] uploadProfilePhoto called:', { userId, fileName: file.name, fileSize: file.size, fileType: file.type });
    const formData = new FormData();
    formData.append('image', file);
    console.log('[UserService] FormData created, calling api.upload');
    const result = await api.upload<{ url: string }>(`/upload/profile-photo`, formData);
    console.log('[UserService] Upload result:', result);
    return result;
  }

  async getNotificationPreferences(userId: string): Promise<NotificationPreferences> {
    return await api.get<NotificationPreferences>(`/users/${userId}/notification-preferences`);
  }

  async updateNotificationPreferences(
    userId: string,
    preferences: Partial<NotificationPreferences>
  ): Promise<NotificationPreferences> {
    return await api.put<NotificationPreferences>(
      `/users/${userId}/notification-preferences`,
      preferences
    );
  }

  async changePassword(userId: string, currentPassword: string, newPassword: string): Promise<void> {
    await api.put(`/users/${userId}/change-password`, {
      currentPassword,
      newPassword,
    });
  }

  async deleteAccount(userId: string, password: string): Promise<void> {
    await api.delete(`/users/${userId}`, { password });
  }
}

export default new UserService();

