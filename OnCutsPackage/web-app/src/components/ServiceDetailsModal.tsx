import { useState, useEffect, useRef } from 'react';
import { X, Clock, MapPin, DollarSign, User, Mail, MessageCircle, CheckCircle, XCircle, Calendar, AlertCircle, Scissors } from 'lucide-react';
import Card from './Card';
import Button from './Button';
import { useBodyScrollLock } from '../hooks';

type TabType = 'customer' | 'service' | 'location' | 'payment';
const TABS: TabType[] = ['customer', 'service', 'location', 'payment'];

interface ServiceDetailsModalProps {
  isOpen: boolean;
  onClose: () => void;
  appointment: {
    id: string;
    time: string;
    date: string;
    client: {
      name: string;
      email: string;
      studentId: string;
      totalBookings: number;
      completedBookings: number;
      cancelledBookings: number;
      reliabilityScore: number;
      avgRating: number;
    };
    service: {
      name: string;
      duration: string;
      notes: string;
    };
    location: {
      type: string;
      address: string;
      instructions: string;
    };
    price: {
      service: number;
      platformFee: number;
      total: number;
      paymentMethod: string;
      paymentStatus: 'paid' | 'pending' | 'pay_later';
    };
    status: string;
    bookedAt: string;
    blockchainTx: string;
  };
}

export default function ServiceDetailsModal({ isOpen, onClose, appointment }: ServiceDetailsModalProps) {
  const [isVisible, setIsVisible] = useState(false);
  const [shouldRender, setShouldRender] = useState(false);
  const [activeTab, setActiveTab] = useState<TabType>('customer');
  
  // Lock body scroll when modal is open
  useBodyScrollLock(shouldRender);
  
  // Swipe handling refs
  const tabContentRef = useRef<HTMLDivElement>(null);
  const touchStartX = useRef<number | null>(null);
  const touchStartY = useRef<number | null>(null);
  const lastWheelTime = useRef<number>(0);

  // Swipe to next/previous tab
  const switchToNextTab = () => {
    const currentIndex = TABS.indexOf(activeTab);
    if (currentIndex < TABS.length - 1) {
      setActiveTab(TABS[currentIndex + 1]);
    }
  };

  const switchToPrevTab = () => {
    const currentIndex = TABS.indexOf(activeTab);
    if (currentIndex > 0) {
      setActiveTab(TABS[currentIndex - 1]);
    }
  };

  // Touch handlers for mobile swipe
  const handleTouchStart = (e: React.TouchEvent) => {
    touchStartX.current = e.touches[0].clientX;
    touchStartY.current = e.touches[0].clientY;
  };

  const handleTouchEnd = (e: React.TouchEvent) => {
    if (touchStartX.current === null || touchStartY.current === null) return;
    
    const touchEndX = e.changedTouches[0].clientX;
    const touchEndY = e.changedTouches[0].clientY;
    const deltaX = touchEndX - touchStartX.current;
    const deltaY = touchEndY - touchStartY.current;
    
    // Only trigger if horizontal swipe is dominant and significant (>50px)
    if (Math.abs(deltaX) > 50 && Math.abs(deltaX) > Math.abs(deltaY) * 1.5) {
      if (deltaX < 0) {
        // Swipe left -> next tab
        switchToNextTab();
      } else {
        // Swipe right -> previous tab
        switchToPrevTab();
      }
    }
    
    touchStartX.current = null;
    touchStartY.current = null;
  };

  // Wheel handler for 2-finger trackpad swipe
  useEffect(() => {
    const container = tabContentRef.current;
    if (!container) return;

    const handleWheel = (e: WheelEvent) => {
      // Only respond to horizontal scroll (deltaX)
      if (Math.abs(e.deltaX) > 30 && Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
        e.preventDefault();
        
        const now = Date.now();
        if (now - lastWheelTime.current < 300) return;
        
        lastWheelTime.current = now;
        if (e.deltaX > 0) {
          switchToNextTab();
        } else {
          switchToPrevTab();
        }
      }
    };

    container.addEventListener('wheel', handleWheel, { passive: false });
    return () => container.removeEventListener('wheel', handleWheel);
  }, [activeTab]);

  // Handle open animation
  useEffect(() => {
    if (isOpen) {
      setShouldRender(true);
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          setIsVisible(true);
        });
      });
    }
  }, [isOpen]);

  // Handle close with animation
  const handleClose = () => {
    setIsVisible(false);
    setTimeout(() => {
      setShouldRender(false);
      onClose();
    }, 150);
  };

  if (!shouldRender) return null;

  const getReliabilityColor = (score: number) => {
    if (score >= 90) return 'text-green-600';
    if (score >= 75) return 'text-yellow-600';
    return 'text-red-600';
  };

  return (
    <div 
      className={`fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-4 transition-all duration-150 ease-out ${
        isVisible ? 'bg-black/50' : 'bg-black/0'
      }`}
      onClick={handleClose}
    >
      <div 
        className={`bg-white rounded-xl shadow-2xl max-w-4xl w-full max-h-[85dvh] sm:max-h-[90vh] overflow-y-auto transition-all duration-150 ease-out ${
          isVisible 
            ? 'opacity-100 scale-100 translate-y-0' 
            : 'opacity-0 scale-95 translate-y-4'
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="sticky top-0 bg-white border-b border-gray-200 px-6 py-4 flex items-center justify-between rounded-t-xl z-10">
          <div>
            <h2 className="text-2xl font-bold text-gray-900">{appointment.service.name}</h2>
            <p className="text-gray-600">{appointment.date} at {appointment.time}</p>
          </div>
          <button 
            onClick={handleClose}
            className="p-2 hover:bg-gray-100 rounded-lg transition-colors"
          >
            <X className="w-6 h-6 text-gray-600" />
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="border-b border-gray-200 px-4 sm:px-6">
          <nav className="flex gap-1 sm:gap-6 overflow-x-auto pb-px scrollbar-hide">
            <button
              onClick={() => setActiveTab('customer')}
              className={`py-3 sm:py-4 px-3 sm:px-2 border-b-2 font-medium text-xs sm:text-sm transition-colors whitespace-nowrap flex-shrink-0 ${
                activeTab === 'customer'
                  ? 'border-primary-500 text-primary-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <div className="flex items-center gap-1.5 sm:gap-2">
                <User className="w-4 h-4" />
                Customer
              </div>
            </button>
            
            <button
              onClick={() => setActiveTab('service')}
              className={`py-3 sm:py-4 px-3 sm:px-2 border-b-2 font-medium text-xs sm:text-sm transition-colors whitespace-nowrap flex-shrink-0 ${
                activeTab === 'service'
                  ? 'border-primary-500 text-primary-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <div className="flex items-center gap-1.5 sm:gap-2">
                <Scissors className="w-4 h-4" />
                Service
              </div>
            </button>
            
            <button
              onClick={() => setActiveTab('location')}
              className={`py-3 sm:py-4 px-3 sm:px-2 border-b-2 font-medium text-xs sm:text-sm transition-colors whitespace-nowrap flex-shrink-0 ${
                activeTab === 'location'
                  ? 'border-primary-500 text-primary-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <div className="flex items-center gap-1.5 sm:gap-2">
                <MapPin className="w-4 h-4" />
                Location
              </div>
            </button>
            
            <button
              onClick={() => setActiveTab('payment')}
              className={`py-3 sm:py-4 px-3 sm:px-2 border-b-2 font-medium text-xs sm:text-sm transition-colors whitespace-nowrap flex-shrink-0 ${
                activeTab === 'payment'
                  ? 'border-primary-500 text-primary-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <div className="flex items-center gap-1.5 sm:gap-2">
                <DollarSign className="w-4 h-4" />
                Payment
              </div>
            </button>
          </nav>
        </div>

        {/* Tab Content */}
        <div 
          ref={tabContentRef}
          onTouchStart={handleTouchStart}
          onTouchEnd={handleTouchEnd}
          className="p-4 sm:p-6 touch-pan-y"
        >
          {/* Tab indicator dots for mobile */}
          <div className="flex justify-center gap-2 mb-4 sm:hidden">
            {TABS.map((tab) => (
              <div
                key={tab}
                className={`w-2 h-2 rounded-full transition-colors ${
                  activeTab === tab ? 'bg-primary-400' : 'bg-gray-300'
                }`}
              />
            ))}
          </div>

          {/* Customer Tab */}
          {activeTab === 'customer' && (
            <div className="space-y-4 animate-fade-in">
              {/* Customer Profile */}
              <div className="flex items-start gap-3 sm:gap-4">
                <div className="w-12 h-12 sm:w-16 sm:h-16 rounded-full bg-gradient-to-br from-primary-400 to-primary-500 flex items-center justify-center text-white text-lg sm:text-2xl font-bold flex-shrink-0">
                  {appointment.client.name.split(' ').map(n => n[0]).join('')}
                </div>
                <div className="flex-1 min-w-0">
                  <h4 className="text-lg sm:text-xl font-bold text-gray-900">{appointment.client.name}</h4>
                  <p className="text-xs sm:text-sm text-gray-600">Student ID: {appointment.client.studentId}</p>
                </div>
              </div>

              {/* Contact Details */}
              <Card className="p-3 sm:p-4">
                <div className="grid sm:grid-cols-2 gap-3">
                  <div className="flex items-center gap-2 sm:gap-3 text-gray-700">
                    <Mail className="w-4 h-4 sm:w-5 sm:h-5 text-gray-400 flex-shrink-0" />
                    <div className="min-w-0">
                      <p className="text-[10px] sm:text-xs text-gray-500">Email</p>
                      <p className="font-medium text-sm sm:text-base truncate">{appointment.client.email}</p>
                    </div>
                  </div>
                </div>
              </Card>

            </div>
          )}

          {/* Service Tab */}
          {activeTab === 'service' && (
            <div className="space-y-4 animate-fade-in">
              <Card className="p-3 sm:p-4">
                <div className="space-y-3 sm:space-y-4">
                  <div className="flex items-start gap-3">
                    <Clock className="w-4 h-4 sm:w-5 sm:h-5 text-gray-400 mt-0.5 flex-shrink-0" />
                    <div>
                      <p className="font-semibold text-gray-900 text-sm sm:text-base">Duration</p>
                      <p className="text-gray-600 text-sm sm:text-base">{appointment.service.duration}</p>
                    </div>
                  </div>
                  
                  <div className="flex items-start gap-3">
                    <Calendar className="w-4 h-4 sm:w-5 sm:h-5 text-gray-400 mt-0.5 flex-shrink-0" />
                    <div>
                      <p className="font-semibold text-gray-900 text-sm sm:text-base">Scheduled Time</p>
                      <p className="text-gray-600 text-sm sm:text-base">{appointment.date} at {appointment.time}</p>
                      <p className="text-xs sm:text-sm text-gray-500">Booked {appointment.bookedAt}</p>
                    </div>
                  </div>
                </div>
              </Card>

              {appointment.service.notes && (
                <div className="p-3 sm:p-4 bg-yellow-50 rounded-lg border border-yellow-200">
                  <p className="font-semibold text-yellow-900 mb-1 text-sm sm:text-base">Customer Notes:</p>
                  <p className="text-yellow-800 text-sm sm:text-base">{appointment.service.notes}</p>
                </div>
              )}
            </div>
          )}

          {/* Location Tab */}
          {activeTab === 'location' && (
            <div className="space-y-4 animate-fade-in">
              <Card className="p-3 sm:p-4">
                <div>
                  <p className="font-semibold text-gray-900 text-sm sm:text-base">{appointment.location.type}</p>
                  <p className="text-gray-600 text-sm sm:text-base">{appointment.location.address}</p>
                </div>
              </Card>
              
              {appointment.location.instructions && (
                <div className="p-3 sm:p-4 bg-blue-50 rounded-lg border border-blue-200">
                  <p className="font-semibold text-blue-900 mb-1 text-sm sm:text-base">Instructions:</p>
                  <p className="text-blue-800 text-sm sm:text-base">{appointment.location.instructions}</p>
                </div>
              )}

              <Button variant="secondary" className="w-full text-sm sm:text-base">
                <MapPin className="w-4 h-4 mr-2" />
                Open in Maps
              </Button>
            </div>
          )}

          {/* Payment Tab */}
          {activeTab === 'payment' && (
            <div className="space-y-4 animate-fade-in">
              <Card className="p-3 sm:p-4">
                <div className="space-y-3">
                  <div className="flex justify-between items-center">
                    <span className="text-gray-600 text-sm sm:text-base">Service Fee</span>
                    <span className="font-semibold text-gray-900 text-sm sm:text-base">${appointment.price.service.toFixed(2)}</span>
                  </div>
                  <div className="border-t border-gray-200 pt-3 flex justify-between items-center">
                    <span className="font-bold text-gray-900 text-sm sm:text-base">Total Amount</span>
                    <span className="font-bold text-xl sm:text-2xl text-green-600">${appointment.price.total.toFixed(2)}</span>
                  </div>
                </div>
              </Card>
              
              {/* Payment Status */}
              <div className={`p-3 sm:p-4 rounded-lg border ${
                appointment.price.paymentStatus === 'paid' 
                  ? 'bg-green-50 border-green-200' 
                  : appointment.price.paymentStatus === 'pay_later'
                  ? 'bg-amber-50 border-amber-200'
                  : 'bg-primary-50 border-primary-200'
              }`}>
                <div className="flex items-center justify-between mb-2">
                  <p className={`font-semibold text-sm sm:text-base ${
                    appointment.price.paymentStatus === 'paid' 
                      ? 'text-green-700' 
                      : appointment.price.paymentStatus === 'pay_later'
                      ? 'text-amber-700'
                      : 'text-primary-700'
                  }`}>Payment Status</p>
                  <span className={`px-2 py-1 text-xs rounded-full font-semibold ${
                    appointment.price.paymentStatus === 'paid' 
                      ? 'bg-green-100 text-green-800' 
                      : appointment.price.paymentStatus === 'pay_later'
                      ? 'bg-amber-100 text-amber-800'
                      : 'bg-primary-100 text-primary-800'
                  }`}>
                    {appointment.price.paymentStatus === 'paid' 
                      ? 'PAID' 
                      : appointment.price.paymentStatus === 'pay_later'
                      ? 'PAY AFTER SERVICE'
                      : 'ESCROWED'}
                  </span>
                </div>
                <p className={`text-xs sm:text-sm ${
                  appointment.price.paymentStatus === 'paid' 
                    ? 'text-green-600' 
                    : appointment.price.paymentStatus === 'pay_later'
                    ? 'text-amber-600'
                    : 'text-primary-600'
                }`}>
                  {appointment.price.paymentStatus === 'paid' 
                    ? 'Payment has been received and is ready for release upon service completion.' 
                    : appointment.price.paymentStatus === 'pay_later'
                    ? 'Customer chose to pay after service. Collect payment once the service is complete.'
                    : 'Funds are securely held in escrow via Stripe. You\'ll receive payment after service completion.'}
                </p>
              </div>

              {/* Collect Payment Button for Pay Later */}
              {appointment.price.paymentStatus === 'pay_later' && (
                <Card className="p-4 bg-gradient-to-r from-primary-50 to-green-50 border-2 border-primary-200">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-semibold text-gray-900">Ready to collect payment?</p>
                      <p className="text-sm text-gray-600">Complete the service and collect ${appointment.price.total.toFixed(2)}</p>
                    </div>
                    <Button variant="primary" className="flex items-center gap-2">
                      <DollarSign className="w-5 h-5" />
                      Collect Payment
                    </Button>
                  </div>
                </Card>
              )}
            </div>
          )}
        </div>

        {/* Quick Actions - Bottom */}
        <div className="sticky bottom-0 bg-white px-4 sm:px-6 py-5 border-t border-gray-200 rounded-b-xl">
          <div className="flex flex-wrap justify-center gap-4 sm:gap-5">
            <Button variant="primary" className="text-base sm:text-lg px-6 sm:px-8 py-3 sm:py-4">
              <MessageCircle className="w-5 h-5 sm:w-6 sm:h-6 mr-2 sm:mr-3" />
              Message
            </Button>
            <Button variant="primary" className="text-base sm:text-lg px-6 sm:px-8 py-3 sm:py-4">
              <CheckCircle className="w-5 h-5 sm:w-6 sm:h-6 mr-2 sm:mr-3" />
              Complete
            </Button>
            <Button variant="danger" className="text-base sm:text-lg px-6 sm:px-8 py-3 sm:py-4">
              <XCircle className="w-5 h-5 sm:w-6 sm:h-6 mr-2 sm:mr-3" />
              Cancel
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
