#!/usr/bin/env python3
"""Durable, append-only backups of the exact artifacts consumed by Pages.

No source export, artifact deletion, asset replacement, or branch update occurs.
Trust comes from hash pins already in pages.yml, not the release's mutable label.
"""
import argparse, ast, hashlib, io, json, os, pathlib, re, stat, sys, urllib.request, urllib.error, zipfile, tempfile

LIMIT = 1024 * 1024 * 1024
DOWNLOAD_LIMIT = 256 * 1024 * 1024

def sha(data):
    return hashlib.sha256(data).hexdigest()

def inventory(workflow):
    starts = list(re.finditer(r"^\s*artifact-ids: ['\"]?(\d+)['\"]?\s*$", workflow, re.M))
    rows = []
    for i, match in enumerate(starts):
        block = workflow[match.end(): starts[i+1].start() if i+1 < len(starts) else len(workflow)]
        run = re.search(r"run-id: ['\"]?(\d+)", block)
        dest = re.search(r"^\s*path: ([\w-]+)\s*$", block, re.M)
        target = re.search(r"target=pathlib.Path\('site/builds/([^']+)'\)", block)
        if not (run and dest and target):
            raise ValueError('Unrecognized Pages artifact consumer: ' + match.group(1))
        row = dict(artifact_id=int(match.group(1)), run_id=int(run.group(1)), destination=dest.group(1), build=target.group(1))
        expected = re.search(r'^\s*expected=(\{.*\})\s*$', block, re.M)
        metadata = re.search(r"assert sha\(meta\)==['\"]([a-f0-9]{64})['\"]", block)
        if expected:
            row['files_sha256'] = ast.literal_eval(expected.group(1))
        elif metadata:
            row['metadata_sha256'] = metadata.group(1)
        else:
            raise ValueError('Missing artifact trust pin: ' + row['build'])
        rows.append(row)
    if not rows or len({r['artifact_id'] for r in rows}) != len(rows):
        raise ValueError('Empty or duplicate artifact inventory')
    return rows

def load_inventory(workflow):
    catalog = pathlib.Path('release-history/WEB_ARCHIVE_CATALOG.json')
    if catalog.exists():
        obj = json.loads(catalog.read_text())
        if obj['schema_version'] != 1 or not obj['artifacts']:
            raise ValueError('Invalid archive catalog')
        return obj['artifacts']
    return inventory(pathlib.Path(workflow).read_text())

def verified_members(data, row):
    if row.get('zip_sha256') and sha(data) != row['zip_sha256']:
        raise ValueError('Pinned archive ZIP digest mismatch')
    z = zipfile.ZipFile(io.BytesIO(data))
    names = set()
    total = 0
    files = {}
    # Inspect every member before reading ANY member payload.
    for info in z.infolist():
        name = info.filename
        p = pathlib.PurePosixPath(name)
        mode = info.external_attr >> 16
        if (not name or name.startswith('/') or '\\' in name or '..' in p.parts
            or ':' in name or name.rstrip('/') != p.as_posix() or name in names
            or stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR))):
            raise ValueError('Unsafe ZIP member: ' + name)
        names.add(name)
        total += info.file_size
        if total > LIMIT:
            raise ValueError('Artifact exceeds 1 GiB uncompressed safety limit')
    for info in z.infolist():
        if not info.is_dir():
            files[info.filename] = z.read(info)
    expected = row.get('files_sha256')
    if expected is None:
        raw = files.get('candidate-metadata.json', b'')
        if sha(raw) != row['metadata_sha256']:
            raise ValueError('Metadata hash mismatch')
        meta = json.loads(raw)
        if meta['build'] != row['build'] or meta['side'] != 'product' or meta['diagnostic_only'] is not False:
            raise ValueError('Not the pinned product build')
        expected = dict(meta['files_sha256'])
        expected['candidate-metadata.json'] = row['metadata_sha256']
    actual = {name: sha(value) for name, value in files.items()}
    if actual != expected:
        raise ValueError('Exact artifact file allowlist/hash mismatch: ' + row['build'])
    return files

class GitHub:
    def __init__(self, repo):
        if not re.fullmatch(r'[\w.-]+/[\w.-]+', repo):
            raise ValueError('Invalid repository')
        self.repo = repo
        self.base = 'https://api.github.com/repos/' + repo
        self.token = os.environ['GH_TOKEN']

    def request(self, path, method='GET', body=None, binary=False):
        url = path if path.startswith('https://') else self.base + path
        if not url.startswith(('https://api.github.com/', 'https://uploads.github.com/')):
            raise ValueError('Unexpected GitHub endpoint')
        headers = {'Authorization': 'Bearer ' + self.token, 'X-GitHub-Api-Version': '2022-11-28',
                   'Accept': 'application/octet-stream' if binary and '/releases/assets/' in url else 'application/vnd.github+json'}
        if isinstance(body, dict):
            body = json.dumps(body).encode()
            headers['Content-Type'] = 'application/json'
        elif body is not None:
            headers['Content-Type'] = 'application/zip'
        # Never forward authentication to artifact/CDN redirect destinations.
        class Redirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, hdrs, newurl):
                redirect = super().redirect_request(req, fp, code, msg, hdrs, newurl)
                if redirect:
                    redirect.remove_header('Authorization')
                return redirect
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        with urllib.request.build_opener(Redirect()).open(req, timeout=180) as response:
            data = response.read(DOWNLOAD_LIMIT + 1)
            if len(data) > DOWNLOAD_LIMIT:
                raise ValueError('GitHub response exceeds 256 MiB bounded download limit')
        return data if binary else json.loads(data)

    def release(self, row):
        try:
            return self.request('/releases/tags/web-archive-artifact-' + str(row['artifact_id']))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            raise

    def asset(self, release, row):
        expected_name = str(row['artifact_id']) + '.zip'
        assets = [a for a in release['assets'] if a['name'] == expected_name]
        if len(assets) > 1:
            raise ValueError('Duplicate archive asset')
        return assets[0] if assets else None

    def read_asset(self, asset, row):
        if row.get('release_asset_id') and asset['id'] != row['release_asset_id']:
            raise ValueError('Pinned release asset identity changed')
        data = self.request('/releases/assets/' + str(asset['id']), binary=True)
        files = verified_members(data, row)
        if asset.get('digest') and asset['digest'] != 'sha256:' + sha(data):
            raise ValueError('Release asset transport digest mismatch')
        return data, files

    def ensure(self, row, create=False):
        release = self.release(row)
        asset = self.asset(release, row) if release else None
        if asset:
            data, files = self.read_asset(asset, row)
            return asset, data, files
        if not create:
            raise ValueError('No durable backup for ' + row['build'] + '; refusing Actions fallback')
        meta = self.request('/actions/artifacts/' + str(row['artifact_id']))
        if meta['expired'] or meta['workflow_run']['id'] != row['run_id']:
            raise ValueError('Expired or wrong-run source artifact')
        data = self.request('/actions/artifacts/' + str(row['artifact_id']) + '/zip', binary=True)
        files = verified_members(data, row)
        if meta.get('digest') and meta['digest'] != 'sha256:' + sha(data):
            raise ValueError('Actions ZIP digest mismatch')
        if release is None:
            release = self.request('/releases', method='POST', body={
                'tag_name': 'web-archive-artifact-' + str(row['artifact_id']),
                'target_commitish': os.environ['GITHUB_SHA'],
                'name': 'Durable Web archive: ' + row['build'],
                'body': 'Exact validated Actions artifact backup. No re-export.\nSource run: ' + str(row['run_id']) + '\nSource artifact: ' + str(row['artifact_id']) + '\nZIP SHA-256: ' + sha(data) + '\nNever replace/delete this archive asset. Consumers verify pinned file hashes.',
                'draft': False, 'prerelease': True, 'make_latest': 'false'})
        # No clobber/replacement path: an existing asset must be verified, never overwritten.
        upload = release['upload_url'].split('{')[0] + '?name=' + str(row['artifact_id']) + '.zip'
        asset = self.request(upload, method='POST', body=data)
        downloaded, checked = self.read_asset(asset, row)
        if sha(downloaded) != sha(data):
            raise ValueError('Read-back ZIP differs from source')
        return asset, downloaded, checked

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['plan', 'archive', 'restore'])
    parser.add_argument('--workflow', default='.github/workflows/pages.yml')
    parser.add_argument('--artifact', type=int)
    parser.add_argument('--destination')
    parser.add_argument('--report', default='web-archive-report.json')
    args = parser.parse_args()
    rows = load_inventory(args.workflow)
    if args.artifact:
        rows = [r for r in rows if r['artifact_id'] == args.artifact]
        if len(rows) != 1:
            raise ValueError('Artifact absent from pinned workflow inventory')
    if args.mode == 'plan':
        print(json.dumps(rows, indent=2))
        return
    github = GitHub(os.environ['GITHUB_REPOSITORY'])
    report = []
    for row in rows:
        asset, data, files = github.ensure(row, create=args.mode == 'archive')
        item = {k: row[k] for k in ['build', 'artifact_id', 'run_id']}
        item.update(asset_id=asset['id'], zip_sha256=sha(data), archive_bytes=len(data),
                    uncompressed_bytes=sum(map(len, files.values())),
                    web_export_bytes=sum(len(v) for k,v in files.items() if k.startswith('artifacts/clean-a/')),
                    file_count=len(files), readback_verified=True)
        report.append(item)
        pathlib.Path(args.report).write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(item), flush=True)
        if args.mode == 'restore':
            if not args.artifact or not args.destination:
                raise ValueError('Restore requires explicit artifact and destination')
            dest = pathlib.Path(args.destination)
            if dest.exists():
                raise ValueError('Restore destination already exists')
            dest.parent.mkdir(parents=True, exist_ok=True)
            stage = pathlib.Path(tempfile.mkdtemp(prefix='.web-archive-stage-', dir=dest.parent))
            for name, value in files.items():
                path = stage / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(value)
            if dest.exists():
                raise ValueError('Restore destination appeared during staging')
            stage.rename(dest)
    print('Verified durable archives:', len(report))

if __name__ == '__main__':
    main()
