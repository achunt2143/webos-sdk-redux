#!/bin/bash
#
# Uninstallation script for the Palm/HP PDK
#
# Removes the components this repo installs to /opt/PalmPDK. Anything else
# living there -- notably the i386 toolchains from a full OEM PDK install --
# is left alone, since this package never owned it.
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

PDK_INSTALL_DIR="/opt/PalmPDK"
PDK_COMPONENTS="include device bin share"

echo ""
echo "=========================================="
echo "  Palm/HP PDK Uninstallation"
echo "=========================================="
echo ""

if [ "$EUID" -ne 0 ]; then
    log_error "Please run with sudo: sudo ./uninstall-pdk.sh"
    exit 1
fi

if [ ! -d "$PDK_INSTALL_DIR" ]; then
    log_info "No PDK installation found at $PDK_INSTALL_DIR"
    exit 0
fi

for component in $PDK_COMPONENTS; do
    if [ -d "$PDK_INSTALL_DIR/$component" ]; then
        rm -rf "${PDK_INSTALL_DIR:?}/$component"
        log_success "Removed $component"
    fi
done

# Only remove the directory itself if nothing else is left in it. A full OEM
# install would still have arm-gcc/, i686-gcc/, host/ and emulator/ here, and
# those are not ours to delete.
REMAINING=$(ls -A "$PDK_INSTALL_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$REMAINING" -eq 0 ]; then
    rmdir "$PDK_INSTALL_DIR"
    log_success "Removed $PDK_INSTALL_DIR"
else
    log_warning "$PDK_INSTALL_DIR not removed -- $REMAINING other item(s) remain:"
    ls -A "$PDK_INSTALL_DIR" | sed 's/^/    /'
    log_info "These were not installed by this package (likely the OEM toolchains)"
fi

# Point out any backups this package's installer created, but do not delete
# them -- they may be the user's only copy of a full OEM PDK.
if compgen -G "$PDK_INSTALL_DIR.backup.*" > /dev/null 2>&1; then
    echo ""
    log_info "Backups from previous installs were left in place:"
    ls -d "$PDK_INSTALL_DIR".backup.* | sed 's/^/    /'
fi

echo ""
log_success "PDK uninstallation complete"
echo ""
