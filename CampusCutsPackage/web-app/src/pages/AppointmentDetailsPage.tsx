import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Clock, MapPin, DollarSign, User, Mail, MessageCircle, CheckCircle, XCircle, Calendar, AlertCircle } from 'lucide-react';
import Card from '../components/Card';
import Button from '../components/Button';
import BarberHeader from '../components/BarberHeader';

export default function AppointmentDetailsPage() {
  const { appointmentId } = useParams();
  const navigate = useNavigate();

  // Mock appointment data - in production, fetch from API based on appointmentId
  // Different data for each appointment ID to show variation
  const mockAppointments: Record<string, any> = {
    '1': {
      id: '1',
      time: '10:00 AM',
      date: 'Today, Friday, January 12, 2025',
      client: {
        name: 'John Doe',
        email: 'john.doe@college.edu',
        avatar: null,
        studentId: 'STU-2024-001',
        totalBookings: 12,
        completedBookings: 11,
        cancelledBookings: 1,
        reliabilityScore: 92,
        avgRating: 4.7,
      },
      service: {
        name: 'Haircut & Fade',
        duration: '45 min',
        notes: 'Looking for a mid-fade with texture on top, similar to last time',
      },
      location: {
        type: 'My Dorm',
        address: 'Yosemite Hall, Room 304',
        instructions: 'Third floor, take elevator. Will meet you in lobby.',
      },
      price: {
        service: 35.00,
        platformFee: 1.75,
        total: 36.75,
        paymentMethod: 'Escrow (Blockchain)',
      },
      status: 'confirmed',
      bookedAt: '2 hours ago',
      blockchainTx: '0x7f8a...3d2c',
    },
    '2': {
      id: '2',
      time: '11:30 AM',
      date: 'Today, Friday, January 12, 2025',
      client: {
        name: 'Mike Smith',
        email: 'mike.smith@college.edu',
        avatar: null,
        studentId: 'STU-2024-002',
        totalBookings: 8,
        completedBookings: 8,
        cancelledBookings: 0,
        reliabilityScore: 100,
        avgRating: 5.0,
      },
      service: {
        name: 'Beard Trim',
        duration: '20 min',
        notes: 'Clean up the edges, keep it natural looking',
      },
      location: {
        type: 'Student Union',
        address: 'UU Plaza, 2nd Floor Lounge',
        instructions: 'Near the food court, will be at the corner table.',
      },
      price: {
        service: 23.00,
        platformFee: 1.15,
        total: 24.15,
        paymentMethod: 'Escrow (Blockchain)',
      },
      status: 'confirmed',
      bookedAt: '3 hours ago',
      blockchainTx: '0x9a2b...4e5f',
    },
    '3': {
      id: '3',
      time: '2:00 PM',
      date: 'Today, Friday, January 12, 2025',
      client: {
        name: 'Chris Lee',
        email: 'chris.lee@college.edu',
        avatar: null,
        studentId: 'STU-2024-003',
        totalBookings: 5,
        completedBookings: 4,
        cancelledBookings: 1,
        reliabilityScore: 80,
        avgRating: 4.5,
      },
      service: {
        name: 'Full Service',
        duration: '60 min',
        notes: 'Haircut, beard trim, and hot towel shave. First time here!',
      },
      location: {
        type: 'Off-Campus Apartment',
        address: 'The Grove Apartments, Unit 204B',
        instructions: 'Use the west entrance, building 2. Parking available.',
      },
      price: {
        service: 45.00,
        platformFee: 2.25,
        total: 47.25,
        paymentMethod: 'Escrow (Blockchain)',
      },
      status: 'pending',
      bookedAt: '30 minutes ago',
      blockchainTx: '0x3c4d...7g8h',
    },
    '4': {
      id: '4',
      time: '3:30 PM',
      date: 'Today, Friday, January 12, 2025',
      client: {
        name: 'David Brown',
        email: 'david.brown@college.edu',
        avatar: null,
        studentId: 'STU-2024-004',
        totalBookings: 15,
        completedBookings: 14,
        cancelledBookings: 1,
        reliabilityScore: 93,
        avgRating: 4.8,
      },
      service: {
        name: 'Haircut',
        duration: '30 min',
        notes: 'Regular trim, same as last 3 times',
      },
      location: {
        type: 'My Dorm',
        address: 'Sierra Madre Hall, Room 512',
        instructions: 'Fifth floor, room at the end of the hall.',
      },
      price: {
        service: 28.00,
        platformFee: 1.40,
        total: 29.40,
        paymentMethod: 'Escrow (Blockchain)',
      },
      status: 'confirmed',
      bookedAt: '1 day ago',
      blockchainTx: '0x5e6f...9i0j',
    },
    '5': {
      id: '5',
      time: '5:00 PM',
      date: 'Today, Friday, January 12, 2025',
      client: {
        name: 'James Wilson',
        email: 'james.wilson@college.edu',
        avatar: null,
        studentId: 'STU-2024-005',
        totalBookings: 3,
        completedBookings: 3,
        cancelledBookings: 0,
        reliabilityScore: 100,
        avgRating: 5.0,
      },
      service: {
        name: 'Haircut',
        duration: '30 min',
        notes: 'Keep it short on the sides, blend the top. Military style.',
      },
      location: {
        type: 'Recreation Center',
        address: 'Campus Rec Center, Main Lobby',
        instructions: 'Meet near the front desk after my workout.',
      },
      price: {
        service: 28.00,
        platformFee: 1.40,
        total: 29.40,
        paymentMethod: 'Escrow (Blockchain)',
      },
      status: 'confirmed',
      bookedAt: '4 hours ago',
      blockchainTx: '0x7k8l...1m2n',
    },
  };

  // Get appointment data by ID, default to ID '1' if not found
  const appointment = mockAppointments[appointmentId || '1'] || mockAppointments['1'];

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'confirmed':
        return 'bg-green-100 text-green-800 border-green-300';
      case 'pending':
        return 'bg-yellow-100 text-yellow-800 border-yellow-300';
      case 'completed':
        return 'bg-blue-100 text-blue-800 border-blue-300';
      case 'cancelled':
        return 'bg-red-100 text-red-800 border-red-300';
      default:
        return 'bg-gray-100 text-gray-800 border-gray-300';
    }
  };

  const getReliabilityColor = (score: number) => {
    if (score >= 90) return 'text-green-600';
    if (score >= 75) return 'text-yellow-600';
    return 'text-red-600';
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-primary-50 to-primary-50">
      {/* Header */}
      <BarberHeader title={`Appointment Details - #${appointment.id}`} showBookingRequests={false} />

      {/* Content */}
      <div className="max-w-4xl mx-auto px-4 py-8 space-y-6">
        
        {/* Status & Quick Actions */}
        <Card>
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-2xl font-bold text-gray-900">{appointment.service.name}</h2>
              <p className="text-gray-600">{appointment.date} at {appointment.time}</p>
            </div>
            <div className={`px-4 py-2 rounded-full border-2 font-semibold uppercase text-sm ${getStatusColor(appointment.status)}`}>
              {appointment.status}
            </div>
          </div>

          {/* Quick Actions */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <Button variant="primary" className="w-full">
              <MessageCircle className="w-4 h-4 mr-2" />
              Message
            </Button>
            <Button variant="primary" className="w-full">
              <CheckCircle className="w-4 h-4 mr-2" />
              Complete
            </Button>
            <Button variant="danger" className="w-full">
              <XCircle className="w-4 h-4 mr-2" />
              Cancel
            </Button>
          </div>
        </Card>

        {/* Customer Information */}
        <Card>
          
          <div className="space-y-4">
            {/* Customer Profile */}
            <div className="flex items-start gap-4">
              <div className="w-16 h-16 rounded-full bg-gradient-to-br from-primary-500 to-primary-500 flex items-center justify-center text-white text-2xl font-bold">
                {appointment.client.name.split(' ').map(n => n[0]).join('')}
              </div>
              <div className="flex-1">
                <h4 className="text-xl font-bold text-gray-900">{appointment.client.name}</h4>
                <p className="text-sm text-gray-600">Student ID: {appointment.client.studentId}</p>
              </div>
            </div>

            {/* Contact Details */}
            <div className="grid sm:grid-cols-2 gap-3 pt-4 border-t border-gray-200">
              <div className="flex items-center gap-3 text-gray-700">
                <Mail className="w-5 h-5 text-gray-400" />
                <div>
                  <p className="text-xs text-gray-500">Email</p>
                  <p className="font-medium">{appointment.client.email}</p>
                </div>
              </div>
            </div>

            {/* Customer Stats */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 pt-4 border-t border-gray-200">
              <div className="text-center">
                <p className="text-2xl font-bold text-primary-400">{appointment.client.totalBookings}</p>
                <p className="text-xs text-gray-600">Total Bookings</p>
              </div>
              <div className="text-center">
                <p className="text-2xl font-bold text-green-600">{appointment.client.completedBookings}</p>
                <p className="text-xs text-gray-600">Completed</p>
              </div>
              <div className="text-center">
                <p className="text-2xl font-bold text-yellow-600">{appointment.client.avgRating}</p>
                <p className="text-xs text-gray-600">Avg Rating</p>
              </div>
              <div className="text-center">
                <p className={`text-2xl font-bold ${getReliabilityColor(appointment.client.reliabilityScore)}`}>
                  {appointment.client.reliabilityScore}%
                </p>
                <p className="text-xs text-gray-600">Reliability</p>
              </div>
            </div>

            {/* Reliability Badge */}
            <div className="flex items-center gap-2 p-3 bg-green-50 rounded-lg border border-green-200">
              <CheckCircle className="w-5 h-5 text-green-600" />
              <div>
                <p className="font-semibold text-green-900">Reliable Customer</p>
                <p className="text-sm text-green-700">High show-up rate, rarely cancels</p>
              </div>
            </div>
          </div>
        </Card>

        {/* Service Details */}
        <Card>
          <h3 className="text-lg font-bold text-gray-900 mb-4 flex items-center gap-2">
            <AlertCircle className="w-5 h-5 text-primary-400" />
            Service Details
          </h3>
          
          <div className="space-y-3">
            <div className="flex items-start gap-3">
              <Clock className="w-5 h-5 text-gray-400 mt-1" />
              <div>
                <p className="font-semibold text-gray-900">Duration</p>
                <p className="text-gray-600">{appointment.service.duration}</p>
              </div>
            </div>
            
            <div className="flex items-start gap-3">
              <Calendar className="w-5 h-5 text-gray-400 mt-1" />
              <div>
                <p className="font-semibold text-gray-900">Scheduled Time</p>
                <p className="text-gray-600">{appointment.date} at {appointment.time}</p>
                <p className="text-sm text-gray-500">Booked {appointment.bookedAt}</p>
              </div>
            </div>

            {appointment.service.notes && (
              <div className="p-3 bg-yellow-50 rounded-lg border border-yellow-200">
                <p className="font-semibold text-yellow-900 mb-1">Customer Notes:</p>
                <p className="text-yellow-800">{appointment.service.notes}</p>
              </div>
            )}
          </div>
        </Card>

        {/* Location Details */}
        <Card>
          <h3 className="text-lg font-bold text-gray-900 mb-4 flex items-center gap-2">
            <MapPin className="w-5 h-5 text-primary-400" />
            Location Details
          </h3>
          
          <div className="space-y-3">
            <div>
              <p className="font-semibold text-gray-900">{appointment.location.type}</p>
              <p className="text-gray-600">{appointment.location.address}</p>
            </div>
            
            {appointment.location.instructions && (
              <div className="p-3 bg-blue-50 rounded-lg border border-blue-200">
                <p className="font-semibold text-blue-900 mb-1">Instructions:</p>
                <p className="text-blue-800">{appointment.location.instructions}</p>
              </div>
            )}

            <Button variant="secondary" className="w-full">
              <MapPin className="w-4 h-4 mr-2" />
              Open in Maps
            </Button>
          </div>
        </Card>

        {/* Payment Information */}
        <Card>
          <h3 className="text-lg font-bold text-gray-900 mb-4 flex items-center gap-2">
            <DollarSign className="w-5 h-5 text-primary-400" />
            Payment Information
          </h3>
          
          <div className="space-y-3">
            <div className="flex justify-between items-center">
              <span className="text-gray-600">Service Fee</span>
              <span className="font-semibold text-gray-900">${appointment.price.service.toFixed(2)}</span>
            </div>
            <div className="border-t border-gray-200 pt-3 flex justify-between items-center">
              <span className="font-bold text-gray-900">Total Amount</span>
              <span className="font-bold text-2xl text-green-600">${appointment.price.total.toFixed(2)}</span>
            </div>
            
            <div className="p-3 bg-primary-50 rounded-lg border border-primary-200">
              <div className="flex items-center justify-between mb-2">
                <p className="font-semibold text-primary-700">Payment Status</p>
                <span className="px-2 py-1 bg-green-100 text-green-800 text-xs rounded-full font-semibold">
                  ESCROWED
                </span>
              </div>
              <p className="text-sm text-primary-600 mb-2">
                Funds are securely held in blockchain escrow. You'll receive payment after service completion.
              </p>
              <div className="flex items-center gap-2 text-xs text-primary-500">
                <span className="font-mono bg-primary-100 px-2 py-1 rounded">
                  TX: {appointment.blockchainTx}
                </span>
              </div>
            </div>
          </div>
        </Card>

        {/* Action History */}
        <Card>
          <h3 className="text-lg font-bold text-gray-900 mb-4">Activity Timeline</h3>
          
          <div className="space-y-4">
            {(() => {
              const timelines: Record<string, any[]> = {
                '1': [
                  { time: appointment.bookedAt, action: 'Booking confirmed', status: 'success' },
                  { time: appointment.bookedAt, action: 'Payment escrowed on blockchain', status: 'success' },
                  { time: appointment.bookedAt, action: 'Customer sent booking request', status: 'info' },
                ],
                '2': [
                  { time: appointment.bookedAt, action: 'Booking confirmed', status: 'success' },
                  { time: appointment.bookedAt, action: 'Payment escrowed on blockchain', status: 'success' },
                  { time: appointment.bookedAt, action: 'Customer sent booking request', status: 'info' },
                ],
                '3': [
                  { time: appointment.bookedAt, action: 'Customer sent booking request', status: 'info' },
                  { time: '25 minutes ago', action: 'Payment escrowed on blockchain', status: 'success' },
                  { time: '20 minutes ago', action: 'Awaiting barber confirmation', status: 'warning' },
                ],
                '4': [
                  { time: appointment.bookedAt, action: 'Booking confirmed', status: 'success' },
                  { time: appointment.bookedAt, action: 'Payment escrowed on blockchain', status: 'success' },
                  { time: appointment.bookedAt, action: 'Customer sent booking request', status: 'info' },
                  { time: '23 hours ago', action: 'Customer added service notes', status: 'info' },
                ],
                '5': [
                  { time: appointment.bookedAt, action: 'Booking confirmed', status: 'success' },
                  { time: appointment.bookedAt, action: 'Payment escrowed on blockchain', status: 'success' },
                  { time: appointment.bookedAt, action: 'Customer sent booking request', status: 'info' },
                ],
              };

              const timeline = timelines[appointment.id] || timelines['1'];

              return timeline.map((activity, idx) => (
                <div key={idx} className="flex items-start gap-3">
                  <div className={`w-2 h-2 rounded-full mt-2 ${
                    activity.status === 'success' 
                      ? 'bg-green-500' 
                      : activity.status === 'warning'
                      ? 'bg-yellow-500'
                      : 'bg-blue-500'
                  }`}></div>
                  <div>
                    <p className="font-medium text-gray-900">{activity.action}</p>
                    <p className="text-sm text-gray-500">{activity.time}</p>
                  </div>
                </div>
              ));
            })()}
          </div>
        </Card>

      </div>
    </div>
  );
}

