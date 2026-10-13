"""Round trip Windows payloads through WIM → ESD → WIM → SWM, without disks."""
import hashlib
import random
import subprocess
import sys
import tempfile
from pathlib import Path
binary = Path(sys.argv[1]).resolve()
def run(*args):
    result = subprocess.run([str(binary), *map(str, args)], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
with tempfile.TemporaryDirectory(prefix='mafus-wim-test-') as folder:
    root = Path(folder)
    source = root / 'source'
    source.mkdir()
    (source / 'Windows').mkdir()
    randomizer = random.Random(42)
    for index in range(3):
        (source / 'Windows' / f'data-{index}.bin').write_bytes(randomizer.randbytes(800_000))
    original = root / 'original.wim'
    esd = root / 'install.esd'
    converted = root / 'converted.wim'
    split = root / 'install.swm'
    run('capture', source, original, '--compress=LZX', '--check')
    run('export', original, 'all', esd, '--compress=LZMS', '--solid', '--check')
    run('export', esd, 'all', converted, '--compress=LZX', '--check')
    run('split', converted, split, '1', '--check')
    parts = list(root.glob('install*.swm'))
    assert len(parts) > 1, 'No split parts were generated'
    run('verify', split, f'--ref={root}/install*.swm')
    extracted = root / 'extracted'
    run('apply', split, '1', extracted, f'--ref={root}/install*.swm')
    for path in source.rglob('*'):
        if path.is_file():
            assert hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256((extracted / path.relative_to(source)).read_bytes()).digest()
print('wimlib checks passed: ESD conversion, splitting, verification and extraction')
