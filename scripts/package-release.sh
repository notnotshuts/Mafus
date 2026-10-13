#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/Info.plist)
release_dir="${1:-$PWD/../Mafus-release-$version}"
mkdir -p "$release_dir"
/usr/bin/codesign --verify --deep --strict dist/Mafus.app
/usr/bin/ditto -c -k --sequesterRsrc --keepParent dist/Mafus.app "$release_dir/Mafus-$version-macOS-arm64.zip"
python3 - "$version" "$release_dir" <<'PY'
from pathlib import Path
import sys,zipfile,hashlib
root=Path.cwd();version=sys.argv[1];destination=Path(sys.argv[2])
with zipfile.ZipFile(destination/f'Mafus-{version}-source.zip','w',zipfile.ZIP_DEFLATED) as archive:
 for path in sorted(root.rglob('*')):
  rel=path.relative_to(root)
  if not path.is_file() or any(part in {'.git','.build','target','dist','.DS_Store','.openai'} for part in rel.parts) and not rel.parts[:2]==('website','dist'):continue
  archive.write(path,Path('Mafus')/rel)
files=sorted(destination.glob('*.zip'))
(destination/'SHA256SUMS.txt').write_text('\n'.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name for p in files)+'\n')
for p in files:
 with zipfile.ZipFile(p) as archive:assert archive.testzip() is None,p.name
print(f'Validated {len(files)} release archives in {destination}')
PY
