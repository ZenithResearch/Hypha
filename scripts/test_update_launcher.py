#!/usr/bin/env python3
"""Behavior checks for the external Terminal updater launcher."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "scripts" / "launch-update-from-main.command"


def run_case(exit_code: int) -> tuple[subprocess.CompletedProcess[str], Path, str]:
    with tempfile.TemporaryDirectory(prefix="hypha-update-launcher-") as temporary:
        app = Path(temporary) / "Hypha.app"
        resources = app / "Contents" / "Resources"
        resources.mkdir(parents=True)
        launcher = resources / LAUNCHER.name
        shutil.copy2(LAUNCHER, launcher)
        launcher.chmod(0o755)

        updater = resources / "update-from-main.sh"
        updater.write_text(
            "#!/bin/zsh\n"
            "print -r -- \"$1\" > \"$(dirname \"$0\")/invoked-app-path\"\n"
            "exit \"${HYPHA_FAKE_UPDATE_EXIT:?}\"\n"
        )
        updater.chmod(0o755)

        environment = os.environ.copy()
        environment["HYPHA_FAKE_UPDATE_EXIT"] = str(exit_code)
        result = subprocess.run(
            [str(launcher)],
            text=True,
            capture_output=True,
            check=False,
            env=environment,
            timeout=15,
        )
        invoked_path = (resources / "invoked-app-path").read_text().strip()
        return result, app, invoked_path


def main() -> None:
    if not LAUNCHER.is_file():
        raise AssertionError(f"missing updater launcher: {LAUNCHER}")

    success, success_app, success_path = run_case(0)
    assert success.returncode == 0, success.stderr
    assert success_path == str(success_app.resolve())
    assert "Update installed from GitHub main" in success.stdout

    failure, failure_app, failure_path = run_case(23)
    assert failure.returncode == 23
    assert failure_path == str(failure_app.resolve())
    assert "Update failed with exit status 23" in failure.stderr

    print("update launcher tests passed")


if __name__ == "__main__":
    main()
