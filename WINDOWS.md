# Windows support

Windows gets a batch installer rather than a GUI. It covers the same three
pieces the Unix installers do — SDK, novacom, PDK. The USB driver comes from
HP's original MSI, committed to `windows/`; **novacomd builds from source**, as
on macOS and Linux (see [novacomd on Windows](#novacomd-on-windows)), and
replaces HP's 2011 daemon when it has been built. The `novacom` client is still
HP's.

```
install-windows.bat            :: run from the repo root, elevated (Administrator)
```

Options: `/y` (no prompts), `/sdkdir <path>`, `/nopdk`, `/nonovacom`,
`/hpnovacomd` (keep HP's daemon even if this repo's is built).

| Component | Lands at |
|---|---|
| SDK | `%ProgramFiles%\PalmSDK\<version>`, with a `Current` junction |
| `palm-*` commands | `%ProgramFiles%\PalmSDK\Current\bin`, added to the system PATH |
| novacom driver, HP's `novacomd.exe` and `novacom.exe` | wherever the MSI puts them |
| this repo's `novacomd.exe`, if built | `%ProgramFiles%\PalmSDK\novacomd`, as the `NovacomD` service |
| PDK | `C:\PalmPDK` |

Open a **new** terminal afterwards so the PATH change is visible, then
`palm-install --version`.

## How the pieces fit together

The important structural fact, which shapes everything else: **the Java tools
never shell out to a `novacom` binary.** They open a TCP connection to novacomd
on `127.0.0.1:6968` (`Novacom.DEFAULT_HOST` / `DEFAULT_PORT` in the jar) and
speak the protocol directly.

That means the SDK half of Windows support is trivial and the driver half is
everything:

- `webos-tools.jar` is **pure Java with zero native libraries** and no
  OS-specific code paths, so each `palm-*` command is one `java` invocation.
- Anything that makes port 6968 answer will satisfy the SDK. On Windows that is
  `novacomd.exe`, which needs the USB driver underneath it.

## The `palm-*.bat` launchers

`0.4/bin/palm-*.bat` sit alongside their bash equivalents. Each one is a
wrapper around a single command:

```bat
java -Dpalm.command=palm-install -jar "...\share\jars\webos-tools.jar" %*
```

The jar reads `palm.command` (`Shell.java`) and looks it up in
`command.properties`, which maps the seven commands (`palm-generate`,
`palm-package`, `palm-install`, `palm-launch`, `palm-log`, `palm-help`,
`palm-run`). `palm-worm` is the exception: it drives `worm.jar` with a larger
heap.

Shared Java detection lives in `palm-common.bat`, which each launcher `call`s.
It looks for `java` on PATH, falls back to `%JAVA_HOME%`, and requires major
version 8 or greater — the same contract as the bash scripts. There is no
Cygwin-style path translation, because a native batch file already runs with
native Windows paths.

These were written from the bash scripts and the jar's own dispatch table, not
extracted from HP's Windows SDK: that installer is an InstallShield
ISSetupStream archive whose payload is individually compressed, and neither
7-Zip nor unshield can open it. Nothing was lost by rebuilding them — the
invocation is fully determined by `command.properties` and `Shell.java`.

## The novacom driver

`windows/NovacomInstaller_{x86,x64}.msi` are HP's originals, dated 25 Jun 2011.
The installer picks the right one for the machine's architecture and runs
`msiexec /i ... /passive /norestart`.

What the MSI actually does, since none of it is obvious from the outside:

- Installs `novacom.inf`, `novacom.cat`, `novacomd.exe`, `dpinst.exe` and the
  WinUSB/UMDF co-installers, plus the VC++ 2005 (`msvcr80`) runtime that
  `novacomd.exe` links against.
- Runs `dpinst.exe -lm -sw` to install the driver package.
- Registers the daemon by invoking **`novacomd.exe -i`** — not through an MSI
  `ServiceInstall` entry, so the MSI has no `ServiceInstall` or `ServiceControl`
  table at all. Removal is `novacomd.exe -d`.

**There is no third-party kernel driver.** `novacom.inf` binds Palm's USB IDs
(VID `0830`, the various TouchPad and Pre PIDs) to Microsoft's in-box
`WinUSB.sys`:

```
Include = WinUSB.inf
Needs   = WinUSB.NT
AddService = WinUSB, 0x00000002, WinUSB_ServiceInstall
ServiceBinary = %12%\WinUSB.sys
```

That matters for whether it still installs on modern Windows. The only kernel
binary involved is Microsoft's own, which is always trusted; the `.cat` is used
for driver-package integrity during PnP install, not to authorise loading a
third-party kernel module.

The catalog is signed by **Microsoft** through the WHQL programme:

```
Subject: CN=Microsoft Windows Hardware Compatibility Publisher, OU=MOPR, O=Microsoft Corporation
Issuer : CN=Microsoft Windows Hardware Compatibility PCA
Digest : SHA1
Timestamp: 11 Mar 2011
```

So it is about as well-signed as a 2011 driver package can be — not a
self-signed or expired third-party certificate. The residual risk is the
**SHA-1** digest: modern Windows distrusts SHA-1 code signatures, generally for
anything timestamped after the 2016 cutoff. This one is countersigned in 2011,
which is on the permissive side of that line.

**Windows 11 accepts it once installed.** On Windows 11 (build 26200) an HP
TouchPad's novacom interface (`VID_0830&PID_8072&MI_01`) binds to `WinUSB`
through Palm's `oem*.inf`, version 1.0.1.0, and both HP's novacomd and this
repo's work through it. That copy came from HP's full SDK installer; a fresh
install from the MSI here on Windows 11 has not been tried. If Windows rejects
the driver, the SDK half still installs and works — you simply have no way to
reach a device, because nothing will be listening on 6968.

## novacomd on Windows

This repo's novacomd builds for Windows with MSYS2's MinGW-w64, from the same
sources as macOS and Linux. Install [MSYS2](https://www.msys2.org/)
(`winget install MSYS2.MSYS2`), then in the **MSYS2 UCRT64** shell:

```bash
cd novacomd && ./build.sh          # installs gcc, make, libusb-1.0 via pacman
```

`build-novacomd\novacomd.exe` is statically linked (no DLLs). Run
`install-windows.bat` afterwards and it takes over the service, or do it by hand
as Administrator:

```
novacomd.exe -i      :: register as the NovacomD service and start it
novacomd.exe -u      :: stop and remove the service (-d also works, as with HP's)
novacomd.exe         :: run in the console instead (stop the service first)
```

`-i` uses HP's service name and display name (`NovacomD`, "Palm Novacom"), so
it repoints HP's existing registration at itself rather than adding a second
daemon fighting over the same ports. `install-windows.bat` records HP's path
first and `uninstall-windows.bat` hands the service back to it.

What it brings over HP's 2011 build: the TCP transport fix
([NOVACOM-TCP.md](NOVACOM-TCP.md)) and Lunacy devices through adb
([LUNACY.md](LUNACY.md)).

How the port is put together, for anyone changing it:

- **No Windows fork of the sources.** `novacomd/include/win32/` stands in for
  `<sys/socket.h>`, `<netinet/in.h>`, `<poll.h>`, `<syslog.h>`,
  `<sys/queue.h>` and friends, so the shared files keep their POSIX includes;
  what Winsock spells differently goes through `platform_closesocket()`,
  `platform_socket_cloexec()` and `platform_socket_nonblock()`.
- **USB is libusb-1.0**, in `host/usb-linux.c` beside the original libusb-0.1
  code (`USB_LIBUSB1=1`). libusb's WinUSB backend opens the device through the
  driver package above, so no Zadig or libwdi step is needed.
- **A service, not a daemon**: `host/service_win32.c`. The executable tells
  whether the SCM started it, as HP's did, so the service's command line has no
  flags. Logging goes to `OutputDebugString` (Sysinternals DebugView) and, as
  everywhere, to anyone connected to port 6970.
- **Listen sockets use `SO_EXCLUSIVEADDRUSE`.** Winsock's `SO_REUSEADDR` would
  let a second novacomd bind ports another one is already listening on.
- **Session ids come from `rand_s()`.** The Windows C runtime keeps `rand()`'s
  state per thread, and only the main thread is seeded, so the USB thread's
  first session id was 41 in every process. A device still holding session 41
  from a novacomd that had been killed then looked like ours: its heartbeats
  were accepted, no reset was sent, and the link never came up.
- **Host-side `get`/`put`/`connect`** — a device asking the *host* to serve its
  own files — is compiled out: it selects over pipes, which Windows can't. The
  SDK tools never use that direction.

After installing, the script probes that port and tells you what it found. It
checks the port rather than a service name deliberately: the port is the actual
contract the SDK depends on, and the service name is not discoverable from the
MSI, since novacomd registers itself.

## The PDK

`C:\PalmPDK` receives `include\`, `device\` and `share\`. `pdk\bin\` is skipped
— those helpers (`pdk-device-install`, `pdk-ssh-init`) are bash scripts.

As on macOS and Linux, **no compiler is included**; see [PDK.md](PDK.md). The
bundled samples' build scripts are Unix shell and will not run under `cmd`
either, so on Windows the PDK is headers and ARM device libraries for your own
toolchain, nothing more.

## Uninstalling

```
uninstall-windows.bat
```

Removes the SDK, the PATH entry, and the PDK components this repo installed
(leaving anything else under `C:\PalmPDK` alone). If this repo's novacomd had
taken over the `NovacomD` service, the service is handed back to HP's daemon
first. It deliberately does **not** remove novacom: that came from an MSI, so
removing it by hand would leave the Windows installer database inconsistent.
Uninstall "Palm Novacom" from Settings → Apps, or
`msiexec /x NovacomInstaller_<arch>.msi`.

## Known gaps

- A fresh install of the driver from the MSI is untested on Windows 10/11; an
  existing install works on Windows 11 (see above).
- `novacomd.exe` is unsigned, HP's and this repo's alike. Only the driver
  catalog carries a signature.
- The `novacom` client is still HP's 2011 build; only novacomd is built here.
- This repo's novacomd has been tested on Windows 11 against an HP TouchPad
  (webOS CE 3.1.0) over USB, both in a console and as the service. Not yet
  tried: a Pre or other Palm device, TCP to a device, Lunacy (needs an Android
  device), and unplug/replug while connected.
- The installer has been syntax- and logic-checked, and its PowerShell fragments
  were executed directly, but the batch files themselves have not been run
  end to end on Windows.
