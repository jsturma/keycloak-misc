# Keycloak Misc

A collection of Keycloak deployment configurations and setup scripts for various environments.

## 📁 Project Structure

```
keycloak-misc/
├── k8s/                    # Kubernetes/Helm deployments
│   ├── keycloak-chart/     # Helm chart for Keycloak
│   ├── keycloak-values.yaml
│   └── keycloak_start_dev.yaml
├── bm-vm/                  # Bare-metal VM deployments
│   ├── setup-keycloak-dev.sh    # Automated setup script
│   ├── deploy-service.sh         # Service deployment script
│   ├── keycloak.service          # Systemd service file
│   └── Readme.md                 # Detailed VM setup guide
├── LICENSE
└── README.md
```

## 🚀 Quick Start

### Kubernetes Deployment

#### Using Helm Chart

```bash
cd k8s
helm install keycloak ./keycloak-chart -f keycloak-values.yaml
```

#### Using Plain Kubernetes YAML

```bash
kubectl apply -f k8s/keycloak_start_dev.yaml
```

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

## 📋 Features

### Kubernetes (`k8s/`)
- Helm chart with configurable values
- Plain Kubernetes manifests for quick deployment
- Development mode configuration
- Health checks and readiness probes

### Bare-Metal VM (`bm-vm/`)
- Complete automated setup script
- HTTPS-only configuration (port 443)
- Systemd service with security hardening
- Non-root user execution
- TLS certificate management
- Port 443 binding capabilities

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

## 📖 Documentation

- [VM Setup Guide](bm-vm/Readme.md) - Detailed bare-metal setup instructions
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

