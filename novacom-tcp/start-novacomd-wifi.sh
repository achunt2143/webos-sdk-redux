#!/usr/bin/env bash
#
# start-novacomd-wifi.sh <DEVICE_IP>
#
# Configure this host's novacomd to ALSO serve a webOS device over Wi-Fi (TCP),
# on top of USB, by writing a systemd drop-in and restarting the daemon.
#
#   ./start-novacomd-wifi.sh 192.168.1.42
#
# Requires a novacomd with the TCP transport fix (see ../NOVACOM-TCP.md) and the
# device prepared per that document (novacomd -b + firewall). Requires sudo.
# Reverse with stop-novacomd-wifi.sh.
#
# CAVEAT, and the reason the "stop" script exists: while the Wi-Fi target is
# unreachable -- device powered off, asleep, or off the network -- novacomd keeps
# retrying that address, and USB access degrades badly. Each failed connect
# stalls the daemon, so `novacom -d usb` calls crawl and large installs over USB
# can time out mid-transfer. Run stop-novacomd-wifi.sh when you are done with
# Wi-Fi, or before heavy USB work.
#
# Linux/systemd only. On macOS novacomd is managed by launchd -- add the same
# `-c <ip>:6969` argument to its launchd plist instead.
#
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $(basename "$0") <DEVICE_IP>" >&2
    echo "  e.g. $(basename "$0") 192.168.1.42" >&2
    exit 2
fi

IP="$1"
PORT="${NOVACOM_TCP_PORT:-6969}"
NOVACOMD="${NOVACOMD:-/usr/local/bin/novacomd}"
DROPDIR=/etc/systemd/system/novacomd.service.d
DROPIN="$DROPDIR/tcp-device.conf"

# rudimentary IPv4 sanity check
case "$IP" in
    *[!0-9.]*|""|*..*) echo "error: '$IP' is not an IPv4 address" >&2; exit 2 ;;
esac

[ -x "$NOVACOMD" ] || { echo "error: $NOVACOMD not found or not executable" >&2; exit 1; }

echo ">> configuring novacomd to serve Wi-Fi device ${IP}:${PORT} (+ USB)"
sudo mkdir -p "$DROPDIR"
sudo tee "$DROPIN" >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=${NOVACOMD} -c ${IP}:${PORT}
EOF
sudo systemctl daemon-reload
sudo systemctl restart novacomd

# The connector retries about once a second; give it a moment to attach.
sleep 2
echo ">> novacom devices:"
novacom -l 2>&1 || true
echo ">> done. Target the Wi-Fi device with:  novacom -d tcp ..."
