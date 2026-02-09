#!/bin/bash
# 06-install-redis.sh
# Install Redis server

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
echo "║                  KHAOS - INSTALL REDIS                            ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# STEP 1: Install Redis
# ============================================================================
log "START" "Install Redis" "Installing Redis server..."

export DEBIAN_FRONTEND=noninteractive

if apt-get install -y -qq redis-server; then
    REDIS_VERSION=$(redis-server --version | head -1)
    log "SUCCESS" "Install Redis" "Redis installed: $REDIS_VERSION"
else
    log "FAIL" "Install Redis" "Failed to install Redis"
    exit 1
fi

# ============================================================================
# STEP 2: Configure Redis
# ============================================================================
log "START" "Configure" "Configuring Redis..."

# Backup original config
cp /etc/redis/redis.conf /etc/redis/redis.conf.backup

# Configure for local use
cat >> /etc/redis/redis.conf << 'EOF'

# Khaos configuration
bind 127.0.0.1
port 6379
daemonize yes
supervised no
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF

log "SUCCESS" "Configure" "Redis configured"

# ============================================================================
# STEP 3: Start Redis
# ============================================================================
log "START" "Start Redis" "Starting Redis server..."

# Create required directories
mkdir -p /var/run/redis
chown redis:redis /var/run/redis

# Check if systemd is available
if pidof systemd > /dev/null 2>&1; then
    systemctl enable redis-server 2>/dev/null || true
    systemctl start redis-server 2>/dev/null || true
    log "SUCCESS" "Start Redis" "Redis started via systemd"
else
    # Start manually
    redis-server /etc/redis/redis.conf
    sleep 2
    
    if redis-cli ping > /dev/null 2>&1; then
        log "SUCCESS" "Start Redis" "Redis started manually"
    else
        log "WARN" "Start Redis" "Redis may not be running properly"
    fi
fi

# ============================================================================
# STEP 4: Test Redis
# ============================================================================
log "START" "Test Redis" "Testing Redis connection..."

if redis-cli ping | grep -q "PONG"; then
    log "SUCCESS" "Test Redis" "Redis is responding"
else
    log "WARN" "Test Redis" "Redis did not respond to ping"
fi

# ============================================================================
# STEP 5: Save config
# ============================================================================
cat > /opt/khaos/config/redis.conf << EOF
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_VERSION=$REDIS_VERSION
EOF

log "SUCCESS" "Save Config" "Redis configuration saved"

# ============================================================================
# DONE
# ============================================================================
echo ""
echo -e "${GREEN}✓ Redis setup completed!${NC}"
echo "  Version: $REDIS_VERSION"
echo "  Host: localhost:6379"
echo "  Test: redis-cli ping"
echo ""
