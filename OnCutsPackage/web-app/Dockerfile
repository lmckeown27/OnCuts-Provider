# Production Dockerfile for CampusCuts Frontend

# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /app

# Build arguments for environment variables
ARG VITE_API_URL
ARG VITE_API_BASE_URL
ARG VITE_WS_URL
ARG VITE_APTOS_NETWORK
ARG VITE_APTOS_NODE_URL
ARG VITE_APTOS_MODULE_ADDRESS
ARG VITE_STRIPE_PUBLISHABLE_KEY
ARG VITE_APP_NAME
ARG VITE_APP_VERSION

# Set as environment variables for build
ENV VITE_API_URL=$VITE_API_URL
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
ENV VITE_WS_URL=$VITE_WS_URL
ENV VITE_APTOS_NETWORK=$VITE_APTOS_NETWORK
ENV VITE_APTOS_NODE_URL=$VITE_APTOS_NODE_URL
ENV VITE_APTOS_MODULE_ADDRESS=$VITE_APTOS_MODULE_ADDRESS
ENV VITE_STRIPE_PUBLISHABLE_KEY=$VITE_STRIPE_PUBLISHABLE_KEY
ENV VITE_APP_NAME=$VITE_APP_NAME
ENV VITE_APP_VERSION=$VITE_APP_VERSION

# Copy package files
COPY package*.json ./

# Install dependencies (including dev deps for build)
RUN npm ci --legacy-peer-deps

# Copy source code
COPY . .

# Build for production
RUN npm run build

# Stage 2: Serve with Nginx
FROM nginx:alpine

# Copy built assets
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Create non-root user
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

USER nginx

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
