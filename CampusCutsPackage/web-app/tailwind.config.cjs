/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
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
      },
      fontFamily: {
        sans: ['"Source Serif 4"', 'Georgia', 'Cambria', '"Times New Roman"', 'serif'],
        serif: ['"Source Serif 4"', 'Georgia', 'Cambria', '"Times New Roman"', 'serif'],
      },
      animation: {
        'slide-down': 'slideDown 0.5s ease-out',
        'slide-up': 'slideUp 0.5s ease-out',
        'fade-in': 'fadeIn 0.3s ease-in',
        'scale-in': 'scaleIn 0.3s ease-out',
      },
      keyframes: {
        slideDown: {
          '0%': { opacity: '0', transform: 'translateY(-10px)', maxHeight: '0' },
          '100%': { opacity: '1', transform: 'translateY(0)', maxHeight: '1000px' },
        },
        slideUp: {
          '0%': { opacity: '1', transform: 'translateY(0)', maxHeight: '1000px' },
          '100%': { opacity: '0', transform: 'translateY(-10px)', maxHeight: '0' },
        },
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        scaleIn: {
          '0%': { opacity: '0', transform: 'scale(0.95)' },
          '100%': { opacity: '1', transform: 'scale(1)' },
        },
      },
      transitionProperty: {
        'height': 'height, max-height',
      },
    },
  },
  plugins: [],
}

