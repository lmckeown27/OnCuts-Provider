#!/usr/bin/env bash
# Run Sui relayer smoke test from repo root (CampusCuts/).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/backend"
exec npx ts-node test-payout.ts "$@"
