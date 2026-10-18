#!/usr/bin/env python3
"""Stage the public website from an exact allowlist; never include the app."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
TOP = {'.nojekyll', '404.html', 'LICENSE', 'index.html', 'privacy.html', 'site.js', 'sitemap.xml', 'styles.css'}
ASSETS = {'app-icon.png', 'demo-preview.webp', 'favicon.svg', 'format-landscape.png', 'format-portrait.png', 'format-square.png', 'formats-proof.png', 'formats-proof.webp', 'github-banner.png', 'provenance.json', 'social-card-it.png', 'social-card.png'}
FILES = TOP | {'it/index.html','it/privacy.html'} | {'assets/'+n for n in ASSETS}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination',type=Path,help='New, empty directory outside the application repository')
    args=parser.parse_args()
    dest=args.destination.expanduser().resolve()
    if dest == ROOT or ROOT in dest.parents or (dest.exists() and any(dest.iterdir())):
        raise SystemExit('Use a new empty destination outside the application repository.')
    subprocess.run(['python3',str(ROOT/'scripts/check_site.py')],check=True)
    dest.mkdir(parents=True,exist_ok=True)
    for name in sorted(FILES):
        src=ROOT/'docs'/name
        if src.is_symlink() or not src.is_file():
            raise SystemExit('Unsupported site entry: '+name)
        target=dest/name
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(src,target)
    shutil.copyfile(ROOT/'marketing/SITE_README.md',dest/'README.md')
    hashes={str(p.relative_to(dest)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(dest.rglob('*')) if p.is_file()}
    print(json.dumps({'destination':str(dest),'files':len(hashes),'sha256':hashes},indent=2))

if __name__=='__main__': main()
