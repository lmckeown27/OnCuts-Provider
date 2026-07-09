#!/bin/bash

# Initialize Aptos CLI profiles for different networks

set -e

echo "🔧 Aptos Profile Setup for CampusCuts"
echo "======================================"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to create profile
create_profile() {
    local NETWORK=$1
    local NODE_URL=$2
    
    echo -e "\n${YELLOW}Setting up ${NETWORK} profile...${NC}"
    
    # Check if profile exists
    if aptos config show-profiles | grep -q "^${NETWORK}"; then
        echo -e "${YELLOW}⚠️  Profile ${NETWORK} already exists${NC}"
        echo "Do you want to overwrite? (yes/no)"
        read -r CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            echo "Skipping ${NETWORK}"
            return
        fi
    fi
    
    # Initialize profile
    aptos init --profile ${NETWORK} --network ${NETWORK} --assume-yes
    
    # Fund account if testnet/devnet
    if [ "$NETWORK" = "devnet" ] || [ "$NETWORK" = "testnet" ]; then
        echo "Funding ${NETWORK} account..."
        aptos account fund-with-faucet --profile ${NETWORK}
        
        # Check balance
        BALANCE=$(aptos account list --profile ${NETWORK} | grep "coin" | head -1)
        echo -e "${GREEN}✅ Account funded: ${BALANCE}${NC}"
    fi
    
    # Get address
    ADDRESS=$(aptos config show-profiles | grep ${NETWORK} -A 3 | grep account | awk '{print $2}')
    PRIVATE_KEY=$(aptos config show-profiles | grep ${NETWORK} -A 3 | grep private_key | awk '{print $2}')
    
    echo -e "${GREEN}✅ ${NETWORK} profile created${NC}"
    echo -e "   Address: ${ADDRESS}"
    echo -e "   Private Key: ${PRIVATE_KEY}"
    
    # Save to .env template
    echo "" >> ../.env.aptos.${NETWORK}
    echo "# ${NETWORK} Configuration" >> ../.env.aptos.${NETWORK}
    echo "APTOS_NETWORK=${NETWORK}" >> ../.env.aptos.${NETWORK}
    echo "APTOS_PLATFORM_ADDRESS=${ADDRESS}" >> ../.env.aptos.${NETWORK}
    echo "APTOS_PLATFORM_PRIVATE_KEY=${PRIVATE_KEY}" >> ../.env.aptos.${NETWORK}
    echo "APTOS_NODE_URL=${NODE_URL}" >> ../.env.aptos.${NETWORK}
}

# Create profiles for different networks
create_profile "devnet" "https://fullnode.devnet.aptoslabs.com/v1"
create_profile "testnet" "https://fullnode.testnet.aptoslabs.com/v1"

echo -e "\n${GREEN}======================================"
echo -e "✅ Profile setup complete!"
echo -e "======================================${NC}"
echo -e "\nProfiles created:"
echo -e "  • devnet  (for development)"
echo -e "  • testnet (for testing)"
echo -e "\nConfiguration files created:"
echo -e "  • .env.aptos.devnet"
echo -e "  • .env.aptos.testnet"
echo -e "\nCopy the appropriate values to ${YELLOW}backend/.env${NC}"
echo ""

