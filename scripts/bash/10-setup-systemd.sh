#!/bin/bash
# 10-setup-systemd.sh
# Enable systemd and create service files for all Khaos services

set -e

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

log() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                  KHAOS - SETUP SYSTEMD                            ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# 1. Enable systemd in WSL
# ============================================================================
log "Configuring WSL for systemd..."

cat > /etc/wsl.conf << 'EOF'
[boot]
systemd=true

[network]
generateHosts = true
generateResolvConf = true

[interop]
enabled = true
appendWindowsPath = true
EOF

success "WSL configured for systemd"

# ============================================================================
# 2. Create Khaos API service (uses published binary)
# ============================================================================
log "Creating Khaos API service..."

cat > /etc/systemd/system/khaos-api.service << EOF
[Unit]
Description=Khaos .NET API (Published)
After=network.target redis-server.service postgresql.service
Wants=redis-server.service postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/khaos/publish/api
Environment=KHAOS_API_PORT=${KHAOS_API_PORT}
Environment=KHAOS_REDIS_PORT=${KHAOS_REDIS_PORT}
Environment=KHAOS_OLLAMA_PORT=${KHAOS_OLLAMA_PORT}
Environment=KHAOS_INSTANCE_NAME=${KHAOS_INSTANCE_NAME}
ExecStart=/opt/khaos/publish/api/KhaosApi
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

success "Khaos API service created (published binary)"

# ============================================================================
# 3. Configure Nginx for static web files
# ============================================================================
log "Nginx will serve static Vue files from /opt/khaos/publish/web"
log "No separate web service needed - nginx handles it"

# ============================================================================
# 4. Create WSL Keepalive service (prevents WSL from auto-terminating)
# ============================================================================
log "Creating WSL keepalive service..."

cat > /etc/systemd/system/wsl-keepalive.service << 'EOF'
[Unit]
Description=WSL Keepalive - Prevents WSL from auto-terminating
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c "while true; do sleep 3600; done"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

success "WSL keepalive service created"

# ============================================================================
# 5. Create Ollama service (if not exists)
# ============================================================================
log "Checking Ollama service..."

if [ ! -f /etc/systemd/system/ollama.service ]; then
    cat > /etc/systemd/system/ollama.service << EOF
[Unit]
Description=Ollama LLM Service
After=network.target

[Service]
Type=simple
User=ollama
Group=ollama
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=10
Environment=HOME=/usr/share/ollama
Environment=OLLAMA_HOST=0.0.0.0:${KHAOS_OLLAMA_PORT}

[Install]
WantedBy=multi-user.target
EOF
    success "Ollama service created"
else
    success "Ollama service already exists"
fi

# ============================================================================
# 6. Enable all services (will take effect after WSL restart)
# ============================================================================
log "Pre-enabling services (will activate after WSL restart with systemd)..."

# These commands will fail now if systemd isn't running, but the symlinks
# will be created and services will start after restart
systemctl enable redis-server 2>/dev/null || true
systemctl enable postgresql 2>/dev/null || true
systemctl enable nginx 2>/dev/null || true
systemctl enable ollama 2>/dev/null || true
systemctl enable khaos-api 2>/dev/null || true
systemctl enable wsl-keepalive 2>/dev/null || true

success "Services pre-enabled"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "  Systemd configuration complete!"
echo ""
echo "  IMPORTANT: You must restart the WSL instance for systemd to work:"
echo ""
echo "    1. From Windows PowerShell, run:"
echo "       wsl --terminate $KHAOS_INSTANCE_NAME"
echo ""
echo "    2. Then start the instance again:"
echo "       wsl -d $KHAOS_INSTANCE_NAME"
echo ""
echo "  After restart, all services will auto-start. To check status:"
echo ""
echo "    systemctl status redis-server postgresql nginx khaos-api ollama"
echo ""
echo "  Service ports:"
echo "    - Web (nginx):  http://localhost:$KHAOS_WEB_PORT"
echo "    - API:          http://localhost:$KHAOS_API_PORT"
echo "    - Ollama:       http://localhost:$KHAOS_OLLAMA_PORT"
echo "    - Redis:        localhost:$KHAOS_REDIS_PORT"
echo "    - PostgreSQL:   localhost:$KHAOS_POSTGRES_PORT"
echo ""
echo "═══════════════════════════════════════════════════════════════════"
