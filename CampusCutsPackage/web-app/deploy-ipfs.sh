#!/bin/bash

# CampusCuts Web App - IPFS Deployment Script

echo "🚀 Deploying CampusCuts Web App to IPFS..."

# Build the application
echo "📦 Building application..."
npm run build

# Check if IPFS is installed
if ! command -v ipfs &> /dev/null; then
    echo "❌ IPFS is not installed. Please install IPFS first."
    echo "Visit: https://docs.ipfs.tech/install/"
    exit 1
fi

# Add dist folder to IPFS
echo "📤 Adding build files to IPFS..."
IPFS_HASH=$(ipfs add -r dist | tail -n 1 | awk '{print $2}')

if [ -z "$IPFS_HASH" ]; then
    echo "❌ Failed to add files to IPFS"
    exit 1
fi

echo "✅ Successfully deployed to IPFS!"
echo "📍 IPFS Hash: $IPFS_HASH"
echo "🌐 Access via:"
echo "   - IPFS Gateway: https://ipfs.io/ipfs/$IPFS_HASH"
echo "   - Cloudflare IPFS: https://cloudflare-ipfs.com/ipfs/$IPFS_HASH"
echo "   - Local Gateway: http://localhost:8080/ipfs/$IPFS_HASH"
echo ""
echo "💡 To pin this hash on Pinata or other services, use:"
echo "   IPFS Hash: $IPFS_HASH"

# Optional: Pin to local IPFS node
read -p "📌 Pin to local IPFS node? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ipfs pin add $IPFS_HASH
    echo "✅ Pinned to local IPFS node"
fi

# Save hash to file for reference
echo $IPFS_HASH > .ipfs-hash
echo "💾 IPFS hash saved to .ipfs-hash"

