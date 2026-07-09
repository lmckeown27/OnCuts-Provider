/**
 * Wallet Page
 * 
 * Complete wallet management with V2 features:
 * - Balance display (available/pending)
 * - Active escrows
 * - Transaction history
 * - Withdrawal options
 */

import React, { useState, useEffect } from 'react';
import { ArrowUpRight, ArrowDownLeft, Clock, CheckCircle2, X } from 'lucide-react';
import BalanceDisplay from '../components/BalanceDisplay';
import EscrowStatusBadge from '../components/EscrowStatusBadge';
import Button from '../components/Button';
import Card from '../components/Card';
import Loading from '../components/Loading';
import walletV2Service from '../services/wallet-v2.service';
import toast from 'react-hot-toast';
import type { WalletBalance, Transaction, Escrow } from '../services/wallet-v2.service';

const WalletPage: React.FC = () => {
  const [balance, setBalance] = useState<WalletBalance | null>(null);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [escrows, setEscrows] = useState<Escrow[]>([]);
  const [activeTab, setActiveTab] = useState<'overview' | 'transactions' | 'escrows'>('overview');
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    loadWalletData();
  }, []);

  const loadWalletData = async () => {
    try {
      setIsLoading(true);
      const [balanceData, transactionsData, escrowsData] = await Promise.all([
        walletV2Service.getBalance(),
        walletV2Service.getTransactionHistory(20),
        walletV2Service.getEscrows(),
      ]);

      setBalance(balanceData);
      setTransactions(transactionsData.transactions);
      setEscrows(escrowsData);
    } catch (error) {
      toast.error('Failed to load wallet data');
    } finally {
      setIsLoading(false);
    }
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMs / 3600000);
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    
    return date.toLocaleDateString();
  };

  const getTransactionIcon = (type: string) => {
    if (type.includes('deposit') || type.includes('charge') || type.includes('credit')) {
      return <ArrowDownLeft className="h-5 w-5 text-green-600" />;
    }
    return <ArrowUpRight className="h-5 w-5 text-red-600" />;
  };

  const getTransactionColor = (type: string) => {
    if (type.includes('deposit') || type.includes('charge') || type.includes('credit')) {
      return 'text-green-600';
    }
    return 'text-red-600';
  };

  if (isLoading || !balance) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <Loading />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 py-8">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-gray-900">Wallet</h1>
          <p className="text-gray-600 mt-2">
            Manage your funds, view transactions, and track escrows
          </p>
        </div>

        {/* Tabs */}
        <div className="mb-6 border-b border-gray-200">
          <nav className="-mb-px flex space-x-8">
            {[
              { key: 'overview', label: 'Overview' },
              { key: 'transactions', label: 'Transactions', count: transactions.length },
              { key: 'escrows', label: 'Active Holds', count: escrows.filter(e => e.status === 'held').length },
            ].map((tab) => (
              <button
                key={tab.key}
                onClick={() => setActiveTab(tab.key as any)}
                className={`
                  py-4 px-1 border-b-2 font-medium text-sm
                  ${activeTab === tab.key
                    ? 'border-primary-400 text-primary-400'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                  }
                `}
              >
                {tab.label}
                {tab.count !== undefined && tab.count > 0 && (
                  <span className="ml-2 py-0.5 px-2 rounded-full bg-gray-100 text-xs">
                    {tab.count}
                  </span>
                )}
              </button>
            ))}
          </nav>
        </div>

        {/* Overview Tab */}
        {activeTab === 'overview' && (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2">
              <BalanceDisplay balance={balance} showDetails />
              
              {/* Recent Transactions */}
              <Card className="mt-6">
                <h3 className="text-lg font-semibold mb-4">Recent Transactions</h3>
                <div className="space-y-3">
                  {transactions.slice(0, 5).map((tx) => (
                    <div key={tx.id} className="flex items-center justify-between py-3 border-b border-gray-100 last:border-0">
                      <div className="flex items-center">
                        <div className="p-2 bg-gray-100 rounded-full mr-3">
                          {getTransactionIcon(tx.type)}
                        </div>
                        <div>
                          <div className="font-medium text-gray-900">{tx.type.replace(/_/g, ' ')}</div>
                          <div className="text-sm text-gray-500">{formatDate(tx.created_at)}</div>
                        </div>
                      </div>
                      <div className={`font-semibold ${getTransactionColor(tx.type)}`}>
                        {tx.amount_dollars > 0 ? '+' : ''}\${Math.abs(tx.amount_dollars).toFixed(2)}
                      </div>
                    </div>
                  ))}
                </div>
                <Button
                  onClick={() => setActiveTab('transactions')}
                  variant="secondary"
                  className="w-full mt-4"
                >
                  View All Transactions
                </Button>
              </Card>
            </div>

            <div>
              {/* Quick Actions */}
              <Card className="mb-6">
                <h3 className="text-lg font-semibold mb-4">Quick Actions</h3>
                <div className="space-y-3">
                  <Button
                    onClick={() => setActiveTab('transactions')}
                    variant="primary"
                    className="w-full"
                  >
                    View all transactions
                  </Button>
                  <Button
                    onClick={() => setActiveTab('escrows')}
                    variant="secondary"
                    className="w-full"
                  >
                    View Escrows ({escrows.filter(e => e.status === 'held').length})
                  </Button>
                </div>
              </Card>

              {/* Active Escrows Summary */}
              {escrows.filter(e => e.status === 'held').length > 0 && (
                <Card>
                  <h3 className="text-lg font-semibold mb-4">Active Holds</h3>
                  <div className="space-y-3">
                    {escrows.filter(e => e.status === 'held').slice(0, 3).map((escrow) => (
                      <div key={escrow.id} className="p-3 bg-gray-50 rounded-lg">
                        <EscrowStatusBadge status={escrow.status} expiresAt={escrow.expires_at} />
                        <div className="mt-2 text-sm text-gray-600">
                          Amount: ${escrow.amount_dollars.toFixed(2)}
                        </div>
                      </div>
                    ))}
                  </div>
                </Card>
              )}
            </div>
          </div>
        )}

        {/* Transactions Tab */}
        {activeTab === 'transactions' && (
          <Card>
            <h3 className="text-lg font-semibold mb-4">Transaction History</h3>
            <div className="space-y-3">
              {transactions.map((tx) => (
                <div key={tx.id} className="flex items-center justify-between py-4 border-b border-gray-100 last:border-0">
                  <div className="flex items-center flex-1">
                    <div className="p-2 bg-gray-100 rounded-full mr-4">
                      {getTransactionIcon(tx.type)}
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center">
                        <div className="font-medium text-gray-900">{tx.type.replace(/_/g, ' ')}</div>
                        <span className={`ml-2 px-2 py-0.5 rounded text-xs font-medium ${
                          tx.status === 'completed' ? 'bg-green-100 text-green-800' :
                          tx.status === 'pending' ? 'bg-yellow-100 text-yellow-800' :
                          'bg-gray-100 text-gray-800'
                        }`}>
                          {tx.status}
                        </span>
                      </div>
                      <div className="text-sm text-gray-500 mt-1">
                        {formatDate(tx.created_at)} • {tx.tx_ref}
                      </div>
                    </div>
                  </div>
                  <div className={`font-semibold text-lg ${getTransactionColor(tx.type)}`}>
                    {tx.amount_dollars > 0 ? '+' : ''}\${Math.abs(tx.amount_dollars).toFixed(2)}
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}

        {/* Escrows Tab */}
        {activeTab === 'escrows' && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {escrows.map((escrow) => (
              <Card key={escrow.id}>
                <div className="flex items-start justify-between mb-4">
                  <div>
                    <h3 className="text-lg font-semibold text-gray-900">
                      ${escrow.amount_dollars.toFixed(2)}
                    </h3>
                    <p className="text-sm text-gray-500 mt-1">
                      Booking ID: {escrow.booking_id.substring(0, 8)}...
                    </p>
                  </div>
                  <EscrowStatusBadge status={escrow.status} expiresAt={escrow.expires_at} />
                </div>

                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-gray-600">Created:</span>
                    <span className="text-gray-900">{new Date(escrow.created_at).toLocaleString()}</span>
                  </div>
                  {escrow.status === 'held' && (
                    <div className="flex justify-between">
                      <span className="text-gray-600">Expires:</span>
                      <span className="text-gray-900">{new Date(escrow.expires_at).toLocaleString()}</span>
                    </div>
                  )}
                  {escrow.released_at && (
                    <div className="flex justify-between">
                      <span className="text-gray-600">Released:</span>
                      <span className="text-gray-900">{new Date(escrow.released_at).toLocaleString()}</span>
                    </div>
                  )}
                  {escrow.refunded_at && (
                    <div className="flex justify-between">
                      <span className="text-gray-600">Refunded:</span>
                      <span className="text-gray-900">{new Date(escrow.refunded_at).toLocaleString()}</span>
                    </div>
                  )}
                </div>
              </Card>
            ))}

            {escrows.length === 0 && (
              <div className="col-span-2 text-center py-12">
                <Clock className="h-12 w-12 text-gray-400 mx-auto mb-4" />
                <h3 className="text-lg font-medium text-gray-900 mb-2">No Escrows</h3>
                <p className="text-gray-600">
                  You don't have any escrow holds at the moment.
                </p>
              </div>
            )}
          </div>
        )}

      </div>
    </div>
  );
};

export default WalletPage;

