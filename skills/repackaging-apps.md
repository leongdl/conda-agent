# Repackaging Applications as Conda Packages

> Lessons learned from packaging Maya 2026 (4 GiB, ~860 ELF binaries, ~1000 bundled .so files).
> All steps below are from our own iterations documented in journal.md.

## Step 1: Extract without installing

```bash
mkdir -p /tmp/app-extract
rpm2cpio app.rpm | cpio -idm -D /tmp/app-extract
# or: tar xzf app.tgz -C /tmp/app-extract
```

## Step 2: Scan for missing dependencies

Run `scripts/find_missing_deps.sh <app_root>` to get:
- `all_needed.txt` — every NEEDED shared lib across all ELF binaries
- `all_provided.txt` — every .so the app ships
- `system_deps.txt` — libs resolved from the build host (candidates to bundle)
- `missing_deps.txt` — libs not found anywhere

## Step 3: Categorize dependencies

Split into three buckets:
1. **Never bundle** — core system libs (glibc, ld-linux, libm, libdl, libpthread, librt, libgcc_s, libstdc++)
2. **Bundle** — system libs the app needs (X11, GL, glib, crypto, etc.) — copy into the app's `lib/` dir
3. **Optional** — plugin deps (gstreamer, gtk2, cups, pulseaudio, wayland extras) — skip if not on build host; categorize in check_rpath.sh as non-critical

Use `dnf provides '*/libfoo.so.1'` to find which RPM provides a missing lib.
Check `history/dnf.md` or `dnf history` to see what's already on the build host.

## Step 4: Create the recipe

```yaml
context:
  version: "2026.0"

package:
  name: app-name
  version: ${{ version }}

source:
  - path: ../app-dir

build:
  number: 0
  script:
    - if: unix
      then:
        - bash ${RECIPE_DIR}/../scripts/build_app.sh

requirements: {}

tests:
  - script:
      - bash ./check_rpath.sh ${PREFIX}
    files:
      recipe:
        - check_rpath.sh
  - package_contents:
      bin:
        - app-wrapper
      files:
        - opt/vendor/app/bin/app.bin

about:
  summary: App repackaged as a conda package
  license: LicenseRef-Vendor-App
```

Notes from iterations:
- `Proprietary` is rejected by rattler-build as a license — use `LicenseRef-*` format (iteration 2)
- `rpm2cpio`/`cpio` are system tools, not conda packages — don't list them in requirements (iteration 2)
- Test files can't reference paths above the recipe dir (`../scripts/` won't work) — copy test scripts into `recipe/` (iteration 3)

## Step 5: Build script pattern

The build script should:

1. **Extract the RPM** into `$PREFIX`
2. **Relocate files** to a clean prefix layout (e.g. `$PREFIX/opt/vendor/app`)
3. **Bundle system libs directly into `lib/`** — not a subdirectory like `lib/bundled/`. Existing rpaths point to `$ORIGIN/../lib`, so libs must be in `lib/` for them to resolve (iteration 4)
4. **Skip libs already provided by the app** — check with `-f "$LIB_DIR/$lib"` before copying
5. **Resolve symlinks when copying** — use `cp -L` to follow symlinks
6. **Include transitive deps** — first-level bundled libs have their own deps (libharfbuzz needs libgraphite2, libcurl needs libidn2, etc.). Miss these and you get hundreds of rpath failures (iterations 5-6)
7. **Symlink internal libs** from deep subdirs into `lib/`:
   - Graphviz libs in `lib/graphviz/` needed by `bin/graphviz/bin/`
   - PySide6/shiboken6 in `site-packages/` needed by xgen plugins
   - numpy internal libs (libgfortran, libquadmath)
   - Use `-type l` in find to catch symlinks too (iteration 6)
8. **Create wrapper scripts** in `$PREFIX/bin/` that set `LD_LIBRARY_PATH` and `exec` the real binary

```bash
cat > "$PREFIX/bin/app" << 'WRAPPER'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(dirname "$SCRIPT_DIR")/opt/vendor/app"
export APP_LOCATION="$APP_ROOT"
export LD_LIBRARY_PATH="$APP_ROOT/lib:$APP_ROOT/bin:${LD_LIBRARY_PATH:-}"
export PATH="$APP_ROOT/bin:$PATH"
exec "$APP_ROOT/bin/app.bin" "$@"
WRAPPER
chmod +x "$PREFIX/bin/app"
```

## Step 6: Iterate on rpath check

Run `scripts/check_rpath.sh $PREFIX` as a test. It categorizes missing libs:
- **CRITICAL** — libs that must be bundled (fails the build)
- **Optional** — plugin deps not on the build host (warning only, e.g. wayland, gstreamer, gtk2, cups)

The check_rpath.sh script uses regex patterns to classify:
- `CORE_SYSTEM_RE` — glibc family, always expected from OS
- `OPTIONAL_RE` — known plugin deps that aren't critical for core app startup

Iteration history:
- Iteration 4: 1547 failures → fixed by moving libs from `lib/bundled/` to `lib/`
- Iteration 5: 263 failures → added transitive deps (libharfbuzz, libffi, liblzma, etc.)
- Iteration 6: 182 failures → added second-level transitive deps, fixed find to include symlinks
- Iteration 7: 0 critical, 118 optional → PASS

## Step 7: rattler-build relinking behavior

rattler-build automatically patches ELF binaries during packaging (patchelf 0.17.2):
- Prepends `$ORIGIN/../../../../lib` (relative path to conda prefix) to existing rpaths
- Strips absolute paths from the vendor's build farm
- 859 binaries relinked in our Maya build
- 547 got "new value is longer than old value" warnings — non-fatal, patchelf can't extend the rpath section on binaries with short original rpaths
- These binaries still work because wrapper scripts set `LD_LIBRARY_PATH` as fallback

Absolute rpaths stripped from Autodesk's build environment:
```
/home/S/workspace/pyside_maya/external_dependencies/qt_6.5.3/lib
/home/S/jenkins/workspace/maya/build/RelWithDebInfo/runTime/lib
/local/S/jenkins/workspace/artifactory/Linux/fbxsdk/95328ca/lib/x64/release
/local/S/workspace/pyside_maya/external_dependencies/libclang/lib
/media/sf_D_DRIVE/git/adp-ipc/thirdParty/boost-linux.1.8.0/lib
```

Example rpath diff:

| Binary | Original (RPM) | Patched (conda) |
|--------|---------------|-----------------|
| `maya.bin` | `$ORIGIN/../lib` | `$ORIGIN/../../../../lib:$ORIGIN/../lib` |
| `libMaya.so` | `$ORIGIN:$ORIGIN/../lib` | `$ORIGIN/../../../../lib:$ORIGIN:$ORIGIN/../lib` |
| `fbxmaya.so` | `/local/.../fbxsdk/.../release:/home/.../runTime/lib` | `$ORIGIN/../../../../../../lib` |
| `QtCore.abi3.so` | `$ORIGIN/:/home/.../qt_6.5.3/lib` | `$ORIGIN/../../../../../../../lib:$ORIGIN/` |

## Step 8: Use `dnf download` for libs not on the build host

When libs are missing and not on the build host, download them without installing:

```bash
dnf download --destdir=/tmp/rpms <package-name>
rpm2cpio /tmp/rpms/<package>.rpm | cpio -idm -D /tmp/rpm-extract
# Then copy the needed .so files into the app's lib/ dir
```

Use `dnf provides '*/libfoo.so.1'` to find which RPM provides a missing lib.

## Step 9: Verify and ship

Once `check_rpath.sh` passes with 0 critical:

```bash
# Iterate with low compression
rattler-build build --recipe recipe.yaml --package-format conda:-7

# Skip tests during early iterations
rattler-build build --recipe recipe.yaml --test skip --package-format conda:-7

# Release build
rattler-build build --recipe recipe.yaml --package-format conda:22
```

## Key files

| File | Purpose |
|------|---------|
| `scripts/find_missing_deps.sh` | Scan app for all missing shared lib deps |
| `scripts/check_rpath.sh` | Verify all libs resolvable within the package |
| `scripts/build_<app>.sh` | Extract, bundle deps, create wrappers |
| `recipe/recipe.yaml` | rattler-build recipe |

## Checklist

- [ ] Extract RPM/tarball and scan with `find_missing_deps.sh`
- [ ] Bundle system libs directly into `lib/` (not a subdirectory)
- [ ] Include transitive deps of bundled libs (check with `ldd`)
- [ ] Symlink internal libs from deep subdirs (graphviz, PySide6, numpy) into `lib/`
- [ ] Use `find -type f -o -type l` to catch symlinks when scanning
- [ ] Create wrapper scripts that set `LD_LIBRARY_PATH` and `exec` the binary
- [ ] Copy test scripts into `recipe/` dir (can't reference `../scripts/` at test time)
- [ ] Use `LicenseRef-*` format for proprietary licenses
- [ ] Categorize missing libs as critical vs optional in `check_rpath.sh`
- [ ] Use `dnf download` for libs not on the build host
- [ ] Use lowest compression (`conda:-7`) while iterating, release with `conda:22`
- [ ] Ensure `patchelf` is on PATH (activate build-env or add to PATH)
