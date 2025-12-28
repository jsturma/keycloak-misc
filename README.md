# Keycloak Misc

A collection of Keycloak deployment configurations and setup scripts for various environments.

## 📁 Project Structure

```
keycloak-misc/
├── k8s/                    # Kubernetes/Helm deployments
│   ├── keycloak-chart/     # Helm chart for Keycloak
│   ├── keycloak-values.yaml
│   ├── keycloak_start_dev.yaml      # H2 database (default)
│   ├── keycloak_start_dev_https.yaml # HTTPS with H2
│   ├── keycloak_postgres.yaml       # PostgreSQL database
│   └── create-tls-secret.sh         # TLS secret creation script
├── bm-vm/                  # Bare-metal VM deployments
│   ├── setup-keycloak-dev.sh    # Automated setup script
│   ├── deploy-service.sh         # Service deployment script
│   ├── keycloak.service          # Systemd service file
│   └── Readme.md                 # Detailed VM setup guide
├── podman/                 # Podman/Docker container deployments
│   ├── DockerFile              # Keycloak container image (Debian base, optimized)
│   ├── DockerFile.official     # Official Keycloak image variant
│   ├── build.sh                # Automated multi-arch build script
│   ├── analyze-image.sh        # Image analysis with dive
│   ├── create-certs.sh         # Certificate creation script
│   ├── docker-compose.postgres.yml  # Docker Compose with PostgreSQL
│   ├── certs-template/         # Certificate configuration templates
│   └── README.md               # Podman setup guide
├── LICENSE
└── README.md
```

## 🚀 Quick Start

### Kubernetes Deployment

#### Using Helm Chart

```bash
# Create the keycloak namespace (if it doesn't exist)
kubectl create namespace keycloak

# Install with Helm (namespace is set in values.yaml)
cd k8s
helm install keycloak ./keycloak-chart -f keycloak-values.yaml -n keycloak

# Or install to a specific namespace
helm install keycloak ./keycloak-chart -f keycloak-values.yaml --create-namespace -n keycloak
```

#### Using Plain Kubernetes YAML

**Option 1: HTTP with H2 Database (Development - No certificates needed)**

```bash
# Create the keycloak namespace (if it doesn't exist)
kubectl create namespace keycloak

# Apply the deployment (uses HTTP on port 8080, H2 in-memory database)
kubectl apply -f k8s/keycloak_start_dev.yaml

# Check deployment status
kubectl get pods -n keycloak
kubectl logs -n keycloak -l app=keycloak

# Access Keycloak
# http://<loadbalancer-ip>:8080
```

**Option 1b: HTTP with PostgreSQL (Persistent database)**

```bash
# Create the keycloak namespace (if it doesn't exist)
kubectl create namespace keycloak

# Apply PostgreSQL and Keycloak deployment
kubectl apply -f k8s/keycloak_postgres.yaml

# Check deployment status
kubectl get pods -n keycloak
kubectl logs -n keycloak -l app=keycloak

# Access Keycloak
# http://<loadbalancer-ip>:8080
```

**Option 2: HTTPS (Requires TLS certificates)**

```bash
# Generate certificates (if not already done)
cd podman
./create-certs.sh --all

# Create TLS secret from certificates (using helper script)
cd ../k8s
./create-tls-secret.sh

# Or manually create the secret
kubectl create namespace keycloak
kubectl create secret tls keycloak-tls \
  --cert=../podman/certs/ca/servers/keycloak.crt \
  --key=../podman/certs/ca/servers/keycloak.key \
  -n keycloak

# Apply HTTPS deployment
kubectl apply -f k8s/keycloak_start_dev_https.yaml

# Access Keycloak
# https://<loadbalancer-ip>:8443
# Note: You may need to accept the self-signed certificate warning
```

**Updating existing deployment:**

```bash
# Delete and recreate
kubectl delete -f k8s/keycloak_start_dev.yaml
kubectl apply -f k8s/keycloak_start_dev.yaml

# Or force replace
kubectl replace --force -f k8s/keycloak_start_dev.yaml
```

**Note:** 
- The deployment uses the `keycloak` namespace (not `default`)
- Default configuration uses HTTP (port 8080) for easier development
- For HTTPS, use `keycloak_start_dev_https.yaml` and provide TLS certificates
- If you see deprecation warnings or the old Keycloak version (26.1.3) in logs, delete the old deployment and recreate it
- Remember to use `-n keycloak` when running kubectl commands

### Bare-Metal VM Deployment

For complete setup on a Linux VM, see the [VM setup guide](bm-vm/Readme.md).

**Automated setup:**
```bash
cd bm-vm
sudo ./setup-keycloak-dev.sh
```

**Manual service deployment:**
```bash
cd bm-vm
sudo ./deploy-service.sh
```

### Podman/Docker Container Deployment

For containerized deployments using Podman or Docker, see the [Podman setup guide](podman/README.md).

**Automated build (recommended):**
```bash
cd podman
./build.sh
podman run -d --name keycloak -p 8443:8443 keycloak:latest
```

**Manual build:**
```bash
cd podman
podman build -t keycloak:latest -f DockerFile .
podman run -d --name keycloak -p 8443:8443 keycloak:latest
```

**Multi-architecture build:**
```bash
cd podman
./build.sh --platform linux/amd64
./build.sh --platform linux/arm64
```

**With certificates (HTTPS-only):**
```bash
cd podman
./create-certs.sh --all
podman run -d --name keycloak -p 8443:8443 \
  -v $(pwd)/certs/ca/servers:/opt/keycloak/conf/certs:ro \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin \
  -e KC_HTTP_ENABLED=false \
  -e KC_HTTPS_PORT=8443 \
  -e KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/conf/certs/keycloak.crt \
  -e KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/conf/certs/keycloak.key \
  keycloak:latest
```

**Note:** Use `KC_BOOTSTRAP_ADMIN_USERNAME` and `KC_BOOTSTRAP_ADMIN_PASSWORD` instead of the deprecated `KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD` variables.

## 📋 Features

### Kubernetes (`k8s/`)
- Helm chart with configurable values
- Plain Kubernetes manifests for quick deployment
- Development mode configuration
- Database options: H2 (default) or PostgreSQL
- PostgreSQL deployment with persistent storage
- HTTPS-only configuration (port 8443)
- Health checks and readiness probes
- Updated to use new environment variables (KC_BOOTSTRAP_ADMIN_USERNAME)
- Keycloak 26.4.7 with JDK 21 support

### Bare-Metal VM (`bm-vm/`)
- Complete automated setup script
- HTTPS-only configuration (port 443)
- Systemd service with security hardening
- Non-root user execution
- TLS certificate management
- Port 443 binding capabilities

### Podman/Docker (`podman/`)
- Containerized Keycloak deployment
- Multi-architecture support (x86_64/amd64 and arm64)
- Rootless Podman compatibility
- Automated build script with platform detection
- Image optimization with dive integration
- Automated certificate creation (CFSSL/OpenSSL)
- Development and production modes
- Database options: H2 (default) or PostgreSQL
- Docker Compose support for PostgreSQL setup
- Custom themes and providers support
- HTTPS-only configuration (port 8443)
- JDK 21 support (required by latest Keycloak versions)

## 🔧 Requirements

### Kubernetes
- Kubernetes cluster (1.20+)
- kubectl configured
- Helm 3.x (for Helm chart)

### Bare-Metal VM
- Linux system with systemd
- Keycloak installed at `/opt/keycloak`
- Java installed and in PATH
- `keycloak` user created
- TLS certificates (for HTTPS)

### Podman/Docker
- Podman or Docker installed
- Docker Buildx (for multi-architecture builds with Docker)
- CFSSL or OpenSSL (for certificate generation, optional)
- TLS certificates (optional, can be generated)
- JDK 21 (included in container image)

## 📖 Documentation

- [VM Setup Guide](bm-vm/Readme.md) - Detailed bare-metal setup instructions
- [Podman Setup Guide](podman/README.md) - Container deployment with Podman/Docker
- [Kubernetes Manifests](k8s/) - K8s deployment files

## 🔐 Security Notes

- VM setup enforces HTTPS-only mode
- Systemd service includes security hardening
- Non-root user execution
- Proper file permissions for TLS certificates

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## ⚠️ Disclaimer

These configurations are provided as-is for development and testing purposes. For production deployments, ensure proper security hardening, backup strategies, and compliance with your organization's policies.

