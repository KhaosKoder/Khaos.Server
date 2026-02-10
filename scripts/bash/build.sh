#!/bin/bash
# build.sh
# Build both API and Web applications

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  KHAOS - BUILD                                    ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# What to build
BUILD_WEB=false
BUILD_API=false

case "${1:-all}" in
    web)
        BUILD_WEB=true
        ;;
    api)
        BUILD_API=true
        ;;
    all|"")
        BUILD_WEB=true
        BUILD_API=true
        ;;
    *)
        echo "Usage: $0 [web|api|all]"
        exit 1
        ;;
esac

# ============================================================================
# Build API
# ============================================================================
if [ "$BUILD_API" = true ]; then
    echo -e "${CYAN}Building .NET API...${NC}"
    cd /opt/khaos/apps/api
    
    if dotnet build -c Release --nologo -v q; then
        echo -e "${GREEN}✓ API built successfully${NC}"
    else
        echo -e "${RED}✗ API build failed${NC}"
        exit 1
    fi
fi

# ============================================================================
# Build Web
# ============================================================================
if [ "$BUILD_WEB" = true ]; then
    echo -e "${CYAN}Building Vue frontend...${NC}"
    cd /opt/khaos/apps/web
    
    if npm run build 2>/dev/null; then
        echo -e "${GREEN}✓ Web built successfully${NC}"
        echo -e "  Output: /opt/khaos/apps/web/dist/"
    else
        echo -e "${RED}✗ Web build failed${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}Build complete.${NC}"
echo ""
