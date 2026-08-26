# EchoOrchestrator

Canonical deployment/orchestration project for the Echo stack.

## Stack

- id — OAuth identity processor for every app under the parent domain (sibling repo `../id`)
- NocoDB — settings store; home of the shared `oAuthConfig` table
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

- `id.wisp.net` → NPM/openresty → `id-web:3200`
- `nocodb.wisp.net` → NPM/openresty → `nocodb:8080`
- `echo.wisp.net` → NPM/openresty → `echo-web:3160`
- `io.echo.wisp.net` → NPM/openresty → `echo-service:8080`
- `media.echo.wisp.net` → NPM/openresty → `echo-media:8082`

Sign-in for every app under the parent domain happens on `id.wisp.net`; see
`DEPLOY-ID.md` for the bootstrap runbook (NocoDB token, first-run setup
wizard, UISP plugin retarget).

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
