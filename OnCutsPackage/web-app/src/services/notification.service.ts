import api from './api.service';

export interface Notification {
  id: string;
  type: string;
  title: string;
  message: string;
  data?: any;
  is_read: boolean;
  created_at: string;
}

interface NotificationsResponse {
  success: boolean;
  data: {
    notifications: Notification[];
    unreadCount: number;
    pagination: {
      page: number;
      limit: number;
      total: number;
    };
  };
}

class NotificationService {
  async getNotifications(page = 1, limit = 20): Promise<NotificationsResponse['data']> {
    // api.get already extracts response.data.data, so we get the inner data directly
    const data = await api.get<NotificationsResponse['data']>('/notifications', { page, limit });
    
    // Handle various response formats
    if (data && 'notifications' in data) {
      return data;
    }
    
    // Fallback: if the response structure is different
    const responseData = data as any;
    return {
      notifications: responseData?.notifications || [],
      unreadCount: responseData?.unreadCount || 0,
      pagination: responseData?.pagination || { page: 1, limit: 20, total: 0 },
    };
  }

  async markAsRead(notificationId: string): Promise<void> {
    await api.put(`/notifications/${notificationId}/read`, {});
  }

  async markAllAsRead(): Promise<void> {
    await api.put('/notifications/read-all', {});
  }

  async deleteNotification(notificationId: string): Promise<void> {
    await api.delete(`/notifications/${notificationId}`);
  }

  async deleteAllNotifications(): Promise<void> {
    await api.delete('/notifications/all');
  }
}

export default new NotificationService();

