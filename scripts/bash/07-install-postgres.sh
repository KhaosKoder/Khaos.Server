#!/bin/bash
# 07-install-postgres.sh
# Install PostgreSQL for persistent storage

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
    KHAOS_POSTGRES_PORT=5432
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
echo "║                  KHAOS - INSTALL POSTGRESQL                       ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# STEP 1: Install PostgreSQL
# ============================================================================
log "START" "Install Postgres" "Installing PostgreSQL 16..."

export DEBIAN_FRONTEND=noninteractive

# Add PostgreSQL repository for version 16
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

apt-get update -qq

if apt-get install -y -qq postgresql-16 postgresql-contrib-16; then
    PG_VERSION=$(psql --version | head -1)
    log "SUCCESS" "Install Postgres" "PostgreSQL installed: $PG_VERSION"
else
    log "FAIL" "Install Postgres" "Failed to install PostgreSQL"
    exit 1
fi

# ============================================================================
# STEP 2: Start PostgreSQL
# ============================================================================
log "START" "Start Postgres" "Starting PostgreSQL..."

# Check if systemd is available
if pidof systemd > /dev/null 2>&1; then
    systemctl enable postgresql 2>/dev/null || true
    systemctl start postgresql 2>/dev/null || true
    log "SUCCESS" "Start Postgres" "PostgreSQL started via systemd"
else
    # Start manually
    service postgresql start 2>/dev/null || pg_ctlcluster 16 main start
    log "SUCCESS" "Start Postgres" "PostgreSQL started"
fi

sleep 2

# ============================================================================
# STEP 3: Create Khaos database and user
# ============================================================================
log "START" "Create DB" "Creating Khaos database and user..."

# Create user and database
sudo -u postgres psql -c "CREATE USER khaos WITH PASSWORD 'khaos';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE khaosdb OWNER khaos;" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE khaosdb TO khaos;" 2>/dev/null || true

log "SUCCESS" "Create DB" "Database 'khaosdb' created with user 'khaos'"

# ============================================================================
# STEP 4: Create key/value table
# ============================================================================
log "START" "Create Table" "Creating kv_store table..."

sudo -u postgres psql -d khaosdb << 'EOF'
CREATE TABLE IF NOT EXISTS kv_store (
    key VARCHAR(255) PRIMARY KEY,
    value JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_kv_store_updated_at ON kv_store;
CREATE TRIGGER update_kv_store_updated_at
    BEFORE UPDATE ON kv_store
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

GRANT ALL ON kv_store TO khaos;
EOF

log "SUCCESS" "Create Table" "kv_store table created"

# ============================================================================
# STEP 5: Configure for local connections
# ============================================================================
log "START" "Configure" "Configuring PostgreSQL for local connections..."

PG_CONF="/etc/postgresql/16/main/postgresql.conf"
PG_HBA="/etc/postgresql/16/main/pg_hba.conf"

# Configure custom port
if [ "$KHAOS_POSTGRES_PORT" != "5432" ]; then
    sed -i "s/^port = .*/port = $KHAOS_POSTGRES_PORT/" "$PG_CONF" 2>/dev/null || true
    sed -i "s/^#port = .*/port = $KHAOS_POSTGRES_PORT/" "$PG_CONF" 2>/dev/null || true
    # Ensure port is set
    if ! grep -q "^port = $KHAOS_POSTGRES_PORT" "$PG_CONF"; then
        echo "port = $KHAOS_POSTGRES_PORT" >> "$PG_CONF"
    fi
fi

# Allow local connections with password
if ! grep -q "khaos" "$PG_HBA"; then
    echo "local   khaosdb         khaos                                   md5" >> "$PG_HBA"
    echo "host    khaosdb         khaos           127.0.0.1/32            md5" >> "$PG_HBA"
fi

# Restart to apply changes
if pidof systemd > /dev/null 2>&1; then
    systemctl restart postgresql
else
    service postgresql restart 2>/dev/null || pg_ctlcluster 16 main restart
fi

log "SUCCESS" "Configure" "PostgreSQL configured"

# ============================================================================
# STEP 6: Test connection
# ============================================================================
log "START" "Test" "Testing PostgreSQL connection..."

if PGPASSWORD=khaos psql -U khaos -d khaosdb -h localhost -p "$KHAOS_POSTGRES_PORT" -c "SELECT 1;" > /dev/null 2>&1; then
    log "SUCCESS" "Test" "PostgreSQL connection successful on port $KHAOS_POSTGRES_PORT"
else
    log "WARN" "Test" "Could not connect to PostgreSQL"
fi

# ============================================================================
# STEP 7: Save config
# ============================================================================
cat > /opt/khaos/config/postgres.conf << EOF
PG_HOST=localhost
PG_PORT=$KHAOS_POSTGRES_PORT
PG_DATABASE=khaosdb
PG_USER=khaos
PG_PASSWORD=khaos
PG_CONNECTION_STRING=Host=localhost;Port=$KHAOS_POSTGRES_PORT;Database=khaosdb;Username=khaos;Password=khaos
EOF

log "SUCCESS" "Save Config" "PostgreSQL configuration saved"

# ============================================================================
# DONE
# ============================================================================
echo ""
echo -e "${GREEN}✓ PostgreSQL setup completed!${NC}"
echo "  Version: $PG_VERSION"
echo "  Database: khaosdb"
echo "  User: khaos / khaos"
echo "  Port: $KHAOS_POSTGRES_PORT"
echo ""
