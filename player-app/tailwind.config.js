/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#0B1220',
        panel: '#121C2E',
        'panel-strong': '#17243A',
        surface: 'rgba(248,250,252,0.06)',
        'surface-hover': 'rgba(248,250,252,0.09)',
        chrome: '#3DA8FF',
        lms: { DEFAULT: '#F97316', dim: 'rgba(249,115,22,0.14)' },
        predictor: { DEFAULT: '#38BDF8', dim: 'rgba(56,189,248,0.14)' },
        success: '#22C55E',
        danger: '#EF4444',
        warning: '#FBBF24',
      },
      fontFamily: {
        sans: ['Inter', '-apple-system', 'system-ui', 'sans-serif'],
      },
      maxWidth: { app: '48rem' },
    },
  },
  plugins: [],
};
