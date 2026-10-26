#!/usr/bin/env bash
# Keeps a DuckDNS A record pointing at this VM. Install as a cron job:
#   (crontab -l; echo "*/5 * * * * DOMAIN=CHANGEME TOKEN=CHANGEME /opt/endurain/oracle/duckdns-update.sh") | crontab -
set -euo pipefail
: "${DOMAIN:?set DOMAIN}"
: "${TOKEN:?set TOKEN}"
curl -fsS "https://www.duckdns.org/update?domains=${DOMAIN}&token=${TOKEN}&ip=" > /dev/null
