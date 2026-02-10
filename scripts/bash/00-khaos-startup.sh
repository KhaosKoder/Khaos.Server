#!/bin/bash
# 00-khaos-startup.sh
# Auto-start script for Khaos services
# This script is called when the WSL instance starts

# Don't exit on error - we want to try starting all services
set +e

# Load Khaos configuration
if [ -f /etc/khaos/khaos.conf ]; then
    source /etc/khaos/khaos.conf
fi

# Set default ports if not configured
KHAOS_WEB_PORT=${KHAOS_WEB_PORT:-3000}
KHAOS_API_PORT=${KHAOS_API_PORT:-5000}
KHAOS_OLLAMA_PORT=${KHAOS_OLLAMA_PORT:-11434}
KHAOS_REDIS_PORT=${KHAOS_REDIS_PORT:-6379}
KHAOS_POSTGRES_PORT=${KHAOS_POSTGRES_PORT:-5432}
KHAOS_INSTANCE_NAME=${KHAOS_INSTANCE_NAME:-"Khaos Server"}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Log file
LOG_FILE="/var/log/khaos/startup.log"
mkdir -p /var/log/khaos

log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" >> "$LOG_FILE"
    echo -e "$1"
}

# Function to check if a process is running on a port
check_port() {
    local port=$1
    netstat -tuln 2>/dev/null | grep -q ":$port " && return 0 || return 1
}

# Function to wait for a port with timeout
wait_for_port() {
    local port=$1
    local timeout=${2:-10}
    local count=0
    while ! check_port $port; do
        sleep 1
        count=$((count + 1))
        if [ $count -ge $timeout ]; then
            return 1
        fi
    done
    return 0
}

# Function to start a service
start_service() {
    local name=$1
    local port=$2
    local start_cmd=$3
    local timeout=${4:-10}
    
    if check_port $port; then
        log "${GREEN}✓${NC} $name already running on port $port"
        return 0
    fi
    
    log "${CYAN}→${NC} Starting $name..."
    eval "$start_cmd"
    
    if wait_for_port $port $timeout; then
        log "${GREEN}✓${NC} $name started on port $port"
        return 0
    else
        log "${RED}✗${NC} $name failed to start on port $port"
        return 1
    fi
}

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                  KHAOS - SERVICE STARTUP                          ║"
echo "║              Instance: $KHAOS_INSTANCE_NAME"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

log "Starting Khaos services..."

# ============================================================================
# 1. Redis
# ============================================================================
start_service "Redis" $KHAOS_REDIS_PORT "redis-server --daemonize yes --bind 127.0.0.1 --port $KHAOS_REDIS_PORT 2>/dev/null" 5

# ============================================================================
# 2. PostgreSQL
# ============================================================================
if check_port $KHAOS_POSTGRES_PORT; then
    log "${GREEN}✓${NC} PostgreSQL already running on port $KHAOS_POSTGRES_PORT"
else
    log "${CYAN}→${NC} Starting PostgreSQL..."
    /etc/init.d/postgresql start > /dev/null 2>&1 || true
    if wait_for_port $KHAOS_POSTGRES_PORT 5; then
        log "${GREEN}✓${NC} PostgreSQL started on port $KHAOS_POSTGRES_PORT"
    else
        log "${RED}✗${NC} PostgreSQL failed to start"
    fi
fi

# ============================================================================
# 3. Ollama
# ============================================================================
# Check if Ollama is already running using curl (more reliable)
if curl -s http://localhost:$KHAOS_OLLAMA_PORT/api/tags > /dev/null 2>&1; then
    log "${GREEN}✓${NC} Ollama already running on port $KHAOS_OLLAMA_PORT"
else
    log "${CYAN}→${NC} Starting Ollama..."
    export OLLAMA_HOST="0.0.0.0:$KHAOS_OLLAMA_PORT"
    nohup ollama serve > /var/log/khaos/ollama.log 2>&1 &
    # Wait and verify with curl
    for i in {1..15}; do
        sleep 1
        if curl -s http://localhost:$KHAOS_OLLAMA_PORT/api/tags > /dev/null 2>&1; then
            log "${GREEN}✓${NC} Ollama started on port $KHAOS_OLLAMA_PORT"
            break
        fi
        if [ $i -eq 15 ]; then
            log "${YELLOW}⚠${NC} Ollama may still be starting (check /var/log/khaos/ollama.log)"
        fi
    done
fi

# ============================================================================
# 4. .NET API
# ============================================================================
if ! check_port $KHAOS_API_PORT; then
    log "${CYAN}→${NC} Starting .NET API..."
    cd /opt/khaos/apps/api
    export DOTNET_ROOT=/usr/share/dotnet
    export PATH=$PATH:/usr/share/dotnet
    export KHAOS_INSTANCE_NAME
    export KHAOS_API_PORT
    export KHAOS_WEB_PORT
    export KHAOS_OLLAMA_PORT
    export KHAOS_REDIS_PORT
    export KHAOS_POSTGRES_PORT
    nohup dotnet run --urls "http://0.0.0.0:$KHAOS_API_PORT" > /var/log/khaos/api.log 2>&1 &
    if wait_for_port $KHAOS_API_PORT 20; then
        log "${GREEN}✓${NC} .NET API started on port $KHAOS_API_PORT"
    else
        log "${YELLOW}⚠${NC} .NET API may still be starting (check /var/log/khaos/api.log)"
    fi
else
    log "${GREEN}✓${NC} .NET API already running on port $KHAOS_API_PORT"
fi

# ============================================================================
# 5. Vue Frontend
# ============================================================================
if ! check_port $KHAOS_WEB_PORT; then
    log "${CYAN}→${NC} Starting Vue frontend..."
    cd /opt/khaos/apps/web
    export PORT=$KHAOS_WEB_PORT
    nohup npm run dev -- --host 0.0.0.0 --port $KHAOS_WEB_PORT > /var/log/khaos/web.log 2>&1 &
    if wait_for_port $KHAOS_WEB_PORT 20; then
        log "${GREEN}✓${NC} Vue frontend started on port $KHAOS_WEB_PORT"
    else
        log "${YELLOW}⚠${NC} Vue frontend may still be starting (check /var/log/khaos/web.log)"
    fi
else
    log "${GREEN}✓${NC} Vue frontend already running on port $KHAOS_WEB_PORT"
fi

# ============================================================================
# 6. Nginx
# ============================================================================
if pgrep nginx > /dev/null; then
    log "${GREEN}✓${NC} Nginx already running"
else
    log "${CYAN}→${NC} Starting Nginx..."
    nginx 2>/dev/null || service nginx start 2>/dev/null || true
    sleep 1
    if pgrep nginx > /dev/null; then
        log "${GREEN}✓${NC} Nginx started on ports 80/443"
    else
        log "${RED}✗${NC} Nginx failed to start"
    fi
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "  🚀 $KHAOS_INSTANCE_NAME is ready!"
echo ""
echo "  Access: http://localhost:$KHAOS_WEB_PORT"
echo ""
echo "  Services:"

# Check each service and report status
for service in "Redis:$KHAOS_REDIS_PORT" "PostgreSQL:$KHAOS_POSTGRES_PORT" "API:$KHAOS_API_PORT" "Frontend:$KHAOS_WEB_PORT"; do
    name=$(echo $service | cut -d: -f1)
    port=$(echo $service | cut -d: -f2)
    if check_port $port; then
        echo -e "    ${GREEN}●${NC} $name (port $port)"
    else
        echo -e "    ${RED}○${NC} $name (port $port) - not running"
    fi
done

# Check Ollama with curl (more reliable)
if curl -s http://localhost:$KHAOS_OLLAMA_PORT/api/tags > /dev/null 2>&1; then
    echo -e "    ${GREEN}●${NC} Ollama (port $KHAOS_OLLAMA_PORT)"
else
    echo -e "    ${RED}○${NC} Ollama (port $KHAOS_OLLAMA_PORT) - not running"
fi

# Check Nginx separately
if pgrep nginx > /dev/null; then
    echo -e "    ${GREEN}●${NC} Nginx (ports 80/443)"
else
    echo -e "    ${RED}○${NC} Nginx - not running"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo ""
