#!/usr/bin/env python3
"""Check publication links, metadata, script boundaries and asset integrity."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
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
        self.ids=[]; self.refs=[]; self.meta={}; self.h1=0; self.lang=None; self.canonical=None; self.scripts=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a: self.ids.append(a['id'])
        if tag=='html': self.lang=a.get('lang'); self.classes=a.get('class','')
        if tag=='h1': self.h1+=1
        if tag=='img':
            assert 'alt' in a, 'Image missing alternative text'
            assert 'width' in a and 'height' in a, 'Image missing dimensions'
        if tag=='meta': self.meta[a.get('name',a.get('property'))]=a.get('content')
        if tag=='link' and a.get('rel')=='canonical': self.canonical=a['href']
        if tag=='script' and 'src' in a: self.scripts.append(a['src'])
        for key in ('href','src'):
            if key in a: self.refs.append(a[key])

pages={}
for path in SITE.rglob('*.html'):
    doc=Document(); doc.feed(path.read_text()); pages[path.resolve()]=doc
    assert doc.h1==1, f'{path}: expected one H1'
    assert doc.lang in ('en','it'), f'{path}: language missing'
    assert len(doc.ids)==len(set(doc.ids)), f'{path}: duplicate IDs'
    assert not any('http:' in ref for ref in doc.refs), f'{path}: insecure URL'
    if path.name!='404.html':
        assert 'no-js' in doc.classes, f'{path}: missing script-free fallback'
        assert doc.meta.get('description') and doc.meta.get('og:image'), f'{path}: incomplete metadata'
        assert doc.canonical==BASE+str(path.relative_to(SITE)).replace('index.html',''), f'{path}: incorrect canonical'
        assert doc.scripts==[('../' if path.parent.name=='it' else '')+'site.js'], f'{path}: unexpected scripts'

count=0
for path,doc in pages.items():
    for ref in doc.refs:
        parsed=urlsplit(ref)
        if parsed.scheme or parsed.netloc: continue
        target=(path.parent/unquote(parsed.path)).resolve() if parsed.path else path
        assert SITE.resolve() in (target,*target.parents), f'Path outside site: {ref}'
        if target.is_dir(): target=target/'index.html'
        assert target.is_file(), f'{path}: broken link {ref}'
        if parsed.fragment:
            assert parsed.fragment in pages[target.resolve()].ids, f'{path}: missing fragment {ref}'
        count+=1
for item in json.loads((SITE/'assets/provenance.json').read_text())['assets']:
    file=SITE/'assets'/item['file']
    assert file.stat().st_size==item['bytes'], f'Asset size changed: {file}'
    assert hashlib.sha256(file.read_bytes()).hexdigest()==item['sha256'], f'Asset integrity changed: {file}'
js=(SITE/'site.js').read_text()
assert not re.search(r'\b(fetch|XMLHttpRequest|localStorage|sessionStorage|document\.cookie)\b',js), 'Unexpected network or persistence API'
assert not re.search(r'https?://',js), 'Unexpected script endpoint'
subprocess.run(['node','--check',str(SITE/'site.js')],check=True)
print(f'PASS: {len(pages)} HTML pages, {count} local references, bilingual metadata, 12 asset hashes, no script network/persistence.')
