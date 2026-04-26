#!/bin/bash
#
# rebuild.sh — Rebuild and restart Echo stack after code changes
#
# Usage:
#   ./scripts/rebuild.sh
#
# This script:
#   1. Rebuilds all Echo service images (EchoService, EchoWeb, EchoMedia, etc.)
#   2. Restarts containers with the new code
#   3. Shows final status and health
#

set -e

ORCHESTRATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "📦 Rebuilding Echo stack from: $ORCHESTRATOR_DIR"
echo

cd "$ORCHESTRATOR_DIR"

# Rebuild and restart
echo "▶️  Running: docker compose up -d --build"
docker compose up -d --build

echo
echo "✅ Rebuild complete. Checking status..."
echo

# Show final status
docker compose ps

echo
echo "📊 Health check:"
docker compose ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(healthy|healthy|unhealthy)" || echo "(checking...)"

echo
echo "💡 To view logs:"
echo "   docker compose logs -f"
echo
echo "💡 To stop the stack:"
echo "   docker compose down"
echo
