# EchoOrchestrator

Canonical deployment/orchestration project for the Echo stack.

## Configuration

Every service in this stack reads its settings from the NocoDB base
**`IdentityBase`**, table **`auth_tbl_Settings`** — see
localsplash/identity#15 for the platform standard. The compose files pass each
service only `NOCODB_BASE_URL` and `NOCODB_API_TOKEN`; the OAuth and UISP
credentials, the database coordinates the applications connect with, the
public URLs and `trustedCIDR` are rows in that table.

- **One base per repository**, named `{Repo}Base`. The name is unique by our
  convention — NocoDB does not enforce it, we do — so services find the base
  ID from the name at runtime rather than carrying an ID that survives a
  rename and outlives a restore.
- **`trustedCIDR` is one value for the whole platform**, not a differently
  named CIDR per service. It describes the network the servers sit on: every
  first-party service inside it is trusted, nothing outside it is. Enforce the
  same value at the NPM/openresty edge.
- **A change reaches every running service within 30 seconds**, with no
  restart — values and the resolved base/table IDs share one cache clock.
- **Failure is loud**: a service that cannot find `IdentityBase` retries once
  at startup and then exits saying so.

The MySQL container keeps `MYSQL_ROOT_PASSWORD` / `MYSQL_USER` /
`MYSQL_PASSWORD` in the `.env` — it cannot read its own credentials out of a
table it is hosting.

The identity service (`identity.X.TLD`, sibling repo `../identity`) owns
`IdentityBase`: it creates and seeds the base on first boot, and its first-run
wizard is the intended way to fill the rows in.

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
