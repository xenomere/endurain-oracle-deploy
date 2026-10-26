#!/bin/bash
# cloud-init for the endurain VM: Docker, deploy bundle, secrets, stack start.
set -euo pipefail
exec > >(tee -a /var/log/endurain-bootstrap.log) 2>&1
echo "=== endurain bootstrap $(date -u) ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl git ufw
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi
ROOT=/opt/endurain
mkdir -p "$ROOT"
if [ ! -d "$ROOT/oracle/.git" ]; then
  git clone --depth 1 https://github.com/xenomere/endurain-oracle-deploy "$ROOT"
fi
SRC="$ROOT/oracle"
mkdir -p "$SRC/data/backend/data" "$SRC/data/backend/logs" "$SRC/data/postgres" "$SRC/data/redis"
chown -R 1000:1000 "$SRC/data/backend"
if [ ! -f "$SRC/.env" ]; then
  cp "$SRC/env.example" "$SRC/.env"
  DB_PW="$(openssl rand -hex 16)"
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$DB_PW|; s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PW|" "$SRC/.env"
  sed -i "s|^SECRET_KEY=.*|SECRET_KEY=$(openssl rand -hex 32)|" "$SRC/.env"
  sed -i "s|^FERNET_KEY=.*|FERNET_KEY=$(openssl rand -base64 32 | tr '+/' '-_')|" "$SRC/.env"
  sed -i "s|^ENDURAIN_HOST=.*|ENDURAIN_HOST=http://127.0.0.1|" "$SRC/.env"
  chmod 600 "$SRC/.env"
fi
ufw allow 22/tcp || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true
ufw --force enable || true
cd "$SRC"
docker compose --env-file .env up -d postgres endurain
echo "=== bootstrap complete $(date -u) ==="
