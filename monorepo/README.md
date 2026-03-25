# Monorepo Layout (Local Workspace)

This repo is already packaged as a Python distribution named `nightops` (see `/Users/suchitraswain/Documents/google/TheNightOps/pyproject.toml`).

To let you use it inside a monorepo without moving your existing code, we created this local workspace folder:

- `monorepo/packages/nightops` is a symlink to the existing `TheNightOps` project root.

## Setup

From the `monorepo/` directory:

```bash
cd monorepo
python3 -m venv .venv
source .venv/bin/activate

# Install TheNightOps as a package
pip install -e "packages/nightops[dev]"
```

## Using the CLI from the monorepo

The CLI loads config from a path you pass via `--config` (or from `config/nightops.yaml` relative to your current working directory).
So, when you run from `monorepo/`, prefer passing an explicit config path:

```bash
nightops verify --config packages/nightops/config/nightops.yaml
nightops agent run --simple --incident "pod OOMKilled" --config packages/nightops/config/nightops.yaml
```

Alternative: `cd packages/nightops` before running `nightops ...` so `config/nightops.yaml` resolves naturally.

## Adding more packages later

For additional Python packages, create new folders under `monorepo/packages/<your-package>/` and give each package its own `pyproject.toml`.

---

## Publish `nightops` (so other repos can install it)

From the `TheNightOps` project root (this repo):

### Step 1: Build artifacts
```bash
cd "/Users/suchitraswain/Documents/google/TheNightOps"

python3 -m pip install -U pip build twine
python3 -m build
```

This generates files in `dist/` (a `.whl` and a `.tar.gz`).

If `python -m build` fails with an error like `Unknown license exception: 'Commons-Clause-1.0'`, make sure `pyproject.toml` uses:
`license = { file = "LICENSE" }`
(this repo has been updated accordingly).

### Step 2: Upload to PyPI (or TestPyPI)

For PyPI:
```bash
twine upload dist/*
```

For TestPyPI:
```bash
twine upload --repository testpypi dist/*
```

You need an API token set up in `~/.pypirc` or via `TWINE_USERNAME` / `TWINE_PASSWORD`.

### Step 3 (before re-publishing): bump version

Update `version = "..."` in `pyproject.toml` and then repeat the build/upload steps.

---

## Install `nightops` in another project

### Step 1: Create/activate a virtualenv
```bash
python3 -m venv .venv
source .venv/bin/activate
```

### Step 2: Install the published package
```bash
pip install nightops
```

Or pin a version:
```bash
pip install "nightops==0.1.0b1"
```

### Step 2b (if using TestPyPI)
```bash
pip install --index-url https://test.pypi.org/simple/ "nightops==0.1.0b1"
```

---

## Using `nightops` in the other project

The CLI expects a config file path via `--config` (or it will look for `config/nightops.yaml` relative to your current working directory).

### Step 1: Copy/create config in the other repo
Create something like:
```text
other-repo/
  config/
    nightops.yaml
```

### Step 2: Run
```bash
nightops verify --config /absolute/path/to/other-repo/config/nightops.yaml

nightops agent run --simple \
  --incident "pod OOMKilled" \
  --config /absolute/path/to/other-repo/config/nightops.yaml
```

### Step 3: Optional: run watch mode
```bash
nightops agent watch --simple \
  --config /absolute/path/to/other-repo/config/nightops.yaml
```

---

## Important note about config files

`nightops` ships default YAML files inside the installed package, so the CLI can start even if the consuming repo doesn’t provide `config/nightops.yaml`.

In practice, you will still want to provide your own `config/nightops.yaml` in the consuming repo (so you can set your real GCP/Grafana/Slack values) and pass `--config` to override defaults.

