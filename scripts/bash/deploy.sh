#!/bin/bash
# deploy.sh
# Stop production, publish new version, start production
# This is the main deployment script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(dirname "$0")"

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  KHAOS - DEPLOY                                   ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# What to deploy
DEPLOY_WEB=false
DEPLOY_API=false

case "${1:-all}" in
    web)
        DEPLOY_WEB=true
        ;;
    api)
        DEPLOY_API=true
        ;;
    all|"")
        DEPLOY_WEB=true
        DEPLOY_API=true
        ;;
    *)
        echo "Usage: $0 [web|api|all]"
        exit 1
        ;;
esac

# ============================================================================
# Step 1: Stop production apps
# ============================================================================
echo -e "${YELLOW}Step 1: Stopping production apps...${NC}"

if [ "$DEPLOY_API" = true ]; then
    "$SCRIPT_DIR/prod-stop.sh" api 2>/dev/null || true
fi

if [ "$DEPLOY_WEB" = true ]; then
    # Web is static files, nothing to stop
    echo -e "  Web: static files (nothing to stop)"
fi

# ============================================================================
# Step 2: Publish new version
# ============================================================================
echo ""
echo -e "${YELLOW}Step 2: Publishing new version...${NC}"

if [ "$DEPLOY_API" = true ]; then
    "$SCRIPT_DIR/publish.sh" api
fi

if [ "$DEPLOY_WEB" = true ]; then
    "$SCRIPT_DIR/publish.sh" web
fi

# ============================================================================
# Step 3: Start production apps
# ============================================================================
echo ""
echo -e "${YELLOW}Step 3: Starting production apps...${NC}"

if [ "$DEPLOY_API" = true ]; then
    "$SCRIPT_DIR/prod-start.sh" api
fi

if [ "$DEPLOY_WEB" = true ]; then
    # Reload nginx to pick up any config changes
    nginx -s reload 2>/dev/null || service nginx reload 2>/dev/null || true
    echo -e "${GREEN}✓ Nginx reloaded (serving static web files)${NC}"
fi

# ============================================================================
# Done
# ============================================================================
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  DEPLOYMENT COMPLETE                              ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Load config for port info
if [ -f /etc/khaos/khaos.conf ]; then
    source /etc/khaos/khaos.conf
    echo -e "  Production URL: http://localhost:$KHAOS_WEB_PORT"
    echo ""
fi
