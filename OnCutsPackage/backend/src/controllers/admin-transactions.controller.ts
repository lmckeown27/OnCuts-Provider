/**
 * Admin Transactions Controller
 * 
 * Returns MOCK transactions for visualization (no database required)
 */

import { Request, Response, NextFunction } from 'express';
import { logger } from '../utils/logger';

/**
 * Shuffle array (Fisher-Yates algorithm)
 */
const shuffleArray = (array: any[]) => {
  const shuffled = [...array];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
};

/**
 * Generate mock transactions for a specific campus
 * Randomizes order on each call to simulate live updates
 */
const generateMockTransactions = (campus: string, limit: number) => {
  const campusData: Record<string, any> = {
    'campus-1': {
      name: 'Cal Poly',
      color: 'blue',
      transactions: [
        { amount: 35, student: 'Alice Smith', barber: 'Marcus Thompson', status: 'completed', minutesAgo: 5 },
        { amount: 42, student: 'Bob Johnson', barber: 'Jordan Williams', status: 'completed', minutesAgo: 15 },
        { amount: 30, student: 'Charlie Brown', barber: 'Alex Chen', status: 'completed', minutesAgo: 30 },
        { amount: 38, student: 'Diana Prince', barber: 'Marcus Thompson', status: 'completed', minutesAgo: 45 },
        { amount: 45, student: 'Eve Adams', barber: 'Sophia Davis', status: 'completed', minutesAgo: 60 },
        { amount: 32, student: 'Frank White', barber: 'Jordan Williams', status: 'pending', minutesAgo: 75 },
        { amount: 40, student: 'Grace Lee', barber: 'Liam Miller', status: 'completed', minutesAgo: 90 },
        { amount: 36, student: 'Henry King', barber: 'Noah Moore', status: 'completed', minutesAgo: 120 },
        { amount: 43, student: 'Ivy Green', barber: 'Marcus Thompson', status: 'completed', minutesAgo: 150 },
        { amount: 31, student: 'Jack Black', barber: 'Jordan Williams', status: 'confirmed', minutesAgo: 180 },
        { amount: 37, student: 'Alice Smith', barber: 'Alex Chen', status: 'completed', minutesAgo: 240 },
        { amount: 44, student: 'Bob Johnson', barber: 'Sophia Davis', status: 'completed', minutesAgo: 300 },
        { amount: 33, student: 'Charlie Brown', barber: 'Marcus Thompson', status: 'completed', minutesAgo: 360 },
        { amount: 39, student: 'Diana Prince', barber: 'Jordan Williams', status: 'completed', minutesAgo: 420 },
        { amount: 41, student: 'Eve Adams', barber: 'Liam Miller', status: 'cancelled', minutesAgo: 480 },
      ],
    },
    'campus-2': {
      name: 'UCSB',
      color: 'green',
      transactions: [
        { amount: 38, student: 'Mia Taylor', barber: 'Tyler Martinez', status: 'completed', minutesAgo: 8 },
        { amount: 45, student: 'James Anderson', barber: 'Sarah Johnson', status: 'completed', minutesAgo: 20 },
        { amount: 32, student: 'Charlotte Thomas', barber: 'Daniel Lee', status: 'completed', minutesAgo: 35 },
        { amount: 40, student: 'William Jackson', barber: 'Emily Brown', status: 'pending', minutesAgo: 50 },
        { amount: 37, student: 'Amelia White', barber: 'Tyler Martinez', status: 'completed', minutesAgo: 70 },
        { amount: 43, student: 'Ethan Harris', barber: 'Michael Davis', status: 'completed', minutesAgo: 100 },
        { amount: 36, student: 'Harper Martin', barber: 'Sarah Johnson', status: 'confirmed', minutesAgo: 130 },
        { amount: 41, student: 'Mia Taylor', barber: 'Daniel Lee', status: 'completed', minutesAgo: 200 },
        { amount: 39, student: 'James Anderson', barber: 'Emily Brown', status: 'completed', minutesAgo: 270 },
        { amount: 34, student: 'Charlotte Thomas', barber: 'Tyler Martinez', status: 'completed', minutesAgo: 340 },
      ],
    },
    'campus-3': {
      name: 'UCLA',
      color: 'purple',
      transactions: [
        { amount: 42, student: 'Sophia Martinez', barber: 'Carlos Rodriguez', status: 'completed', minutesAgo: 3 },
        { amount: 37, student: 'Jacob Hernandez', barber: 'Jessica Green', status: 'completed', minutesAgo: 12 },
        { amount: 48, student: 'Isabella Lopez', barber: 'David Baker', status: 'completed', minutesAgo: 25 },
        { amount: 35, student: 'Mason Gonzalez', barber: 'Ashley Nelson', status: 'completed', minutesAgo: 40 },
        { amount: 44, student: 'Ava Perez', barber: 'Carlos Rodriguez', status: 'pending', minutesAgo: 55 },
        { amount: 39, student: 'Ryan Allen', barber: 'Christopher Carter', status: 'completed', minutesAgo: 80 },
        { amount: 46, student: 'Kimberly Young', barber: 'Jessica Green', status: 'completed', minutesAgo: 110 },
        { amount: 33, student: 'Brandon Hernandez', barber: 'David Baker', status: 'confirmed', minutesAgo: 140 },
        { amount: 41, student: 'Samantha King', barber: 'Carlos Rodriguez', status: 'completed', minutesAgo: 190 },
        { amount: 38, student: 'Sophia Martinez', barber: 'Ashley Nelson', status: 'completed', minutesAgo: 250 },
        { amount: 43, student: 'Jacob Hernandez', barber: 'Christopher Carter', status: 'completed', minutesAgo: 320 },
        { amount: 36, student: 'Isabella Lopez', barber: 'Jessica Green', status: 'completed', minutesAgo: 400 },
        { amount: 45, student: 'Mason Gonzalez', barber: 'Carlos Rodriguez', status: 'completed', minutesAgo: 480 },
        { amount: 40, student: 'Ava Perez', barber: 'David Baker', status: 'cancelled', minutesAgo: 550 },
      ],
    },
  };

  const data = campusData[campus] || campusData['campus-1'];
  const now = new Date();

  // Shuffle transactions to simulate live updates on each reload
  const shuffledTransactions = shuffleArray(data.transactions);

  return shuffledTransactions.slice(0, limit).map((tx: any, index: number) => {
    const timestamp = new Date(now.getTime() - tx.minutesAgo * 60000);
    
    // Generate consistent user IDs based on names (for demo purposes)
    const studentId = `user-${tx.student.replace(/\s/g, '-').toLowerCase()}`;
    const barberId = `user-${tx.barber.replace(/\s/g, '-').toLowerCase()}`;
    
    return {
      id: `mock-${campus}-${index}`,
      type: tx.status === 'completed' ? 'DONE' : 
            tx.status === 'pending' ? 'BOOK' : 
            tx.status === 'confirmed' ? 'PAY' : 'TXN',
      timestamp: timestamp.toISOString(),
      amount: tx.amount, // Return as number, let frontend format it
      from: tx.student,
      to: tx.barber,
      fromName: tx.student,
      toName: tx.barber,
      fromId: studentId,
      toId: barberId,
      status: tx.status,
      description: `${tx.student} → ${tx.barber}`,
      txHash: `0x${(campus + index).padStart(64, '0')}`,
      campus: data.name,
    };
  });
};

/**
 * GET /api/admin/transactions
 * Returns mock transaction data (no database required)
 */
export const getRecentTransactions = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const { campus = 'campus-1', limit = '20' } = req.query;
    const limitNum = Math.min(parseInt(limit as string), 100);

    logger.info('Fetching mock transactions', {
      campus,
      limit: limitNum,
    });

    // Generate mock transactions
    const transactions = generateMockTransactions(campus as string, limitNum);

    res.json({
      success: true,
      transactions,
      count: transactions.length,
      campus: campus || 'all',
      mock: true, // Indicate this is mock data
    });
  } catch (error: any) {
    logger.error('Failed to fetch mock transactions:', error);
    next(error);
  }
};

/**
 * GET /api/admin/transactions/stats
 * Returns mock transaction statistics
 */
export const getTransactionStats = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const { campus } = req.query;

    const stats: Record<string, any> = {
      'campus-1': {
        name: 'Cal Poly',
        total_transactions: 156,
        total_volume: 5840.00,
        avg_transaction: 37.44,
        completed: 142,
        pending: 8,
        cancelled: 6,
      },
      'campus-2': {
        name: 'UCSB',
        total_transactions: 98,
        total_volume: 3724.00,
        avg_transaction: 38.00,
        completed: 89,
        pending: 5,
        cancelled: 4,
      },
      'campus-3': {
        name: 'UCLA',
        total_transactions: 203,
        total_volume: 8321.00,
        avg_transaction: 41.00,
        completed: 189,
        pending: 9,
        cancelled: 5,
      },
    };

    const campusStats = campus ? stats[campus as string] : null;

    res.json({
      success: true,
      stats: campusStats || stats,
      mock: true,
    });
  } catch (error: any) {
    logger.error('Failed to fetch mock stats:', error);
    next(error);
  }
};
