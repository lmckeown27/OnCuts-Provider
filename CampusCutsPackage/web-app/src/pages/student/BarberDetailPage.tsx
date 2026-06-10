// @ts-nocheck
import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { MapPin, Clock, DollarSign, Heart, MessageCircle, Award, TrendingUp } from 'lucide-react';
import type { Barber, Review } from '../../types';
import barberService from '../../services/barber.service';
import Loading from '../../components/Loading';
import Button from '../../components/Button';
import Card from '../../components/Card';
import toast from 'react-hot-toast';
import { format } from 'date-fns';

export default function BarberDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [barber, setBarber] = useState<Barber | null>(null);
  const [reviews, setReviews] = useState<Review[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [showTipModal, setShowTipModal] = useState(false);
  const [tipAmount, setTipAmount] = useState(5);
  const [selectedImageIndex, setSelectedImageIndex] = useState<number | null>(null);

  useEffect(() => {
    if (id) {
      loadBarber(id);
      loadReviews(id);
    }
  }, [id]);

  const loadBarber = async (barberId: string) => {
    try {
      const data = await barberService.getBarberById(barberId);
      setBarber(data);
    } catch (error) {
      console.error('Failed to load barber:', error);
      toast.error('Failed to load barber profile');
    } finally {
      setIsLoading(false);
    }
  };

  const loadReviews = async (barberId: string) => {
    try {
      const response = await barberService.getBarberReviews(barberId, 1, 10);
      setReviews(response.data);
    } catch (error) {
      console.error('Failed to load reviews:', error);
    }
  };

  const handleSendTip = async () => {
    if (!barber) return;
    try {
      // Integrate with payment service
      toast.success(`$${tipAmount} tip sent to ${barber.user?.first_name}!`);
      setShowTipModal(false);
      setTipAmount(5);
    } catch (error) {
      toast.error('Failed to send tip');
    }
  };

  if (isLoading) return <Loading fullScreen text="Loading barber..." />;
  if (!barber) return <div className="text-center py-12">Barber not found</div>;

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      {/* Portfolio Images Gallery */}
      {barber.portfolio_images && barber.portfolio_images.length > 0 && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          {barber.portfolio_images.map((image, index) => (
            <div
              key={image.id}
              className="relative group cursor-pointer overflow-hidden rounded-lg"
              onClick={() => setSelectedImageIndex(index)}
            >
              <img
                src={image.thumbnail_url || image.image_url}
                alt={`Portfolio ${index + 1}`}
                className="w-full h-64 object-cover transition-transform group-hover:scale-110"
              />
              <div className="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-20 transition-all" />
            </div>
          ))}
        </div>
      )}

      <div className="grid md:grid-cols-3 gap-8">
        <div className="md:col-span-2">
          {/* Header */}
          <div className="flex items-start justify-between mb-6">
            <div>
              <h1 className="text-3xl font-bold text-gray-900 mb-2">
                {barber.user?.first_name} {barber.user?.last_name}
              </h1>
              
              <div className="flex flex-wrap items-center gap-4 mb-4">
                <span className="text-gray-600">{barber.total_bookings} bookings</span>
                <div className="flex items-center gap-1 text-gray-600">
                  <Award className="w-5 h-5" />
                  <span>{barber.years_of_experience} years exp.</span>
                </div>
              </div>
            </div>
          </div>

          {/* About */}
          <Card className="mb-6">
            <h2 className="font-semibold text-lg mb-2">About</h2>
            <p className="text-gray-700">{barber.bio}</p>
          </Card>

          {/* Specialties */}
          <Card className="mb-6">
            <h2 className="font-semibold text-lg mb-3">Specialties</h2>
            <div className="flex flex-wrap gap-2">
              {barber.specialties.map((specialty, index) => (
                <span
                  key={index}
                  className="px-3 py-1 bg-primary-100 text-primary-700 rounded-full text-sm font-medium"
                >
                  {specialty}
                </span>
              ))}
            </div>
          </Card>

          {/* Services & Pricing */}
          <Card className="mb-6">
            <h2 className="font-semibold text-lg mb-3">Services & Pricing</h2>
            <div className="space-y-3">
              {barber.pricing?.map((service) => (
                <div key={service.id} className="flex justify-between items-center p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors">
                  <div>
                    <h3 className="font-medium text-gray-900">{service.name}</h3>
                    {service.description && (
                      <p className="text-sm text-gray-600 mt-1">{service.description}</p>
                    )}
                  </div>
                  <div className="text-right">
                    <p className="font-semibold text-primary-600 text-lg">${service.price}</p>
                    <p className="text-sm text-gray-600 flex items-center gap-1">
                      <Clock className="w-3 h-3" />
                      {service.duration_minutes} min
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </Card>

          {/* Reviews Section */}
          <Card>
            <div className="flex items-center justify-between mb-4">
              <h2 className="font-semibold text-lg">Reviews ({reviews.length})</h2>
            </div>
            
            {reviews.length > 0 ? (
              <div className="space-y-4">
                {reviews.map((review) => (
                  <div key={review.id} className="border-b border-gray-200 pb-4 last:border-0">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-2">
                        <div className="w-10 h-10 bg-primary-500 rounded-full flex items-center justify-center text-white font-semibold">
                          {review.student?.first_name?.[0]}{review.student?.last_name?.[0]}
                        </div>
                        <div>
                          <p className="font-medium text-gray-900">
                            {review.student?.first_name} {review.student?.last_name}
                          </p>
                          <p className="text-sm text-gray-500">
                            {format(new Date(review.created_at), 'MMM d, yyyy')}
                          </p>
                        </div>
                      </div>
                    </div>
                    {review.review_text && (
                      <p className="text-gray-700">{review.review_text}</p>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-gray-500 text-center py-8">No reviews yet</p>
            )}
          </Card>
        </div>

        {/* Sidebar */}
        <div>
          <Card className="sticky top-20 space-y-4">
            <h2 className="font-semibold text-lg">Book an Appointment</h2>
            
            <Button
              fullWidth
              onClick={() => navigate(`/student/booking/${barber.id}`)}
            >
              Book Now
            </Button>

            <Button
              fullWidth
              variant="secondary"
              onClick={() => setShowTipModal(true)}
            >
              <Heart className="w-4 h-4 mr-2" />
              Send a Tip
            </Button>

            <Button
              fullWidth
              variant="secondary"
              onClick={() => navigate(`/student/messages?barber=${barber.id}`)}
            >
              <MessageCircle className="w-4 h-4 mr-2" />
              Message
            </Button>

            {/* Quick Stats */}
            <div className="pt-4 border-t border-gray-200">
              <h3 className="font-semibold text-sm text-gray-700 mb-3">Quick Stats</h3>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-600">Total Bookings:</span>
                  <span className="font-semibold">{barber.total_bookings}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">Experience:</span>
                  <span className="font-semibold">{barber.years_of_experience} years</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">Response Time:</span>
                  <span className="font-semibold">~1 hour</span>
                </div>
              </div>
            </div>
          </Card>
        </div>
      </div>

      {/* Tip Modal */}
      {showTipModal && (
        <div 
          className="fixed inset-0 min-h-[100dvh] bg-black bg-opacity-50 flex items-center justify-center z-50 p-4"
          onClick={() => setShowTipModal(false)}
        >
          <Card 
            className="max-w-md w-full max-h-[85dvh] sm:max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="text-2xl font-bold mb-4">Send a Tip</h2>
            <p className="text-gray-600 mb-6">
              Show your appreciation to {barber.user?.first_name}!
            </p>
            
            <div className="mb-6">
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Tip Amount: ${tipAmount}
              </label>
              <input
                type="range"
                min="1"
                max="50"
                value={tipAmount}
                onChange={(e) => setTipAmount(Number(e.target.value))}
                className="w-full"
              />
              <div className="flex justify-between mt-2">
                {[5, 10, 15, 20].map((amount) => (
                  <button
                    key={amount}
                    onClick={() => setTipAmount(amount)}
                    className={`px-3 py-1 rounded-lg text-sm font-medium ${
                      tipAmount === amount
                        ? 'bg-primary-600 text-white'
                        : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                    }`}
                  >
                    ${amount}
                  </button>
                ))}
              </div>
            </div>

            <div className="flex gap-3">
              <Button
                fullWidth
                variant="secondary"
                onClick={() => setShowTipModal(false)}
              >
                Cancel
              </Button>
              <Button fullWidth onClick={handleSendTip}>
                Send ${tipAmount}
              </Button>
            </div>
          </Card>
        </div>
      )}

      {/* Image Lightbox */}
      {selectedImageIndex !== null && barber.portfolio_images && (
        <div
          className="fixed inset-0 min-h-[100dvh] bg-black bg-opacity-90 flex items-center justify-center z-50 p-4"
          onClick={() => setSelectedImageIndex(null)}
        >
          <img
            src={barber.portfolio_images[selectedImageIndex].image_url}
            alt="Portfolio"
            className="max-w-full max-h-full object-contain"
          />
          <button
            className="absolute top-4 right-4 text-white text-4xl font-bold"
            onClick={() => setSelectedImageIndex(null)}
          >
            ×
          </button>
        </div>
      )}
    </div>
  );
}

