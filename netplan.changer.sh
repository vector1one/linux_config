#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:"
  echo "sudo $0"
  exit 1
fi

NETPLAN_DIR="/etc/netplan"
BACKUP_DIR="/etc/netplan/backup"

mkdir -p "$BACKUP_DIR"

echo "Ubuntu Netplan Static IP Config"
echo "--------------------------------"

mapfile -t NETPLAN_FILES < <(find "$NETPLAN_DIR" -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.yml" \) | sort)

if [[ ${#NETPLAN_FILES[@]} -eq 0 ]]; then
  NETPLAN_FILE="$NETPLAN_DIR/01-static-ip.yaml"
elif [[ -f "$NETPLAN_DIR/50-cloud-init.yaml" ]]; then
  NETPLAN_FILE="$NETPLAN_DIR/50-cloud-init.yaml"
else
  echo "Detected Netplan files:"
  select FILE in "${NETPLAN_FILES[@]}"; do
    if [[ -n "$FILE" ]]; then
      NETPLAN_FILE="$FILE"
      break
    fi
  done
fi

echo
echo "Using Netplan file: $NETPLAN_FILE"

if [[ ! -f "$NETPLAN_FILE" ]]; then
  echo "Creating new Netplan file: $NETPLAN_FILE"
  touch "$NETPLAN_FILE"
fi

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_FILE="$BACKUP_DIR/$(basename "$NETPLAN_FILE").bak-$TIMESTAMP"
cp "$NETPLAN_FILE" "$BACKUP_FILE"

echo "Backup created: $BACKUP_FILE"
echo

DEFAULT_IFACE=$(ip route | awk '/default/ {print $5; exit}' || true)

read -rp "Network interface [$DEFAULT_IFACE]: " IFACE
IFACE=${IFACE:-$DEFAULT_IFACE}

if [[ -z "$IFACE" ]]; then
  echo "No network interface selected."
  exit 1
fi

if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "Interface '$IFACE' does not exist."
  echo "Available interfaces:"
  ip -o link show | awk -F': ' '{print $2}'
  exit 1
fi

read -rp "Static IP, example 192.168.2.143 or 192.168.2.143/24: " STATIC_IP

if [[ "$STATIC_IP" != */* ]]; then
  read -rp "CIDR prefix length [24]: " PREFIX
  PREFIX=${PREFIX:-24}
  STATIC_IP="${STATIC_IP}/${PREFIX}"
fi

read -rp "Gateway, example 192.168.2.1: " GATEWAY
read -rp "DNS servers, comma separated [1.1.1.1,8.8.8.8]: " DNS
DNS=${DNS:-"1.1.1.1,8.8.8.8"}

if [[ -z "$STATIC_IP" || -z "$GATEWAY" ]]; then
  echo "Static IP and gateway are required."
  exit 1
fi

DNS_FORMATTED=$(echo "$DNS" | tr -d ' ' | sed 's/,/, /g')

echo
echo "Writing Netplan config..."

cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: false
      addresses:
        - $STATIC_IP
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$DNS_FORMATTED]
EOF

chmod 600 "$NETPLAN_FILE"

echo
echo "Generated config:"
cat "$NETPLAN_FILE"

echo
echo "Verifying Netplan config..."
netplan generate

echo
echo "Applying Netplan config..."
netplan apply

echo
echo "Done."
echo "Interface: $IFACE"
echo "IP:        $STATIC_IP"
echo "Gateway:   $GATEWAY"
echo "DNS:       $DNS_FORMATTED"
echo "File:      $NETPLAN_FILE"
