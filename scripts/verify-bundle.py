#!/usr/bin/env python3
from pathlib import Path
import json,plistlib,subprocess,platform
root=Path(__file__).resolve().parents[1]
app=root/'dist/Mafus.app'
arch=platform.machine()
for name in ('Mafus','mafus-core','wimlib-imagex','xz','zstd','mkntfs','ntfs-populate','xorriso','mke2fs'):
    path=app/'Contents/MacOS'/name
    actual=subprocess.check_output(['lipo','-archs',str(path)],text=True).strip().split()
    assert arch in actual, f'{name}: wrong architecture {actual}, expected {arch}'
    dependencies=subprocess.check_output(['otool','-L',str(path)],text=True)
    assert '/opt/homebrew/' not in dependencies and '/usr/local/' not in dependencies, f'{name}: unbundled dependency'
source=root/'Sources/Mafus/Resources/Translations'
for path in source.glob('*.json'):
    installed=app/'Contents/Resources/Translations'/path.name
    assert installed.read_bytes()==path.read_bytes(), f'{path.name}: stale/missing packaged translations'
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(f'Validated {arch} app: executables, dependencies, 24 translation tables and signature')
