#!/usr/bin/env python3
"""Create local review packages, including corresponding source, without Git history."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import shutil
import subprocess
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = (
    "Info.plist", "LICENSE", "README.md", "README.it.md", "LEGGIMI.txt", "VALIDAZIONE.txt",
    "PROJECT_STATUS.md", "RELEASE_CHECKLIST.txt", "UPSTREAM_AUDIT.txt", "PROMO.txt", ".gitignore",
    "build.sh", "test.sh", "Anteprima-demo.png",
)
DIRECTORIES = ("Sources", "Native", "Resources", "Tests", "ThirdParty", "scripts", "docs", "marketing")
SKIP_PARTS = {".git", ".build", ".DS_Store", "__pycache__"}


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def source_files(root=ROOT):
    result = [root / name for name in FILES]
    for directory in DIRECTORIES:
        result.extend(path for path in sorted((root / directory).rglob("*"))
                      if not SKIP_PARTS.intersection(path.relative_to(root).parts)
                      and path.suffix != ".pyc" and (path.is_file() or path.is_symlink()))
    for path in result:
        if path.is_symlink() or not path.is_file():
            raise SystemExit(f"Missing or unsupported source entry: {path.relative_to(root)}")
    return result


def public_metadata(member):
    member.uid = member.gid = 0
    member.uname = member.gname = ""
    member.pax_headers = {}
    return member


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true", help="Prepare sources without building or running tests")
    args = parser.parse_args()
    version = plistlib.loads((ROOT / "Info.plist").read_bytes())["CFBundleShortVersionString"]
    output = ROOT / ".build/releases" / version
    if args.source_only:
        output = output / "source-only"
    (ROOT / ".build").mkdir(exist_ok=True)
    entries = source_files()
    manifest = {str(path.relative_to(ROOT)): digest(path) for path in entries}
    source_name = f"specchio-studio-{version}-source.tar.gz"
    with tempfile.TemporaryDirectory(prefix="specchio-release-", dir=ROOT / ".build") as work:
        staging = pathlib.Path(work)
        source_archive = staging / source_name
        source_root = staging / f"specchio-studio-{version}"
        source_root.mkdir()
        for path in entries:
            target = source_root / path.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
        # Verify the staged bytes, then build only from this immutable snapshot.
        if manifest != {name: digest(source_root / name) for name in manifest}:
            raise SystemExit("Source files changed while staging; retry after edits finish.")
        if not args.source_only:
            # Prove source correspondence instead of trusting the bundled archive.
            subprocess.run(["./Native/build_crypto.sh"], cwd=source_root, check=True)
        staged_entries = source_files(source_root)
        staged_manifest = {str(path.relative_to(source_root)): digest(path) for path in staged_entries}
        manifest_path = source_root / "SOURCE-MANIFEST.json"
        manifest_path.write_text(
            json.dumps({"version": version, "sha256": staged_manifest}, indent=2) + "\n", encoding="utf-8")
        with tarfile.open(source_archive, "w:gz") as archive:
            for path in [*staged_entries, manifest_path]:
                archive.add(path, arcname=source_root.name + "/" + str(path.relative_to(source_root)), filter=public_metadata)
        if not args.source_only:
            subprocess.run(["./test.sh"], cwd=source_root, check=True)
            subprocess.run(["./build.sh"], cwd=source_root, check=True)
        info = staging / "SOURCE-INFO.txt"
        info.write_text(
            f"Specchio Studio {version}\n"
            f"Corresponding source: {source_name}\nSHA-256: {digest(source_archive)}\n\n"
            "GPL-3.0-or-later; see the bundled LICENSE and third-party notices.\n"
            "Publish the source archive alongside the binary at the same location.\n"
            "Unpack the source, run ./Native/build_crypto.sh, then ./build.sh.\n"
            "Apple Silicon, macOS 14+, Apple Command Line Tools, Python 3, Perl and make.\n"
            "This local app uses ad hoc signing and is not notarized.\n"
            "These packages require provenance and release review before publication.\n",
            encoding="utf-8")
        artifacts = [source_archive]
        if not args.source_only:
            distribution = staging / "Specchio Studio"
            distribution.mkdir()
            shutil.copytree(source_root / "Specchio Studio.app", distribution / "Specchio Studio.app")
            shutil.copy2(info, distribution / info.name)
            shutil.copy2(source_root / "LICENSE", distribution / "LICENSE")
            shutil.copy2(source_root / "LEGGIMI.txt", distribution / "LEGGIMI.txt")
            binary_archive = staging / f"specchio-studio-{version}-macos-arm64.zip"
            subprocess.run(["ditto", "-c", "-k", "--keepParent", "--norsrc", str(distribution), str(binary_archive)], check=True)
            artifacts.append(binary_archive)
        checksums = staging / "SHA256SUMS.txt"
        checksums.write_text(
            "".join(f"{digest(path)}  {path.name}\n" for path in artifacts), encoding="utf-8")
        output.mkdir(parents=True, exist_ok=True)
        for path in [*artifacts, info, checksums]:
            shutil.copy2(path, output / path.name)
    print(f"Local review packages: {output}")
    print("No repository visibility or remote history was changed.")


if __name__ == "__main__":
    main()
