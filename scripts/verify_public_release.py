#!/usr/bin/env python3
"""Fail-closed checks for Hypha's public-release licensing and workflow metadata."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path, PurePosixPath
from urllib.parse import quote
from zipfile import BadZipFile, ZipFile

ROOT = Path(__file__).resolve().parents[1]
SECURITY_URL = "https://github.com/ZenithResearch/Hypha/security/advisories/new"
AGPL_SHA256 = "0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0"
SDK_SHA256 = "9b853f98352f088ae0939e28d4d739349c396f9b57f6af815c0a7957156fe4c8"
THIRD_PARTY_LICENSES_SHA256 = "fcaea90f82dc3aa6f0ab1761310e19c554ae771829e7a77d167c84128f9e42f2"
LICENSE_INVENTORY_SHA256 = "66887660cc784b7d6cb4c4e425ba4a8d164ad1c9854a903a9af792576816216a"
THIRD_PARTY_NOTICES_SHA256 = "e09cc55f6c0279876b459f03a91f28363b2be859736eef97ac269c4e7da5c86f"
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
    "Resources/ZenithOSIcon.icns": "59f627b5e8996335d8be81b5fcc6092088b9c1915ed9b2cd82e49e0b9a348a78",
    "Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png": "af1d53159a8fe909f0308a413942d368243aefe2f4d170df3638435285dbe382",
    "Resources/iOS/Assets.xcassets/HyphaMark.imageset/HyphaMark.png": "af1d53159a8fe909f0308a413942d368243aefe2f4d170df3638435285dbe382",
    "docs/evidence/issue-2/native-shell.png": "7e88b4366551f923c2e12b33eea737cef01558899484060b37a5ce2a37a0b84b",
    "Vendor/MatrixRustSDK/MatrixSDKFFI.xcframework.zip": SDK_SHA256,
}
CRITICAL_POLICY_HASHES = {
    "project.yml": "32aca3f10b90261e678cdd8bc7a27383d9b72be32ff3fd083fa1ea6652aab637",
    "Resources/iOS/Info.plist": "f684655642e476f10aa8b909f0bf62fecb65e9d91f2bcdf3ef7f60666625b2f6",
    "HyphaMobile.xcodeproj/project.pbxproj": "addbf377324d71c8ec8e1cb679fd1d8e9f619ea5ccd282a5ccdd8dcd68239686",
    ".github/workflows/ci.yml": "a0197e410b90e50ef99e60665d9558ba8326abf77616211f8eb3f5abfd834064",
    ".github/workflows/release.yml": "766a573d6aa88ebc175a323bdfb712653ff0f213ea636619a080244dd15862ca",
    "SECURITY.md": "38c04ef47f90e68ef21eed3234f891b935caf5cf2386dd0f4737f922eaa17e37",
    "build-app.sh": "6f1b7ba44241e52439fe024922b9b266f2a866ca19fa3f58b131ccd98d1ebee4",
    "release/encryption-gate.json": "6aac43d006072c05c3ecc65ec05490e2c24acc76c3aa85bc146473e6f9a9e1c6",
    "release/RELEASE_NOTES.md": "f382d08f5238c173fc9e5099d72f38b4d30d1c9f592f89bab099e0c1aafbdb57",
    "scripts/package-release.sh": "37466216ca5e8d19746a4ade4149a2e58c0fb9735a2ed1eeb5ca74a51fcf7482",
    "scripts/prepare-release-signing.sh": "659ddbd4d260c3db31d9bfe6813676212ef2cf76983ec39c776fb98cda7cff61",
    "scripts/test_prepare_release_signing.py": "dcfb977656b7cddb5b61e6021f90d8418d31b092fd2da15fecb833a7f08677d3",
    "scripts/update-from-main.sh": "39b42e5ee8ed1e8bbac324249381b47cdb07cd30c8d7ca8259d18c4ec43a7392",
    "scripts/launch-update-from-main.command": "6850baecd7798789955c5e88883586dc03209d4235756da15b814322e60fe606",
    "scripts/test_update_launcher.py": "5a0e134d6cf647774520a0ec399a5c951f76d852390c9ada48ed3c21dd73553e",
    "scripts/write_release_metadata.py": "d0f6cdca5dc39d7ecb537a94d0dd5ac1696d51838641ba8d3a4bfb6ed79054a1",
    "scripts/test_release_metadata.py": "1b6b5590fe095352fd2a47f10c81973af6f08422a509621ecd3fe79dbea34f93",
    "scripts/verify_app_licenses.py": "62cedfdd0c4590c79ec3d66d1f38fe61caee767403d5629c13107697190823ce",
    "scripts/generate_zenith_icon.py": "f91f71cdf8309fe9217e06cafd0477c32faa380c66b4f31feedc8d0944250b18",
    "Resources/ZenithOSIcon.svg": "b553714e443d6ab856295676f92ee363d9b9ccfb8a0a6711e73ce9780fe2ac78",
}
TEXT_SUFFIXES = {"", ".command", ".entitlements", ".hbs", ".html", ".json", ".md", ".pbxproj", ".plist", ".py", ".sh", ".svg", ".swift", ".toml", ".txt", ".xcworkspacedata", ".xcscheme", ".yml", ".yaml"}
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

sdk_archive_path = ROOT / "Vendor/MatrixRustSDK/MatrixSDKFFI.xcframework.zip"
try:
    with ZipFile(sdk_archive_path) as sdk_archive:
        sdk_entries = sdk_archive.namelist()
except BadZipFile as error:
    raise SystemExit("Matrix SDK artifact is not a valid ZIP archive") from error
require(bool(sdk_entries), "Matrix SDK archive is empty")
for entry in sdk_entries:
    entry_path = PurePosixPath(entry)
    require(not entry_path.is_absolute() and ".." not in entry_path.parts, f"unsafe Matrix SDK archive path: {entry}")
    require(
        "__MACOSX" not in entry_path.parts and not any(part.startswith("._") for part in entry_path.parts),
        f"AppleDouble metadata contaminates Matrix SDK archive: {entry}",
    )

for identifier, expected in LICENSE_HASHES.items():
    require(sha256(f"LICENSES/{identifier}.txt") == expected, f"license text mismatch: {identifier}")
for path, expected in CRITICAL_POLICY_HASHES.items():
    require(sha256(path) == expected, f"critical policy file changed without canonical review: {path}")

require(sha256("Vendor/MatrixRustSDK/license-inventory.json") == LICENSE_INVENTORY_SHA256, "canonical license inventory changed")
require(sha256("THIRD_PARTY_NOTICES.md") == THIRD_PARTY_NOTICES_SHA256, "third-party notices changed without inventory regeneration")
inventory = json.loads(text("Vendor/MatrixRustSDK/license-inventory.json"))
require(inventory.get("schema_version") == 1, "unsupported license inventory schema")
require(inventory.get("matrix_sdk_source_commit") == "d28c164ef37cd67723aa565bf5aec9c0cefc3bb8", "license inventory source drift")
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
    jobs = parsed_workflow.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        raise SystemExit(f"workflow jobs missing: {path.name}")
    assert isinstance(jobs, dict)
    for job_name, job in jobs.items():
        validate_job(job, f"{path.name}:{job_name}")
    trigger = parsed_workflow.get("on", parsed_workflow.get("true"))
    if not isinstance(trigger, dict):
        raise SystemExit(f"workflow trigger mapping missing: {path.name}")
    require("pull_request_target" not in trigger, f"privileged pull_request_target trigger: {path.name}")
    if path.name == "ci.yml":
        validate_permissions(parsed_workflow.get("permissions"), path.name)
        require("pull_request" in trigger, f"pull-request scan missing: {path.name}")
        require("push" in trigger and trigger["push"] is None, f"push scan must cover every branch: {path.name}")
    elif path.name == "release.yml":
        require(set(trigger) == {"push"}, "release workflow must be tag-push only")
        push_trigger = trigger.get("push")
        require(isinstance(push_trigger, dict), "release push trigger must be a mapping")
        require(push_trigger.get("tags") == ["v[0-9]*.[0-9]*.[0-9]*"], "release tag allowlist changed")
        require(parsed_workflow.get("permissions") == {"contents": "write"}, "release permission must be contents: write only")
        require(set(jobs) == {"release"}, "release workflow must contain one release job")
        require(jobs["release"].get("environment") == "release", "release job must use the protected release environment")
    else:
        raise SystemExit(f"unreviewed workflow: {path.name}")
require("permissions:\n  contents: read" in text(".github/workflows/ci.yml"), "CI top-level contents: read missing")
ci_workflow = text(".github/workflows/ci.yml")
require("fetch-depth: 0" in ci_workflow, "history scanner requires full checkout")
require("gitleaks_8.30.1_darwin_arm64.tar.gz" in ci_workflow, "pinned Gitleaks download missing")
require("b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5" in ci_workflow, "Gitleaks checksum missing")
require("/tmp/gitleaks git ." in ci_workflow and "/tmp/gitleaks dir ." in ci_workflow, "ongoing secret scans missing")

release_workflow = text(".github/workflows/release.yml")
required_release_secrets = (
    "MACOS_CERTIFICATE_P12",
    "MACOS_CERTIFICATE_PASSWORD",
    "RELEASE_KEYCHAIN_PASSWORD",
    "APPLE_API_KEY_P8",
    "APPLE_API_KEY_ID",
    "APPLE_API_ISSUER_ID",
)
for secret_name in required_release_secrets:
    require(f"secrets.{secret_name}" in release_workflow, f"release secret is not wired: {secret_name}")
require("scripts/prepare-release-signing.sh" in release_workflow, "release signing preparation is not invoked")
require("HYPHA_RELEASE_MODE: distributable" in release_workflow, "public release is not distributable")
require("HYPHA_ALLOW_NON_DISTRIBUTABLE_RELEASE" not in release_workflow, "public release has an ad-hoc escape hatch")
require("release/RELEASE_NOTES.md" in release_workflow, "distributable release notes are not published")
require("ADHOC_RELEASE_NOTICE" not in release_workflow, "public release still publishes the ad-hoc warning")

credential_import = text("scripts/prepare-release-signing.sh")
for secret_name in required_release_secrets:
    require(f"${{{secret_name}:?" in credential_import, f"credential importer does not require {secret_name}")
require("-T /usr/bin/codesign" in credential_import, "Developer ID private key is not limited to codesign")
require(" -A " not in credential_import, "Developer ID private key grants unrestricted application access")
require("trap cleanup_on_error EXIT" in credential_import, "partial credential import does not clean up")

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
