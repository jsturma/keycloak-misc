**complete, bare-metal setup for Keycloak running in dev mode as a Linux service** with:

* service user: **`keycloak`**
* **HTTPS only**
* **port 443**
* **no HTTP listener**
* compatible with **`start-dev`** (and production later)

---

## 🚀 Quick Start

### Automated Setup

Use the provided setup script for automated installation:

```bash
sudo ./setup-keycloak-dev.sh
```

The script will:
- ✅ Check prerequisites (user, Keycloak installation, Java)
- ✅ Create configuration file
- ✅ Set up TLS directory and permissions
- ✅ Configure Java capabilities for port 443
- ✅ Install and start the systemd service
- ✅ Validate the setup

### Manual Setup

For manual step-by-step setup, follow the sections below. You can also use the `deploy-service.sh` script to deploy just the systemd service file.

---

# 1️⃣ `keycloak.conf` (final, service-ready)

**Location**

```
/opt/keycloak/conf/keycloak.conf
```

```ini
############################
# NETWORK
############################

http-enabled=false
https-port=443


############################
# TLS
############################

https-certificate-file=/etc/keycloak/tls/tls.crt
https-certificate-key-file=/etc/keycloak/tls/tls.key


############################
# HOSTNAME
############################

hostname=https://auth.example.com
hostname-strict=true
hostname-strict-https=true


############################
# MANAGEMENT
############################

http-management-scheme=inherited
```

---

# 2️⃣ TLS directory & permissions (CRITICAL)

Create a secure directory readable by the **keycloak** user:

```bash
sudo mkdir -p /etc/keycloak/tls
sudo chown root:keycloak /etc/keycloak/tls
sudo chmod 750 /etc/keycloak/tls
```

Certificates:

```bash
sudo chown root:keycloak /etc/keycloak/tls/tls.key
sudo chmod 640 /etc/keycloak/tls/tls.key

sudo chown root:keycloak /etc/keycloak/tls/tls.crt
sudo chmod 644 /etc/keycloak/tls/tls.crt
```

✅ Keycloak can read the key
❌ Others cannot

---

# 3️⃣ Allow **non-root** user to bind port 443

Keycloak runs as user `keycloak`, so **Java** must be allowed to bind low ports.

### Apply capability to Java binary

```bash
sudo setcap 'cap_net_bind_service=+ep' \
  $(readlink -f $(which java))
```

Verify:

```bash
getcap $(readlink -f $(which java))
```

Expected output:

```
cap_net_bind_service=ep
```

⚠️ This survives restarts but **may be lost after Java upgrades**.

---

# 4️⃣ systemd service file (correct & hardened)

**Service file location in this repo:**

```
bm-vm/keycloak.service
```

**Installation location:**

```
/etc/systemd/system/keycloak.service
```

### Deploy Service Manually

Use the deployment script:

```bash
sudo ./deploy-service.sh
```

Or copy manually:

```bash
sudo cp bm-vm/keycloak.service /etc/systemd/system/keycloak.service
sudo chmod 644 /etc/systemd/system/keycloak.service
```

**Service file contents:**

```ini
[Unit]
Description=Keycloak Identity Server
After=network.target

[Service]
Type=exec
User=keycloak
Group=keycloak

WorkingDirectory=/opt/keycloak

ExecStart=/opt/keycloak/bin/kc.sh start-dev

Environment=KC_HOME=/opt/keycloak
Environment=KC_CONF_DIR=/opt/keycloak/conf

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/opt/keycloak /etc/keycloak
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

Restart=on-failure
RestartSec=5

LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

---

# 5️⃣ Reload & start

```bash
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable keycloak
sudo systemctl start keycloak
```

Check status:

```bash
systemctl status keycloak
```

---

# 6️⃣ Validation checklist

### Ports

```bash
ss -tulpen | grep java
```

Expected:

```
LISTEN 0 4096 0.0.0.0:443
```

❌ No `:8080`

---

### HTTP must fail

```bash
curl -v http://auth.example.com
```

→ `Connection refused`

---

### HTTPS works

```bash
curl -vk https://auth.example.com
```

→ `200` or `302`

---

### OIDC metadata

```bash
curl -s https://auth.example.com/realms/master/.well-known/openid-configuration | jq .issuer
```

Expected:

```json
"https://auth.example.com/realms/master"
```

---

# 🔐 Security result

✔ HTTPS enforced
✔ No HTTP listener
✔ Correct issuer URLs
✔ No reverse proxy required
✔ Non-root service user
✔ systemd-hardened

---

---

## 📁 Files in this directory

* **`setup-keycloak-dev.sh`** - Automated setup script (full installation)
* **`deploy-service.sh`** - Manual service deployment script
* **`keycloak.service`** - Systemd service file
* **`Readme.md`** - This file

---

## Next steps (optional)

I can also give you:

* production-mode (`kc.sh start`) hardened config
* automatic cert reload (Let's Encrypt)
* SELinux policy (if enforcing)
* health / metrics exposure over HTTPS only

Just tell me what you want next.
