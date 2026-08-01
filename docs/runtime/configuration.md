# Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `TRAEFIK_WEB_BIND_ADDRESS` | `127.0.0.1` | Bind address for the HTTP/HTTPS ports. Widening this does not by itself make the proxy reachable from a remote device - see the exposure notes below |
| `TRAEFIK_TCP_BIND_ADDRESS` | `127.0.0.1` | Bind address for database TCP entrypoints (see [database-routing.md](database-routing.md)). Independent from `TRAEFIK_WEB_BIND_ADDRESS` on purpose |
| `TRAEFIK_HTTP_PORT` | `80` | Host HTTP port (redirects to HTTPS in HTTPS mode) |
| `TRAEFIK_HTTPS_PORT` | `443` | Host HTTPS port (included in redirects) |
| `TRAEFIK_NETWORK_NAME` | `proxy` | **Advanced.** Docker network shared with routed projects. Changing it requires every already-configured consuming project to change too, or discovery breaks silently |
| `TRAEFIK_DASHBOARD_ENABLED` | `true` | Set to `false` to fully disable the dashboard/API router |
| `TRAEFIK_FALLBACK_TO_COMPOSE_SERVICE_NAME` | `false` | Route `<compose-service-name>.localtest.me` when `traefik.hostname` is absent (see [connecting-services.md](connecting-services.md)) |
| `TRAEFIK_FALLBACK_TO_CONTAINER_NAME` | `false` | Route `<container-name>.localtest.me` when `traefik.hostname` is absent and the service-name tier above didn't match |
| `TRAEFIK_CERTIFICATE_FILE` | `./certs/localtest.me.crt` | Certificate file the proxy mounts - point this at any cert, however it got there |
| `TRAEFIK_CERTIFICATE_KEY_FILE` | `./certs/localtest.me.key` | Matching private key file |
| `TRAEFIK_NEO4J_PORT` | `7687` | Neo4j TCP entrypoint |
| `TRAEFIK_MSSQL_PORT` | `1433` | MSSQL TCP entrypoint |
| `TRAEFIK_MYSQL_PORT` | `3306` | MySQL TCP entrypoint |
| `TRAEFIK_POSTGRES_PORT` | `5432` | Postgres TCP entrypoint |
| `TRAEFIK_LOG_LEVEL` | `INFO` | Log verbosity: DEBUG, INFO, WARN, ERROR |

Override these settings in an optional `.env`. With non-default web ports, use
the explicit port in browser URLs - for example, `http://demo.localtest.me:8080`
and `https://demo.localtest.me:8443`. HTTPS mode constructs its redirect using
the published `TRAEFIK_HTTPS_PORT`.

The Traefik image version is a literal tag in the Compose manifests (not a
variable), which keeps it the authoritative source that Dependabot updates
automatically. To run a different image instead, add
`docker-compose.use-custom-traefik-image.yml` to your `-f` list and set
`TRAEFIK_IMAGE`; see that file for the exact invocation. This is an advanced,
opt-in path - the default Quick start always uses the pinned, tested image.

The automatic HTTP-to-HTTPS redirect has no on/off env var - Traefik has no
boolean flag for it, the mere presence of the redirect flags is what enables
it, and Compose's `command:` key fully replaces (not merges) across `-f`
files, so there is no way to toggle just those flags with a variable. To
disable it, use `just up-without-http-to-https-redirect`, or add
`docker-compose.disable-http-to-https-redirect.yml` to your `-f` list
directly. A CI check keeps that file in sync with docker-compose.yml's
command list.

The TCP database ports are not published by default because they conflict
with local installs of Neo4j, MSSQL, MySQL, and Postgres - each is only
published by adding its own `docker-compose.<db>.yml` override file (see
[database-routing.md](database-routing.md)). Leave the relevant override file
out if that port is already in use on the host.

**Exposure notes:**

- Widening `TRAEFIK_WEB_BIND_ADDRESS` beyond `127.0.0.1` still requires a
  remote DNS/hosts override pointing at this machine, CA trust on the remote
  client, and host firewall access - `*.localtest.me` resolves every client
  to its own loopback address, not to this machine, so binding wider does not
  by itself make anything reachable remotely.
- Widening `TRAEFIK_TCP_BIND_ADDRESS` exposes every currently-enabled
  database override port (see [database-routing.md](database-routing.md)) to
  host interfaces, not just one.
- Disable or otherwise protect the dashboard (`TRAEFIK_DASHBOARD_ENABLED=false`)
  before widening `TRAEFIK_WEB_BIND_ADDRESS`.
- `just up` and `just validate` print a non-blocking advisory warning
  when either bind address resolves to something other than `127.0.0.1`. This
  only runs on just/mise-managed tasks - it cannot protect a raw `docker
  compose up` invocation.
