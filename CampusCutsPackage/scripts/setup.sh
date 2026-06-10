#!/bin/bash

# CampusCuts Setup Script
# This script sets up the development environment

set -e

echo "🚀 CampusCuts Setup Script"
echo "================================"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js not found. Please install Node.js 18+${NC}"
    exit 1
else
    NODE_VERSION=$(node -v)
    echo -e "${GREEN}✅ Node.js ${NODE_VERSION}${NC}"
fi

# Check npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}❌ npm not found${NC}"
    exit 1
else
    NPM_VERSION=$(npm -v)
    echo -e "${GREEN}✅ npm ${NPM_VERSION}${NC}"
fi

# Check PostgreSQL
if ! command -v psql &> /dev/null; then
    echo -e "${YELLOW}⚠️  PostgreSQL CLI not found. Install or use Docker${NC}"
else
    PSQL_VERSION=$(psql --version)
    echo -e "${GREEN}✅ ${PSQL_VERSION}${NC}"
fi

# Check Aptos CLI
if ! command -v aptos &> /dev/null; then
    echo -e "${YELLOW}⚠️  Aptos CLI not found${NC}"
    echo "Install with: curl -fsSL https://aptos.dev/scripts/install_cli.py | python3"
else
    echo -e "${GREEN}✅ Aptos CLI installed${NC}"
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}⚠️  Docker not found (optional)${NC}"
else
    echo -e "${GREEN}✅ Docker installed${NC}"
fi

# Setup Backend
echo -e "\n${YELLOW}Setting up backend...${NC}"
cd backend

if [ ! -f .env ]; then
    echo "Creating .env file from example..."
    cp .env.example .env
    echo -e "${GREEN}✅ .env created. Please update with your credentials!${NC}"
else
    echo -e "${GREEN}✅ .env already exists${NC}"
fi

echo "Installing backend dependencies..."
npm install
echo -e "${GREEN}✅ Backend dependencies installed${NC}"

cd ..

# Setup Smart Contracts
echo -e "\n${YELLOW}Setting up Aptos smart contracts...${NC}"
cd contracts

if command -v aptos &> /dev/null; then
    echo "Compiling Move contracts..."
    aptos move compile --skip-fetch-latest-git-deps || echo -e "${YELLOW}⚠️  Compile failed. Check contracts/sources/${NC}"
    
    echo "Running Move tests..."
    aptos move test --skip-fetch-latest-git-deps || echo -e "${YELLOW}⚠️  Tests failed${NC}"
    
    echo -e "${GREEN}✅ Smart contracts setup complete${NC}"
else
    echo -e "${YELLOW}⚠️  Skipping contract compilation (Aptos CLI not installed)${NC}"
fi

cd ..

# Setup iOS App (if on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "\n${YELLOW}Setting up iOS app...${NC}"
    cd ios-app
    
    if command -v pod &> /dev/null; then
        echo "Installing CocoaPods dependencies..."
        pod install
        echo -e "${GREEN}✅ iOS dependencies installed${NC}"
    else
        echo -e "${YELLOW}⚠️  CocoaPods not installed. Run: sudo gem install cocoapods${NC}"
    fi
    
    cd ..
else
    echo -e "${YELLOW}⚠️  Skipping iOS setup (not on macOS)${NC}"
fi

# Setup Database (if Docker is available)
echo -e "\n${YELLOW}Would you like to start the database with Docker? (y/n)${NC}"
read -r START_DB

if [ "$START_DB" = "y" ]; then
    echo "Starting PostgreSQL with Docker Compose..."
    docker-compose up -d postgres
    echo "Waiting for database to be ready..."
    sleep 5
    echo -e "${GREEN}✅ Database started${NC}"
    
    echo "Running database migrations..."
    docker-compose exec postgres psql -U postgres -d campuscuts -f /docker-entrypoint-initdb.d/schema.sql || echo -e "${YELLOW}⚠️  Schema already applied${NC}"
fi

# Final instructions
echo -e "\n${GREEN}================================${NC}"
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo -e "\nNext steps:"
echo -e "1. Update ${YELLOW}backend/.env${NC} with your credentials"
echo -e "2. Start backend: ${YELLOW}cd backend && npm run dev${NC}"
echo -e "3. Deploy contracts: ${YELLOW}cd contracts && ./deploy.sh${NC}"
echo -e "4. Open iOS app in Xcode: ${YELLOW}open ios-app/CampusCuts.xcodeproj${NC}"
echo -e "\nDocumentation: ${YELLOW}docs/MVP_SPECIFICATION.md${NC}"
echo ""

