This directory is for local, generated TLS assets used by Traefik during development.

Tracked in Git:

- `README.md`

Generated locally and gitignored:

- `ca.crt`
- `ca.key`
- `localtest.me.crt`
- `localtest.me.key`
- any other generated certs, CSRs, or private keys

To regenerate the local CA and wildcard certificate:

```bash
./scripts/generate-dev-certs.sh --force
```

After regenerating, re-import `ca.crt` into Windows Trusted Root Certification Authorities.
