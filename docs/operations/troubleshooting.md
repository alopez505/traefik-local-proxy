# Troubleshooting

Quick hits for the most common issues. Each links to the section with full detail.

- **Browser says the certificate isn't trusted.** Run `mise run certificates:trust-ca`
  (see [../onboarding/certificates.md](../onboarding/certificates.md)).
- **`network proxy declared as external, but could not be found`.** Start
  `traefik-local-proxy` first - it creates the network (see
  [../runtime/connecting-services.md](../runtime/connecting-services.md#adding-a-service)).
- **Port `80`/`443` (or a database port) is already in use.** Override
  `TRAEFIK_HTTP_PORT`/`TRAEFIK_HTTPS_PORT`/`TRAEFIK_*_PORT` in `.env`, or skip
  that database's override file (see [../runtime/configuration.md](../runtime/configuration.md)).
- **A service returns a 404 or never gets a route.** Confirm the container is
  on the `proxy` network, has `traefik.enable=true`, and has either a
  `traefik.hostname` label or an enabled fallback (see
  [../runtime/connecting-services.md](../runtime/connecting-services.md#adding-a-service)).
- **Windows can't reach a WSL2-published port.** That's a WSL2 networking or
  Docker Engine port-publishing issue, not a certificate problem (see
  [../architecture.md](../architecture.md#wsl2-notes)).
- **Dashboard is unreachable.** Check `TRAEFIK_DASHBOARD_ENABLED` and confirm
  you're using the right scheme for the current mode (see
  [../../README.md](../../README.md#switching-modes)).
