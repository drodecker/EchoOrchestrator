# EchoOrchestrator

Canonical deployment/orchestration project for the Echo stack.

## Configuration

Each Echo service reads its settings from **`echo_tbl_Settings` in the Echo
database** — see EchoDatabase `init/009_settings.sql`. Rows are keyed by
`sApp`: `'*'` is read by every Echo app, `'web'` / `'service'` / `'media'` by
one, and an app's own row wins over the general one. Adding an app-specific
setting is a row, never a new table.

The compose files therefore pass each service only what cannot describe
itself:

| Passed | Why |
| --- | --- |
| `DB_HOST` / `DB_USER` / `DB_PASSWORD` / `DB_NAME` | Where `echo_tbl_Settings` lives |
| `NOCODB_BASE_URL` / `NOCODB_API_TOKEN` | Where `trustedCIDR` lives (below) |
| `MYSQL_*` (database service only) | The container configures itself; it cannot read its own credentials out of a table it is hosting |

**`trustedCIDR` is the one setting read from outside the Echo database.** It
is platform-wide network policy that the identity service and every
application have to agree on, so it is spelled once — in the NocoDB base
`IdentityBase`, table `auth_tbl_Settings` — rather than as a differently
named CIDR per service. That base is found by *name* at runtime, never by an
ID from a config file. Enforce the same value at the NPM/openresty edge.

A settings change reaches every running service within 30 seconds, with no
restart and no redeploy. A service that cannot read its settings retries once
at startup and then exits saying so; there is no fallback to defaults.

## Stack

- EchoWeb
- EchoService
- EchoDatabase
- EchoMedia

## Production model

On `proxy.wisp.net`, the canonical edge model is:

- **Nginx Proxy Manager/openresty** owns the public Echo hostnames and TLS termination
- **EchoOrchestrator** runs the containers on the shared `echo-net` Docker network so NPM can proxy directly to service names
- Localhost-only published ports remain useful for direct service checks and fallback/debugging

## Hostname mapping

- `echo.wisp.net` → NPM/openresty → `echo-web:3160`
- `io.echo.wisp.net` → NPM/openresty → `echo-service:8080`
- `media.echo.wisp.net` → NPM/openresty → `echo-media:8082`

## Docker networks

- `echo-net` → shared internal Echo service network
- `dokku_network` → optional external/public integration network

## Volumes

Production uses external Docker volumes:

- DB volume: `echomessagingservice_echo_database_data`
- Media volume: `echo_media_data`

## Production compose

Use:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

## NPM configs

Live NPM proxy-host records on `proxy.wisp.net` should be the source of truth for the Echo edge.

- `echo.wisp.net` uses Let's Encrypt cert id/path `npm-9`
- `io.echo.wisp.net` uses Let's Encrypt cert id/path `npm-11`
- `media.echo.wisp.net` uses Let's Encrypt cert id/path `npm-12`

The files under `deploy/nginx/` are historical/fallback references only; do not treat them as the canonical production edge unless NPM is intentionally bypassed.

## Deployment portability notes

For a second server with different root URL structure:

- update the public hostnames
- update `MEDIA_BASE_URL`
- create/update NPM proxy hosts and attach certificates for that environment
- keep the localhost proxy-port pattern for service checks unless there is a reason to change it
- preserve external volume strategy if you want durable DB/media state
