/**
 * Location Fuzzy Matching Service
 * 
 * Purpose: Intelligent deduplication of campus locations
 * Strategy: Multi-algorithm similarity detection with confidence scoring
 * 
 * Algorithms:
 * 1. Exact normalized match (100% confidence)
 * 2. Edit distance (Levenshtein)
 * 3. Trigram similarity
 * 4. Token overlap
 * 5. Acronym matching
 */

import { Pool } from 'pg';
import { TextNormalizationService } from './text-normalization.service';

interface LocationCandidate {
  id: string;
  name: string;
  normalized_name: string;
  category: string;
  cohort: string;
  confidence: number;
  usage_count: number;
  is_verified: boolean;
}

interface MatchResult {
  location: LocationCandidate;
  similarity: number;
  matchReason: string;
}

export class LocationFuzzyMatchingService {
  private pool: Pool;
  private readonly SIMILARITY_THRESHOLD = 0.88; // 88% similarity required for match

  constructor(pool: Pool) {
    this.pool = pool;
  }

  /**
   * Find existing locations that match the input
   * 
   * Returns candidates sorted by similarity (highest first)
   * Only returns matches above SIMILARITY_THRESHOLD
   */
  async findMatches(
    universityId: string,
    locationName: string,
    category?: string
  ): Promise<MatchResult[]> {
    const normalizedInput = TextNormalizationService.normalizeForMatching(locationName);

    // Step 1: Exact match check (fastest)
    const exactMatch = await this.findExactMatch(universityId, normalizedInput);
    if (exactMatch) {
      return [
        {
          location: exactMatch,
          similarity: 1.0,
          matchReason: 'exact_match',
        },
      ];
    }

    // Step 2: Check aliases for exact match
    const aliasMatch = await this.findAliasMatch(universityId, normalizedInput);
    if (aliasMatch) {
      return [
        {
          location: aliasMatch,
          similarity: 1.0,
          matchReason: 'alias_match',
        },
      ];
    }

    // Step 3: Fetch all locations for this university (with category filter)
    const candidates = await this.fetchCandidates(universityId, category);

    // Step 4: Calculate similarity scores
    const scored = candidates.map(candidate => {
      const similarity = this.calculateSimilarity(locationName, candidate.name);
      return {
        location: candidate,
        similarity,
        matchReason: this.determineMatchReason(similarity),
      };
    });

    // Step 5: Filter and sort
    return scored
      .filter(result => result.similarity >= this.SIMILARITY_THRESHOLD)
      .sort((a, b) => b.similarity - a.similarity);
  }

  /**
   * Find exact normalized match
   */
  private async findExactMatch(
    universityId: string,
    normalizedName: string
  ): Promise<LocationCandidate | null> {
    const result = await this.pool.query(
      `SELECT * FROM campus_locations
       WHERE university_id = $1
       AND normalized_name = $2
       LIMIT 1`,
      [universityId, normalizedName]
    );

    return result.rows[0] || null;
  }

  /**
   * Find match via alias table
   */
  private async findAliasMatch(
    universityId: string,
    normalizedName: string
  ): Promise<LocationCandidate | null> {
    const result = await this.pool.query(
      `SELECT cl.* FROM campus_locations cl
       JOIN campus_location_aliases cla ON cla.campus_location_id = cl.id
       WHERE cl.university_id = $1
       AND cla.normalized_alias = $2
       LIMIT 1`,
      [universityId, normalizedName]
    );

    return result.rows[0] || null;
  }

  /**
   * Fetch candidate locations for fuzzy matching
   */
  private async fetchCandidates(
    universityId: string,
    category?: string
  ): Promise<LocationCandidate[]> {
    let query = `
      SELECT * FROM campus_locations
      WHERE university_id = $1
    `;
    const params: any[] = [universityId];

    if (category) {
      query += ` AND category = $2`;
      params.push(category);
    }

    query += ` ORDER BY usage_count DESC, confidence DESC LIMIT 100`;

    const result = await this.pool.query(query, params);
    return result.rows;
  }

  /**
   * Calculate composite similarity score
   * 
   * Combines multiple algorithms with weights
   */
  private calculateSimilarity(input: string, candidate: string): number {
    const normInput = TextNormalizationService.normalizeForMatching(input);
    const normCandidate = TextNormalizationService.normalizeForMatching(candidate);

    // Algorithm 1: Edit Distance (50% weight)
    const editSimilarity = TextNormalizationService.similarityRatio(normInput, normCandidate);

    // Algorithm 2: Trigram Similarity (30% weight)
    const trigramSimilarity = this.trigramSimilarity(normInput, normCandidate);

    // Algorithm 3: Token Overlap (20% weight)
    const tokenSimilarity = this.tokenOverlapSimilarity(normInput, normCandidate);

    // Weighted average
    const composite =
      editSimilarity * 0.5 +
      trigramSimilarity * 0.3 +
      tokenSimilarity * 0.2;

    // Bonus: Acronym match
    const inputAcronym = TextNormalizationService.extractAcronym(input);
    const candidateWords = normCandidate.split(/\s+/);
    if (inputAcronym.length >= 2 && candidateWords.some(word => word.startsWith(inputAcronym.toLowerCase()))) {
      return Math.min(1.0, composite + 0.1);
    }

    return composite;
  }

  /**
   * Trigram similarity (character n-grams)
   * 
   * Measures overlap of 3-character sequences
   */
  private trigramSimilarity(str1: string, str2: string): number {
    const trigrams1 = this.generateTrigrams(str1);
    const trigrams2 = this.generateTrigrams(str2);

    if (trigrams1.size === 0 && trigrams2.size === 0) return 1.0;
    if (trigrams1.size === 0 || trigrams2.size === 0) return 0.0;

    const intersection = new Set([...trigrams1].filter(x => trigrams2.has(x)));
    const union = new Set([...trigrams1, ...trigrams2]);

    return intersection.size / union.size;
  }

  /**
   * Generate trigrams from string
   */
  private generateTrigrams(str: string): Set<string> {
    const padded = `  ${str}  `; // Padding for edge trigrams
    const trigrams = new Set<string>();

    for (let i = 0; i < padded.length - 2; i++) {
      trigrams.add(padded.substring(i, i + 3));
    }

    return trigrams;
  }

  /**
   * Token overlap similarity (word-level)
   * 
   * Measures how many words are shared
   */
  private tokenOverlapSimilarity(str1: string, str2: string): number {
    const tokens1 = new Set(str1.split(/\s+/).filter(Boolean));
    const tokens2 = new Set(str2.split(/\s+/).filter(Boolean));

    if (tokens1.size === 0 && tokens2.size === 0) return 1.0;
    if (tokens1.size === 0 || tokens2.size === 0) return 0.0;

    const intersection = new Set([...tokens1].filter(x => tokens2.has(x)));
    const union = new Set([...tokens1, ...tokens2]);

    return intersection.size / union.size;
  }

  /**
   * Determine why a match was made
   */
  private determineMatchReason(similarity: number): string {
    if (similarity >= 0.98) return 'near_exact';
    if (similarity >= 0.95) return 'strong_match';
    if (similarity >= 0.90) return 'probable_match';
    return 'possible_match';
  }

  /**
   * Batch check if multiple inputs match a location
   * 
   * Used for AI-suggested aliases
   */
  async batchCheckAliases(
    universityId: string,
    locationId: string,
    aliases: string[]
  ): Promise<{ alias: string; matches: boolean; similarity: number }[]> {
    const location = await this.pool.query(
      `SELECT * FROM campus_locations WHERE id = $1`,
      [locationId]
    );

    if (location.rows.length === 0) {
      return aliases.map(alias => ({ alias, matches: false, similarity: 0 }));
    }

    const locationData = location.rows[0];

    return aliases.map(alias => {
      const similarity = this.calculateSimilarity(alias, locationData.name);
      return {
        alias,
        matches: similarity >= 0.85, // Slightly lower threshold for aliases
        similarity,
      };
    });
  }
}

