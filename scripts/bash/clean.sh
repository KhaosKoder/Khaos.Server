#!/bin/bash
# clean.sh
# Clean build artifacts

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  KHAOS - CLEAN                                    ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# What to clean
CLEAN_WEB=false
CLEAN_API=false

case "${1:-all}" in
    web)
        CLEAN_WEB=true
        ;;
    api)
        CLEAN_API=true
        ;;
    all|"")
        CLEAN_WEB=true
        CLEAN_API=true
        ;;
    *)
        echo "Usage: $0 [web|api|all]"
        exit 1
        ;;
esac

# ============================================================================
# Clean API
# ============================================================================
if [ "$CLEAN_API" = true ]; then
    echo -e "${CYAN}Cleaning API...${NC}"
    
    API_PATH="/opt/khaos/apps/api"
    API_PUBLISH="/opt/khaos/publish/api"
    
    rm -rf "$API_PATH/bin" "$API_PATH/obj" 2>/dev/null || true
    rm -rf "$API_PUBLISH" 2>/dev/null || true
    
    echo -e "${GREEN}✓ API cleaned${NC}"
fi

# ============================================================================
# Clean Web
# ============================================================================
if [ "$CLEAN_WEB" = true ]; then
    echo -e "${CYAN}Cleaning Web...${NC}"
    
    WEB_PATH="/opt/khaos/apps/web"
    WEB_PUBLISH="/opt/khaos/publish/web"
    
    rm -rf "$WEB_PATH/dist" 2>/dev/null || true
    rm -rf "$WEB_PATH/.vite" 2>/dev/null || true
    rm -rf "$WEB_PUBLISH" 2>/dev/null || true
    
    echo -e "${GREEN}✓ Web cleaned${NC}"
fi

echo ""
echo -e "${GREEN}Clean complete.${NC}"
echo ""
