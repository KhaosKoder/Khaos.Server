#!/bin/bash
# 04-install-dotnet.sh
# Install .NET 10 SDK and copy API project from templates

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

# Load configuration
if [ -f /etc/khaos/khaos.conf ]; then
    source /etc/khaos/khaos.conf
else
    KHAOS_API_PORT=5000
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                  KHAOS - INSTALL .NET                             ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# Template directory (mounted from Windows host)
TEMPLATE_DIR="/mnt/khaos-cache/templates"

# ============================================================================
# STEP 1: Install .NET SDK
# ============================================================================
log "START" "Install .NET" "Installing .NET 10 SDK..."

# Check if already installed
if command -v dotnet &> /dev/null; then
    CURRENT_VERSION=$(dotnet --version 2>/dev/null)
    log "INFO" "Install .NET" ".NET already installed: $CURRENT_VERSION"
else
    # Use Microsoft's install script from cache or download
    INSTALL_SCRIPT="/mnt/khaos-cache/scripts/dotnet-install.sh"
    
    if [ -f "$INSTALL_SCRIPT" ]; then
        log "INFO" "Install .NET" "Using cached install script"
    else
        log "INFO" "Install .NET" "Downloading install script..."
        curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
        INSTALL_SCRIPT="/tmp/dotnet-install.sh"
    fi
    
    chmod +x "$INSTALL_SCRIPT"
    
    # Install .NET 10 (or latest if 10 not available)
    if "$INSTALL_SCRIPT" --channel 10.0 --install-dir /usr/share/dotnet; then
        log "SUCCESS" "Install .NET" ".NET 10 SDK installed"
    elif "$INSTALL_SCRIPT" --channel STS --install-dir /usr/share/dotnet; then
        log "SUCCESS" "Install .NET" ".NET (latest STS) installed"
    else
        log "FAIL" "Install .NET" "Failed to install .NET SDK"
        exit 1
    fi
    
    # Create symlinks
    ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
fi

# Add to PATH for all users
echo 'export DOTNET_ROOT=/usr/share/dotnet' >> /etc/profile.d/dotnet.sh
echo 'export PATH=$PATH:/usr/share/dotnet' >> /etc/profile.d/dotnet.sh
source /etc/profile.d/dotnet.sh 2>/dev/null || true

DOTNET_VERSION=$(dotnet --version 2>/dev/null || echo "unknown")
log "SUCCESS" "Install .NET" ".NET SDK version: $DOTNET_VERSION"

# ============================================================================
# STEP 2: Create API project structure
# ============================================================================
log "START" "Create Project" "Creating Khaos API project..."

API_PATH="/opt/khaos/apps/api"

# Clean up if exists
rm -rf "$API_PATH"
mkdir -p "$API_PATH"

cd "$API_PATH"

# ============================================================================
# STEP 3: Copy project files from templates
# ============================================================================
log "START" "Copy Templates" "Copying API files from templates..."

if [ -d "$TEMPLATE_DIR/api" ]; then
    # Copy project file
    if [ -f "$TEMPLATE_DIR/api/KhaosApi.csproj" ]; then
        cp "$TEMPLATE_DIR/api/KhaosApi.csproj" "$API_PATH/KhaosApi.csproj"
        log "SUCCESS" "Copy Templates" "Copied KhaosApi.csproj"
    else
        log "FAIL" "Copy Templates" "Template file KhaosApi.csproj not found"
        exit 1
    fi
    
    # Copy Program.cs
    if [ -f "$TEMPLATE_DIR/api/Program.cs" ]; then
        cp "$TEMPLATE_DIR/api/Program.cs" "$API_PATH/Program.cs"
        log "SUCCESS" "Copy Templates" "Copied Program.cs"
    else
        log "FAIL" "Copy Templates" "Template file Program.cs not found"
        exit 1
    fi
else
    log "FAIL" "Copy Templates" "Template directory not found: $TEMPLATE_DIR/api"
    exit 1
fi

# ============================================================================
# STEP 4: Restore NuGet packages
# ============================================================================
log "START" "Restore" "Restoring NuGet packages..."

if dotnet restore; then
    log "SUCCESS" "Restore" "NuGet packages restored"
else
    log "FAIL" "Restore" "Failed to restore packages"
    exit 1
fi

# ============================================================================
# STEP 5: Build project
# ============================================================================
log "START" "Build" "Building API project..."

# Clean any previous build artifacts that may cause issues
rm -rf "$API_PATH/bin" "$API_PATH/obj" 2>/dev/null || true

if dotnet build -c Release --nologo; then
    log "SUCCESS" "Build" "API project built successfully"
else
    log "WARN" "Build" "Build had warnings or errors"
fi

# ============================================================================
# STEP 6: Publish for production
# ============================================================================
log "START" "Publish" "Publishing API for production..."

API_PUBLISH="/opt/khaos/publish/api"
rm -rf "$API_PUBLISH"
mkdir -p "$API_PUBLISH"

if dotnet publish -c Release -o "$API_PUBLISH" --nologo; then
    log "SUCCESS" "Publish" "API published to $API_PUBLISH"
else
    log "FAIL" "Publish" "Failed to publish API"
    exit 1
fi

# ============================================================================
# STEP 7: Set ownership
# ============================================================================
if id khaos &>/dev/null; then
    chown -R khaos:khaos "$API_PATH"
    chown -R khaos:khaos "$API_PUBLISH"
fi

# ============================================================================
# STEP 8: Save config
# ============================================================================
cat > /opt/khaos/config/dotnet.conf << EOF
DOTNET_VERSION=$DOTNET_VERSION
API_PATH=$API_PATH
API_PUBLISH=$API_PUBLISH
API_PORT=$KHAOS_API_PORT
DEV_API_PORT=$((KHAOS_API_PORT + 1))
EOF

log "SUCCESS" "Save Config" ".NET configuration saved"

# ============================================================================
# DONE
# ============================================================================
echo ""
echo -e "${GREEN}✓ .NET setup completed!${NC}"
echo "  SDK: $DOTNET_VERSION"
echo "  Source: $API_PATH"
echo "  Published: $API_PUBLISH"
echo "  Prod Port: $KHAOS_API_PORT"
echo "  Dev Port: $((KHAOS_API_PORT + 1))"
echo ""
