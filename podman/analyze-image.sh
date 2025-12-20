#!/bin/bash

# Script to analyze Docker/Podman images using dive
# Helps identify optimization opportunities in container images

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="${1:-keycloak:latest}"
CI_MODE="${CI_MODE:-false}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if dive is installed
check_dive() {
    if ! command -v dive &> /dev/null; then
        log_error "dive is not installed"
        echo ""
        echo "Install dive:"
        echo "  macOS:   brew install dive"
        echo "  Linux:   See https://github.com/wagoodman/dive#installation"
        echo "  Windows: See https://github.com/wagoodman/dive#installation"
        echo ""
        echo "Or use Docker/Podman to run dive:"
        echo "  docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wagoodman/dive ${IMAGE_NAME}"
        echo "  podman run --rm -it -v /run/podman/podman.sock:/var/run/docker.sock wagoodman/dive ${IMAGE_NAME}"
        exit 1
    fi
    log_info "dive found: $(dive --version 2>&1 | head -1)"
}

# Check if image exists
check_image() {
    if command -v podman &> /dev/null; then
        if ! podman image exists "${IMAGE_NAME}" 2>/dev/null; then
            log_error "Image '${IMAGE_NAME}' not found"
            log_info "Build the image first:"
            echo "  podman build -t ${IMAGE_NAME} -f DockerFile ."
            exit 1
        fi
        log_info "Using Podman to analyze image"
        CONTAINER_CMD="podman"
    elif command -v docker &> /dev/null; then
        if ! docker image inspect "${IMAGE_NAME}" &> /dev/null; then
            log_error "Image '${IMAGE_NAME}' not found"
            log_info "Build the image first:"
            echo "  docker build -t ${IMAGE_NAME} -f DockerFile ."
            exit 1
        fi
        log_info "Using Docker to analyze image"
        CONTAINER_CMD="docker"
    else
        log_error "Neither podman nor docker found"
        exit 1
    fi
}

# Analyze image with dive
analyze_image() {
    log_info "Analyzing image: ${IMAGE_NAME}"
    echo ""
    
    if [ "$CI_MODE" = "true" ]; then
        log_info "Running in CI mode (non-interactive)"
        if [ "$CONTAINER_CMD" = "podman" ]; then
            podman run --rm -it \
                -v /run/podman/podman.sock:/var/run/docker.sock \
                wagoodman/dive "${IMAGE_NAME}" --ci
        else
            docker run --rm -it \
                -v /var/run/docker.sock:/var/run/docker.sock \
                wagoodman/dive "${IMAGE_NAME}" --ci
        fi
    else
        log_info "Starting interactive dive analysis..."
        log_info "Use arrow keys to navigate, 'Tab' to switch views, 'Ctrl+C' to exit"
        echo ""
        
        if [ "$CONTAINER_CMD" = "podman" ]; then
            podman run --rm -it \
                -v /run/podman/podman.sock:/var/run/docker.sock \
                wagoodman/dive "${IMAGE_NAME}"
        else
            docker run --rm -it \
                -v /var/run/docker.sock:/var/run/docker.sock \
                wagoodman/dive "${IMAGE_NAME}"
        fi
    fi
}

# Show optimization tips
show_tips() {
    echo ""
    log_info "=== Optimization Tips ==="
    echo ""
    echo "1. Look for large files that can be removed"
    echo "2. Check for duplicate files across layers"
    echo "3. Identify inefficient layer ordering"
    echo "4. Look for unnecessary packages or files"
    echo "5. Consider multi-stage builds for build dependencies"
    echo ""
    log_info "Common optimizations:"
    echo "  - Combine RUN commands to reduce layers"
    echo "  - Remove package manager cache in same layer"
    echo "  - Use .dockerignore to exclude unnecessary files"
    echo "  - Remove build dependencies in final stage"
    echo "  - Use specific tags instead of 'latest'"
    echo ""
}

# Main execution
main() {
    echo "=========================================="
    echo "  Keycloak Image Analysis with Dive"
    echo "=========================================="
    echo ""
    
    if [ $# -gt 0 ] && [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "Usage: $0 [IMAGE_NAME] [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  IMAGE_NAME    Image to analyze (default: keycloak:latest)"
        echo "  --ci          Run in CI mode (non-interactive)"
        echo "  --help, -h    Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 keycloak:latest"
        echo "  $0 keycloak:amd64 --ci"
        echo "  $0 my-registry/keycloak:v1.0"
        exit 0
    fi
    
    # Parse CI mode flag
    if [[ "$*" == *"--ci"* ]]; then
        CI_MODE="true"
        # Remove --ci from arguments
        IMAGE_NAME=$(echo "$*" | sed 's/--ci//' | xargs | awk '{print $1}')
    fi
    
    check_dive
    check_image
    show_tips
    
    analyze_image
}

# Run main function
main "$@"

