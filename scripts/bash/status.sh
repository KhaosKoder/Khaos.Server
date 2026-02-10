#!/bin/bash
# status.sh
# Show status of all Khaos services

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

DEV_WEB_PORT=$((KHAOS_WEB_PORT + 1))
DEV_API_PORT=$((KHAOS_API_PORT + 1))

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  KHAOS - STATUS                                   ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Instance: ${GREEN}$KHAOS_INSTANCE_NAME${NC}"
echo -e "Base Port: ${GREEN}$KHAOS_BASE_PORT${NC}"
echo ""

# Helper function
check_port() {
    local port=$1
    local name=$2
    if ss -tlnp 2>/dev/null | grep -q ":$port "; then
        echo -e "  ${GREEN}✓${NC} $name (port $port)"
        return 0
    else
        echo -e "  ${RED}✗${NC} $name (port $port)"
        return 1
    fi
}

check_process() {
    local pattern=$1
    local name=$2
    if pgrep -f "$pattern" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $name"
        return 0
    else
        echo -e "  ${RED}✗${NC} $name"
        return 1
    fi
}

# ============================================================================
# Production Services
# ============================================================================
echo -e "${YELLOW}Production Services:${NC}"

check_port $KHAOS_WEB_PORT "Web (nginx static)" || true
check_port $KHAOS_API_PORT "API" || true
check_port $KHAOS_REDIS_PORT "Redis" || true
check_port $KHAOS_POSTGRES_PORT "PostgreSQL" || true
check_port $KHAOS_OLLAMA_PORT "Ollama" || true

# ============================================================================
# Development Services
# ============================================================================
echo ""
echo -e "${YELLOW}Development Services:${NC}"

if ss -tlnp 2>/dev/null | grep -q ":$DEV_WEB_PORT "; then
    echo -e "  ${GREEN}✓${NC} Vite dev server (port $DEV_WEB_PORT)"
else
    echo -e "  ${CYAN}○${NC} Vite dev server (port $DEV_WEB_PORT) - not running"
fi

if ss -tlnp 2>/dev/null | grep -q ":$DEV_API_PORT "; then
    echo -e "  ${GREEN}✓${NC} API dev server (port $DEV_API_PORT)"
else
    echo -e "  ${CYAN}○${NC} API dev server (port $DEV_API_PORT) - not running"
fi

# ============================================================================
# URLs
# ============================================================================
echo ""
echo -e "${YELLOW}URLs:${NC}"
echo -e "  Production:"
echo -e "    Web: http://localhost:$KHAOS_WEB_PORT"
echo -e "    API: http://localhost:$KHAOS_API_PORT/api/health"
echo -e "  Development:"
echo -e "    Web: http://localhost:$DEV_WEB_PORT"
echo -e "    API: http://localhost:$DEV_API_PORT/api/health"

# ============================================================================
# Commands
# ============================================================================
echo ""
echo -e "${YELLOW}Commands:${NC}"
echo -e "  /opt/khaos/scripts/status.sh       - This status page"
echo -e "  /opt/khaos/scripts/dev-start.sh    - Start dev servers"
echo -e "  /opt/khaos/scripts/dev-stop.sh     - Stop dev servers"
echo -e "  /opt/khaos/scripts/build.sh        - Build apps"
echo -e "  /opt/khaos/scripts/deploy.sh       - Deploy to production"
echo -e "  /opt/khaos/scripts/prod-start.sh   - Start production"
echo -e "  /opt/khaos/scripts/prod-stop.sh    - Stop production"
echo ""
