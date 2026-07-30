# Novacom over TCP/IP (Wi-Fi) — the RCVLOWAT fix

As of commit `06979cd`, novacomd's TCP transport works on Linux hosts. This
enables **wireless novacom to a stock webOS device**: the device appears in
`novacom -l` as a `tcp` entry alongside USB devices, and every SDK tool
(`novacom`, `novaterm`, `palm-install`, `palm-log`, …) works over it
unchanged. Useful when the device's only USB port is needed for something
else (accessory testing, charging on a Touchstone across the room, etc.).

## The bug

`novacomd/src/transport_inet.c` (`inet_rx_loop`) set a receive low-water
mark of one full packet buffer on every TCP transport socket:

```c
opt = IP_MAX_PACKET_SIZE;   /* 4096 */
setsockopt(socket, SOL_SOCKET, SO_RCVLOWAT, (const char *)&opt, sizeof(opt));
```

`SO_RCVLOWAT` tells the kernel "don't wake a blocking `recv()` until this
many bytes are queued." But the transport's messages are tiny:

| Message | Size |
|---|---|
| `nduid: …` handshake syn | 48 bytes |
| `ELTSDIM` packet header (keepalive when `packetlen == 0`) | 12 bytes |

Linux honors `SO_RCVLOWAT` in `recv()`. So a connecting daemon
(`novacomd -c <device>:6969`) would establish the TCP session, send its own
syn, then block in `recv()` waiting for 4096 bytes that never arrive in a
timely way. The remote device never registered.

The smoking gun is visible from the outside: the connection sits in
`ESTAB` while its Recv-Q grows as `48 + n × 12` — the peer's unread syn
plus one 12-byte keepalive every ~2 seconds. (After ~11 minutes, 4096
bytes finally accumulate and the transport lurches forward one step, which
is why TCP mode historically seemed "almost working" rather than dead, and
why it behaved differently on platforms with laxer RCVLOWAT semantics.)

## The fix

Two changes in `inet_rx_loop`:

1. **Remove the `SO_RCVLOWAT` call.**
2. **Pass `MSG_WAITALL` to the three exact-length `recv()` calls**
   (handshake syn, packet header, payload).

The low-water mark was doubling as a crude message-reassembly guarantee —
the loop treats any short read as a fatal "invalid packet." `MSG_WAITALL`
is the correct primitive: block until exactly the requested length has
arrived. This also fixes spurious transport drops when a payload larger
than one TCP segment (~1448 bytes on typical Wi-Fi) arrived fragmented.

The same code exists verbatim in the `openwebos/novacomd` and
`webosose/novacomd` repositories; the patch ports trivially.

## Using it: host ⇄ device over Wi-Fi

Direction matters: **the host must dial the device.** Only the connecting
side registers the peer as a device (`novacom_go_online(nduid, "tcp", …)`);
the listening side merely announces itself and serves. Port map
(`novacomd/include/novacom.h`): 6968 device-list, **6969 inet transport**,
6970 log, 6971 ctrl.

### Device side (tested: HP TouchPad, webOS 3.0.5)

1. Make the device's novacomd bind all interfaces instead of localhost.
   Edit `/etc/event.d/novacomd` and add `-b` to the exec line:

   ```
   exec /sbin/novacomd -b > /dev/null
   ```

   Then reboot the device. **Warnings from the field:**
   - Never kill/stop novacomd from a novacom session — the job stanza
     `normal exit 0 TERM` means upstart will NOT respawn it, and you lose
     all access until a physical reboot.
   - Never leave a backup copy inside `/etc/event.d/` — upstart treats
     every file there as a job; a stale copy races the real one at boot
     (and the loser silently does nothing, because novacomd refuses to
     start twice). Keep backups elsewhere, e.g. `/etc/`.

2. Open the firewall. webOS's INPUT policy is DROP on the Wi-Fi interface
   (only established flows, mDNS, and some ICMP pass). Runtime rule:

   ```
   iptables -I INPUT 1 -i eth0 -s <your-lan>/24 -p tcp --dport 6968:6970 -j ACCEPT
   ```

   For persistence, install the ready-made upstart job
   [`novacom-tcp/novacom-wifi-fw`](novacom-tcp/novacom-wifi-fw) as
   `/etc/event.d/novacom-wifi-fw` (edit its source range first).

   **The ~60s delay in that job is load-bearing.** The platform's own firewall
   setup runs during boot and flushes the INPUT chain, so a rule inserted
   earlier is silently wiped. If you shorten it, verify with
   `iptables -L INPUT -n` several minutes after boot rather than seconds.

3. Give the device a DHCP reservation so its IP is stable.

### Host side

Run the (patched) host novacomd with `-c`:

```
novacomd -c <device-ip>:6969
```

e.g. as a systemd drop-in (`/etc/systemd/system/novacomd.service.d/tcp-device.conf`):

```ini
[Service]
ExecStart=
ExecStart=/usr/local/bin/novacomd -c <device-ip>:6969
```

Scripts that write that drop-in and restart the daemon for you are in
[`novacom-tcp/`](novacom-tcp/):

```sh
novacom-tcp/start-novacomd-wifi.sh 192.168.1.42   # Wi-Fi device + USB
novacom-tcp/stop-novacomd-wifi.sh                 # back to USB-only
```

**Turn the connector off when the device is unreachable.** This is the one
operational gotcha worth internalising: while the Wi-Fi target is powered
off, asleep or off-network, novacomd keeps retrying that address and every
failed connect stalls the daemon. USB access degrades badly — `novacom -d
usb` calls crawl and large installs over USB time out mid-transfer. It
presents exactly like a failing cable or a dying device, and it has cost
real debugging time. `stop-novacomd-wifi.sh` is the fix.

The connector retries every second, so device reboots and Wi-Fi drops
re-attach automatically. The device shows up as type `emulator` on the
`tcp` transport (TCP devices share the emulator attach path):

```
$ novacom -l
35625 c37f7a34…  usb topaz-linux
37291 c37f7a34…  tcp emulator
```

Target it explicitly with `novacom -d tcp …` when USB is also connected;
with the cable unplugged it's simply the only device.

### Known limitation: the client's direct-dial mode

The `novacom` client can also talk straight to a device's daemon, skipping
the local novacomd entirely:

```
novacom -a <device-ip> -p 6968 -l
```

That **works** — it returns the device list. But the same form with `run`,
`put` or `get` hangs and then reports `unable to find device`, against a
device whose ports are open and which the `-c` connector serves happily at
the same moment. So direct-dial is usable for enumeration only.

We did not chase the cause, because the connector path above does
everything and the direct path adds nothing once it is set up. Noting it
so the next person does not spend an afternoon assuming their firewall or
`-b` setup is wrong when the enumeration half works and the useful half
does not. If you do dig in, the interesting asymmetry is that the device
runs a **stock, unpatched** `novacomd-119`: the `-c` arrangement puts the
patched host daemon on the rx side of the transport, whereas direct-dial
does not — which would fit, though we have not proven it.

More broadly, this is the shape of the whole feature: the ports, the `-b`
flag, the `-c` connector and the emulator attach path are all present in
Palm's code, and it looks like TCP support was built out and never
finished off. Most of it works once `SO_RCVLOWAT` stops breaking the
handshake.

### Security note

Network novacom is an **unauthenticated root shell**. Scope the firewall
rule to your trusted LAN (or a single host), and treat any device with
`-b` enabled as lab equipment, not a daily driver.

## Verification performed

Against a stock webOS 3.0.5 TouchPad (`novacomd-119` on-device, untouched
binary): device attaches over Wi-Fi within a second of the host daemon
starting; interactive `run`, `put`, and `get` all work; a 300 KB random
binary round-trip (`put` then `get`) came back byte-identical; a ~1 MB
`/var/log/messages` pull succeeded; the host auto-reattaches after device
reboots.
