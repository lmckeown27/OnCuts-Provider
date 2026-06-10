/**
 * Admin Users Controller
 * 
 * Handles admin operations on user accounts
 */

import { Request, Response, NextFunction } from 'express';
import { logger } from '../utils/logger';

/**
 * Mock user database for demo purposes
 * In production, this would query PostgreSQL or blockchain
 */
const mockUsers: Record<string, any> = {};

// Initialize comprehensive mock users (matching transaction data)
const initMockUsers = () => {
  // Helper to generate user data
  const createBarber = (id: string, name: string, campus: string, domain: string, bookings: number, rating: number, specialties: string[]) => ({
    id,
    name,
    email: `${name.toLowerCase().replace(/\s/g, '.')}@${domain}`,
    role: 'barber',
    wallet_address: `0xB${Math.random().toString(16).slice(2, 42).padEnd(40, '0')}`,
    status: 'active',
    is_verified: true,
    created_at: new Date(Date.now() - Math.random() * 365 * 24 * 60 * 60 * 1000).toISOString(),
    last_login: new Date(Date.now() - Math.random() * 7 * 24 * 60 * 60 * 1000).toISOString(),
    total_bookings: bookings,
    total_earned: bookings * 35,
    average_rating: rating,
    specialties,
    campus,
    admin_notes: [],
    flags: [],
  });

  const createStudent = (id: string, name: string, campus: string, domain: string, bookings: number) => ({
    id,
    name,
    email: `${name.toLowerCase().replace(/\s/g, '.')}@${domain}`,
    role: 'student',
    wallet_address: `0xS${Math.random().toString(16).slice(2, 42).padEnd(40, '0')}`,
    status: 'active',
    is_verified: true,
    created_at: new Date(Date.now() - Math.random() * 365 * 24 * 60 * 60 * 1000).toISOString(),
    last_login: new Date(Date.now() - Math.random() * 7 * 24 * 60 * 60 * 1000).toISOString(),
    total_bookings: bookings,
    total_spent: bookings * 35,
    campus,
    admin_notes: [],
    flags: [],
  });

  // Cal Poly Barbers
  mockUsers['user-marcus-thompson'] = createBarber('user-marcus-thompson', 'Marcus Thompson', 'California Polytechnic State University', 'calpoly.edu', 156, 4.9, ['Fades', 'Curly Hair', 'Beard Grooming']);
  mockUsers['user-jordan-williams'] = createBarber('user-jordan-williams', 'Jordan Williams', 'California Polytechnic State University', 'calpoly.edu', 132, 4.8, ['Line-ups', 'Buzz Cuts', 'Fades']);
  mockUsers['user-alex-chen'] = createBarber('user-alex-chen', 'Alex Chen', 'California Polytechnic State University', 'calpoly.edu', 98, 4.7, ['Tapers', 'Fades', 'Modern Styles']);
  mockUsers['user-sophia-davis'] = createBarber('user-sophia-davis', 'Sophia Davis', 'California Polytechnic State University', 'calpoly.edu', 124, 4.9, ['Women\'s Cuts', 'Styling', 'Color']);
  mockUsers['user-liam-miller'] = createBarber('user-liam-miller', 'Liam Miller', 'California Polytechnic State University', 'calpoly.edu', 87, 4.6, ['Classic Cuts', 'Beard Trims']);
  mockUsers['user-noah-moore'] = createBarber('user-noah-moore', 'Noah Moore', 'California Polytechnic State University', 'calpoly.edu', 95, 4.7, ['Fades', 'Designs', 'Line-ups']);

  // Cal Poly Students
  mockUsers['user-alice-smith'] = createStudent('user-alice-smith', 'Alice Smith', 'California Polytechnic State University', 'calpoly.edu', 12);
  mockUsers['user-bob-johnson'] = createStudent('user-bob-johnson', 'Bob Johnson', 'California Polytechnic State University', 'calpoly.edu', 8);
  mockUsers['user-charlie-brown'] = createStudent('user-charlie-brown', 'Charlie Brown', 'California Polytechnic State University', 'calpoly.edu', 15);
  mockUsers['user-diana-prince'] = createStudent('user-diana-prince', 'Diana Prince', 'California Polytechnic State University', 'calpoly.edu', 10);
  mockUsers['user-eve-adams'] = createStudent('user-eve-adams', 'Eve Adams', 'California Polytechnic State University', 'calpoly.edu', 7);
  mockUsers['user-frank-white'] = createStudent('user-frank-white', 'Frank White', 'California Polytechnic State University', 'calpoly.edu', 9);
  mockUsers['user-grace-lee'] = createStudent('user-grace-lee', 'Grace Lee', 'California Polytechnic State University', 'calpoly.edu', 11);
  mockUsers['user-henry-king'] = createStudent('user-henry-king', 'Henry King', 'California Polytechnic State University', 'calpoly.edu', 6);
  mockUsers['user-ivy-green'] = createStudent('user-ivy-green', 'Ivy Green', 'California Polytechnic State University', 'calpoly.edu', 13);
  mockUsers['user-jack-black'] = createStudent('user-jack-black', 'Jack Black', 'California Polytechnic State University', 'calpoly.edu', 8);

  // UCSB Barbers
  mockUsers['user-tyler-martinez'] = createBarber('user-tyler-martinez', 'Tyler Martinez', 'University of California, Santa Barbara', 'ucsb.edu', 145, 4.8, ['Fades', 'Modern Styles', 'Beard Grooming']);
  mockUsers['user-sarah-johnson'] = createBarber('user-sarah-johnson', 'Sarah Johnson', 'University of California, Santa Barbara', 'ucsb.edu', 128, 4.9, ['Women\'s Cuts', 'Styling', 'Treatments']);
  mockUsers['user-daniel-lee'] = createBarber('user-daniel-lee', 'Daniel Lee', 'University of California, Santa Barbara', 'ucsb.edu', 112, 4.7, ['Classic Cuts', 'Fades', 'Line-ups']);
  mockUsers['user-emily-brown'] = createBarber('user-emily-brown', 'Emily Brown', 'University of California, Santa Barbara', 'ucsb.edu', 134, 4.8, ['Modern Styles', 'Color', 'Styling']);
  mockUsers['user-michael-davis'] = createBarber('user-michael-davis', 'Michael Davis', 'University of California, Santa Barbara', 'ucsb.edu', 98, 4.6, ['Fades', 'Tapers', 'Designs']);

  // UCSB Students
  mockUsers['user-mia-taylor'] = createStudent('user-mia-taylor', 'Mia Taylor', 'University of California, Santa Barbara', 'ucsb.edu', 14);
  mockUsers['user-james-anderson'] = createStudent('user-james-anderson', 'James Anderson', 'University of California, Santa Barbara', 'ucsb.edu', 11);
  mockUsers['user-charlotte-thomas'] = createStudent('user-charlotte-thomas', 'Charlotte Thomas', 'University of California, Santa Barbara', 'ucsb.edu', 9);
  mockUsers['user-william-jackson'] = createStudent('user-william-jackson', 'William Jackson', 'University of California, Santa Barbara', 'ucsb.edu', 7);
  mockUsers['user-amelia-white'] = createStudent('user-amelia-white', 'Amelia White', 'University of California, Santa Barbara', 'ucsb.edu', 12);
  mockUsers['user-ethan-harris'] = createStudent('user-ethan-harris', 'Ethan Harris', 'University of California, Santa Barbara', 'ucsb.edu', 10);
  mockUsers['user-harper-martin'] = createStudent('user-harper-martin', 'Harper Martin', 'University of California, Santa Barbara', 'ucsb.edu', 8);

  // UCLA Barbers
  mockUsers['user-carlos-rodriguez'] = createBarber('user-carlos-rodriguez', 'Carlos Rodriguez', 'University of California, Los Angeles', 'ucla.edu', 167, 4.9, ['Fades', 'Modern Styles', 'Designs']);
  mockUsers['user-jessica-green'] = createBarber('user-jessica-green', 'Jessica Green', 'University of California, Los Angeles', 'ucla.edu', 142, 4.8, ['Women\'s Cuts', 'Styling', 'Color']);
  mockUsers['user-david-baker'] = createBarber('user-david-baker', 'David Baker', 'University of California, Los Angeles', 'ucla.edu', 156, 4.9, ['Classic Cuts', 'Fades', 'Beard Grooming']);
  mockUsers['user-ashley-nelson'] = createBarber('user-ashley-nelson', 'Ashley Nelson', 'University of California, Los Angeles', 'ucla.edu', 138, 4.8, ['Modern Styles', 'Treatments', 'Styling']);
  mockUsers['user-christopher-carter'] = createBarber('user-christopher-carter', 'Christopher Carter', 'University of California, Los Angeles', 'ucla.edu', 125, 4.7, ['Fades', 'Line-ups', 'Designs']);

  // UCLA Students
  mockUsers['user-sophia-martinez'] = createStudent('user-sophia-martinez', 'Sophia Martinez', 'University of California, Los Angeles', 'ucla.edu', 16);
  mockUsers['user-jacob-hernandez'] = createStudent('user-jacob-hernandez', 'Jacob Hernandez', 'University of California, Los Angeles', 'ucla.edu', 13);
  mockUsers['user-isabella-lopez'] = createStudent('user-isabella-lopez', 'Isabella Lopez', 'University of California, Los Angeles', 'ucla.edu', 11);
  mockUsers['user-mason-gonzalez'] = createStudent('user-mason-gonzalez', 'Mason Gonzalez', 'University of California, Los Angeles', 'ucla.edu', 9);
  mockUsers['user-ava-perez'] = createStudent('user-ava-perez', 'Ava Perez', 'University of California, Los Angeles', 'ucla.edu', 14);
  mockUsers['user-ryan-allen'] = createStudent('user-ryan-allen', 'Ryan Allen', 'University of California, Los Angeles', 'ucla.edu', 10);
  mockUsers['user-kimberly-young'] = createStudent('user-kimberly-young', 'Kimberly Young', 'University of California, Los Angeles', 'ucla.edu', 12);
  mockUsers['user-brandon-hernandez'] = createStudent('user-brandon-hernandez', 'Brandon Hernandez', 'University of California, Los Angeles', 'ucla.edu', 8);
  mockUsers['user-samantha-king'] = createStudent('user-samantha-king', 'Samantha King', 'University of California, Los Angeles', 'ucla.edu', 15);
};

initMockUsers();

/**
 * GET /api/admin/users/:userId
 * Get user details
 */
export const getUserById = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { userId } = req.params;

    logger.info(`Fetching user details for ${userId}`);

    const user = mockUsers[userId];

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    // Generate mock activity logs
    const activityLogs = [
      {
        id: 'act-1',
        timestamp: new Date(Date.now() - Math.random() * 60 * 60 * 1000).toISOString(),
        action: 'Login',
        details: `Logged in from ${Math.floor(Math.random() * 255)}.${Math.floor(Math.random() * 255)}.x.x`,
      },
      {
        id: 'act-2',
        timestamp: new Date(Date.now() - Math.random() * 2 * 24 * 60 * 60 * 1000).toISOString(),
        action: user.role === 'barber' ? 'Booking Completed' : 'Booking Created',
        details: user.role === 'barber' 
          ? `Completed booking #BK-${Math.floor(Math.random() * 9000) + 1000}` 
          : `Created booking #BK-${Math.floor(Math.random() * 9000) + 1000}`,
      },
      {
        id: 'act-3',
        timestamp: new Date(Date.now() - Math.random() * 3 * 24 * 60 * 60 * 1000).toISOString(),
        action: user.role === 'barber' ? 'Payment Received' : 'Payment Sent',
        details: user.role === 'barber' 
          ? `Received $${(Math.random() * 20 + 30).toFixed(2)} for booking` 
          : `Paid $${(Math.random() * 20 + 30).toFixed(2)} for haircut`,
      },
      {
        id: 'act-4',
        timestamp: new Date(Date.now() - Math.random() * 5 * 24 * 60 * 60 * 1000).toISOString(),
        action: user.role === 'barber' ? 'Profile Updated' : 'Review Posted',
        details: user.role === 'barber' 
          ? 'Updated availability schedule' 
          : 'Posted 5-star review',
      },
    ];

    // Generate mock transactions based on user's total bookings
    const transactions = [];
    const numTransactions = Math.min(user.total_bookings || 5, 10);
    
    if (user.role === 'barber') {
      // Barber receives payments and makes withdrawals
      for (let i = 0; i < numTransactions; i++) {
        transactions.push({
          id: `tx-${i + 1}`,
          type: 'Payment Received',
          amount: Math.floor(Math.random() * 20 + 30),
          date: new Date(Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000).toISOString(),
          status: 'completed',
          counterparty: ['Student', 'Client'][Math.floor(Math.random() * 2)] + ` #${Math.floor(Math.random() * 1000)}`,
        });
      }
      // Add a withdrawal
      transactions.push({
        id: `tx-${numTransactions + 1}`,
        type: 'Withdrawal',
        amount: -Math.floor(Math.random() * 300 + 200),
        date: new Date(Date.now() - Math.random() * 15 * 24 * 60 * 60 * 1000).toISOString(),
        status: 'completed',
        counterparty: `Bank Account ****${Math.floor(Math.random() * 9000) + 1000}`,
      });
    } else {
      // Student sends payments
      for (let i = 0; i < numTransactions; i++) {
        transactions.push({
          id: `tx-${i + 1}`,
          type: 'Payment Sent',
          amount: -Math.floor(Math.random() * 20 + 30),
          date: new Date(Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000).toISOString(),
          status: 'completed',
          counterparty: ['Barber', 'Service'][Math.floor(Math.random() * 2)] + ` #${Math.floor(Math.random() * 1000)}`,
        });
      }
    }

    // Sort transactions by date (most recent first)
    transactions.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
    
    res.json({
      success: true,
      user,
      activityLogs,
      transactions,
    });
  } catch (error: any) {
    logger.error('Error fetching user:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error',
    });
  }
};

/**
 * PUT /api/admin/users/:userId/status
 * Update user status (active, blocked, banned, suspended)
 */
export const updateUserStatus = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { userId } = req.params;
    const { status } = req.body;

    logger.info(`Updating status for ${userId} to ${status}`);

    const user = mockUsers[userId];

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    if (!['active', 'blocked', 'banned', 'suspended'].includes(status)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid status',
      });
    }

    user.status = status;

    res.json({
      success: true,
      user,
    });
  } catch (error: any) {
    logger.error('Error updating user status:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error',
    });
  }
};

/**
 * PUT /api/admin/users/:userId/verification
 * Toggle user verification status
 */
export const toggleVerification = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { userId } = req.params;

    logger.info(`Toggling verification for ${userId}`);

    const user = mockUsers[userId];

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    user.is_verified = !user.is_verified;

    res.json({
      success: true,
      user,
    });
  } catch (error: any) {
    logger.error('Error toggling verification:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error',
    });
  }
};

/**
 * POST /api/admin/users/:userId/notes
 * Add admin note to user
 */
export const addAdminNote = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { userId } = req.params;
    const { note } = req.body;

    logger.info(`Adding note to ${userId}`);

    const user = mockUsers[userId];

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    if (!note || !note.trim()) {
      return res.status(400).json({
        success: false,
        message: 'Note cannot be empty',
      });
    }

    const timestamp = new Date().toISOString().split('T')[0];
    const formattedNote = `${note} - ${timestamp}`;
    user.admin_notes.unshift(formattedNote);

    res.json({
      success: true,
      user,
    });
  } catch (error: any) {
    logger.error('Error adding admin note:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error',
    });
  }
};

/**
 * POST /api/admin/users/:userId/reset-password
 * Send password reset email to user
 */
export const resetPassword = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { userId } = req.params;

    logger.info(`Sending password reset for ${userId}`);

    const user = mockUsers[userId];

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    // In production: send actual password reset email
    logger.info(`Password reset email sent to ${user.email}`);

    res.json({
      success: true,
      message: `Password reset email sent to ${user.email}`,
    });
  } catch (error: any) {
    logger.error('Error resetting password:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error',
    });
  }
};

/**
 * DELETE /api/admin/users/:userId
 * Delete user account (dangerous operation)
 */
export const deleteUser = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { userId } = req.params;

    logger.warn(`DELETING user ${userId}`);

    const user = mockUsers[userId];

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    // In production: soft-delete or archive user data
    delete mockUsers[userId];

    res.json({
      success: true,
      message: 'User deleted successfully',
    });
  } catch (error: any) {
    logger.error('Error deleting user:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error',
    });
  }
};

