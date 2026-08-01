# Task reference

`just <recipe>` wraps every `mise run <task>` this repo defines, so `mise`
still manages tool versions while `just` is the public task interface (see
[../../CLAUDE.md](../../CLAUDE.md)). Run `just --list` for the short form of
this table.

```text
just up                                 # start Traefik + create proxy network
just up-http                            # start Traefik without local TLS certificates
just up-without-http-to-https-redirect  # advanced: HTTPS mode, redirect disabled
just stop                               # stop Traefik, keep proxy network
just down                               # stop Traefik and remove proxy if no other containers use it
just restart                            # restart Traefik process; use up to apply config changes
just logs                               # follow Traefik logs
just ps                                 # show service status
just update                             # pull images + apply the HTTPS configuration
just update-http                        # pull images + apply the HTTP-only configuration
just certificates-generate              # generate the wildcard cert via mkcert (skips if already present)
just certificates-verify                # verify the configured cert/key: expiry, SAN, pairing, chain, permissions
just certificates-import-from-image     # import a cert/key pair from a container image without starting it
just certificates-replace-ca            # untrust old Windows CA, replace it, and trust the new CA
just certificates-trust-ca              # import CA into Windows CurrentUser trust store (WSL2 -> Windows)
just certificates-untrust-ca            # remove dev CA from Windows CurrentUser trust store
just demo                               # start whoami test service at https://demo.localtest.me
just demo-http                          # start whoami test service at http://demo.localtest.me
just demo-down                          # stop the whoami test service
just config                             # validate docker-compose.yml
just validate                           # run pre-commit hooks + validate all compose configs
just smoke                              # live HTTPS/HTTP transition and custom-port checks
just smoke-fallback                     # live hostname-fallback resolution-order checks
just network                            # list containers currently on proxy
```

The smoke task uses loopback ports `18080`/`18443`, a disposable network, and
cleans up afterward. It refuses to run while the normal proxy or demo
containers exist.
