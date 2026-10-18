#!/usr/bin/env python3
"""Build the pinned AirPlay protocol libraries without GStreamer or system installs."""
import concurrent.futures, hashlib, os, pathlib, subprocess
root = pathlib.Path(__file__).resolve().parent.parent
out = root / '.build/native'
out.mkdir(parents=True, exist_ok=True)
ux = root / 'ThirdParty/UxPlay/lib'
pl = root / 'ThirdParty/libplist'
crypto = pathlib.Path(os.environ.get('SPECCHIO_OPENSSL', str(root/'ThirdParty/OpenSSL')))
sources = list(ux.glob('*.c')) + list((ux/'playfair').glob('*.c')) + list((ux/'llhttp').glob('*.c')) + list((ux/'dns_sd').glob('*.c'))
sources += list((pl/'src').glob('*.c')) + [pl/'libcnary/node.c',pl/'libcnary/node_list.c']
common = ['clang','-target','arm64-apple-macos14.0','-O2','-fPIC','-fmodules-cache-path='+str(out/'modules'),'-DNOHOLD','-DPLIST_210','-DPLIST_230','-DUXPLAY_HAVE_APPLE_P2P', '-DOPENSSL_API_COMPAT=0x10101000L', '-DHAVE_STRNDUP','-DHAVE_MEMMEM','-DHAVE_STRPTIME','-DHAVE_LOCALTIME_R','-DHAVE_GMTIME_R','-DHAVE_TM_TM_GMTOFF','-DHAVE_TM_TM_ZONE','-DPACKAGE_VERSION="2.8.0"']
for p in [ux,ux/'playfair',ux/'llhttp',pl,pl/'src',pl/'include',pl/'libcnary/include',crypto/'include']:
    common += ['-I',str(p)]
headers_hash=hashlib.sha256()
for directory in (ux,pl,crypto/'include'):
    for header in sorted(directory.rglob('*.h')):
        headers_hash.update(header.read_bytes())
headers_digest=headers_hash.digest()
def compile_c(src):
    obj = out / (str(src.relative_to(root)).replace('/','_') + '.o')
    key = hashlib.sha256(src.read_bytes() + repr(common).encode() + headers_digest).hexdigest()
    stamp = obj.with_suffix('.sha')
    if not obj.exists() or not stamp.exists() or stamp.read_text() != key:
        subprocess.run(common + ['-c',str(src),'-o',str(obj)],check=True)
        stamp.write_text(key)
    return obj
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    objects = list(pool.map(compile_c, sources))
bridge = out / 'WirelessBridge.o'
subprocess.run(common + ['-fobjc-arc','-fmodules','-c',str(root/'Native/WirelessBridge.m'),'-o',str(bridge)],check=True)
subprocess.run(['libtool','-static','-o',str(out/'libSpecchioAirPlay.a'),*[str(o) for o in objects],str(bridge)],check=True)
print(out/'libSpecchioAirPlay.a')
