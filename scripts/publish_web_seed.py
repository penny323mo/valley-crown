#!/usr/bin/env python3
"""Append-only SHA-addressed Release seed for R2. No Pages deployment or deletion.
Future builds: supply complete, reviewed per-file hashes in --catalog (same schema
as PAGES_ARCHIVE_BASELINE), and the exact exported --directory; no mutable URL trust.
"""
import argparse, hashlib, json, os, pathlib, re, urllib.error
from web_release_archive import GitHub
p=argparse.ArgumentParser()
p.add_argument('--build',required=True);p.add_argument('--directory',required=True)
p.add_argument('--catalog',default='release-history/PAGES_ARCHIVE_BASELINE.json')
a=p.parse_args()
if not re.fullmatch(r'vc-[0-9a-f]{12}',a.build):raise ValueError('Invalid build')
root=pathlib.Path(a.directory)
if root.is_symlink() or any(x.is_symlink() for x in root.rglob('*')):raise ValueError('Symlink rejected')
base=json.loads(pathlib.Path(a.catalog).read_text())['files'];prefix='builds/'+a.build+'/'
expected={name[len(prefix):]:meta for name,meta in base.items() if name.startswith(prefix)}
actual={x.relative_to(root).as_posix():{'bytes':x.stat().st_size,'sha256':hashlib.sha256(x.read_bytes()).hexdigest()} for x in root.rglob('*') if x.is_file()}
if not expected or actual!=expected:raise ValueError('Complete file allowlist/size/SHA mismatch')
if any(x['bytes']>64*1024*1024 for x in actual.values()):raise ValueError('File exceeds 64 MiB seed policy')
g=GitHub(os.environ['GITHUB_REPOSITORY']);tag='web-seed-'+a.build
try:r=g.request('/releases/tags/'+tag)
except urllib.error.HTTPError as e:
    if e.code!=404:raise
    r=g.request('/releases',method='POST',body={'tag_name':tag,'target_commitish':os.environ['GITHUB_SHA'],'name':'Verified Web seed: '+a.build,'body':'Append-only content-addressed game files for persistent R2 ingestion. Never replace existing assets.','draft':False,'prerelease':True,'make_latest':'false'})
existing={x['name']:x for x in r['assets']}
report={'build':a.build,'tag':tag,'files':{}}
for name,meta in sorted(expected.items()):
    digest=meta['sha256'];assetname=digest+'.bin'
    if not meta['bytes']:
        report['files'][name]={**meta,'url':None};continue
    asset=existing.get(assetname)
    if asset is None:
        asset=g.request(r['upload_url'].split('{')[0]+'?name='+assetname,method='POST',body=(root/name).read_bytes())
        existing[assetname]=asset
    data=g.request('/releases/assets/'+str(asset['id']),binary=True)
    if len(data)!=meta['bytes'] or hashlib.sha256(data).hexdigest()!=digest:raise ValueError('Release readback mismatch '+name)
    report['files'][name]={**meta,'asset_id':asset['id'],'url':asset['browser_download_url']}
manifest=(json.dumps(report,indent=2)+'\n').encode()
m=existing.get('seed-manifest.json')
if m is None:
    m=g.request(r['upload_url'].split('{')[0]+'?name=seed-manifest.json',method='POST',body=manifest)
if g.request('/releases/assets/'+str(m['id']),binary=True)!=manifest:raise ValueError('Durable seed manifest mismatch')
pathlib.Path('web-seed-report.json').write_bytes(manifest)
print(json.dumps({'build':a.build,'verified_files':len(report['files']),'bytes':sum(x['bytes'] for x in expected.values())}))
