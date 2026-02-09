#!/bin/bash
# 00-khaos-startup.sh
# Auto-start script for Khaos services
# This script is called when the WSL instance starts

# Don't exit on error - we want to try starting all services
set +e

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
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

log "Starting Khaos services..."

# ============================================================================
# 1. Redis
# ============================================================================
start_service "Redis" 6379 "redis-server --daemonize yes --bind 127.0.0.1 2>/dev/null" 5

# ============================================================================
# 2. PostgreSQL
# ============================================================================
if check_port 5432; then
    log "${GREEN}✓${NC} PostgreSQL already running on port 5432"
else
    log "${CYAN}→${NC} Starting PostgreSQL..."
    /etc/init.d/postgresql start > /dev/null 2>&1 || true
    if wait_for_port 5432 5; then
        log "${GREEN}✓${NC} PostgreSQL started on port 5432"
    else
        log "${RED}✗${NC} PostgreSQL failed to start"
    fi
fi

# ============================================================================
# 3. Ollama
# ============================================================================
# Check if Ollama is already running using curl (more reliable)
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    log "${GREEN}✓${NC} Ollama already running on port 11434"
else
    log "${CYAN}→${NC} Starting Ollama..."
    nohup ollama serve > /var/log/khaos/ollama.log 2>&1 &
    # Wait and verify with curl
    for i in {1..15}; do
        sleep 1
        if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
            log "${GREEN}✓${NC} Ollama started on port 11434"
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
if ! check_port 5000; then
    log "${CYAN}→${NC} Starting .NET API..."
    cd /opt/khaos/apps/api
    export DOTNET_ROOT=/usr/share/dotnet
    export PATH=$PATH:/usr/share/dotnet
    nohup dotnet run --urls "http://0.0.0.0:5000" > /var/log/khaos/api.log 2>&1 &
    if wait_for_port 5000 20; then
        log "${GREEN}✓${NC} .NET API started on port 5000"
    else
        log "${YELLOW}⚠${NC} .NET API may still be starting (check /var/log/khaos/api.log)"
    fi
else
    log "${GREEN}✓${NC} .NET API already running on port 5000"
fi

# ============================================================================
# 5. Vue Frontend
# ============================================================================
if ! check_port 3000; then
    log "${CYAN}→${NC} Starting Vue frontend..."
    cd /opt/khaos/apps/web
    nohup npm run dev -- --host 0.0.0.0 > /var/log/khaos/web.log 2>&1 &
    if wait_for_port 3000 20; then
        log "${GREEN}✓${NC} Vue frontend started on port 3000"
    else
        log "${YELLOW}⚠${NC} Vue frontend may still be starting (check /var/log/khaos/web.log)"
    fi
else
    log "${GREEN}✓${NC} Vue frontend already running on port 3000"
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
echo "  🚀 Khaos is ready!"
echo ""
echo "  Access: https://localhost"
echo ""
echo "  Services:"

# Check each service and report status
for service in "Redis:6379" "PostgreSQL:5432" "API:5000" "Frontend:3000"; do
    name=$(echo $service | cut -d: -f1)
    port=$(echo $service | cut -d: -f2)
    if check_port $port; then
        echo -e "    ${GREEN}●${NC} $name (port $port)"
    else
        echo -e "    ${RED}○${NC} $name (port $port) - not running"
    fi
done

# Check Ollama with curl (more reliable)
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo -e "    ${GREEN}●${NC} Ollama (port 11434)"
else
    echo -e "    ${RED}○${NC} Ollama (port 11434) - not running"
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
