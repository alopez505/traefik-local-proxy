# Contributing

## Prerequisites

- Docker Engine with Compose v2.
- `mise`.
- `openssl` and `curl` (used by the regression and smoke tests).

## One-time setup

```bash
mise trust && mise install   # installs the pinned toolchain (mkcert, jq, uv, gitleaks)
```

## Before opening a pull request

Run the local gate that CI's `validate` job runs:

```bash
mise run validate   # pre-commit hooks (shellcheck, gitleaks), all compose configs, parity checks, regression tests
```

`mise run validate` requires a git repository (pre-commit needs `.git`) and a
running Docker daemon.

CI also runs live smoke tests against a real Traefik container. To run them
locally:

```bash
mise run smoke            # HTTPS/HTTP mode transitions and custom ports
mise run smoke-fallback   # hostname-fallback resolution order
```

Both use high loopback ports and clean up after themselves. They refuse to run
while the regular proxy or socket-proxy container exists (running or stopped)
or while the `proxy` network exists, and `mise run smoke` also checks for the
demo container. Remove the regular stack first: stop any other projects
attached to the `proxy` network, then run `mise run demo-down` and
`mise run down` (not `mise run stop`, which keeps the containers and network).
`mise run down` cannot remove `proxy` while other containers are attached to
it.

`mise run` loads `.env` (as does a shell with `mise activate`). The smoke
scripts set their own ports, log level, and network name, but other values from
`.env` (bind addresses, certificate paths, `TRAEFIK_DASHBOARD_ENABLED`, and for
`mise run smoke` the hostname-fallback flags) override the `.env.example`
defaults the scripts pass to Compose. To match CI, move a customized `.env`
aside before running them.

## Continuous integration

GitHub Actions runs [`.github/workflows/ci.yml`](.github/workflows/ci.yml) on
every pull request that targets `main` and on every push to `main`. The
workflow has four jobs:

| Job | Runner | What it checks | Local equivalent |
| --- | --- | --- | --- |
| `validate` | `ubuntu-latest` | Pre-commit hooks, every Compose configuration, Compose parity checks (both modes share an identical `defaultrule`; `docker-compose.disable-http-to-https-redirect.yml` drops only the 3 redirect flags from the base command list), and script regression tests | `mise run validate` |
| `runtime-smoke` | `ubuntu-latest`, after `validate` passes | Starts the proxy and test services, then checks HTTPS/HTTP mode transitions, custom ports, and hostname fallback | `mise run smoke` and `mise run smoke-fallback` |
| `powershell` | `windows-latest` | Parses `scripts/*.ps1` and runs PSScriptAnalyzer at Error and Warning severity | `Invoke-ScriptAnalyzer -Path scripts -Recurse -Severity Error, Warning` in `pwsh` with PSScriptAnalyzer 1.25.0 (the separate parse step is not included) |
| `secret-scan` | `ubuntu-latest` | gitleaks across the full Git history, at the version pinned in `mise.toml` | `mise exec -- gitleaks detect --source . --redact` |

The gitleaks hook scans only staged changes. Under `mise run validate` it sees
whatever is staged at that moment (nothing, in CI); at commit time it runs only
if pre-commit is installed as a Git hook. The `secret-scan` job is the
full-history check.

Dependabot checks weekly for newer image tags in the Compose files (repository
root and `examples/whoami/`) and for newer GitHub Actions versions. Its pull
requests run through the same workflow.

## Pinned versions

Tool versions (`mkcert`, `jq`, `uv`, `gitleaks`) are pinned in `mise.toml`, and
`mise.lock` locks a download URL for each of the seven supported platforms. `jq`,
`uv` and `gitleaks` also carry checksums there; `mkcert` is URL-only, because its
upstream release publishes bare binaries with no checksum file for aqua to
record. After changing a version in `mise.toml`, run `mise lock` and commit the
updated lockfile: CI installs with `--locked` and fails if the two disagree.

`shellcheck` is pinned in `.pre-commit-config.yaml`; `gitleaks` is pinned in
`mise.toml` and the hook runs that binary, so no Go toolchain is built. mise
itself is pinned through the `version` input of both mise action steps in
`.github/workflows/ci.yml` (in the `validate` and `secret-scan` jobs);
Dependabot updates the action reference but not that input, so bump the two
`version` inputs together by hand. The Traefik image version is a literal tag
in the Compose manifests (not a variable), so Dependabot can track and bump it
directly.
