#!/usr/bin/env python3
"""Inspect a local extracted preview bundle; never run it or alter security settings."""
import plistlib,re,subprocess,sys
from pathlib import Path
app=Path(sys.argv[1]);version,build=sys.argv[2:]
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='com.t0nyz0.MakerPulse'
assert info['CFBundleShortVersionString']==version and info['CFBundleVersion']==build
assert info['LSMinimumSystemVersion']=='14.0'
allowed={'Contents/Info.plist','Contents/MacOS/MakerGlance','Contents/Resources/MakerGlance.icns','Contents/_CodeSignature/CodeResources'}
files={str(p.relative_to(app)) for p in app.rglob('*') if p.is_file()}
assert files==allowed, 'Unexpected or missing bundle files'
for file in app.rglob('*'):
    assert not file.is_symlink(), 'Unexpected link inside application'
    if file.is_file():
        data=file.read_bytes()
        assert not re.search(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/',data), 'Machine path present in distributed file'
        assert (b'-----BEGIN ' + b'PRIVATE KEY-----') not in data
binary=app/'Contents/MacOS/MakerGlance'
assert subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()=='arm64'
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(f'Verified local extracted app v{version} build{build}: arm64, signature, exact bundle inventory and machine-path guard.')
