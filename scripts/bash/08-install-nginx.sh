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

cat > /etc/nginx/sites-available/khaos << 'EOF'
# Khaos Server Nginx Configuration

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name localhost;
    return 301 https://$host$request_uri;
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    server_name localhost;

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/khaos.crt;
    ssl_certificate_key /etc/nginx/ssl/khaos.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;

    # Logging
    access_log /var/log/nginx/khaos-access.log;
    error_log /var/log/nginx/khaos-error.log;

    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }

    # Ollama proxy (optional, for direct LLM access)
    location /ollama/ {
        rewrite ^/ollama/(.*) /$1 break;
        proxy_pass http://127.0.0.1:11434;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 300s;
    }

    # Frontend (Vue dev server or static files)
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
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

if pidof systemd > /dev/null 2>&1; then
    systemctl enable nginx 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || true
    log "SUCCESS" "Start Nginx" "Nginx started via systemd"
else
    service nginx restart 2>/dev/null || nginx -s reload
    log "SUCCESS" "Start Nginx" "Nginx started"
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
echo "  HTTP:  http://localhost (redirects to HTTPS)"
echo "  HTTPS: https://localhost"
echo "  Routes:"
echo "    /        -> Vue frontend (port 3000)"
echo "    /api/*   -> .NET API (port 5000)"
echo "    /ollama/* -> Ollama API (port 11434)"
echo ""
