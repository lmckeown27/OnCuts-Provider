import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { MapPin, Search } from 'lucide-react';
import type { Campus } from '../../types';
import { useAuthStore } from '../../store/useAuthStore';
import campusService from '../../services/campus.service';
import { ROUTES } from '../../config/constants';
import Loading from '../../components/Loading';
import Button from '../../components/Button';
import Input from '../../components/Input';
import Card from '../../components/Card';

export default function CampusSelectPage() {
  const navigate = useNavigate();
  const { user, loadUser } = useAuthStore();
  const [campuses, setCampuses] = useState<Campus[]>([]);
  const [filteredCampuses, setFilteredCampuses] = useState<Campus[]>([]);
  const [searchTerm, setSearchTerm] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [selectedCampus, setSelectedCampus] = useState<Campus | null>(null);

  useEffect(() => {
    loadCampuses();
  }, []);

  useEffect(() => {
    if (searchTerm) {
      setFilteredCampuses(
        campuses.filter(campus =>
          campus.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
          campus.city.toLowerCase().includes(searchTerm.toLowerCase())
        )
      );
    } else {
      setFilteredCampuses(campuses);
    }
  }, [searchTerm, campuses]);

  const loadCampuses = async () => {
    try {
      const data = await campusService.getCampuses();
      setCampuses(data);
      setFilteredCampuses(data);
    } catch (error) {
      toast.error('Failed to load campuses');
    } finally {
      setIsLoading(false);
    }
  };

  const handleSelectCampus = async () => {
    if (!selectedCampus) return;

    try {
      // Update user's campus (API endpoint needed)
      await loadUser();
      toast.success(`Welcome to ${selectedCampus.name}!`);
      navigate(user?.user_type === 'barber' ? ROUTES.BARBER_DASHBOARD : ROUTES.STUDENT_DISCOVERY);
    } catch (error) {
      toast.error('Failed to select campus');
    }
  };

  if (isLoading) {
    return <Loading fullScreen text="Loading campuses..." />;
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-primary-50 to-primary-100 px-4 py-12">
      <div className="max-w-4xl mx-auto">
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">Select Your Campus</h1>
          <p className="text-gray-600">Choose your university to get started</p>
        </div>

        <div className="mb-6">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-5 h-5" />
            <Input
              type="text"
              placeholder="Search for your campus..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10"
            />
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
          {filteredCampuses.map((campus) => (
            <Card
              key={campus.id}
              hoverable
              className={`cursor-pointer transition-all ${
                selectedCampus?.id === campus.id
                  ? 'ring-2 ring-primary-600 bg-primary-50'
                  : ''
              }`}
              onClick={() => setSelectedCampus(campus)}
            >
              <div className="flex items-start gap-3">
                <MapPin className="w-6 h-6 text-primary-600 flex-shrink-0 mt-1" />
                <div>
                  <h3 className="font-semibold text-gray-900">{campus.name}</h3>
                  <p className="text-sm text-gray-600">
                    {campus.city}, {campus.state}
                  </p>
                </div>
              </div>
            </Card>
          ))}
        </div>

        {filteredCampuses.length === 0 && (
          <div className="text-center py-12">
            <p className="text-gray-600">No campuses found matching "{searchTerm}"</p>
          </div>
        )}

        <div className="flex justify-center">
          <Button
            onClick={handleSelectCampus}
            disabled={!selectedCampus}
            size="lg"
          >
            Continue to CampusCut
          </Button>
        </div>
      </div>
    </div>
  );
}

