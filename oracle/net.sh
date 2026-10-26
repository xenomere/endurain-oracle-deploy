#!/bin/bash
set -euo pipefail
export OCI=~/.oci/venv/bin/oci
export SUPPRESS_LABEL_WARNING=True
T=$(~/.oci/venv/bin/oci iam compartment list --compartment-id-in-subtree true --query 'data[0]."compartment-id"' --raw-output 2>/dev/null || true)
TENANCY=ocid1.tenancy.oc1..aaaaaaaahz72l5lckm453a5grp2y2jhbw4zt4v3iz7fiudbeyagbgrvvf7ia
EXIST=$($OCI network vcn list --compartment-id "$TENANCY" --query 'data[? "display-name"==`endurain-vcn`].id | [0]' --raw-output 2>/dev/null || echo "")
if [ -z "$EXIST" ] || [ "$EXIST" = "None" ]; then
  VCN=$($OCI network vcn create --compartment-id "$TENANCY" --cidr-block 10.0.0.0/24 --display-name endurain-vcn --dns-label endurain --wait-for-state AVAILABLE --query 'data.id' --raw-output)
else VCN=$EXIST; fi
echo "VCN=$VCN"
IGW=$($OCI network internet-gateway list --compartment-id "$TENANCY" --vcn-id "$VCN" --query 'data[0].id' --raw-output 2>/dev/null || echo "")
if [ -z "$IGW" ] || [ "$IGW" = "None" ]; then
  IGW=$($OCI network internet-gateway create --compartment-id "$TENANCY" --vcn-id "$VCN" --is-enabled true --display-name endurain-igw --wait-for-state AVAILABLE --query 'data.id' --raw-output)
fi
echo "IGW=$IGW"
RT=$($OCI network route-table list --compartment-id "$TENANCY" --vcn-id "$VCN" --query 'data[0].id' --raw-output 2>/dev/null || echo "")
if [ -z "$RT" ] || [ "$RT" = "None" ]; then
  RT=$($OCI network route-table create --compartment-id "$TENANCY" --vcn-id "$VCN" --display-name endurain-rt --route-rules "[{\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$IGW\"}]" --wait-for-state AVAILABLE --query 'data.id' --raw-output)
fi
echo "RT=$RT"
SL=$($OCI network security-list list --compartment-id "$TENANCY" --vcn-id "$VCN" --query 'data[0].id' --raw-output 2>/dev/null || echo "")
if [ -z "$SL" ] || [ "$SL" = "None" ]; then
  SL=$($OCI network security-list create --compartment-id "$TENANCY" --vcn-id "$VCN" --display-name endurain-sl \
    --egress-security-rules '[{"destination":"0.0.0.0/0","protocol":"all","isStateless":false}]' \
    --ingress-security-rules '[{"source":"0.0.0.0/0","protocol":"6","isStateless":false,"tcpOptions":{"destinationPortRange":{"min":22,"max":22}}},{"source":"0.0.0.0/0","protocol":"6","isStateless":false,"tcpOptions":{"destinationPortRange":{"min":80,"max":80}}},{"source":"0.0.0.0/0","protocol":"6","isStateless":false,"tcpOptions":{"destinationPortRange":{"min":443,"max":443}}}]' \
    --wait-for-state AVAILABLE --query 'data.id' --raw-output)
fi
echo "SL=$SL"
SUBNET=$($OCI network subnet list --compartment-id "$TENANCY" --vcn-id "$VCN" --query 'data[? "display-name"==`endurain-subnet`].id | [0]' --raw-output 2>/dev/null || echo "")
if [ -z "$SUBNET" ] || [ "$SUBNET" = "None" ]; then
  SUBNET=$($OCI network subnet create --compartment-id "$TENANCY" --vcn-id "$VCN" --cidr-block 10.0.0.0/24 --display-name endurain-subnet --dns-label endurain --route-table-id "$RT" --security-list-ids "[\"$SL\"]" --wait-for-state AVAILABLE --query 'data.id' --raw-output)
fi
echo "SUBNET=$SUBNET"
cat > "$HOME/.oci/endurain-net.json" <<JSON
{"tenancy":"$TENANCY","vcn":"$VCN","igw":"$IGW","rt":"$RT","sl":"$SL","subnet":"$SUBNET"}
JSON
echo "saved ~/.oci/endurain-net.json"
