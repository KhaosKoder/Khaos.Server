#!/bin/bash
# 08-install-nginx.sh
# Install Nginx as reverse proxy with SSL

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
    KHAOS_WEB_PORT=3000
    KHAOS_API_PORT=5000
    KHAOS_OLLAMA_PORT=11434
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
echo "║                  KHAOS - INSTALL NGINX                            ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# STEP 1: Install Nginx
# ============================================================================
log "START" "Install Nginx" "Installing Nginx..."

export DEBIAN_FRONTEND=noninteractive

if apt-get install -y -qq nginx; then
    NGINX_VERSION=$(nginx -v 2>&1)
    log "SUCCESS" "Install Nginx" "Nginx installed"
else
    log "FAIL" "Install Nginx" "Failed to install Nginx"
    exit 1
fi

# ============================================================================
# STEP 2: Create SSL directory
# ============================================================================
log "START" "SSL Setup" "Setting up SSL directory..."

mkdir -p /etc/nginx/ssl
chmod 700 /etc/nginx/ssl

log "SUCCESS" "SSL Setup" "SSL directory created"

# ============================================================================
# STEP 3: Generate self-signed certificate
# ============================================================================
log "START" "Generate Cert" "Generating self-signed SSL certificate..."

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/khaos.key \
    -out /etc/nginx/ssl/khaos.crt \
    -subj "/C=US/ST=Local/L=Local/O=Khaos/CN=localhost" \
    2>/dev/null

log "SUCCESS" "Generate Cert" "Self-signed certificate generated"

# ============================================================================
# STEP 4: Create Nginx configuration
# ============================================================================
log "START" "Configure" "Creating Nginx configuration..."

cat > /etc/nginx/sites-available/khaos << EOF
# Khaos Server Nginx Configuration
# Serves static Vue files and proxies API requests

server {
    listen $KHAOS_WEB_PORT;
    server_name localhost;

    # Logging
    access_log /var/log/nginx/khaos-access.log;
    error_log /var/log/nginx/khaos-error.log;

    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:$KHAOS_API_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }

    # Ollama proxy (optional, for direct LLM access)
    location /ollama/ {
        rewrite ^/ollama/(.*) /\$1 break;
        proxy_pass http://127.0.0.1:$KHAOS_OLLAMA_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 300s;
    }

    # Frontend - serve static files from published Vue build
    location / {
        root /opt/khaos/publish/web;
        index index.html;
        try_files \$uri \$uri/ /index.html;
        
        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
}
EOF

# Enable the site
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/khaos /etc/nginx/sites-enabled/khaos

log "SUCCESS" "Configure" "Nginx configuration created"

# ============================================================================
# STEP 5: Test configuration
# ============================================================================
log "START" "Test Config" "Testing Nginx configuration..."

if nginx -t 2>/dev/null; then
    log "SUCCESS" "Test Config" "Nginx configuration is valid"
else
    log "FAIL" "Test Config" "Nginx configuration test failed"
    nginx -t
    exit 1
fi

# ============================================================================
# STEP 6: Start Nginx
# ============================================================================
log "START" "Start Nginx" "Starting Nginx..."

# Stop any existing nginx first
pkill -9 nginx 2>/dev/null || true
sleep 1

# Remove stale PID file
rm -f /run/nginx.pid 2>/dev/null || true

if pidof systemd > /dev/null 2>&1; then
    systemctl enable nginx 2>/dev/null || true
    systemctl start nginx 2>/dev/null || true
    log "SUCCESS" "Start Nginx" "Nginx started via systemd"
else
    # Start nginx directly
    nginx 2>/dev/null || true
    sleep 1
    if pgrep nginx > /dev/null; then
        log "SUCCESS" "Start Nginx" "Nginx started"
    else
        log "WARN" "Start Nginx" "Nginx may not have started (port 80/443 may be in use)"
    fi
fi

# ============================================================================
# STEP 7: Save config
# ============================================================================
cat > /opt/khaos/config/nginx.conf << EOF
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443
NGINX_SSL_CERT=/etc/nginx/ssl/khaos.crt
NGINX_SSL_KEY=/etc/nginx/ssl/khaos.key
EOF

log "SUCCESS" "Save Config" "Nginx configuration saved"

# ============================================================================
# DONE
# ============================================================================
echo ""
echo -e "${GREEN}✓ Nginx setup completed!${NC}"
echo "  Listens on port $KHAOS_WEB_PORT"
echo "  Routes:"
echo "    /         -> Static files from /opt/khaos/publish/web"
echo "    /api/*    -> .NET API (port $KHAOS_API_PORT)"
echo "    /ollama/* -> Ollama API (port $KHAOS_OLLAMA_PORT)"
echo ""
