# Task reference

Tasks are defined in `mise.toml` and run with `mise run <task>` (see
[../../CLAUDE.md](../../CLAUDE.md)). Run `mise tasks` for the short form of
this table. Always use the `mise run` form: bare `mise up` and `mise config`
are mise's own subcommands (upgrade, settings), not this repo's tasks.

Pass flags through to the underlying script after `--`, for example
`mise run certificates:generate -- --force`.

```text
mise run up                                 # start Traefik + create proxy network
mise run up-http                            # start Traefik without local TLS certificates
mise run up-without-http-to-https-redirect  # advanced: HTTPS mode, redirect disabled
mise run stop                               # stop Traefik, keep proxy network
mise run down                               # stop Traefik and remove proxy if no other containers use it
mise run restart                            # restart Traefik process; use up to apply config changes
mise run logs                               # follow Traefik logs
mise run ps                                 # show service status
mise run update                             # pull images + apply the HTTPS configuration
mise run update-http                        # pull images + apply the HTTP-only configuration
mise run certificates:generate              # generate the wildcard cert via mkcert (skips if already present)
mise run certificates:verify                # verify the configured cert/key: expiry, SAN, pairing, chain, permissions
mise run certificates:import-from-image     # import a cert/key pair from a container image without starting it
mise run certificates:replace-ca            # untrust old Windows CA, replace it, and trust the new CA
mise run certificates:trust-ca              # import CA into Windows CurrentUser trust store (WSL2 -> Windows)
mise run certificates:untrust-ca            # remove dev CA from Windows CurrentUser trust store
mise run demo                               # start whoami test service at https://demo.localtest.me
mise run demo-http                          # start whoami test service at http://demo.localtest.me
mise run demo-down                          # stop the whoami test service
mise run config                             # validate docker-compose.yml
mise run validate                           # run pre-commit hooks + validate all compose configs
mise run smoke                              # live HTTPS/HTTP transition and custom-port checks
mise run smoke-fallback                     # live hostname-fallback resolution-order checks
mise run network                            # list containers currently on proxy
```

The smoke task uses loopback ports `18080`/`18443`, a disposable network, and
cleans up afterward. It refuses to run while the normal proxy or demo
containers exist.
