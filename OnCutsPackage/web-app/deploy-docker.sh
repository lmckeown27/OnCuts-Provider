#!/bin/bash

# CampusCuts Frontend - Complete Docker Deployment Script
# Builds and deploys the frontend application

set -e  # Exit on error

echo "════════════════════════════════════════════════════════"
echo "  🏆 CampusCuts Frontend - Docker Deployment"
echo "════════════════════════════════════════════════════════"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    echo "   Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

echo "✅ Docker is installed"
echo ""

# Check for .env file
if [ ! -f .env ]; then
    echo "⚠️  No .env file found!"
    echo ""
    echo "📝 Creating .env from env.example..."
    
    if [ -f env.example ]; then
        cp env.example .env
        echo "✅ Created .env file"
        echo ""
        echo "🔧 Please edit .env with your production values:"
        echo "   - VITE_API_URL"
        echo "   - VITE_APTOS_MODULE_ADDRESS"
        echo "   - VITE_STRIPE_PUBLISHABLE_KEY"
        echo ""
        read -p "Press Enter after updating .env to continue..."
    else
        echo "❌ env.example not found. Cannot create .env"
        exit 1
    fi
fi

# Load environment variables
echo "📦 Loading environment variables..."
export $(cat .env | grep -v '^#' | xargs)

echo "✅ Environment loaded"
echo ""
echo "🔨 Building Docker image..."
echo ""

# Build the image
./build-docker.sh

echo ""
echo "🧹 Cleaning up old containers..."

# Stop and remove old container
if [ "$(docker ps -aq -f name=campuscuts-frontend)" ]; then
    docker stop campuscuts-frontend || true
    docker rm campuscuts-frontend || true
    echo "✅ Old container removed"
else
    echo "✅ No old container to remove"
fi

echo ""
echo "🚀 Starting new container..."
echo ""

# Run the new container
./run-docker.sh

echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✅ Deployment Complete!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "🌐 Application URL: http://localhost"
echo ""
echo "📊 Useful Commands:"
echo "  View logs:    docker logs -f campuscuts-frontend"
echo "  Stop:         docker stop campuscuts-frontend"
echo "  Restart:      docker restart campuscuts-frontend"
echo "  Shell access: docker exec -it campuscuts-frontend sh"
echo ""
echo "🔍 Health check: curl http://localhost/health"
echo ""

