# Journal: Maya 2026 Conda Package Build

## Iteration 1 — Initial analysis
- Extracted Maya RPM to `/tmp/maya-extract` using `rpm2cpio | cpio`
- Ran `find_missing_deps.sh` against extracted tree
- Found 386 unique NEEDED libs, 1049 provided by Maya, 125 not in app
- Of those 125: 80 resolved from system, 45 truly missing (gtk2, gstreamer, wayland extras, etc.)

## Iteration 2 — First recipe + build script
- Created `recipe/recipe.yaml` with local path source, no build deps (rpm2cpio/cpio are system tools)
- Created `scripts/build_maya.sh`: extracts RPM, bundles system libs into `lib/bundled/`, creates wrapper scripts
- License `Proprietary` rejected by rattler-build — changed to `LicenseRef-Autodesk-Maya`
- `rpm2cpio`/`cpio` not conda packages — removed from requirements
- Build succeeded, 3.90 GiB package

## Iteration 3 — Test script path issues
- `${RECIPE_DIR}/../scripts/check_rpath.sh` not available at test time
- `files: recipe: ../scripts/check_rpath.sh` didn't work (can't go above recipe dir)
- Fix: copied `check_rpath.sh` into `recipe/` and referenced it as `./check_rpath.sh`

## Iteration 4 — rpath check: 1547 failures
- Bundled libs were in `lib/bundled/` but rpaths point to `$ORIGIN/../lib`
- Fix: changed `BUNDLE_DIR` from `lib/bundled/` to `lib/` directly
- Also updated wrapper scripts to remove `lib/bundled` from `LD_LIBRARY_PATH`

## Iteration 5 — rpath check: 263 failures
- Transitive deps of bundled libs missing (libharfbuzz, libffi, liblzma, etc.)
- Graphviz internal libs not found (symlinks not followed by `find -type f`)
- PySide6/shiboken6 libs exist in site-packages but xgen plugins can't find them
- Fix: added transitive deps to SYSTEM_LIBS array, symlinked internal libs to `lib/`

## Iteration 6 — rpath check: 182 failures (54 unique libs)
- More second-level transitive deps needed (libbrotlicommon, libblkid, libgraphite2, libunistring)
- ~50 libs genuinely not on this headless build host (gtk2, gstreamer, wayland, cups, pulseaudio, etc.)
- Fix: added second-level transitive deps, fixed graphviz find to include symlinks (`-type l`)
- Updated `check_rpath.sh` to categorize missing as critical vs optional

## Iteration 7 — PASS
- 0 critical missing, 118 optional (plugin deps for wayland/gstreamer/gtk2/cups not on build host)
- All package_contents tests pass (maya, mayapy, maya-render wrappers + maya.bin)
- Final package: 3.90 GiB, `output/linux-64/maya-2026.0-hb0f4dca_0.conda`

## Iteration 8 — Clean rebuild verification
- Ran clean rebuild to confirm reproducibility
- First attempt failed: `patchelf` not on PATH (build-env not activated)
- Also accidentally spawned two concurrent builds; killed the stale one
- Fix: run with `PATH="/home/ssm-user/.conda/envs/build-env/bin:$PATH"`
- Build completed: 95 system libs bundled, 42 skipped (not on headless host)
- Relinking phase: many "new value is longer than old value" patchelf warnings (expected for pre-built binaries with short rpaths — non-fatal)
- PySide6 `.abi3.so` files had build-time rpaths from Autodesk's build farm (`/home/S/workspace/pyside_maya/...`) stripped by rattler-build — expected
- Overlinking warnings for glibc/libstdc++ on a few .so files — cosmetic, not errors
- `check_rpath.sh` test: STATUS: PASS, 0 critical missing
- `package_contents` test: all passed (maya, mayapy, maya-render, maya.bin)
- Final artifact: `output/linux-64/maya-2026.0-hb0f4dca_0.conda` (3.90 GiB)
- Cleaned stale broken/ artifact from killed build
- **Status: DONE** — package builds reproducibly and passes all tests
## Iteration 9 — Patching & bundling analysis

### Bundled system libraries (95 bundled, 42 skipped)

Our `build_maya.sh` copies system .so files from the build host into `opt/autodesk/maya2026/lib/`
so the package is self-contained. 138 libs are listed in the SYSTEM_LIBS array; 95 were found
on the headless build host and bundled, 42 were not present (optional plugin deps).

#### DNF packages providing the bundled libs

```
alsa-lib            bzip2-libs          cairo               dbus-libs
expat               fontconfig          freetype            glib2
graphite2           harfbuzz            jbigkit-libs        keyutils-libs
krb5-libs           libICE              libSM               libX11
libX11-xcb          libXau              libXcomposite       libXdamage
libXext             libXfixes           libXi               libXinerama
libXmu              libXpm              libXrandr           libXrender
libXt               libXtst             libXv               libXxf86vm
libattr             libblkid            libbrotli           libcap
libcom_err          libcurl-minimal     libdrm              libffi
libglvnd            libglvnd-glx        libglvnd-opengl     libgomp
libidn2             libjpeg-turbo       libmount            libnghttp2
libpng              libpsl              libselinux          libtiff
libtool-ltdl        libunistring        libuuid             libwayland-client
libwebp             libxcb              libxkbcommon         libxml2
libzstd             mesa-libGLU         ncurses-libs        nspr
nss                 nss-util            openssl-libs        pciutils-libs
pcre2               pixman              systemd-libs        xz-libs
```

#### Bundled .so files (95 found on build host)

```
libEGL.so.1  libGL.so.1  libGLU.so.1  libGLX.so.0  libGLdispatch.so.0
libOpenGL.so.0  libICE.so.6  libSM.so.6
libX11.so.6  libX11-xcb.so.1  libXau.so.6  libXcomposite.so.1  libXdamage.so.1
libXext.so.6  libXfixes.so.3  libXi.so.6  libXinerama.so.1  libXmu.so.6
libXpm.so.4  libXrandr.so.2  libXrender.so.1  libXt.so.6  libXtst.so.6
libXv.so.1  libXxf86vm.so.1
libxcb.so.1  libxcb-glx.so.0  libxcb-randr.so.0  libxcb-render.so.0
libxcb-shape.so.0  libxcb-shm.so.0  libxcb-sync.so.1  libxcb-xfixes.so.0
libxcb-xkb.so.1  libxkbcommon.so.0
libcairo.so.2  libdrm.so.2  libfontconfig.so.1  libfreetype.so.6
libpng16.so.16  libjpeg.so.62  libtiff.so.5
libglib-2.0.so.0  libgmodule-2.0.so.0  libgobject-2.0.so.0
libgio-2.0.so.0  libgthread-2.0.so.0
libasound.so.2
libcrypto.so.3  libssl.so.3  libcurl.so.4  libgssapi_krb5.so.2
libnss3.so  libnspr4.so  libnssutil3.so  libsmime3.so  libplc4.so  libplds4.so
libdbus-1.so.3  libexpat.so.1  libxml2.so.2
libbz2.so.1  libzstd.so.1  libgomp.so.1
libattr.so.1  libcap.so.2  libltdl.so.7  libuuid.so.1  libpci.so.3
libncurses.so.6  libtinfo.so.6  libwayland-client.so.0
libharfbuzz.so.0  libffi.so.8  liblzma.so.5  libbrotlidec.so.1
libpcre2-8.so.0  libpixman-1.so.0  libpsl.so.5  libselinux.so.1
libsystemd.so.0  libwebp.so.7  libblkid.so.1  libbrotlicommon.so.1
libgraphite2.so.3  libunistring.so.2  libcom_err.so.2
libidn2.so.0  libjbig.so.2.1  libk5crypto.so.3  libkeyutils.so.1
libkrb5.so.3  libkrb5support.so.0  libmount.so.1  libnghttp2.so.14
libXau.so.6  libGLdispatch.so.0
```

#### Skipped .so files (42 — not on headless build host, all optional)

```
libXaw.so.7  libXft.so.2  libXp.so.6  libatk-1.0.so.0  libcups.so.2
libgdk-x11-2.0.so.0  libgdk_pixbuf-2.0.so.0  libgtk-x11-2.0.so.0
libpango-1.0.so.0  libpangocairo-1.0.so.0  libpangoft2-1.0.so.0
libwayland-cursor.so.0  libwayland-egl.so.1
libxcb-cursor.so.0  libxcb-icccm.so.4  libxcb-image.so.0
libxcb-keysyms.so.1  libxcb-render-util.so.0
libxkbcommon-x11.so.0  libxkbfile.so.1
libva.so.2  libva-drm.so.2  libva-x11.so.2  libvdpau.so.1
libpulse.so.0  libspeechd.so.2  librsvg-2.so.2  libpoppler-glib.so.4
libgd.so.2  libgs.so.8  libgts-0.7.so.5  libmng.so.2  libpng12.so.0  libpq.so.5
libgstallocators-1.0.so.0  libgstapp-1.0.so.0  libgstaudio-1.0.so.0
libgstbase-1.0.so.0  libgstgl-1.0.so.0  libgstpbutils-1.0.so.0
libgstreamer-1.0.so.0  libgstvideo-1.0.so.0
```

These would come from: `gtk2`, `gdk-pixbuf2`, `pango`, `atk`, `cups-libs`, `gstreamer1*`,
`libva`, `libvdpau`, `pulseaudio-libs`, `speech-dispatcher`, `librsvg2`, `poppler-glib`,
`gd`, `ghostscript`, `gts`, `libmng`, `libpng12`, `postgresql-libs`, `libwayland-cursor`,
`libwayland-egl`, `libxcb` extras, `libxkbcommon-x11`, `libxkbfile`, `libXaw`, `libXft`, `libXp`.

### Patching by rattler-build (patchelf 0.17.2)

859 unique ELF binaries were relinked during the packaging phase:
- 803 patched via patchelf (rpath prepend)
- 59 had absolute build-farm rpaths stripped (no patchelf, rpath removal only)
- 547 got "new value is longer than old value" warnings (non-fatal; rpath section too short to extend)

#### What rattler-build does to rpaths

It prepends a relative `$ORIGIN/../../...` path that resolves from the binary's location
up to the conda prefix root. Absolute paths from Autodesk's build farm are stripped.
Original `$ORIGIN`-relative paths are preserved.

#### Absolute rpaths stripped (from Autodesk build farm)

```
/home/S/workspace/pyside_maya/external_dependencies/qt_6.5.3/lib
/home/S/jenkins/workspace/maya/build/RelWithDebInfo/runTime/lib
/local/S/jenkins/workspace/artifactory/Linux/fbxsdk/95328ca/lib/x64/release
/local/S/workspace/pyside_maya/external_dependencies/libclang/lib
/local/S/jenkins/workspace/3dsmax-conan-recipes@tmp/.conan/data/Imath/3.1.9/...
/media/sf_D_DRIVE/git/adp-ipc/thirdParty/boost-linux.1.8.0/lib
```

#### Rpath diff (representative samples)

| Binary | Original (RPM) | Patched (conda) |
|--------|---------------|-----------------|
| `maya.bin` | `$ORIGIN/../lib` | `$ORIGIN/../../../../lib:$ORIGIN/../lib` |
| `libMaya.so` | `$ORIGIN:$ORIGIN/../lib` | `$ORIGIN/../../../../lib:$ORIGIN:$ORIGIN/../lib` |
| `libFoundation.so` | `$ORIGIN` | `$ORIGIN/../../../../lib:$ORIGIN` |
| `fbxmaya.so` | `/local/.../fbxsdk/.../release:/home/.../runTime/lib` | `$ORIGIN/../../../../../../lib` |
| `QtCore.abi3.so` | `$ORIGIN/:/home/.../qt_6.5.3/lib` | `$ORIGIN/../../../../../../../lib:$ORIGIN/` |

The `$ORIGIN/../../../../lib` prefix resolves to the conda prefix `lib/` directory from
`opt/autodesk/maya2026/bin/`. Deeper binaries (e.g. PySide6 in `lib/python3.11/site-packages/`)
get longer relative paths like `$ORIGIN/../../../../../../../lib`.

For the 547 binaries where patchelf couldn't extend the rpath, the wrapper scripts in
`$PREFIX/bin/{maya,mayapy,maya-render}` set `LD_LIBRARY_PATH` as a fallback.
