#!/bin/bash

# Start CampusCuts development environment

set -e

echo "🚀 Starting CampusCuts Development Environment"
echo "==============================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Docker is not running. Starting database with Docker...${NC}"
    echo "Please start Docker Desktop and run this script again."
    exit 1
fi

# Start database
echo -e "\n${BLUE}📊 Starting PostgreSQL database...${NC}"
docker-compose up -d postgres redis

echo "Waiting for database to be ready..."
sleep 5

# Check database health
until docker-compose exec -T postgres pg_isready -U postgres > /dev/null 2>&1; do
    echo "Waiting for database..."
    sleep 2
done

echo -e "${GREEN}✅ Database ready${NC}"

# Start backend in background
echo -e "\n${BLUE}🔧 Starting backend API...${NC}"
cd backend

if [ ! -d "node_modules" ]; then
    echo "Installing backend dependencies..."
    npm install
fi

# Start backend in a new terminal tab (macOS specific)
if [[ "$OSTYPE" == "darwin"* ]]; then
    osascript -e 'tell application "Terminal" to do script "cd '$(pwd)' && npm run dev"'
    echo -e "${GREEN}✅ Backend started in new terminal tab${NC}"
else
    # For Linux, just start in background
    npm run dev &
    BACKEND_PID=$!
    echo -e "${GREEN}✅ Backend started (PID: ${BACKEND_PID})${NC}"
fi

cd ..

# Instructions for iOS
echo -e "\n${BLUE}📱 iOS App:${NC}"
echo -e "   Open Xcode: ${YELLOW}open ios-app/CampusCuts.xcodeproj${NC}"
echo -e "   Or use: ${YELLOW}cd ios-app && pod install && open CampusCuts.xcworkspace${NC}"

echo -e "\n${GREEN}==============================================="
echo -e "✅ Development environment started!"
echo -e "===============================================${NC}"
echo -e "\nServices running:"
echo -e "  • PostgreSQL: localhost:5432"
echo -e "  • Redis: localhost:6379"
echo -e "  • Backend API: http://localhost:3000"
echo -e "\nAPI Health: ${YELLOW}http://localhost:3000/health${NC}"
echo -e "\nTo stop services:"
echo -e "  ${YELLOW}docker-compose down${NC}"
echo ""

