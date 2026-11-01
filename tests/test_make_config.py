"""Installer configuration contract."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import yaml


REPO = Path(__file__).resolve().parent.parent


def test_make_config_uses_existing_pebble_route_and_generates_bearer(tmp_path: Path) -> None:
    """The bridge owns Pebble auth, while Hermes keeps owning its route secret."""
    checkout = tmp_path / "bridge"
    checkout.mkdir()
    shutil.copy2(REPO / "make-config.sh", checkout / "make-config.sh")
    (checkout / "make-config.sh").chmod(0o755)
    home = tmp_path / "home"
    hermes = home / ".hermes"
    hermes.mkdir(parents=True)
    (hermes / "webhook_subscriptions.json").write_text(
        json.dumps({"pebble": {"secret": "route-secret-from-hermes"}})
    )

    env = {**os.environ, "HOME": str(home)}
    env.pop("HERMES_HOME", None)
    subprocess.run(["bash", "./make-config.sh"], cwd=checkout, env=env, check=True)

    config = yaml.safe_load((checkout / "config.yaml").read_text())
    assert config["hermes"]["route_secret"] == "route-secret-from-hermes"
    assert config["hermes"]["url"] == "http://127.0.0.1:8644/webhooks/pebble"
    assert config["pebble"]["bearer_token"]
    assert config.get("whatsapp", {}).get("ack_chat_id") in (None, "")


def test_make_config_preserves_existing_pebble_bearer_token(tmp_path: Path) -> None:
    checkout = tmp_path / "bridge"
    checkout.mkdir()
    shutil.copy2(REPO / "make-config.sh", checkout / "make-config.sh")
    (checkout / "make-config.sh").chmod(0o755)
    home = tmp_path / "home"
    hermes = home / ".hermes"
    hermes.mkdir(parents=True)
    (hermes / "webhook_subscriptions.json").write_text(
        json.dumps({"pebble": {"secret": "route-secret-from-hermes"}})
    )
    existing = "keep-this-pebble-token"
    signing_secret = "keep-this-signing-secret"
    (checkout / "config.yaml").write_text(
        "pebble:\n  bearer_token: " + existing + "\n  signing_secret: " + signing_secret + "\n"
    )

    env = {**os.environ, "HOME": str(home)}
    env.pop("HERMES_HOME", None)
    subprocess.run(["bash", "./make-config.sh"], cwd=checkout, env=env, check=True)

    config = yaml.safe_load((checkout / "config.yaml").read_text())
    assert config["pebble"]["bearer_token"] == existing
    assert config["pebble"]["signing_secret"] == signing_secret
