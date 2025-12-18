# Keycloak Podman Setup

This directory contains a Dockerfile for running Keycloak 26.x with Podman compatibility.

## Overview

The Dockerfile is configured to:
- Use Keycloak 26.4.7 (latest version)
- Run in development mode (`start-dev`)
- Support rootless Podman operations
- Expose HTTPS on port 8443

## Building the Image

To build the Keycloak image using Podman:

```bash
podman build -t keycloak:latest -f DockerFile .
```

Or using Docker:

```bash
docker build -t keycloak:latest -f DockerFile .
```

## Creating SSL/TLS Certificates

Keycloak requires SSL/TLS certificates for HTTPS connections. Here are instructions for creating certificates:

### Self-Signed Certificate (Development)

For development purposes, you can create a self-signed certificate:

```bash
# Create a directory for certificates
mkdir -p certs

# Generate a private key
openssl genrsa -out certs/keycloak.key 2048

# Generate a certificate signing request
openssl req -new -key certs/keycloak.key -out certs/keycloak.csr \
  -subj "/CN=localhost/O=Keycloak/C=US"

# Generate a self-signed certificate (valid for 365 days)
openssl x509 -req -days 365 -in certs/keycloak.csr \
  -signkey certs/keycloak.key -out certs/keycloak.crt

# Create a PKCS12 keystore (required by Keycloak)
openssl pkcs12 -export -in certs/keycloak.crt -inkey certs/keycloak.key \
  -out certs/keycloak.p12 -name keycloak -password pass:changeit

# Clean up the CSR file (optional)
rm certs/keycloak.csr
```

### Using CFSSL (Alternative to OpenSSL)

CFSSL is Cloudflare's PKI/TLS toolkit. To use cfssl instead of openssl:

#### Install CFSSL

```bash
# macOS
brew install cfssl

# Linux (download binary)
# Visit https://github.com/cloudflare/cfssl/releases
# Or use package manager if available
```

#### Create Certificate with CFSSL

```bash
# Create a directory for certificates
mkdir -p certs

# Copy the certificate configuration template
cp cert-config.json certs/cert-config.json

# Edit certs/cert-config.json to customize for your environment if needed
# (e.g., change CN, hosts, organization details)

# Generate self-signed certificate with proper extensions
# Using gencert -initca ensures keyUsage and extendedKeyUsage are applied
cfssl gencert -initca certs/cert-config.json | cfssljson -bare certs/keycloak

# Rename files to match Keycloak expectations
mv certs/keycloak-key.pem certs/keycloak.key
mv certs/keycloak.pem certs/keycloak.crt

# Create a PKCS12 keystore (required by Keycloak)
openssl pkcs12 -export -in certs/keycloak.crt -inkey certs/keycloak.key \
  -out certs/keycloak.p12 -name keycloak -password pass:changeit

# Verify the certificate has the correct extensions (optional)
openssl x509 -in certs/keycloak.crt -text -noout | grep -A 5 "X509v3 extensions"

# Clean up intermediate files (optional)
rm certs/cert-config.json certs/keycloak.csr
```

**Important:** The `cert-config.json` template includes proper key usage extensions (`keyUsage` and `extendedKeyUsage`) to prevent `ERR_SSL_KEY_USAGE_INCOMPATIBLE` errors in browsers. If you encounter this error, regenerate your certificates using the updated template.

Note: The PKCS12 keystore creation still requires openssl, but you can also use `keytool` (Java) if available:

```bash
# Alternative: Create PKCS12 keystore using keytool
keytool -importkeystore -srckeystore certs/keycloak.key -srcstoretype PEM \
  -destkeystore certs/keycloak.p12 -deststoretype PKCS12 \
  -srcstorepass "" -deststorepass changeit \
  -alias keycloak
```

### Using the Certificate with Keycloak

When running the container, mount the certificate directory and configure Keycloak to use it:

```bash
podman run -d \
  --name keycloak \
  -p 8443:8443 \
  -v $(pwd)/certs:/opt/keycloak/conf/certs:ro \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  -e KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/conf/certs/keycloak.crt \
  -e KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/conf/certs/keycloak.key \
  keycloak:latest
```

Alternatively, you can use a Java keystore:

```bash
podman run -d \
  --name keycloak \
  -p 8443:8443 \
  -v $(pwd)/certs:/opt/keycloak/conf/certs:ro \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  -e KC_HTTPS_KEYSTORE_FILE=/opt/keycloak/conf/certs/keycloak.p12 \
  -e KC_HTTPS_KEYSTORE_PASSWORD=changeit \
  keycloak:latest
```

### Production Certificates

For production environments:
- Use certificates from a trusted Certificate Authority (CA)
- Consider using Let's Encrypt for free SSL certificates
- Ensure certificates are properly signed and not expired
- Use strong private keys (at least 2048 bits, preferably 4096 bits)

## Running the Container

### Basic Run

```bash
podman run -d \
  --name keycloak \
  -p 8443:8443 \
  keycloak:latest
```

### With Environment Variables

```bash
podman run -d \
  --name keycloak \
  -p 8443:8443 \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  keycloak:latest
```

### With Volume for Data Persistence

```bash
podman run -d \
  --name keycloak \
  -p 8443:8443 \
  -v keycloak-data:/opt/keycloak/data \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  keycloak:latest
```

## Configuration

### Development Mode

The container runs in development mode (`start-dev`), which:
- Uses an in-memory database (H2)
- Enables the admin console
- Auto-creates an admin user if `KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD` are set
- Not suitable for production use

### Custom Themes and Providers

To add custom themes or providers, uncomment the relevant lines in the Dockerfile:

```dockerfile
# COPY themes /opt/keycloak/themes
# COPY providers/*.jar /opt/keycloak/providers/
```

Then place your themes in a `themes/` directory and providers in a `providers/` directory before building.

## Podman Compatibility

The Dockerfile is configured for rootless Podman:
- Sets ownership to UID 1000 (common for rootless containers)
- Uses USER 1000 for running the container
- Ensures proper file permissions

## Accessing Keycloak

Once the container is running:
- Admin Console: `https://localhost:8443`
- Default admin credentials (if set via environment variables):
  - Username: `admin`
  - Password: `admin` (or your `KEYCLOAK_ADMIN_PASSWORD` value)

## Troubleshooting

### ERR_SSL_KEY_USAGE_INCOMPATIBLE

If you encounter the error `ERR_SSL_KEY_USAGE_INCOMPATIBLE` when accessing Keycloak in your browser, it means your certificate is missing the required key usage extensions for SSL/TLS server authentication.

**Solution:**
1. Ensure you're using the updated `cert-config.json` template which includes:
   - `keyUsage` with `digitalSignature` and `keyEncipherment`
   - `extendedKeyUsage` with `serverAuth`
2. Regenerate your certificates using the updated template:
   ```bash
   # Create certs directory if it doesn't exist
   mkdir -p certs
   
   # Remove only the certificate files (not the directory)
   rm -f certs/keycloak.* certs/cert-config.json
   
   # Copy the updated template
   cp cert-config.json certs/cert-config.json
   
   # Generate new certificates (using gencert -initca to ensure extensions are applied)
   cfssl gencert -initca certs/cert-config.json | cfssljson -bare certs/keycloak
   mv certs/keycloak-key.pem certs/keycloak.key
   mv certs/keycloak.pem certs/keycloak.crt
   openssl pkcs12 -export -in certs/keycloak.crt -inkey certs/keycloak.key \
     -out certs/keycloak.p12 -name keycloak -password pass:changeit
   ```
3. Restart your Keycloak container

## Notes

- The container exposes only HTTPS (port 8443)
- For production use, change `start-dev` to `start` in the CMD instruction
- Ensure you have proper SSL certificates configured for production deployments
- The build step (`kc.sh build`) is included for production readiness

