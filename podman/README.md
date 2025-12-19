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

**Note:** This method creates a self-signed certificate (no CA). For consistency with the CFSSL approach, certificates are stored in `certs/ca/servers/` even though no CA is used.

```bash
# Create directory structure for certificates
mkdir -p certs/ca/servers

# Generate a private key
openssl genrsa -out certs/ca/servers/keycloak.key 2048

# Create a certificate configuration file with proper extensions
cat > certs/ca/servers/cert-extensions.conf <<EOF
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
openssl req -new -key certs/ca/servers/keycloak.key -out certs/ca/servers/keycloak.csr \
  -config certs/ca/servers/cert-extensions.conf

# Generate a self-signed certificate with extensions (valid for 365 days)
openssl x509 -req -days 365 -in certs/ca/servers/keycloak.csr \
  -signkey certs/ca/servers/keycloak.key -out certs/ca/servers/keycloak.crt \
  -extensions v3_req -extfile certs/ca/servers/cert-extensions.conf

# Create a PKCS12 keystore (required by Keycloak)
openssl pkcs12 -export -in certs/ca/servers/keycloak.crt -inkey certs/ca/servers/keycloak.key \
  -out certs/ca/servers/keycloak.p12 -name keycloak -password pass:changeit

# Verify the certificate has the correct extensions (optional)
openssl x509 -in certs/ca/servers/keycloak.crt -text -noout | grep -A 10 "X509v3 extensions"

# Clean up intermediate files (optional)
rm certs/ca/servers/keycloak.csr certs/ca/servers/cert-extensions.conf
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

**Two-Config Approach:** We use separate configuration files stored in `certs-template/`:
- `certs-template/ca-cert-config.json` - for the CA certificate (reusable, kept for future server certificates)
- `certs-template/cert-config.json` - for server certificates (can be customized per server)
- `certs-template/ca-config.json` - CA signing configuration

**Directory Structure:**
- CA files are stored in `./certs/ca/`
- Server certificate files are stored in `./certs/ca/servers/`

The CA can be reused to sign multiple server certificates, so it's only created once and kept in the `certs/ca/` directory.

#### Automated Certificate Creation Script

For convenience, a script is provided to automate certificate creation:

```bash
# Make the script executable (first time only)
chmod +x create-certs.sh

# Create CA and default keycloak server certificate
./create-certs.sh --all

# Create CA only
./create-certs.sh --create-ca

# Create a server certificate (default: keycloak)
./create-certs.sh --server keycloak

# Create a server certificate with custom name
./create-certs.sh --server my-server

# Regenerate CA (forces recreation)
./create-certs.sh --force-ca

# Verify existing certificates
./create-certs.sh --verify

# Show help
./create-certs.sh --help
```

The script automatically:
- Checks for required dependencies (cfssl, cfssljson, openssl)
- Creates CA if it doesn't exist
- Creates server certificates with full chain
- Generates PKCS12 keystores
- Verifies certificate extensions
- Cleans up intermediate files

#### Manual Certificate Creation with CFSSL

If you prefer to create certificates manually, follow these steps:

```bash
# Create directory structure for certificates
mkdir -p certs/ca/servers

# Step 1: Create a CA (Certificate Authority) - only if it doesn't exist
if [ ! -f certs/ca/ca.pem ]; then
  echo "Creating new CA..."
  cp certs-template/ca-cert-config.json certs/ca/ca-cert-config.json
  cfssl gencert -initca certs/ca/ca-cert-config.json | cfssljson -bare certs/ca/ca
  echo "CA created and saved in certs/ca/ directory for future reuse"
else
  echo "Using existing CA from certs/ca/ directory"
fi

# Step 2: Copy the server certificate configuration template
cp certs-template/cert-config.json certs/ca/servers/cert-config.json

# Edit certs/ca/servers/cert-config.json to customize for your environment if needed
# (e.g., change CN, hosts, organization details)

# Step 3: Copy the CA config template
cp certs-template/ca-config.json certs/ca/ca-config.json

# Step 4: Generate server certificate signed by the CA
cfssl gencert -ca certs/ca/ca.pem -ca-key certs/ca/ca-key.pem \
  -config certs/ca/ca-config.json -profile server \
  certs/ca/servers/cert-config.json | cfssljson -bare certs/ca/servers/keycloak

# Rename files to match Keycloak expectations
mv certs/ca/servers/keycloak-key.pem certs/ca/servers/keycloak.key
mv certs/ca/servers/keycloak.pem certs/ca/servers/keycloak.crt

# Create full chain certificate (server cert + CA cert)
# This is useful for clients that need to validate the complete certificate chain
cat certs/ca/servers/keycloak.crt certs/ca/ca.pem > certs/ca/servers/keycloak-chain.crt

# Create a PKCS12 keystore (required by Keycloak)
# Include the CA in the keystore for complete chain
openssl pkcs12 -export -in certs/ca/servers/keycloak.crt -inkey certs/ca/servers/keycloak.key \
  -certfile certs/ca/ca.pem \
  -out certs/ca/servers/keycloak.p12 -name keycloak -password pass:changeit

# Verify the certificate has the correct extensions (optional)
# Should show "Digital Signature", "Key Encipherment", and "TLS Web Server Authentication"
openssl x509 -in certs/ca/servers/keycloak.crt -text -noout | grep -A 10 "X509v3 extensions"

# Clean up intermediate files (optional)
# Note: This removes copies in certs/ directory, but keeps:
# - Template files in certs-template/ directory
# - CA files (ca.pem, ca-key.pem) in certs/ca/ for future reuse
rm certs/ca/servers/cert-config.json certs/ca/ca-cert-config.json certs/ca/ca-config.json certs/ca/servers/*.csr
```

#### Creating Additional Server Certificates

Once you have a CA in the `certs/ca/` directory, you can easily create additional server certificates by reusing the same CA:

```bash
# Ensure CA exists
if [ ! -f certs/ca/ca.pem ]; then
  echo "Error: CA not found. Please create it first using the steps above."
  exit 1
fi

# Create servers directory if it doesn't exist
mkdir -p certs/ca/servers

# Copy and customize the server certificate template
cp certs-template/cert-config.json certs/ca/servers/new-server-config.json
# Edit certs/ca/servers/new-server-config.json to customize CN, hosts, etc. for the new server

# Copy CA config
cp certs-template/ca-config.json certs/ca/ca-config.json

# Generate new server certificate (e.g., for a different hostname)
cfssl gencert -ca certs/ca/ca.pem -ca-key certs/ca/ca-key.pem \
  -config certs/ca/ca-config.json -profile server \
  certs/ca/servers/new-server-config.json | cfssljson -bare certs/ca/servers/new-server

# Rename and create keystore as needed
mv certs/ca/servers/new-server-key.pem certs/ca/servers/new-server.key
mv certs/ca/servers/new-server.pem certs/ca/servers/new-server.crt

# Create full chain certificate (server cert + CA cert)
cat certs/ca/servers/new-server.crt certs/ca/ca.pem > certs/ca/servers/new-server-chain.crt

# Create PKCS12 keystore with full chain
openssl pkcs12 -export -in certs/ca/servers/new-server.crt -inkey certs/ca/servers/new-server.key \
  -certfile certs/ca/ca.pem \
  -out certs/ca/servers/new-server.p12 -name new-server -password pass:changeit

# Clean up intermediate files
rm certs/ca/servers/new-server-config.json certs/ca/ca-config.json certs/ca/servers/*.csr
```

**Important:** 
- We use two separate config files in `certs-template/`: `ca-cert-config.json` for the CA and `cert-config.json` for server certificates
- The CA is created once and kept in `certs/ca/` directory for reuse with multiple server certificates
- Server certificates are stored in `certs/ca/servers/` directory
- The `certs-template/cert-config.json` template includes proper key usage extensions (`keyUsage` and `extendedKeyUsage`) to prevent `ERR_SSL_KEY_USAGE_INCOMPATIBLE` errors in browsers
- The two-step process (CA + server certificate) is required because `cfssl gencert -initca` alone creates a CA certificate, not a server certificate with the correct extensions
- If you encounter `ERR_SSL_KEY_USAGE_INCOMPATIBLE`, ensure you're using the complete process above (not just `-initca`)

Note: The PKCS12 keystore creation still requires openssl, but you can also use `keytool` (Java) if available:

```bash
# Alternative: Create PKCS12 keystore using keytool
keytool -importkeystore -srckeystore certs/ca/servers/keycloak.key -srcstoretype PEM \
  -destkeystore certs/ca/servers/keycloak.p12 -deststoretype PKCS12 \
  -srcstorepass "" -deststorepass changeit \
  -alias keycloak
```

### Using the Certificate with Keycloak

When running the container, mount the certificate directory and configure Keycloak to use it:

**Option 1: Using certificate files with full chain (recommended)**

```bash
podman run -d \
  --name keycloak \
  -p 8443:8443 \
  -v $(pwd)/certs/ca/servers:/opt/keycloak/conf/certs:ro \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  -e KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/conf/certs/keycloak.crt \
  -e KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/conf/certs/keycloak.key \
  -e KC_HTTPS_CERTIFICATE_CHAIN_FILE=/opt/keycloak/conf/certs/keycloak-chain.crt \
  keycloak:latest
```

**Option 2: Using certificate files without chain**

```bash
podman run -d \
  --name keycloak \
  -p 8443:8443 \
  -v $(pwd)/certs/ca/servers:/opt/keycloak/conf/certs:ro \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  -e KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/conf/certs/keycloak.crt \
  -e KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/conf/certs/keycloak.key \
  keycloak:latest
```

**Option 3: Using Java keystore (includes full chain)**

```bash
podman run -d \
  --name keycloak \
  -p 8443:8443 \
  -v $(pwd)/certs/ca/servers:/opt/keycloak/conf/certs:ro \
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
1. Ensure you're using the updated `certs-template/cert-config.json` template which includes:
   - `keyUsage` with `digitalSignature` and `keyEncipherment`
   - `extendedKeyUsage` with `serverAuth`
2. Regenerate your certificates using the correct method:
   - **For OpenSSL:** Use the method above with the extensions configuration file
   - **For CFSSL:** Use the two-step process (CA + server certificate) as shown below:
   ```bash
   # Create certs directory structure if it doesn't exist
   mkdir -p certs/ca/servers
   
   # Remove only the server certificate files (keep CA for reuse)
   rm -f certs/ca/servers/keycloak.* certs/ca/servers/cert-config.json certs/ca/ca-config.json certs/ca/servers/*.csr
   
   # Step 1: Create or reuse CA
   if [ ! -f certs/ca/ca.pem ]; then
     echo "Creating new CA..."
     cp certs-template/ca-cert-config.json certs/ca/ca-cert-config.json
     cfssl gencert -initca certs/ca/ca-cert-config.json | cfssljson -bare certs/ca/ca
   else
     echo "Using existing CA"
   fi
   
   # Step 2: Copy the server certificate template
   cp certs-template/cert-config.json certs/ca/servers/cert-config.json
   
   # Step 3: Copy the CA config template
   cp certs-template/ca-config.json certs/ca/ca-config.json
   
   # Step 4: Generate server certificate signed by CA
   cfssl gencert -ca certs/ca/ca.pem -ca-key certs/ca/ca-key.pem \
     -config certs/ca/ca-config.json -profile server \
     certs/ca/servers/cert-config.json | cfssljson -bare certs/ca/servers/keycloak
   
   # Rename files
   mv certs/ca/servers/keycloak-key.pem certs/ca/servers/keycloak.key
   mv certs/ca/servers/keycloak.pem certs/ca/servers/keycloak.crt
   
   # Create full chain certificate (server cert + CA cert)
   cat certs/ca/servers/keycloak.crt certs/ca/ca.pem > certs/ca/servers/keycloak-chain.crt
   
   # Create PKCS12 keystore with full chain
   openssl pkcs12 -export -in certs/ca/servers/keycloak.crt -inkey certs/ca/servers/keycloak.key \
     -certfile certs/ca/ca.pem \
     -out certs/ca/servers/keycloak.p12 -name keycloak -password pass:changeit
   
   # Verify extensions (should show "Digital Signature" and "Key Encipherment")
   openssl x509 -in certs/ca/servers/keycloak.crt -text -noout | grep -A 10 "X509v3 extensions"
   ```
   
   **Note:** If you need to regenerate the CA (e.g., if it was created incorrectly), remove it first:
   ```bash
   rm -f certs/ca/ca.pem certs/ca/ca-key.pem certs/ca/ca.csr
   ```
3. Restart your Keycloak container

## Notes

- The container exposes only HTTPS (port 8443)
- For production use, change `start-dev` to `start` in the CMD instruction
- Ensure you have proper SSL certificates configured for production deployments
- The build step (`kc.sh build`) is included for production readiness

