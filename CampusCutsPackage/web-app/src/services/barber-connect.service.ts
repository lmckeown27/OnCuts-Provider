import api from './api.service';

export interface BarberConnectStatus {
  has_account: boolean;
  account_id?: string;
  detailsSubmitted?: boolean;
  chargesEnabled?: boolean;
  payoutsEnabled?: boolean;
}

export async function fetchBarberConnectStatus(): Promise<BarberConnectStatus> {
  return api.get<BarberConnectStatus>('/barber/connect/status');
}

export async function createBarberConnectOnboarding(): Promise<{ account_id: string; onboarding_url: string }> {
  return api.post('/barber/connect/create', {});
}

export async function fetchBarberStripeDashboardUrl(): Promise<string> {
  const data = await api.get<{ dashboard_url: string }>('/barber/connect/dashboard');
  return data.dashboard_url;
}
