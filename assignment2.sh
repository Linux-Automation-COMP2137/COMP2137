#!/usr/bin/env bash
# assignment2.sh
# This script configures the 192.168.16 network interface, installs required software,
# creates users with SSH keys, and sets sudo access for dennis.

set -euo pipefail

echo "Hello! Starting the server1 setup script."
echo "Note: Please run this script using sudo or as root."

# Check for root permissions
if [[ $EUID -ne 0 ]]; then
  echo "[FAIL] Please run as root or with sudo."
  exit 1
fi

# Assignment variables

TARGET_IP="192.168.16.21"
TARGET_CIDR="${TARGET_IP}/24"
GATEWAY_IP="192.168.16.2"
HOSTNAME_TAG="server1"
USERS="dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda"
DENNIS_EXTRA_PUB='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm'

echo
echo "Step 1: Detect the network interface connected to the 192.168.16 network (don’t touch the mgmt one)."
# Detect interface using ip and grep for 192.168.16 subnet
IFACE="$(ip -o -4 addr show | awk '{print $2, $4}' | sed 's#/.*##' | awk '$2 ~ /^192\.168\.16\./ {print $1; exit}')"
if [[ -z "${IFACE:-}" ]]; then
  echo "[FAIL] Could not find an interface on 192.168.16.0/24. Is this server1?"
  exit 1
fi
echo "Detected interface: $IFACE"

# Try to figure out which netplan file sets up this interface.
# Netplan files can end in .yaml or .yml, and if there’s only one file, we’ll use that.

NPFILES=(/etc/netplan/*.yaml /etc/netplan/*.yml)
NPFILE=""
for f in "${NPFILES[@]}"; do
  [[ -f "$f" ]] || continue
  if grep -q "$IFACE" "$f"; then NPFILE="$f"; break; fi
done
# If none are found, just use the only netplan file if one is available.
if [[ -z "$NPFILE" ]]; then
  count=0; lastfile=""
  for f in "${NPFILES[@]}"; do
    [[ -f "$f" ]] && { count=$((count+1)); lastfile="$f"; }
  done
  [[ $count -eq 1 ]] && NPFILE="$lastfile"
fi
if [[ -z "$NPFILE" ]]; then
  echo "[FAIL] No suitable netplan file found in /etc/netplan."
  exit 1
fi
echo "Using netplan file: $NPFILE"

# Backup netplan config once

if [[ ! -f "${NPFILE}.bak" ]]; then
  cp -a "$NPFILE" "${NPFILE}.bak"
  echo "Backed up $NPFILE to ${NPFILE}.bak"
fi

echo "Checking if netplan already contains static IP $TARGET_CIDR."
if grep -qE "^[[:space:]]*-[[:space:]]*${TARGET_IP}/24" "$NPFILE"; then
  echo "Netplan already configured with $TARGET_CIDR on $IFACE."
else
  echo "Adding static IP and gateway to netplan for $IFACE."
  # Add minimal iface stanza if missing
  if ! grep -q "^[[:space:]]*$IFACE:" "$NPFILE"; then
    echo "Adding minimal stanza for $IFACE under ethernets:"
    tmpfile="$(mktemp)"
    awk -v IFACE="$IFACE" '
      { print }
      /^\s*ethernets:\s*$/ && !added {
        print "  " IFACE ":"
        print "    dhcp4: false"
        added=1
      }
    ' "$NPFILE" > "$tmpfile" && mv "$tmpfile" "$NPFILE"
  fi

  # Remove old addresses and gateway lines to avoid duplicates
  tmpfile="$(mktemp)"
  awk -v IFACE="$IFACE" '
    BEGIN { inblock=0 }
    {
      if ($0 ~ "^[[:space:]]*" IFACE ":") inblock=1
      else if ($0 ~ "^[[:space:]]*[a-zA-Z0-9_-]+:" && $0 !~ "^[[:space:]]*" IFACE ":") inblock=0

      if (inblock && ($0 ~ "^[[:space:]]*addresses:" || $0 ~ "^[[:space:]]*gateway4:")) next
      if (inblock && $0 ~ "^[[:space:]]*-[[:space:]]*[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]+") next

      print
    }
  ' "$NPFILE" > "$tmpfile" && mv "$tmpfile" "$NPFILE"

  # Make sure dhcp4: false line present under iface
  if ! grep -q "^[[:space:]]*dhcp4: false" "$NPFILE"; then
    sed -i "/^[[:space:]]*$IFACE:[[:space:]]*$/a\    dhcp4: false" "$NPFILE"
  fi

  # Add addresses and gateway after iface line
  sed -i "/^[[:space:]]*$IFACE:[[:space:]]*$/a\    addresses:\n      - ${TARGET_CIDR}\n    gateway4: ${GATEWAY_IP}" "$NPFILE"
fi

echo "Applying netplan configuration."
netplan generate
netplan apply
echo "[OK] Netplan configured and applied."

echo
echo "Step 2: Update /etc/hosts file to include '$TARGET_IP $HOSTNAME_TAG'."

# Backup /etc/hosts once
if [[ ! -f /etc/hosts.bak ]]; then
  cp -a /etc/hosts /etc/hosts.bak
  echo "Backed up /etc/hosts to /etc/hosts.bak"
fi

# Remove old server1 entries and add the correct one if missing
if grep -qE "^[[:space:]]*$TARGET_IP[[:space:]]+$HOSTNAME_TAG([[:space:]]|\$)" /etc/hosts; then
  echo "/etc/hosts already correctly contains '$TARGET_IP $HOSTNAME_TAG'."
else
  sed -i -E "/^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+$HOSTNAME_TAG([[:space:]]|\$)/d" /etc/hosts
  echo "$TARGET_IP $HOSTNAME_TAG" >> /etc/hosts
  echo "Added '$TARGET_IP $HOSTNAME_TAG' to /etc/hosts."
fi

echo
echo "Step 3 & 4: Making sure apache2 and squid are installed and running."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y

if ! dpkg -s apache2 >/dev/null 2>&1; then
  apt-get install -y apache2
fi
if ! dpkg -s squid >/dev/null 2>&1; then
  apt-get install -y squid
fi

systemctl enable --now apache2 squid

echo "[OK] apache2 status: $(systemctl is-active apache2)"
echo "[OK] squid status: $(systemctl is-active squid)"

echo
echo "Step 5: Creating user accounts and setting up SSH keys."

for user in $USERS; do
  if id "$user" >/dev/null 2>&1; then
    echo "User '$user' already exists."
  else
    echo "Creating user '$user' with home directory and bash shell."
    useradd -m -s /bin/bash "$user"
  fi

  HOMEDIR="/home/$user"
  SSHDIR="$HOMEDIR/.ssh"
  mkdir -p "$SSHDIR"
  chmod 700 "$SSHDIR"
  chown -R "$user:$user" "$SSHDIR"

  # Generate keys for user if missing (run as user for correct ownership)
  [[ -f "$SSHDIR/id_rsa" ]] || sudo -u "$user" ssh-keygen -t rsa -b 4096 -N "" -f "$SSHDIR/id_rsa" >/dev/null
  [[ -f "$SSHDIR/id_ed25519" ]] || sudo -u "$user" ssh-keygen -t ed25519 -N "" -f "$SSHDIR/id_ed25519" >/dev/null

  AUTH_KEYS="$SSHDIR/authorized_keys"
  [[ -f "$AUTH_KEYS" ]] || { touch "$AUTH_KEYS"; chmod 600 "$AUTH_KEYS"; chown "$user:$user" "$AUTH_KEYS"; }

  # Add public keys to authorized_keys if not already present
  for keytype in rsa ed25519; do
    PUB="$SSHDIR/id_${keytype}.pub"
    if ! grep -qF "$(cat "$PUB")" "$AUTH_KEYS"; then
      cat "$PUB" >> "$AUTH_KEYS"
    fi
  done

done

echo
echo "Step 6: Add 'dennis' to sudo group and add extra SSH public key."

usermod -aG sudo dennis || true

DENNIS_AUTH="/home/dennis/.ssh/authorized_keys"
if ! grep -qF "$DENNIS_EXTRA_PUB" "$DENNIS_AUTH"; then
  echo "$DENNIS_EXTRA_PUB" >> "$DENNIS_AUTH"
  echo "Added extra SSH key for dennis."
else
  echo "Extra SSH key for dennis is already present."
fi

echo
echo "----- Setup Summary -----"
echo "Network interface: $IFACE"
ip -4 -brief addr show "$IFACE" | sed 's/^/  /'
echo "Default route: $(ip route show default)"
echo "Hosts file entry: $(grep --color=auto -E \"^[[:space:]]*$TARGET_IP[[:space:]]+$HOSTNAME_TAG([[:space:]]|\$)\" /etc/hosts || echo 'MISSING')"
echo "apache2 status: $(systemctl is-active apache2)"
echo "squid status: $(systemctl is-active squid)"
echo "Users configured: $USERS"
echo "Netplan file: $NPFILE"
echo "========================="
echo
echo "[DONE] Server1 setup complete!"

exit 0

