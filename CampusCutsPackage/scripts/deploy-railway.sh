#!/bin/bash

# CampusCuts Railway Deployment Script
# This script automates the deployment process to Railway

set -e  # Exit on error

echo "🚀 CampusCuts Railway Deployment"
echo "================================="
echo ""

# Check if Railway CLI is installed
if ! command -v railway &> /dev/null; then
    echo "❌ Railway CLI not found. Installing..."
    npm install -g @railway/cli
fi

# Login to Railway
echo "🔐 Logging into Railway..."
railway login

# Check if project is already linked
if [ ! -f ".railway" ]; then
    echo "📦 Creating new Railway project..."
    railway init
else
    echo "✅ Project already linked to Railway"
fi

# Add PostgreSQL if not already added
echo "🗄️  Setting up PostgreSQL..."
railway add --database postgres || echo "✅ PostgreSQL already exists"

# Set environment variables
echo "🔧 Setting environment variables..."
echo ""
echo "Please provide the following values:"
echo ""

read -p "APTOS_PLATFORM_PRIVATE_KEY: " APTOS_KEY
railway variables set APTOS_PLATFORM_PRIVATE_KEY="$APTOS_KEY"

read -p "STRIPE_SECRET_KEY: " STRIPE_KEY
railway variables set STRIPE_SECRET_KEY="$STRIPE_KEY"

read -p "CIRCLE_API_KEY: " CIRCLE_KEY
railway variables set CIRCLE_API_KEY="$CIRCLE_KEY"

read -p "GAS_WALLET_PRIVATE_KEY (or press Enter to use APTOS key): " GAS_KEY
if [ -z "$GAS_KEY" ]; then
    railway variables set GAS_WALLET_PRIVATE_KEY="$APTOS_KEY"
else
    railway variables set GAS_WALLET_PRIVATE_KEY="$GAS_KEY"
fi

# Set other required variables
railway variables set NODE_ENV=production
railway variables set APTOS_NETWORK=mainnet
railway variables set APTOS_NODE_URL=https://fullnode.mainnet.aptoslabs.com/v1

echo ""
echo "✅ Environment variables configured"

# Deploy backend
echo "📤 Deploying backend to Railway..."
cd backend
railway up

# Get the backend URL
BACKEND_URL=$(railway domain)
echo ""
echo "✅ Backend deployed to: $BACKEND_URL"

# Run database migrations
echo "🔄 Running database migrations..."
railway run npx prisma migrate deploy

echo ""
echo "🎉 Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Visit your Railway dashboard to monitor the deployment"
echo "2. Setup custom domain: railway domain add api.campuscuts.com"
echo "3. Deploy frontend to Vercel with VITE_API_URL=$BACKEND_URL"
echo "4. Fund gas wallet: curl $BACKEND_URL/api/admin/gas-wallet/status"
echo ""



