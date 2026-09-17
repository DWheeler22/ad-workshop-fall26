#!/usr/bin/env bash

set -euo pipefail

BH_PASSWORD='Workshop2026!'
BH_URL='http://127.0.0.1:8080'
BH_CLI='/usr/local/bin/bloodhound-cli'

echo "[+] Installing dependencies..."

sudo apt update
sudo apt install -y docker.io curl wget jq

# BloodHound CLI 0.2.x requires Docker Compose v2.
if ! docker compose version >/dev/null 2>&1; then
    echo "[+] Installing Docker Compose v2..."

    if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
        sudo apt install -y docker-compose-v2
    elif apt-cache show docker-compose-plugin >/dev/null 2>&1; then
        sudo apt install -y docker-compose-plugin
    else
        sudo apt install -y docker-compose
    fi
fi

echo "[+] Enabling Docker..."

sudo systemctl enable --now docker

echo "[+] Downloading BloodHound CLI..."

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)
        BH_ARCH="amd64"
        ;;
    aarch64|arm64)
        BH_ARCH="arm64"
        ;;
    *)
        echo "[-] Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$TMP_DIR"

wget -q \
    "https://github.com/SpecterOps/bloodhound-cli/releases/latest/download/bloodhound-cli-linux-${BH_ARCH}.tar.gz"

tar -xzf "bloodhound-cli-linux-${BH_ARCH}.tar.gz"

sudo install -m 755 bloodhound-cli "$BH_CLI"

echo "[+] BloodHound CLI installed:"
"$BH_CLI" version 2>/dev/null || true

echo "[+] Installing BloodHound CE..."

# Run as the current user so the BloodHound config remains associated
# with the current user's ~/.config/bloodhound directory.
sudo -E "$BH_CLI" install

echo "[+] Retrieving generated BloodHound password..."

INITIAL_PASSWORD="$(sudo -E "$BH_CLI" config get default_password | tail -n 1 | tr -d '\r')"

if [[ -z "$INITIAL_PASSWORD" ]]; then
    echo "[-] Could not retrieve the generated BloodHound password."
    exit 1
fi

echo "[+] Waiting for BloodHound API..."

for i in {1..60}; do
    if curl -fsS "$BH_URL" >/dev/null 2>&1; then
        break
    fi

    sleep 2
done

echo "[+] Authenticating as BloodHound admin..."

LOGIN_RESPONSE="$(
    curl -fsS \
        -X POST \
        "$BH_URL/api/v2/login" \
        -H 'Content-Type: application/json' \
        --data "$(jq -n \
            --arg password "$INITIAL_PASSWORD" \
            '{
                login_method: "secret",
                username: "admin",
                secret: $password
            }'
        )"
)"

SESSION_TOKEN="$(jq -r '.data.session_token // empty' <<< "$LOGIN_RESPONSE")"
USER_ID="$(jq -r '.data.user_id // empty' <<< "$LOGIN_RESPONSE")"

if [[ -z "$SESSION_TOKEN" || -z "$USER_ID" ]]; then
    echo "[-] Could not authenticate to BloodHound."
    echo "$LOGIN_RESPONSE"
    exit 1
fi

echo "[+] Setting admin password..."

curl -fsS \
    -X PUT \
    "$BH_URL/api/v2/bloodhound-users/$USER_ID/secret" \
    -H "Authorization: Bearer $SESSION_TOKEN" \
    -H 'Content-Type: application/json' \
    --data "$(jq -n \
        --arg password "$BH_PASSWORD" \
        '{
            secret: $password,
            needs_password_reset: false
        }'
    )" >/dev/null

echo
echo "=================================================="
echo " BloodHound CE installation complete"
echo "=================================================="
echo
echo " URL:      $BH_URL/ui/login"
echo " Username: admin"
echo " Password: $BH_PASSWORD"
echo
echo "=================================================="
