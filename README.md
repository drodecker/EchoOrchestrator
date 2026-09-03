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
| `MYSQL_*` (database service only) | The container configures itself; it cannot read its own credentials out of a table it is hosting |

That is the whole list, and there is deliberately **no `NOCODB_*`** in this
repo's `.env`.

**`trustedCIDR` is the one setting read from outside the Echo database.** It
is platform-wide network policy that the identity service and every
application have to agree on, so it is spelled once — in the NocoDB base
`IdentityBase`, table `auth_tbl_Settings` — rather than as a differently
named CIDR per service. That base is found by *name* at runtime, never by an
ID from a config file. Enforce the same value at the NPM/openresty edge.

Only **EchoService** reads it, to decide which callers may reach the webhook
endpoints without basic auth. EchoWeb used to fetch it and never look at it,
which made a NocoDB token a hard requirement for starting; it no longer does
(EchoWeb#17), so EchoWeb needs nothing but a database.

### How EchoService finds NocoDB

Not from this `.env`. The identity service already keeps those two keys in
`config.json` on its own volume, written by its `/setup` wizard — so that
volume is mounted here read-only and EchoService reads the same file:

```yaml
volumes:
  identity-config:
    external: true
    name: ${IDENTITY_CONFIG_VOLUME:-identity_identity-config}
```

Set up identity and Echo follows. Nothing to copy, and one place for the token
rather than two.

Two things this depends on:

- **Order.** The volume is declared `external`, so bringing this stack up
  before identity fails immediately and says so — which beats inventing a
  configuration. Bring up identity, finish its `/setup`, then bring up Echo.
- **uid 100.** identity writes that file mode 0600 as uid 100, so the reader
  has to *be* uid 100. It is pinned with `adduser -u 100` in identity,
  EchoService and EchoWeb — a platform invariant, not the coincidence it was
  when each image independently ran `adduser -S`.

For an EchoService on a *different* host there is no volume to share, so it
falls back to its own first-run wizard at `/setup`, which asks for the same two
values. This stack does not try to solve that case; it makes the local one need
no solving.

## Schema migrations

`../EchoDatabase/init` is mounted into the database container at
`/docker-entrypoint-initdb.d`, which MySQL runs **only when initialising an
empty data directory**. Files added after the first `up` are silently skipped —
which is how `009_settings.sql` sat in the repo while a running database had no
`echo_tbl_Settings`.

So a one-shot `echo-migrate` service applies the same files, in order, against
the database as it actually is, recording each in `echo_tbl_SchemaMigration`.
`echo-service` and `echo-web` wait on it completing.

The schema files are **not** idempotent — 006/007/008 are bare `ALTER TABLE ...
ADD COLUMN`, and 001/003 seed lookup tables with bare `INSERT`. The ledger is
the entire safety mechanism: each file runs exactly once. A database that
already has the schema but no ledger is therefore **baselined** — every current
file recorded as applied without being run, loudly, once — because initdb
already ran them and there is no way to ask MySQL which.

## First install

```bash
scripts/install.sh          # generates .env with database passwords, once
# bring up identity and complete its /setup wizard
docker compose up -d --build
```

`install.sh` never overwrites an existing `.env`: the passwords in it are what
the database volume was initialised with.

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
