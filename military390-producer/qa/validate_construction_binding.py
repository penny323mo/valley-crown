"""Read-only preparation gate. Never invokes a browser, subprocess or host probe."""
import argparse
import hashlib
import json
from pathlib import Path
import re


PREPARED_SCENARIO = 'military390-producer'
PREPARED_VIEWPORT = [390, 844]
RESIZED_VIEWPORT = [844, 390]
PREPARED_PROFILE = 'portrait'

def validate(manifest, lock, manifest_sha256):
    if manifest.get('reviewed') is not True or lock.get('reviewed') is not True:
        raise ValueError('Both menu manifest and browser lock must be reviewed')
    if manifest.get('profile') != PREPARED_PROFILE or lock.get('profile') != PREPARED_PROFILE or manifest.get('hud_schema') != 2:
        raise ValueError('One exact fixed menu context and HUD schema2 required')
    if manifest.get('scenario') != PREPARED_SCENARIO or manifest.get('viewport') != PREPARED_VIEWPORT or manifest.get('resized_viewport') != RESIZED_VIEWPORT:
        raise ValueError('Wrong exact prepared scenario/viewport')
    if not re.fullmatch(r'vc-[0-9a-f]{12}', manifest.get('build', '')):
        raise ValueError('Final build pin missing')
    if not re.fullmatch(r'[0-9a-f]{40}', manifest.get('source_commit', '')):
        raise ValueError('Final source commit pin missing')
    for field in ('build', 'source_commit', 'files_sha256'):
        if manifest.get(field) != lock.get(field):
            raise ValueError('Menu and guard identity differ: ' + field)
    files = manifest.get('files_sha256')
    if not isinstance(files, dict) or not all(name in files for name in ('index.html', 'index.pck', 'index.wasm')):
        raise ValueError('Verified export inventory missing')
    for name, digest in files.items():
        if not isinstance(name, str) or name.startswith('/') or '\\' in name or any(part in ('', '.', '..') for part in name.split('/')) or not re.fullmatch('[0-9a-f]{64}', digest):
            raise ValueError('Invalid export inventory entry')
    if lock.get('qa_files_sha256', {}).get('scenario-manifest.json') != manifest_sha256:
        raise ValueError('Scenario manifest is not byte-bound in reviewed QA bundle')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--scenario', required=True, type=Path)
    parser.add_argument('--lock', required=True, type=Path)
    args = parser.parse_args()
    data = args.scenario.read_bytes()
    validate(json.loads(data), json.loads(args.lock.read_text()), hashlib.sha256(data).hexdigest())
    print('Menu scenario identity matches reviewed browser lock; no browser launched.')


if __name__ == '__main__': main()
