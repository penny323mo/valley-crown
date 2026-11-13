#!/usr/bin/env python3
"""Prepare one exact public building candidate; import itself stays in its guard."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import zipfile
import building_import_policy as building

BRANCH = 'refs/heads/ci/advanced-building-import-vc-886b128c98ce-a1'
BUILD = 'vc-886b128c98ce'
GAME_TREE = 'cbed985236a2a5a3d0efb913a139dd4c36c629c1'
ENGINE = '4.6.3.stable.official.7d41c59c4'


def need(value, message):
    if not value:
        raise ValueError(message)


def dump(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True); stream.write('\n')


def sha(path):
    return building.digest(path)


def admitted():
    need(os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'Fresh GitHub-hosted runner required')
    need(os.environ.get('GITHUB_REPOSITORY') == 'penny323mo/valley-crown' and os.environ.get('GITHUB_REF') == BRANCH and os.environ.get('GITHUB_RUN_ATTEMPT') == '1', 'Wrong repository/branch/attempt')
    need(os.environ.get('BUILDING_IMPORT_COLLECTION_APPROVED') == 'true', 'Collection has not been reviewed')
    need('VERSION_ID="24.04"' in Path('/etc/os-release').read_text(), 'Ubuntu 24.04 required')


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True, timeout=8).strip()


def prepare(root, work):
    project = root / 'game'
    need(git(root, 'rev-parse', 'HEAD:game') == GAME_TREE, 'Exact public game tree differs')
    need(not work.exists() and not any(p.is_symlink() for p in [work, *work.parents]), 'Fresh real work root required')
    need(not work.is_relative_to(root) and not root.is_relative_to(work), 'Work/source overlap')
    public = {}
    for line in git(root, 'ls-tree', '-r', 'HEAD:game').splitlines():
        meta, name = line.split('\t', 1); mode, kind, digest = meta.split()
        need(mode == '100644' and kind == 'blob', 'Nonregular public source')
        public[name] = digest
    entries = {}; actual = {}
    for path in sorted(project.rglob('*')):
        need(not path.is_symlink(), 'Source symlink')
        if path.is_dir():
            continue
        need(path.is_file(), 'Special source')
        name = path.relative_to(project).as_posix(); data = path.read_bytes()
        actual[name] = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        entries[name] = {'file': name, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    need(actual == public and len(actual) == 252, 'Exact source bytes/count differ')
    building.expected({name: value['sha256'] for name, value in entries.items()})
    spec = importlib.util.spec_from_file_location('candidate_runtime', project / 'tools/runtime_manifest.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    module.verify_mature_export_exclusions(project)
    paths = module.runtime_paths(project)
    need(len(paths) == 149, 'Pre-import runtime input count differs')
    runtime = {'build': BUILD, 'engine': ENGINE, 'source_sha256': {p.relative_to(project).as_posix(): sha(p) for p in paths}}
    identity = hashlib.sha256()
    for name in sorted(runtime['source_sha256']):
        data = (project / name).read_bytes()
        if name == 'scripts/rules.gd':
            need(re.findall(rb'const BUILD_ID = "([^"]*)"', data) == [BUILD.encode()], 'Pre-import build differs')
            data = re.sub(rb'const BUILD_ID = "[^"]*"', b'const BUILD_ID = "normalized"', data)
        identity.update(name.encode()); identity.update(b'\0'); identity.update(data)
    need('vc-' + identity.hexdigest()[:12] == BUILD, 'Derived pre-import identity differs')
    work.mkdir(mode=0o700); dest = work / 'project'; shutil.copytree(project, dest)
    archive = work / 'source.zip'
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_STORED) as output:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0)); info.create_system = 3; info.external_attr = 0o100644 << 16
            with (dest / name).open('rb') as source, output.open(info, 'w') as member:
                shutil.copyfileobj(source, member, 1024 * 1024)
    runtime_sha = hashlib.sha256(json.dumps(runtime, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    # Existing adapter requires a bound suite descriptor, but test phase is
    # explicitly disabled. No suite, exporter, browser or renderer is invoked.
    suite = 'tests/map80_contract.gd'; suite_sha = entries[suite]['sha256']; report = 'OUTPUT/not-invoked.json'
    contract = dict(format='JSON object', must_be_new_file_from_this_run=True, process_exit_code=0,
        minimum_rows=1, rows_field='checks', row_verdict=dict(key='pass', equals=True, type='boolean'),
        count_equations=['passed == len(checks)', 'failed == 0'],
        required_integer_fields=dict(passed=dict(minimum=1), failed=dict(equals=0)),
        required_external_receipt=dict(candidate_build=BUILD, runtime_manifest_sha256=runtime_sha,
            suite_sha256=suite_sha, require_process_and_output_hash_binding=True))
    manifest = dict(candidate=BUILD, engine_expected=ENGINE, execution_enabled=False,
        files=list(entries.values()), runtime_manifest=dict(inputs=len(paths), sha256=runtime_sha),
        public_runtime_descriptor=runtime, suites=[dict(name='unused_map_descriptor', script=suite,
        script_sha256=suite_sha, argv=['GODOT', '--headless', '--path', 'PROJECT', '--script', 'res://' + suite, '--', report],
        report=report, report_contract=contract)])
    dump(work / 'import-manifest.json', manifest)
    dump(work / 'source-attestation.json', {'schema': 'vc-building-preimport-source-v1', 'build': BUILD,
        'game_tree': GAME_TREE, 'workflow_commit': git(root, 'rev-parse', 'HEAD'), 'source_files': len(entries),
        'runtime_inputs': len(paths), 'stage': 'collection-only; final release must be restamped',
        'source_archive_sha256': sha(archive), 'import_manifest_sha256': sha(work / 'import-manifest.json'),
        'policy_sha256': sha(Path(building.__file__)), 'engine_executed': False})
    (work / 'pins.env').write_text('ARCHIVE_SHA=' + sha(archive) + '\nMANIFEST_SHA=' + sha(work / 'import-manifest.json') + '\n')
    return {'build': BUILD, 'game_tree': GAME_TREE, 'source_files': len(entries), 'engine_executed': False}


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('phase', choices=['prepare', 'engine'])
    parser.add_argument('--work', type=Path, required=True); args = parser.parse_args()
    admitted(); work = args.work.absolute(); root = Path(__file__).resolve().parents[1]
    if args.phase == 'prepare':
        print(json.dumps(prepare(root, work)))
    else:
        import official_download as download
        need((work / 'source-attestation.json').is_file(), 'Exact source preparation missing')
        download.download(download.ENGINE_URL, work / 'engine.zip')
        download.safe_extract(work / 'engine.zip', {download.ENGINE_NAME: download.ENGINE_SHA}, work / 'engine', max_total=256*1024*1024, max_member=256*1024*1024)
        (work / 'engine' / download.ENGINE_NAME).chmod(0o755)
        print('Pinned official engine prepared without launch')


if __name__ == '__main__':
    main()
