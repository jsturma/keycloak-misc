#!/bin/bash

# Script to create Kubernetes TLS secret for Keycloak from certificates

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
NAMESPACE="${NAMESPACE:-keycloak}"
SECRET_NAME="${SECRET_NAME:-keycloak-tls}"
CERT_DIR="${CERT_DIR:-../podman/certs/ca/servers}"
CERT_FILE="${CERT_FILE:-${CERT_DIR}/keycloak.crt}"
KEY_FILE="${KEY_FILE:-${CERT_DIR}/keycloak.key}"

# Check if certificates exist
if [ ! -f "$CERT_FILE" ]; then
    log_error "Certificate file not found: $CERT_FILE"
    log_info "Generate certificates first:"
    echo "  cd podman"
    echo "  ./create-certs.sh --all"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    log_error "Private key file not found: $KEY_FILE"
    log_info "Generate certificates first:"
    echo "  cd podman"
    echo "  ./create-certs.sh --all"
    exit 1
fi

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
fi

# Check if secret already exists
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    log_warn "Secret $SECRET_NAME already exists in namespace $NAMESPACE"
    read -p "Delete and recreate? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
    else
        log_info "Keeping existing secret. Exiting."
        exit 0
    fi
fi

# Create TLS secret
log_info "Creating TLS secret: $SECRET_NAME in namespace: $NAMESPACE"
log_info "Using certificate: $CERT_FILE"
log_info "Using private key: $KEY_FILE"

kubectl create secret tls "$SECRET_NAME" \
    --cert="$CERT_FILE" \
    --key="$KEY_FILE" \
    -n "$NAMESPACE"

log_info "TLS secret created successfully!"
log_info "You can now deploy Keycloak with HTTPS using:"
echo "  kubectl apply -f k8s/keycloak_start_dev_https.yaml"

