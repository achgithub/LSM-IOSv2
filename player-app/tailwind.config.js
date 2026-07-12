/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#131B2E',
        panel: '#141B2C',
        'panel-strong': '#1B2438',
        surface: 'rgba(248,250,252,0.06)',
        'surface-hover': 'rgba(248,250,252,0.09)',
        chrome: '#3DA8FF',
        lms: { DEFAULT: '#F97316', dim: 'rgba(249,115,22,0.14)', deep: '#C2540A', text: '#1A0E04' },
        predictor: { DEFAULT: '#38BDF8', dim: 'rgba(56,189,248,0.14)' },
        killer: { DEFAULT: '#F43F5E', dim: 'rgba(244,63,94,0.14)' },
        success: '#34D399',
        danger: '#F87171',
        warning: '#FBBF24',
      },
      fontFamily: {
        sans: ['Inter', '-apple-system', 'system-ui', 'sans-serif'],
        display: ['Space Grotesk', 'Inter', '-apple-system', 'system-ui', 'sans-serif'],
      },
      maxWidth: { app: '48rem' },
    },
  },
  plugins: [],
};
