#!/usr/bin/env python3
"""Behavioral checks for fail-closed release source binding."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_SCRIPT = ROOT / "scripts" / "package-release.sh"
EXPECTED_ERROR = "Release packaging requires a clean source worktree"


def run(command: list[str], *, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def make_repository(parent: Path) -> Path:
    repository = parent / "candidate"
    scripts = repository / "scripts"
    scripts.mkdir(parents=True)
    shutil.copy2(PACKAGE_SCRIPT, scripts / "package-release.sh")
    (repository / "tracked.txt").write_text("committed\n", encoding="utf-8")
    for command in (
        ["git", "init", "-q"],
        ["git", "config", "user.name", "Hypha Release Test"],
        ["git", "config", "user.email", "release-test@users.noreply.github.com"],
        ["git", "add", "scripts/package-release.sh", "tracked.txt"],
        ["git", "commit", "-q", "-m", "fixture"],
    ):
        result = run(command, cwd=repository)
        assert result.returncode == 0, result.stderr
    return repository


def assert_dirty_tree_rejected(kind: str) -> None:
    with tempfile.TemporaryDirectory(prefix=f"hypha-release-{kind}-") as directory:
        parent = Path(directory)
        repository = make_repository(parent)
        if kind == "tracked":
            (repository / "tracked.txt").write_text("modified\n", encoding="utf-8")
        else:
            (repository / "untracked.txt").write_text("new\n", encoding="utf-8")
        result = run(
            [
                "/bin/bash",
                "scripts/package-release.sh",
                "v0.2.0",
                str(parent / "output"),
            ],
            cwd=repository,
        )
        assert result.returncode == 1
        assert EXPECTED_ERROR in result.stderr


def main() -> None:
    assert_dirty_tree_rejected("tracked")
    assert_dirty_tree_rejected("untracked")
    print("release package source-binding tests passed")


if __name__ == "__main__":
    main()
