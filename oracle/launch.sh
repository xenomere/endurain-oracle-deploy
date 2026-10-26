#!/bin/bash
# Creates the endurain instance, retrying across shapes while A1 capacity is scarce.
set -uo pipefail
export OCI=~/.oci/venv/bin/oci SUPPRESS_LABEL_WARNING=True
TENANCY=ocid1.tenancy.oc1..aaaaaaaahz72l5lckm453a5grp2y2jhbw4zt4v3iz7fiudbeyagbgrvvf7ia
AD="MEye:eu-amsterdam-1-AD-1"
IMG=ocid1.image.oc1.eu-amsterdam-1.aaaaaaaacctrpgvk6atopvfenvfbvg3dmjpexja4bvj67htd4ahz7yv4ntca
SUBNET=$(python3 -c "import json;print(json.load(open('$HOME/.oci/endurain-net.json'))['subnet'])")
KEY=$HOME/.ssh/oracle_endurain.pub
UD=$HOME/.dsh/kinetics/departments/engineering/endurain-deploy/oracle/cloudinit/user-data.sh
LOG=$HOME/.oci/endurain-launch.log
: > "$LOG"
for SHAPE in "1 6" "2 12" "4 24"; do
  set -- $SHAPE; OCPUS=$1; MEM=$2
  for ATTEMPT in $(seq 1 12); do
    echo "[$(date -u +%H:%M:%S)] attempt ocpus=$OCPUS mem=$MEM try=$ATTEMPT" >> "$LOG"
    OUT=$($OCI compute instance launch \
      --compartment-id "$TENANCY" --availability-domain "$AD" \
      --shape VM.Standard.A1.Flex \
      --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEM}" \
      --image-id "$IMG" --subnet-id "$SUBNET" --assign-public-ip true \
      --display-name endurain-server \
      --ssh-authorized-keys-file "$KEY" --user-data-file "$UD" \
      --query 'data.id' --raw-output 2>&1)
    if echo "$OUT" | grep -q "^ocid1.instance"; then
      echo "SUCCESS $OUT" >> "$LOG"
      echo "$OUT" > "$HOME/.oci/endurain-instance.id"
      echo "created: $OUT"
      exit 0
    fi
    echo "  -> $(echo "$OUT" | grep -oE 'Out of host capacity|InternalError|LimitExceeded|[A-Za-z ]{10,60}' | head -1)" >> "$LOG"
    sleep 15
  done
done
echo "gave up: no capacity" >> "$LOG"
exit 1
