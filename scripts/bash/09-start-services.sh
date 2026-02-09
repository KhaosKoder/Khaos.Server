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

# ============================================================================
# Service startup functions
# ============================================================================

start_redis() {
    log "START" "Redis" "Starting Redis..."
    if pidof systemd > /dev/null 2>&1; then
        systemctl start redis-server 2>/dev/null || true
    else
        redis-server /etc/redis/redis.conf 2>/dev/null || true
    fi
    sleep 1
    if redis-cli ping 2>/dev/null | grep -q "PONG"; then
        log "SUCCESS" "Redis" "Redis is running on port 6379"
    else
        log "WARN" "Redis" "Redis may not be running"
    fi
}

start_postgres() {
    log "START" "PostgreSQL" "Starting PostgreSQL..."
    if pidof systemd > /dev/null 2>&1; then
        systemctl start postgresql 2>/dev/null || true
    else
        service postgresql start 2>/dev/null || pg_ctlcluster 16 main start 2>/dev/null || true
    fi
    sleep 2
    if pg_isready -q 2>/dev/null; then
        log "SUCCESS" "PostgreSQL" "PostgreSQL is running on port 5432"
    else
        log "WARN" "PostgreSQL" "PostgreSQL may not be running"
    fi
}

start_ollama() {
    log "START" "Ollama" "Starting Ollama..."
    
    # Kill any existing instance
    pkill ollama 2>/dev/null || true
    sleep 1
    
    # Start Ollama
    nohup ollama serve > /var/log/khaos/ollama.log 2>&1 &
    sleep 3
    
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        log "SUCCESS" "Ollama" "Ollama is running on port 11434"
    else
        log "WARN" "Ollama" "Ollama may not be running (check /var/log/khaos/ollama.log)"
    fi
}

start_api() {
    log "START" ".NET API" "Starting .NET API..."
    
    API_PATH="/opt/khaos/apps/api"
    
    # Kill any existing instance
    pkill -f "dotnet.*KhaosApi" 2>/dev/null || true
    sleep 1
    
    cd "$API_PATH"
    nohup dotnet run --no-build > /var/log/khaos/api.log 2>&1 &
    sleep 5
    
    if curl -s http://localhost:5000/api/health > /dev/null 2>&1; then
        log "SUCCESS" ".NET API" "API is running on port 5000"
    else
        log "WARN" ".NET API" "API may not be running (check /var/log/khaos/api.log)"
    fi
}

start_web() {
    log "START" "Vue Web" "Starting Vue development server..."
    
    WEB_PATH="/opt/khaos/apps/web"
    
    # Kill any existing instance
    pkill -f "vite" 2>/dev/null || true
    sleep 1
    
    cd "$WEB_PATH"
    nohup npm run dev > /var/log/khaos/web.log 2>&1 &
    sleep 5
    
    if curl -s http://localhost:3000 > /dev/null 2>&1; then
        log "SUCCESS" "Vue Web" "Vue dev server is running on port 3000"
    else
        log "WARN" "Vue Web" "Vue dev server may not be running (check /var/log/khaos/web.log)"
    fi
}

start_nginx() {
    log "START" "Nginx" "Starting Nginx..."
    if pidof systemd > /dev/null 2>&1; then
        systemctl start nginx 2>/dev/null || true
    else
        service nginx start 2>/dev/null || nginx 2>/dev/null || true
    fi
    sleep 1
    if curl -sk https://localhost > /dev/null 2>&1; then
        log "SUCCESS" "Nginx" "Nginx is running on ports 80/443"
    else
        log "WARN" "Nginx" "Nginx may not be accessible"
    fi
}

# ============================================================================
# Start all services in order
# ============================================================================

start_redis
start_postgres
start_ollama
start_api
start_web
start_nginx

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                  ALL SERVICES STARTED                             ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Access the application at:"
echo ""
echo "    🌐 https://localhost"
echo ""
echo "  Individual services:"
echo "    - Redis:      localhost:6379"
echo "    - PostgreSQL: localhost:5432"
echo "    - Ollama:     http://localhost:11434"
echo "    - API:        http://localhost:5000"
echo "    - Web:        http://localhost:3000"
echo ""
echo "  Logs:"
echo "    - Ollama: /var/log/khaos/ollama.log"
echo "    - API:    /var/log/khaos/api.log"
echo "    - Web:    /var/log/khaos/web.log"
echo "    - Nginx:  /var/log/nginx/khaos-*.log"
echo ""
