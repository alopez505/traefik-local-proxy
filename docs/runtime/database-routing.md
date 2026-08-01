# TCP database routing (optional)

The HTTPS Compose command always defines TCP entrypoints for Neo4j (7687),
MSSQL (1433), MySQL (3306), and Postgres (5432), but **none of their host
ports are published unless you add the matching override file** to your `-f`
list: `docker-compose.neo4j.yml`, `docker-compose.mssql.yml`,
`docker-compose.mysql.yml`, `docker-compose.postgres.yml`. There is nothing
to uncomment in `docker-compose.yml` - add only the override files you need:

```bash
docker compose -f docker-compose.yml -f docker-compose.postgres.yml up -d
```

Publishing a port only opens the entrypoint - it does not route anything by
itself. An actual database container still needs its own TCP router/service
labels, for example:

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
    name: proxy
```

Connect the client to `${TRAEFIK_TCP_BIND_ADDRESS:-127.0.0.1}:${TRAEFIK_POSTGRES_PORT:-5432}`.
Repeat the pattern with the matching entrypoint and container port for the
other database types. Those ports commonly conflict with local database
installs; for the normal multi-project setup, use private project networking
and optional per-project loopback bindings as described in
[connecting-services.md](connecting-services.md) instead.

**Read this before assuming any database can share an entrypoint by
hostname.** A raw, non-TLS `HostSNI(\`*\`)` rule like the one above supports
exactly **one backend per entrypoint** - it cannot distinguish between
several Postgres (or several MSSQL, MySQL, or Neo4j) containers on the same
port. Traefik does support routing by SNI after a client's TLS/STARTTLS
negotiation for some protocols - it explicitly documents this for Postgres,
provided the client uses a compatible `sslmode` - but this is
protocol-and-client-specific behavior, not a general Traefik capability.
**Do not assume it generalizes to MSSQL, MySQL, or Neo4j** without testing
that protocol's own TLS/negotiation handshake; each override file's own
header comment repeats this caveat. See [Traefik's TCP TLS routing
documentation](https://doc.traefik.io/traefik/reference/routing-configuration/tcp/tls/)
for the mechanism this depends on. Beyond that, this is raw TCP forwarding:
authentication and encryption remain entirely the responsibility of the
database protocol and client.
