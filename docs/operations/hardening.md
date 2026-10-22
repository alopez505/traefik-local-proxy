# Optional hardening

The middleware files on this page go in `dynamic/`. HTTPS mode loads that
whole directory; HTTP-only mode (`mise run up-http`) loads only
`dynamic/serverstransport.yml`, so routers used with it cannot reference
`dashboard-auth@file` or `security-headers@file`.

## Dashboard basic auth

Add a `dynamic/dashboard-auth.yml` file (already gitignored, since it may
contain credentials):

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

With the default loopback bind address this is defense-in-depth. Before
widening `TRAEFIK_WEB_BIND_ADDRESS`, add this middleware (HTTPS mode only) or
disable the dashboard (see
[../runtime/configuration.md](../runtime/configuration.md)).

## Security response headers

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
