# Contributing

## Prerequisites

- Docker Engine with Compose v2.
- `mise`.

## One-time setup

```bash
mise trust && mise install   # installs the pinned toolchain (mkcert, jq, uv)
```

## Before opening a pull request

Run the same local gate CI runs:

```bash
mise run validate   # pre-commit hooks (shellcheck, gitleaks) + all compose configs + regression tests
```

`mise run validate` requires a git repository (pre-commit needs `.git`) and a
running Docker daemon.

## Pinned versions

Tool versions (`mkcert`, `jq`, `uv`) are pinned in `mise.toml`, and `mise.lock`
locks a download URL for each of the seven supported platforms. `jq` and `uv`
also carry checksums there; `mkcert` is URL-only, because its upstream release
publishes bare binaries with no checksum file for aqua to record. After
changing a version in `mise.toml`, run `mise lock` and commit the updated
lockfile: CI installs with `--locked` and fails if the two disagree.

`shellcheck` and `gitleaks` are pinned in `.pre-commit-config.yaml`, and mise
itself is pinned in `.github/workflows/ci.yml`. The Traefik image version is a
literal tag in the Compose manifests (not a variable), so Dependabot can track
and bump it directly.
