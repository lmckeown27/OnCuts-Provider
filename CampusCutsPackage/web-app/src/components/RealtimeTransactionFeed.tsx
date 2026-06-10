/**
 * Real-Time Transaction Feed
 * 
 * Shows live transactions for a specific campus
 * Styled to match the Admin Payments page transactions view
 */

import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { CheckCircle, Clock, XCircle, RefreshCw, ChevronDown, ChevronUp, ChevronLeft, ChevronRight, Calendar, Scissors, User } from 'lucide-react';

interface Transaction {
  id: string;
  type: 'payment' | 'payout' | 'refund' | 'fee';
  timestamp: string;
  amount: number;
  serviceName: string;
  barberName: string;
  barberId: string;
  customerName: string;
  customerId: string;
  status: 'pending' | 'completed' | 'processing' | 'failed';
  campus: string;
  stripeId?: string;
}

interface RealtimeTransactionFeedProps {
  campusId?: string;
  maxItems?: number;
}

// TODO: Fetch transactions from API
// For now, returns empty array - will be populated by real data
const fetchTransactions = async (_campusId?: string): Promise<Transaction[]> => {
  // TODO: Replace with actual API call
  // const response = await transactionService.getTransactions(campusId);
  // return response.data;
  return [];
};

// Time filter options
const TIME_OPTIONS = [
  { value: 'today', label: 'Today' },
  { value: '7days', label: 'Last 7 days' },
  { value: '30days', label: 'Last 30 days' },
  { value: 'all', label: 'All time' },
];

// Service filter options
const SERVICE_OPTIONS = [
  { value: 'all', label: 'All Services' },
  { value: 'Fade', label: 'Fade' },
  { value: 'Haircut', label: 'Haircut' },
  { value: 'Taper', label: 'Taper' },
  { value: 'Beard Trim', label: 'Beard Trim' },
  { value: 'Line Up', label: 'Line Up' },
  { value: 'Haircut & Fade', label: 'Haircut & Fade' },
  { value: 'Buzz Cut', label: 'Buzz Cut' },
  { value: 'Color Treatment', label: 'Color Treatment' },
];

// Barber filter options
const BARBER_OPTIONS = [
  { value: 'all', label: 'All Barbers' },
  { value: 'Marcus T.', label: 'Marcus T.' },
  { value: 'Alex C.', label: 'Alex C.' },
  { value: 'Jordan W.', label: 'Jordan W.' },
  { value: 'Tyler M.', label: 'Tyler M.' },
  { value: 'Carlos R.', label: 'Carlos R.' },
];

export const RealtimeTransactionFeed: React.FC<RealtimeTransactionFeedProps> = ({
  campusId,
  maxItems = 20,
}) => {
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [expandedTransaction, setExpandedTransaction] = useState<string | null>(null);
  const [currentPage, setCurrentPage] = useState(1);
  const [timeFilter, setTimeFilter] = useState('all');
  const [serviceFilter, setServiceFilter] = useState('all');
  const [barberFilter, setBarberFilter] = useState('all');
  const [showTimeDropdown, setShowTimeDropdown] = useState(false);
  const [showServiceDropdown, setShowServiceDropdown] = useState(false);
  const [showBarberDropdown, setShowBarberDropdown] = useState(false);
  const itemsPerPage = 7;

  useEffect(() => {
    // Load transactions from API
    const loadTransactions = async () => {
      const data = await fetchTransactions(campusId);
      setTransactions(data);
    };
    loadTransactions();
  }, [campusId]);

  // Filter transactions by time and service
  const filteredTransactions = transactions.filter(tx => {
    // Time filter
    if (timeFilter !== 'all') {
      const txDate = new Date(tx.timestamp);
      const now = new Date();
      if (timeFilter === 'today') {
        if (txDate.toDateString() !== now.toDateString()) return false;
      }
      if (timeFilter === '7days') {
        const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
        if (txDate < weekAgo) return false;
      }
      if (timeFilter === '30days') {
        const monthAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
        if (txDate < monthAgo) return false;
      }
    }
    
    // Service filter
    if (serviceFilter !== 'all') {
      if (tx.serviceName !== serviceFilter) return false;
    }
    
    // Barber filter
    if (barberFilter !== 'all') {
      if (tx.barberName !== barberFilter) return false;
    }
    
    return true;
  });

  const getServiceFilterLabel = () => {
    return SERVICE_OPTIONS.find(o => o.value === serviceFilter)?.label || 'All Services';
  };

  const getBarberFilterLabel = () => {
    return BARBER_OPTIONS.find(o => o.value === barberFilter)?.label || 'All Barbers';
  };

  // Pagination
  const totalPages = Math.ceil(filteredTransactions.length / itemsPerPage);
  const startIndex = (currentPage - 1) * itemsPerPage;
  const paginatedTransactions = filteredTransactions.slice(startIndex, startIndex + itemsPerPage);

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);

    if (diffMins < 60) return `${diffMins} min ago`;
    if (diffHours < 24) return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
    return date.toLocaleDateString();
  };

  const getStatusIcon = (status: Transaction['status']) => {
    switch (status) {
      case 'completed':
        return (
          <div className="flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center bg-green-100 text-green-700">
            <CheckCircle className="w-4 h-4" />
          </div>
        );
      case 'pending':
        return (
          <div className="flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center bg-yellow-100 text-yellow-700">
            <Clock className="w-4 h-4" />
          </div>
        );
      case 'processing':
        return (
          <div className="flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center bg-blue-100 text-blue-700">
            <RefreshCw className="w-4 h-4 animate-spin" />
          </div>
        );
      case 'failed':
        return (
          <div className="flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center bg-red-100 text-red-700">
            <XCircle className="w-4 h-4" />
          </div>
        );
    }
  };

  const getTimeFilterLabel = () => {
    return TIME_OPTIONS.find(o => o.value === timeFilter)?.label || 'All time';
  };

  const PaginationControls = () => (
    <div className="flex items-center justify-between py-3">
      <p className="text-sm text-gray-600">
        Showing {startIndex + 1}-{Math.min(startIndex + itemsPerPage, filteredTransactions.length)} of {filteredTransactions.length}
      </p>
      <div className="flex items-center gap-2">
        <button
          onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
          disabled={currentPage === 1}
          className="p-2 rounded-lg border border-gray-300 hover:bg-gray-100 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          <ChevronLeft className="w-4 h-4" />
        </button>
        <div className="flex items-center gap-1">
          {Array.from({ length: Math.min(4, totalPages) }, (_, i) => i + 1).map(page => (
            <button
              key={page}
              onClick={() => setCurrentPage(page)}
              className={`w-8 h-8 rounded-lg text-sm font-medium transition-colors ${
                currentPage === page
                  ? 'bg-primary-500 text-white'
                  : 'hover:bg-gray-100 text-gray-700'
              }`}
            >
              {page}
            </button>
          ))}
        </div>
        <button
          onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
          disabled={currentPage === totalPages}
          className="p-2 rounded-lg border border-gray-300 hover:bg-gray-100 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          <ChevronRight className="w-4 h-4" />
        </button>
      </div>
    </div>
  );

  return (
    <div className="card">
      {/* Header */}
      <h3 className="text-lg font-bold text-gray-900 text-center mb-4">Transactions</h3>
      
      {/* Filters */}
      <div className="flex flex-row items-center justify-between sm:justify-center gap-2 sm:gap-3 mb-4">
        {/* Time Filter */}
        <div className="relative">
          <button
            onClick={() => {
              setShowTimeDropdown(!showTimeDropdown);
              setShowServiceDropdown(false);
              setShowBarberDropdown(false);
            }}
            className="flex items-center gap-2 px-3 py-2 border border-gray-300 rounded-lg text-sm hover:bg-gray-50 transition-colors"
          >
            <Calendar className="w-4 h-4 text-gray-500" />
            <span>{getTimeFilterLabel()}</span>
            <ChevronDown className={`w-4 h-4 text-gray-400 transition-transform ${showTimeDropdown ? 'rotate-180' : ''}`} />
          </button>
          
          {showTimeDropdown && (
            <div className="absolute top-full left-0 mt-2 min-w-full bg-white rounded-lg shadow-lg border border-gray-200 py-2 z-50">
              {TIME_OPTIONS.map(option => (
                <button
                  key={option.value}
                  onClick={() => {
                    setTimeFilter(option.value);
                    setShowTimeDropdown(false);
                    setCurrentPage(1);
                  }}
                  className={`w-full px-3 py-2 text-left text-sm hover:bg-gray-100 ${
                    timeFilter === option.value ? 'text-primary-600 font-medium' : 'text-gray-700'
                  }`}
                >
                  {option.label}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Service Filter */}
        <div className="relative">
          <button
            onClick={() => {
              setShowServiceDropdown(!showServiceDropdown);
              setShowTimeDropdown(false);
              setShowBarberDropdown(false);
            }}
            className="flex items-center gap-2 px-3 py-2 border border-gray-300 rounded-lg text-sm hover:bg-gray-50 transition-colors"
          >
            <Scissors className="w-4 h-4 text-gray-500" />
            <span>{getServiceFilterLabel()}</span>
            <ChevronDown className={`w-4 h-4 text-gray-400 transition-transform ${showServiceDropdown ? 'rotate-180' : ''}`} />
          </button>
          
          {showServiceDropdown && (
            <div className="absolute top-full left-0 mt-2 min-w-full bg-white rounded-lg shadow-lg border border-gray-200 py-2 z-50">
              {SERVICE_OPTIONS.map(option => (
                <button
                  key={option.value}
                  onClick={() => {
                    setServiceFilter(option.value);
                    setShowServiceDropdown(false);
                    setCurrentPage(1);
                  }}
                  className={`w-full px-3 py-2 text-left text-sm hover:bg-gray-100 ${
                    serviceFilter === option.value ? 'text-primary-600 font-medium' : 'text-gray-700'
                  }`}
                >
                  {option.label}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Barber Filter */}
        <div className="relative">
          <button
            onClick={() => {
              setShowBarberDropdown(!showBarberDropdown);
              setShowTimeDropdown(false);
              setShowServiceDropdown(false);
            }}
            className="flex items-center gap-2 px-3 py-2 border border-gray-300 rounded-lg text-sm hover:bg-gray-50 transition-colors"
          >
            <User className="w-4 h-4 text-gray-500" />
            <span>{getBarberFilterLabel()}</span>
            <ChevronDown className={`w-4 h-4 text-gray-400 transition-transform ${showBarberDropdown ? 'rotate-180' : ''}`} />
          </button>
          
          {showBarberDropdown && (
            <div className="absolute top-full left-0 mt-2 min-w-full bg-white rounded-lg shadow-lg border border-gray-200 py-2 z-50">
              {BARBER_OPTIONS.map(option => (
                <button
                  key={option.value}
                  onClick={() => {
                    setBarberFilter(option.value);
                    setShowBarberDropdown(false);
                    setCurrentPage(1);
                  }}
                  className={`w-full px-3 py-2 text-left text-sm hover:bg-gray-100 ${
                    barberFilter === option.value ? 'text-primary-600 font-medium' : 'text-gray-700'
                  }`}
                >
                  {option.label}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Pagination Top */}
      {filteredTransactions.length > 0 && <PaginationControls />}

      {/* Transaction List */}
      {filteredTransactions.length === 0 ? (
        <div className="text-center py-12 text-gray-500">
          <Scissors className="w-12 h-12 mx-auto mb-3 text-gray-300" />
          <p className="font-medium">No transactions found</p>
          <p className="text-sm mt-1">Try adjusting your filters</p>
        </div>
      ) : (
        <div className="space-y-3">
          {paginatedTransactions.map((tx) => (
            <div
              key={tx.id}
              className="border border-gray-200 rounded-lg overflow-hidden bg-white hover:border-gray-300 transition-colors"
            >
              <button
                onClick={() => setExpandedTransaction(expandedTransaction === tx.id ? null : tx.id)}
                className="w-full px-4 py-3 flex items-center justify-between gap-3 text-left hover:bg-gray-50 transition-colors"
              >
                <div className="flex items-center gap-3 min-w-0 flex-1">
                  {getStatusIcon(tx.status)}
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-gray-900 truncate">{tx.serviceName}</span>
                      <span className="text-xs text-gray-600">• {tx.barberName}</span>
                    </div>
                    <div className="text-xs text-gray-500">{formatTimestamp(tx.timestamp)}</div>
                  </div>
                </div>
                <div className="flex items-center gap-2 flex-shrink-0">
                  <span className={`font-semibold ${tx.amount < 0 ? 'text-red-600' : 'text-gray-900'}`}>
                    ${Math.abs(tx.amount).toFixed(2)}
                  </span>
                  {expandedTransaction === tx.id ? (
                    <ChevronUp className="w-5 h-5 text-gray-400" />
                  ) : (
                    <ChevronDown className="w-5 h-5 text-gray-400" />
                  )}
                </div>
              </button>

              {/* Expanded Details */}
              {expandedTransaction === tx.id && (
                <div className="px-4 py-3 bg-gray-50 border-t border-gray-200">
                  <div className="grid grid-cols-2 gap-4 text-sm">
                    <div>
                      <p className="text-gray-500">Customer</p>
                      <Link
                        to={`/admin/user/${tx.customerId}`}
                        className="font-medium text-primary-600 hover:underline"
                      >
                        {tx.customerName}
                      </Link>
                    </div>
                    <div>
                      <p className="text-gray-500">Barber</p>
                      <Link
                        to={`/admin/user/${tx.barberId}`}
                        className="font-medium text-primary-600 hover:underline"
                      >
                        {tx.barberName}
                      </Link>
                    </div>
                    <div>
                      <p className="text-gray-500">Type</p>
                      <p className="font-medium capitalize">{tx.type}</p>
                    </div>
                    <div>
                      <p className="text-gray-500">Status</p>
                      <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${
                        tx.status === 'completed' ? 'bg-green-100 text-green-700' :
                        tx.status === 'pending' ? 'bg-yellow-100 text-yellow-700' :
                        tx.status === 'processing' ? 'bg-blue-100 text-blue-700' :
                        'bg-red-100 text-red-700'
                      }`}>
                        {tx.status}
                      </span>
                    </div>
                    {tx.stripeId && (
                      <div className="col-span-2">
                        <p className="text-gray-500">Stripe ID</p>
                        <p className="font-mono text-xs text-gray-600">{tx.stripeId}</p>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Pagination Bottom */}
      {filteredTransactions.length > 0 && <PaginationControls />}
    </div>
  );
};

export default RealtimeTransactionFeed;
