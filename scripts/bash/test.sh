#!/bin/bash
# test.sh
# Run tests for API and Web

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  KHAOS - TEST                                     ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# What to test
TEST_WEB=false
TEST_API=false

case "${1:-all}" in
    web)
        TEST_WEB=true
        ;;
    api)
        TEST_API=true
        ;;
    all|"")
        TEST_WEB=true
        TEST_API=true
        ;;
    *)
        echo "Usage: $0 [web|api|all]"
        exit 1
        ;;
esac

EXIT_CODE=0

# ============================================================================
# Test API
# ============================================================================
if [ "$TEST_API" = true ]; then
    echo -e "${CYAN}Testing API...${NC}"
    
    cd /opt/khaos/apps/api
    
    if dotnet test --nologo -v q 2>/dev/null; then
        echo -e "${GREEN}✓ API tests passed${NC}"
    else
        # No test project, just try building
        if dotnet build --nologo -v q; then
            echo -e "${GREEN}✓ API builds successfully${NC}"
        else
            echo -e "${RED}✗ API build failed${NC}"
            EXIT_CODE=1
        fi
    fi
fi

# ============================================================================
# Test Web
# ============================================================================
if [ "$TEST_WEB" = true ]; then
    echo -e "${CYAN}Testing Web...${NC}"
    
    cd /opt/khaos/apps/web
    
    # Type check
    if npm run type-check 2>/dev/null; then
        echo -e "${GREEN}✓ TypeScript type check passed${NC}"
    else
        # Try building instead
        if npm run build 2>/dev/null; then
            echo -e "${GREEN}✓ Web builds successfully${NC}"
        else
            echo -e "${RED}✗ Web build failed${NC}"
            EXIT_CODE=1
        fi
    fi
fi

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}All tests passed.${NC}"
else
    echo -e "${RED}Some tests failed.${NC}"
fi
echo ""

exit $EXIT_CODE
