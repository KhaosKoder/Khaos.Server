#!/bin/bash
# prod-start.sh
# Start production services (published apps)
# Web is served as static files by nginx - no process needed
# API runs the published dll

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

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  KHAOS - START PRODUCTION                         ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# What to start
START_API=false
START_INFRA=false

case "${1:-all}" in
    api)
        START_API=true
        ;;
    infra)
        START_INFRA=true
        ;;
    all|"")
        START_API=true
        START_INFRA=true
        ;;
    *)
        echo "Usage: $0 [api|infra|all]"
        exit 1
        ;;
esac

# ============================================================================
# Start Infrastructure (Redis, Postgres, Ollama, Nginx)
# ============================================================================
if [ "$START_INFRA" = true ]; then
    echo -e "${CYAN}Starting infrastructure services...${NC}"
    
    # Redis
    if ! pgrep -x "redis-server" > /dev/null; then
        redis-server /etc/redis/redis.conf 2>/dev/null || redis-server --port $KHAOS_REDIS_PORT --daemonize yes
        echo -e "${GREEN}✓ Redis started on port $KHAOS_REDIS_PORT${NC}"
    else
        echo -e "${GREEN}✓ Redis already running${NC}"
    fi
    
    # PostgreSQL
    if ! pgrep -x "postgres" > /dev/null; then
        su - postgres -c "/usr/lib/postgresql/*/bin/pg_ctl start -D /var/lib/postgresql/*/main -l /var/log/postgresql/postgresql.log" 2>/dev/null || \
        service postgresql start 2>/dev/null || true
        echo -e "${GREEN}✓ PostgreSQL started on port $KHAOS_POSTGRES_PORT${NC}"
    else
        echo -e "${GREEN}✓ PostgreSQL already running${NC}"
    fi
    
    # Ollama
    if ! pgrep -x "ollama" > /dev/null; then
        export OLLAMA_HOST="0.0.0.0:$KHAOS_OLLAMA_PORT"
        export OLLAMA_MODELS="/usr/share/ollama/.ollama/models"
        nohup ollama serve > /var/log/khaos/ollama.log 2>&1 &
        sleep 2
        echo -e "${GREEN}✓ Ollama started on port $KHAOS_OLLAMA_PORT${NC}"
    else
        echo -e "${GREEN}✓ Ollama already running${NC}"
    fi
    
    # Nginx
    if ! pgrep -x "nginx" > /dev/null; then
        nginx 2>/dev/null || service nginx start 2>/dev/null || true
        echo -e "${GREEN}✓ Nginx started (serving static files on port $KHAOS_WEB_PORT)${NC}"
    else
        echo -e "${GREEN}✓ Nginx already running${NC}"
    fi
fi

# ============================================================================
# Start API (published version)
# ============================================================================
if [ "$START_API" = true ]; then
    echo -e "${CYAN}Starting API (published)...${NC}"
    
    API_PUBLISH="/opt/khaos/publish/api"
    API_DLL="$API_PUBLISH/KhaosApi.dll"
    
    if [ ! -f "$API_DLL" ]; then
        echo -e "${RED}✗ Published API not found at $API_DLL${NC}"
        echo -e "  Run: /opt/khaos/scripts/publish.sh api"
        exit 1
    fi
    
    # Kill any existing API on prod port
    pkill -f "KhaosApi.dll" 2>/dev/null || true
    sleep 1
    
    # Start published API
    # Note: Program.cs reads KHAOS_API_PORT and configures Kestrel
    # Do NOT use ASPNETCORE_URLS as it conflicts with ConfigureKestrel
    cd "$API_PUBLISH"
    ASPNETCORE_ENVIRONMENT=Production \
    KHAOS_API_PORT="$KHAOS_API_PORT" \
    KHAOS_REDIS_PORT="$KHAOS_REDIS_PORT" \
    KHAOS_OLLAMA_PORT="$KHAOS_OLLAMA_PORT" \
    KHAOS_POSTGRES_PORT="$KHAOS_POSTGRES_PORT" \
    nohup dotnet KhaosApi.dll > /var/log/khaos/api.log 2>&1 &
    
    sleep 2
    
    if curl -s "http://localhost:$KHAOS_API_PORT/api/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ API started on port $KHAOS_API_PORT${NC}"
    else
        echo -e "${YELLOW}⚠ API starting (may need a moment)${NC}"
    fi
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${GREEN}Production services started.${NC}"
echo ""
echo -e "  Web: http://localhost:$KHAOS_WEB_PORT (nginx serving static files)"
echo -e "  API: http://localhost:$KHAOS_API_PORT/api/health"
echo ""
