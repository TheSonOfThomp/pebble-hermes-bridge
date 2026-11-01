# pebble-hermes-bridge

A narrow relay from a Pebble Index 01 webhook to a Hermes Generic V2 route.

The relay verifies the Pebble request, discards audio, forwards only the transcription
and event metadata to Hermes, and returns Hermes's HTTP status to the Pebble app.
It does not route messages, edit Hermes configuration, trigger phone actions, or use
WhatsApp unless an acknowledgement destination is explicitly configured.

## Flow

```
Pebble app ──HTTPS──> Caddy / Cloudflare Tunnel ──> relay :8645 ──> Hermes :8644/webhooks/pebble ──> Discord
```

The relay listens on `127.0.0.1:8645`. Publish only its `/pebble-index-01` route
through the existing Caddy reverse proxy or a Cloudflare Tunnel; never expose Hermes port `8644`.

## Requirements

- Python 3.11 or newer
- A running Hermes gateway with its existing dynamic `pebble` webhook subscription
- A public HTTPS route through Caddy or Cloudflare Tunnel
- A configured Hermes Discord delivery target

## Install

```bash
git clone https://github.com/TheSonOfThomp/pebble-hermes-bridge.git
cd pebble-hermes-bridge
python3.11 -m venv .venv
.venv/bin/pip install -e '.[test]'
./make-config.sh
./install.sh
```

`make-config.sh` reads the local secret for the existing dynamic Hermes route named
`pebble` from `${HERMES_HOME:-~/.hermes}/webhook_subscriptions.json`. It writes a
private `config.yaml` (`0600`) containing that route secret and a newly generated
Pebble bearer token. It never modifies `~/.hermes/config.yaml`.

`install.sh` stages a runnable copy under `~/.local/share/index01-adapter/` and creates its
Python 3.11 virtual environment there. The launchd process runs only that staged copy; the
Git checkout can remain in `~/Documents/GitHub` without requiring Files & Folders or Full Disk
Access permissions. Each rerun refreshes the staged code while preserving its private
`config.yaml`, including the Pebble bearer token.

The default outbound Hermes endpoint is:

```
http://127.0.0.1:8644/webhooks/pebble
```

## Public ingress

Add one HTTPS reverse-proxy route for the relay, for example with Caddy on the same host:

```caddyfile
pebble.example.com {
    handle /pebble-index-01 {
        reverse_proxy 127.0.0.1:8645
    }
    respond 404
}
```

Point Pebble at `https://pebble.example.com/pebble-index-01`. Do not proxy `/healthz` or
any Hermes endpoint. A Cloudflare Tunnel may target the same loopback relay instead.

Use the generated Pebble bearer token from `config.yaml` as the Pebble app's
`Authorization` header value: `Bearer <token>`. With Pebble signing enabled, also configure its
signing secret in the bridge's private config.

## Hermes delivery

Configure the existing dynamic `pebble` route in Hermes to deliver to Discord. Its
prompt should reference the relay payload field named `transcription`, for example:

```text
Pebble voice note (untrusted data): {transcription}
```

The relay signs Generic V2 requests using `X-Webhook-Timestamp` and
`X-Webhook-Signature-V2` and includes the Pebble delivery identifier in
`X-Request-ID`.

## Optional WhatsApp acknowledgement

WhatsApp acknowledgement is disabled by default. To enable it, create a git-ignored
`.env` containing an explicit destination:

```bash
ACK_CHAT_ID=123456789@g.us
```

Then rerun `./make-config.sh`. The acknowledgement is best effort and uses the
local Baileys bridge only after a successful Hermes response.

## Security and behavior

- Pebble HMAC verification covers the exact raw multipart body and uses a
  constant-time comparison.
- When Pebble signing is off, the relay accepts only the configured bearer token.
- Multipart file/audio parts are discarded; only the `transcription` text part is
  forwarded.
- `/healthz` returns `{"status":"ok"}`.
- Oversized, malformed, stale, or unauthenticated requests are rejected.

## Verify a deployment

The launchd service exposes a local health check:

```bash
curl --fail http://127.0.0.1:8645/healthz
launchctl print gui/$(id -u)/com.user.index01-adapter
```

For a real ring test, make a harmless recording such as `Reply with Pebble relay test received.`
The adapter writes structured request logs to:

```text
~/Library/Logs/index01-adapter/err.log
```

A successful request includes `forwarded to Hermes` and a `hermes_status` of `200` or `202`.
A `403 signature verification failed` means the signing secret configured in Pebble does not match
`pebble.signing_secret` in the staged private config. A `403 unsigned request requires a matching
Authorization header` means the bearer header is missing or wrong.

## Test

```bash
.venv/bin/python -m pytest -q
```