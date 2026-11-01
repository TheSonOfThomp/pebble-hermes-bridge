from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def test_editable_install_imports_adapter_outside_checkout(tmp_path: Path) -> None:
    result = subprocess.run(
        [sys.executable, "-c", "import adapter; print(adapter.Config.__name__)"],
        cwd=tmp_path,
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "Config"
