#!/usr/bin/env python3
"""Check integrated source consistency without invoking Godot or any subprocess."""
from pathlib import Path
import hashlib
import json
import re
import sys
from runtime_manifest import runtime_paths, verify_mature_export_exclusions

ROOT = Path(__file__).resolve().parents[1]
checks = []

def check(label, condition):
    checks.append(label)
    if not condition:
        raise AssertionError(label)

def main():
    verify_mature_export_exclusions(ROOT)
    check('art excluded from engine import', (ROOT / 'art/.gdignore').is_file())
    for p in ROOT.rglob('*'):
        check('regular path: ' + p.relative_to(ROOT).as_posix(), not p.is_symlink())
    paths = runtime_paths(ROOT)
    rules = (ROOT / 'scripts/rules.gd').read_bytes()
    actual_id = re.search(rb'const BUILD_ID = "([^"]+)"', rules).group(1).decode()
    digest = hashlib.sha256()
    for p in paths:
        data = p.read_bytes()
        if p == ROOT / 'scripts/rules.gd':
            data = re.sub(rb'const BUILD_ID = "[^"]*"', b'const BUILD_ID = "normalized"', data)
        digest.update(p.relative_to(ROOT).as_posix().encode())
        digest.update(b'\0')
        digest.update(data)
    check('deterministic build identity', actual_id == 'vc-' + digest.hexdigest()[:12])
    for name in ('building_damage_component.gd', 'building_damage_projection.gd'):
        source = (ROOT / 'tests' / name).read_text()
        check('test bound to current build: ' + name, 'const EXPECTED_BUILD = "' + actual_id + '"' in source)
    for p in ROOT.rglob('*'):
        if not p.is_file() or p.suffix not in {'.gd', '.tscn', '.tres'}:
            continue
        text = p.read_text()
        for resource in re.findall(r'(?:preload|load)\("res://([^"\n]+)"\)', text):
            check('literal resource: ' + resource, (ROOT / resource).is_file())
    game = (ROOT / 'scripts/game.gd').read_text()
    check('last selected unit targeting cleanup', 'if rally_building==ent.id or (touch_command and rally_building<0 and selected.is_empty()): _cancel_mode()' in game)
    check('camera gesture cannot move build preview', 'elif not build_mode.is_empty() and not touch_gesture:' in game)
    for name in ('kaykit-animations', 'quaternius-base', 'quaternius-outfits', 'quaternius-ual', 'quaternius-ual2'):
        check('character license: ' + name, (ROOT / ('art/action_characters/licenses/' + name + '.txt')).is_file())
    for name in ('DEJAVU-LICENSE.txt', 'NOTO-LICENSE.txt'):
        check('font license: ' + name, (ROOT / 'assets/fonts' / name).is_file())
    for kind in ('villager', 'spearman', 'archer', 'scout'):
        for relative in ('art/action_characters/' + kind + '.blend',
                         'art/action_characters/interchange/' + kind + '.glb',
                         'assets/mature/models/' + kind + '_action.scn'):
            check('retained character source: ' + relative, (ROOT / relative).is_file())
    print(json.dumps({'status': 'PASS_SOURCE_ONLY', 'build': actual_id,
                      'checks': len(checks), 'runtime_inputs': len(paths),
                      'godot_parse_import_execution': 'NOT_RUN',
                      'browser_physical_iphone': 'NOT_RUN'}))

if __name__ == '__main__':
    main()
