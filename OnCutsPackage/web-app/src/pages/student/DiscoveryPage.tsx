import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, SlidersHorizontal } from 'lucide-react';
import type { Barber } from '../../types';
import barberService from '../../services/barber.service';
import { useAuthStore } from '../../store/useAuthStore';
import Loading from '../../components/Loading';
import Input from '../../components/Input';
import Card from '../../components/Card';

export default function DiscoveryPage() {
  const navigate = useNavigate();
  const { user } = useAuthStore();
  const [barbers, setBarbers] = useState<Barber[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');

  useEffect(() => {
    loadBarbers();
  }, []);

  const loadBarbers = async () => {
    try {
      const response = await barberService.getBarbers({
        campus_id: user?.campus_id,
        page: 1,
        limit: 20,
      });
      setBarbers(response.data);
    } catch (error) {
      console.error('Failed to load barbers:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const filteredBarbers = barbers.filter(barber =>
    barber.user?.first_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    barber.user?.last_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    barber.specialties.some(s => s.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  if (isLoading) {
    return <Loading fullScreen text="Finding barbers..." />;
  }

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-gray-900 mb-4">Discover Barbers</h1>
        
        <div className="flex gap-4">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-5 h-5" />
            <Input
              type="text"
              placeholder="Search barbers, styles, specialties..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10"
            />
          </div>
          <button className="flex items-center gap-2 px-4 py-2 border-2 border-gray-300 rounded-lg hover:bg-gray-50">
            <SlidersHorizontal className="w-5 h-5" />
            <span>Filters</span>
          </button>
        </div>
      </div>

      {/* Pinterest-style Masonry Grid */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
        {filteredBarbers.map((barber) => (
          <Card
            key={barber.id}
            hoverable
            className="p-0 overflow-hidden cursor-pointer"
            onClick={() => navigate(`/student/barber/${barber.id}`)}
          >
            {barber.portfolio_images && barber.portfolio_images[0] ? (
              <img
                src={barber.portfolio_images[0].image_url}
                alt={`${barber.user?.first_name}'s work`}
                className="w-full h-48 object-cover"
              />
            ) : (
              <div className="w-full h-48 bg-gray-200 flex items-center justify-center">
                <p className="text-gray-400">No portfolio</p>
              </div>
            )}
            <div className="p-4">
              <h3 className="font-semibold text-gray-900">
                {barber.user?.first_name} {barber.user?.last_name}
              </h3>
              <div className="flex items-center gap-2 mt-1">
                <span className="text-yellow-500">★</span>
                <span className="text-sm text-gray-600">
                  {barber.average_rating.toFixed(1)} ({barber.total_bookings} cuts)
                </span>
              </div>
              {barber.pricing && barber.pricing.length > 0 && (
                <p className="text-sm text-primary-600 font-medium mt-2">
                  From ${Math.min(...barber.pricing.map(p => p.price))}
                </p>
              )}
            </div>
          </Card>
        ))}
      </div>

      {filteredBarbers.length === 0 && (
        <div className="text-center py-12">
          <p className="text-gray-600">No barbers found matching your search</p>
        </div>
      )}
    </div>
  );
}

