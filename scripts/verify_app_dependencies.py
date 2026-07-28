#!/usr/bin/env python3
import pathlib
import subprocess
import sys


def linked_dependencies(executable: pathlib.Path) -> list[str]:
    result = subprocess.run(
        ["otool", "-L", str(executable)],
        check=True,
        capture_output=True,
        text=True,
    )
    dependencies = []
    for line in result.stdout.splitlines()[1:]:
        candidate = line.strip().split(" (compatibility version", 1)[0]
        if candidate:
            dependencies.append(candidate)
    return dependencies


def resolves(dependency: str, executable: pathlib.Path, app: pathlib.Path) -> bool:
    if dependency.startswith(("/System/Library/", "/usr/lib/")):
        return True
    executable_dir = executable.parent
    replacements = {
        "@executable_path": executable_dir,
        "@loader_path": executable_dir,
    }
    for prefix, base in replacements.items():
        if dependency == prefix or dependency.startswith(prefix + "/"):
            suffix = dependency[len(prefix):].lstrip("/")
            return (base / suffix).exists()
    if dependency.startswith("@rpath/"):
        suffix = dependency[len("@rpath/"):]
        candidates = [
            executable_dir / suffix,
            app / "Contents" / "Frameworks" / suffix,
        ]
        return any(candidate.exists() for candidate in candidates)
    if dependency.startswith("/"):
        return pathlib.Path(dependency).exists()
    return False


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: verify_app_dependencies.py <executable> <app>", file=sys.stderr)
        return 2
    executable = pathlib.Path(sys.argv[1]).resolve()
    app = pathlib.Path(sys.argv[2]).resolve()
    missing = [
        dependency
        for dependency in linked_dependencies(executable)
        if not resolves(dependency, executable, app)
    ]
    if missing:
        print("unresolved non-system dynamic dependencies:", file=sys.stderr)
        for dependency in missing:
            print(f"- {dependency}", file=sys.stderr)
        return 1
    print(f"dependency audit passed: {executable}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
