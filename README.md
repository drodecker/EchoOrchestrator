# EchoOrchestrator

Canonical deployment/orchestration project for the Echo stack.

## Stack

- EchoWeb
- EchoService
- EchoDatabase
- EchoMedia

## Production model

On `proxy.wisp.net`, the canonical edge model is:

- **host nginx** terminates TLS and owns the public Echo hostnames
- **EchoOrchestrator** runs the containers and publishes localhost-only ports for nginx to proxy to
- **NPM/openresty is not the preferred Echo edge path**

## Hostname mapping

- `echo.wisp.net` → host nginx → `127.0.0.1:13160` → `echo-web`
- `io.echo.wisp.net` → host nginx → `127.0.0.1:18080` → `echo-service`
- `media.echo.wisp.net` → host nginx → `127.0.0.1:18082` → `echo-media`

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

## Nginx configs

Working host-nginx configs from `proxy.wisp.net` are stored in:

- `deploy/nginx/echo.wisp.net.conf`
- `deploy/nginx/io.echo.wisp.net.conf`
- `deploy/nginx/media.echo.wisp.net.conf`

These are the current known-good reference configs for the live server.

## Certificate notes

Current live certificate paths on `proxy.wisp.net` reference the existing Let's Encrypt material under:

- `/opt/nginx-proxy-manager/letsencrypt/live/npm-9/` for `echo.wisp.net`
- `/opt/nginx-proxy-manager/letsencrypt/live/npm-11/` for `io.echo.wisp.net`
- `/opt/nginx-proxy-manager/letsencrypt/live/npm-12/` for `media.echo.wisp.net`

For another server, do **not** assume those exact `npm-*` paths. Re-issue/attach certificates for that environment and update the nginx config paths accordingly.

## Deployment portability notes

For a second server with different root URL structure:

- update the public hostnames
- update `MEDIA_BASE_URL`
- update host nginx server blocks
- keep the localhost proxy-port pattern unless there is a reason to change it
- preserve external volume strategy if you want durable DB/media state
