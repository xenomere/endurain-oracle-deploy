#!/bin/bash
# Waits for the instance and SSH, then reports cloud-init and stack status.
set -euo pipefail
export OCI=~/.oci/venv/bin/oci SUPPRESS_LABEL_WARNING=True
ID=$(cat "$HOME/.oci/endurain-instance.id")
IP=$(cat "$HOME/.oci/endurain-ip.txt" 2>/dev/null || true)
if [ -z "$IP" ]; then
  IP=$($OCI compute instance list-vnics --instance-id "$ID" --query 'data[0]."public-ip"' --raw-output)
  echo "$IP" > "$HOME/.oci/endurain-ip.txt"
fi
echo "IP=$IP"
OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i $HOME/.ssh/oracle_endurain"
for i in $(seq 1 90); do
  if nc -z -G 5 "$IP" 22 2>/dev/null; then echo "ssh port open"; break; fi
  sleep 10
done
ssh $OPTS ubuntu@"$IP" 'cloud-init status --wait; echo "---"; cd /opt/endurain/oracle 2>/dev/null && sudo docker compose ps || echo "stack not found yet"'
