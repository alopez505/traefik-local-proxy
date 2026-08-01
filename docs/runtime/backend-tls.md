# Backend TLS compatibility

Some backend services present a self-signed or otherwise untrusted HTTPS
certificate. Rather than a global bypass, this repo ships one named,
inert-by-default `serversTransport` in
[`../../dynamic/serverstransport.yml`](../../dynamic/serverstransport.yml):

```yaml
http:
  serversTransports:
    skip-backend-certificate-verification:
      insecureSkipVerify: true
```

`insecureSkipVerify: true` weakens certificate verification **between
Traefik and that one backend** - it does nothing on its own, and is safer
than a global bypass only because each service must opt in individually, not
because it's free. A service opts in with **both** of these labels:

```yaml
traefik.http.services.example.loadbalancer.server.scheme: "https"
traefik.http.services.example.loadbalancer.serverstransport: "skip-backend-certificate-verification@file"
```

`server.scheme: "https"` is required alongside the transport reference -
without it, Traefik's port-based scheme inference may never attempt HTTPS to
the backend at all, making the transport reference alone insufficient.

This works in both proxy modes. In HTTPS mode the whole `dynamic/` directory
is mounted and watched, same as the TLS config. In HTTP-only mode, only
`dynamic/serverstransport.yml` itself is mounted and loaded via
`--providers.file.filename` (not `--providers.file.directory` - HTTP-only
mode has no TLS store to configure, so `dynamic/tls.yml` is never loaded
there).

A healthy `--ping` healthcheck only proves Traefik itself is running - it
does not prove this file parsed or the named transport actually registered.
