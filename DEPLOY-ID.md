# Deploying the `id` identity processor

Runbook for standing up the domain-wide sign-in layer: the `id` app at
`id.<parent-domain>` (X.TLD), NocoDB at `nocodb.<parent-domain>`, and the
switch of EchoWeb to delegated login. Written to be followed top to bottom.

**Read this first:** EchoWeb stops doing OAuth itself. Existing Echo logins
break deliberately — identities are not migrated; accounts re-bind on the
first sign-in through `id` (matched by UISP clientId or CRM contact email).
Do this in a maintenance window.

The moving parts:

- **`id-web`** (sibling repo `../id`) — all OAuth (Google, Microsoft, UISP
  bridge), domain-wide SSO cookie on `.X.TLD`, sessions that persist until
  revoked, Super System Admin console at `/admin`.
- **`nocodb`** — the settings store. Every application-level setting
  (provider credentials, UISP integration, URLs, the app↔id exchange
  secret) lives in the `oAuthConfig` table of base `id`. The **only**
  auth-related values left in `.env` are the NocoDB coordinates.
- **`echo-web`** — redirects visitors to `id/authorize`, redeems the
  returned one-time code, and keeps only org/membership logic.

---

## 0. Preconditions

- [ ] Sibling checkout of the `id` repo next to the others
      (`../EchoDatabase ../EchoWeb ../id …`).
- [ ] TLS-terminated hostnames for `id.<domain>` and `nocodb.<domain>`
      (NPM proxy hosts → `id-web:3200` / `nocodb:8080`, or the localhost
      ports `13200` / `18090` on prod). Cookies are `Secure`; nothing signs
      in over plain HTTP.
- [ ] A database backup (`mysqldump`) — step 2 alters `echo_db`.

## 1. Databases

Fresh installs get everything from `EchoDatabase/init` automatically. An
**existing** deployment runs the new scripts manually, in order:

```bash
docker exec -i echo-database sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' <<'SQL'
CREATE DATABASE IF NOT EXISTS id_db     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS nocodb_db CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
GRANT ALL PRIVILEGES ON id_db.*     TO 'echo_app'@'%';
GRANT ALL PRIVILEGES ON nocodb_db.* TO 'echo_app'@'%';
FLUSH PRIVILEGES;
SQL

# id_db tables (also created idempotently by id-web at boot):
docker exec -i echo-database sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  < ../EchoDatabase/init/010_id_schema.sql
```

## 2. Migrate echo_db (breaking)

```bash
docker exec -i echo-database sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  < ../EchoDatabase/init/011_echoweb_identity_to_id.sql
```

This adds `auth_tbl_User.iIdUserId`, makes Echo sessions non-expiring
(revocation-only), and drops `auth_tbl_Identity` / `auth_tbl_SsoNonce`.

## 3. Environment

In `EchoOrchestrator/.env`:

```bash
# NEW — NocoDB
NOCODB_PUBLIC_URL=https://nocodb.<domain>
NOCODB_API_TOKEN=            # filled in at step 5

# REMOVE — these now live in the oAuthConfig table, not the environment:
#   GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
#   MICROSOFT_CLIENT_ID / MICROSOFT_CLIENT_SECRET / MICROSOFT_TENANT
#   UISP_SSO_SECRET / UISP_PLUGIN_URL / UISP_BASE_URL / UISP_CRM_APP_KEY_READ
```

`APP_BASE_URL` stays: it is EchoWeb's own public URL.

## 4. Bring the stack up

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

`id-web` will log a NocoDB bootstrap warning until step 5 — expected.

## 5. NocoDB admin + API token

1. Open `https://nocodb.<domain>`, create the admin account.
2. Account menu → **Tokens** → create a token.
3. Put it in `.env` as `NOCODB_API_TOKEN`, then
   `docker compose up -d id-web echo-web` (recreates with the token).
   `id-web` now creates base `id` with the `oAuthConfig` table and seeds
   every known key with a description.

## 6. Claim the instance (first-run wizard)

Open `https://id.<domain>` — while no provider is configured it redirects
to **/setup**:

1. Enter the **application domain** (X.TLD) — where the apps are served.
   This becomes the SSO cookie scope and the redirect allowlist.
2. Pick Google or Microsoft and paste that provider's client credentials
   (register the shown callback URL with the provider first; Microsoft
   additionally needs the directory/tenant ID — `common` cannot prove a
   domain).
3. The wizard runs a real sign-in against those credentials. If it works
   and your verified account is on the Super Admin domain, everything is
   saved to `oAuthConfig` (including a generated `ID_CLIENT_SECRET`) and you
   land on `/admin` as Super System Admin. Nothing is saved otherwise.
4. **If your identity domain differs from your application domain**, the
   wizard says so and offers the right value. This is the norm with a Google
   Workspace **domain alias**: apps at `example.ai`, Workspace primary
   `example.com`, and Google always asserts the primary — never the alias.
   Confirm, and it re-runs the sign-in with `SUPERADMIN_DOMAIN=example.com`
   in place. (`SUPERADMIN_DOMAIN` accepts a comma-separated list if more
   than one domain should qualify.)

From `/admin` (or the NocoDB UI) fill in the rest: the second provider,
`UISP_BASE_URL`, `UISP_CRM_APP_KEY_READ`, `UISP_SSO_SECRET`,
`DEFAULT_REDIRECT_URI` (usually `https://echo.<domain>/auth/callback`).

**A login method appears on id's sign-in page only when all of its keys are
set** — an unconfigured provider simply isn't offered.

## 7. UISP plugin

Re-upload the bumped plugin (its config key changed):

1. CRM → System → Plugins → upload the new `echo-sso-plugin.zip`.
2. Set **Identity (id) Base URL** = `https://id.<domain>` and the shared
   secret = `UISP_SSO_SECRET` from `oAuthConfig`.
3. Copy the "Plugin public URL" into `oAuthConfig.UISP_PLUGIN_URL`.

## 7b. Confirm the apps are listening

Each app keeps its **own** session, independent of id's. Revoking a login at
id therefore only stops *new* sign-ins unless the app is told — so an app
that is not listening is a real (and silent) offboarding hole.

Apps handle this themselves: on boot each one registers its receiver with
id and gets back the secret that signs deliveries. Nothing to configure —
but do confirm it happened.

- [ ] Open `id/admin` → **Application integrations**. Every app that signs
      users in should read **listening**.
- [ ] An app showing **not integrated** redeems logins but never registered
      a receiver — id spots this on its own from the token exchange, so the
      row appearing at all means the app is live and deaf. Deploy the
      receiver and restart it.
- [ ] **Not listening** means deliveries are erroring; the row shows the
      last error. **Send test event** re-tests on demand.

The same panel shows the integration contract for anything new you build
under the domain.

## 8. Verify

- [ ] `https://id.<domain>/healthz` and `https://echo.<domain>/healthz` OK.
- [ ] Visiting Echo signed-out bounces through `id` and back.
- [ ] The id login page shows exactly the configured methods.
- [ ] A CRM-known Google account lands in its org; the UISP portal button
      lands its client in Echo.
- [ ] A `<domain>` Google account reaches `/internal` on Echo and `/admin`
      on id.
- [ ] Sign-out in Echo ends the id session too (next visit shows the login
      page, not a silent re-login).
- [ ] Revoking a session from id `/admin` actually ends it **in Echo too** —
      revoke, then reload Echo: it should send you back through sign-in. If
      Echo stays logged in, its receiver is not working; check the
      integration panel (step 7b).
- [ ] `id/admin` → **Application integrations** shows every app as
      *listening*.

## Notes

- **Sessions never expire.** Logins persist until revoked — logout,
  "sign out everywhere", or an admin revocation. Revocations reach the apps
  as signed webhooks; an app that was down catches up from id's event log at
  boot, so no app needs a cron job.
- **Duplicate people** (one person as two id users — came through the ISP
  bridge, later signed in with Google) are repaired with **Merge into…** in
  `id/admin`: login methods move, the retired user's sessions end, and the
  apps repoint their own mapping automatically.
- Any new app under X.TLD gets sign-in with no registration: redirect to
  `id/authorize` with its callback as `redirect_uri`, then redeem the code
  at `POST id/api/token` with `ID_CLIENT_SECRET` from `oAuthConfig`.
