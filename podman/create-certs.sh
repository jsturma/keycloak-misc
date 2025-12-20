#!/bin/bash

# Keycloak Certificate Creation Script using CFSSL
# This script automates the creation of CA and server certificates

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CA_DIR="certs/ca"
SERVERS_DIR="${CA_DIR}/servers"
TEMPLATE_DIR="certs-template"
CA_NAME="ca"
DEFAULT_SERVER_NAME="keycloak"

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    local missing_deps=0
    
    if ! command -v cfssl &> /dev/null; then
        print_error "cfssl is not installed. Please install it first."
        echo "  macOS: brew install cfssl"
        echo "  Linux: Visit https://github.com/cloudflare/cfssl/releases"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v cfssljson &> /dev/null; then
        print_error "cfssljson is not installed. Please install it first."
        echo "  macOS: brew install cfssl"
        echo "  Linux: Visit https://github.com/cloudflare/cfssl/releases"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v openssl &> /dev/null; then
        print_error "openssl is not installed. Please install it first."
        missing_deps=$((missing_deps + 1))
    fi
    
    if [ $missing_deps -gt 0 ]; then
        echo ""
        print_error "Missing $missing_deps dependency/dependencies. Please install them before continuing."
        exit 1
    fi
}

check_templates() {
    if [ ! -f "${TEMPLATE_DIR}/ca-cert-config.json" ]; then
        print_error "CA certificate template not found: ${TEMPLATE_DIR}/ca-cert-config.json"
        exit 1
    fi
    
    if [ ! -f "${TEMPLATE_DIR}/cert-config.json" ]; then
        print_error "Server certificate template not found: ${TEMPLATE_DIR}/cert-config.json"
        exit 1
    fi
    
    if [ ! -f "${TEMPLATE_DIR}/ca-config.json" ]; then
        print_error "CA config template not found: ${TEMPLATE_DIR}/ca-config.json"
        exit 1
    fi
}

create_ca() {
    if [ -f "${CA_DIR}/${CA_NAME}.pem" ]; then
        print_info "CA already exists at ${CA_DIR}/${CA_NAME}.pem"
        print_info "Skipping CA creation. Use --force-ca to regenerate."
        return 0
    fi
    
    print_info "Creating new CA..."
    mkdir -p "${CA_DIR}"
    
    cp "${TEMPLATE_DIR}/ca-cert-config.json" "${CA_DIR}/ca-cert-config.json"
    cfssl gencert -initca "${CA_DIR}/ca-cert-config.json" | cfssljson -bare "${CA_DIR}/${CA_NAME}"
    
    print_info "CA created successfully at ${CA_DIR}/${CA_NAME}.pem"
    
    # Set permissions for container use
    chmod 644 "${CA_DIR}/${CA_NAME}.pem" "${CA_DIR}/${CA_NAME}-key.pem" 2>/dev/null || true
    
    # Clean up temporary config
    rm -f "${CA_DIR}/ca-cert-config.json"
}

create_server_cert() {
    local server_name=$1
    
    if [ -z "$server_name" ]; then
        server_name="${DEFAULT_SERVER_NAME}"
    fi
    
    print_info "Creating server certificate: ${server_name}"
    
    # Check if CA exists
    if [ ! -f "${CA_DIR}/${CA_NAME}.pem" ]; then
        print_error "CA not found. Creating CA first..."
        create_ca
    fi
    
    # Create directories
    mkdir -p "${SERVERS_DIR}"
    
    # Copy templates
    cp "${TEMPLATE_DIR}/cert-config.json" "${SERVERS_DIR}/${server_name}-config.json"
    cp "${TEMPLATE_DIR}/ca-config.json" "${CA_DIR}/ca-config.json"
    
    print_info "Edit ${SERVERS_DIR}/${server_name}-config.json to customize CN, hosts, etc. if needed"
    print_warn "Press Enter to continue or Ctrl+C to cancel and edit the config..."
    read -r
    
    # Generate server certificate
    cfssl gencert -ca "${CA_DIR}/${CA_NAME}.pem" \
        -ca-key "${CA_DIR}/${CA_NAME}-key.pem" \
        -config "${CA_DIR}/ca-config.json" \
        -profile server \
        "${SERVERS_DIR}/${server_name}-config.json" | cfssljson -bare "${SERVERS_DIR}/${server_name}"
    
    # Rename files
    mv "${SERVERS_DIR}/${server_name}-key.pem" "${SERVERS_DIR}/${server_name}.key"
    mv "${SERVERS_DIR}/${server_name}.pem" "${SERVERS_DIR}/${server_name}.crt"
    
    # Create full chain certificate
    print_info "Creating full chain certificate..."
    cat "${SERVERS_DIR}/${server_name}.crt" "${CA_DIR}/${CA_NAME}.pem" > "${SERVERS_DIR}/${server_name}-chain.crt"
    
    # Create PKCS12 keystore with full chain
    print_info "Creating PKCS12 keystore..."
    openssl pkcs12 -export \
        -in "${SERVERS_DIR}/${server_name}.crt" \
        -inkey "${SERVERS_DIR}/${server_name}.key" \
        -certfile "${CA_DIR}/${CA_NAME}.pem" \
        -out "${SERVERS_DIR}/${server_name}.p12" \
        -name "${server_name}" \
        -password pass:changeit
    
    # Verify certificate
    print_info "Verifying certificate extensions..."
    openssl x509 -in "${SERVERS_DIR}/${server_name}.crt" -text -noout | grep -A 10 "X509v3 extensions" || true
    
    # Clean up intermediate files
    rm -f "${SERVERS_DIR}/${server_name}-config.json" "${CA_DIR}/ca-config.json" "${SERVERS_DIR}"/*.csr
    
    # Set permissions for container use
    # Certificates: readable by all (644)
    # Private keys: readable by all (644) - acceptable in container volumes
    # Keystores: readable by all (644)
    print_info "Setting permissions for container use..."
    chmod 644 "${SERVERS_DIR}/${server_name}.crt" \
              "${SERVERS_DIR}/${server_name}-chain.crt" \
              "${SERVERS_DIR}/${server_name}.p12" \
              "${SERVERS_DIR}/${server_name}.key" 2>/dev/null || true
    
    print_info "Server certificate created successfully:"
    echo "  Certificate: ${SERVERS_DIR}/${server_name}.crt"
    echo "  Private Key: ${SERVERS_DIR}/${server_name}.key"
    echo "  Full Chain:  ${SERVERS_DIR}/${server_name}-chain.crt"
    echo "  Keystore:    ${SERVERS_DIR}/${server_name}.p12"
    echo ""
    print_info "Permissions set to 644 for container compatibility (keycloak user UID 1000)"
}

regenerate_ca() {
    print_warn "This will regenerate the CA. All existing server certificates will need to be regenerated."
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "Cancelled."
        return 0
    fi
    
    rm -f "${CA_DIR}/${CA_NAME}.pem" "${CA_DIR}/${CA_NAME}-key.pem" "${CA_DIR}/${CA_NAME}.csr"
    create_ca
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [SERVER_NAME]

Create or update Keycloak certificates using CFSSL.

OPTIONS:
    -h, --help              Show this help message
    -c, --create-ca         Create CA only (if it doesn't exist)
    -f, --force-ca           Force regeneration of CA
    -s, --server NAME        Create server certificate (default: keycloak)
    -a, --all                Create CA and default server certificate
    -v, --verify             Verify existing certificates
    -p, --fix-permissions    Fix permissions for container use (readable by UID 1000)

SERVER_NAME:
    Name for the server certificate (default: keycloak)

EXAMPLES:
    $0 --all                    # Create CA and keycloak server cert
    $0 --create-ca              # Create CA only
    $0 --server keycloak         # Create keycloak server cert
    $0 --server new-server       # Create new-server certificate
    $0 --force-ca                # Regenerate CA
    $0 --fix-permissions        # Fix permissions for existing certificates

EOF
}

fix_permissions() {
    print_info "Fixing permissions for container use..."
    
    # Fix CA permissions
    if [ -f "${CA_DIR}/${CA_NAME}.pem" ]; then
        chmod 644 "${CA_DIR}/${CA_NAME}.pem" "${CA_DIR}/${CA_NAME}-key.pem" 2>/dev/null || true
        print_info "Fixed CA permissions"
    fi
    
    # Fix server certificate permissions
    if [ -d "${SERVERS_DIR}" ]; then
        find "${SERVERS_DIR}" -type f \( -name "*.crt" -o -name "*.key" -o -name "*.p12" -o -name "*.pem" \) -exec chmod 644 {} \; 2>/dev/null || true
        print_info "Fixed server certificate permissions in ${SERVERS_DIR}"
    else
        print_warn "No server certificates directory found"
    fi
    
    print_info "Permissions fixed. Files are now readable by container user (UID 1000)"
}

verify_certificates() {
    print_info "Verifying certificates..."
    
    if [ ! -f "${CA_DIR}/${CA_NAME}.pem" ]; then
        print_error "CA not found at ${CA_DIR}/${CA_NAME}.pem"
        return 1
    fi
    
    print_info "CA Certificate:"
    openssl x509 -in "${CA_DIR}/${CA_NAME}.pem" -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After)" || true
    
    echo ""
    
    if [ -d "${SERVERS_DIR}" ]; then
        for cert in "${SERVERS_DIR}"/*.crt; do
            if [ -f "$cert" ] && [[ "$cert" != *"-chain.crt" ]]; then
                server_name=$(basename "$cert" .crt)
                print_info "Server Certificate: ${server_name}"
                openssl x509 -in "$cert" -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After)" || true
                echo ""
            fi
        done
    else
        print_warn "No server certificates found in ${SERVERS_DIR}"
    fi
}

# Main script
main() {
    # Check dependencies
    check_dependencies
    check_templates
    
    # Parse arguments
    if [ $# -eq 0 ]; then
        show_usage
        exit 0
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--create-ca)
                create_ca
                shift
                ;;
            -f|--force-ca)
                regenerate_ca
                shift
                ;;
            -s|--server)
                if [ -z "$2" ]; then
                    print_error "Server name required for --server option"
                    exit 1
                fi
                create_server_cert "$2"
                shift 2
                ;;
            -a|--all)
                create_ca
                create_server_cert "${DEFAULT_SERVER_NAME}"
                shift
                ;;
            -v|--verify)
                verify_certificates
                shift
                ;;
            -p|--fix-permissions)
                fix_permissions
                shift
                ;;
            *)
                # Treat as server name
                create_server_cert "$1"
                shift
                ;;
        esac
    done
}

# Run main function
main "$@"

