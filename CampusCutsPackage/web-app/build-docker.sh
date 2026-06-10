#!/bin/bash

# CampusCuts Frontend - Docker Build Script
# Builds the Docker image with proper environment variables

set -e  # Exit on error

echo "🐳 Building CampusCuts Frontend Docker Image..."
echo ""

# Load environment variables from .env if it exists
if [ -f .env ]; then
    echo "✅ Loading environment variables from .env"
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "⚠️  No .env file found. Using default values."
    echo "   Copy env.example to .env and configure it for production."
fi

# Default values if not set
export VITE_API_URL=${VITE_API_URL:-http://localhost:3001/api/v1}
export VITE_API_BASE_URL=${VITE_API_BASE_URL:-http://localhost:3001}
export VITE_WS_URL=${VITE_WS_URL:-ws://localhost:3001}
export VITE_APTOS_NETWORK=${VITE_APTOS_NETWORK:-devnet}
export VITE_APTOS_NODE_URL=${VITE_APTOS_NODE_URL:-https://fullnode.devnet.aptoslabs.com/v1}
export VITE_APP_NAME=${VITE_APP_NAME:-CampusCuts}
export VITE_APP_VERSION=${VITE_APP_VERSION:-1.0.0}

echo ""
echo "📦 Build Configuration:"
echo "  API URL: $VITE_API_URL"
echo "  WebSocket: $VITE_WS_URL"
echo "  Aptos Network: $VITE_APTOS_NETWORK"
echo "  App Version: $VITE_APP_VERSION"
echo ""

# Build the image
docker build \
  --build-arg VITE_API_URL="$VITE_API_URL" \
  --build-arg VITE_API_BASE_URL="$VITE_API_BASE_URL" \
  --build-arg VITE_WS_URL="$VITE_WS_URL" \
  --build-arg VITE_APTOS_NETWORK="$VITE_APTOS_NETWORK" \
  --build-arg VITE_APTOS_NODE_URL="$VITE_APTOS_NODE_URL" \
  --build-arg VITE_APTOS_MODULE_ADDRESS="$VITE_APTOS_MODULE_ADDRESS" \
  --build-arg VITE_STRIPE_PUBLISHABLE_KEY="$VITE_STRIPE_PUBLISHABLE_KEY" \
  --build-arg VITE_APP_NAME="$VITE_APP_NAME" \
  --build-arg VITE_APP_VERSION="$VITE_APP_VERSION" \
  -t campuscuts-frontend:latest \
  -t campuscuts-frontend:${VITE_APP_VERSION} \
  .

echo ""
echo "✅ Docker image built successfully!"
echo ""
echo "🚀 Run the container with:"
echo "   docker run -d -p 80:80 --name campuscuts-frontend campuscuts-frontend:latest"
echo ""
echo "🔍 Or use docker-compose:"
echo "   docker-compose up -d frontend"

