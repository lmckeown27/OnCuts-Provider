#!/bin/bash

# Deploy Aptos Smart Contracts Script

set -e

echo "🚀 Deploying CampusCuts Smart Contracts to Aptos"
echo "=================================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if Aptos CLI is installed
if ! command -v aptos &> /dev/null; then
    echo -e "${RED}❌ Aptos CLI not found${NC}"
    echo "Install with: curl -fsSL https://aptos.dev/scripts/install_cli.py | python3"
    exit 1
fi

# Navigate to contracts directory
cd "$(dirname "$0")/../contracts"

# Get network from argument or use devnet
NETWORK=${1:-devnet}
echo -e "${YELLOW}Target Network: ${NETWORK}${NC}"

# Compile contracts
echo -e "\n${YELLOW}📦 Compiling Move contracts...${NC}"
aptos move compile --skip-fetch-latest-git-deps

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Compilation successful${NC}"
else
    echo -e "${RED}❌ Compilation failed${NC}"
    exit 1
fi

# Run tests
echo -e "\n${YELLOW}🧪 Running tests...${NC}"
aptos move test --skip-fetch-latest-git-deps

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed${NC}"
else
    echo -e "${RED}❌ Tests failed${NC}"
    exit 1
fi

# Deploy to network
echo -e "\n${YELLOW}🌐 Deploying to ${NETWORK}...${NC}"

if [ "$NETWORK" = "mainnet" ]; then
    echo -e "${RED}⚠️  WARNING: Deploying to MAINNET${NC}"
    echo "Are you sure? (yes/no)"
    read -r CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Deployment cancelled"
        exit 0
    fi
fi

# Deploy (requires profile setup)
aptos move publish \
    --profile ${NETWORK} \
    --skip-fetch-latest-git-deps \
    --assume-yes

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✅ Deployment successful!${NC}"
    
    # Get deployed address
    DEPLOYED_ADDRESS=$(aptos config show-profiles | grep ${NETWORK} -A 3 | grep account | awk '{print $2}')
    echo -e "${GREEN}📍 Contract Address: ${DEPLOYED_ADDRESS}${NC}"
    
    # Initialize modules
    echo -e "\n${YELLOW}🔧 Initializing modules...${NC}"
    
    aptos move run \
        --profile ${NETWORK} \
        --function-id ${DEPLOYED_ADDRESS}::booking_system::initialize \
        --assume-yes
    
    aptos move run \
        --profile ${NETWORK} \
        --function-id ${DEPLOYED_ADDRESS}::review_system::initialize \
        --assume-yes
    
    aptos move run \
        --profile ${NETWORK} \
        --function-id ${DEPLOYED_ADDRESS}::barber_registry::initialize \
        --assume-yes
    
    aptos move run \
        --profile ${NETWORK} \
        --function-id ${DEPLOYED_ADDRESS}::payment_system::initialize \
        --assume-yes
    
    echo -e "${GREEN}✅ All modules initialized${NC}"
    
    echo -e "\n${GREEN}=================================================="
    echo -e "Deployment Complete!"
    echo -e "=================================================="
    echo -e "Network: ${NETWORK}"
    echo -e "Address: ${DEPLOYED_ADDRESS}"
    echo -e "\nUpdate backend/.env with:"
    echo -e "APTOS_PLATFORM_ADDRESS=${DEPLOYED_ADDRESS}"
    echo -e "APTOS_NETWORK=${NETWORK}${NC}"
    
else
    echo -e "${RED}❌ Deployment failed${NC}"
    exit 1
fi

