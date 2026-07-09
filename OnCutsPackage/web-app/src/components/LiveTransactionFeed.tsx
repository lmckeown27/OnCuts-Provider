/**
 * Live Transaction Feed Component
 * 
 * Displays real-time chain and Stripe payment transactions
 * Uses WebSocket for live updates
 */

import { useEffect, useState } from 'react';
import { io, Socket } from 'socket.io-client';
import Card from './Card';
import { toast } from 'react-hot-toast';

interface Transaction {
  platform: 'sui' | 'stripe';
  transaction_id: string;
  transaction_type: string;
  from_address?: string;
  to_address?: string;
  amount_usd?: number;
  description: string;
  timestamp: string;
  status_success: boolean;
  metadata?: any;
  
  // Chain-specific (optional)
  tx_hash?: string;
  sender?: string;
  recipient?: string;
  amount_apt?: number;
  gas_used?: number;
  
  // Stripe specific
  event_id?: string;
  event_type?: string;
  payment_intent_id?: string;
  student_email?: string;
  barber_email?: string;
  booking_id?: string;
  amount_cents?: number;
  status?: string;
}

interface PlatformStats {
  platform: string;
  transaction_count: number;
  successful_volume_usd: number;
  successful_count: number;
  failed_count: number;
}

export default function LiveTransactionFeed() {
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [stats, setStats] = useState<PlatformStats[]>([]);
  const [socket, setSocket] = useState<Socket | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [filter, setFilter] = useState<'all' | 'sui' | 'stripe'>('all');
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    // Connect to WebSocket
    const socketInstance = io('http://localhost:3001', {
      transports: ['polling', 'websocket'],
    });

    socketInstance.on('connect', () => {
      console.log('✅ Connected to live feed WebSocket');
      setIsConnected(true);
      // Join admin live feed room
      socketInstance.emit('join-admin-live-feed', 1); // TODO: Use actual admin user ID
    });

    socketInstance.on('disconnect', () => {
      console.log('❌ Disconnected from live feed WebSocket');
      setIsConnected(false);
    });

    socketInstance.on('connect_error', () => {
      console.log('⚠️ WebSocket connection failed - using mock data');
      setIsConnected(false);
    });

    // Listen for Sui transactions (admin feed)
    socketInstance.on('sui-transaction', (tx: Transaction) => {
      console.log('⛓️ New Sui transaction:', tx);
      setTransactions((prev) => [tx, ...prev].slice(0, 100)); // Keep last 100
      toast(`New Sui transaction: ${tx.description}`, {
        icon: '⛓️',
        duration: 3000,
      });
    });

    // Listen for Stripe payments
    socketInstance.on('stripe-payment', (payment: Transaction) => {
      console.log('💳 New Stripe payment:', payment);
      setTransactions((prev) => [payment, ...prev].slice(0, 100)); // Keep last 100
      toast(`New Stripe payment: ${payment.description}`, {
        icon: '💳',
        duration: 3000,
      });
    });

    setSocket(socketInstance);

    // Fetch initial data
    fetchInitialData();

    // Cleanup on unmount
    return () => {
      socketInstance.disconnect();
    };
  }, []);

  const fetchInitialData = async () => {
    try {
      setIsLoading(true);

      // Fetch recent transactions
      const txResponse = await fetch('http://localhost:3001/api/admin/live-feed?limit=50');
      const txData = await txResponse.json();
      
      if (txData.success) {
        setTransactions(txData.data);
      }

      // Fetch platform stats
      const statsResponse = await fetch('http://localhost:3001/api/admin/live-feed/stats');
      const statsData = await statsResponse.json();
      
      if (statsData.success) {
        setStats(statsData.data.realtime);
      }

      setIsLoading(false);
    } catch (error) {
      console.error('Failed to fetch initial data:', error);
      // Keep empty arrays on API failure
      setTransactions([]);
      setStats([]);
      setIsLoading(false);
    }
  };

  const filteredTransactions = transactions.filter((tx) => {
    if (filter === 'all') return true;
    return tx.platform === filter;
  });

  const getPlatformIcon = (platform: string) => {
    if (platform === 'sui') return '⛓️';
    if (platform === 'stripe') return '💳';
    return '💰';
  };

  const getStatusBadge = (tx: Transaction) => {
    if (tx.platform === 'sui') {
      return tx.status_success ? (
        <span className="px-2 py-1 bg-green-100 text-green-800 text-xs font-semibold rounded-full">
          Success
        </span>
      ) : (
        <span className="px-2 py-1 bg-red-100 text-red-800 text-xs font-semibold rounded-full">
          Failed
        </span>
      );
    } else {
      const status = tx.status || 'unknown';
      const colorMap: Record<string, string> = {
        succeeded: 'bg-green-100 text-green-800',
        paid: 'bg-green-100 text-green-800',
        created: 'bg-blue-100 text-blue-800',
        failed: 'bg-red-100 text-red-800',
        refunded: 'bg-yellow-100 text-yellow-800',
      };
      const colorClass = colorMap[status] || 'bg-gray-100 text-gray-800';
      return (
        <span className={`px-2 py-1 ${colorClass} text-xs font-semibold rounded-full capitalize`}>
          {status}
        </span>
      );
    }
  };

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp);
    const now = new Date();
    const diffSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);

    if (diffSeconds < 60) return `${diffSeconds}s ago`;
    if (diffSeconds < 3600) return `${Math.floor(diffSeconds / 60)}m ago`;
    if (diffSeconds < 86400) return `${Math.floor(diffSeconds / 3600)}h ago`;
    return date.toLocaleString();
  };

  if (isLoading) {
    return (
      <Card>
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-400"></div>
        </div>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header with stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">WebSocket Status</p>
              <p className={`text-2xl font-bold ${isConnected ? 'text-green-600' : 'text-red-600'}`}>
                {isConnected ? 'Connected' : 'Disconnected'}
              </p>
            </div>
          </div>
        </Card>

        <Card>
          <div>
            <p className="text-sm text-gray-600">Total Transactions (24h)</p>
            <p className="text-2xl font-bold text-primary-400">
              {stats.reduce((sum, s) => sum + s.transaction_count, 0)}
            </p>
          </div>
        </Card>

        <Card>
          <div>
            <p className="text-sm text-gray-600">Total Volume (24h)</p>
            <p className="text-2xl font-bold text-green-600">
              ${stats.reduce((sum, s) => sum + (s.successful_volume_usd || 0), 0).toFixed(2)}
            </p>
          </div>
        </Card>
      </div>

      {/* Filters */}
      <Card>
        <div className="flex items-center space-x-4">
          <button
            onClick={() => setFilter('all')}
            className={`px-4 py-2 rounded-lg font-semibold ${
              filter === 'all'
                ? 'bg-primary-400 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
            }`}
          >
            All ({transactions.length})
          </button>
          <button
            onClick={() => setFilter('sui')}
            className={`px-4 py-2 rounded-lg font-semibold ${
              filter === 'sui'
                ? 'bg-primary-400 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
            }`}
          >
            Sui ({transactions.filter((t) => t.platform === 'sui').length})
          </button>
          <button
            onClick={() => setFilter('stripe')}
            className={`px-4 py-2 rounded-lg font-semibold ${
              filter === 'stripe'
                ? 'bg-primary-400 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
            }`}
          >
            Stripe ({transactions.filter((t) => t.platform === 'stripe').length})
          </button>
        </div>
      </Card>

      {/* Transaction feed */}
      <Card>
        <div className="mb-4">
          <h3 className="text-lg font-semibold">Live Transaction Feed</h3>
          <p className="text-sm text-gray-600">Real-time updates from blockchain and payment processor</p>
        </div>

        <div className="space-y-3 max-h-[600px] overflow-y-auto">
          {filteredTransactions.length === 0 ? (
            <div className="text-center py-12 text-gray-500">
              <div className="text-4xl mb-2 font-bold text-gray-400">💰</div>
              <p>No transactions yet</p>
              <p className="text-sm mt-1">Transactions will appear here in real-time</p>
            </div>
          ) : (
            filteredTransactions.map((tx, index) => (
              <div
                key={`${tx.platform}-${tx.transaction_id}-${index}`}
                className="border border-gray-200 rounded-lg p-4 hover:bg-gray-50 transition-colors"
              >
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center space-x-3 mb-2">
                      <span className="text-2xl">{getPlatformIcon(tx.platform)}</span>
                      <div>
                        <p className="font-semibold text-gray-900">{tx.description}</p>
                        <p className="text-xs text-gray-500 font-mono">
                          {tx.transaction_id.substring(0, 20)}...
                        </p>
                      </div>
                    </div>

                    <div className="grid grid-cols-2 gap-3 text-sm mt-3">
                      {tx.platform === 'sui' && (
                        <>
                          <div>
                            <span className="text-gray-600">From:</span>{' '}
                            <span className="font-mono text-xs">
                              {tx.sender?.substring(0, 10)}...
                            </span>
                          </div>
                          {tx.recipient && (
                            <div>
                              <span className="text-gray-600">To:</span>{' '}
                              <span className="font-mono text-xs">
                                {tx.recipient.substring(0, 10)}...
                              </span>
                            </div>
                          )}
                          {tx.amount_apt && (
                            <div>
                              <span className="text-gray-600">Amount:</span>{' '}
                              <span className="font-semibold">{tx.amount_apt.toFixed(4)} APT</span>
                            </div>
                          )}
                          {tx.gas_used && (
                            <div>
                              <span className="text-gray-600">Gas:</span>{' '}
                              <span className="text-xs">{tx.gas_used} units</span>
                            </div>
                          )}
                        </>
                      )}

                      {tx.platform === 'stripe' && (
                        <>
                          {tx.student_email && (
                            <div>
                              <span className="text-gray-600">Student:</span>{' '}
                              <span className="text-xs">{tx.student_email}</span>
                            </div>
                          )}
                          {tx.barber_email && (
                            <div>
                              <span className="text-gray-600">Barber:</span>{' '}
                              <span className="text-xs">{tx.barber_email}</span>
                            </div>
                          )}
                          {tx.booking_id && (
                            <div>
                              <span className="text-gray-600">Booking:</span>{' '}
                              <span className="font-mono text-xs">{tx.booking_id}</span>
                            </div>
                          )}
                        </>
                      )}

                      {tx.amount_usd && (
                        <div>
                          <span className="text-gray-600">Value:</span>{' '}
                          <span className="font-semibold text-green-600">
                            ${tx.amount_usd.toFixed(2)}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>

                  <div className="flex flex-col items-end space-y-2">
                    {getStatusBadge(tx)}
                    <span className="text-xs text-gray-500">{formatTimestamp(tx.timestamp)}</span>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      </Card>
    </div>
  );
}

