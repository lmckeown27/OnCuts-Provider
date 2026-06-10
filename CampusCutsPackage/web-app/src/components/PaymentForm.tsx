/**
 * Payment Form Component
 * 
 * Handles Stripe payment for bookings
 */

import { useState } from 'react';
import { CreditCard, Lock, DollarSign, Check, AlertCircle } from 'lucide-react';
import Button from './Button';
import Card from './Card';

interface PaymentFormProps {
  amount: number;
  bookingId: string;
  barberId: string;
  studentId: string;
  onSuccess: (paymentIntentId: string) => void;
  onError: (error: string) => void;
}

export default function PaymentForm({
  amount,
  bookingId,
  barberId,
  studentId,
  onSuccess,
  onError,
}: PaymentFormProps) {
  const [isProcessing, setIsProcessing] = useState(false);
  const [paymentMethod, setPaymentMethod] = useState<'card' | 'saved'>('card');
  const [cardNumber, setCardNumber] = useState('');
  const [cardExpiry, setCardExpiry] = useState('');
  const [cardCvc, setCardCvc] = useState('');
  const [cardholderName, setCardholderName] = useState('');

  const platformFee = amount * 0.15;
  const barberAmount = amount - platformFee;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsProcessing(true);

    try {
      // Step 1: Create payment intent
      const response = await fetch('http://localhost:3001/api/payments/create-intent', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          amount,
          bookingId,
          barberId,
          studentId,
        }),
      });

      const data = await response.json();

      if (!data.success) {
        throw new Error(data.message || 'Failed to create payment intent');
      }

      // Step 2: In production, use Stripe Elements to tokenize card
      // For demo: simulate successful payment
      await new Promise(resolve => setTimeout(resolve, 2000));

      // Step 3: Confirm payment was successful
      const statusResponse = await fetch(
        `http://localhost:3001/api/payments/${data.data.paymentIntentId}/status`
      );
      const statusData = await statusResponse.json();

      if (statusData.success) {
        onSuccess(data.data.paymentIntentId);
      } else {
        throw new Error('Payment confirmation failed');
      }
    } catch (error: any) {
      console.error('Payment error:', error);
      onError(error.message || 'Payment failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const formatCardNumber = (value: string) => {
    const v = value.replace(/\s+/g, '').replace(/[^0-9]/gi, '');
    const matches = v.match(/\d{4,16}/g);
    const match = (matches && matches[0]) || '';
    const parts = [];

    for (let i = 0, len = match.length; i < len; i += 4) {
      parts.push(match.substring(i, i + 4));
    }

    if (parts.length) {
      return parts.join(' ');
    } else {
      return value;
    }
  };

  const formatExpiry = (value: string) => {
    const v = value.replace(/\s+/g, '').replace(/[^0-9]/gi, '');
    if (v.length >= 2) {
      return v.slice(0, 2) + (v.length > 2 ? ' / ' + v.slice(2, 4) : '');
    }
    return v;
  };

  return (
    <Card className="max-w-2xl mx-auto">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900 mb-2">Payment Details</h2>
        <p className="text-gray-600">Complete your booking with secure payment</p>
      </div>

      {/* Payment Summary */}
      <div className="mb-6 p-4 bg-gray-50 rounded-lg">
        <div className="flex justify-between mb-2">
          <span className="text-gray-600">Service Amount</span>
          <span className="font-semibold">${amount.toFixed(2)}</span>
        </div>
        <div className="flex justify-between mb-2 text-sm">
          <span className="text-gray-500">Barber Receives</span>
          <span className="text-green-600 font-medium">${barberAmount.toFixed(2)}</span>
        </div>
        <div className="pt-2 border-t border-gray-200 flex justify-between">
          <span className="font-bold text-gray-900">Total</span>
          <span className="font-bold text-xl text-primary-400">${amount.toFixed(2)}</span>
        </div>
      </div>

      {/* Payment Form */}
      <form onSubmit={handleSubmit}>
        {/* Payment Method Selector */}
        <div className="mb-6">
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Payment Method
          </label>
          <div className="grid grid-cols-2 gap-4">
            <button
              type="button"
              onClick={() => setPaymentMethod('card')}
              className={`p-4 border-2 rounded-lg flex items-center justify-center gap-2 transition-colors ${
                paymentMethod === 'card'
                  ? 'border-primary-400 bg-primary-50 text-primary-500'
                  : 'border-gray-200 hover:border-gray-300'
              }`}
            >
              <CreditCard className="w-5 h-5" />
              <span className="font-medium">Credit Card</span>
            </button>
            <button
              type="button"
              onClick={() => setPaymentMethod('saved')}
              className={`p-4 border-2 rounded-lg flex items-center justify-center gap-2 transition-colors ${
                paymentMethod === 'saved'
                  ? 'border-primary-400 bg-primary-50 text-primary-500'
                  : 'border-gray-200 hover:border-gray-300'
              }`}
              disabled
            >
              <Lock className="w-5 h-5" />
              <span className="font-medium">Saved Cards</span>
            </button>
          </div>
        </div>

        {/* Card Details */}
        {paymentMethod === 'card' && (
          <div className="space-y-4 mb-6">
            {/* Cardholder Name */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Cardholder Name
              </label>
              <input
                type="text"
                value={cardholderName}
                onChange={(e) => setCardholderName(e.target.value)}
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                placeholder="John Doe"
                required
              />
            </div>

            {/* Card Number */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Card Number
              </label>
              <input
                type="text"
                value={cardNumber}
                onChange={(e) => setCardNumber(formatCardNumber(e.target.value))}
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                placeholder="4242 4242 4242 4242"
                maxLength={19}
                required
              />
              <p className="text-xs text-gray-500 mt-1">
                Test card: 4242 4242 4242 4242
              </p>
            </div>

            {/* Expiry and CVC */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Expiry Date
                </label>
                <input
                  type="text"
                  value={cardExpiry}
                  onChange={(e) => setCardExpiry(formatExpiry(e.target.value))}
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                  placeholder="MM / YY"
                  maxLength={7}
                  required
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  CVC
                </label>
                <input
                  type="text"
                  value={cardCvc}
                  onChange={(e) => setCardCvc(e.target.value.replace(/\D/g, ''))}
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                  placeholder="123"
                  maxLength={4}
                  required
                />
              </div>
            </div>
          </div>
        )}

        {/* Security Notice */}
        <div className="mb-6 p-4 bg-green-50 border border-green-200 rounded-lg flex items-start gap-3">
          <Lock className="w-5 h-5 text-green-600 mt-0.5" />
          <div className="flex-1">
            <p className="text-sm font-medium text-green-900">Secure Payment</p>
            <p className="text-xs text-green-700 mt-1">
              Your payment is encrypted and secure. Funds are held in escrow until service completion.
            </p>
          </div>
        </div>

        {/* Submit Button */}
        <Button
          type="submit"
          disabled={isProcessing}
          className="w-full py-4 text-lg font-semibold"
        >
          {isProcessing ? (
            <>
              <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin mr-2" />
              Processing Payment...
            </>
          ) : (
            <>
              <DollarSign className="w-5 h-5 mr-2" />
              Pay ${amount.toFixed(2)}
            </>
          )}
        </Button>

        {/* Terms */}
        <p className="text-xs text-center text-gray-500 mt-4">
          By completing this payment, you agree to our{' '}
          <a href="/terms" className="text-primary-400 hover:underline">
            Terms of Service
          </a>{' '}
          and{' '}
          <a href="/help" className="text-primary-400 hover:underline">
            Refund Policy
          </a>
        </p>
      </form>
    </Card>
  );
}

