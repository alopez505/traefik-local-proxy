set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes.
default:
    @just --list

# Start Traefik (creates proxy network if needed).
up:
    mise run up

# Start Traefik without local TLS certificates.
up-http:
    mise run up-http

# Start Traefik with the HTTP-to-HTTPS redirect disabled (advanced, opt-in).
up-without-http-to-https-redirect:
    mise run up-without-http-to-https-redirect

# Stop Traefik and remove the compose-owned proxy network.
down:
    mise run down

# Stop Traefik while keeping the proxy network.
stop:
    mise run stop

# Restart Traefik (use 'up' to apply config/port changes).
restart:
    mise run restart

# Follow Traefik logs (Ctrl-C to exit).
logs:
    mise run logs

# Show Traefik service status.
ps:
    mise run ps

# Pull images and apply the HTTPS proxy configuration.
update:
    mise run update

# Pull images and apply the HTTP-only proxy configuration.
update-http:
    mise run update-http

# Generate wildcard cert via mkcert (skips if already present). Accepts --force/--replace-ca.
certificates-generate *args:
    mise run certificates:generate -- {{args}}

# Verify the configured certificate/key: expiry, SAN, pairing, chain, permissions.
certificates-verify *args:
    mise run certificates:verify -- {{args}}

# Import a certificate/key pair from a container image without starting it.
certificates-import-from-image *args:
    mise run certificates:import-from-image -- {{args}}

# Untrust the old Windows CA, replace it, and trust the current mkcert CA.
certificates-replace-ca:
    mise run certificates:replace-ca

# Import dev CA into Windows CurrentUser trust store (WSL2 -> Windows, no admin required).
certificates-trust-ca:
    mise run certificates:trust-ca

# Remove dev CA from Windows CurrentUser trust store.
certificates-untrust-ca:
    mise run certificates:untrust-ca

# Validate the rendered compose config.
config:
    mise run config

# Full local gate: pre-commit hooks + all compose configs.
validate:
    mise run validate

# Show containers currently attached to the proxy network.
network:
    mise run network

# Start whoami test service at https://demo.localtest.me.
demo:
    mise run demo

# Start whoami test service at http://demo.localtest.me.
demo-http:
    mise run demo-http

# Stop the whoami test service.
demo-down:
    mise run demo-down

# Run live HTTPS/HTTP mode-transition and custom-port smoke tests.
smoke:
    mise run smoke

# Run live hostname-fallback resolution-order smoke tests.
smoke-fallback:
    mise run smoke-fallback
