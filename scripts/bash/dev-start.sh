#!/bin/bash
# dev-start.sh
# Start development servers for interactive development
# Production continues running on prod ports while you develop on dev ports

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
else
    echo -e "${RED}Error: /etc/khaos/khaos.conf not found${NC}"
    exit 1
fi

# Dev ports are prod ports + 1
DEV_WEB_PORT=$((KHAOS_WEB_PORT + 1))
DEV_API_PORT=$((KHAOS_API_PORT + 1))

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  KHAOS - START DEVELOPMENT                        ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# What to start
START_WEB=false
START_API=false

case "${1:-all}" in
    web)
        START_WEB=true
        ;;
    api)
        START_API=true
        ;;
    all|"")
        START_WEB=true
        START_API=true
        ;;
    *)
        echo "Usage: $0 [web|api|all]"
        exit 1
        ;;
esac

# ============================================================================
# Start API Development Server
# ============================================================================
if [ "$START_API" = true ]; then
    echo -e "${CYAN}Starting .NET API dev server on port $DEV_API_PORT...${NC}"
    
    # Kill any existing dev API
    pkill -f "dotnet.*--urls.*:$DEV_API_PORT" 2>/dev/null || true
    sleep 1
    
    cd /opt/khaos/apps/api
    
    # Start in background with dev port
    ASPNETCORE_ENVIRONMENT=Development \
    nohup dotnet run --urls "http://0.0.0.0:$DEV_API_PORT" > /var/log/khaos/api-dev.log 2>&1 &
    
    echo -e "${GREEN}✓ API dev server starting on http://localhost:$DEV_API_PORT${NC}"
    echo -e "  Log: /var/log/khaos/api-dev.log"
fi

# ============================================================================
# Start Web Development Server
# ============================================================================
if [ "$START_WEB" = true ]; then
    echo -e "${CYAN}Starting Vite dev server on port $DEV_WEB_PORT...${NC}"
    
    # Kill any existing dev web
    pkill -f "vite.*--port.*$DEV_WEB_PORT" 2>/dev/null || true
    sleep 1
    
    cd /opt/khaos/apps/web
    
    # Start Vite with API pointing to dev API
    VITE_API_URL="http://localhost:$DEV_API_PORT" \
    nohup npm run dev -- --host 0.0.0.0 --port $DEV_WEB_PORT > /var/log/khaos/web-dev.log 2>&1 &
    
    echo -e "${GREEN}✓ Vite dev server starting on http://localhost:$DEV_WEB_PORT${NC}"
    echo -e "  Log: /var/log/khaos/web-dev.log"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${GREEN}Development servers starting...${NC}"
echo ""
echo -e "  ${YELLOW}Development URLs:${NC}"
if [ "$START_WEB" = true ]; then
    echo -e "    Web: http://localhost:$DEV_WEB_PORT"
fi
if [ "$START_API" = true ]; then
    echo -e "    API: http://localhost:$DEV_API_PORT/api/health"
fi
echo ""
echo -e "  ${YELLOW}Production URLs (still running):${NC}"
echo -e "    Web: http://localhost:$KHAOS_WEB_PORT"
echo -e "    API: http://localhost:$KHAOS_API_PORT/api/health"
echo ""
echo -e "  ${YELLOW}Commands:${NC}"
echo -e "    Stop dev:     /opt/khaos/scripts/dev-stop.sh"
echo -e "    View logs:    tail -f /var/log/khaos/*-dev.log"
echo -e "    Deploy:       /opt/khaos/scripts/deploy.sh"
echo ""
