# traefik-local-proxy

Local HTTPS reverse proxy for Docker development. Traefik terminates TLS for
`*.localtest.me`, redirects HTTP to HTTPS, and routes containers via labels.
HTTPS-first means secure cookies, OAuth callbacks, and browser secure-context
APIs behave much closer to production - local CA and loopback DNS are realistic
but not identical to public production TLS.

Pairs with any local Docker project that benefits from clean HTTPS routing:
web apps, APIs, dashboards, documentation sites, admin tools, and internal
utilities.

---

## Quick start

```bash
cp .env.example .env    # review ports and Traefik version
mise run certs          # generate local CA + wildcard cert (skips if present)
mise run trust-ca       # import CA into Windows CurrentUser trust store (WSL2 → Windows)
mise run up             # start Traefik
mise run demo           # start whoami test service → https://demo.localtest.me
mise run demo-down      # remove the demo container after testing

Dashboard: <https://proxy.localtest.me>

For a lower-ceremony alternative, [mkcert](https://github.com/FiloSottile/mkcert)
auto-installs a local CA into both the Windows and WSL2 trust stores:
`pre-commit` or `shellcheck` install required. It does assume you are inside a
Git working tree, so run it from a normal clone or after `git init`.
generated certs the same way and skip `mise run trust-ca`.

---

## How it works

```mermaid
flowchart LR
  Browser -->|"https://myapp.localtest.me"| T["Traefik :443<br/>proxy"]
  T -->|"HTTP :80 → :443 redirect"| T
  T -->|"label-based routing"| A["myapp container<br/>proxy"]
  T -->|"label-based routing"| B["demo container<br/>proxy"]
```

Traefik watches Docker through the local socket-proxy service for containers that:

1. Are attached to the shared proxy network (default: `proxy`)
2. Have `traefik.enable=true`
3. Have routing labels or a `traefik.hostname` label

It automatically picks them up - no restart required.

---

## What is localtest.me

`localtest.me` is a public wildcard DNS domain that resolves every subdomain to
`127.0.0.1`. It is not an IETF standard like `localhost` - it is a convenience
domain run by a third party. It works because the record is public:
`*.localtest.me IN A 127.0.0.1`.

Why use it instead of `*.localhost`?

- Browsers special-case `localhost` but not all browser + OS combinations treat
  `myapp.localhost` as a secure context or as a valid same-site origin.
- `localtest.me` + a locally-trusted CA makes cookie, CORS, and secure-context
  behavior much closer to production.
- No `/etc/hosts` edits required.

See the DNS-privacy note in the Certificate setup section below.

---

## Certificate setup (WSL2 + Windows)

1. Generate or regenerate the local CA and wildcard cert:

   ```bash
   ./scripts/generate-dev-certs.sh
   # Use --force to replace existing certs
   ```

2. Import `certs/ca.crt` into the Windows trust store - **no admin required**:

   ```bash
   mise run trust-ca
   ```

   This invokes `scripts/trust-ca-windows.ps1`, which imports into
   `Cert:\CurrentUser\Root`. To remove it later: `mise run untrust-ca`.

   Certs are valid 825 days (leaf) and 2 years (CA). To regenerate:
   `./scripts/generate-dev-certs.sh --force` then `mise run trust-ca` again.

3. Start Traefik and open <https://proxy.localtest.me>.

> **Work / managed devices:** Installing a custom root CA may be against your
> IT policy and can trigger endpoint security tooling. Confirm it is allowed
> before trusting `ca.crt` on a corporate machine.
>
> **DNS privacy:** `localtest.me` subdomains are resolved publicly (to
> `127.0.0.1`). Do not use confidential project names, client names, or
> employer names as subdomains on a work network. Use generic names like
> `api.localtest.me`, `demo.localtest.me`, `app.localtest.me`.

---

## Adding a service

In your service's `docker-compose.yml`:

```yaml
services:
  myapp:
    image: myapp:latest
    networks:
      - proxy
    labels:
      traefik.enable: "true"
      traefik.hostname: "myapp"   # routes https://myapp.localtest.me
      traefik.http.routers.myapp.entrypoints: "websecure"
      traefik.http.routers.myapp.tls: "true"
      # Only needed if the container exposes multiple ports:
      traefik.http.services.myapp.loadbalancer.server.port: "8000"

networks:
  proxy:
    external: true
    name: ${TRAEFIK_PROXY_NETWORK:-proxy}
```

> **Hostname with the default rule:** if you rely on the default rule, set
> `traefik.hostname`. Without it, Traefik cannot generate the expected
> `*.localtest.me` host rule. If you define an explicit router `rule`,
> `traefik.hostname` is optional.

**Start traefik-local-proxy first** - it creates the `proxy` network. Other
services reference it as external and will fail to start if the network does
not exist. If you run `mise run down` while no other containers are attached,
start Traefik again before starting those services.

---

## Connecting another Docker project

In another project's `docker-compose.yml`:

```yaml
services:
  myapp:
    image: myapp:latest
    networks:
      - default
      - proxy
    labels:
      traefik.enable: "true"
      traefik.hostname: "myapp"
      traefik.http.routers.myapp.entrypoints: "websecure"
      traefik.http.routers.myapp.tls: "true"
      traefik.http.services.myapp.loadbalancer.server.port: "3000"

networks:
  proxy:
    external: true
    name: ${TRAEFIK_PROXY_NETWORK:-proxy}
```

Start `traefik-local-proxy` first, then start the other project. The service
will be reachable at <https://myapp.localtest.me>.

> **Custom network name:** If you set `TRAEFIK_PROXY_NETWORK` to something other
> than `proxy`, set the same value in each consuming project's `.env`, or replace
> the variable reference with the concrete network name. If the names diverge,
> Traefik discovers containers but routes traffic through the wrong network and
> nothing loads.

---

## Available tasks

Run `mise install` once to install repo-managed tools (uv), then use any task
below. `mise run validate` is fully self-contained - no system-level
`pre-commit` or `shellcheck` install required.

```text
mise run up         # start Traefik + create proxy network
mise run stop       # stop Traefik, keep proxy network
mise run down       # stop Traefik and remove proxy if no other containers use it
mise run restart    # restart Traefik process; use up to apply config changes
mise run logs       # follow Traefik logs
mise run ps         # show service status
mise run pull       # pull newer image + restart
mise run certs      # generate local CA + wildcard cert (skips if already present)
mise run trust-ca   # import CA into Windows CurrentUser trust store (WSL2 → Windows)
mise run untrust-ca # remove dev CA from Windows CurrentUser trust store
mise run demo       # start whoami test service at https://demo.localtest.me
mise run demo-down  # stop the whoami test service
mise run config     # validate docker-compose.yml
mise run validate   # run pre-commit hooks + validate all compose configs
mise run network    # list containers currently on proxy
```

---

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `TRAEFIK_VERSION` | `v3.7.8` | Traefik image tag |
| `TRAEFIK_PROXY_NETWORK` | `proxy` | Shared Docker network name |
| `TRAEFIK_HTTP_PORT` | `80` | Host HTTP port (bound to 127.0.0.1; redirects to HTTPS) |
| `TRAEFIK_HTTPS_PORT` | `443` | Host HTTPS port (bound to 127.0.0.1) |
| `TRAEFIK_NEO4J_PORT` | `7687` | Neo4j TCP entrypoint (loopback-only) |
| `TRAEFIK_MSSQL_PORT` | `1433` | MSSQL TCP entrypoint (loopback-only) |
| `TRAEFIK_MYSQL_PORT` | `3306` | MySQL TCP entrypoint (loopback-only) |
| `TRAEFIK_POSTGRES_PORT` | `5432` | Postgres TCP entrypoint (loopback-only) |
| `TRAEFIK_LOG_LEVEL` | `INFO` | Log verbosity: DEBUG, INFO, WARN, ERROR |

Override in `.env`. Keep `TRAEFIK_VERSION` pinned to a specific patch release
for reproducibility.

The TCP database ports conflict with local installs of MSSQL, MySQL, and
Postgres. Comment out the relevant `ports:` lines in `docker-compose.yml` if
you run those databases directly on the host.

---

## TCP database routing (optional)

The TCP entrypoints for Neo4j (7687), MSSQL (1433), MySQL (3306), and
Postgres (5432) are defined in `traefik.yml` but **the matching port bindings
in `docker-compose.yml` are commented out by default**. Uncomment only the
ports you need and only when you are routing database containers through this
proxy. Those ports commonly conflict with local database installs.

---

## Static config

Traefik static configuration lives in [`traefik.yml`](./traefik.yml).
Dynamic configuration (TLS material) lives in [`dynamic/tls.yml`](./dynamic/tls.yml).

Key settings in `traefik.yml`:

- `providers.docker.defaultRule` generates routes from `traefik.hostname`
  labels without explicit `Host()` rules in every label set.
- `docker-compose.yml` sets the Docker provider endpoint and network with CLI
  flags so `TRAEFIK_PROXY_NETWORK` stays in sync with Compose.
- `providers.file` watches `dynamic/` for hot-reload of TLS config.
- `entrypoints.web` redirects all HTTP to HTTPS permanently.
- `api.insecure=false` - the dashboard is only accessible via the
  `proxy.localtest.me` TLS route.

---

## Optional hardening

### Dashboard basic auth

Add a `dynamic/dashboard-auth.yml` file (gitignore it if it contains
credentials):

```yaml
http:
  middlewares:
    dashboard-auth:
      basicAuth:
        users:
          - "admin:$apr1$..."  # htpasswd -nb admin <password>
```

Then reference the middleware on the dashboard router label in
`docker-compose.yml`:

```yaml
traefik.http.routers.proxy.middlewares: "dashboard-auth@file"
```

Since ports are loopback-only, this is defense-in-depth, not a hard
requirement.

### Security response headers

Add `dynamic/security-headers.yml` and reference it as a middleware on any
router:

```yaml
http:
  middlewares:
    security-headers:
      headers:
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "strict-origin-when-cross-origin"
        # HSTS intentionally disabled - do not enable on a dev domain.
        # Preloaded HSTS persists in browsers after you decommission the proxy.
        # forceSTSHeader: true
        # stsSeconds: 31536000
```

---

## Security notes

- All ports are bound to `127.0.0.1` only - not exposed on the LAN.
- The dashboard is served over HTTPS through the `proxy.localtest.me` route.
  `api.insecure` is disabled.
- Docker socket access effectively grants full Docker API access on the host.
  The raw socket is mounted only into `socket-proxy`; Traefik talks to the
  filtered API endpoint at `tcp://socket-proxy:2375`. Keep this stack
  local-only.
- Private keys in `certs/` are mode `600` and are gitignored. The CA private
  key is powerful - if it leaks and is trusted on any machine, an attacker can
  mint trusted certificates for that CA scope. Treat it as a secret.
- Do not use client, project, or employer names as `localtest.me` subdomains
  on a work network. Use generic names (e.g. `demo`, `api`, `app`).

---

## WSL2 notes

- Docker Engine runs on the WSL2 instance - `mise run up` runs there too.
- `*.localtest.me` resolves publicly to `127.0.0.1`, so Windows browsers reach
  WSL2-published ports without `/etc/hosts` changes.
- If any TCP port is already in use (e.g. a local Postgres on 5432), comment
  out that `ports:` line in `docker-compose.yml` and the corresponding
  entrypoint in `traefik.yml`.
- Certificate trust is determined by the Windows trust store, not the WSL2
  trust store. Use `mise run trust-ca` to import `certs/ca.crt` into Windows
  `CurrentUser\Root` (no admin required). To remove it: `mise run untrust-ca`.
  If Windows cannot reach WSL2-published ports, that is a WSL2 networking or
  Docker Engine port-publishing issue, not a certificate issue.
