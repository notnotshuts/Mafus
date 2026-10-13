#!/usr/bin/env python3
"""Fail packaging if a locale is incomplete or corrupts interpolated values."""
from pathlib import Path
import json, re
root = Path(__file__).resolve().parents[1] / 'Sources/Mafus/Resources/Translations'
base = json.loads((root / 'ru.json').read_text())
expected = {'en','ru','de','fr','es','it','pt','nl','pl','uk','cs','sk','hu','ro','tr','sv','da','fi','nb','el','ja','ko','zh-Hans','zh-Hant'}
assert {p.stem for p in root.glob('*.json')} == expected
for path in root.glob('*.json'):
    table = json.loads(path.read_text())
    assert table.keys() == base.keys(), f'{path.name}: missing or extra messages'
    for key, value in table.items():
        assert value.strip(), (path.name, key)
        assert sorted(re.findall(r'\{\d+\}', key)) == sorted(re.findall(r'\{\d+\}', value)), (path.name, key, value)
print(f'Validated {len(base)} messages in {len(expected)} languages')
