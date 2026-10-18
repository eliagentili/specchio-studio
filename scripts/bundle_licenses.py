#!/usr/bin/env python3
"""Ship the original license texts and attribution with the local app."""
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def bundle(destination):
    destination = pathlib.Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "LICENSE", destination / "LICENSE")
    shutil.copy2(ROOT / "ThirdParty/NOTICE.txt", destination / "NOTICE.txt")
    shutil.copy2(ROOT / "ThirdParty/UxPlay-SPECCHIO-CHANGES.txt", destination / "UxPlay-SPECCHIO-CHANGES.txt")
    for source in sorted((ROOT / "ThirdParty").rglob("*")):
        if source.is_file() and source.name.upper().startswith(("LICENSE", "COPYING", "NOTICE", "AUTHORS")):
            target = destination / "ThirdParty" / source.relative_to(ROOT / "ThirdParty")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    uxplay_readme = (ROOT / "ThirdParty/UxPlay/README.md").read_text(encoding="utf-8")
    for heading, filename in (("Disclaimer", "UxPlay-DISCLAIMER.txt"), ("UxPlay authors", "UxPlay-AUTHORS.txt")):
        section = uxplay_readme.split("# " + heading + "\n", 1)[1].split("\n# ", 1)[0]
        (destination / filename).write_text(heading + "\n" + section, encoding="utf-8")
    (destination / "SOURCE.txt").write_text(
        "Specchio Studio — GPL-3.0-or-later\n\n"
        "Software libero, senza garanzia; il testo completo è in LICENSE.\n"
        "Le dipendenze conservano le licenze e attribuzioni incluse.\n"
        "Per una distribuzione binaria, fornire insieme anche l'archivio\n"
        "specchio-studio-<versione>-source.tar.gz della stessa build,\n"
        "con i sorgenti delle dipendenze e le istruzioni di ricompilazione.\n"
        "Vedi SOURCE-INFO.txt nel pacchetto di distribuzione.\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: bundle_licenses.py <destination>")
    bundle(sys.argv[1])
