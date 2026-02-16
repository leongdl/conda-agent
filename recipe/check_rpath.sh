#!/usr/bin/env bash
# check_rpath.sh — Verify that shared libraries in a conda package prefix
# are resolvable using only the package's own lib dirs.
#
# Usage: ./check_rpath.sh <prefix_dir>
# Returns exit code 0 if all critical libs resolve, 1 if critical ones are missing.
# Optional/plugin libs that aren't on the build host are reported as warnings.

set -uo pipefail

PREFIX="${1:?Usage: $0 <prefix_dir>}"

WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# Core system libs — always expected from the OS
CORE_SYSTEM_RE='^(ld-linux|libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libresolv\.so|libutil\.so|libgcc_s\.so|libstdc\+\+\.so)'

# Optional plugin libs — not critical for core app startup
# These are for wayland, gstreamer, gtk2, cups, pulseaudio, etc.
OPTIONAL_RE='^(libQt6Designer|libQt6Wayland|libgtk-x11|libgdk-x11|libgdk_pixbuf|libatk-1\.0|libpango|libcups|libpulse|libspeechd|librsvg|libpoppler|libgd\.so|libgs\.so|libgts-|libmng|libpng12|libpq\.so|libgst(allocators|app|audio|base|gl|pbutils|reamer|video)|libva\.so|libva-drm|libva-x11|libvdpau|libwayland-(cursor|egl)|libxcb-(cursor|icccm|image|keysyms|render-util)|libxkbcommon-x11|libxkbfile|libXaw|libXft|libXp\.so)'

mapfile -t LIB_DIRS < <(find "$PREFIX" -type d \( -name "lib" -o -name "lib64" -o -name "bin" \) 2>/dev/null)

echo "=== Checking rpath resolution under: $PREFIX ==="
COMBINED_LD_PATH=$(IFS=:; echo "${LIB_DIRS[*]}")

find "$PREFIX" -type f \( -name "*.so" -o -name "*.so.*" -o -executable \) > "$WORK_DIR/elfs.txt" 2>/dev/null

CHECKED=0
CRITICAL=0
OPTIONAL=0

while IFS= read -r f; do
    readelf -h "$f" &>/dev/null || continue
    CHECKED=$((CHECKED + 1))

    RPATH=$(readelf -d "$f" 2>/dev/null | grep -E 'RPATH|RUNPATH' | sed 's/.*\[//;s/\]//' || true)
    NEEDED=$(readelf -d "$f" 2>/dev/null | grep NEEDED | sed 's/.*\[//;s/\]//')
    [[ -z "$NEEDED" ]] && continue

    BINARY_DIR=$(dirname "$f")
    ORIGIN_RESOLVED="${RPATH//\$ORIGIN/$BINARY_DIR}"
    SEARCH_PATH="$ORIGIN_RESOLVED:$COMBINED_LD_PATH"

    while read -r lib; do
        FOUND=0
        IFS=: read -ra DIRS <<< "$SEARCH_PATH"
        for d in "${DIRS[@]}"; do
            if [[ -f "$d/$lib" || -L "$d/$lib" ]]; then
                FOUND=1
                break
            fi
        done
        if [[ $FOUND -eq 0 ]]; then
            if echo "$lib" | grep -qP "$CORE_SYSTEM_RE"; then
                : # core system lib, OK
            elif echo "$lib" | grep -qP "$OPTIONAL_RE"; then
                OPTIONAL=$((OPTIONAL + 1))
            else
                echo "CRITICAL: $lib (needed by $(basename "$f"))"
                CRITICAL=$((CRITICAL + 1))
            fi
        fi
    done <<< "$NEEDED"
done < "$WORK_DIR/elfs.txt"

echo ""
echo "=== RPATH CHECK RESULTS ==="
echo "ELF files checked: $CHECKED"
echo "Critical missing: $CRITICAL"
echo "Optional missing (plugin deps not on build host): $OPTIONAL"

if [[ $CRITICAL -eq 0 ]]; then
    echo "STATUS: PASS"
    exit 0
else
    echo "STATUS: FAIL — $CRITICAL critical unresolved references"
    exit 1
fi
