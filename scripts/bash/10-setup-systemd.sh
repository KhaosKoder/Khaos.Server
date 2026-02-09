#!/bin/bash
# 10-setup-systemd.sh
# Enable systemd and create service files for all Khaos services

set -e

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
# 2. Create Khaos API service
# ============================================================================
log "Creating Khaos API service..."

cat > /etc/systemd/system/khaos-api.service << 'EOF'
[Unit]
Description=Khaos .NET API
After=network.target redis.service postgresql.service
Wants=redis.service postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/khaos/apps/api
Environment=DOTNET_ROOT=/usr/share/dotnet
Environment=PATH=/usr/share/dotnet:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/share/dotnet/dotnet run --urls http://0.0.0.0:5000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

success "Khaos API service created"

# ============================================================================
# 3. Create Khaos Web (Vue) service
# ============================================================================
log "Creating Khaos Web service..."

cat > /etc/systemd/system/khaos-web.service << 'EOF'
[Unit]
Description=Khaos Vue Frontend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/khaos/apps/web
ExecStart=/usr/bin/npx vite --host 0.0.0.0
Restart=always
RestartSec=10
Environment=NODE_ENV=development

[Install]
WantedBy=multi-user.target
EOF

success "Khaos Web service created"

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
    cat > /etc/systemd/system/ollama.service << 'EOF'
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

[Install]
WantedBy=multi-user.target
EOF
    success "Ollama service created"
else
    success "Ollama service already exists"
fi

# ============================================================================
# 5. Enable all services
# ============================================================================
log "Services will be enabled after WSL restart with systemd..."

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "  Systemd configuration complete!"
echo ""
echo "  IMPORTANT: You must restart the WSL instance for systemd to work:"
echo ""
echo "    1. Exit WSL"
echo "    2. Run: wsl --terminate khaos-test"
echo "    3. Run: wsl -d khaos-test"
echo ""
echo "  After restart, enable services with:"
echo ""
echo "    sudo systemctl enable --now redis-server"
echo "    sudo systemctl enable --now postgresql"
echo "    sudo systemctl enable --now ollama"
echo "    sudo systemctl enable --now khaos-api"
echo "    sudo systemctl enable --now khaos-web"
echo "    sudo systemctl enable --now nginx"
echo ""
echo "═══════════════════════════════════════════════════════════════════"
