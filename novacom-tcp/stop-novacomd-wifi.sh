#!/usr/bin/env bash
#
# stop-novacomd-wifi.sh
#
# Restart this host's novacomd USB-only, dropping the Wi-Fi (TCP) transport.
#
# Use this whenever the Wi-Fi device is off or unreachable. Otherwise novacomd
# keeps retrying the dead TCP target, every failed connect stalls the daemon,
# and USB access crawls -- large installs over USB can time out mid-transfer.
# That symptom looks like a broken cable or a broken device, so reach for this
# script before you go hunting hardware faults.
#
# Requires sudo. Re-enable with:  ./start-novacomd-wifi.sh <DEVICE_IP>
#
# Linux/systemd only. On macOS, remove the `-c <ip>:6969` argument from
# novacomd's launchd plist instead.
#
set -euo pipefail

DROPIN=/etc/systemd/system/novacomd.service.d/tcp-device.conf

if [ -f "$DROPIN" ]; then
    echo ">> removing Wi-Fi drop-in $DROPIN"
    sudo rm -f "$DROPIN"
    sudo systemctl daemon-reload
else
    echo ">> no Wi-Fi drop-in present; just recycling novacomd"
fi
sudo systemctl restart novacomd

sleep 2
echo ">> novacomd is now USB-only. Devices:"
novacom -l 2>&1 || true
