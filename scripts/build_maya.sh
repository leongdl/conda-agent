#!/usr/bin/env bash
# build_maya.sh — Build script for the Maya conda package.
# Extracts the Maya RPM, copies system dependencies, and installs into $PREFIX.
set -uo pipefail

echo "=== Maya conda package build ==="
echo "PREFIX=$PREFIX"
echo "SRC_DIR=$SRC_DIR"

MAYA_ROOT="$PREFIX/opt/autodesk/maya2026"
MAYA_BIN="$MAYA_ROOT/bin"
MAYA_LIB="$MAYA_ROOT/lib"

mkdir -p "$MAYA_ROOT"

# 1. Extract the Maya RPM
echo "Extracting Maya RPM..."
rpm2cpio "$SRC_DIR/Packages/Maya2026_64-2026.0-13485.x86_64.rpm" | \
    cpio -idm -D "$PREFIX" 2>/dev/null

# The RPM installs to /usr/autodesk/maya2026 — move to our prefix layout
if [[ -d "$PREFIX/usr/autodesk/maya2026" ]]; then
    cp -a "$PREFIX/usr/autodesk/maya2026/"* "$MAYA_ROOT/"
    rm -rf "$PREFIX/usr"
fi
rm -rf "$PREFIX/opt/Autodesk"

# 2. Bundle system libraries directly into lib/ so existing rpaths resolve
echo "Bundling system dependencies into $MAYA_LIB ..."

SYSTEM_LIBS=(
    # X11 / display
    libEGL.so.1 libGL.so.1 libGLU.so.1 libGLX.so.0 libOpenGL.so.0
    libICE.so.6 libSM.so.6
    libX11.so.6 libX11-xcb.so.1 libXcomposite.so.1 libXdamage.so.1
    libXext.so.6 libXfixes.so.3 libXi.so.6 libXinerama.so.1
    libXmu.so.6 libXpm.so.4 libXrandr.so.2 libXrender.so.1
    libXt.so.6 libXtst.so.6 libXv.so.1 libXxf86vm.so.1
    libxcb.so.1 libxcb-glx.so.0 libxcb-randr.so.0 libxcb-render.so.0
    libxcb-shape.so.0 libxcb-shm.so.0 libxcb-sync.so.1
    libxcb-xfixes.so.0 libxcb-xkb.so.1 libxcb-dri3.so.0
    libxkbcommon.so.0
    # Graphics
    libcairo.so.2 libdrm.so.2
    libfontconfig.so.1 libfreetype.so.6
    libpng16.so.16 libjpeg.so.62 libtiff.so.5
    # GLib / GTK
    libglib-2.0.so.0 libgmodule-2.0.so.0 libgobject-2.0.so.0
    libgio-2.0.so.0 libgthread-2.0.so.0
    # Audio
    libasound.so.2
    # Networking / crypto
    libcrypto.so.3 libssl.so.3 libcurl.so.4 libgssapi_krb5.so.2
    libnss3.so libnspr4.so libnssutil3.so libsmime3.so libplc4.so libplds4.so
    # Misc
    libdbus-1.so.3 libexpat.so.1 libxml2.so.2
    libbz2.so.1 libzstd.so.1 libgomp.so.1
    libattr.so.1 libcap.so.2 libltdl.so.7
    libuuid.so.1 libpci.so.3
    libncurses.so.6 libtinfo.so.6
    libwayland-client.so.0
    # Previously "missing" — try to find on build host
    libXaw.so.7 libXft.so.2 libXp.so.6
    libatk-1.0.so.0 libcups.so.2
    libgdk-x11-2.0.so.0 libgdk_pixbuf-2.0.so.0 libgtk-x11-2.0.so.0
    libpango-1.0.so.0 libpangocairo-1.0.so.0 libpangoft2-1.0.so.0
    libwayland-cursor.so.0 libwayland-egl.so.1
    libxcb-cursor.so.0 libxcb-icccm.so.4 libxcb-image.so.0
    libxcb-keysyms.so.1 libxcb-render-util.so.0
    libxkbcommon-x11.so.0 libxkbfile.so.1
    libva.so.2 libva-drm.so.2 libva-x11.so.2 libvdpau.so.1
    libpulse.so.0 libspeechd.so.2
    librsvg-2.so.2 libpoppler-glib.so.4
    libgd.so.2 libgs.so.8 libgts-0.7.so.5 libmng.so.2 libpng12.so.0
    libpq.so.5
    # Transitive deps of bundled libs
    libGLdispatch.so.0 libXau.so.6
    libbrotlidec.so.1 libcom_err.so.2 libffi.so.8
    libharfbuzz.so.0 libidn2.so.0 libjbig.so.2.1
    libk5crypto.so.3 libkeyutils.so.1 libkrb5.so.3 libkrb5support.so.0
    liblzma.so.5 libmount.so.1 libnghttp2.so.14
    libpcre2-8.so.0 libpixman-1.so.0 libpsl.so.5
    libselinux.so.1 libsystemd.so.0 libwebp.so.7
    # Second-level transitive deps
    libblkid.so.1 libbrotlicommon.so.1 libgraphite2.so.3 libunistring.so.2
    libgstallocators-1.0.so.0 libgstapp-1.0.so.0 libgstaudio-1.0.so.0
    libgstbase-1.0.so.0 libgstgl-1.0.so.0 libgstpbutils-1.0.so.0
    libgstreamer-1.0.so.0 libgstvideo-1.0.so.0
)

BUNDLED=0
SKIPPED=0
for lib in "${SYSTEM_LIBS[@]}"; do
    # Don't overwrite libs already provided by Maya
    if [[ -f "$MAYA_LIB/$lib" || -L "$MAYA_LIB/$lib" ]]; then
        continue
    fi
    SYS_PATH=$(ldconfig -p 2>/dev/null | grep -oP "=> \K.*/${lib}$" | head -1 || true)
    if [[ -z "$SYS_PATH" ]]; then
        for d in /usr/lib64 /lib64 /usr/lib /lib; do
            if [[ -f "$d/$lib" || -L "$d/$lib" ]]; then
                SYS_PATH="$d/$lib"
                break
            fi
        done
    fi
    if [[ -n "$SYS_PATH" ]]; then
        cp -L "$(readlink -f "$SYS_PATH")" "$MAYA_LIB/$lib"
        BUNDLED=$((BUNDLED + 1))
    else
        echo "  SKIP (not on build host): $lib"
        SKIPPED=$((SKIPPED + 1))
    fi
done
echo "Bundled $BUNDLED system libs, skipped $SKIPPED"

# 2b. Copy pre-downloaded RPM-extracted libs (for libs not available on build host)
EXTRA_LIBS_DIR="$SRC_DIR/extra-libs"
if [[ -d "$EXTRA_LIBS_DIR" ]]; then
    echo "Copying pre-downloaded extra libs from $EXTRA_LIBS_DIR ..."
    EXTRA_COPIED=0
    for f in "$EXTRA_LIBS_DIR"/*.so*; do
        BASENAME=$(basename "$f")
        if [[ ! -f "$MAYA_LIB/$BASENAME" && ! -L "$MAYA_LIB/$BASENAME" ]]; then
            cp -a "$f" "$MAYA_LIB/$BASENAME"
            EXTRA_COPIED=$((EXTRA_COPIED + 1))
        fi
    done
    echo "Copied $EXTRA_COPIED extra libs from RPM downloads"
fi

# 3. Symlink internal libs that exist in the package but aren't found due to deep rpath
echo "Creating symlinks for internal libs with deep rpaths..."
# Graphviz libs live in lib/graphviz/ but binaries in bin/graphviz/bin/ need them in lib/
for gvlib in libcdt.so.5 libcgraph.so.6 libgvc.so.6 libgvpr.so.2 libpathplan.so.4 libxdot.so.4; do
    SRC=$(find "$MAYA_ROOT/lib/graphviz" -name "$gvlib" \( -type f -o -type l \) 2>/dev/null | head -1)
    if [[ -n "$SRC" && ! -f "$MAYA_LIB/$gvlib" ]]; then
        cp -L "$SRC" "$MAYA_LIB/$gvlib"
    fi
done

# PySide6/shiboken6 libs live in site-packages but xgen plugins need them in lib/
for pylib in libpyside6.abi3.so.6.5 libshiboken6.abi3.so.6.5; do
    SRC=$(find "$MAYA_ROOT/lib/python3.11" -name "$pylib" -type f 2>/dev/null | head -1)
    if [[ -n "$SRC" && ! -f "$MAYA_LIB/$pylib" ]]; then
        ln -sf "$SRC" "$MAYA_LIB/$pylib"
    fi
done

# numpy internal libs
for nplib in libgfortran-040039e1.so.5.0.0 libquadmath-96973f99.so.0.0.0; do
    SRC=$(find "$MAYA_ROOT/lib/python3.11" -name "$nplib" -type f 2>/dev/null | head -1)
    if [[ -n "$SRC" && ! -f "$MAYA_LIB/$nplib" ]]; then
        ln -sf "$SRC" "$MAYA_LIB/$nplib"
    fi
done

# 3. Create the `maya` symlink in Maya's own bin dir
# The RPM normally creates this, but our extract missed it.
# Maya's Render script (and render.bin internally) looks for $MAYA_LOCATION/bin/maya
# to start the Maya process.
if [[ ! -e "$MAYA_BIN/maya" ]]; then
    echo "Creating maya -> maya2026 symlink in $MAYA_BIN"
    ln -sf maya2026 "$MAYA_BIN/maya"
fi

# 4. Create wrapper scripts
echo "Creating wrapper scripts..."
mkdir -p "$PREFIX/bin"

for cmd_name in maya mayapy maya-render; do
    case "$cmd_name" in
        maya)       BINARY="maya.bin" ;;
        mayapy)     BINARY="mayapy.bin" ;;
        maya-render) BINARY="render.bin" ;;
    esac
    cat > "$PREFIX/bin/$cmd_name" << WRAPPER
#!/usr/bin/env bash
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
MAYA_ROOT="\$(dirname "\$SCRIPT_DIR")/opt/autodesk/maya2026"
export MAYA_LOCATION="\$MAYA_ROOT"
export LD_LIBRARY_PATH="\$MAYA_ROOT/lib:\$MAYA_ROOT/bin:\${LD_LIBRARY_PATH:-}"
export PATH="\$MAYA_ROOT/bin:\$PATH"
exec "\$MAYA_ROOT/bin/$BINARY" "\$@"
WRAPPER
    chmod +x "$PREFIX/bin/$cmd_name"
done

echo ""
echo "=== Build complete ==="
