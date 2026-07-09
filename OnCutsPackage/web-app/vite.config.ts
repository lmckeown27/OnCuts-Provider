import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  
  server: {
    port: 3000,
    
    // Hot Module Replacement for instant updates
    hmr: true,
    
    // Better file watching
    watch: {
      usePolling: true,  // Use polling for more reliable file watching
      interval: 100,     // Check for changes every 100ms
    },
    
    // Force browser to not cache during development
    headers: {
      'Cache-Control': 'no-store',
    },
  },
  
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@assets': path.resolve(__dirname, './src/assets'),
      '@components': path.resolve(__dirname, './src/components'),
      '@pages': path.resolve(__dirname, './src/pages'),
      '@services': path.resolve(__dirname, './src/services'),
      '@store': path.resolve(__dirname, './src/store'),
      '@types': path.resolve(__dirname, './src/types'),
      '@config': path.resolve(__dirname, './src/config'),
    },
  },
  
  // Production optimizations
  build: {
    // Code splitting for better performance
    rollupOptions: {
      output: {
        // Split vendor chunks for optimal caching and loading
        manualChunks(id) {
          // React core - changes rarely, cache long-term
          if (id.includes('node_modules/react') || 
              id.includes('node_modules/react-dom') || 
              id.includes('node_modules/react-router')) {
            return 'react-vendor';
          }
          
          // UI libraries
          if (id.includes('node_modules/lucide-react')) {
            return 'icons';
          }
          
          if (id.includes('node_modules/react-hot-toast')) {
            return 'toast';
          }
          
          // React Query
          if (id.includes('node_modules/@tanstack')) {
            return 'query-vendor';
          }
          
          // Socket.io for real-time messaging
          if (id.includes('node_modules/socket.io')) {
            return 'socket';
          }
          
          // Date/time utilities
          if (id.includes('node_modules/date-fns') || id.includes('node_modules/dayjs')) {
            return 'date-utils';
          }
          
          // AWS SDK (if used for S3)
          if (id.includes('node_modules/@aws-sdk')) {
            return 'aws-sdk';
          }
          
          // Admin pages - lazy loaded, separate chunk
          if (id.includes('/pages/admin/')) {
            return 'admin-pages';
          }
        },
      },
    },
    
    // Chunk size warnings
    chunkSizeWarningLimit: 500, // Warn if chunk > 500KB
    
    // Minification
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: true, // Remove console.logs in production
        drop_debugger: true,
      },
    },
    
    // Source maps (only in dev)
    sourcemap: false,
  },
  
  // Optimize dependencies
  optimizeDeps: {
    include: [
      'react',
      'react-dom',
      'react-router-dom',
      '@tanstack/react-query',
    ],
    // Force re-bundle dependencies on server start if needed
    // Set to true temporarily if you encounter caching issues
    force: false,
  },
})
