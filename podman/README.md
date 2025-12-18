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

### Self-Signed Certificate with OpenSSL (Development)

For development purposes, you can create a self-signed certificate using OpenSSL:

```bash
# Create a directory for certificates
mkdir -p certs

# Generate a private key
openssl genrsa -out certs/keycloak.key 2048

# Create a certificate configuration file with proper extensions
cat > certs/cert-extensions.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
CN = localhost
O = Keycloak
C = US

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = keycloak
IP.1 = 127.0.0.1
EOF

# Generate a certificate signing request
openssl req -new -key certs/keycloak.key -out certs/keycloak.csr \
  -config certs/cert-extensions.conf

# Generate a self-signed certificate with extensions (valid for 365 days)
openssl x509 -req -days 365 -in certs/keycloak.csr \
  -signkey certs/keycloak.key -out certs/keycloak.crt \
  -extensions v3_req -extfile certs/cert-extensions.conf

# Create a PKCS12 keystore (required by Keycloak)
openssl pkcs12 -export -in certs/keycloak.crt -inkey certs/keycloak.key \
  -out certs/keycloak.p12 -name keycloak -password pass:changeit

# Verify the certificate has the correct extensions (optional)
openssl x509 -in certs/keycloak.crt -text -noout | grep -A 10 "X509v3 extensions"

# Clean up intermediate files (optional)
rm certs/keycloak.csr certs/cert-extensions.conf
```

**Note:** The extensions file ensures the certificate has proper key usage (`digitalSignature`, `keyEncipherment`) and extended key usage (`serverAuth`) to prevent `ERR_SSL_KEY_USAGE_INCOMPATIBLE` errors in browsers.

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

**Important:** CFSSL requires a two-step process: first create a CA (Certificate Authority), then sign a server certificate with that CA. Using `-initca` alone creates a CA certificate, not a server certificate, which will cause `ERR_SSL_KEY_USAGE_INCOMPATIBLE` errors.

```bash
# Create a directory for certificates
mkdir -p certs

# Copy the certificate configuration template
cp cert-config.json certs/cert-config.json

# Edit certs/cert-config.json to customize for your environment if needed
# (e.g., change CN, hosts, organization details)

# Step 1: Create a CA (Certificate Authority)
cfssl gencert -initca certs/cert-config.json | cfssljson -bare certs/ca

# Step 2: Copy the CA config template
cp ca-config.json certs/ca-config.json

# Step 3: Generate server certificate signed by the CA
cfssl gencert -ca certs/ca.pem -ca-key certs/ca-key.pem \
  -config certs/ca-config.json -profile server \
  certs/cert-config.json | cfssljson -bare certs/keycloak

# Rename files to match Keycloak expectations
mv certs/keycloak-key.pem certs/keycloak.key
mv certs/keycloak.pem certs/keycloak.crt

# Create a PKCS12 keystore (required by Keycloak)
openssl pkcs12 -export -in certs/keycloak.crt -inkey certs/keycloak.key \
  -out certs/keycloak.p12 -name keycloak -password pass:changeit

# Verify the certificate has the correct extensions (optional)
# Should show "Digital Signature", "Key Encipherment", and "TLS Web Server Authentication"
openssl x509 -in certs/keycloak.crt -text -noout | grep -A 10 "X509v3 extensions"

# Clean up intermediate files (optional)
# Note: This removes copies in certs/ directory, but keeps the template files in the root
rm certs/cert-config.json certs/ca-config.json certs/*.csr certs/ca.pem certs/ca-key.pem
```

**Important:** 
- The `cert-config.json` template includes proper key usage extensions (`keyUsage` and `extendedKeyUsage`) to prevent `ERR_SSL_KEY_USAGE_INCOMPATIBLE` errors in browsers.
- The two-step process (CA + server certificate) is required because `cfssl gencert -initca` alone creates a CA certificate, not a server certificate with the correct extensions.
- If you encounter `ERR_SSL_KEY_USAGE_INCOMPATIBLE`, ensure you're using the complete process above (not just `-initca`).

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

**Common causes:**
- Using `cfssl gencert -initca` alone (creates a CA certificate, not a server certificate)
- Missing key usage extensions in the certificate
- Certificate was generated without proper server authentication extensions

**Solution:**
1. Ensure you're using the updated `cert-config.json` template which includes:
   - `keyUsage` with `digitalSignature` and `keyEncipherment`
   - `extendedKeyUsage` with `serverAuth`
2. Regenerate your certificates using the correct method:
   - **For OpenSSL:** Use the method above with the extensions configuration file
   - **For CFSSL:** Use the two-step process (CA + server certificate) as shown below:
   ```bash
   # Create certs directory if it doesn't exist
   mkdir -p certs
   
   # Remove only the certificate files (not the directory)
   rm -f certs/*.pem certs/*.key certs/*.crt certs/*.p12 certs/*.json certs/*.csr
   
   # Copy the updated template
   cp cert-config.json certs/cert-config.json
   
   # Step 1: Create a CA
   cfssl gencert -initca certs/cert-config.json | cfssljson -bare certs/ca
   
   # Step 2: Copy the CA config template
   cp ca-config.json certs/ca-config.json
   
   # Step 3: Generate server certificate signed by CA
   cfssl gencert -ca certs/ca.pem -ca-key certs/ca-key.pem \
     -config certs/ca-config.json -profile server \
     certs/cert-config.json | cfssljson -bare certs/keycloak
   
   # Rename files
   mv certs/keycloak-key.pem certs/keycloak.key
   mv certs/keycloak.pem certs/keycloak.crt
   
   # Create PKCS12 keystore
   openssl pkcs12 -export -in certs/keycloak.crt -inkey certs/keycloak.key \
     -out certs/keycloak.p12 -name keycloak -password pass:changeit
   
   # Verify extensions (should show "Digital Signature" and "Key Encipherment")
   openssl x509 -in certs/keycloak.crt -text -noout | grep -A 10 "X509v3 extensions"
   ```
3. Restart your Keycloak container

## Notes

- The container exposes only HTTPS (port 8443)
- For production use, change `start-dev` to `start` in the CMD instruction
- Ensure you have proper SSL certificates configured for production deployments
- The build step (`kc.sh build`) is included for production readiness

