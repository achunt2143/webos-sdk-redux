# The PDK — restoring the symbols

The PDK (Plug-in Development Kit) is the native half of webOS development: the
headers and libraries you build C/C++ plug-ins and SDL games against, plus the
tooling to get them onto a device and debug them there.

Earlier releases of this repo shipped **no PDK at all**, on the reasoning that
none of it runs on a modern Mac. That was half right, and the wrong half is the
half that matters.

## What was actually in the box

HP's `palmpdk.pkg` installs 299 MB to `/opt/PalmPDK`. It splits cleanly in two:

| Component | Size | Format | Runs on a modern host? |
|---|---:|---|---|
| `i686-gcc/` | 137 MB | Mach-O **i386** | No |
| `arm-gcc/` | 128 MB | Mach-O **i386** | No |
| `host/` | 12 MB | Mach-O **i386** dylibs | No |
| `emulator/` | 5.9 MB | emulator support | No |
| **`device/lib/`** | **7.0 MB** | **ARM ELF, EABI5, unstripped** | **Yes** |
| **`include/`** | **3.9 MB** | 192 text headers | **Yes** |
| **`share/`** | **5.2 MB** | samples, device packages, jars | **Yes** |
| **`bin/`** | **20 KB** | shell scripts | **Yes** |

The top four are 283 MB of 32-bit Intel executables. Apple removed 32-bit
support in macOS 10.15 Catalina (2019), so they will not launch on any Mac sold
in the last six years — Intel or Apple Silicon, Rosetta or not. Excluding
**those** was the right call, and this repo still excludes them.

The bottom four are 16 MB and contain no host code whatsoever. Headers are text.
The device libraries are ARM ELF objects meant for the *device*, not the host —
their architecture has nothing to do with what you build on. Excluding them was
the mistake, because they are the part you actually need.

## Why the symbols matter without the compiler

`device/lib/` holds 50 shared objects lifted from the device filesystem,
**unstripped and carrying `debug_info`**:

- `libpdl.so` — the PDL API itself (`PDL_Init`, `PDL_CallJS`, the sensor,
  service and purchase APIs declared in `include/PDL*.h`)
- `libSDL.so` and friends — `SDL_net`, `SDL_ttf`, `SDL_image`, `SDL_mixer`
- `libGLESv2.so`, `libGLES_CM.so` — OpenGL ES 2.0 and 1.x
- OpenAL, curl, openssl, freetype, libpng, libjpeg, zlib
- `libc.so.6`, `libstdc++.so.6` — the device's own runtime

You need these regardless of which compiler you use:

- **To link.** A cross-compiler needs the actual `.so` files to resolve
  `PDL_*`, `SDL_*` and `gl*` symbols at link time. Headers alone are not enough.
- **To debug.** They are unstripped, so `gdb` on the device (or a remote gdb)
  can resolve symbols and produce real backtraces through library frames rather
  than bare addresses.
- **To target the right ABI.** They pin the exact glibc and libstdc++ versions
  the device provides, which is what tells you whether a modern toolchain's
  output will actually load there.

None of that depends on HP's dead compiler. It depends on having the artifacts,
which is why they are back.

## What this repo ships

`pdk/` contains the four host-agnostic components and nothing else:

```
pdk/
├── include/          # 192 headers: PDL.h, PDL_JS.h, PDL_Sensors.h, PDL_Services.h,
│                     #   PDL_Purchase.h, PDL_types.h, cplite.h, SDL/, GLES/, GLES2/,
│                     #   AL/, curl/, freetype2/, openssl/, zlib, png, jpeg
├── device/lib/       # 50 unstripped ARM shared objects (see above)
├── bin/              # pdk-device-install, pdk-ssh-init, devprofile, nova-browser
├── share/
│   ├── samplecode/   # simple, shapespin, FileTree, HybridKeyboard, badfont
│   ├── packages/     # on-device gdb + dropbear .ipk (armv6 and armv7)
│   └── jars/         # DeviceBrowser.jar, profile.jar
├── install-pdk.sh
└── uninstall-pdk.sh
```

Provenance: extracted from `palmpdk.pkg` inside
`Palm_webOS_SDK.3.0.5.676.dmg`, the OEM Mac SDK.

## Installing

```bash
cd pdk && sudo ./install-pdk.sh      # or run the top-level ./install.sh
```

One script covers macOS and Linux, because nothing it installs is host-specific.

It installs to **`/opt/PalmPDK`**, unversioned and with no `Current` symlink —
deliberately, and unlike the SDK. That path is hardcoded in the PDK's own helper
scripts, in every sample's `buildit_for_device.sh`, in the bundled Xcode project
and throughout HP's documentation (which still ships in
`Current/share/documentation/sdk/dev-guide/pdk/`). Palm is gone; the path will
never move, so versioning it would buy nothing and break all of the above.

The installer copies components individually rather than replacing the whole
directory. If you already have a full OEM PDK installed there, **your
`arm-gcc/` and `i686-gcc/` are preserved** — the installer says so, takes a
timestamped backup first, and `uninstall-pdk.sh` likewise removes only the four
components it owns, leaving anything else (and any backups) alone.

## Building without HP's toolchain

There is no compiler in this package. Point a modern ARM cross-compiler at the
headers and device libraries:

```bash
arm-linux-gnueabi-gcc \
    -I/opt/PalmPDK/include \
    -L/opt/PalmPDK/device/lib \
    -Wl,--allow-shlib-undefined \
    -lpdl -lSDL -lGLESv2 \
    -o myplugin myplugin.c
```

The TouchPad is ARMv7 (`castle`); the Pre and Pre 2 are ARMv6 (`pixie`). Match
`-march`/`-mfpu` accordingly, and remember the device runs a 2011-era glibc — a
modern toolchain will happily emit binaries it cannot load, so check against
`device/lib/libc.so.6` when something fails at runtime.

## On-device debugging

`share/packages/Native-SDK/` carries `gdb` and `dropbear` as `.ipk`s for both
armv6 and armv7. Push them with the bundled helper:

```bash
sudo /opt/PalmPDK/bin/pdk-device-install install
```

`pdk-ssh-init` then sets up key-based SSH over the novacom link, which is what
makes remote gdb practical.

## Related

- [SDK-VERSION-DETECTION.md](SDK-VERSION-DETECTION.md) — device detection on webOS CE
- [NOVACOM-TCP.md](NOVACOM-TCP.md) — novacom over Wi-Fi
- HP's original PDK guide ships with the SDK at
  `Current/share/documentation/sdk/dev-guide/pdk/`
