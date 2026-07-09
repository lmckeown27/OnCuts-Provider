/**
 * Text Normalization Service
 * 
 * Purpose: Deterministic text normalization for deduplication
 * Strategy: Aggressive normalization for matching, preserve original for display
 * 
 * Use Cases:
 * - Campus location deduplication
 * - Fuzzy matching preparation
 * - Alias comparison
 */

export class TextNormalizationService {
  /**
   * Normalize text for deduplication matching
   * 
   * Steps:
   * 1. Convert to lowercase
   * 2. Remove diacritics/accents
   * 3. Remove punctuation
   * 4. Collapse whitespace
   * 5. Trim edges
   * 
   * Examples:
   * "Yakʔitʸuʸu Hall" → "yakit yutyu hall"
   * "Sierra Madre Dorm" → "sierra madre dorm"
   * "PCV (Poly Canyon Village)" → "pcv poly canyon village"
   */
  static normalizeForMatching(text: string): string {
    if (!text) return '';

    return text
      .toLowerCase()
      .normalize('NFD') // Decompose accented characters
      .replace(/[\u0300-\u036f]/g, '') // Remove diacritics
      .replace(/[^\w\s]/g, ' ') // Replace punctuation with space
      .replace(/\s+/g, ' ') // Collapse multiple spaces
      .trim();
  }

  /**
   * Normalize for display (preserve more formatting)
   * 
   * Steps:
   * 1. Trim whitespace
   * 2. Collapse multiple spaces
   * 3. Capitalize first letter of each word
   * 
   * Examples:
   * "yakʔitʸuʸu hall" → "Yakʔitʸuʸu Hall"
   * "  sierra   madre  " → "Sierra Madre"
   */
  static normalizeForDisplay(text: string): string {
    if (!text) return '';

    return text
      .trim()
      .replace(/\s+/g, ' ')
      .split(' ')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
      .join(' ');
  }

  /**
   * Extract acronym from text
   * 
   * Examples:
   * "Poly Canyon Village" → "PCV"
   * "Cerro Vista Apartments" → "CVA"
   */
  static extractAcronym(text: string): string {
    if (!text) return '';

    return text
      .split(/\s+/)
      .map(word => word.charAt(0).toUpperCase())
      .join('');
  }

  /**
   * Generate search tokens for full-text search
   * 
   * Returns array of searchable substrings
   * 
   * Example:
   * "Yak Yit Dorm" → ["yak", "yit", "dorm", "yak yit", "yit dorm", "yak yit dorm"]
   */
  static generateSearchTokens(text: string): string[] {
    const normalized = this.normalizeForMatching(text);
    const words = normalized.split(/\s+/).filter(Boolean);
    const tokens: string[] = [...words];

    // Add bigrams
    for (let i = 0; i < words.length - 1; i++) {
      tokens.push(`${words[i]} ${words[i + 1]}`);
    }

    // Add full phrase
    if (words.length > 1) {
      tokens.push(words.join(' '));
    }

    // Add acronym
    if (words.length > 1) {
      const acronym = words.map(w => w.charAt(0)).join('');
      if (acronym.length >= 2) {
        tokens.push(acronym);
      }
    }

    return Array.from(new Set(tokens)); // Deduplicate
  }

  /**
   * Clean location name for database storage
   * 
   * Less aggressive than normalizeForMatching
   * Preserves unicode characters for display
   */
  static cleanLocationName(text: string): string {
    if (!text) return '';

    return text
      .trim()
      .replace(/\s+/g, ' ')
      .replace(/[<>]/g, ''); // Remove only dangerous HTML chars
  }

  /**
   * Check if two normalized strings are likely the same
   * 
   * Quick equality check before expensive fuzzy matching
   */
  static areExactMatch(text1: string, text2: string): boolean {
    const norm1 = this.normalizeForMatching(text1);
    const norm2 = this.normalizeForMatching(text2);
    return norm1 === norm2;
  }

  /**
   * Get edit distance between two strings (Levenshtein)
   * 
   * Used for similarity scoring
   */
  static editDistance(str1: string, str2: string): number {
    const m = str1.length;
    const n = str2.length;
    const dp: number[][] = Array(m + 1)
      .fill(null)
      .map(() => Array(n + 1).fill(0));

    for (let i = 0; i <= m; i++) dp[i][0] = i;
    for (let j = 0; j <= n; j++) dp[0][j] = j;

    for (let i = 1; i <= m; i++) {
      for (let j = 1; j <= n; j++) {
        if (str1[i - 1] === str2[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] = Math.min(
            dp[i - 1][j] + 1,     // deletion
            dp[i][j - 1] + 1,     // insertion
            dp[i - 1][j - 1] + 1  // substitution
          );
        }
      }
    }

    return dp[m][n];
  }

  /**
   * Calculate similarity ratio (0.0 to 1.0)
   * 
   * 1.0 = identical
   * 0.0 = completely different
   */
  static similarityRatio(str1: string, str2: string): number {
    const norm1 = this.normalizeForMatching(str1);
    const norm2 = this.normalizeForMatching(str2);

    if (norm1 === norm2) return 1.0;
    if (!norm1 || !norm2) return 0.0;

    const maxLen = Math.max(norm1.length, norm2.length);
    const distance = this.editDistance(norm1, norm2);

    return 1 - (distance / maxLen);
  }
}

