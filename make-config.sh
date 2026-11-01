#!/usr/bin/env bash
# Generate the bridge's private config without changing Hermes configuration.
set -euo pipefail
cd "$(dirname "$0")"

# Optional acknowledgement settings are local opt-in values only.
if [ -f .env ]; then set -a; . ./.env; set +a; fi

ROUTE_FILE="${HERMES_HOME:-$HOME/.hermes}/webhook_subscriptions.json"
if [ ! -r "$ROUTE_FILE" ]; then
  echo "Hermes webhook subscriptions not found: $ROUTE_FILE" >&2
  exit 1
fi

ROUTE_SECRET="$(ROUTE_FILE="$ROUTE_FILE" python3 - <<'PY'
import json
import os
from pathlib import Path

try:
    route = json.loads(Path(os.environ["ROUTE_FILE"]).read_text())["pebble"]
    secret = route["secret"]
except (OSError, ValueError, KeyError, TypeError) as exc:
    raise SystemExit(f"Unable to read the Hermes 'pebble' route: {exc}")
if not isinstance(secret, str) or not secret:
    raise SystemExit("Hermes 'pebble' route has no secret")
print(secret)
PY
)"

# Preserve Pebble credentials across deployments so the app does not need reconfiguration.
PEBBLE_BEARER_TOKEN=""
PEBBLE_SIGNING_SECRET=""
if [ -f config.yaml ]; then
  bearer_line="$(grep -E '^  bearer_token: ' config.yaml | head -n 1 || true)"
  signing_line="$(grep -E '^  signing_secret: ' config.yaml | head -n 1 || true)"
  if [ -n "$bearer_line" ]; then
    PEBBLE_BEARER_TOKEN="${bearer_line#*: }"
    PEBBLE_BEARER_TOKEN="${PEBBLE_BEARER_TOKEN#\"}"
    PEBBLE_BEARER_TOKEN="${PEBBLE_BEARER_TOKEN%\"}"
  fi
  if [ -n "$signing_line" ]; then
    PEBBLE_SIGNING_SECRET="${signing_line#*: }"
    PEBBLE_SIGNING_SECRET="${PEBBLE_SIGNING_SECRET#\"}"
    PEBBLE_SIGNING_SECRET="${PEBBLE_SIGNING_SECRET%\"}"
  fi
fi
if [ -z "$PEBBLE_BEARER_TOKEN" ]; then
  PEBBLE_BEARER_TOKEN="$(openssl rand -hex 24)"
fi
PEBBLE_SIGNING_SECRET_YAML=""
if [ -n "$PEBBLE_SIGNING_SECRET" ]; then
  PEBBLE_SIGNING_SECRET_YAML="  signing_secret: \"${PEBBLE_SIGNING_SECRET}\""
fi
ACK_CHAT_ID="${ACK_CHAT_ID:-}"
cat > config.yaml <<EOF
pebble:
  bearer_token: "${PEBBLE_BEARER_TOKEN}"
${PEBBLE_SIGNING_SECRET_YAML}
  max_body_size: 5242880
  max_timestamp_age: 300
hermes:
  route_secret: "${ROUTE_SECRET}"
  url: "http://127.0.0.1:8644/webhooks/pebble"
listen:
  host: "127.0.0.1"
  port: 8645
whatsapp:
  ack_chat_id: "${ACK_CHAT_ID}"
  ack_bridge_port: 3000
  ack_emoji: "🪨"
log_level: "INFO"
EOF
chmod 600 config.yaml
echo "config.yaml written (600 perms); WhatsApp acknowledgements are disabled unless ACK_CHAT_ID is set."
