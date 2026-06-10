/**
 * Dynamic Pricing Service Tests
 */

import dynamicPricingService, { PricingInput } from '../../services/dynamic-pricing.service';

describe('DynamicPricingService', () => {
  describe('calculatePrice', () => {
    it('should calculate price for high-rated barber', () => {
      const input: PricingInput = {
        barber_rating: 5.0,
        barber_completion_rate: 1.0,
        barber_total_bookings: 100,
        barber_avg_price: 25,
        barbers_available_count: 5,
        bookings_last_24h: 20,
        market_type: 'medium_campus',
        time_of_day: 'afternoon',
        service_category: 'standard',
        estimated_duration_minutes: 30,
      };

      const result = dynamicPricingService.calculatePrice(input);

      expect(result.recommended_price).toBeGreaterThan(25); // Should be above base
      expect(result.confidence).toBeGreaterThan(0.8); // High confidence with 100 bookings
      expect(result.price_floor).toBeLessThan(result.recommended_price);
      expect(result.price_ceiling).toBeGreaterThan(result.recommended_price);
    });

    it('should calculate lower price for new barber', () => {
      const input: PricingInput = {
        barber_rating: 3.0,
        barber_completion_rate: 0.8,
        barber_total_bookings: 2,
        barber_avg_price: 25,
        barbers_available_count: 10,
        bookings_last_24h: 5,
        market_type: 'small_campus',
        time_of_day: 'morning',
        service_category: 'basic',
        estimated_duration_minutes: 20,
      };

      const result = dynamicPricingService.calculatePrice(input);

      expect(result.recommended_price).toBeLessThanOrEqual(20); // Lower for new barber
      expect(result.confidence).toBeLessThan(0.8); // Low confidence with 2 bookings
    });

    it('should apply weekend multiplier correctly', () => {
      const input: PricingInput = {
        barber_rating: 4.0,
        barber_completion_rate: 0.95,
        barber_total_bookings: 50,
        barber_avg_price: 25,
        barbers_available_count: 5,
        bookings_last_24h: 15,
        market_type: 'large_campus',
        time_of_day: 'weekend',
        service_category: 'standard',
        estimated_duration_minutes: 30,
      };

      const result = dynamicPricingService.calculatePrice(input);

      expect(result.breakdown.time_multiplier).toBe(1.2); // Weekend multiplier
      expect(result.recommended_price).toBeGreaterThan(25);
    });

    it('should respect price floor and ceiling', () => {
      const extremeInput: PricingInput = {
        barber_rating: 1.0,
        barber_completion_rate: 0.5,
        barber_total_bookings: 1,
        barber_avg_price: 25,
        barbers_available_count: 20,
        bookings_last_24h: 1,
        market_type: 'small_campus',
        time_of_day: 'night',
        service_category: 'standard',
        estimated_duration_minutes: 30,
      };

      const result = dynamicPricingService.calculatePrice(extremeInput);

      expect(result.recommended_price).toBeGreaterThanOrEqual(result.price_floor);
      expect(result.recommended_price).toBeLessThanOrEqual(result.price_ceiling);
    });

    it('should provide detailed reasoning', () => {
      const input: PricingInput = {
        barber_rating: 4.5,
        barber_completion_rate: 0.95,
        barber_total_bookings: 75,
        barber_avg_price: 30,
        barbers_available_count: 3,
        bookings_last_24h: 25,
        market_type: 'metro',
        time_of_day: 'evening',
        service_category: 'premium',
        estimated_duration_minutes: 60,
      };

      const result = dynamicPricingService.calculatePrice(input);

      expect(result.reasoning).toBeDefined();
      expect(result.reasoning.length).toBeGreaterThan(0);
      expect(result.reasoning.some(r => r.includes('Base price'))).toBe(true);
    });
  });

  describe('suggestStartingPrice', () => {
    it('should suggest reasonable starting price', () => {
      const result = dynamicPricingService.suggestStartingPrice({
        service_category: 'standard',
        market_type: 'medium_campus',
        estimated_duration_minutes: 30,
      });

      expect(result.recommended).toBe(25); // Base for standard
      expect(result.min).toBeLessThan(result.recommended);
      expect(result.max).toBeGreaterThan(result.recommended);
    });

    it('should adjust for market type', () => {
      const metro = dynamicPricingService.suggestStartingPrice({
        service_category: 'standard',
        market_type: 'metro',
        estimated_duration_minutes: 30,
      });

      const small = dynamicPricingService.suggestStartingPrice({
        service_category: 'standard',
        market_type: 'small_campus',
        estimated_duration_minutes: 30,
      });

      expect(metro.recommended).toBeGreaterThan(small.recommended);
    });
  });

  describe('getCurrentTimeCategory', () => {
    it('should return valid time category', () => {
      const category = dynamicPricingService.getCurrentTimeCategory();
      
      expect(['morning', 'afternoon', 'evening', 'night', 'weekend']).toContain(category);
    });
  });
});

