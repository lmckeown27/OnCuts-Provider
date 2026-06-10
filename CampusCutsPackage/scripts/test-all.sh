#!/bin/bash

# Run all tests for CampusCuts

set -e

echo "🧪 Running CampusCuts Test Suite"
echo "================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

FAILED=0

# Test Smart Contracts
echo -e "\n${YELLOW}1. Testing Move Smart Contracts...${NC}"
cd contracts

if command -v aptos &> /dev/null; then
    if aptos move test --skip-fetch-latest-git-deps; then
        echo -e "${GREEN}✅ Smart contract tests passed${NC}"
    else
        echo -e "${RED}❌ Smart contract tests failed${NC}"
        FAILED=1
    fi
else
    echo -e "${YELLOW}⚠️  Aptos CLI not found, skipping contract tests${NC}"
fi

cd ..

# Test Backend
echo -e "\n${YELLOW}2. Testing Backend API...${NC}"
cd backend

if [ -d "node_modules" ]; then
    if npm test; then
        echo -e "${GREEN}✅ Backend tests passed${NC}"
    else
        echo -e "${RED}❌ Backend tests failed${NC}"
        FAILED=1
    fi
else
    echo -e "${YELLOW}⚠️  Backend dependencies not installed, skipping tests${NC}"
fi

cd ..

# Lint Backend
echo -e "\n${YELLOW}3. Linting Backend...${NC}"
cd backend

if npm run lint; then
    echo -e "${GREEN}✅ Lint passed${NC}"
else
    echo -e "${RED}❌ Lint failed${NC}"
    FAILED=1
fi

cd ..

# Test iOS App (if on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "\n${YELLOW}4. Testing iOS App...${NC}"
    cd ios-app
    
    if [ -f "CampusCuts.xcworkspace" ]; then
        xcodebuild test \
            -workspace CampusCuts.xcworkspace \
            -scheme CampusCuts \
            -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0' \
            || echo -e "${RED}❌ iOS tests failed${NC}" && FAILED=1
    else
        echo -e "${YELLOW}⚠️  Xcode workspace not found, skipping iOS tests${NC}"
    fi
    
    cd ..
else
    echo -e "${YELLOW}⚠️  Skipping iOS tests (not on macOS)${NC}"
fi

# Summary
echo -e "\n================================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi

