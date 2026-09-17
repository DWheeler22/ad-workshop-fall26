#!/bin/bash

set -e

echo "[+] Installing Docker..."
sudo apt update
sudo apt install -y docker-cli docker-compose docker.io curl

echo "[+] Starting Docker..."
sudo systemctl enable --now docker

echo "[+] Downloading and starting BloodHound CE..."

curl -L https://ghst.ly/getbhce -o /tmp/docker-compose.yml

sudo docker-compose \
    -f /tmp/docker-compose.yml \
    up -d

echo "[+] Waiting for BloodHound to initialize..."

# Wait until the BloodHound container exists
until BH_CONTAINER=$(sudo docker ps \
    --format '{{.ID}} {{.Names}}' |
    awk '/bloodhound/ {print $1; exit}') && [ -n "$BH_CONTAINER" ]; do
    sleep 2
done

# Wait until the initial password appears in the logs
until PASSWORD_LINE=$(sudo docker logs "$BH_CONTAINER" 2>&1 |
    grep -i -m1 'initial password\|password.*admin\|admin.*password'); do
    sleep 2
done

echo
echo "======================================"
echo " BloodHound CE is running"
echo "======================================"
echo
echo "Username: admin"
echo "$PASSWORD_LINE"
echo
echo "URL: http://localhost:8080/ui/login"
echo