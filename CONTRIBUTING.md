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

Tool versions (`mkcert`, `jq`, `uv`) are pinned in `mise.toml`. `shellcheck`
and `gitleaks` versions are pinned in `.pre-commit-config.yaml`. The Traefik
image version is a literal tag in the Compose manifests (not a variable), so
Dependabot can track and bump it directly.
