#!/bin/bash
# 09-start-services.sh
# Start all Khaos services

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
    # Default ports if config not found
    KHAOS_WEB_PORT=3000
    KHAOS_API_PORT=5000
    KHAOS_OLLAMA_PORT=11434
    KHAOS_REDIS_PORT=6379
    KHAOS_POSTGRES_PORT=5432
fi

log() {
    local status=$1
    local step=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $status in
        "START")   color=$CYAN ;;
        "SUCCESS") color=$GREEN ;;
        "FAIL")    color=$RED ;;
        "WARN")    color=$YELLOW ;;
        *)         color=$NC ;;
    esac
    
    echo -e "${color}[$timestamp] [$step] [$status] $message${NC}"
    echo "[$timestamp] [$step] [$status] $message" >> /var/log/khaos/setup.log
}

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                  KHAOS - START SERVICES                           ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Using ports from config:"
echo "    - Web:      $KHAOS_WEB_PORT"
echo "    - API:      $KHAOS_API_PORT"
echo "    - Ollama:   $KHAOS_OLLAMA_PORT"
echo "    - Redis:    $KHAOS_REDIS_PORT"
echo "    - Postgres: $KHAOS_POSTGRES_PORT"
echo ""

# ============================================================================
# Service startup functions
# ============================================================================

start_redis() {
    log "START" "Redis" "Starting Redis on port $KHAOS_REDIS_PORT..."
    
    # Update Redis config with correct port
    if [ -f /etc/redis/redis.conf ]; then
        sed -i "s/^port .*/port $KHAOS_REDIS_PORT/" /etc/redis/redis.conf
    fi
    
    if pidof systemd > /dev/null 2>&1; then
        systemctl start redis-server 2>/dev/null || true
    else
        redis-server /etc/redis/redis.conf 2>/dev/null || true
    fi
    sleep 1
    if redis-cli -p $KHAOS_REDIS_PORT ping 2>/dev/null | grep -q "PONG"; then
        log "SUCCESS" "Redis" "Redis is running on port $KHAOS_REDIS_PORT"
    else
        log "WARN" "Redis" "Redis may not be running"
    fi
}

start_postgres() {
    log "START" "PostgreSQL" "Starting PostgreSQL on port $KHAOS_POSTGRES_PORT..."
    
    # Update PostgreSQL port if not default
    if [ "$KHAOS_POSTGRES_PORT" != "5432" ]; then
        PG_CONF="/etc/postgresql/16/main/postgresql.conf"
        if [ -f "$PG_CONF" ]; then
            sed -i "s/^#*port = .*/port = $KHAOS_POSTGRES_PORT/" "$PG_CONF"
        fi
    fi
    
    if pidof systemd > /dev/null 2>&1; then
        systemctl start postgresql 2>/dev/null || true
    else
        service postgresql start 2>/dev/null || pg_ctlcluster 16 main start 2>/dev/null || true
    fi
    sleep 2
    if pg_isready -p $KHAOS_POSTGRES_PORT -q 2>/dev/null; then
        log "SUCCESS" "PostgreSQL" "PostgreSQL is running on port $KHAOS_POSTGRES_PORT"
    else
        log "WARN" "PostgreSQL" "PostgreSQL may not be running"
    fi
}

start_ollama() {
    log "START" "Ollama" "Starting Ollama on port $KHAOS_OLLAMA_PORT..."
    
    # Kill any existing instance
    pkill ollama 2>/dev/null || true
    sleep 1
    
    # Start Ollama with configured port and correct models directory
    export OLLAMA_HOST="0.0.0.0:$KHAOS_OLLAMA_PORT"
    export OLLAMA_MODELS="/usr/share/ollama/.ollama/models"
    nohup ollama serve > /var/log/khaos/ollama.log 2>&1 &
    sleep 3
    
    if curl -s http://localhost:$KHAOS_OLLAMA_PORT/api/tags > /dev/null 2>&1; then
        log "SUCCESS" "Ollama" "Ollama is running on port $KHAOS_OLLAMA_PORT"
    else
        log "WARN" "Ollama" "Ollama may not be running (check /var/log/khaos/ollama.log)"
    fi
}

start_api() {
    log "START" ".NET API" "Starting .NET API on port $KHAOS_API_PORT..."
    
    API_PATH="/opt/khaos/apps/api"
    
    # Kill any existing instance
    pkill -f "KhaosApi.dll" 2>/dev/null || true
    sleep 1
    
    API_PUBLISH="/opt/khaos/publish/api"
    
    # Check if published API exists
    if [ ! -f "$API_PUBLISH/KhaosApi.dll" ]; then
        log "WARN" ".NET API" "Published API not found, building..."
        cd "$API_PATH"
        rm -rf bin obj 2>/dev/null || true
        dotnet publish -c Release -o "$API_PUBLISH" --nologo 2>/dev/null || true
    fi
    
    if [ ! -f "$API_PUBLISH/KhaosApi.dll" ]; then
        log "FAIL" ".NET API" "Cannot find or build API"
        return 1
    fi
    
    cd "$API_PUBLISH"
    
    # Start published API with configured port
    # Note: Program.cs reads KHAOS_API_PORT and configures Kestrel
    # Do NOT use ASPNETCORE_URLS as it conflicts with ConfigureKestrel
    nohup env \
        ASPNETCORE_ENVIRONMENT="Production" \
        KHAOS_API_PORT="$KHAOS_API_PORT" \
        KHAOS_WEB_PORT="$KHAOS_WEB_PORT" \
        KHAOS_OLLAMA_PORT="$KHAOS_OLLAMA_PORT" \
        KHAOS_REDIS_PORT="$KHAOS_REDIS_PORT" \
        KHAOS_POSTGRES_PORT="$KHAOS_POSTGRES_PORT" \
        KHAOS_INSTANCE_NAME="$KHAOS_INSTANCE_NAME" \
        dotnet KhaosApi.dll > /var/log/khaos/api.log 2>&1 &
    sleep 3
    
    if curl -s http://localhost:$KHAOS_API_PORT/api/health > /dev/null 2>&1; then
        log "SUCCESS" ".NET API" "API is running on port $KHAOS_API_PORT"
    else
        log "WARN" ".NET API" "API may not be running (check /var/log/khaos/api.log)"
    fi
}

start_nginx() {
    log "START" "Nginx" "Starting Nginx on port $KHAOS_WEB_PORT..."
    
    # Kill any existing nginx
    pkill nginx 2>/dev/null || true
    sleep 1
    
    # Start nginx
    if pidof systemd > /dev/null 2>&1; then
        systemctl start nginx 2>/dev/null || nginx 2>/dev/null || true
    else
        nginx 2>/dev/null || service nginx start 2>/dev/null || true
    fi
    sleep 1
    
    if curl -s http://localhost:$KHAOS_WEB_PORT > /dev/null 2>&1; then
        log "SUCCESS" "Nginx" "Nginx is serving static files on port $KHAOS_WEB_PORT"
    else
        log "WARN" "Nginx" "Nginx may not be accessible (check /var/log/nginx/error.log)"
    fi
}

# ============================================================================
# Start all services in order
# ============================================================================

start_redis
start_postgres
start_ollama
start_api
start_nginx

# ============================================================================
# Summary
# ============================================================================
DEV_WEB_PORT=$((KHAOS_WEB_PORT + 1))
DEV_API_PORT=$((KHAOS_API_PORT + 1))

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                  ALL SERVICES STARTED                             ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Instance: $KHAOS_INSTANCE_NAME"
echo "  Base Port: $KHAOS_BASE_PORT"
echo ""
echo "  Production (nginx serves static files):"
echo "    🌐 http://localhost:$KHAOS_WEB_PORT"
echo ""
echo "  Services:"
echo "    - Web (nginx):  http://localhost:$KHAOS_WEB_PORT"
echo "    - API:          http://localhost:$KHAOS_API_PORT/api/health"
echo "    - Redis:        localhost:$KHAOS_REDIS_PORT"
echo "    - PostgreSQL:   localhost:$KHAOS_POSTGRES_PORT"
echo "    - Ollama:       http://localhost:$KHAOS_OLLAMA_PORT"
echo ""
echo "  Development ports (when using dev-start.sh):"
echo "    - Vite:         http://localhost:$DEV_WEB_PORT"
echo "    - API:          http://localhost:$DEV_API_PORT/api/health"
echo ""
echo "  Commands:"
echo "    /opt/khaos/scripts/status.sh      - Show status"
echo "    /opt/khaos/scripts/dev-start.sh   - Start dev servers"
echo "    /opt/khaos/scripts/deploy.sh      - Deploy changes"
echo ""

# Keep WSL session alive so background processes don't die
# This is critical - without an active session, nohup processes will be killed
if [ "$1" = "--keep-alive" ] || [ "$KHAOS_KEEP_ALIVE" = "true" ]; then
    log "INFO" "Keep Alive" "Keeping WSL session alive (Ctrl+C to stop)..."
    exec sleep infinity
fi
