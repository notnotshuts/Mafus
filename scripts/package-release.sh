#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
architecture=$(uname -m)
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/Info.plist)
release_dir="${1:-$PWD/../Mafus-release-$version}"
mkdir -p "$release_dir"
/usr/bin/codesign --verify --deep --strict dist/Mafus.app
/usr/bin/ditto -c -k --sequesterRsrc --keepParent dist/Mafus.app "$release_dir/Mafus-$version-macOS-$architecture.zip"
python3 - "$version" "$release_dir" <<'PY'
from pathlib import Path
import sys,zipfile,hashlib,subprocess
root=Path.cwd();version=sys.argv[1];destination=Path(sys.argv[2])
with zipfile.ZipFile(destination/f'Mafus-{version}-source.zip','w',zipfile.ZIP_DEFLATED) as archive:
 paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z']).decode().split('\0')
 for name in sorted(filter(None,paths)):
  rel=Path(name);path=root/rel
  if not path.is_file() or path.is_symlink():continue
  archive.write(path,Path('Mafus')/rel)
files=sorted(destination.glob('*.zip'))
(destination/'SHA256SUMS.txt').write_text('\n'.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name for p in files)+'\n')
for p in files:
 with zipfile.ZipFile(p) as archive:assert archive.testzip() is None,p.name
print(f'Validated {len(files)} release archives in {destination}')
PY
