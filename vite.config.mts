// vite.config.mts
/// <reference types="vitest" />
import { defineConfig } from 'vite';
import RubyPlugin from 'vite-plugin-ruby'; // Your existing plugin
import react from '@vitejs/plugin-react'; // You'll likely want this for React support in Vite and tests

export default defineConfig({
  plugins: [
    RubyPlugin(),
    react(), // Add the React plugin
  ],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './setupTests.ts', // Path to your setup file (adjust if different)
    // Optional: If you want to include .tsx files in your tests by default
    // include: ['**/*.{test,spec}.{js,mjs,cjs,ts,mts,jsx,tsx}'],
    css: true, // To handle CSS imports if your components import CSS files
  },
});
