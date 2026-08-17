# client-zone.js tests

Runs the plugin's injected script against a real DOM (jsdom) in a container, so
no host install is needed:

```bash
cd /opt/echo/EchoOrchestrator/uisp-plugin/tests
docker run --rm -v "$PWD":/w -v /opt/echo:/opt/echo:ro -w /w node:20-alpine \
  sh -c 'npm install jsdom --silent >/dev/null 2>&1 && node client-zone.test.js'
```

Covers the SSO auto-return (including the redirect-loop guard and the
same-origin refusal) and the menu icon decoration (href and label matching,
active state, idempotency, and that it never alters the link itself).

`tests/` is excluded from the plugin ZIP.
