/**
 * CampusCut Color System
 * Based on CampusKinect design system
 * 
 * Primary: Olive Green (#708d81)
 * Background: Grey (#525252)
 * Semantic: Standard success/warning/error/info
 */

export const colors = {
  primary: {
    DEFAULT: '#708d81',
    50: '#f2f5f4',
    100: '#e6ebea',
    200: '#bfcdc8',
    300: '#99afa7',
    400: '#708d81',
    500: '#5a7268',
    600: '#445750',
    700: '#2e3c38',
    800: '#172120',
    900: '#0b1110',
  },
  neutral: {
    50: '#fafafa',
    100: '#f5f5f5',
    200: '#e5e5e5',
    300: '#d4d4d4',
    400: '#a3a3a3',
    500: '#737373',
    600: '#525252',
    700: '#404040',
    800: '#262626',
    900: '#171717',
  },
  olive: {
    DEFAULT: '#708d81',
    50: '#f2f5f4',
    100: '#e6ebea',
    200: '#bfcdc8',
    300: '#99afa7',
    400: '#708d81',
    500: '#5a7268',
    600: '#445750',
    700: '#2e3c38',
    800: '#172120',
    900: '#0b1110',
  },
  semantic: {
    primary: '#708d81',
    success: '#22c55e',
    warning: '#f59e0b',
    error: '#ef4444',
    info: '#3b82f6',
  },
} as const;

// Commonly used combinations
export const colorCombinations = {
  primaryButton: {
    bg: colors.primary[400],
    hoverBg: colors.primary[500],
    activeBg: colors.primary[600],
    text: '#ffffff',
  },
  secondaryButton: {
    bg: colors.neutral[200],
    hoverBg: colors.neutral[300],
    text: colors.neutral[900],
  },
  mainBackground: {
    bg: colors.neutral[600],
    text: '#ffffff',
  },
  cardBackground: {
    bg: colors.neutral[700],
    text: '#ffffff',
  },
} as const;

export default colors;

