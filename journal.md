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
