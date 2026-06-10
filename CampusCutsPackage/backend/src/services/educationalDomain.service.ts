/**
 * Educational Domain Validation Service for CampusCuts
 * Transferred from CampusKinect with CampusCuts adaptations
 * 
 * Validates .edu and international educational email domains
 * Three-tier validation: Database → External APIs → Pattern Matching
 */

import { pool } from '../database/connection';
import axios from 'axios';

interface ValidationResult {
  isValid: boolean;
  country?: string;
  university?: string;
  confidence?: 'high' | 'medium' | 'low';
  source?: 'database' | 'api' | 'pattern' | 'none';
  needsVerification?: boolean;
  isUnsupportedUniversity?: boolean;
  domain?: string;
}

interface KnownUniversity {
  name: string;
  country: string;
}

class EducationalDomainService {
  // Major first-world country educational domains
  private knownPatterns: Record<string, string[]> = {
    US: ['.edu'],
    UK: ['.ac.uk'],
    Canada: ['.ca'],
    Australia: ['.edu.au'],
    Germany: ['.de'],
    France: ['.fr'],
  };

  // Common university name patterns
  private universityPatterns: RegExp[] = [
    /university/i,
    /college/i,
    /institute/i,
  ];

  /**
   * Validate if an email domain is educational
   */
  async validateEducationalDomain(email: string): Promise<ValidationResult> {
    try {
      const domain = email.split('@')[1];

      // First: Check our database for known universities
      const knownUniversity = await this.checkKnownUniversity(domain);
      if (knownUniversity) {
        return {
          isValid: true,
          country: knownUniversity.country,
          university: knownUniversity.name,
          confidence: 'high',
          source: 'database',
        };
      }

      // Special case: .edu domains are verified US educational institutions
      // Auto-accept and let the registration process add them to the database
      if (domain.endsWith('.edu')) {
        // Extract university name from domain (e.g., "calpoly.edu" -> "Cal Poly")
        const domainParts = domain.replace('.edu', '').split('.');
        const universitySlug = domainParts[domainParts.length - 1];
        
        return {
          isValid: true,
          country: 'US',
          university: universitySlug.charAt(0).toUpperCase() + universitySlug.slice(1),
          domain: domain,
          confidence: 'high',
          source: 'pattern',
          needsVerification: false,
        };
      }

      // Second: Try external validation APIs
      const apiValidation = await this.checkExternalAPIs(domain);
      if (apiValidation.isValid) {
        // Auto-add to our database
        await this.addNewUniversity(domain, apiValidation);
        return {
          isValid: true,
          country: apiValidation.country,
          university: apiValidation.university,
          confidence: 'high',
          source: 'api',
        };
      }

      // Third: Pattern matching fallback
      const patternValidation = this.validateByPattern(domain);
      if (patternValidation.isValid) {
        return {
          isValid: true,
          country: patternValidation.country,
          university: undefined,
          confidence: 'medium',
          source: 'pattern',
          needsVerification: true,
        };
      }

      return {
        isValid: false,
        confidence: 'low',
        source: 'none',
      };
    } catch (error) {
      console.error('Error validating educational domain:', error);
      return this.validateByPattern(email.split('@')[1]);
    }
  }

  /**
   * Check if domain exists in our database
   */
  private async checkKnownUniversity(domain: string): Promise<KnownUniversity | null> {
    try {
      const result = await pool.query(
        'SELECT name, country FROM campuses WHERE domain = $1 AND is_active = true',
        [domain]
      );
      return result.rows[0] || null;
    } catch (error) {
      console.error('Error checking known university:', error);
      return null;
    }
  }

  /**
   * Try external validation APIs
   */
  private async checkExternalAPIs(domain: string): Promise<ValidationResult> {
    try {
      // Note: External API calls are optional and may require API keys
      // For MVP, we'll rely primarily on database and pattern matching
      return { isValid: false };
    } catch (error) {
      console.error('Error checking external APIs:', error);
      return { isValid: false };
    }
  }

  /**
   * Pattern-based validation fallback
   */
  private validateByPattern(domain: string): ValidationResult {
    // Check known country patterns
    for (const [country, patterns] of Object.entries(this.knownPatterns)) {
      if (patterns.some((pattern) => domain.endsWith(pattern))) {
        return {
          isValid: true,
          country,
          confidence: 'medium',
          source: 'pattern',
        };
      }
    }

    // Check for university name patterns
    const hasUniversityPattern = this.universityPatterns.some((pattern) =>
      pattern.test(domain)
    );

    if (hasUniversityPattern) {
      const country = this.detectCountryFromDomain(domain);
      return {
        isValid: true,
        country,
        confidence: 'low',
        source: 'pattern',
        needsVerification: true,
      };
    }

    return { isValid: false };
  }

  /**
   * Detect country from domain patterns
   */
  private detectCountryFromDomain(domain: string): string {
    if (domain.endsWith('.edu')) return 'US';
    if (domain.endsWith('.ac.uk')) return 'UK';
    if (domain.endsWith('.ca')) return 'Canada';
    if (domain.endsWith('.edu.au')) return 'Australia';
    if (domain.endsWith('.de')) return 'Germany';
    if (domain.endsWith('.fr')) return 'France';

    return 'US'; // Default
  }

  /**
   * Add new university to database
   * Note: Disabled in blockchain-first architecture (no PostgreSQL)
   */
  private async addNewUniversity(
    domain: string,
    validationData: ValidationResult
  ): Promise<void> {
    // Note: PostgreSQL removed - this method is now a no-op
    // In blockchain-first architecture, universities would be stored on-chain
    console.log(`ℹ️  Would add university: ${domain} (${validationData.country})`);
  }

  /**
   * Get all supported countries
   */
  getSupportedCountries(): string[] {
    return Object.keys(this.knownPatterns);
  }

  /**
   * Get educational domains for a specific country
   */
  getCountryPatterns(country: string): string[] {
    return this.knownPatterns[country] || [];
  }
}

export default new EducationalDomainService();

