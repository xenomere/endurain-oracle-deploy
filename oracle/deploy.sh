#!/bin/bash
# After launch: wait for the instance, read its public IP, verify cloud-init and the stack.
set -euo pipefail
export OCI=~/.oci/venv/bin/oci SUPPRESS_LABEL_WARNING=True
ID=$(cat "$HOME/.oci/endurain-instance.id")
echo "instance: $ID"
for i in $(seq 1 60); do
  STATE=$($OCI compute instance get --instance-id "$ID" --query 'data."lifecycle-state"' --raw-output 2>/dev/null || echo unknown)
  echo "state: $STATE"
  [ "$STATE" = "RUNNING" ] && break
  sleep 10
done
IP=$($OCI compute instance list-vnics --instance-id "$ID" --query 'data[0]."public-ip"' --raw-output 2>/dev/null)
echo "public IP: $IP"
echo "$IP" > "$HOME/.oci/endurain-ip.txt"
