#!/usr/bin/env python3
"""Fail-closed checks for Hypha's public-release licensing and workflow metadata."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
SECURITY_URL = "https://github.com/ZenithResearch/Hypha/security/advisories/new"
AGPL_SHA256 = "0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0"
SDK_SHA256 = "ca8796d0f065ade3787de2f18693afd940914ce2e35f807ccf479d2f14c5c565"
THIRD_PARTY_LICENSES_SHA256 = "f1e427b7af156b275595b0dbc78c0dcf1c85aee0240a9b92f856e07d5f55ed61"
LICENSE_INVENTORY_SHA256 = "898a66bde0576256aaec51d98f517484bed57e32600f676d7169f37944f68309"
THIRD_PARTY_NOTICES_SHA256 = "b6bed55f72684e47af3277525965bc2a5861ddf2b2754e5aebee376916b94c94"
PRIVATE_PATH_PREFIXES = ("/" + "Users/", "/" + "Volumes/" + "home/", "/" + "home/")
LICENSE_HASHES = {
    "0BSD": "e3f18c71e10d673590eb9856c1d79dd3b4b0d65404efb5e8584dbede7edd608b",
    "Apache-2.0": "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30",
    "BSD-2-Clause": "f32fb3b417a194167cfad068223fc975ba96c5960513a10f66a3c28720aec1df",
    "BSD-3-Clause": "5a93d5831e1297ab10fe643e1a631e83be392896da14ee2951285a79012df69d",
    "BSL-1.0": "84c6ef3ea9e3254a54d0acf5d3e0c61ae011b8fef7dd6940591cf060e6380a8f",
    "CC0-1.0": "a2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499",
    "ISC": "f2ec607f67bb0dd3053b49835b02110d5cd0f8eb6da3aac4dc0b142a6b299be9",
    "LLVM-exception": "e34c58338bd89d43e709e226610d8f32b3e3c47f4ad9a99a8dc1d4ac7842488e",
    "MIT-0": "59746d6285ffa44bfc7ecada352aa5d6a20dc8eab418a60ce091cc739012c135",
    "MIT": "b05785f9f18e6716bab63424b11454513b9943a222595b70411009202fc592b5",
    "MPL-2.0": "66a3107d5ad6a058aab753eaac2047ccb2ed0e39465dd0fe5844da3e300d5172",
    "Unicode-3.0": "f7db81051789b729fea528a63ec4c938fdcb93d9d61d97dc8cc2e9df6d47f2a1",
    "Unlicense": "0bdebfeda07d45dada625ae1317c6f833186e798b171d0db640bcf32e92a8240",
    "Zlib": "bfb1112d49db5b1daecdfef24bd7e2f3ea0bafb33aa67aa0ab51e2bf8407c03d",
    "zlib-acknowledgement": "aeb83cf7f4c9076691f72856d3b8f64a152027e9b1a136d399198c683fd26c12",
}
ALLOWED_SPDX_IDS = set(LICENSE_HASHES) | {"MPL-2.0-or-later"}
BINARY_HASHES = {
    "Resources/ZenithOSIcon.icns": "61ad8afdb2674ba035cdfbab4a850e327a872fbc1ba940c76469d0349d3e5342",
    "docs/evidence/issue-2/native-shell.png": "7e88b4366551f923c2e12b33eea737cef01558899484060b37a5ce2a37a0b84b",
    "Vendor/MatrixRustSDK/MatrixSDKFFI.xcframework.zip": SDK_SHA256,
}
CRITICAL_POLICY_HASHES = {
    ".github/workflows/ci.yml": "ba41a70428569a236439121277c2b725961fa8e8f04f7909bf23345fce1e8340",
    "SECURITY.md": "38c04ef47f90e68ef21eed3234f891b935caf5cf2386dd0f4737f922eaa17e37",
    "build-app.sh": "cf0fb549796569ca366080f42cac92b83ae9aeccf6bca686c29bd78d6b1452c0",
    "scripts/verify_app_licenses.py": "62cedfdd0c4590c79ec3d66d1f38fe61caee767403d5629c13107697190823ce",
    "scripts/generate_hypha_icon.py": "1925269ceb71635b9ad66a2ea8e7bafcce954b92f63ba68eace30e099f095342",
    "Resources/HyphaIconSource.svg": "3ed8f9878335d2cf9199577b0ec4dbf981a35d8195f8999b7fe16db6cfcfad92",
}
TEXT_SUFFIXES = {"", ".entitlements", ".hbs", ".html", ".json", ".md", ".plist", ".py", ".sh", ".svg", ".swift", ".toml", ".txt", ".yml", ".yaml"}
BINARY_MAGIC_PREFIXES = (b"PK\x03\x04", b"\x89PNG\r\n\x1a\n", b"icns", b"\x7fELF", b"%PDF", b"\x1f\x8b")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def file_bytes(path: str) -> bytes:
    return (ROOT / path).read_bytes()


def text(path: str) -> str:
    return file_bytes(path).decode("utf-8")


def sha256(path: str) -> str:
    return hashlib.sha256(file_bytes(path)).hexdigest()


def parse_workflow(path: Path) -> dict:
    ruby = (
        "require 'yaml'; require 'json'; "
        "data = YAML.safe_load(File.read(ARGV[0]), aliases: false); "
        "STDOUT.write(JSON.generate(data))"
    )
    result = subprocess.run(
        ["/usr/bin/ruby", "-e", ruby, str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    require(result.returncode == 0, f"workflow YAML parse failed: {path.name}")
    parsed = json.loads(result.stdout)
    require(isinstance(parsed, dict), f"workflow root is not a mapping: {path.name}")
    return parsed


def validate_permissions(value: object, boundary: str) -> None:
    if not isinstance(value, dict):
        raise SystemExit(f"permissions must be an explicit mapping: {boundary}")
    for permission, level in value.items():
        require(level in {"read", "none"}, f"write or invalid permission {permission}: {boundary}")


def validate_job(job: object, boundary: str) -> None:
    if not isinstance(job, dict):
        raise SystemExit(f"job is not a mapping: {boundary}")
    if "permissions" in job:
        validate_permissions(job["permissions"], boundary)
    reusable = job.get("uses")
    if reusable is not None:
        require(isinstance(reusable, str), f"reusable workflow reference is not text: {boundary}")
        require(not reusable.startswith("./"), f"local reusable workflows require explicit recursive policy support: {reusable}")
        require(re.fullmatch(r"[^@\s]+@[0-9a-f]{40}", reusable) is not None, f"mutable reusable workflow reference: {reusable}")
        require("secrets" not in job, f"reusable workflow secrets require explicit policy: {boundary}")
    for container_key in ("container", "services"):
        container = job.get(container_key)
        if container is None:
            continue
        containers = container.values() if isinstance(container, dict) and container_key == "services" else [container]
        for entry in containers:
            image = entry.get("image") if isinstance(entry, dict) else entry
            require(
                isinstance(image, str) and re.fullmatch(r"[^@\s]+@sha256:[0-9a-f]{64}", image) is not None,
                f"container image is not digest pinned: {boundary}",
            )
    steps = job.get("steps", [])
    if not isinstance(steps, list):
        raise SystemExit(f"job steps are not a list: {boundary}")
    for index, step in enumerate(steps):
        if not isinstance(step, dict):
            raise SystemExit(f"workflow step is not a mapping: {boundary}:{index}")
        uses = step.get("uses")
        if uses is None:
            continue
        require(isinstance(uses, str), f"action reference is not text: {boundary}:{index}")
        require(not uses.startswith("./"), f"local actions require explicit recursive policy support: {uses}")
        require(re.fullmatch(r"[^@\s]+@[0-9a-f]{40}", uses) is not None, f"mutable action reference: {uses}")


def normalize_cargo_license(raw: str) -> str:
    normalized = re.sub(r"\s*/\s*", " OR ", raw.strip())
    return normalized.replace("MPL-2.0+", "MPL-2.0-or-later")


def validate_spdx(expression: str) -> None:
    tokens = re.findall(r"\(|\)|AND|OR|WITH|[A-Za-z0-9.+-]+", expression)
    require(" ".join(tokens).replace("( ", "(").replace(" )", ")") != "", "empty SPDX expression")
    require("".join(tokens) == re.sub(r"\s+", "", expression), f"invalid SPDX characters: {expression}")
    index = 0

    def primary() -> None:
        nonlocal index
        require(index < len(tokens), f"truncated SPDX expression: {expression}")
        if tokens[index] == "(":
            index += 1
            parse_or()
            require(index < len(tokens) and tokens[index] == ")", f"unbalanced SPDX expression: {expression}")
            index += 1
        else:
            require(tokens[index] in ALLOWED_SPDX_IDS, f"unapproved SPDX identifier: {tokens[index]}")
            index += 1

    def parse_with() -> None:
        nonlocal index
        primary()
        if index < len(tokens) and tokens[index] == "WITH":
            index += 1
            require(index < len(tokens) and tokens[index] == "LLVM-exception", f"unsupported SPDX exception: {expression}")
            index += 1

    def parse_and() -> None:
        nonlocal index
        parse_with()
        while index < len(tokens) and tokens[index] == "AND":
            index += 1
            parse_with()

    def parse_or() -> None:
        nonlocal index
        parse_and()
        while index < len(tokens) and tokens[index] == "OR":
            index += 1
            parse_and()

    parse_or()
    require(index == len(tokens), f"invalid SPDX grammar: {expression}")


require(sha256("LICENSE") == AGPL_SHA256, "LICENSE is not the canonical AGPL-3.0 text")
readme = text("README.md")
contributing = text("CONTRIBUTING.md")
security = text("SECURITY.md")
notices = text("THIRD_PARTY_NOTICES.md")
licenses_html = text("THIRD_PARTY_LICENSES.html")
provenance = text("Vendor/MatrixRustSDK/PROVENANCE.md")
build_script = text("build-app.sh")
require("SPDX-License-Identifier: AGPL-3.0-or-later" in readme, "README SPDX declaration missing")
require("GNU AGPL v3 or later" in contributing, "contribution license missing")
require(SECURITY_URL in security and "attacker.invalid" not in security, "exact security-reporting URL missing")
require(SDK_SHA256 in notices and SDK_SHA256 in provenance, "SDK checksum missing")

for identifier, expected in LICENSE_HASHES.items():
    require(sha256(f"LICENSES/{identifier}.txt") == expected, f"license text mismatch: {identifier}")
for path, expected in CRITICAL_POLICY_HASHES.items():
    require(sha256(path) == expected, f"critical policy file changed without canonical review: {path}")

require(sha256("Vendor/MatrixRustSDK/license-inventory.json") == LICENSE_INVENTORY_SHA256, "canonical license inventory changed")
require(sha256("THIRD_PARTY_NOTICES.md") == THIRD_PARTY_NOTICES_SHA256, "third-party notices changed without inventory regeneration")
inventory = json.loads(text("Vendor/MatrixRustSDK/license-inventory.json"))
require(inventory.get("schema_version") == 1, "unsupported license inventory schema")
require(inventory.get("matrix_sdk_source_commit") == "f4889ec898e77d8b8c9013adadd77f3d0901fc2d", "license inventory source drift")
require(inventory.get("cargo_about_version") == "0.9.1", "license inventory generator drift")
require(inventory.get("target") == "aarch64-apple-darwin", "license inventory target drift")
expected_packages = inventory.get("packages")
require(isinstance(expected_packages, list) and inventory.get("package_count") == 507 and len(expected_packages) == 507, "canonical license inventory is incomplete")

row_pattern = re.compile(r"^\| `([^`]+)` \| `([^`]+)` \| `([^`]+)` \| `([^`]+)` \| (.+) \| \[source\]\((https://[^)]+)\) \|$")
rows = []
for line in notices.splitlines():
    if line.startswith("| `"):
        match = row_pattern.fullmatch(line)
        if match is None:
            raise SystemExit(f"invalid dependency row: {line[:100]}")
        name, version, raw_license, spdx, attribution, source = match.groups()
        rows.append({
            "name": name.replace("\\|", "|"),
            "version": version.replace("\\|", "|"),
            "raw_cargo_license": raw_license.replace("\\|", "|"),
            "normalized_spdx": spdx.replace("\\|", "|"),
            "package_metadata_attribution": attribution.replace("\\|", "|"),
            "immutable_source": source,
        })
require(rows == expected_packages, "notice table does not exactly match canonical cargo-about inventory")
require(len({(row["name"], row["version"]) for row in rows}) == 507, "duplicate dependency inventory row")
for row in rows:
    name = row["name"]
    version = row["version"]
    raw_license = row["raw_cargo_license"]
    spdx = row["normalized_spdx"]
    attribution = row["package_metadata_attribution"]
    source = row["immutable_source"]
    require(bool(attribution.strip()), f"package attribution missing: {name} {version}")
    require(normalize_cargo_license(raw_license) == spdx, f"license normalization mismatch: {name} {version}")
    validate_spdx(spdx)
    immutable_crate = source == f"https://crates.io/api/v1/crates/{quote(name, safe='')}/{quote(version, safe='')}/download"
    immutable_git = re.fullmatch(r"https://github\.com/[^/]+/[^/]+/commit/[0-9a-f]{40}", source) is not None
    require(immutable_crate or immutable_git, f"dependency source is not immutable: {name} {version}")

require(sha256("THIRD_PARTY_LICENSES.html") == THIRD_PARTY_LICENSES_SHA256, "generated package-specific attribution changed")
require("Copyright" in licenses_html, "generated package-specific attribution is missing")
html_packages = set(re.findall(r"<code>([^< ]+) ([^< ]+)</code>", licenses_html))
expected_package_ids = {(row["name"], row["version"]) for row in rows}
require(html_packages == expected_package_ids, "cargo-about attribution package set differs from canonical inventory")

workflow_paths = sorted((ROOT / ".github" / "workflows").glob("*.yml")) + sorted((ROOT / ".github" / "workflows").glob("*.yaml"))
require(bool(workflow_paths), "no workflows found")
for path in workflow_paths:
    workflow = path.read_text(encoding="utf-8")
    require("pull_request_target" not in workflow, f"unsafe public-fork trigger: {path.name}")
    parsed_workflow = parse_workflow(path)
    validate_permissions(parsed_workflow.get("permissions"), path.name)
    jobs = parsed_workflow.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        raise SystemExit(f"workflow jobs missing: {path.name}")
    for job_name, job in jobs.items():
        validate_job(job, f"{path.name}:{job_name}")
    trigger = parsed_workflow.get("on", parsed_workflow.get("true"))
    if not isinstance(trigger, dict):
        raise SystemExit(f"workflow trigger mapping missing: {path.name}")
    require("pull_request" in trigger, f"pull-request scan missing: {path.name}")
    require("pull_request_target" not in trigger, f"privileged pull_request_target trigger: {path.name}")
    require("push" in trigger and trigger["push"] is None, f"push scan must cover every branch: {path.name}")
require("permissions:\n  contents: read" in text(".github/workflows/ci.yml"), "CI top-level contents: read missing")
ci_workflow = text(".github/workflows/ci.yml")
require("fetch-depth: 0" in ci_workflow, "history scanner requires full checkout")
require("gitleaks_8.30.1_darwin_arm64.tar.gz" in ci_workflow, "pinned Gitleaks download missing")
require("b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5" in ci_workflow, "Gitleaks checksum missing")
require("/tmp/gitleaks git ." in ci_workflow and "/tmp/gitleaks dir ." in ci_workflow, "ongoing secret scans missing")

require("THIRD_PARTY_LICENSES.html" in build_script and "verify_app_licenses.py" in build_script, "app packaging omits license verification")
for forbidden in PRIVATE_PATH_PREFIXES:
    require(forbidden not in provenance, f"current SDK provenance contains private path: {forbidden}")

tracked = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT).decode().split("\0")
for relative in filter(None, tracked):
    path = ROOT / relative
    if not path.is_file():
        continue
    data = path.read_bytes()
    if relative in BINARY_HASHES:
        require(hashlib.sha256(data).hexdigest() == BINARY_HASHES[relative], f"binary checksum mismatch: {relative}")
        continue
    require(path.suffix.lower() in TEXT_SUFFIXES, f"unreviewed file type requires explicit allowlist and checksum: {relative}")
    require(not any(data.startswith(magic) for magic in BINARY_MAGIC_PREFIXES), f"binary magic requires explicit allowlist and checksum: {relative}")
    require(b"\x00" not in data, f"unreviewed binary or UTF-16 file: {relative}")
    try:
        content = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise SystemExit(f"non-UTF-8 tracked file requires explicit binary allowlist: {relative}") from error
    for forbidden in PRIVATE_PATH_PREFIXES:
        require(forbidden not in content, f"tracked current file contains private path: {relative}")

print("public-release metadata verification passed")
