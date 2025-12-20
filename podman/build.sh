#!/bin/bash

# Build script for Keycloak multi-architecture Docker image
# Checks if platform-specific base image exists, otherwise builds from Debian/Ubuntu

set -euo pipefail

# Configuration
KEYCLOAK_VERSION="${KEYCLOAK_VERSION:-26.4.7}"
DOCKERFILE="${DOCKERFILE:-DockerFile}"
IMAGE_NAME="${IMAGE_NAME:-keycloak:latest}"
PLATFORM="${PLATFORM:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if official image exists for platform
check_official_image() {
    local platform=$1
    local image="quay.io/keycloak/keycloak:${KEYCLOAK_VERSION}"
    
    log_info "Checking if official Keycloak image exists for platform: ${platform}"
    
    # Try to pull the manifest for the specific platform
    if command -v skopeo &> /dev/null; then
        if skopeo inspect --raw "docker://${image}" | jq -e ".manifests[] | select(.platform.architecture == \"${platform#linux/}\")" &> /dev/null; then
            log_info "Official image found for platform ${platform}"
            return 0
        fi
    elif command -v docker &> /dev/null && docker buildx version &> /dev/null; then
        # Try with docker buildx
        if docker buildx imagetools inspect "${image}" --raw 2>/dev/null | grep -q "${platform#linux/}" 2>/dev/null; then
            log_info "Official image found for platform ${platform}"
            return 0
        fi
    else
        log_warn "Cannot check for official image (skopeo or docker buildx not available)"
        log_warn "Will attempt to build and fall back to Debian base if official image fails"
        return 1
    fi
    
    log_warn "Official image not found for platform ${platform}, will use Debian base"
    return 1
}

# Build function
build_image() {
    local platform=$1
    local use_official=$2
    local dockerfile="${DOCKERFILE}"
    
    log_info "Building Keycloak image for platform: ${platform:-auto-detect}"
    
    # Select Dockerfile based on preference
    if [ "$use_official" = "true" ]; then
        if [ -f "DockerFile.official" ]; then
            dockerfile="DockerFile.official"
            log_info "Using official Keycloak base image (DockerFile.official)"
        else
            log_warn "DockerFile.official not found, using DockerFile (Debian base)"
            dockerfile="DockerFile"
        fi
    else
        dockerfile="DockerFile"
        log_info "Using Debian base image (DockerFile)"
    fi
    
    # Build command
    if command -v podman &> /dev/null; then
        BUILD_CMD="podman build"
        if [ -n "$platform" ]; then
            BUILD_CMD="${BUILD_CMD} --platform ${platform}"
        fi
    elif command -v docker &> /dev/null; then
        BUILD_CMD="docker build"
        if [ -n "$platform" ] && docker buildx version &> /dev/null; then
            BUILD_CMD="docker buildx build --platform ${platform}"
        elif [ -n "$platform" ]; then
            log_warn "Docker buildx not available, platform flag may not work"
        fi
    else
        log_error "Neither podman nor docker found"
        exit 1
    fi
    
    # Build with appropriate arguments
    log_info "Building with: ${BUILD_CMD}"
    if ! $BUILD_CMD \
        --build-arg KEYCLOAK_VERSION="${KEYCLOAK_VERSION}" \
        --build-arg TARGETPLATFORM="${platform:-}" \
        -f "${dockerfile}" \
        -t "${IMAGE_NAME}" \
        .; then
        if [ "$use_official" = "true" ] && [ "$dockerfile" = "DockerFile.official" ]; then
            log_warn "Official image build failed, trying Debian base..."
            if [ -f "DockerFile" ]; then
                log_info "Building with Debian base (DockerFile) as fallback"
                $BUILD_CMD \
                    --build-arg KEYCLOAK_VERSION="${KEYCLOAK_VERSION}" \
                    --build-arg TARGETPLATFORM="${platform:-}" \
                    -f "DockerFile" \
                    -t "${IMAGE_NAME}" \
                    .
            else
                log_error "DockerFile not found, cannot fallback"
                exit 1
            fi
        else
            log_error "Build failed"
            exit 1
        fi
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "  Keycloak Multi-Architecture Build"
    echo "=========================================="
    echo
    
    # Parse arguments
    USE_OFFICIAL="auto"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            --force-debian)
                USE_OFFICIAL="false"
                shift
                ;;
            --force-official)
                USE_OFFICIAL="true"
                shift
                ;;
            --version)
                KEYCLOAK_VERSION="$2"
                shift 2
                ;;
            --image)
                IMAGE_NAME="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --platform PLATFORM    Target platform (e.g., linux/amd64, linux/arm64)"
                echo "  --force-debian         Force use of Debian base (skip official image check)"
                echo "  --force-official       Force use of official image (skip check, may fail)"
                echo "  --version VERSION      Keycloak version (default: ${KEYCLOAK_VERSION})"
                echo "  --image IMAGE          Output image name (default: ${IMAGE_NAME})"
                echo "  --help                 Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check for official image if auto mode
    if [ "$USE_OFFICIAL" = "auto" ] && [ -n "$PLATFORM" ]; then
        if check_official_image "$PLATFORM"; then
            USE_OFFICIAL="true"
        else
            USE_OFFICIAL="false"
        fi
    elif [ "$USE_OFFICIAL" = "auto" ]; then
        log_info "No platform specified, will attempt official image with automatic fallback"
        USE_OFFICIAL="true"
    fi
    
    # Build the image
    build_image "$PLATFORM" "$USE_OFFICIAL"
    
    log_info "Build complete! Image: ${IMAGE_NAME}"
}

# Run main function
main "$@"

