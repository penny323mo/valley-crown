#!/usr/bin/env python3
"""Deterministic runtime identity; --dry-run never writes rules or reports."""
from pathlib import Path
import argparse
import hashlib
import json
import re
from runtime_manifest import runtime_paths, verify_mature_export_exclusions

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    root = args.root.resolve()
    verify_mature_export_exclusions(root)
    rules = root / 'scripts/rules.gd'
    content = rules.read_text()
    if 'const BUILD_ID =' not in content:
        content = content.replace('const VERSION =', 'const BUILD_ID = "unstamped"\nconst VERSION =', 1)
    paths = runtime_paths(root)
    h = hashlib.sha256()
    for p in paths:
        data = content.encode() if p == rules else p.read_bytes()
        if p == rules:
            data = re.sub(rb'const BUILD_ID = "[^"]*"', b'const BUILD_ID = "normalized"', data)
        h.update(p.relative_to(root).as_posix().encode()); h.update(b'\0'); h.update(data)
    build = 'vc-' + h.hexdigest()[:12]
    stamped = re.sub(r'const BUILD_ID = "[^"]*"', f'const BUILD_ID = "{build}"', content).encode()
    manifest = {'build': build, 'engine': '4.6.3.stable.official.7d41c59c4', 'scope': 'Recursive runtime scripts/UIDs, export settings, fonts/import settings, legacy meshes and mature native scenes/textures/import metadata. Editable/interchange art is source-archive only.', 'source_sha256': {p.relative_to(root).as_posix(): hashlib.sha256(stamped if p == rules else p.read_bytes()).hexdigest() for p in paths}}
    if args.dry_run:
        print(json.dumps({'dry_run': True, 'writes': 0, 'manifest': manifest}, indent=2))
    else:
        rules.write_bytes(stamped)
        (root / 'reports').mkdir(exist_ok=True)
        (root / 'reports/build-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        print(build)

if __name__ == '__main__':
    main()
