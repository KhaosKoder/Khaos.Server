#!/bin/bash
# prod-stop.sh
# Stop production services

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  KHAOS - STOP PRODUCTION                          ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# What to stop
STOP_API=false
STOP_INFRA=false

case "${1:-all}" in
    api)
        STOP_API=true
        ;;
    infra)
        STOP_INFRA=true
        ;;
    all|"")
        STOP_API=true
        STOP_INFRA=true
        ;;
    *)
        echo "Usage: $0 [api|infra|all]"
        exit 1
        ;;
esac

# ============================================================================
# Stop API
# ============================================================================
if [ "$STOP_API" = true ]; then
    echo -e "${CYAN}Stopping API...${NC}"
    pkill -f "KhaosApi.dll" 2>/dev/null && \
        echo -e "${GREEN}✓ API stopped${NC}" || \
        echo -e "${GREEN}✓ API was not running${NC}"
fi

# ============================================================================
# Stop Infrastructure
# ============================================================================
if [ "$STOP_INFRA" = true ]; then
    echo -e "${CYAN}Stopping infrastructure...${NC}"
    
    # Nginx
    nginx -s stop 2>/dev/null || pkill nginx 2>/dev/null || true
    echo -e "${GREEN}✓ Nginx stopped${NC}"
    
    # Ollama
    pkill ollama 2>/dev/null || true
    echo -e "${GREEN}✓ Ollama stopped${NC}"
    
    # PostgreSQL
    su - postgres -c "/usr/lib/postgresql/*/bin/pg_ctl stop -D /var/lib/postgresql/*/main" 2>/dev/null || \
    service postgresql stop 2>/dev/null || \
    pkill postgres 2>/dev/null || true
    echo -e "${GREEN}✓ PostgreSQL stopped${NC}"
    
    # Redis
    redis-cli shutdown 2>/dev/null || pkill redis-server 2>/dev/null || true
    echo -e "${GREEN}✓ Redis stopped${NC}"
fi

echo ""
echo -e "${GREEN}Production services stopped.${NC}"
echo ""
