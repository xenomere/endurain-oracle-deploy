# endurain on Oracle Cloud Always Free (ARM Ampere)

Full endurain (auth, federation, Strava/Garmin sync, admin, websockets) on a free-forever VM:
**VM.Standard.A1.Flex — 4 OCPU / 24 GB RAM / 200 GB disk**, Ubuntu 24.04 aarch64, behind Caddy
with automatic HTTPS. Monthly cost: **$0**.

## What is in this folder

| File | Purpose |
|---|---|
| `oracle/docker-compose.yml` | Caddy (TLS) + endurain API + worker + Postgres 18 (published multi-arch image) |
| `oracle/Caddyfile` | Reverse proxy + Let's Encrypt for your host |
| `oracle/env.example` | Every required variable, with the secrets left as CHANGEME |
| `oracle/bootstrap.sh` | Installs Docker, generates secrets, creates data dirs, opens the firewall, pulls and starts the stack |
| `oracle/duckdns-update.sh` | Cron-friendly DuckDNS A-record updater |

## Steps that need the owner (console work)

### 1. Create the Oracle Cloud account
1. https://signup.oraclecloudeurope.eu (or oracle.com/cloud/free) — pick your **home region**
   (Frankfurt or Amsterdam are closest to Skopje).
2. Verify email and phone. Oracle asks for a payment card for identity verification — Always
   Free resources are not charged; the card is only used if you upgrade.
3. Wait for the account to be provisioned (usually minutes, sometimes a few hours).

### 2. Create the VM (console → Compute → Instances → Create instance)
- **Image:** Canonical Ubuntu 24.04 (aarch64)
- **Shape:** Ampere → **VM.Standard.A1.Flex** → **4 OCPUs, 24 GB memory**
- **Boot volume:** Custom → **200 GB**
- **Networking:** Create new VCN (public subnet), **Assign a public IPv4 address: Yes**
- **SSH keys:** paste your public key (`~/.ssh/id_ed25519.pub`, generate with
  `ssh-keygen -t ed25519` if you have none)
- Leave cloud-init user data empty — bootstrap handles everything.

> If Oracle says "out of host capacity" for A1, retry in another availability domain, or in a
> few hours; capacity frees up regularly. A 2 OCPU / 12 GB instance also runs endurain fine.

### 3. Open the ports (console → Networking → VCN → Security Lists → Default)
Add ingress rules: **22/tcp** (source: your IP), **80/tcp** and **443/tcp** (source 0.0.0.0/0).
`bootstrap.sh` also configures the host `ufw` for the same ports.

### 4. DNS — free subdomain (DuckDNS)
1. https://www.duckdns.org → sign in → create a subdomain, e.g. `kinetics-endurain`
   → your host is `kinetics-endurain.duckdns.org`.
2. Copy the **token** shown at the top of the DuckDNS page.
3. After the VM is up, run once:
   ```bash
   DOMAIN=kinetics-endurain TOKEN=<duckdns-token> /opt/endurain/oracle/duckdns-update.sh
   (crontab -l; echo "*/5 * * * * DOMAIN=kinetics-endurain TOKEN=<token> /opt/endurain/oracle/duckdns-update.sh") | crontab -
   ```
   (DuckDNS needs "*" or your VM IP; the script sends the VM's own IP — run it **on the VM**.)

### 5. SMTP for signup verification (free)
Brevo (https://www.brevo.com, 300 emails/day free) or Resend (100/day):
- Create an account → SMTP credentials.
- Brevo SMTP host `smtp-relay.brevo.com`, port `587`, STARTTLS; username = your Brevo login,
  password = SMTP key.

### 6. Strava (optional, for activity sync)
1. https://www.strava.com/settings/api → create an app.
2. **Authorization Callback Domain:** `kinetics-endurain.duckdns.org` (no scheme).
3. Put the Client ID / Client Secret into `.env` as `STRAVA_CLIENT_ID` / `STRAVA_CLIENT_SECRET`.

## Deploy (5 minutes, mostly autonomous)

On the VM:

```bash
sudo mkdir -p /opt/endurain && cd /opt/endurain
# copy the bundle up from your Mac:
#   scp -r ./endurain-deploy/oracle ubuntu@<VM-IP>:/tmp/oracle && ssh ubuntu@<VM-IP> 'sudo mv /tmp/oracle /opt/endurain/oracle'
sudo bash /opt/endurain/oracle/bootstrap.sh
```

Then edit `/opt/endurain/oracle/.env` (bootstrap already generated DB/secret/Fernet values):

```
ENDURAIN_HOST=https://kinetics-endurain.duckdns.org
SMTP_USERNAME=...
SMTP_PASSWORD=...
STRAVA_CLIENT_ID=...
STRAVA_CLIENT_SECRET=...
```

and start:

```bash
cd /opt/endurain/oracle
sudo docker compose --env-file .env up -d
sudo docker compose ps
```

Caddy fetches the certificate on the first request to the host. Then:

1. Open `https://kinetics-endurain.duckdns.org` → **sign up** — the **first account becomes the
   admin**.
2. Settings → Server settings: server name, registration policy, federation on/off.
3. Settings → Strava: connect, then import history.
4. Settings → Users: invite the studio members.

## Verifying it works

```bash
curl -fsS https://kinetics-endurain.duckdns.org/api/v1/version      # JSON version payload
curl -fsS -o /dev/null -w "%{http_code}\n" https://kinetics-endurain.duckdns.org/webfinger?resource=acct:admin@kinetics-endurain.duckdns.org
```

Federation, websockets and OAuth callbacks all work because the VM never sleeps — the reason
Render's free tier is not suitable for this workload.

## Notes

- **Image:** the published `ghcr.io/endurain-project/endurain:0.20.1` is multi-arch (arm64
  included), so no source build is needed. To pin a newer release, change the tag in
  `docker-compose.yml`.
- **Redis** is optional. The shipped setup uses the database-backed job queue. For a durable
  Redis queue, build the image with `--build-arg PYTHON_EXTRAS=distributed` and set
  `REDIS_URL=redis://redis:6379/0` (the compose file has a commented redis service).
- **Backups:** `data/postgres` and `data/backend/data` hold everything. Nightly:
  `docker exec endurain-postgres pg_dump -U endurain endurain | gzip > /opt/endurain/backup-$(date +%F).sql.gz`
- **Updates:** change the image tag → `docker compose pull && docker compose up -d`
  (migrations run at API startup).
- **Licence:** endurain is AGPL-3.0 — self-hosting for the studio is fine; publish source if
  you distribute a modified server.
