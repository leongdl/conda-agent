# Repackaging Applications as Conda Packages

> Steps to debug and create a self-sufficient conda package from a pre-built application (RPM, tarball, etc.)

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
1. Core system libs (glibc, ld-linux, libm, libdl, libpthread, librt, libgcc_s, libstdc++) — never bundle
2. System libs to bundle (X11, GL, glib, crypto, etc.) — copy into the app's `lib/` dir
3. Optional plugin deps (gstreamer, gtk2, cups, pulseaudio, wayland extras) — skip if not on build host

Check `history/dnf.md` or `dnf history` — if a lib was previously installed via dnf, it should be bundled.

## Step 4: Create the recipe

Per `skills/best-practices.md`:
- Keep build scripts in separate files, reference from recipe
- Use lowest compression (`--package-format conda:-7`) while iterating
- Use `--test skip` during early iterations to speed up feedback

```yaml
source:
  - path: ../app-dir

build:
  script:
    - bash ${RECIPE_DIR}/../scripts/build_app.sh

tests:
  - script:
      - bash ./check_rpath.sh ${PREFIX}
    files:
      recipe:
        - check_rpath.sh
  - package_contents:
      bin:
        - app-wrapper
```

## Step 5: Build script pattern

The build script should:
1. Extract the RPM/tarball into `$PREFIX`
2. Relocate files to a clean prefix layout (e.g. `$PREFIX/opt/vendor/app`)
3. Bundle system libs directly into the app's `lib/` dir (not a subdirectory) so existing rpaths resolve
4. Skip libs already provided by the app (`-f "$LIB_DIR/$lib"` check)
5. Resolve symlinks when copying (`cp -L`)
6. Symlink internal libs that exist in deep subdirs (e.g. PySide6, graphviz) into `lib/`
7. Create wrapper scripts in `$PREFIX/bin/` that set `LD_LIBRARY_PATH` and `exec` the real binary

## Step 6: Iterate on rpath check

Run `scripts/check_rpath.sh $PREFIX` as a test. It will report:
- CRITICAL: libs that must be bundled (fail the build)
- Optional: plugin deps not on the build host (warning only)

IMPORTANT: Always test inside the actual conda environment, not the build host. The conda env is isolated and won't have system libs. Use:
```bash
conda create -n test-env ./output/linux-64/mypackage.conda
conda run -n test-env ldd $CONDA_PREFIX/opt/app/bin/app.bin
conda run -n test-env bash -c 'LD_LIBRARY_PATH=$CONDA_PREFIX/opt/app/lib ldd $CONDA_PREFIX/opt/app/bin/app.bin'
```
Never assume the build host environment matches the conda activate environment.

## Step 6b: Use dnf download for missing libs (don't install)

When libs are missing and not on the build host, download them without installing:
```bash
dnf download --destdir=/tmp/rpms <package-name>
rpm2cpio /tmp/rpms/<package>.rpm | cpio -idm -D /tmp/rpm-extract
# Then copy the needed .so files into the app's lib/ dir
```

Use `dnf provides '*/libfoo.so.1'` to find which RPM provides a missing lib.

## Step 7: Verify and ship

Once `check_rpath.sh` passes with 0 critical:
```bash
rattler-build build --recipe recipe.yaml --package-format conda:22  # release compression
```

## Key files

| File | Purpose |
|------|---------|
| `scripts/find_missing_deps.sh` | Scan app for all missing shared lib deps |
| `scripts/check_rpath.sh` | Verify all libs resolvable within the package |
| `scripts/build_<app>.sh` | Extract, bundle deps, create wrappers |
| `recipe/recipe.yaml` | rattler-build recipe |
