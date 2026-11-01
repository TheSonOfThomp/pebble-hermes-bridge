#!/usr/bin/env bash
# Stage and install the Index 01 adapter as a launchd user service on macOS.
# Keeping the runtime outside Documents avoids TCC restrictions on LaunchAgents.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$HOME/.local/share/index01-adapter"
PYTHON_BIN="${PYTHON_BIN:-/opt/homebrew/bin/python3.11}"
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.index01-adapter.plist"

if [ ! -x "$PYTHON_BIN" ]; then
  echo "Python 3.11+ not found at $PYTHON_BIN; set PYTHON_BIN to a supported interpreter." >&2
  exit 1
fi

mkdir -p "$RUNTIME_DIR" "$HOME/Library/Logs/index01-adapter"
rsync -a --delete \
  --exclude .git --exclude .venv --exclude __pycache__ \
  --exclude config.yaml --exclude .env \
  "$SOURCE_DIR/" "$RUNTIME_DIR/"

if [ ! -x "$RUNTIME_DIR/.venv/bin/python" ]; then
  "$PYTHON_BIN" -m venv "$RUNTIME_DIR/.venv"
fi
"$RUNTIME_DIR/.venv/bin/pip" install --quiet --editable "$RUNTIME_DIR"
(
  cd "$RUNTIME_DIR"
  ./make-config.sh
)

python3 - "$RUNTIME_DIR" "$HOME" <<'PY'
from pathlib import Path
import sys

runtime, home = map(Path, sys.argv[1:])
template = (runtime / "com.user.index01-adapter.plist").read_text()
plist = template.replace("__INSTALL_DIR__", str(runtime)).replace("__HOME__", str(home))
(home / "Library/LaunchAgents/com.user.index01-adapter.plist").write_text(plist)
PY

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"
sleep 2
if curl --fail --silent --max-time 5 http://127.0.0.1:8645/healthz >/dev/null; then
  echo "adapter listening on 127.0.0.1:8645"
else
  echo "adapter failed to start; check ~/Library/Logs/index01-adapter/err.log" >&2
  exit 1
fi
