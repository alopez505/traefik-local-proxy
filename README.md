# traefik-local-proxy

[![CI](https://github.com/alopez505/traefik-local-proxy/actions/workflows/ci.yml/badge.svg)](https://github.com/alopez505/traefik-local-proxy/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Local HTTPS reverse proxy for Docker development. Traefik terminates TLS for
`*.localtest.me`, redirects HTTP to HTTPS, and routes containers via labels.
HTTPS-first means secure cookies, OAuth callbacks, and browser secure-context
APIs behave much closer to production - local CA and loopback DNS are realistic
but not identical to public production TLS.

Pairs with any local Docker project that benefits from clean HTTPS routing:
web apps, APIs, dashboards, documentation sites, admin tools, and internal
utilities. This is an independent personal project, not affiliated with or
endorsed by Traefik Labs.

## Quick start

Prerequisites: Docker Engine with Compose v2 and `mise`.

Choose one startup mode:

| Mode | Command | Dashboard URL | Needs generated certs? | Needs Windows trust? |
| --- | --- | --- | --- | --- |
| HTTPS (default, closest to production) | `mise run up` | <https://proxy.localtest.me> | Yes (`certificates:generate`) | Yes (`certificates:trust-ca`) |
| HTTP-only (no local CA required) | `mise run up-http` | <http://proxy.localtest.me> | No | No |

### HTTPS mode (default)

```bash
mise trust                            # one time per clone
mise install                          # install pinned tools (mkcert, jq, uv)
cp .env.example .env                  # optional: override ports or log level
mise run certificates:generate        # generate the wildcard cert via mkcert (skips if present)
mise run certificates:trust-ca        # import the CA into Windows CurrentUser\Root (WSL2 -> Windows)
mise run up                           # start Traefik
mise run demo                         # start whoami test service -> https://demo.localtest.me
mise run demo-down                    # remove the demo container after testing
```

Dashboard: <https://proxy.localtest.me>

Certificates are generated with [mkcert](https://github.com/FiloSottile/mkcert),
pinned in `mise.toml`. mkcert keeps its CA in its own CAROOT outside the repo;
`mise run certificates:trust-ca` imports that CA into the Windows trust store so
Windows browsers trust the HTTPS Traefik serves from WSL2. Full walkthrough,
rotation, and team-onboarding notes: [docs/onboarding/certificates.md](docs/onboarding/certificates.md).

### HTTP-only mode

Installing a local root CA may not be allowed on a work-managed device. TLS is
optional: run `mise run up-http` without generating or trusting certificates.
Copying `.env.example` to `.env` is optional in both modes. HTTP mode does not
mount certificate files or load the dynamic TLS configuration, and serves the
dashboard at <http://proxy.localtest.me>.

HTTP-only mode is intended for local development where browser HTTPS behavior
is not required. Services used with it should route through the `web`
entrypoint and omit the `tls` label.

### Switching modes

The two modes use the same Compose project, container names, network, and host
ports. Running `mise run up-http` while HTTPS is running, or `mise run up` while
HTTP is running, causes Compose to recreate the proxy with the selected config;
you do not need to remove certificates or rebuild anything. The certificate
files and Windows trust entry remain on the machine but are unused in HTTP mode.
HTTPS mode uses temporary redirects so browsers do not retain a permanent
HTTP-to-HTTPS redirect after the proxy switches back to HTTP.

The proxy switches automatically, but routed application containers do not
change their labels. Use `mise run demo-http` for the HTTP demo, or update an
application's router from `websecure` plus `tls: "true"` to `web` without the
TLS label. Switch those labels back when returning to HTTPS.

## Commands

| Task | Purpose |
| --- | --- |
| `mise run up` / `mise run up-http` | Start Traefik in HTTPS or HTTP-only mode |
| `mise run down` / `mise run stop` | Remove or stop the proxy |
| `mise run certificates:generate` | Generate the wildcard cert via mkcert |
| `mise run certificates:trust-ca` | Import the dev CA into the Windows trust store |
| `mise run demo` / `mise run demo-down` | Start/stop the whoami test service |
| `mise run validate` | Full local gate: pre-commit hooks + all compose configs |
| `mise run network` | List containers currently attached to the proxy network |

Full reference (all 24 tasks): [docs/operations/tasks.md](docs/operations/tasks.md).

## Layout

```text
dynamic/           TLS config, backend-TLS transport, optional hardening middlewares
examples/whoami/   Minimal test service used by `mise run demo`
scripts/           Certificate generation/verification/import, exposure checks, smoke tests
docs/              Architecture, onboarding, runtime, and operations
```

## Docs

- [docs/architecture.md](docs/architecture.md)
- Onboarding: [certificates](docs/onboarding/certificates.md)
- Runtime: [configuration](docs/runtime/configuration.md) ·
  [connecting-services](docs/runtime/connecting-services.md) ·
  [database-routing](docs/runtime/database-routing.md) ·
  [backend-tls](docs/runtime/backend-tls.md)
- Operations: [tasks](docs/operations/tasks.md) ·
  [hardening](docs/operations/hardening.md) ·
  [troubleshooting](docs/operations/troubleshooting.md)

## Non-goals

No production TLS termination, no multi-tenant/shared-hosting isolation, no
Kubernetes, and no CI/CD pipelines. This proxy is local-development
infrastructure, not a production reverse proxy.
