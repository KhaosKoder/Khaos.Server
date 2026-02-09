#!/bin/bash
# 03-install-python.sh
# Install Python 3.12 and RAG/ML libraries

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
echo "║                  KHAOS - INSTALL PYTHON                           ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# STEP 1: Add deadsnakes PPA for Python 3.12
# ============================================================================
log "START" "Add PPA" "Adding Python PPA..."

if add-apt-repository -y ppa:deadsnakes/ppa > /dev/null 2>&1; then
    apt-get update -qq
    log "SUCCESS" "Add PPA" "Python PPA added"
else
    log "WARN" "Add PPA" "Could not add PPA, will try default repositories"
fi

# ============================================================================
# STEP 2: Install Python 3.12
# ============================================================================
log "START" "Install Python" "Installing Python 3.12..."

export DEBIAN_FRONTEND=noninteractive

if apt-get install -y -qq python3.12 python3.12-venv python3.12-dev python3-pip; then
    PYTHON_VERSION=$(python3.12 --version)
    log "SUCCESS" "Install Python" "$PYTHON_VERSION installed"
else
    log "FAIL" "Install Python" "Failed to install Python 3.12"
    exit 1
fi

# ============================================================================
# STEP 3: Create virtual environment
# ============================================================================
log "START" "Create Venv" "Creating virtual environment..."

VENV_PATH="/opt/khaos/venv"

if python3.12 -m venv $VENV_PATH; then
    log "SUCCESS" "Create Venv" "Virtual environment created at $VENV_PATH"
else
    log "FAIL" "Create Venv" "Failed to create virtual environment"
    exit 1
fi

# Activate venv for subsequent commands
source $VENV_PATH/bin/activate

# Upgrade pip
pip install --upgrade pip -q

# ============================================================================
# STEP 4: Install RAG/ML libraries
# ============================================================================
log "START" "Install Libs" "Installing RAG/ML libraries..."

PACKAGES=(
    "langchain"
    "langchain-community"
    "sentence-transformers"
    "chromadb"
    "httpx"
    "redis"
    "psycopg2-binary"  # PostgreSQL adapter
    "python-dotenv"
)

for pkg in "${PACKAGES[@]}"; do
    log "INFO" "Install Libs" "Installing $pkg..."
    if pip install "$pkg" -q; then
        log "SUCCESS" "Install Libs" "$pkg installed"
    else
        log "WARN" "Install Libs" "Failed to install $pkg (continuing...)"
    fi
done

# ============================================================================
# STEP 5: Save configuration
# ============================================================================
log "START" "Save Config" "Saving Python configuration..."

cat > /opt/khaos/config/python.conf << EOF
PYTHON_VERSION=3.12
VENV_PATH=$VENV_PATH
PYTHON_BIN=$VENV_PATH/bin/python
PIP_BIN=$VENV_PATH/bin/pip
EOF

# Create activation script for convenience
cat > /opt/khaos/activate.sh << 'EOF'
#!/bin/bash
source /opt/khaos/venv/bin/activate
EOF
chmod +x /opt/khaos/activate.sh

# Set ownership
chown -R khaos:khaos /opt/khaos

log "SUCCESS" "Save Config" "Python configuration saved"

# ============================================================================
# STEP 6: Verify installation
# ============================================================================
log "START" "Verify" "Verifying Python installation..."

$VENV_PATH/bin/python -c "import langchain; import chromadb; import redis; print('All imports successful')" 2>/dev/null

if [ $? -eq 0 ]; then
    log "SUCCESS" "Verify" "All Python packages verified"
else
    log "WARN" "Verify" "Some packages may not be properly installed"
fi

# ============================================================================
# DONE
# ============================================================================
echo ""
echo -e "${GREEN}✓ Python setup completed!${NC}"
echo "  Python: $($VENV_PATH/bin/python --version)"
echo "  Venv: $VENV_PATH"
echo "  Activate: source /opt/khaos/activate.sh"
echo ""
