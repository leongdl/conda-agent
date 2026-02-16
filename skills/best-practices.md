# Best Practices

## rattler-build

### Use Lowest Compression When Iterating

When actively developing and iterating on builds, use the lowest compression level to speed up packaging:

```bash
# Fastest iteration: lowest compression
rattler-build build --recipe recipe.yaml --package-format conda:-7

# tar-bz2 with minimum compression
rattler-build build --recipe recipe.yaml --package-format tar-bz2:1
```

Only use higher compression (or defaults) for final/release builds:

```bash
# Release build: max compression
rattler-build build --recipe recipe.yaml --package-format conda:22
```

### Skip Tests During Early Iteration

When debugging the build script itself, skip tests to tighten the feedback loop:

```bash
rattler-build build --recipe recipe.yaml --test skip --package-format conda:-7
```

Re-enable tests once the build is stable.

### Use `--render-only` to Validate Recipes

Before running a full build, validate your recipe renders correctly:

```bash
rattler-build build --recipe recipe.yaml --render-only
```

### Use `debug-shell` for Build Failures

Don't guess — drop into the build environment interactively:

```bash
rattler-build debug --recipe recipe.yaml
rattler-build debug-shell
```

### Use `--keep-build` When Debugging

Preserve intermediate artifacts so you can inspect what went wrong:

```bash
rattler-build build --recipe recipe.yaml --keep-build
```

### Pin Variants Explicitly During Dev

Override variants on the CLI to avoid building the full matrix while iterating:

```bash
rattler-build build --recipe recipe.yaml --variant python=3.12
```

### Use `--skip-existing` in CI

Avoid rebuilding packages that are already published:

```bash
rattler-build build --recipe-dir recipes/ --skip-existing all --continue-on-failure
```


## Scripts Handling

Keep build scripts in separate files rather than inlining them in `recipe.yaml`. This improves readability and avoids YAML escaping headaches.

```yaml
# Good — source a separate script
build:
  script:
    - if: unix
      then:
        - bash ${RECIPE_DIR}/build.sh
    - if: win
      then:
        - call %RECIPE_DIR%\build.bat
```

```yaml
# Avoid — inline multi-line scripts in the recipe
build:
  script:
    - if: unix
      then: |
        ./configure --prefix=$PREFIX
        make -j$CPU_COUNT
        make install
```

Benefits:
- Easier to read and review the recipe at a glance
- No YAML quoting/escaping issues with special characters
- Scripts get proper syntax highlighting in editors
- Simpler diffs when build logic changes
