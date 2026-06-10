/**
 * Stripe Payment Form Component
 * 
 * Handles post-booking payments using Stripe Elements with PaymentElement
 * Supports Apple Pay, Google Pay, and card payments with Face ID/Touch ID
 * 
 * Flow:
 * 1. Barber completes service
 * 2. Student is prompted to pay
 * 3. This form creates Payment Intent
 * 4. Student pays with Apple Pay, Google Pay, or card
 * 5. Stripe processes payment
 * 6. Webhook confirms and distributes funds
 */

import { useState, useEffect } from 'react';
import { loadStripe } from '@stripe/stripe-js';
import { Elements, PaymentElement, useStripe, useElements } from '@stripe/react-stripe-js';
import axios from 'axios';
import toast from 'react-hot-toast';
import Button from './Button';
import Card from './Card';
import { API_BASE_URL, STRIPE_PUBLIC_KEY } from '../config/constants';

const stripePromise = loadStripe(STRIPE_PUBLIC_KEY || 'pk_test_placeholder');

interface StripePaymentFormProps {
  bookingId: string;
  amount: number; // in dollars
  serviceName: string;
  barberName: string;
  onSuccess?: () => void;
  onError?: (error: Error) => void;
}

// Inner form component that uses Stripe hooks
function PaymentFormInner({
  bookingId,
  amount,
  serviceName,
  barberName,
  onSuccess,
  onError,
}: StripePaymentFormProps) {
  const stripe = useStripe();
  const elements = useElements();

  const [isProcessing, setIsProcessing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [paymentSuccess, setPaymentSuccess] = useState(false);

  const handlePayment = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!stripe || !elements) {
      setError('Payment system not ready. Please try again.');
      return;
    }

    setIsProcessing(true);
    setError(null);

    try {
      // Confirm payment with Stripe - PaymentElement handles all payment methods
      const { error: stripeError, paymentIntent } = await stripe.confirmPayment({
        elements,
        confirmParams: {
          return_url: window.location.href,
        },
        redirect: 'if_required',
      });

      if (stripeError) {
        throw new Error(stripeError.message || 'Payment failed');
      }

      if (paymentIntent?.status === 'succeeded') {
        setPaymentSuccess(true);
        toast.success('Payment successful! Thank you!');

        if (onSuccess) {
          onSuccess();
        }
      } else {
        throw new Error(`Payment status: ${paymentIntent?.status}`);
      }
    } catch (err: any) {
      const errorMessage = err.response?.data?.error?.message || err.message || 'Payment failed';
      setError(errorMessage);
      toast.error(errorMessage);

      if (onError) {
        onError(err);
      }
    } finally {
      setIsProcessing(false);
    }
  };

  if (paymentSuccess) {
    return (
      <Card className="p-6">
        <div className="text-center">
          <div className="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-green-100 mb-4">
            <svg
              className="h-6 w-6 text-green-600"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
          </div>
          <h3 className="text-lg font-medium text-gray-900 mb-2">
            Payment Successful!
          </h3>
          <p className="text-sm text-gray-600">
            Your payment of ${amount.toFixed(2)} has been processed.
          </p>
          <p className="text-sm text-gray-600 mt-2">
            {barberName} has received their payout.
          </p>
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <div className="mb-6">
        <h3 className="text-lg font-medium text-gray-900 mb-2">
          Complete Payment
        </h3>
        <div className="text-sm text-gray-600 space-y-1">
          <p>Service: <span className="font-medium">{serviceName}</span></p>
          <p>Barber: <span className="font-medium">{barberName}</span></p>
          <p className="text-lg font-semibold text-gray-900 mt-2">
            Amount: ${amount.toFixed(2)}
          </p>
        </div>
      </div>

      <form onSubmit={handlePayment}>
        <div className="mb-4">
          <PaymentElement 
            options={{
              layout: 'tabs',
              wallets: {
                applePay: 'auto',
                googlePay: 'auto',
              },
            }}
          />
        </div>

        {error && (
          <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-md">
            <p className="text-sm text-red-800">{error}</p>
          </div>
        )}

        <div className="bg-blue-50 border border-blue-200 rounded-md p-3 mb-4">
          <p className="text-xs text-blue-800">
            <strong>Secure Payment:</strong> Pay with Apple Pay, Google Pay, or card. 
            Your payment is processed securely by Stripe.
          </p>
        </div>

        <Button
          type="submit"
          variant="primary"
          className="w-full"
          disabled={!stripe || isProcessing}
        >
          {isProcessing ? (
            <span className="flex items-center justify-center">
              <svg
                className="animate-spin -ml-1 mr-3 h-5 w-5 text-white"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  className="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  strokeWidth="4"
                ></circle>
                <path
                  className="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                ></path>
              </svg>
              Processing...
            </span>
          ) : (
            `Pay $${amount.toFixed(2)}`
          )}
        </Button>
      </form>

      <div className="mt-4 text-center">
        <p className="text-xs text-gray-500">
          Supports Apple Pay, Google Pay & Cards | Secured by Stripe
        </p>
      </div>
    </Card>
  );
}

// Main wrapper component that handles payment intent creation
export const StripePaymentForm: React.FC<StripePaymentFormProps> = (props) => {
  const { bookingId } = props;
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const createPaymentIntent = async () => {
      try {
        const token = localStorage.getItem('accessToken');

        const response = await axios.post(
          `${API_BASE_URL}/bookings/${bookingId}/payment/create`,
          {},
          {
            headers: {
              Authorization: `Bearer ${token}`,
            },
          }
        );

        setClientSecret(response.data.data.client_secret);
      } catch (err: any) {
        console.error('Failed to create payment intent:', err);
        setError(err.response?.data?.error?.message || 'Failed to initialize payment');
      } finally {
        setIsLoading(false);
      }
    };

    createPaymentIntent();
  }, [bookingId]);

  if (isLoading) {
    return (
      <Card className="p-6">
        <div className="flex flex-col items-center justify-center py-8">
          <div className="animate-spin w-8 h-8 border-4 border-primary-200 border-t-primary-500 rounded-full mb-4"></div>
          <p className="text-gray-600">Preparing payment...</p>
        </div>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="p-6">
        <div className="text-center py-4">
          <p className="text-red-600 mb-4">{error}</p>
          <Button onClick={() => window.location.reload()}>
            Try Again
          </Button>
        </div>
      </Card>
    );
  }

  if (!clientSecret) {
    return null;
  }

  return (
    <Elements 
      stripe={stripePromise}
      options={{
        clientSecret,
        appearance: {
          theme: 'stripe',
          variables: {
            colorPrimary: '#059669',
            fontFamily: 'system-ui, sans-serif',
          },
        },
      }}
    >
      <PaymentFormInner {...props} />
    </Elements>
  );
};

export default StripePaymentForm;
