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

Prerequisites: Docker Engine with Compose v2 and `mise`. Windows PowerShell
must be accessible from WSL2 when using the Windows trust-store task. Choose
one startup mode.
The HTTPS mode is the default and is closest to production; the HTTP mode does
not generate certificates or modify the Windows trust store.

`mise install` installs the repo-pinned versions of `mkcert` and `uv` defined in
`mise.toml`. The validation task runs a pinned version of `pre-commit` through
`uvx`; `uv` is otherwise only needed for that task.

### HTTPS mode (default)

```bash
mise install            # install pinned tools (mkcert, uv)
cp .env.example .env    # optional: override ports, network name, or log level
mise run certs          # generate the wildcard cert via mkcert (skips if present)
mise run trust-ca       # import the CA into Windows CurrentUser\Root (WSL2 -> Windows)
mise run up             # start Traefik
mise run demo           # start whoami test service -> https://demo.localtest.me
mise run demo-down      # remove the demo container after testing
```

Dashboard: <https://proxy.localtest.me>

Certificates are generated with [mkcert](https://github.com/FiloSottile/mkcert),
which is pinned in `mise.toml` and installed by `mise install`. mkcert keeps its
CA in its own CAROOT outside the repo; `mise run trust-ca` then imports the CA
certificate into the Windows trust store so Windows browsers trust the HTTPS
that Traefik serves from WSL2.

### HTTP-only mode

Installing a local root CA may not be allowed on a work-managed device. TLS is
optional: run `mise run up-http` without generating or trusting certificates.
Copying `.env.example` to `.env` is optional in both modes. HTTP mode does not
mount certificate files or load the dynamic TLS configuration, and serves the
dashboard at <http://proxy.localtest.me>.

HTTP-only mode is intended for local development where browser HTTPS behavior
is not required. Services used with it should route through the `web`
entrypoint and omit the `tls` label. The existing HTTPS setup remains the
default and is unchanged.

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

---

## How it works

Two views: how a browser request reaches your container, and how Traefik
discovers containers and loads its configuration.

### Request flow

```mermaid
flowchart LR
  Browser -->|"http://myapp.localtest.me"| W["Traefik<br/>web :80"]
  W -->|"temporary HTTPS redirect"| SEC["Traefik<br/>websecure :443"]
  Browser -->|"https://myapp.localtest.me"| SEC
  CA["Windows trust store<br/>(mkcert CA)"] -. trusts .-> Browser
  TLS["dynamic/tls.yml<br/>+ leaf certificate and key"] -->|"TLS configuration"| SEC
  SEC -->|"label-based routing<br/>over the proxy network"| A["myapp container"]
  SEC -->|"label-based routing<br/>over the proxy network"| B["demo container"]
```

`*.localtest.me` resolves to `127.0.0.1`, so the browser reaches Traefik in
WSL2 with no `/etc/hosts` edits. HTTP is redirected to HTTPS; the certificate
and key are mounted as exact files and served via `dynamic/tls.yml`. The
certificate is trusted because the mkcert CA is in the Windows trust store.
HTTP-only mode skips the redirect and TLS; any existing certificate files and
Windows trust entry remain present but unused.

### Container discovery & configuration

```mermaid
flowchart LR
  Static["docker-compose.yml<br/>install configuration"] --> T["Traefik"]
  Dyn["dynamic/tls.yml<br/>hot-reloaded"] --> T
  Certs["certs/<br/>leaf certificate + key"] --> Dyn
  CACopy["certs/ca.crt<br/>CA copy"] -->|"mise run trust-ca"| Trust["Windows trust store"]
  T -->|"filtered Docker API<br/>tcp://socket-proxy:2375"| S["socket-proxy"]
  S <-->|"read-only Docker API<br/>/var/run/docker.sock"| D["Docker Engine"]
  S -->|"container metadata<br/>labels, networks, events"| T
```

Traefik watches Docker through the local socket-proxy service for containers that:

1. Are attached to the shared proxy network (default: `proxy`)
2. Have `traefik.enable=true`
3. Have routing labels or a `traefik.hostname` label

It automatically picks them up - no restart required.

---

## What is localtest.me

`localtest.me` is a public wildcard DNS domain operated by a third party. Its
commonly used IPv4 wildcard record, `*.localtest.me IN A 127.0.0.1`, resolves
subdomains to the IPv4 loopback address. It is a convenience domain, not an
IETF standard like `localhost`.

This stack publishes Docker ports on IPv4 `127.0.0.1` only. Some resolvers also
return IPv6 `::1`; if a browser selects IPv6 first and the request fails, use an
IPv4-preferred resolver or configure Docker to publish the ports on IPv6 too.

Why use it instead of `*.localhost`?

- Browsers special-case `localhost` but not all browser + OS combinations treat
  `myapp.localhost` as a secure context or as a valid same-site origin.
- `localtest.me` + a locally-trusted CA makes cookie, CORS, and secure-context
  behavior much closer to production.
- No `/etc/hosts` edits required.

See the DNS-privacy note in the Certificate setup section below.

---

## Certificate setup (WSL2 + Windows)

1. Generate the wildcard certificate (creates the mkcert CA on first run):

   ```bash
   ./scripts/generate-dev-certs.sh
   # Regenerate only the leaf while keeping the same CA:
   ./scripts/generate-dev-certs.sh --force
   ```

2. Import `certs/ca.crt` into the Windows trust store - **no admin required**:

   ```bash
   mise run trust-ca
   ```

   This invokes `scripts/trust-ca-windows.ps1`, which imports into
   `Cert:\CurrentUser\Root`. To remove it later: `mise run untrust-ca`.

> **Important:** `mise run untrust-ca` removes only the root certificate that
> matches `certs/ca.crt`. mkcert normally shares one CA across projects for a
> user profile, so other projects using that same CA will stop trusting it.

Because `--force` reuses the same mkcert CA, you do not need to re-run
`mise run trust-ca` after regenerating the leaf. If mkcert's CAROOT changes or
its CA is reset, the generator refuses to overwrite `certs/ca.crt`—even with
`--force`—because that file is required to identify the exact old trusted root.
Use the guarded rotation workflow instead:

```bash
mise run replace-ca
```

It removes the old CA from Windows `CurrentUser\Root`, verifies the removal,
replaces the staged CA and leaf, then trusts the new CA. The task manages only
that Windows store. If you separately installed the old CA in WSL, Firefox/NSS,
Java, or another trust store, remove it there before rotating it. If the old CA
cannot be removed, preserve `certs/ca.crt`; do not discard the only exact
identifier for the trusted root.

Then start Traefik and open <https://proxy.localtest.me>.

> **Work / managed devices:** Installing a custom root CA may be against your
> IT policy and can trigger endpoint security tooling. Confirm it is allowed
> before trusting `ca.crt` on a corporate machine.
>
> **DNS privacy:** `localtest.me` subdomains are resolved publicly (to
> `127.0.0.1`). Do not use confidential project names, client names, or
> employer names as subdomains on a work network. Use generic names like
> `api.localtest.me`, `demo.localtest.me`, `app.localtest.me`.
>
> **Team setup (onboarding):** Every developer runs `mise run certs`, which uses
> mkcert to create their **own** local CA (stored in their own mkcert CAROOT) and
> sign their own leaf. Never share that CA around for the whole team to trust:
> whoever holds a CA private key that other machines trust can mint trusted
> certificates for *any* website on every machine that imported it. mkcert keeps
> the CA key in CAROOT, outside the repo, and `certs/` is gitignored (with the
> pre-commit / CI gitleaks hooks as a backstop), so the CA private key never
> leaves the machine that created it. When you re-image or hand off a machine,
> run `mise run untrust-ca` first.

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
      # Required if no backend port can be inferred or several are exposed.
      # Keeping it explicit also makes examples portable:
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

## Project database networking

This proxy is intended to remain running as shared local infrastructure. Both
proxy services use `restart: unless-stopped`, so Docker restarts them after a
Docker Engine or machine restart unless you explicitly stopped them. Start the
proxy once with `mise run up` (or `mise run up-http` for HTTP-only), use
`mise run update` (or `mise run update-http`) to apply image or configuration
updates, and avoid `mise run down` during normal use because it also tries to
remove the shared network.

For a project with an application and a database, attach the application to
both its private project network and the shared `proxy` network. Keep the
database only on the private project network:

```yaml
services:
  myapp:
    image: myapp:latest
    networks:
      - default
      - proxy
    labels:
      traefik.enable: "true"
      traefik.hostname: "project-a"
      traefik.http.routers.project-a.entrypoints: "websecure"
      traefik.http.routers.project-a.tls: "true"
      traefik.http.services.project-a.loadbalancer.server.port: "3000"

  postgres:
    image: postgres:17
    environment:
      POSTGRES_PASSWORD: example
    networks:
      - default
    # Optional access for a host client such as DBeaver:
    ports:
      - "127.0.0.1:15432:5432"

networks:
  proxy:
    external: true
    name: ${TRAEFIK_PROXY_NETWORK:-proxy}
```

The application connects directly to `postgres:5432` using Docker's internal
DNS; it does not send its database traffic through Traefik. A browser reaches
the application through Traefik at <https://project-a.localtest.me>. If
DBeaver, SSMS, or another host application needs database access, publish a
unique loopback port from that project's database container, such as
`127.0.0.1:15432` above. Use a different host port for each project.

The same direct-networking pattern applies to every supported database. If the
Compose service uses the conventional name, the application connects to:

- Postgres: `postgres:5432`
- MSSQL: `mssql:1433`
- MySQL: `mysql:3306`
- Neo4j: `neo4j:7687`

```mermaid
flowchart LR
  Browser -->|"HTTPS"| Traefik
  Traefik -->|"shared proxy network"| Application
  Application -->|"private project network"| Database
  Client["Database client"] -->|"optional unique loopback port"| Database
```

The shared TCP entrypoints described below are an opt-in alternative for a
single database service per entrypoint. Rules such as ``HostSNI(`*`)`` match
all connections and cannot distinguish several Postgres, MSSQL, MySQL, or
Neo4j services on the same port. They are therefore not the recommended
database path when multiple projects use the same database protocol.

---

## Available tasks

Run `mise install` once to install repo-managed tools (mkcert, uv), then use any task
below. `mise run validate` is fully self-contained - no system-level
`pre-commit` or `shellcheck` install required.

```text
mise run up          # start Traefik + create proxy network
mise run up-http     # start Traefik without local TLS certificates
mise run stop        # stop Traefik, keep proxy network
mise run down        # stop Traefik and remove proxy if no other containers use it
mise run restart     # restart Traefik process; use up to apply config changes
mise run logs        # follow Traefik logs
mise run ps          # show service status
mise run update      # pull images + apply the HTTPS configuration
mise run update-http # pull images + apply the HTTP-only configuration
mise run certs       # generate the wildcard cert via mkcert (skips if already present)
mise run replace-ca  # untrust old Windows CA, replace it, and trust the new CA
mise run trust-ca    # import CA into Windows CurrentUser trust store (WSL2 → Windows)
mise run untrust-ca  # remove dev CA from Windows CurrentUser trust store
mise run demo        # start whoami test service at https://demo.localtest.me
mise run demo-http   # start whoami test service at http://demo.localtest.me
mise run demo-down   # stop the whoami test service
mise run config      # validate docker-compose.yml
mise run validate    # run pre-commit hooks + validate all compose configs
mise run smoke       # live HTTPS/HTTP transition and custom-port checks
mise run network     # list containers currently on proxy
```

The smoke task uses loopback ports `18080`/`18443`, a disposable network, and
cleans up afterward. It refuses to run while the normal proxy or demo
containers exist.

---

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `TRAEFIK_PROXY_NETWORK` | `proxy` | Shared Docker network name |
| `TRAEFIK_HTTP_PORT` | `80` | Host HTTP port (bound to 127.0.0.1; redirects to HTTPS in HTTPS mode) |
| `TRAEFIK_HTTPS_PORT` | `443` | Host HTTPS port (bound to 127.0.0.1 and included in redirects) |
| `TRAEFIK_NEO4J_PORT` | `7687` | Neo4j TCP entrypoint (loopback-only) |
| `TRAEFIK_MSSQL_PORT` | `1433` | MSSQL TCP entrypoint (loopback-only) |
| `TRAEFIK_MYSQL_PORT` | `3306` | MySQL TCP entrypoint (loopback-only) |
| `TRAEFIK_POSTGRES_PORT` | `5432` | Postgres TCP entrypoint (loopback-only) |
| `TRAEFIK_LOG_LEVEL` | `INFO` | Log verbosity: DEBUG, INFO, WARN, ERROR |

Override these settings in an optional `.env`. With non-default web ports, use
the explicit port in browser URLs—for example, `http://demo.localtest.me:8080`
and `https://demo.localtest.me:8443`. HTTPS mode constructs its redirect using
the published `TRAEFIK_HTTPS_PORT`.

Image versions are declared directly in the Compose manifests, which are the
authoritative source and are updated by Dependabot.

The TCP database port bindings are commented out by default because they
conflict with local installs of Neo4j, MSSQL, MySQL, and Postgres. Leave the
relevant bindings disabled if those ports are already in use on the host.

---

## TCP database routing (optional)

The HTTPS Compose command defines TCP entrypoints for Neo4j (7687), MSSQL
(1433), MySQL (3306), and Postgres (5432), but **the matching port bindings in
`docker-compose.yml` are commented out by default**. Uncomment only the ports
you need and only when you are routing a single database service through each
entrypoint. Those ports commonly conflict with local database installs. For
the normal multi-project setup, use private project networking and optional
per-project loopback bindings as described above.

For example, to route a Postgres container, uncomment the Postgres host-port
binding in `docker-compose.yml`, then add these labels to the database service:

```yaml
services:
  postgres:
    networks:
      - proxy
    labels:
      traefik.enable: "true"
      traefik.tcp.routers.postgres.entrypoints: "postgres"
      traefik.tcp.routers.postgres.rule: "HostSNI(`*`)"
      traefik.tcp.services.postgres.loadbalancer.server.port: "5432"

networks:
  proxy:
    external: true
    name: ${TRAEFIK_PROXY_NETWORK:-proxy}
```

Connect the client to `127.0.0.1:${TRAEFIK_POSTGRES_PORT:-5432}`. Repeat the
pattern with the matching entrypoint and container port for the other database
types. This is raw TCP forwarding; TLS, authentication, and encryption remain
the responsibility of the database protocol and client.

---

## Install and dynamic config

Traefik install configuration lives in each Compose service's `command` list:
[`docker-compose.yml`](./docker-compose.yml) for HTTPS and
[`docker-compose.http.yml`](./docker-compose.http.yml) for HTTP-only mode.
Traefik supports file, CLI, and environment install configuration as separate
methods, so this repository uses CLI consistently rather than mixing methods.
That lets Compose interpolate the selected network, log level, and external
HTTPS redirect port. HTTP-only mode has no `websecure` entrypoint, HTTPS port,
file provider, or certificate mount.

Dynamic TLS configuration lives in
[`dynamic/tls.yml`](./dynamic/tls.yml).

The HTTPS Compose file mounts `dynamic/` read-only and mounts only
`certs/localtest.me.crt` and `certs/localtest.me.key` at their exact container
paths. Traefik does not receive `certs/ca.crt` or any unrelated file that may
exist in `certs/`. The checked-in `tls.yml` expects those exact leaf filenames.
HTTP-only mode does not mount or load the dynamic directory or certificate
files.

Key install settings in the Compose commands:

- `providers.docker.defaultRule` generates routes from `traefik.hostname`
  labels without explicit `Host()` rules in every label set.
- `docker-compose.yml` sets the Docker provider endpoint and network with CLI
  flags so `TRAEFIK_PROXY_NETWORK` stays in sync with Compose. It also sets the
  redirect target to the externally published HTTPS port.
- `providers.file` watches `dynamic/` for hot-reload of TLS config.
- `entrypoints.web` redirects HTTP to HTTPS temporarily in HTTPS mode.
- `api.insecure=false` - the dashboard is exposed only through a labeled
  router: TLS in the default mode and loopback-only HTTP in HTTP mode.

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
- The dashboard is served over HTTPS through the `proxy.localtest.me` route in
  the default mode. The explicit HTTP fallback serves it over loopback HTTP.
  `api.insecure` remains disabled in both modes.
- Docker socket access effectively grants full Docker API access on the host.
  The raw socket is mounted only into `socket-proxy`; Traefik talks to the
  filtered API endpoint at `tcp://socket-proxy:2375`. Keep this stack
  local-only.
- The leaf private key in `certs/` is mode `600` and gitignored; the CA private
  key is not in the repo at all - mkcert keeps it in its CAROOT. That CA key is
  powerful: if it leaks and is trusted on any machine, an attacker can mint
  trusted certificates for that CA scope. Treat it as a secret.
- Do not use client, project, or employer names as `localtest.me` subdomains
  on a work network. Use generic names (e.g. `demo`, `api`, `app`).

---

## WSL2 notes

- Docker Engine runs on the WSL2 instance - `mise run up` runs there too.
- `*.localtest.me` resolves publicly to `127.0.0.1`, so Windows browsers reach
  WSL2-published ports without `/etc/hosts` changes.
- The optional database port bindings are disabled by default. If an enabled
  port conflicts with a local database, disable that binding again or assign a
  different `TRAEFIK_*_PORT` value in `.env`.
- Certificate trust is determined by the Windows trust store, not the WSL2
  trust store. Use `mise run trust-ca` to import `certs/ca.crt` into Windows
  `CurrentUser\Root` (no admin required). To remove it: `mise run untrust-ca`.
  If Windows cannot reach WSL2-published ports, that is a WSL2 networking or
  Docker Engine port-publishing issue, not a certificate issue.
