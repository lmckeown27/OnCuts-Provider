#!/bin/bash

# CampusCuts Frontend - Docker Run Script
# Runs the Docker container with proper configuration

set -e  # Exit on error

echo "🚀 Starting CampusCuts Frontend Container..."
echo ""

# Stop and remove existing container if running
if [ "$(docker ps -aq -f name=campuscuts-frontend)" ]; then
    echo "🛑 Stopping existing container..."
    docker stop campuscuts-frontend || true
    docker rm campuscuts-frontend || true
fi

# Run the container
docker run -d \
  --name campuscuts-frontend \
  --restart unless-stopped \
  -p 80:80 \
  campuscuts-frontend:latest

echo ""
echo "✅ Container started successfully!"
echo ""
echo "📊 Container Status:"
docker ps | grep campuscuts-frontend

echo ""
echo "🌐 Access the application at:"
echo "   http://localhost"
echo ""
echo "📝 View logs with:"
echo "   docker logs -f campuscuts-frontend"
echo ""
echo "🛑 Stop the container with:"
echo "   docker stop campuscuts-frontend"

