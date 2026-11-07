#!/usr/bin/env python3
"""Apply only the small reviewed construction overlay to accepted c721 source.

File-only assembly. No engine, material generation, network, upload or deployment.
The full archive is assembled on the runner from existing public artifact bytes.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import re
import shutil
import stat
import zipfile

ACCEPTED_LOCK_SHA = '52711be56c32b5f1a8b861ff4578843cebd3e16a1501b78466a5ac0492ad05aa'
BUILD = 'vc-43276605e0fb'
ALLOWED = {'scripts/game.gd', 'scripts/construction_visual.gd.uid', 'scripts/construction_visual.gd', 'tests/construction_visual.gd', 'tests/construction_visual.gd.uid', 'reports/build-manifest.json', 'scripts/rules.gd'}


def require(ok, message):
    if not ok: raise RuntimeError(message)


def sha(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def inventory(root):
    require(root.is_dir() and not root.is_symlink(), 'Invalid project root')
    files = {}
    for path in sorted(root.rglob('*')):
        mode = path.lstat().st_mode
        require(not stat.S_ISLNK(mode), 'Symlink rejected')
        if stat.S_ISDIR(mode): continue
        require(stat.S_ISREG(mode), 'Special entry rejected')
        files[path.relative_to(root).as_posix()] = sha(path)
    return files


def write_archive(project, entries, archive):
    require(not archive.exists() and not archive.is_symlink(), 'Archive must be fresh')
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_STORED) as target:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.create_system = 3; info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_STORED
            with (project / name).open('rb') as source, target.open(info, 'w') as output:
                shutil.copyfileobj(source, output, length=65536)


def apply(args):
    project = args.project.resolve(); archive = args.archive.resolve(); receipt = args.receipt.resolve()
    require(not archive.is_relative_to(project) and not receipt.is_relative_to(project), 'Outputs must be external')
    require(not receipt.exists() and not receipt.is_symlink(), 'Receipt must be fresh')
    require(sha(args.accepted_lock) == ACCEPTED_LOCK_SHA, 'Accepted c721 lock mismatch')
    require(sha(args.package) == args.package_sha256, 'Package identity mismatch')
    package = json.loads(args.package.read_text()); base = json.loads(args.accepted_lock.read_text())
    before = {row['file']: row['sha256'] for row in base['files']}
    require(base['candidate'] == 'vc-c7211e1083c8' and len(before) == len(base['files']) == 188, 'Wrong accepted base')
    require(inventory(project) == before, 'Initial accepted source mismatch')
    expected = {row['file']: row['sha256'] for row in package['files']}
    require(package['candidate'] == BUILD and len(expected) == len(package['files']) == 192, 'Wrong derived package')
    changed = {name for name in expected if expected[name] != before.get(name)}
    require(set(before).issubset(expected) and changed == ALLOWED, 'Unreviewed source changes')
    require(sha(args.overlay) == package['construction_overlay']['sha256'], 'Overlay hash mismatch')
    require(set(package['construction_overlay']['files']) == ALLOWED, 'Wrong overlay declaration')
    require(args.overlay.stat().st_size < 300000, 'Overlay unexpectedly large')
    with zipfile.ZipFile(args.overlay) as source:
        require(len(source.infolist()) == len(ALLOWED) and set(source.namelist()) == ALLOWED and source.testzip() is None, 'Overlay inventory/CRC mismatch')
        require(sum(row.file_size for row in source.infolist()) < 300000, 'Overlay expanded size exceeds bound')
        verified = {}
        for info in source.infolist():
            name = info.filename; path = PurePosixPath(name)
            require(not path.is_absolute() and all(part not in ('', '.', '..') for part in name.split('/')) and '\\' not in name, 'Unsafe member')
            require(stat.S_IFMT(info.external_attr >> 16) in (0, stat.S_IFREG), 'Nonregular overlay member')
            data = source.read(info)
            require(hashlib.sha256(data).hexdigest() == expected[name] == package['construction_overlay']['files'][name], 'Overlay member hash mismatch')
            verified[name] = data
        for name, data in verified.items():
            path = project / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    require(inventory(project) == expected, 'Derived source inventory mismatch')
    runtime = json.loads((project / 'reports/build-manifest.json').read_text())
    require(runtime['build'] == BUILD and sha(project / 'reports/build-manifest.json') == package['runtime_manifest']['sha256'], 'Derived runtime manifest mismatch')
    stamp = hashlib.sha256()
    for name, digest in sorted(runtime['source_sha256'].items()):
        require(expected.get(name) == digest, 'Runtime source differs')
        data = (project / name).read_bytes()
        if name == 'scripts/rules.gd':
            require(re.findall(rb'const BUILD_ID = "([^"]*)"', data) == [BUILD.encode()], 'Rules identity mismatch')
            data = re.sub(rb'const BUILD_ID = "[^"]*"', b'const BUILD_ID = "normalized"', data)
        stamp.update(name.encode()); stamp.update(b'\0'); stamp.update(data)
    require('vc-' + stamp.hexdigest()[:12] == BUILD, 'Derived stamp mismatch')
    write_archive(project, expected, archive)
    require(sha(archive) == package['source_archive_sha256'], 'Full source archive differs')
    receipt.write_text(json.dumps({'passed': True, 'base_build': base['candidate'], 'candidate': BUILD,
        'file_count': len(expected), 'overlay_file_count': len(ALLOWED), 'archive_sha256': sha(archive),
        'runtime_manifest_sha256': package['runtime_manifest']['sha256'],
        'scope': 'File-only construction source assembly; no engine execution or visual acceptance'}, indent=2) + '\n')
    print('Exact construction source assembly verified: ' + BUILD)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('project', 'accepted-lock', 'package', 'overlay', 'archive', 'receipt'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--package-sha256', required=True)
    apply(parser.parse_args())
