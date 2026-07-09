#!/bin/bash

# CampusCuts - Restore Original Files
# Restores the original App.tsx, tsconfig, and constants.ts from backups

set -e  # Exit on error

echo "🔄 Restoring original CampusCuts web-app files..."
echo ""

cd "$(dirname "$0")"

# Check if backups exist
if [ ! -f "src/App.tsx.backup" ]; then
    echo "❌ No backups found. Run ./fix-build.sh first."
    exit 1
fi

# Restore files
echo "📦 Restoring from backups..."
mv src/App.tsx.backup src/App.tsx
mv tsconfig.app.json.backup tsconfig.app.json
mv src/config/constants.ts.backup src/config/constants.ts

echo "✅ Original files restored"
echo ""
echo "The web-app has been restored to its original state."
echo ""
echo "To fix for minimal build again:"
echo "  ./fix-build.sh"
echo ""

