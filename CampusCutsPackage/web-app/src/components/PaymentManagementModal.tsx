/**
 * Payout Settings — Stripe Connect actions, booking estimates, and payout copy.
 */

import { useState, useEffect } from 'react';
import { X, BarChart3, Landmark, ExternalLink } from 'lucide-react';
import toast from 'react-hot-toast';
import Button from './Button';
import {
  fetchBarberPayoutSummary,
  type BarberPayoutSummary,
} from '../services/barber-payout.service';
import {
  fetchBarberConnectStatus,
  createBarberConnectOnboarding,
  fetchBarberStripeDashboardUrl,
  type BarberConnectStatus,
} from '../services/barber-connect.service';

interface PaymentManagementModalProps {
  isOpen: boolean;
  onClose: () => void;
}

function formatUsd(dollars: number): string {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(
    Number.isFinite(dollars) ? dollars : 0
  );
}

function centsToUsd(cents: number): number {
  return Math.round(cents) / 100;
}

export default function PaymentManagementModal({ isOpen, onClose }: PaymentManagementModalProps) {
  const [summary, setSummary] = useState<BarberPayoutSummary | null>(null);
  const [connectStatus, setConnectStatus] = useState<BarberConnectStatus | null>(null);
  const [connectStatusUnknown, setConnectStatusUnknown] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [connectBusy, setConnectBusy] = useState<'dashboard' | 'onboarding' | null>(null);
  const [isVisible, setIsVisible] = useState(false);
  const [isAnimating, setIsAnimating] = useState(false);

  const load = async () => {
    try {
      setIsLoading(true);
      setConnectStatusUnknown(false);
      const [sumRes, connRes] = await Promise.allSettled([
        fetchBarberPayoutSummary(),
        fetchBarberConnectStatus(),
      ]);
      setSummary(sumRes.status === 'fulfilled' ? sumRes.value : null);
      if (connRes.status === 'fulfilled') {
        setConnectStatus(connRes.value);
      } else {
        console.error(connRes.reason);
        setConnectStatus(null);
        setConnectStatusUnknown(true);
      }
    } catch (e: unknown) {
      console.error(e);
      toast.error('Could not load payout settings');
      setSummary(null);
      setConnectStatus(null);
    } finally {
      setIsLoading(false);
    }
  };

  const openStripeDashboard = async () => {
    try {
      setConnectBusy('dashboard');
      const url = await fetchBarberStripeDashboardUrl();
      window.open(url, '_blank', 'noopener,noreferrer');
    } catch (err: unknown) {
      const msg =
        err && typeof err === 'object' && 'response' in err
          ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
          : undefined;
      toast.error(msg || 'Could not open Stripe. Try completing Connect setup first.');
    } finally {
      setConnectBusy(null);
    }
  };

  const startStripeOnboarding = async () => {
    try {
      setConnectBusy('onboarding');
      const { onboarding_url: onboardingUrl } = await createBarberConnectOnboarding();
      window.location.assign(onboardingUrl);
    } catch (err: unknown) {
      const msg =
        err && typeof err === 'object' && 'response' in err
          ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
          : undefined;
      toast.error(msg || 'Could not start Stripe Connect');
      setConnectBusy(null);
    }
  };

  useEffect(() => {
    if (isOpen) {
      setIsVisible(true);
      void load();
      requestAnimationFrame(() => {
        requestAnimationFrame(() => setIsAnimating(true));
      });
    } else {
      setIsAnimating(false);
      const t = setTimeout(() => setIsVisible(false), 150);
      return () => clearTimeout(t);
    }
  }, [isOpen]);

  if (!isVisible && !isOpen) return null;

  const displayTotal = summary?.display_total_dollars ?? 0;
  const recent30Usd = summary ? centsToUsd(summary.recent_30d_barber_cents) : 0;
  const usesLedger = summary && summary.ledger_total_dollars > 0;

  return (
    <div
      className={`fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-4 transition-all duration-150 ease-out ${
        isAnimating ? 'bg-black/50' : 'bg-black/0'
      }`}
      onClick={onClose}
    >
      <div
        className={`bg-white rounded-2xl shadow-2xl max-w-lg w-full max-h-[90dvh] overflow-hidden transition-all duration-150 ease-out ${
          isAnimating ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 translate-y-4'
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="bg-gradient-to-r from-primary-600 to-primary-500 px-6 py-4 flex items-center justify-between">
          <div>
            <h2 className="text-xl font-bold text-white">Payout Settings</h2>
            <p className="text-white/80 text-sm">
              Stripe Connect payouts · booking estimates (not a platform balance)
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        <div className="p-6 overflow-y-auto max-h-[calc(90dvh-80px)]">
          {isLoading ? (
            <div className="text-center py-12">
              <div className="animate-spin w-10 h-10 border-4 border-primary-200 border-t-primary-500 rounded-full mx-auto mb-4" />
              <p className="text-gray-500">Loading payout settings…</p>
            </div>
          ) : (
            <>
              {summary?.has_barber_profile && (
                <div className="mb-6 rounded-xl border border-gray-200 bg-slate-50/90 p-4">
                  <div className="flex items-center gap-2 text-gray-900 mb-3">
                    <BarChart3 className="w-5 h-5 text-primary-600" />
                    <h3 className="text-sm font-semibold">Revenue overview</h3>
                  </div>
                  <p className="text-[11px] text-gray-600 mb-3 leading-snug">
                    Figures reflect paid bookings and internal records for your reference. Payout cash is not stored in a
                    CampusCuts balance—funds flow to your <strong>Stripe Connect</strong> account per Stripe&apos;s
                    schedule.
                  </p>
                  <div className="grid grid-cols-2 gap-3">
                    <div className="rounded-lg bg-white border border-gray-100 p-3 shadow-sm">
                      <p className="text-xs text-gray-500 mb-1">Estimated received</p>
                      <p className="text-lg font-bold text-gray-900 tabular-nums">{formatUsd(displayTotal)}</p>
                      <p className="text-[10px] text-gray-400 mt-1 leading-snug">
                        {usesLedger
                          ? 'From ledger records (accounting); payouts still go through Stripe Connect.'
                          : 'From paid bookings (~85% of service after platform fee + tips).'}
                      </p>
                    </div>
                    <div className="rounded-lg bg-white border border-gray-100 p-3 shadow-sm">
                      <p className="text-xs text-gray-500 mb-1">Paid bookings</p>
                      <p className="text-lg font-bold text-gray-900 tabular-nums">
                        {summary.paid_bookings_count}
                      </p>
                      <p className="text-[10px] text-gray-400 mt-1">Completed checkout</p>
                    </div>
                    <div className="rounded-lg bg-white border border-gray-100 p-3 shadow-sm col-span-2">
                      <p className="text-xs text-gray-500 mb-1">Last 30 days (estimate)</p>
                      <p className="text-base font-semibold text-primary-700 tabular-nums">
                        {formatUsd(recent30Usd)}
                      </p>
                    </div>
                  </div>
                  {usesLedger && (
                    <div className="mt-3 flex flex-wrap gap-2 text-[11px] text-gray-600">
                      <span className="rounded-full bg-emerald-50 text-emerald-800 px-2 py-0.5">
                        Recorded settled: {formatUsd(summary.ledger_paid_out_dollars)}
                      </span>
                      {summary.ledger_pending_dollars > 0 && (
                        <span className="rounded-full bg-amber-50 text-amber-800 px-2 py-0.5">
                          Recorded pending: {formatUsd(summary.ledger_pending_dollars)}
                        </span>
                      )}
                    </div>
                  )}
                </div>
              )}

              <div className="mb-6 rounded-xl border border-primary-200 bg-primary-50/60 p-4">
                <div className="flex items-center gap-2 text-gray-900 mb-2">
                  <Landmark className="w-5 h-5 text-primary-600 shrink-0" />
                  <h3 className="text-sm font-semibold">Stripe Connect</h3>
                </div>
                <p className="text-xs text-gray-600 mb-3">
                  Open your Stripe Express dashboard to see payouts, balances, and bank transfers—or finish setup if you
                  haven&apos;t connected yet.
                </p>
                {connectStatusUnknown && (
                  <p className="text-[11px] text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-2 py-1.5 mb-3">
                    Could not load your Connect status. You can still open Stripe or start setup below.
                  </p>
                )}
                {(connectStatusUnknown || connectStatus?.has_account) && (
                  <Button
                    type="button"
                    variant="primary"
                    className="w-full flex items-center justify-center gap-2"
                    onClick={() => void openStripeDashboard()}
                    disabled={connectBusy !== null}
                  >
                    <ExternalLink className="w-4 h-4 shrink-0" />
                    {connectBusy === 'dashboard' ? 'Opening…' : 'Open Stripe dashboard'}
                  </Button>
                )}
                <Button
                  type="button"
                  variant={connectStatusUnknown || connectStatus?.has_account ? 'secondary' : 'primary'}
                  className={`w-full flex items-center justify-center gap-2 ${connectStatusUnknown || connectStatus?.has_account ? 'mt-2' : ''}`}
                  onClick={() => void startStripeOnboarding()}
                  disabled={connectBusy !== null}
                >
                  <ExternalLink className="w-4 h-4 shrink-0" />
                  {connectBusy === 'onboarding'
                    ? 'Redirecting…'
                    : connectStatus?.has_account
                      ? 'Continue or update payout details in Stripe'
                      : 'Set up Stripe Connect'}
                </Button>
              </div>

              <div className="border-t border-gray-200 pt-6 text-sm text-gray-600 space-y-2">
                <p className="font-medium text-gray-900">How payments work</p>
                <ul className="list-disc pl-5 space-y-1 text-xs">
                  <li>Customer pays in USD through Stripe Checkout (card / enabled methods).</li>
                  <li>
                    Your share is paid out through <strong>Stripe Connect</strong>. CampusCuts does not hold barber payout
                    funds in a platform balance.
                  </li>
                  <li>Use the buttons above to open Stripe or finish Connect onboarding.</li>
                </ul>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
