#!/bin/bash
# publish.sh
# Publish both API and Web applications for production

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load configuration
if [ -f /etc/khaos/khaos.conf ]; then
    source /etc/khaos/khaos.conf
fi

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  KHAOS - PUBLISH                                  ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# What to publish
PUBLISH_WEB=false
PUBLISH_API=false

case "${1:-all}" in
    web)
        PUBLISH_WEB=true
        ;;
    api)
        PUBLISH_API=true
        ;;
    all|"")
        PUBLISH_WEB=true
        PUBLISH_API=true
        ;;
    *)
        echo "Usage: $0 [web|api|all]"
        exit 1
        ;;
esac

# ============================================================================
# Publish API
# ============================================================================
if [ "$PUBLISH_API" = true ]; then
    echo -e "${CYAN}Publishing .NET API...${NC}"
    
    API_SRC="/opt/khaos/apps/api"
    API_PUBLISH="/opt/khaos/publish/api"
    
    # Clean publish directory
    rm -rf "$API_PUBLISH"
    mkdir -p "$API_PUBLISH"
    
    cd "$API_SRC"
    
    if dotnet publish -c Release -o "$API_PUBLISH" --nologo -v q; then
        echo -e "${GREEN}✓ API published to $API_PUBLISH${NC}"
    else
        echo -e "${RED}✗ API publish failed${NC}"
        exit 1
    fi
fi

# ============================================================================
# Publish Web
# ============================================================================
if [ "$PUBLISH_WEB" = true ]; then
    echo -e "${CYAN}Publishing Vue frontend...${NC}"
    
    WEB_SRC="/opt/khaos/apps/web"
    WEB_PUBLISH="/opt/khaos/publish/web"
    
    cd "$WEB_SRC"
    
    # Build with production API URL
    export VITE_API_URL="http://localhost:$KHAOS_API_PORT"
    
    if npm run build 2>/dev/null; then
        # Clean and copy to publish directory
        rm -rf "$WEB_PUBLISH"
        mkdir -p "$WEB_PUBLISH"
        cp -r "$WEB_SRC/dist/"* "$WEB_PUBLISH/"
        
        echo -e "${GREEN}✓ Web published to $WEB_PUBLISH${NC}"
    else
        echo -e "${RED}✗ Web publish failed${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}Publish complete.${NC}"
echo ""
echo -e "Published locations:"
echo -e "  API: /opt/khaos/publish/api/"
echo -e "  Web: /opt/khaos/publish/web/"
echo ""
