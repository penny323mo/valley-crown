#!/usr/bin/env python3
"""Prepare exact exported bytes and official npm packages without launching a browser."""
from pathlib import Path, PurePosixPath
import argparse
import base64
import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import urllib.request
from check_export_pins import validate_pins

INTEGRITY = {
    'playwright': 'sha512-ilYQj1s8sr2ppEJ2YVadYBN0Mb3mdo9J0wQ+UuDhzYqURwSoW4n1Xs5vs7ORwgDGmyEh33tRMeS8KhdkMoLXQw==',
    'playwright-core': 'sha512-agTcKlMw/mjBWOnD6kFZttAAGHgi/Nw0CZ2o6JqWSbMlI219lAFLZZCyqByTsvVAJq5XA5H8cA6PrvBRpBWEuQ=='
}
HERE = Path(__file__).resolve().parent

def need(ok, message):
    if not ok:
        raise RuntimeError(message)

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def inventory(root):
    result = {}
    for p in sorted(root.rglob('*')):
        need(not p.is_symlink() and (p.is_dir() or p.is_file()), 'Nonregular input')
        if p.is_file():
            result[p.relative_to(root).as_posix()] = sha(p)
    return result

def official_package(name, deps):
    url = f'https://registry.npmjs.org/{name}/-/{name}-1.57.0.tgz'
    archive = deps / (name + '-1.57.0.tgz')
    with urllib.request.urlopen(url, timeout=40) as response:
        need(response.status == 200 and response.url == url, 'Unexpected package response or redirect')
        count = 0
        with archive.open('xb') as target:
            while chunk := response.read(1024 * 1024):
                count += len(chunk)
                need(count <= 8 * 1024 * 1024, 'Package archive oversized')
                target.write(chunk)
    with archive.open('rb') as stream:
        integrity = 'sha512-' + base64.b64encode(hashlib.file_digest(stream, 'sha512').digest()).decode()
    need(integrity == INTEGRITY[name], 'Official npm package integrity mismatch')
    target = deps / 'node_modules' / name
    target.mkdir(parents=True)
    with tarfile.open(archive, 'r:gz') as tar:
        members = tar.getmembers()
        need(len(members) <= 1000 and sum(m.size for m in members) <= 20 * 1024 * 1024, 'Package expansion exceeds bounds')
        names = set()
        for member in members:
            normalized = member.name.rstrip('/') if member.isdir() else member.name
            path = PurePosixPath(normalized)
            need(not path.is_absolute() and '\\' not in normalized and path.parts[0] == 'package' and all(part not in ('', '.', '..') for part in normalized.split('/')), 'Unsafe npm member')
            need(normalized not in names and (member.isfile() or member.isdir()), 'Duplicate or special npm member')
            names.add(normalized)
            out = target.joinpath(*path.parts[1:])
            if member.isdir():
                out.mkdir(parents=True, exist_ok=True)
            else:
                need(member.size <= 10 * 1024 * 1024, 'Oversized npm member')
                out.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, out.open('xb') as destination:
                    shutil.copyfileobj(source, destination, 1024 * 1024)
    need(json.loads((target / 'package.json').read_text())['version'] == '1.57.0', 'Package version differs')
    return {'sha256': sha(archive), 'integrity': integrity, 'files_sha256': inventory(target)}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--profile', choices=['desktop', 'portrait'], required=True)
    args = parser.parse_args()
    need(os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'Fresh GitHub-hosted VM required')
    need(os.environ.get('GITHUB_REPOSITORY') == 'penny323mo/valley-crown' and os.environ.get('GITHUB_REF') == 'refs/heads/ci/military-gameplay-web-vc-542ddb524e45' and os.environ.get('GITHUB_RUN_ATTEMPT') == '1', 'Wrong repository/branch/attempt')
    candidate = args.candidate.resolve()
    work = args.work.resolve()
    need(not work.exists() and not work.is_symlink(), 'Fresh work root required')
    expected = json.loads((HERE / 'expected-export.json').read_text())
    scenario_data = (HERE / 'scenario-manifest.json').read_bytes()
    validate_pins(expected, json.loads(scenario_data), hashlib.sha256(scenario_data).hexdigest())
    need(inventory(candidate) == expected['files_sha256'], 'Export candidate identity mismatch')
    work.mkdir()
    shutil.copytree(candidate / 'artifacts/clean-a', work / 'export')
    need(inventory(work / 'export') == expected['export_manifest']['files_sha256'], 'Served export bytes differ')
    deps = work / 'deps'
    deps.mkdir()
    for name in ['package.json', 'package-lock.json']:
        shutil.copyfile(HERE / name, deps / name)
    packages = {name: official_package(name, deps) for name in INTEGRITY}
    receipt = {'source_commit': expected['export_manifest']['source_commit'], 'build': expected['build'], 'files_sha256': expected['export_manifest']['files_sha256'], 'packages': packages, 'npm_lock_sha256': sha(deps / 'package-lock.json'), 'browser_executed': False}
    # These read package metadata only; do not launch Chrome during preparation.
    chrome = Path('/opt/google/chrome/chrome')
    need(chrome.is_file() and not chrome.is_symlink(), 'Stock Google Chrome binary unavailable')
    owner = subprocess.check_output(['/usr/bin/dpkg-query', '-S', str(chrome)], text=True, timeout=15).strip()
    need(owner == 'google-chrome-stable: /opt/google/chrome/chrome', 'Chrome is not owned by expected stock package')
    version = subprocess.check_output(['/usr/bin/dpkg-query', '-W', '-f=${Version}', 'google-chrome-stable'], text=True, timeout=5).strip()
    node = Path(shutil.which('node') or '').resolve()
    need(node.is_file() and not node.is_symlink(), 'Stock Node runtime unavailable')
    receipt['profile'] = args.profile
    lock = dict(reviewed=True, profile=args.profile, build=receipt['build'], source_commit=receipt['source_commit'],
        files_sha256=receipt['files_sha256'], qa_files_sha256=inventory(HERE),
        npm_lock_sha256=receipt['npm_lock_sha256'],
        npm_tarball_sha256=packages['playwright']['sha256'], npm_registry_integrity=INTEGRITY['playwright'],
        npm_core_tarball_sha256=packages['playwright-core']['sha256'], npm_core_registry_integrity=INTEGRITY['playwright-core'],
        npm_package_files_sha256={name: info['files_sha256'] for name, info in packages.items()},
        deps_files_sha256=inventory(deps),
        chrome_path=str(chrome), chrome_sha256=sha(chrome), chrome_version='google-chrome-stable package ' + version,
        node_path=str(node), node_sha256=sha(node))
    (work / 'browser-lock.json').write_text(json.dumps(lock, indent=2) + '\n')
    (work / 'preparation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'build': receipt['build'], 'export_files': len(receipt['files_sha256']), 'official_packages': list(packages), 'browser_executed': False}))

if __name__ == '__main__':
    main()
