#!/bin/bash
# dev-stop.sh
# Stop development servers

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load configuration
if [ -f /etc/khaos/khaos.conf ]; then
    source /etc/khaos/khaos.conf
fi

DEV_WEB_PORT=$((KHAOS_WEB_PORT + 1))
DEV_API_PORT=$((KHAOS_API_PORT + 1))

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  KHAOS - STOP DEVELOPMENT                         ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# What to stop
STOP_WEB=false
STOP_API=false

case "${1:-all}" in
    web)
        STOP_WEB=true
        ;;
    api)
        STOP_API=true
        ;;
    all|"")
        STOP_WEB=true
        STOP_API=true
        ;;
    *)
        echo "Usage: $0 [web|api|all]"
        exit 1
        ;;
esac

# Stop API dev server
if [ "$STOP_API" = true ]; then
    echo -e "${CYAN}Stopping API dev server...${NC}"
    pkill -f "dotnet.*--urls.*:$DEV_API_PORT" 2>/dev/null && \
        echo -e "${GREEN}✓ API dev server stopped${NC}" || \
        echo -e "${GREEN}✓ API dev server was not running${NC}"
fi

# Stop Web dev server
if [ "$STOP_WEB" = true ]; then
    echo -e "${CYAN}Stopping Vite dev server...${NC}"
    pkill -f "vite.*--port.*$DEV_WEB_PORT" 2>/dev/null && \
        echo -e "${GREEN}✓ Vite dev server stopped${NC}" || \
        echo -e "${GREEN}✓ Vite dev server was not running${NC}"
    
    # Also kill any orphaned node processes on dev port
    pkill -f "node.*$DEV_WEB_PORT" 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}Development servers stopped.${NC}"
echo -e "Production servers are still running."
echo ""
