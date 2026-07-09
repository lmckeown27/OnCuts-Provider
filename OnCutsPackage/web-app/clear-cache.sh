#!/bin/bash

# CampusCuts Development Cache Cleaner
# Run this script when you encounter stale code issues

echo "🧹 CampusCuts Cache Cleaner"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if we're in the web-app directory
if [ ! -f "package.json" ]; then
    echo "❌ Error: Please run this script from the web-app directory"
    echo "   cd web-app && ./clear-cache.sh"
    exit 1
fi

echo "1️⃣  Clearing Vite dependency cache..."
if [ -d "node_modules/.vite" ]; then
    rm -rf node_modules/.vite
    echo "   ✅ Cleared node_modules/.vite/"
else
    echo "   ℹ️  No Vite cache found (already clean)"
fi

echo ""
echo "2️⃣  Clearing build output..."
if [ -d "dist" ]; then
    rm -rf dist/
    echo "   ✅ Cleared dist/"
else
    echo "   ℹ️  No build output found (already clean)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Cache cleared successfully!"
echo ""
echo "📝 Next steps:"
echo "   1. Restart the dev server: npm run dev"
echo "   2. Hard refresh browser: Cmd + Shift + R (Mac) or Ctrl + Shift + R (Windows)"
echo "   3. Or: Open DevTools → Right-click refresh → 'Empty Cache and Hard Reload'"
echo ""
echo "💡 Pro tip: Keep DevTools open with 'Disable cache' checked to prevent future issues"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

