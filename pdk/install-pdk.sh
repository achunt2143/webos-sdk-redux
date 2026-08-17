#!/bin/bash
#
# Installation script for the Palm/HP PDK (Plug-in Development Kit)
#
# Installs the host-agnostic parts of the OEM PDK to /opt/PalmPDK: the headers,
# the unstripped ARM device libraries, the device helper scripts and the sample
# code. See PDK.md for what is deliberately left out and why.
#
# The install path is deliberately fixed and unversioned. /opt/PalmPDK is
# hardcoded in the PDK's own helper scripts, in every sample's build script, in
# the bundled Xcode project and throughout HP's documentation. Palm is long
# gone and none of that will ever move, so a versioned directory plus a Current
# symlink would buy nothing.
#
# This script works on both macOS and Linux -- nothing it installs is
# host-specific.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Configuration
#
# pwd -P so that invoking this through a symlink still resolves the real source
# directory (see the equivalent note in the SDK installers).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PDK_SOURCE="$SCRIPT_DIR"
PDK_INSTALL_DIR="/opt/PalmPDK"

# The components shipped in this repo. Each must exist in the source tree.
PDK_COMPONENTS="include device bin share"

echo ""
echo "=========================================="
echo "  Palm/HP PDK Installation"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run with sudo: sudo ./install-pdk.sh"
    exit 1
fi

# Verify source structure before touching anything
for component in $PDK_COMPONENTS; do
    if [ ! -d "$PDK_SOURCE/$component" ]; then
        log_error "PDK component not found: $PDK_SOURCE/$component"
        exit 1
    fi
done

HEADER_COUNT=$(find "$PDK_SOURCE/include" -type f | wc -l | tr -d ' ')
DEVICE_LIB_COUNT=$(find "$PDK_SOURCE/device/lib" -name "*.so*" | wc -l | tr -d ' ')

log_info "PDK source: $PDK_SOURCE"
log_info "Install to: $PDK_INSTALL_DIR"
log_info "Headers: $HEADER_COUNT   Device libraries: $DEVICE_LIB_COUNT"
echo ""

# Back up an existing installation. Unlike the SDK there is no versioned
# directory to fall back to, so a timestamped copy is the only safety net --
# in particular for anyone who has the full OEM PDK (with the i386 toolchains)
# already installed here and would otherwise lose it.
if [ -d "$PDK_INSTALL_DIR" ]; then
    if [ -d "$PDK_INSTALL_DIR/arm-gcc" ] || [ -d "$PDK_INSTALL_DIR/i686-gcc" ]; then
        log_warning "Existing install appears to be the full OEM PDK (includes toolchains)"
        log_warning "This package ships symbols only -- the toolchains will NOT be replaced"
    fi
    BACKUP="$PDK_INSTALL_DIR.backup.$(date +%Y%m%d-%H%M%S)"
    log_info "Backing up existing PDK to: $BACKUP"
    if ! cp -Rp "$PDK_INSTALL_DIR" "$BACKUP"; then
        log_error "Failed to back up existing PDK"
        exit 1
    fi
    log_success "Backup created"
fi

# Install. Components are copied individually rather than copying the whole
# source directory, so that this script and the docs beside it do not end up
# in /opt/PalmPDK -- and so that an existing full OEM install keeps its
# toolchain directories instead of having them deleted out from under it.
log_info "Installing PDK components..."
mkdir -p "$PDK_INSTALL_DIR"

for component in $PDK_COMPONENTS; do
    rm -rf "${PDK_INSTALL_DIR:?}/$component"
    if ! cp -Rp "$PDK_SOURCE/$component" "$PDK_INSTALL_DIR/"; then
        log_error "Failed to install component: $component"
        exit 1
    fi
    log_success "Installed $component"
done

# Ownership and permissions
#
# Normalise the mode rather than only stripping group/other write: "cp -R"
# carries the source tree's permissions across, so installing from a working
# copy that is mode 0700 would otherwise produce a root-owned 0700 tree that no
# ordinary user can traverse. u=rwX,go=rX gives 755 for directories and
# anything already executable, 644 for everything else.
log_info "Setting ownership and permissions..."
if [ "$(uname -s)" = "Darwin" ]; then
    chown -R root:wheel "$PDK_INSTALL_DIR"
else
    chown -R root:root "$PDK_INSTALL_DIR"
fi
chmod -R u=rwX,go=rX "$PDK_INSTALL_DIR"
chmod 755 "$PDK_INSTALL_DIR/bin"/*
log_success "Permissions set"

# Verify
echo ""
log_info "Verifying installation..."
VERIFY_FAILED=0
for f in include/PDL.h device/lib/libpdl.so device/lib/libSDL.so bin/pdk-device-install; do
    if [ ! -e "$PDK_INSTALL_DIR/$f" ]; then
        log_error "Missing after install: $PDK_INSTALL_DIR/$f"
        VERIFY_FAILED=1
    fi
done
if [ "$VERIFY_FAILED" -ne 0 ]; then
    log_error "Installation verification failed"
    exit 1
fi
log_success "Verification passed"

echo ""
echo "=========================================="
echo "  PDK Installation Complete"
echo "=========================================="
echo ""
log_info "Installed to: $PDK_INSTALL_DIR"
log_info "Headers:      $PDK_INSTALL_DIR/include        (PDL.h, SDL, GLES, OpenAL, ...)"
log_info "Device libs:  $PDK_INSTALL_DIR/device/lib     (unstripped ARM .so, with debug symbols)"
log_info "Helpers:      $PDK_INSTALL_DIR/bin            (pdk-device-install, pdk-ssh-init, ...)"
log_info "Samples:      $PDK_INSTALL_DIR/share/samplecode"
echo ""
log_warning "This package contains no compiler."
if [ "$(uname -s)" = "Darwin" ]; then
    echo "  HP's cross-toolchains were 32-bit Intel Mach-O binaries and cannot run on"
    echo "  macOS 10.15 or later."
else
    echo "  HP's cross-toolchains shipped as 32-bit Mach-O binaries for macOS and are"
    echo "  not included here."
fi
echo "  Build with your own ARM toolchain, pointing it at the headers and device"
echo "  libraries above."
echo ""
echo "To install the on-device debugging tools (gdb, dropbear):"
echo "  sudo $PDK_INSTALL_DIR/bin/pdk-device-install install"
echo ""
