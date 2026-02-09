#!/bin/bash
# 05-install-node-vue.sh
# Install Node.js 22 and copy Vue 3 + Vuetify frontend from templates

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
echo "║                  KHAOS - INSTALL NODE + VUE                       ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# Template directory (mounted from Windows host)
TEMPLATE_DIR="/mnt/khaos-cache/templates"

# ============================================================================
# STEP 1: Install Node.js 22
# ============================================================================
log "START" "Install Node" "Installing Node.js 22 LTS..."

# Add NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1

if apt-get install -y -qq nodejs; then
    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    log "SUCCESS" "Install Node" "Node $NODE_VERSION, npm $NPM_VERSION installed"
else
    log "FAIL" "Install Node" "Failed to install Node.js"
    exit 1
fi

# ============================================================================
# STEP 2: Create Vue project directory
# ============================================================================
log "START" "Create Vue" "Creating Vue 3 + Vuetify project..."

WEB_PATH="/opt/khaos/apps/web"

# Clean up if exists
rm -rf "$WEB_PATH"
mkdir -p "$WEB_PATH/src/views"
mkdir -p "$WEB_PATH/src/components"
mkdir -p "$WEB_PATH/src/stores"
mkdir -p "$WEB_PATH/public"

cd "$WEB_PATH"

# ============================================================================
# STEP 3: Copy template files
# ============================================================================
log "START" "Copy Templates" "Copying Vue files from templates..."

if [ -d "$TEMPLATE_DIR/web" ]; then
    # Copy root config files
    cp "$TEMPLATE_DIR/web/package.json" "$WEB_PATH/" 2>/dev/null && log "INFO" "Copy Templates" "Copied package.json"
    cp "$TEMPLATE_DIR/web/vite.config.ts" "$WEB_PATH/" 2>/dev/null && log "INFO" "Copy Templates" "Copied vite.config.ts"
    cp "$TEMPLATE_DIR/web/tsconfig.json" "$WEB_PATH/" 2>/dev/null && log "INFO" "Copy Templates" "Copied tsconfig.json"
    cp "$TEMPLATE_DIR/web/index.html" "$WEB_PATH/" 2>/dev/null && log "INFO" "Copy Templates" "Copied index.html"
    
    # Copy src files
    cp "$TEMPLATE_DIR/web/src/main.ts" "$WEB_PATH/src/" 2>/dev/null && log "INFO" "Copy Templates" "Copied main.ts"
    cp "$TEMPLATE_DIR/web/src/App.vue" "$WEB_PATH/src/" 2>/dev/null && log "INFO" "Copy Templates" "Copied App.vue"
    
    # Copy views
    if [ -d "$TEMPLATE_DIR/web/src/views" ]; then
        cp "$TEMPLATE_DIR/web/src/views/"*.vue "$WEB_PATH/src/views/" 2>/dev/null
        log "INFO" "Copy Templates" "Copied view components"
    fi
    
    log "SUCCESS" "Copy Templates" "All template files copied"
else
    log "FAIL" "Copy Templates" "Template directory not found: $TEMPLATE_DIR/web"
    exit 1
fi

# ============================================================================
# STEP 4: Install npm dependencies
# ============================================================================
log "START" "Dependencies" "Installing npm dependencies (this may take a minute)..."

cd "$WEB_PATH"
npm install > /dev/null 2>&1

if [ $? -eq 0 ]; then
    log "SUCCESS" "Dependencies" "npm dependencies installed"
else
    log "WARN" "Dependencies" "Some npm packages may have issues"
fi

# ============================================================================
# STEP 5: Set ownership
# ============================================================================
chown -R khaos:khaos "$WEB_PATH"

# ============================================================================
# STEP 6: Save config
# ============================================================================
cat > /opt/khaos/config/node.conf << EOF
NODE_VERSION=$NODE_VERSION
NPM_VERSION=$NPM_VERSION
WEB_PATH=$WEB_PATH
WEB_PORT=3000
EOF

log "SUCCESS" "Save Config" "Node configuration saved"

# ============================================================================
# DONE
# ============================================================================
echo ""
echo -e "${GREEN}✓ Node + Vue setup completed!${NC}"
echo "  Node: $NODE_VERSION"
echo "  Web: $WEB_PATH"
echo "  Run: cd $WEB_PATH && npm run dev"
echo ""
