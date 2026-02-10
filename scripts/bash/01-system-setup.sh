#!/bin/bash
# 01-system-setup.sh
# Update system packages and install base tools

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
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

# Create log directory
mkdir -p /var/log/khaos
touch /var/log/khaos/setup.log

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                  KHAOS - SYSTEM SETUP                             ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# STEP 1: Update package lists
# ============================================================================
log "START" "Update Packages" "Updating package lists..."

export DEBIAN_FRONTEND=noninteractive

if apt-get update -qq; then
    log "SUCCESS" "Update Packages" "Package lists updated"
else
    log "FAIL" "Update Packages" "Failed to update package lists"
    exit 1
fi

# ============================================================================
# STEP 2: Upgrade existing packages
# ============================================================================
log "START" "Upgrade Packages" "Upgrading existing packages..."

if apt-get upgrade -y -qq; then
    log "SUCCESS" "Upgrade Packages" "Packages upgraded"
else
    log "WARN" "Upgrade Packages" "Some packages may not have upgraded"
fi

# ============================================================================
# STEP 3: Install essential tools
# ============================================================================
log "START" "Install Tools" "Installing essential tools..."

TOOLS="curl wget git unzip jq htop nano ca-certificates gnupg lsb-release apt-transport-https software-properties-common build-essential zstd net-tools"

if apt-get install -y -qq $TOOLS; then
    log "SUCCESS" "Install Tools" "Essential tools installed"
else
    log "FAIL" "Install Tools" "Failed to install essential tools"
    exit 1
fi

# ============================================================================
# STEP 4: Create Khaos directories
# ============================================================================
log "START" "Create Dirs" "Creating Khaos directory structure..."

mkdir -p /opt/khaos/apps/api
mkdir -p /opt/khaos/apps/web
mkdir -p /opt/khaos/scripts
mkdir -p /opt/khaos/config
mkdir -p /opt/khaos/publish/api
mkdir -p /opt/khaos/publish/web
mkdir -p /var/log/khaos

# Copy management scripts from cache
SCRIPT_CACHE="/mnt/khaos-cache/scripts/bash"
if [ -d "$SCRIPT_CACHE" ]; then
    for script in dev-start.sh dev-stop.sh build.sh publish.sh deploy.sh prod-start.sh prod-stop.sh clean.sh test.sh status.sh; do
        if [ -f "$SCRIPT_CACHE/$script" ]; then
            cp "$SCRIPT_CACHE/$script" /opt/khaos/scripts/
            chmod +x /opt/khaos/scripts/$script
        fi
    done
    log "INFO" "Create Dirs" "Management scripts copied to /opt/khaos/scripts"
fi

# Set ownership to khaos user (if exists)
if id khaos &>/dev/null; then
    chown -R khaos:khaos /opt/khaos
    chown -R khaos:khaos /var/log/khaos
fi

log "SUCCESS" "Create Dirs" "Directory structure created at /opt/khaos"

# ============================================================================
# STEP 5: Configure locale
# ============================================================================
log "START" "Locale" "Configuring locale..."

locale-gen en_US.UTF-8 > /dev/null 2>&1
update-locale LANG=en_US.UTF-8 > /dev/null 2>&1

log "SUCCESS" "Locale" "Locale set to en_US.UTF-8"

# ============================================================================
# STEP 6: Check GPU (for Ollama)
# ============================================================================
log "START" "GPU Check" "Checking for NVIDIA GPU..."

if command -v nvidia-smi &> /dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "Unknown")
    log "SUCCESS" "GPU Check" "NVIDIA GPU detected: $GPU_INFO"
    echo "GPU_AVAILABLE=true" > /opt/khaos/config/gpu.conf
    echo "GPU_NAME=$GPU_INFO" >> /opt/khaos/config/gpu.conf
else
    log "INFO" "GPU Check" "No NVIDIA GPU detected (will use CPU for LLM)"
    echo "GPU_AVAILABLE=false" > /opt/khaos/config/gpu.conf
fi

# ============================================================================
# DONE
# ============================================================================
echo ""
echo -e "${GREEN}✓ System setup completed successfully!${NC}"
echo ""
