/**
 * System Health Dashboard Component
 * 
 * Visual dashboard showing:
 * - PostgreSQL database status
 * - API server status
 * - Service connectivity (Stripe, Email)
 * - System metrics (memory, uptime, connections)
 */

import React, { useEffect, useState } from 'react';
import axios from 'axios';
import { 
  Database, 
  Server, 
  CreditCard, 
  Mail, 
  Activity,
  CheckCircle,
  XCircle,
  AlertTriangle,
  RefreshCw,
  Clock,
  HardDrive,
  Zap
} from 'lucide-react';

interface ServiceStatus {
  name: string;
  status: 'operational' | 'degraded' | 'down' | 'not_configured';
  responseTime?: number;
  message?: string;
  lastChecked: string;
  details?: any;
}

interface SystemHealth {
  status: 'operational' | 'degraded' | 'error';
  services: {
    database: ServiceStatus;
    api: ServiceStatus;
    stripe: ServiceStatus;
    email: ServiceStatus;
  };
  metrics: {
    uptime: number;
    memoryUsage: {
      used: number;
      total: number;
      percentage: number;
    };
    activeConnections: number;
    nodeVersion: string;
    environment: string;
  };
  timestamp: string;
}

// Fallback health data when API is unavailable
const FALLBACK_HEALTH: SystemHealth = {
  status: 'degraded',
  services: {
    database: {
      name: 'PostgreSQL',
      status: 'not_configured',
      message: 'Unable to connect',
      lastChecked: new Date().toISOString(),
    },
    api: {
      name: 'API Server',
      status: 'not_configured',
      message: 'Unable to connect',
      lastChecked: new Date().toISOString(),
    },
    stripe: {
      name: 'Stripe Payments',
      status: 'not_configured',
      message: 'Status unknown',
      lastChecked: new Date().toISOString(),
    },
    email: {
      name: 'Email Service',
      status: 'not_configured',
      message: 'Status unknown',
      lastChecked: new Date().toISOString(),
    },
  },
  metrics: {
    uptime: 0,
    memoryUsage: { used: 0, total: 0, percentage: 0 },
    activeConnections: 0,
    nodeVersion: 'unknown',
    environment: 'unknown',
  },
  timestamp: new Date().toISOString(),
};

export const SystemModeMeter: React.FC = () => {
  const [health, setHealth] = useState<SystemHealth | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchHealth();
    const interval = setInterval(fetchHealth, 30000); // Refresh every 30s
    return () => clearInterval(interval);
  }, []);

  const fetchHealth = async () => {
    try {
      setRefreshing(true);
      const response = await axios.get('http://localhost:3001/api/system/health');
      if (response.data && response.data.services) {
        setHealth(response.data);
        setError(null);
      } else {
        console.warn('Invalid health response, using fallback data');
        setHealth(FALLBACK_HEALTH);
      }
    } catch (err) {
      console.error('Failed to fetch system health:', err);
      setError('Unable to connect to backend');
      setHealth(FALLBACK_HEALTH);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const formatUptime = (seconds: number) => {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${minutes}m`;
    return `${minutes}m`;
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'operational':
        return <CheckCircle className="w-5 h-5 text-green-500" />;
      case 'degraded':
        return <AlertTriangle className="w-5 h-5 text-yellow-500" />;
      case 'down':
        return <XCircle className="w-5 h-5 text-red-500" />;
      case 'not_configured':
        return <AlertTriangle className="w-5 h-5 text-gray-400" />;
      default:
        return <AlertTriangle className="w-5 h-5 text-gray-400" />;
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'operational':
        return 'bg-green-100 text-green-800 border-green-200';
      case 'degraded':
        return 'bg-yellow-100 text-yellow-800 border-yellow-200';
      case 'down':
        return 'bg-red-100 text-red-800 border-red-200';
      case 'not_configured':
        return 'bg-gray-100 text-gray-600 border-gray-200';
      default:
        return 'bg-gray-100 text-gray-600 border-gray-200';
    }
  };

  const getServiceIcon = (serviceName: string) => {
    switch (serviceName.toLowerCase()) {
      case 'postgresql':
        return <Database className="w-5 h-5" />;
      case 'api server':
        return <Server className="w-5 h-5" />;
      case 'stripe payments':
        return <CreditCard className="w-5 h-5" />;
      case 'email service':
        return <Mail className="w-5 h-5" />;
      default:
        return <Activity className="w-5 h-5" />;
    }
  };

  if (loading) {
    return (
      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-center">
          <RefreshCw className="w-6 h-6 text-primary-500 animate-spin mr-2" />
          <span className="text-gray-600">Loading system status...</span>
        </div>
      </div>
    );
  }

  if (!health) {
    return (
      <div className="bg-white rounded-lg shadow p-6">
        <div className="text-center text-red-600">
          <XCircle className="w-8 h-8 mx-auto mb-2" />
          Unable to load system health
        </div>
      </div>
    );
  }

  const overallHealthy = health.status === 'operational';

  return (
    <div className="space-y-6">
      {/* Error Banner */}
      {error && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 flex items-start gap-3">
          <AlertTriangle className="w-5 h-5 text-yellow-600 mt-0.5" />
          <div>
            <p className="font-medium text-yellow-800">{error}</p>
            <p className="text-sm text-yellow-700">Showing cached/mock data. Check if backend is running.</p>
          </div>
        </div>
      )}

      {/* Services Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {Object.entries(health.services).map(([key, service]) => (
          <div 
            key={key}
            className="bg-white rounded-lg shadow p-5 border-l-4"
            style={{ 
              borderLeftColor: service.status === 'operational' ? '#22c55e' : 
                              service.status === 'degraded' ? '#eab308' :
                              service.status === 'down' ? '#ef4444' : '#9ca3af'
            }}
          >
            <div className="flex items-start justify-between mb-3">
              <div className="flex items-center gap-3">
                <div className={`p-2 rounded-lg ${
                  service.status === 'operational' ? 'bg-green-100 text-green-600' :
                  service.status === 'degraded' ? 'bg-yellow-100 text-yellow-600' :
                  service.status === 'down' ? 'bg-red-100 text-red-600' :
                  'bg-gray-100 text-gray-500'
                }`}>
                  {getServiceIcon(service.name)}
                </div>
                <div>
                  <h4 className="font-semibold text-gray-900">{service.name}</h4>
                  <p className="text-sm text-gray-500">{service.message}</p>
                </div>
              </div>
              {getStatusIcon(service.status)}
            </div>

            <div className="flex items-center justify-between">
              <span className={`text-xs px-2 py-1 rounded-full border ${getStatusBadge(service.status)}`}>
                {service.status === 'not_configured' ? 'Not Configured' : service.status.charAt(0).toUpperCase() + service.status.slice(1)}
              </span>
              {service.responseTime !== undefined && (
                <span className="text-xs text-gray-500 flex items-center gap-1">
                  <Zap className="w-3 h-3" />
                  {service.responseTime}ms
                </span>
              )}
            </div>

            {/* Pool Details for Database */}
            {service.details?.pool && (
              <div className="mt-3 pt-3 border-t border-gray-100">
                <div className="flex justify-between text-xs text-gray-600">
                  <span>Connection Pool</span>
                  <span>{service.details.pool.total - service.details.pool.idle} active / {service.details.pool.total} total</span>
                </div>
                <div className="mt-1 h-2 bg-gray-100 rounded-full overflow-hidden">
                  <div 
                    className="h-full bg-green-500 rounded-full transition-all"
                    style={{ 
                      width: `${((service.details.pool.total - service.details.pool.idle) / service.details.pool.total) * 100}%` 
                    }}
                  />
                </div>
              </div>
            )}
          </div>
        ))}
      </div>

      </div>
  );
};

export default SystemModeMeter;
