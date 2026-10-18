#!/usr/bin/env python3
"""Check publication links, metadata, script boundaries and asset integrity."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote, parse_qsl
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT/'docs'
BASE = 'https://eliagentili.github.io/specchio-studio-site/'

class Document(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids=[]; self.refs=[]; self.meta={}; self.alternates=[]; self.h1=0; self.lang=None; self.canonical=None; self.scripts=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a: self.ids.append(a['id'])
        if tag=='html': self.lang=a.get('lang'); self.classes=a.get('class','')
        if tag=='h1': self.h1+=1
        if tag=='img':
            assert 'alt' in a, 'Image missing alternative text'
            assert 'width' in a and 'height' in a, 'Image missing dimensions'
        if tag=='meta': self.meta[a.get('name',a.get('property',a.get('http-equiv')))]=a.get('content')
        if tag=='link' and a.get('rel')=='canonical': self.canonical=a['href']
        if tag=='link' and a.get('rel')=='alternate': self.alternates.append(a)
        if tag=='script' and 'src' in a: self.scripts.append(a['src'])
        for key in ('href','src'):
            if key in a: self.refs.append(a[key])

pages={}
for path in SITE.rglob('*.html'):
    doc=Document(); doc.feed(path.read_text()); pages[path.resolve()]=doc
    assert doc.h1==1, f'{path}: expected one H1'
    assert doc.lang=='en', f'{path}: website must be English'
    assert not doc.alternates, f'{path}: obsolete language alternate'
    assert len(doc.ids)==len(set(doc.ids)), f'{path}: duplicate IDs'
    assert not any('http:' in ref for ref in doc.refs), f'{path}: insecure URL'
    if path.parent.name=='it':
        target = '' if path.name=='index.html' else 'privacy.html'
        assert doc.canonical==BASE+target, f'{path}: incorrect legacy canonical'
        assert doc.meta.get('refresh')=='0;url=../'+target, f'{path}: broken legacy redirect'
        assert doc.meta.get('robots')=='noindex,follow', f'{path}: legacy URL should not be indexed'
        assert not doc.scripts, f'{path}: redirect must work without scripts'
    elif path.name!='404.html':
        assert 'no-js' in doc.classes, f'{path}: missing script-free fallback'
        assert doc.meta.get('description') and doc.meta.get('og:image'), f'{path}: incomplete metadata'
        assert doc.canonical==BASE+str(path.relative_to(SITE)).replace('index.html',''), f'{path}: incorrect canonical'
        assert [urlsplit(ref).path for ref in doc.scripts]==['site.js'], f'{path}: unexpected scripts'

count=0
versions=0
for path,doc in pages.items():
    # Metadata image URLs must invalidate cached social previews as well.
    refs=doc.refs+[doc.meta[key] for key in ('og:image','twitter:image') if doc.meta.get(key)]
    for ref in refs:
        parsed=urlsplit(ref)
        if parsed.scheme or parsed.netloc:
            if not ref.startswith(BASE): continue
            target=(SITE/unquote(parsed.path[len(urlsplit(BASE).path):])).resolve()
        else:
            target=(path.parent/unquote(parsed.path)).resolve() if parsed.path else path
        assert SITE.resolve() in (target,*target.parents), f'Path outside site: {ref}'
        if target.is_dir(): target=target/'index.html'
        assert target.is_file(), f'{path}: broken link {ref}'
        if target.suffix in {'.css','.js','.png','.svg','.webp'}:
            expected=hashlib.sha256(target.read_bytes()).hexdigest()[:12]
            assert parse_qsl(parsed.query)==[('v',expected)], f'{path}: stale or missing asset version {ref}'
            versions+=1
        if parsed.fragment:
            assert parsed.fragment in pages[target.resolve()].ids, f'{path}: missing fragment {ref}'
        count+=1
assets=json.loads((SITE/'assets/provenance.json').read_text())['assets']
assert {p.name for p in (SITE/'assets').iterdir()}=={a['file'] for a in assets}|{'provenance.json'}, 'Unlisted or stale website asset'
for item in assets:
    file=SITE/'assets'/item['file']
    assert file.stat().st_size==item['bytes'], f'Asset size changed: {file}'
    assert hashlib.sha256(file.read_bytes()).hexdigest()==item['sha256'], f'Asset integrity changed: {file}'
js=(SITE/'site.js').read_text()
assert not re.search(r'\b(fetch|XMLHttpRequest|localStorage|sessionStorage|document\.cookie)\b',js), 'Unexpected network or persistence API'
assert not re.search(r'https?://',js), 'Unexpected script endpoint'
subprocess.run(['node','--check',str(SITE/'site.js')],check=True)
print(f'PASS: {len(pages)} HTML pages, {count} site references, {versions} content-versioned asset URLs, English metadata, two legacy redirects, {len(assets)} asset hashes, no script network/persistence.')
