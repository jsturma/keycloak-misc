#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
KEYCLOAK_USER="keycloak"
KEYCLOAK_HOME="/opt/keycloak"
KEYCLOAK_CONF_DIR="${KEYCLOAK_HOME}/conf"
KEYCLOAK_CONF_FILE="${KEYCLOAK_CONF_DIR}/keycloak.conf"
TLS_DIR="/etc/keycloak/tls"
SYSTEMD_SERVICE="/etc/systemd/system/keycloak.service"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_keycloak_user() {
    if ! id -u "${KEYCLOAK_USER}" &>/dev/null; then
        log_error "User '${KEYCLOAK_USER}' does not exist. Please create it first:"
        echo "  sudo useradd -r -s /bin/false ${KEYCLOAK_USER}"
        exit 1
    fi
    log_info "User '${KEYCLOAK_USER}' exists"
}

check_keycloak_installation() {
    if [[ ! -d "${KEYCLOAK_HOME}" ]]; then
        log_error "Keycloak is not installed at ${KEYCLOAK_HOME}"
        exit 1
    fi
    
    if [[ ! -f "${KEYCLOAK_HOME}/bin/kc.sh" ]]; then
        log_error "Keycloak binary not found at ${KEYCLOAK_HOME}/bin/kc.sh"
        exit 1
    fi
    
    log_info "Keycloak installation found at ${KEYCLOAK_HOME}"
}

check_java() {
    if ! command -v java &> /dev/null; then
        log_error "Java is not installed or not in PATH"
        exit 1
    fi
    
    JAVA_BIN=$(readlink -f $(which java))
    log_info "Java found at: ${JAVA_BIN}"
}

check_tls_certificates() {
    if [[ ! -f "${TLS_DIR}/tls.crt" ]] || [[ ! -f "${TLS_DIR}/tls.key" ]]; then
        log_warn "TLS certificates not found at ${TLS_DIR}/"
        log_warn "Please ensure tls.crt and tls.key are placed in ${TLS_DIR}/ before starting Keycloak"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_info "TLS certificates found"
    fi
}

# Get hostname from user
get_hostname() {
    if [[ -z "${HOSTNAME:-}" ]]; then
        read -p "Enter Keycloak hostname (e.g., https://auth.example.com): " HOSTNAME
        if [[ -z "${HOSTNAME}" ]]; then
            log_error "Hostname cannot be empty"
            exit 1
        fi
    fi
    log_info "Using hostname: ${HOSTNAME}"
}

# Step 1: Create keycloak.conf
create_keycloak_conf() {
    log_info "Creating Keycloak configuration file..."
    
    mkdir -p "${KEYCLOAK_CONF_DIR}"
    chown root:root "${KEYCLOAK_CONF_DIR}"
    chmod 755 "${KEYCLOAK_CONF_DIR}"
    
    cat > "${KEYCLOAK_CONF_FILE}" <<EOF
############################
# NETWORK
############################

http-enabled=false
https-port=443


############################
# TLS
############################

https-certificate-file=${TLS_DIR}/tls.crt
https-certificate-key-file=${TLS_DIR}/tls.key


############################
# HOSTNAME
############################

hostname=${HOSTNAME}
hostname-strict=true
hostname-strict-https=true


############################
# MANAGEMENT
############################

http-management-scheme=inherited
EOF

    chown root:root "${KEYCLOAK_CONF_FILE}"
    chmod 644 "${KEYCLOAK_CONF_FILE}"
    
    log_info "Configuration file created at ${KEYCLOAK_CONF_FILE}"
}

# Step 2: Create TLS directory and set permissions
setup_tls_directory() {
    log_info "Setting up TLS directory and permissions..."
    
    mkdir -p "${TLS_DIR}"
    chown root:${KEYCLOAK_USER} "${TLS_DIR}"
    chmod 750 "${TLS_DIR}"
    
    # Set permissions on certificates if they exist
    if [[ -f "${TLS_DIR}/tls.key" ]]; then
        chown root:${KEYCLOAK_USER} "${TLS_DIR}/tls.key"
        chmod 640 "${TLS_DIR}/tls.key"
        log_info "Set permissions on tls.key"
    fi
    
    if [[ -f "${TLS_DIR}/tls.crt" ]]; then
        chown root:${KEYCLOAK_USER} "${TLS_DIR}/tls.crt"
        chmod 644 "${TLS_DIR}/tls.crt"
        log_info "Set permissions on tls.crt"
    fi
    
    log_info "TLS directory configured at ${TLS_DIR}"
}

# Step 3: Set capabilities on Java binary
setup_java_capabilities() {
    log_info "Setting capabilities on Java binary to allow binding to port 443..."
    
    JAVA_BIN=$(readlink -f $(which java))
    
    if setcap 'cap_net_bind_service=+ep' "${JAVA_BIN}" 2>/dev/null; then
        log_info "Capabilities set successfully"
        
        # Verify
        if getcap "${JAVA_BIN}" | grep -q "cap_net_bind_service=ep"; then
            log_info "Capabilities verified: $(getcap ${JAVA_BIN})"
        else
            log_warn "Could not verify capabilities"
        fi
    else
        log_error "Failed to set capabilities on Java binary"
        log_error "You may need to install libcap2-bin: apt-get install libcap2-bin"
        exit 1
    fi
    
    log_warn "Note: Capabilities may be lost after Java upgrades"
}

# Step 4: Create systemd service file
create_systemd_service() {
    log_info "Creating systemd service file..."
    
    cat > "${SYSTEMD_SERVICE}" <<EOF
[Unit]
Description=Keycloak Identity Server
After=network.target

[Service]
Type=exec
User=${KEYCLOAK_USER}
Group=${KEYCLOAK_USER}

WorkingDirectory=${KEYCLOAK_HOME}

ExecStart=${KEYCLOAK_HOME}/bin/kc.sh start-dev

Environment=KC_HOME=${KEYCLOAK_HOME}
Environment=KC_CONF_DIR=${KEYCLOAK_CONF_DIR}

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${KEYCLOAK_HOME} /etc/keycloak
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

Restart=on-failure
RestartSec=5

LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "${SYSTEMD_SERVICE}"
    log_info "Systemd service file created at ${SYSTEMD_SERVICE}"
}

# Step 5: Reload systemd and start service
reload_and_start_service() {
    log_info "Reloading systemd daemon..."
    systemctl daemon-reexec
    systemctl daemon-reload
    
    log_info "Enabling Keycloak service..."
    systemctl enable keycloak
    
    log_info "Starting Keycloak service..."
    if systemctl start keycloak; then
        log_info "Keycloak service started successfully"
    else
        log_error "Failed to start Keycloak service"
        log_error "Check status with: systemctl status keycloak"
        log_error "Check logs with: journalctl -u keycloak -f"
        exit 1
    fi
}

# Step 6: Validation
validate_setup() {
    log_info "Validating setup..."
    
    echo
    log_info "=== Service Status ==="
    systemctl status keycloak --no-pager -l || true
    
    echo
    log_info "=== Port Check ==="
    if ss -tulpen | grep -q "java.*:443"; then
        log_info "✓ Keycloak is listening on port 443"
        ss -tulpen | grep java || true
    else
        log_warn "Keycloak is not listening on port 443 yet (may need a moment to start)"
    fi
    
    if ss -tulpen | grep -q "java.*:8080"; then
        log_warn "⚠ Keycloak is also listening on port 8080 (unexpected)"
    else
        log_info "✓ No HTTP listener on port 8080"
    fi
    
    echo
    log_info "=== Validation Complete ==="
    log_info "To check service status: systemctl status keycloak"
    log_info "To view logs: journalctl -u keycloak -f"
    log_info "To test HTTPS: curl -vk ${HOSTNAME}"
    log_info "To test OIDC: curl -s ${HOSTNAME}/realms/master/.well-known/openid-configuration | jq .issuer"
}

# Main execution
main() {
    echo "=========================================="
    echo "  Keycloak Start-Dev Setup Script"
    echo "=========================================="
    echo
    
    check_root
    check_keycloak_user
    check_keycloak_installation
    check_java
    get_hostname
    check_tls_certificates
    
    echo
    log_info "Starting setup process..."
    echo
    
    create_keycloak_conf
    setup_tls_directory
    setup_java_capabilities
    create_systemd_service
    reload_and_start_service
    
    echo
    sleep 3  # Give service a moment to start
    validate_setup
    
    echo
    log_info "Setup complete! ✓"
}

# Run main function
main

