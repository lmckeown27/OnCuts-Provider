#!/bin/bash

# CampusCuts Service Worker Emergency Fix
# Run this when service workers are causing issues in development

echo "🚨 CampusCuts Service Worker Emergency Fix"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Clear Vite cache
echo "1️⃣  Clearing Vite cache..."
if [ -d "node_modules/.vite" ]; then
    rm -rf node_modules/.vite
    echo "   ✅ Cleared node_modules/.vite/"
else
    echo "   ℹ️  No Vite cache found"
fi

# Step 2: Clear build output
echo ""
echo "2️⃣  Clearing build output..."
if [ -d "dist" ]; then
    rm -rf dist/
    echo "   ✅ Cleared dist/"
else
    echo "   ℹ️  No build output found"
fi

# Step 3: Provide unregister instructions
echo ""
echo "3️⃣  Service Worker Unregistration Required"
echo "   ⚠️  You must manually unregister service workers in the browser"
echo ""
echo "   Option A: Use the cleanup page"
echo "   ┌────────────────────────────────────────────────┐"
echo "   │  1. Start dev server: npm run dev             │"
echo "   │  2. Open: http://localhost:3000/unregister-sw.html │"
echo "   │  3. Click 'Unregister All Service Workers'    │"
echo "   │  4. Click 'Clear All Caches'                  │"
echo "   └────────────────────────────────────────────────┘"
echo ""
echo "   Option B: Use DevTools"
echo "   ┌────────────────────────────────────────────────┐"
echo "   │  1. Open DevTools (F12)                       │"
echo "   │  2. Go to 'Application' tab                   │"
echo "   │  3. Click 'Service Workers' in sidebar        │"
echo "   │  4. Click 'Unregister' on all workers         │"
echo "   │  5. Click 'Storage' → 'Clear site data'       │"
echo "   └────────────────────────────────────────────────┘"
echo ""
echo "   Option C: Browser Console"
echo "   ┌────────────────────────────────────────────────┐"
echo "   │  Copy & paste this into browser console:      │"
echo "   │                                                │"
echo "   │  navigator.serviceWorker.getRegistrations()   │"
echo "   │    .then(regs => {                            │"
echo "   │      regs.forEach(reg => reg.unregister());   │"
echo "   │      console.log('Unregistered', regs.length);│"
echo "   │    });                                        │"
echo "   │  caches.keys().then(keys => {                 │"
echo "   │    Promise.all(keys.map(k => caches.delete(k)))│"
echo "   │      .then(() => console.log('Caches cleared'));│"
echo "   │  });                                          │"
echo "   └────────────────────────────────────────────────┘"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Local cache cleared!"
echo ""
echo "📝 After unregistering service workers:"
echo "   1. The app will auto-unregister them on next load"
echo "   2. Hard refresh: Cmd + Shift + R (Mac) or Ctrl + Shift + R (Windows)"
echo "   3. Restart dev server if needed: npm run dev"
echo ""
echo "💡 Pro tip: Keep DevTools open with 'Disable cache' checked"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

