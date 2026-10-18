#!/usr/bin/env python3
"""Check app catalog coverage and printf argument parity without launching the app."""
from pathlib import Path
import json
import re
import subprocess

ROOT=Path(__file__).resolve().parent.parent

def read_strings(path):
    result=subprocess.run(['plutil','-convert','json','-o','-',str(path)],check=True,capture_output=True,text=True)
    return json.loads(result.stdout)

def placeholders(text):
    return re.findall(r'%(?:\d+\$)?[-+0 #]*(?:\d+)?(?:\.\d+)?(?:ll|l|h|z)?[@diufegs]',text.replace('%%',''))

en=read_strings(ROOT/'Resources/en.lproj/Localizable.strings')
it=read_strings(ROOT/'Resources/it.lproj/Localizable.strings')
assert en.keys()==it.keys(),'The two catalogs have different keys'
for key in en:
    assert placeholders(en[key])==placeholders(it[key]),f'Placeholder mismatch: {key}'
keys=set()
for path in (ROOT/'Sources').glob('*.swift'):
    # App strings in L/LF are plain Swift literals; variable rawValue labels are checked separately.
    for match in re.finditer(r'\b(?:L|LF)\(\s*("(?:[^"\\]|\\.)*")',path.read_text()):
        token=match.group(1)
        assert '\\(' not in token,f'Use LF with stable placeholders: {path.name}: {token}'
        key=json.loads(token)
        assert key in en,f'Untranslated source key in {path.name}: {key}'
        keys.add(key)
for key in ['Automatico','Verticale 9:16','Quadrato 1:1','Orizzontale 16:9','Grafite','Oceano','Carta','Trasparente','Alta','Massima']:
    assert key in en,f'Missing dynamic enum label: {key}'
for language in ['en','it']:
    permissions=read_strings(ROOT/f'Resources/{language}.lproj/InfoPlist.strings')
    assert set(permissions)=={'NSCameraUsageDescription','NSMicrophoneUsageDescription','NSLocalNetworkUsageDescription'}
print(f'PASS: {len(keys)} literal localization keys, {len(en)} catalog entries per language, matching format arguments and bilingual permission descriptions.')
