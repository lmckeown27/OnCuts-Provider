/**
 * E2E Test: Complete Booking Flow
 * 
 * Tests the entire user journey from finding a barber to completing a booking
 */

import { test, expect } from '@playwright/test';

test.describe('Complete Booking Flow', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('http://localhost:3000');
  });

  test('student can browse barbers and create booking', async ({ page }) => {
    // 1. Login/Signup
    await page.click('text=Login');
    await page.fill('input[type="email"]', 'student@test.com');
    await page.fill('input[type="password"]', 'password123');
    await page.click('button:has-text("Login")');
    
    // Wait for dashboard
    await expect(page.locator('h1')).toContainText('Welcome');
    
    // 2. Browse barbers
    await page.click('text=Find Barber');
    await expect(page.locator('.barber-card')).toHaveCount.greaterThan(0);
    
    // 3. Select barber
    await page.locator('.barber-card').first().click();
    await expect(page.locator('h1')).toContainText('Barber Profile');
    
    // 4. View services
    await expect(page.locator('.service-card')).toHaveCount.greaterThan(0);
    
    // 5. Book service
    await page.locator('.service-card').first().click();
    await page.click('button:has-text("Book Now")');
    
    // 6. Select date/time
    await page.click('button[data-testid="date-selector"]');
    await page.click('.available-slot');
    
    // 7. Add payment method (Stripe)
    await page.frameLocator('iframe[name="__privateStripeFrame"]')
      .locator('input[name="cardnumber"]')
      .fill('4242424242424242');
    await page.frameLocator('iframe[name="__privateStripeFrame"]')
      .locator('input[name="exp-date"]')
      .fill('12/25');
    await page.frameLocator('iframe[name="__privateStripeFrame"]')
      .locator('input[name="cvc"]')
      .fill('123');
    
    // 8. Confirm booking
    await page.click('button:has-text("Confirm Booking")');
    
    // 9. Wait for success
    await expect(page.locator('.success-message')).toContainText('Booking Confirmed');
    
    // 10. Verify booking appears in dashboard
    await page.click('text=My Bookings');
    await expect(page.locator('.booking-card')).toHaveCount.greaterThan(0);
  });

  test('barber can view and complete booking', async ({ page }) => {
    // 1. Login as barber
    await page.click('text=Login');
    await page.fill('input[type="email"]', 'barber@test.com');
    await page.fill('input[type="password"]', 'password123');
    await page.click('button:has-text("Login")');
    
    // 2. View pending bookings
    await page.click('text=My Bookings');
    await expect(page.locator('.booking-card')).toHaveCount.greaterThan(0);
    
    // 3. Mark booking as completed
    await page.locator('.booking-card').first().click();
    await page.click('button:has-text("Mark Complete")');
    
    // 4. Verify completion
    await expect(page.locator('.status-badge')).toContainText('Completed');
  });

  test('admin can view platform stats', async ({ page }) => {
    // 1. Login as admin
    await page.click('text=Login');
    await page.fill('input[type="email"]', 'admin@campuscuts.com');
    await page.fill('input[type="password"]', 'admin123');
    await page.click('button:has-text("Login")');
    
    // 2. Navigate to admin dashboard
    await page.click('text=Admin');
    await expect(page.locator('h1')).toContainText('Admin Dashboard');
    
    // 3. Verify stats are displayed
    await expect(page.locator('.stat-card')).toHaveCount.greaterThan(0);
    
    // 4. Connect wallet
    await page.click('button:has-text("Connect wallet")');
    // Note: In E2E, you'd need to mock the wallet extension
    
    // 5. View gas wallet status
    await expect(page.locator('.gas-wallet-card')).toBeVisible();
  });
});

test.describe('Error Handling', () => {
  test('should handle network errors gracefully', async ({ page }) => {
    // Simulate offline
    await page.context().setOffline(true);
    
    await page.goto('http://localhost:3000');
    
    // Should show offline message
    await expect(page.locator('.offline-indicator')).toBeVisible();
  });

  test('should handle invalid payment', async ({ page }) => {
    await page.goto('http://localhost:3000/book/123');
    
    // Try to book with invalid card
    await page.frameLocator('iframe[name="__privateStripeFrame"]')
      .locator('input[name="cardnumber"]')
      .fill('4000000000000002'); // Decline card
    
    await page.click('button:has-text("Confirm Booking")');
    
    // Should show error
    await expect(page.locator('.error-message')).toContainText('declined');
  });
});

