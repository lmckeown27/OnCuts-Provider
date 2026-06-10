import { useState, useEffect } from 'react';
import { TrendingUp, TrendingDown, ChevronRight, ChevronDown } from 'lucide-react';
import Card from './Card';
import Loading from './Loading';
import barberService from '../services/barber.service';

type BarberPricingDashboardProps = {
  barberId: string;
};

type PriceData = {
  serviceId: number;
  serviceName: string;
  currentPrice: number;
  previousPrice: number;
  priceChange: number;
  priceChangePct: number;
};

type PerformanceData = {
  totalBookings: number;
  totalRevenue: number;
  avgRating: number;
  totalReviews: number;
};

export default function BarberPricingDashboard({ barberId }: BarberPricingDashboardProps) {
  const [isLoading, setIsLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'performance' | 'pricing'>('performance');
  const [expandedSection, setExpandedSection] = useState<string | null>(null);
  const [performanceData, setPerformanceData] = useState<PerformanceData | null>(null);
  const [prices, setPrices] = useState<PriceData[]>([]);
  const [revenueHistory, setRevenueHistory] = useState<any[]>([]);

  useEffect(() => {
    loadPricingData();
  }, [barberId]);

  const loadPricingData = async () => {
    setIsLoading(true);

    try {
      // Fetch real barber data from API
      const barberData = await barberService.getBarberByUserId(barberId);
      
      if (barberData) {
        // Use real data from barber profile
        setPerformanceData({
          totalBookings: barberData.total_bookings || 0,
          totalRevenue: 0, // Revenue tracking not yet implemented
          avgRating: barberData.average_rating || 0,
          totalReviews: barberData.total_reviews || 0,
        });

        // Convert barber services to pricing data
        const servicePrices: PriceData[] = (barberData.pricing || []).map((service: any, idx: number) => ({
          serviceId: idx + 1,
          serviceName: service.name,
          currentPrice: service.price,
          previousPrice: service.price, // No historical data yet
          priceChange: 0,
          priceChangePct: 0,
        }));

        setPrices(servicePrices);
        setRevenueHistory([]); // Revenue history not yet implemented
      } else {
        // No barber data - show empty state
        setPerformanceData({
          totalBookings: 0,
          totalRevenue: 0,
          avgRating: 0,
          totalReviews: 0,
        });
        setPrices([]);
        setRevenueHistory([]);
      }
    } catch (error) {
      console.error('Failed to load pricing data:', error);
      // Show empty state on error
      setPerformanceData({
        totalBookings: 0,
        totalRevenue: 0,
        avgRating: 0,
        totalReviews: 0,
      });
      setPrices([]);
      setRevenueHistory([]);
    } finally {
      setIsLoading(false);
    }
  };

  const toggleSection = (section: string) => {
    setExpandedSection(expandedSection === section ? null : section);
  };

  if (isLoading) {
    return (
      <div className="flex justify-center items-center min-h-[400px]">
        <Loading />
      </div>
    );
  }

  if (!performanceData) {
    return (
      <Card>
        <p className="text-center text-gray-600 py-8">No performance data available</p>
      </Card>
    );
  }

  // Calculate summary stats from history
  const totalRevenue30Day = revenueHistory.reduce((sum, h) => sum + h.revenue, 0);
  const totalBookings30Day = revenueHistory.reduce((sum, h) => sum + h.bookings, 0);
  const avgDailyRevenue = totalRevenue30Day / revenueHistory.length;
  const avgDailyBookings = totalBookings30Day / revenueHistory.length;

  // Mock review data
  const recentReviews = [
    { name: 'Alex R.', rating: 5, comment: 'Great fade, very professional!', date: 'Dec 22', service: 'Fade' },
    { name: 'Jordan L.', rating: 5, comment: 'Best haircut I\'ve had on campus.', date: 'Dec 20', service: 'Haircut' },
    { name: 'Sam M.', rating: 4, comment: 'Good work, bit of a wait though.', date: 'Dec 18', service: 'Haircut & Fade' },
    { name: 'Chris T.', rating: 5, comment: 'Super clean lineup!', date: 'Dec 16', service: 'Lineup' },
    { name: 'Mike P.', rating: 5, comment: 'Always delivers quality.', date: 'Dec 14', service: 'Fade' },
  ];

  return (
    <div className="space-y-4">
      {/* Tab Navigation */}
      <div className="flex border-b border-gray-200">
        <button
          onClick={() => setActiveTab('performance')}
          className={`flex-1 py-3 px-4 text-center font-semibold transition-colors ${
            activeTab === 'performance'
              ? 'text-gray-900 border-b-2 border-gray-900'
              : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          Performance
        </button>
        <button
          onClick={() => setActiveTab('pricing')}
          className={`flex-1 py-3 px-4 text-center font-semibold transition-colors ${
            activeTab === 'pricing'
              ? 'text-gray-900 border-b-2 border-gray-900'
              : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          Pricing
        </button>
      </div>

      {/* Performance Tab */}
      {activeTab === 'performance' && (
        <div className="space-y-2">
          {/* Bookings Section */}
          <div className="border border-gray-200 rounded-lg overflow-hidden">
            <button
              onClick={() => toggleSection('bookings')}
              className="w-full flex items-center justify-between p-4 hover:bg-gray-50 transition-colors"
            >
              <div className="flex items-center gap-4">
                <span className="font-semibold text-gray-900">Bookings</span>
                <span className="text-gray-500">{performanceData.totalBookings} all-time</span>
              </div>
              {expandedSection === 'bookings' ? (
                <ChevronDown className="w-5 h-5 text-gray-400" />
              ) : (
                <ChevronRight className="w-5 h-5 text-gray-400" />
              )}
            </button>
            {expandedSection === 'bookings' && (
              <div className="border-t border-gray-200 p-4 bg-gray-50">
                <div className="grid grid-cols-3 gap-4 mb-4">
                  <div className="text-center">
                    <p className="text-2xl font-bold text-gray-900">{performanceData.totalBookings}</p>
                    <p className="text-xs text-gray-500">All-Time</p>
                  </div>
                  <div className="text-center">
                    <p className="text-2xl font-bold text-gray-900">{totalBookings30Day}</p>
                    <p className="text-xs text-gray-500">Last 30 Days</p>
                  </div>
                  <div className="text-center">
                    <p className="text-2xl font-bold text-gray-900">{avgDailyBookings.toFixed(1)}</p>
                    <p className="text-xs text-gray-500">Daily Avg</p>
                  </div>
                </div>
                <p className="text-sm font-medium text-gray-700 mb-2">Recent Days</p>
                <div className="space-y-1 max-h-40 overflow-y-auto">
                  {revenueHistory.slice(-10).reverse().map((day, idx) => (
                    <div key={idx} className="flex items-center justify-between p-2 bg-white rounded text-sm">
                      <span className="text-gray-600">{day.date}</span>
                      <span className="font-medium text-gray-900">{day.bookings} bookings</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Revenue Section */}
          <div className="border border-gray-200 rounded-lg overflow-hidden">
            <button
              onClick={() => toggleSection('revenue')}
              className="w-full flex items-center justify-between p-4 hover:bg-gray-50 transition-colors"
            >
              <div className="flex items-center gap-4">
                <span className="font-semibold text-gray-900">Revenue</span>
                <span className="text-gray-500">${performanceData.totalRevenue.toLocaleString()} all-time</span>
              </div>
              {expandedSection === 'revenue' ? (
                <ChevronDown className="w-5 h-5 text-gray-400" />
              ) : (
                <ChevronRight className="w-5 h-5 text-gray-400" />
              )}
            </button>
            {expandedSection === 'revenue' && (
              <div className="border-t border-gray-200 p-4 bg-gray-50">
                <div className="grid grid-cols-3 gap-4 mb-4">
                  <div className="text-center">
                    <p className="text-2xl font-bold text-gray-900">${performanceData.totalRevenue.toLocaleString()}</p>
                    <p className="text-xs text-gray-500">All-Time</p>
                  </div>
                  <div className="text-center">
                    <p className="text-2xl font-bold text-gray-900">${totalRevenue30Day.toFixed(0)}</p>
                    <p className="text-xs text-gray-500">Last 30 Days</p>
                  </div>
                  <div className="text-center">
                    <p className="text-2xl font-bold text-gray-900">${avgDailyRevenue.toFixed(0)}</p>
                    <p className="text-xs text-gray-500">Daily Avg</p>
                  </div>
                </div>
                <p className="text-sm font-medium text-gray-700 mb-2">Recent Days</p>
                <div className="space-y-1 max-h-40 overflow-y-auto">
                  {revenueHistory.slice(-10).reverse().map((day, idx) => (
                    <div key={idx} className="flex items-center justify-between p-2 bg-white rounded text-sm">
                      <span className="text-gray-600">{day.date}</span>
                      <span className="font-medium text-gray-900">+${day.revenue.toFixed(0)}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>


          {/* Reviews Section */}
          <div className="border border-gray-200 rounded-lg overflow-hidden">
            <button
              onClick={() => toggleSection('reviews')}
              className="w-full flex items-center justify-between p-4 hover:bg-gray-50 transition-colors"
            >
              <div className="flex items-center gap-4">
                <span className="font-semibold text-gray-900">Reviews</span>
                <span className="text-gray-500">{performanceData.totalReviews} total</span>
              </div>
              {expandedSection === 'reviews' ? (
                <ChevronDown className="w-5 h-5 text-gray-400" />
              ) : (
                <ChevronRight className="w-5 h-5 text-gray-400" />
              )}
            </button>
            {expandedSection === 'reviews' && (
              <div className="border-t border-gray-200 p-4 bg-gray-50">
                <div className="space-y-3 max-h-64 overflow-y-auto">
                  {recentReviews.map((review, idx) => (
                    <div key={idx} className="p-3 bg-white rounded-lg border border-gray-100">
                      <div className="flex items-center justify-between mb-1">
                        <div className="flex items-center gap-2">
                          <span className="font-medium text-gray-900">{review.name}</span>
                          <span className="text-xs text-gray-400">•</span>
                          <span className="text-xs text-gray-500">{review.service}</span>
                        </div>
                      </div>
                      <p className="text-sm text-gray-600">"{review.comment}"</p>
                      <p className="text-xs text-gray-400 mt-1">{review.date}</p>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Pricing Tab */}
      {activeTab === 'pricing' && (
        <div className="space-y-4">
          {/* Current Prices */}
          <div className="space-y-2">
            <p className="text-sm font-medium text-gray-700">Your Service Prices</p>
            {prices.map((price) => (
              <div key={price.serviceId} className="flex items-center justify-between p-4 border border-gray-200 rounded-lg">
                <div>
                  <p className="font-medium text-gray-900">{price.serviceName}</p>
                  {price.previousPrice !== price.currentPrice && (
                    <p className="text-xs text-gray-500">
                      Was ${price.previousPrice.toFixed(2)}
                    </p>
                  )}
                </div>
                <div className="text-right">
                  <p className="text-xl font-bold text-gray-900">${price.currentPrice.toFixed(2)}</p>
                  {price.priceChangePct !== 0 && (
                    <div className={`flex items-center justify-end gap-1 text-xs ${
                      price.priceChangePct > 0 ? 'text-gray-600' : 'text-gray-600'
                    }`}>
                      {price.priceChangePct > 0 ? (
                        <TrendingUp className="w-3 h-3" />
                      ) : (
                        <TrendingDown className="w-3 h-3" />
                      )}
                      {price.priceChangePct > 0 ? '+' : ''}{price.priceChangePct.toFixed(1)}%
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>

          {/* Dynamic Pricing Info */}
          <div className="p-4 border border-gray-200 rounded-lg">
            <p className="font-medium text-gray-900 mb-2">Dynamic Pricing</p>
            <p className="text-sm text-gray-600 mb-3">
              Your prices are automatically optimized based on:
            </p>
            <ul className="text-sm text-gray-600 space-y-1">
              <li>• Market demand and competition</li>
              <li>• Your ratings and reviews</li>
              <li>• Time of day and week</li>
              <li>• Your booking availability</li>
            </ul>
          </div>
        </div>
      )}
    </div>
  );
}
