#!/bin/bash

# CampusCuts Vercel Deployment Script
# This script automates frontend deployment to Vercel

set -e  # Exit on error

echo "🚀 CampusCuts Vercel Deployment"
echo "================================"
echo ""

# Check if Vercel CLI is installed
if ! command -v vercel &> /dev/null; then
    echo "❌ Vercel CLI not found. Installing..."
    npm install -g vercel
fi

# Login to Vercel
echo "🔐 Logging into Vercel..."
vercel login

cd web-app

# Deploy to production
echo "📤 Deploying to Vercel..."
vercel --prod

echo ""
read -p "Backend API URL (e.g., https://api.campuscuts.com): " API_URL

# Set environment variables
echo "🔧 Setting environment variables..."
vercel env add VITE_API_URL production
echo "$API_URL"

echo ""
echo "✅ Frontend deployed successfully!"
echo ""
echo "Next steps:"
echo "1. Setup custom domain in Vercel dashboard"
echo "2. Visit https://vercel.com/dashboard to manage your project"
echo "3. Test your app at: https://campuscuts.vercel.app"
echo ""



