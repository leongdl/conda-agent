# Comparison: Our Build vs Deadline Cloud Sample

Moved from journal.md iterations 9-10.

## Patching & Bundling Analysis (was Iteration 9)

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

### Patching by rattler-build (patchelf 0.17.2)

859 unique ELF binaries were relinked during the packaging phase:
- 803 patched via patchelf (rpath prepend)
- 59 had absolute build-farm rpaths stripped (no patchelf, rpath removal only)
- 547 got "new value is longer than old value" warnings (non-fatal; rpath section too short to extend)

#### Rpath diff (representative samples)

| Binary | Original (RPM) | Patched (conda) |
|--------|---------------|-----------------|
| `maya.bin` | `$ORIGIN/../lib` | `$ORIGIN/../../../../lib:$ORIGIN/../lib` |
| `libMaya.so` | `$ORIGIN:$ORIGIN/../lib` | `$ORIGIN/../../../../lib:$ORIGIN:$ORIGIN/../lib` |
| `fbxmaya.so` | `/local/.../fbxsdk/.../release:/home/.../runTime/lib` | `$ORIGIN/../../../../../../lib` |
| `QtCore.abi3.so` | `$ORIGIN/:/home/.../qt_6.5.3/lib` | `$ORIGIN/../../../../../../../lib:$ORIGIN/` |

## Comparison with Deadline Cloud Sample (was Iteration 10)

### Patching strategy

| Aspect | Sample | Ours |
|--------|--------|------|
| Who patches | Manual `patchelf` in build.sh | rattler-build automatic relinking |
| rattler-build relinking | Disabled | Enabled (default) |
| Scope | Targeted: specific globs | All 859 ELF binaries |
| Warnings | None | 547 "new value is longer" (non-fatal) |

### Bundled libraries

Our 72 dnf packages are a strict superset of the sample's 14.

In both (7): `alsa-lib fontconfig freetype graphite2 harfbuzz libbrotli pciutils-libs`

Only in sample (7): `libva libvdpau libxkbcommon-x11 libxkbfile xcb-util-cursor xcb-util-keysyms xcb-util-wm`

Only in ours (65): everything else (X11, GL, glib, crypto, etc.)

### Features in sample that we lack

1. Licensing setup (ProductInformation.pit + AdlmThinClientCustomEnv.xml)
2. Conda activation/deactivation scripts instead of wrapper scripts
3. No LD_LIBRARY_PATH (symlinks + rpath only)
4. `dnf download --resolve` for missing libs
5. Functional tests (mayapy, maya -batch)
6. patchelf as build requirement
7. Removes Examples directory
8. `--resolve` flag pulls transitive deps automatically

### Features in ours that sample lacks

1. Aggressive lib bundling (65 more packages)
2. rpath verification test (check_rpath.sh)
3. Dependency scanner (find_missing_deps.sh)
4. Internal lib symlinks (graphviz, PySide6, numpy)
5. package_contents test
