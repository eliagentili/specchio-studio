#!/usr/bin/env python3
"""Check vendored sources against pinned official archives; network is opt-in."""
import argparse
import hashlib
import json
import pathlib
import sys
import subprocess
import tempfile
import tarfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def archive_files(path):
    result = {}
    with tarfile.open(path, "r:*") as archive:
        for member in archive:
            if not member.isfile():
                continue
            parts = pathlib.PurePosixPath(member.name).parts
            if len(parts) < 2 or ".." in parts or member.name.startswith("/"):
                raise ValueError(f"Unexpected archive path: {member.name}")
            relative = "/".join(parts[1:])
            if relative in result:
                raise ValueError(f"Duplicate archive path: {relative}")
            result[relative] = digest(archive.extractfile(member).read())
    return result


def directory_files(path):
    result = {}
    for entry in sorted(path.rglob("*")):
        if entry.is_symlink():
            raise ValueError(f"Unexpected vendored symlink: {entry.relative_to(ROOT)}")
        if entry.is_file():
            result[entry.relative_to(path).as_posix()] = digest(entry.read_bytes())
    return result


def verify_signature(component, archive):
    key = ROOT / component["release_signing_key_path"]
    if digest(key.read_bytes()) != component["release_signing_key_sha256"]:
        raise ValueError("Recorded release signing key has changed")
    with tempfile.TemporaryDirectory(prefix="specchio-pgp-") as temporary:
        keyring = pathlib.Path(temporary) / "release-key.gpg"
        subprocess.run(["gpg", "--batch", "--yes", "--dearmor", "--output", str(keyring), str(key)],
                       check=True, capture_output=True)
        result = subprocess.run(["gpgv", "--homedir", temporary, "--keyring", str(keyring), "--status-fd", "1",
                                 str(ROOT / component["release_signature_path"]), str(archive)],
                                capture_output=True, text=True)
        valid = [line.split() for line in result.stdout.splitlines() if line.startswith("[GNUPG:] VALIDSIG ")]
        if result.returncode or not any(line[-1] == component["release_signing_primary_fingerprint"] for line in valid):
            raise ValueError("Release signature does not match the pinned OpenSSL primary key")
        return component["release_signing_primary_fingerprint"]


def verify(component, cache, download, signatures):
    name = component["name"]
    archive = cache / component["cache_filename"]
    if not archive.exists() and download:
        cache.mkdir(parents=True, exist_ok=True)
        temporary = archive.with_name(archive.name + ".download")
        try:
            request = urllib.request.Request(component["archive_url"], headers={"User-Agent": "Specchio-Studio-upstream-verification"})
            with urllib.request.urlopen(request, timeout=60) as response, temporary.open("wb") as output:
                while block := response.read(1024 * 1024):
                    output.write(block)
            if digest(temporary.read_bytes()) != component["archive_sha256"]:
                raise ValueError("Downloaded archive checksum differs from the recorded audit")
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    if not archive.exists():
        raise ValueError(f"Missing cached archive {archive}; use --download to permit HTTPS downloads")
    actual_archive_digest = digest(archive.read_bytes())
    if actual_archive_digest != component["archive_sha256"]:
        raise ValueError("Cached official archive checksum differs from the recorded audit")
    signature = verify_signature(component, archive) if signatures and component.get("release_signature_path") else None
    official = archive_files(archive)
    local_path = ROOT / component["local_path"]
    if component["local_kind"] == "archive":
        if digest(local_path.read_bytes()) != component["archive_sha256"]:
            raise ValueError("Vendored archive is not byte-identical to the verified official release")
        local = archive_files(local_path)
    else:
        local = directory_files(local_path)
    missing = sorted(official.keys() - local.keys())
    extra = sorted(local.keys() - official.keys())
    differences = sorted(path for path in official.keys() & local.keys() if official[path] != local[path])
    allowed = component.get("local_modifications", {})
    unexpected = [path for path in differences if allowed.get(path) != local[path]]
    stale_allowlist = [path for path in allowed if path not in differences]
    passed = not (missing or extra or unexpected or stale_allowlist)
    return {"name": name, "commit": component["commit"], "passed": passed,
            "official_files": len(official), "local_files": len(local),
            "unchanged_files": sum(official.get(path) == value for path, value in local.items()),
            "declared_modifications": differences, "missing": missing, "extra": extra,
            "unexpected_modifications": unexpected, "stale_modification_allowlist": stale_allowlist,
            "archive_sha256": actual_archive_digest, "verified_signing_primary_fingerprint": signature}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=pathlib.Path, default=ROOT / ".build/upstream-cache")
    parser.add_argument("--offline", action="store_true", help="Require cached archives (also the default)")
    parser.add_argument("--download", action="store_true", help="Allow downloading missing official archives over HTTPS")
    parser.add_argument("--signatures", action="store_true", help="Also verify included release signatures with gpg and gpgv")
    parser.add_argument("--report", type=pathlib.Path, help="Also save the JSON result to this path")
    args = parser.parse_args()
    if args.offline and args.download:
        parser.error("--offline and --download are mutually exclusive")
    manifest = json.loads((ROOT / "ThirdParty/upstream.json").read_text())
    results = []
    for component in manifest["components"]:
        try:
            results.append(verify(component, args.cache, args.download, args.signatures))
        except Exception as error:
            results.append({"name": component["name"], "passed": False, "error": str(error)})
    report = {"audit_date": manifest["audit_date"], "network_allowed": args.download,
              "passed": all(result["passed"] for result in results), "components": results,
              "scope": "Source integrity and declared local modifications; not legal clearance, binary reproducibility or proof of absence of vulnerabilities."}
    output = json.dumps(report, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output)
    print(output, end="")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
