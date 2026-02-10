#!/bin/bash
# 02-install-ollama.sh
# Install Ollama and pull the default model

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load configuration
if [ -f /etc/khaos/khaos.conf ]; then
    source /etc/khaos/khaos.conf
else
    KHAOS_OLLAMA_PORT=11434
fi

# Default model (can be overridden by argument)
MODEL=${1:-"qwen2.5:3b"}

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
echo "║                  KHAOS - INSTALL OLLAMA                           ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# STEP 1: Install Ollama
# ============================================================================
log "START" "Install Ollama" "Installing Ollama..."

if command -v ollama &> /dev/null; then
    CURRENT_VERSION=$(ollama --version 2>/dev/null | head -1)
    log "INFO" "Install Ollama" "Ollama already installed: $CURRENT_VERSION"
else
    # Install using the official script
    if curl -fsSL https://ollama.ai/install.sh | sh; then
        log "SUCCESS" "Install Ollama" "Ollama installed successfully"
    else
        log "FAIL" "Install Ollama" "Failed to install Ollama"
        exit 1
    fi
fi

# ============================================================================
# STEP 2: Start Ollama service
# ============================================================================
log "START" "Start Ollama" "Starting Ollama service..."

# Check if systemd is available (WSL2 may or may not have it)
if pidof systemd > /dev/null 2>&1; then
    # Create systemd override to use custom port
    mkdir -p /etc/systemd/system/ollama.service.d
    cat > /etc/systemd/system/ollama.service.d/override.conf << EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:$KHAOS_OLLAMA_PORT"
EOF
    systemctl daemon-reload
    systemctl enable ollama 2>/dev/null || true
    systemctl restart ollama 2>/dev/null || true
    log "SUCCESS" "Start Ollama" "Ollama service started via systemd on port $KHAOS_OLLAMA_PORT"
else
    # Start manually in background
    log "INFO" "Start Ollama" "Systemd not available, starting Ollama manually..."
    
    # Kill any existing instance
    pkill ollama 2>/dev/null || true
    sleep 1
    
    # Start Ollama serve in background with configured port
    export OLLAMA_HOST="0.0.0.0:$KHAOS_OLLAMA_PORT"
    nohup ollama serve > /var/log/khaos/ollama.log 2>&1 &
    sleep 3
    
    # Verify it's running
    if curl -s http://localhost:$KHAOS_OLLAMA_PORT/api/tags > /dev/null 2>&1; then
        log "SUCCESS" "Start Ollama" "Ollama service started manually on port $KHAOS_OLLAMA_PORT"
    else
        log "WARN" "Start Ollama" "Ollama may not be running, check /var/log/khaos/ollama.log"
    fi
fi

# ============================================================================
# STEP 3: Pull the model
# ============================================================================
log "START" "Pull Model" "Pulling model: $MODEL (this may take a while)..."

# Ensure ollama commands use the correct port
export OLLAMA_HOST="http://localhost:$KHAOS_OLLAMA_PORT"

# Check if model is already downloaded
EXISTING_MODELS=$(ollama list 2>/dev/null | grep -c "$MODEL" || echo "0")

if [ "$EXISTING_MODELS" -gt 0 ]; then
    log "INFO" "Pull Model" "Model $MODEL already exists on port $KHAOS_OLLAMA_PORT"
else
    log "INFO" "Pull Model" "Pulling to Ollama server on port $KHAOS_OLLAMA_PORT..."
    if ollama pull "$MODEL"; then
        log "SUCCESS" "Pull Model" "Model $MODEL pulled successfully"
    else
        log "FAIL" "Pull Model" "Failed to pull model $MODEL"
        exit 1
    fi
fi

# ============================================================================
# STEP 4: Test the model
# ============================================================================
log "START" "Test Model" "Testing model with a simple prompt..."

TEST_RESPONSE=$(echo "Say 'Hello Khaos' in exactly those words" | ollama run "$MODEL" 2>/dev/null | head -1)

if [ -n "$TEST_RESPONSE" ]; then
    log "SUCCESS" "Test Model" "Model responded: $TEST_RESPONSE"
else
    log "WARN" "Test Model" "Model did not respond (may need manual verification)"
fi

# ============================================================================
# STEP 5: Save config
# ============================================================================
echo "OLLAMA_MODEL=$MODEL" > /opt/khaos/config/ollama.conf
echo "OLLAMA_HOST=http://localhost:$KHAOS_OLLAMA_PORT" >> /opt/khaos/config/ollama.conf
echo "OLLAMA_PORT=$KHAOS_OLLAMA_PORT" >> /opt/khaos/config/ollama.conf

log "SUCCESS" "Save Config" "Ollama configuration saved (port $KHAOS_OLLAMA_PORT)"

# ============================================================================
# DONE
# ============================================================================
echo ""
echo -e "${GREEN}✓ Ollama setup completed!${NC}"
echo "  Model: $MODEL"
echo "  API: http://localhost:11434"
echo ""
