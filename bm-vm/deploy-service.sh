#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_FILE="${SCRIPT_DIR}/keycloak.service"
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

check_service_file() {
    if [[ ! -f "${SERVICE_FILE}" ]]; then
        log_error "Service file not found: ${SERVICE_FILE}"
        exit 1
    fi
    log_info "Service file found: ${SERVICE_FILE}"
}

deploy_service() {
    log_info "Copying service file to ${SYSTEMD_SERVICE}..."
    
    cp "${SERVICE_FILE}" "${SYSTEMD_SERVICE}"
    chmod 644 "${SYSTEMD_SERVICE}"
    
    log_info "Service file deployed successfully"
}

reload_systemd() {
    log_info "Reloading systemd daemon..."
    systemctl daemon-reexec
    systemctl daemon-reload
    log_info "Systemd daemon reloaded"
}

enable_service() {
    log_info "Enabling Keycloak service..."
    if systemctl enable keycloak; then
        log_info "Service enabled successfully"
    else
        log_error "Failed to enable service"
        exit 1
    fi
}

show_status() {
    echo
    log_info "=== Service Status ==="
    systemctl status keycloak --no-pager -l || true
}

show_commands() {
    echo
    log_info "=== Useful Commands ==="
    echo "  Start service:    sudo systemctl start keycloak"
    echo "  Stop service:     sudo systemctl stop keycloak"
    echo "  Restart service:  sudo systemctl restart keycloak"
    echo "  Check status:     systemctl status keycloak"
    echo "  View logs:        journalctl -u keycloak -f"
    echo "  Disable service:  sudo systemctl disable keycloak"
}

# Main execution
main() {
    echo "=========================================="
    echo "  Keycloak Service Deployment Script"
    echo "=========================================="
    echo
    
    check_root
    check_service_file
    
    echo
    log_info "Deploying Keycloak systemd service..."
    echo
    
    deploy_service
    reload_systemd
    enable_service
    
    echo
    log_info "Service deployment complete! ✓"
    log_warn "Note: The service is enabled but not started automatically."
    log_warn "Start it manually with: sudo systemctl start keycloak"
    
    show_commands
    
    # Ask if user wants to start the service
    echo
    read -p "Start the Keycloak service now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Starting Keycloak service..."
        if systemctl start keycloak; then
            log_info "Service started successfully"
            sleep 2
            show_status
        else
            log_error "Failed to start service"
            log_error "Check logs with: journalctl -u keycloak -f"
            exit 1
        fi
    fi
}

# Run main function
main

