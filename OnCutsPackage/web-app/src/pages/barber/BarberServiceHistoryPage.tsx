import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Calendar, MapPin, DollarSign, MessageSquare, User, Search, Filter } from 'lucide-react';
import Card from '../../components/Card';
import Button from '../../components/Button';
import BarberHeader from '../../components/BarberHeader';

type ServiceRecord = {
  id: string;
  date: string;
  time: string;
  customerName: string;
  customerId: string;
  serviceType: string;
  location: string;
  price: number;
  status: 'completed' | 'cancelled' | 'no-show';
  rating?: number;
  review?: string;
  customerComment?: string; // Comment left during booking
  completedAt?: string;
};

export default function BarberServiceHistoryPage() {
  const navigate = useNavigate();
  const [searchQuery, setSearchQuery] = useState('');
  const [filterStatus, setFilterStatus] = useState<'all' | 'completed' | 'cancelled' | 'no-show'>('all');
  const [filterRating, setFilterRating] = useState<'all' | '5' | '4' | '3-below'>('all');

  // Mock service history data
  const serviceHistory: ServiceRecord[] = [
    {
      id: 'service-1',
      date: '2025-12-16',
      time: '2:00 PM',
      customerName: 'Alex Rivera',
      customerId: 'customer-1',
      serviceType: 'Fade',
      location: 'Student Union - Room 204',
      price: 35.00,
      status: 'completed',
      rating: 5,
      review: 'Excellent fade! Marcus really knows what he\'s doing. Super clean lines and great attention to detail. Will definitely book again!',
      customerComment: 'Looking for a mid-fade with some texture on top. Similar to what we did last time.',
      completedAt: '2025-12-16 2:45 PM',
    },
    {
      id: 'service-2',
      date: '2025-12-15',
      time: '4:30 PM',
      customerName: 'Jordan Lee',
      customerId: 'customer-2',
      serviceType: 'Haircut & Beard Trim',
      location: 'Kennedy Library - Study Room 3B',
      price: 45.00,
      status: 'completed',
      rating: 5,
      review: 'Best haircut I\'ve gotten on campus. Marcus is professional and knows how to work with different hair types. The beard trim was perfect too.',
      customerComment: 'First time getting a cut with you. I usually get a #2 on the sides and trim the top.',
      completedAt: '2025-12-15 5:15 PM',
    },
    {
      id: 'service-3',
      date: '2025-12-14',
      time: '12:00 PM',
      customerName: 'Sam Chen',
      customerId: 'customer-3',
      serviceType: 'Lineup',
      location: 'Cerro Vista Apartments - Building C',
      price: 20.00,
      status: 'completed',
      rating: 4,
      review: 'Good lineup, came out clean. Took a bit longer than expected but overall satisfied with the result.',
      customerComment: 'Just need a quick lineup before my job interview tomorrow.',
      completedAt: '2025-12-14 12:25 PM',
    },
    {
      id: 'service-4',
      date: '2025-12-13',
      time: '6:00 PM',
      customerName: 'Marcus Williams',
      customerId: 'customer-4',
      serviceType: 'Full Service',
      location: 'Poly Canyon Village - Tower 5, Room 305',
      price: 55.00,
      status: 'completed',
      rating: 5,
      review: 'Worth every penny! Got the full service and Marcus absolutely delivered. The hot towel shave was amazing and the haircut was exactly what I wanted. 10/10 experience.',
      customerComment: 'Want to get the full experience - haircut, fade, beard trim, and hot towel shave. Got a date this weekend!',
      completedAt: '2025-12-13 7:10 PM',
    },
    {
      id: 'service-5',
      date: '2025-12-12',
      time: '3:00 PM',
      customerName: 'David Park',
      customerId: 'customer-5',
      serviceType: 'Fade',
      location: 'Campus Market - Outside Seating',
      price: 32.00,
      status: 'completed',
      rating: 4,
      review: 'Solid fade. Marcus is skilled and friendly. Would recommend.',
      customerComment: 'Regular customer - you know what I like!',
      completedAt: '2025-12-12 3:40 PM',
    },
    {
      id: 'service-6',
      date: '2025-12-11',
      time: '1:30 PM',
      customerName: 'Tyler Johnson',
      customerId: 'customer-6',
      serviceType: 'Haircut',
      location: 'Recreation Center - Meeting Room A',
      price: 30.00,
      status: 'cancelled',
      customerComment: 'Need a trim before finals week. Nothing too fancy, just clean it up.',
    },
    {
      id: 'service-7',
      date: '2025-12-10',
      time: '5:00 PM',
      customerName: 'Chris Martinez',
      customerId: 'customer-7',
      serviceType: 'Beard Trim',
      location: 'Engineering Plaza - Outdoor Tables',
      price: 25.00,
      status: 'no-show',
      customerComment: 'Just need a beard shape-up. Been letting it grow out.',
    },
    {
      id: 'service-8',
      date: '2025-12-09',
      time: '2:30 PM',
      customerName: 'Ryan Thompson',
      customerId: 'customer-8',
      serviceType: 'Haircut & Fade',
      location: 'Sierra Madre Hall - Lounge',
      price: 38.00,
      status: 'completed',
      rating: 3,
      review: 'Cut was okay but felt a bit rushed. Not bad, but I\'ve had better experiences.',
      customerComment: 'Low fade with a clean part. Keep the top longer.',
      completedAt: '2025-12-09 3:15 PM',
    },
  ];

  // Filter services based on search and filters
  const filteredServices = serviceHistory.filter((service) => {
    const matchesSearch = service.customerName.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         service.serviceType.toLowerCase().includes(searchQuery.toLowerCase());
    
    const matchesStatus = filterStatus === 'all' || service.status === filterStatus;
    
    const matchesRating = filterRating === 'all' || 
                         (filterRating === '5' && service.rating === 5) ||
                         (filterRating === '4' && service.rating === 4) ||
                         (filterRating === '3-below' && service.rating && service.rating <= 3);
    
    return matchesSearch && matchesStatus && matchesRating;
  });

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed':
        return 'bg-green-100 text-green-700';
      case 'cancelled':
        return 'bg-yellow-100 text-yellow-700';
      case 'no-show':
        return 'bg-red-100 text-red-700';
      default:
        return 'bg-gray-100 text-gray-700';
    }
  };

  const getRatingColor = (rating: number) => {
    if (rating >= 5) return 'text-green-600';
    if (rating >= 4) return 'text-yellow-600';
    return 'text-orange-600';
  };

  // Calculate stats
  const stats = {
    total: serviceHistory.length,
    completed: serviceHistory.filter(s => s.status === 'completed').length,
    avgRating: serviceHistory.filter(s => s.rating).reduce((sum, s) => sum + (s.rating || 0), 0) / serviceHistory.filter(s => s.rating).length,
    totalEarned: serviceHistory.filter(s => s.status === 'completed').reduce((sum, s) => sum + s.price, 0),
  };

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <BarberHeader title="Service History" showBookingRequests={false} />

      {/* Content */}
      <div className="max-w-7xl mx-auto px-4 py-8">
        {/* Stats Overview */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <Card>
            <div className="text-center">
              <p className="text-3xl font-bold text-gray-900">{stats.total}</p>
              <p className="text-sm text-gray-600 mt-1">Total Services</p>
            </div>
          </Card>
          <Card>
            <div className="text-center">
              <p className="text-3xl font-bold text-green-600">{stats.completed}</p>
              <p className="text-sm text-gray-600 mt-1">Completed</p>
            </div>
          </Card>
          <Card>
            <div className="text-center">
              <p className="text-3xl font-bold text-yellow-600">{stats.avgRating.toFixed(1)}</p>
              <p className="text-sm text-gray-600 mt-1">Average Rating</p>
            </div>
          </Card>
          <Card>
            <div className="text-center">
              <p className="text-3xl font-bold text-primary-400">${stats.totalEarned.toFixed(2)}</p>
              <p className="text-sm text-gray-600 mt-1">Total Earned</p>
            </div>
          </Card>
        </div>

        {/* Search and Filters */}
        <Card className="mb-6">
          <div className="flex flex-col md:flex-row gap-4">
            {/* Search */}
            <div className="flex-1 relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-gray-400" />
              <input
                type="text"
                placeholder="Search by customer name or service type..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
              />
            </div>

            {/* Status Filter */}
            <div className="flex items-center gap-2">
              <Filter className="w-5 h-5 text-gray-400" />
              <select
                value={filterStatus}
                onChange={(e) => setFilterStatus(e.target.value as any)}
                className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
              >
                <option value="all">All Status</option>
                <option value="completed">Completed</option>
                <option value="cancelled">Cancelled</option>
                <option value="no-show">No-show</option>
              </select>
            </div>

            {/* Rating Filter */}
            <div>
              <select
                value={filterRating}
                onChange={(e) => setFilterRating(e.target.value as any)}
                className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
              >
                <option value="all">All Ratings</option>
                <option value="5">5 Stars</option>
                <option value="4">4 Stars</option>
                <option value="3-below">3 Stars & Below</option>
              </select>
            </div>
          </div>
        </Card>

        {/* Service Records */}
        {filteredServices.length === 0 ? (
          <Card className="text-center py-12">
            <MessageSquare className="w-12 h-12 text-gray-300 mx-auto mb-4" />
            <p className="text-gray-600">No services found matching your criteria</p>
          </Card>
        ) : (
          <div className="space-y-4">
            {filteredServices.map((service) => (
              <Card key={service.id} className="p-6">
                <div className="flex items-start justify-between mb-4">
                  <div className="flex-1">
                    <div className="flex items-center gap-3 mb-2">
                      <h3 className="text-lg font-bold text-gray-900">{service.customerName}</h3>
                      <span className={`px-2 py-1 rounded-full text-xs font-semibold ${getStatusColor(service.status)}`}>
                        {service.status.replace('-', ' ').toUpperCase()}
                      </span>
                    </div>
                    <div className="flex items-center gap-4 text-sm text-gray-600">
                      <div className="flex items-center gap-1">
                        <Calendar className="w-4 h-4" />
                        <span>{new Date(service.date).toLocaleDateString()} at {service.time}</span>
                      </div>
                      <span>•</span>
                      <span className="font-medium text-gray-900">{service.serviceType}</span>
                      <span>•</span>
                      <span className="font-semibold text-green-600">${service.price.toFixed(2)}</span>
                    </div>
                  </div>

                </div>

                {/* Location */}
                <div className="flex items-center gap-2 text-sm text-gray-700 mb-4">
                  <MapPin className="w-4 h-4 text-gray-400" />
                  <span>{service.location}</span>
                </div>

                {/* Customer's Booking Comment */}
                {service.customerComment && (
                  <div className="mb-4 p-4 bg-blue-50 border border-blue-200 rounded-lg">
                    <div className="flex items-center gap-2 mb-2">
                      <MessageSquare className="w-4 h-4 text-blue-600" />
                      <span className="text-sm font-semibold text-blue-900">Customer's Booking Notes</span>
                    </div>
                    <p className="text-sm text-blue-800">{service.customerComment}</p>
                  </div>
                )}

                {/* Review (if completed) */}
                {service.review && (
                  <div className="p-4 bg-green-50 border border-green-200 rounded-lg">
                    <div className="flex items-center gap-2 mb-2">
                      <MessageSquare className="w-4 h-4 text-green-600" />
                      <span className="text-sm font-semibold text-green-900">Customer Review</span>
                    </div>
                    <p className="text-sm text-green-800">{service.review}</p>
                    {service.completedAt && (
                      <p className="text-xs text-green-600 mt-2">
                        Completed on {new Date(service.completedAt).toLocaleString()}
                      </p>
                    )}
                  </div>
                )}

                {/* No Review Yet (if completed but no review) */}
                {service.status === 'completed' && !service.review && (
                  <div className="p-4 bg-gray-50 border border-gray-200 rounded-lg">
                    <p className="text-sm text-gray-600 italic">Customer has not left a review yet</p>
                  </div>
                )}
              </Card>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

