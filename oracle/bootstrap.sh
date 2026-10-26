#!/usr/bin/env bash
# endurain bootstrap for Oracle Cloud Always Free (ARM Ampere, Ubuntu 24.04).
# Idempotent: safe to re-run. Generates secrets, prepares data directories,
# builds the arm64 image from source and starts the stack.
set -euo pipefail

ROOT="/opt/endurain"
SRC="$ROOT/oracle"

log() { echo -e "\n==> $*"; }

log "Installing Docker, git and compose plugin"
if ! command -v docker >/dev/null; then
  apt-get update -y
  apt-get install -y ca-certificates curl git ufw
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

log "Pulling the published multi-arch image (arm64)"
docker compose -f "$SRC/docker-compose.yml" --env-file "$SRC/.env" pull endurain

log "Preparing data directories and permissions (container runs as UID 1000)"
mkdir -p "$SRC/data/backend/data" "$SRC/data/backend/logs" "$SRC/data/postgres" "$SRC/data/redis"
chown -R 1000:1000 "$SRC/data/backend" || true

log "Generating .env secrets (only on first run)"
if [ ! -f "$SRC/.env" ]; then
  cp "$SRC/env.example" "$SRC/.env"
  DB_PW="$(openssl rand -hex 16)"
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$DB_PW|; s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PW|" "$SRC/.env"
  sed -i "s|^SECRET_KEY=.*|SECRET_KEY=$(openssl rand -hex 32)|" "$SRC/.env"
  sed -i "s|^FERNET_KEY=.*|FERNET_KEY=$(openssl rand -base64 32 | tr '+/' '-_')|" "$SRC/.env"
  chmod 600 "$SRC/.env"
  echo "Generated $SRC/.env — set ENDURAIN_HOST, SMTP_* and STRAVA_* before first start."
fi

log "Firewall (SSH, HTTP, HTTPS)"
ufw allow 22/tcp || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true
ufw --force enable || true

log "Starting the stack"
docker compose -f "$SRC/docker-compose.yml" --env-file "$SRC/.env" up -d

log "Done. Check: docker compose -f $SRC/docker-compose.yml ps"
echo "First run: open https://<ENDURAIN_HOST> and create the admin account."
