# novacom-tcp — helper files for Wi-Fi novacom

Ready-made pieces for the setup described in [`../NOVACOM-TCP.md`](../NOVACOM-TCP.md).
Read that first: it explains the transport bug, the fix, and why each piece is
needed. These are the parts you would otherwise retype.

| File | Runs on | What it does |
|---|---|---|
| `start-novacomd-wifi.sh` | host (Linux/systemd) | Point the host's novacomd at a device over TCP, keeping USB. |
| `stop-novacomd-wifi.sh` | host (Linux/systemd) | Go back to USB-only. |
| `novacom-wifi-fw` | **device** | Upstart job that opens the novacom ports through webOS's firewall. |

## Host

```sh
./start-novacomd-wifi.sh 192.168.1.42     # serve that device over Wi-Fi, plus USB
./stop-novacomd-wifi.sh                   # USB only
```

Both need `sudo` (they rewrite a systemd drop-in and restart novacomd) and print
`novacom -l` afterwards so you can see what attached. The change persists across
host reboots until you run the other one.

**Run the stop script whenever the Wi-Fi device is off or unreachable.**
novacomd keeps retrying a dead TCP target, and each failed connect stalls the
daemon — USB calls crawl and large installs over USB time out mid-transfer. It
presents as a flaky cable or a failing device, so it is worth recognising.

macOS uses launchd rather than systemd, so these two scripts are Linux-only. The
underlying change is the same: add `-c <device-ip>:6969` to novacomd's arguments.

## Device

`novacom-wifi-fw` goes in `/etc/event.d/` on the device and is only half the job —
novacomd also has to be started with `-b` so it binds all interfaces instead of
localhost. Both steps, and the traps around editing upstart jobs on webOS, are in
[`../NOVACOM-TCP.md`](../NOVACOM-TCP.md).

**Edit the source range in `novacom-wifi-fw` before installing it.** It ships
scoped to `192.168.1.0/24` as a placeholder. Network novacom is an
unauthenticated root shell: scope it to a network you trust, or to the single
host you develop from.
