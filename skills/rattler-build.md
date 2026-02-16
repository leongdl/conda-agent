# rattler-build

> **Disclaimer**: This skill was written on February 15, 2026. If it is more than 1 month old, please update it by re-reading the official docs at https://prefix-dev.github.io/rattler-build/latest/

## What is rattler-build?

A fast, Rust-based conda package builder. It reads a `recipe.yaml` file and produces standard `.conda` packages installable by pixi, mamba, or conda. No Python or conda-build dependency required.

## Installation

```bash
pixi global install rattler-build    # recommended
conda install rattler-build -c conda-forge
brew install rattler-build           # macOS
```

## Recipe Format (`recipe.yaml`)

Not `meta.yaml` (that's conda-build). Key differences from conda-build:
- Pure YAML, no Jinja2 `{% set %}` or comment-based selectors
- Jinja interpolation uses `${{ var }}` syntax (dollar sign prefix)
- Variables defined in a `context:` section
- Selectors use YAML dict style: `if: osx` / `then:` instead of `# [osx]`

### Recipe Sections

| Section | Purpose |
|---------|---------|
| `context` | Define variables for Jinja interpolation |
| `package` | Package name and version |
| `source` | Source URL, git repo, or local path + sha256 + patches |
| `build` | Build number, script, noarch setting |
| `requirements` | `build`, `host`, `run`, `run_constraints` dependencies |
| `tests` | Test definitions (see Testing below) |
| `outputs` | Multiple output packages from one recipe |
| `about` | Homepage, license, summary, description |

### Minimal Example

```yaml
context:
  version: "1.0.0"

package:
  name: my-package
  version: ${{ version }}

build:
  number: 0
  script:
    - python -m pip install .

requirements:
  host:
    - python
    - pip
  run:
    - python

tests:
  - python:
      imports:
        - my_package
```

### Conditional Selectors

```yaml
build:
  script:
    - if: unix
      then:
        - ./configure --prefix=$PREFIX
        - make -j$CPU_COUNT
    - if: win
      then:
        - cmake -G "Ninja" ...
        - ninja install

requirements:
  build:
    - ${{ compiler('c') }}
    - if: win
      then:
        - cmake
        - ninja
    - if: unix
      then:
        - make
```

### Noarch Packages

```yaml
build:
  noarch: python
  script:
    - python -m pip install . -vv
```

## CLI Commands

### Build
```bash
rattler-build build --recipe recipe.yaml
rattler-build build --recipe recipe.yaml -c conda-forge -c bioconda
rattler-build build --recipe-dir myrecipes/   # build all recipes in dir
rattler-build build --render-only             # dry-run, just render
rattler-build build --variant python=3.12     # override variant
rattler-build build -m variants.yaml          # use variant config file
rattler-build build --target-platform linux-64
rattler-build build --test skip               # skip tests
rattler-build build --package-format conda    # output format
rattler-build build --keep-build              # keep build artifacts
```

Output goes to `./output/` by default (e.g. `output/linux-64/pkg-1.0.0-hash_0.conda`).

### Publish (build + upload in one step)
```bash
rattler-build publish recipe.yaml --to https://prefix.dev/my-channel
rattler-build publish recipe.yaml --to https://anaconda.org/my-username
rattler-build publish recipe.yaml --to s3://my-bucket/my-channel
rattler-build publish recipe.yaml --to /path/to/local/channel
rattler-build publish recipe.yaml --to <url> --build-number=+1  # auto-bump
```

### Upload (pre-built packages)
```bash
rattler-build upload prefix -c my-channel ./output/linux-64/pkg.conda
rattler-build upload anaconda -o my-org ./output/linux-64/pkg.conda
rattler-build upload s3 -c s3://bucket/channel ./output/linux-64/pkg.conda
```

### Test
```bash
rattler-build test --package-file ./output/linux-64/pkg-1.0.0-hash_0.conda
```

### Auth
```bash
rattler-build auth login prefix.dev --token <token>
rattler-build auth login anaconda.org --conda-token <token>
rattler-build auth logout prefix.dev
```

### Generate Recipe
```bash
rattler-build generate-recipe pypi numpy
rattler-build generate-recipe cran dplyr
rattler-build generate-recipe pypi requests --write --tree  # with deps
```

### Bump Version
```bash
rattler-build bump-recipe --recipe recipe.yaml                # auto-detect latest
rattler-build bump-recipe --recipe recipe.yaml --version 2.0  # explicit
rattler-build bump-recipe --recipe recipe.yaml --check-only   # just check
```

### Debug
```bash
rattler-build debug --recipe recipe.yaml     # set up env without building
rattler-build debug-shell                    # interactive shell in build env
rattler-build create-patch                   # create patch from modified source
```

### Inspect
```bash
rattler-build package inspect pkg.conda
rattler-build package inspect pkg.conda --all --json
rattler-build package extract pkg.conda -d ./extracted/
```

## Testing

Tests go in the `tests:` section. Each test runs in an isolated environment.

```yaml
tests:
  # Shell commands
  - script:
      - echo "test passed"

  # Python imports
  - python:
      imports:
        - mypackage
      pip_check: true

  # Script with extra deps and files
  - script:
      - pytest ./tests
    requirements:
      run:
        - pytest
    files:
      recipe:
        - tests/

  # Inline script with interpreter
  - script:
      interpreter: python
      content: |
        import mypackage
        assert mypackage.__version__ == "1.0.0"

  # Package contents check (runs without creating env)
  - package_contents:
      files:
        - lib/python*/site-packages/mypackage/*.py
      bin:
        - myapp
      lib:
        - mylib
```

## Variants

Use a `variants.yaml` file next to the recipe (auto-detected) or pass `-m variants.yaml`:

```yaml
python:
  - "3.10"
  - "3.11"
  - "3.12"
numpy:
  - "1.24"
  - "1.26"
```

Or override on CLI: `--variant python=3.12,3.11`

## Build Process Steps

1. **Render** — parse recipe, evaluate Jinja/conditionals/variants
2. **Fetch source** — download tarballs, clone git repos, apply patches
3. **Install build envs** — install build/host dependencies
4. **Build** — execute build script, install into host prefix (`$PREFIX`)
5. **Prepare package** — collect new files, fix rpaths for relocatability
6. **Package** — bundle into `.conda`, write metadata (`index.json`, `about.json`, `paths.json`)
7. **Test** — run tests; package goes to `broken/` if tests fail

## Key Environment Variables in Build Scripts

- `$PREFIX` / `%PREFIX%` — host prefix (where package installs to)
- `$SRC_DIR` — source directory
- `$BUILD_PREFIX` — build tools prefix
- `$CPU_COUNT` — available CPUs
- `$LIBRARY_PREFIX` — library prefix (Windows)

## GitHub Actions

```yaml
- uses: prefix-dev/rattler-build-action@v0.2.34
  with:
    recipe-path: conda.recipe/recipe.yaml  # default
    build-args: --target-platform linux-64
```

Supports OIDC trusted publishing to prefix.dev (no API keys needed).

## Sources

- [Official docs](https://prefix-dev.github.io/rattler-build/latest/)
- [Recipe format reference](https://rattler.build/dev/reference/recipe_file/)
- [CLI reference](https://rattler-build.prefix.dev/v0.54.0/reference/cli/)
- [GitHub](https://github.com/prefix-dev/rattler-build)
