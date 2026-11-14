#!/usr/bin/env python3
"""Rebuild Pages from Release assets only, with the current original validators.

Does not deploy, mutate releases or change repository files. All outputs live in
an isolated temp directory. Reports exact final URL/file hashes and byte count.
"""
import hashlib, json, os, pathlib, re, shutil, subprocess, tempfile
from web_release_archive import GitHub, inventory

repo = pathlib.Path.cwd()
text = (repo/'.github/workflows/pages.yml').read_text()
rows = inventory(text)
work = pathlib.Path(tempfile.mkdtemp(prefix='verified-release-only-pages-'))
github = GitHub(os.environ['GITHUB_REPOSITORY'])
for source in ['release-history','landing.html','valley-crown-vc-bff2dcf4109a-web.zip']:
    src = repo/source
    if src.is_dir(): shutil.copytree(src,work/source)
    else: shutil.copyfile(src,work/source)
for row in rows:
    asset, data, files = github.ensure(row, create=False)
    target = work/row['destination']
    target.mkdir()
    for name,content in files.items():
        out=target/name;out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(content)
# Run the existing, trusted packaging/validation code verbatim, never the deploy.
packaging = text.split('      - uses: actions/configure-pages@')[0]
runs = re.findall(r'^        run: \|\n((?:^          .*\n|^\n)+)',packaging,re.M)
if len(runs)!=len(rows): raise ValueError('Unexpected packaging program structure')
for program in runs:
    script='\n'.join(line[10:] if line.startswith('          ') else line for line in program.splitlines())+'\n'
    subprocess.run(['bash','-euo','pipefail','-c',script],cwd=work,check=True)
site=work/'site'
if any(p.is_symlink() for p in site.rglob('*')):raise ValueError('Site symlink')
files={p.relative_to(site).as_posix():{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(site.rglob('*')) if p.is_file()}
report={'release_only':True,'archives':len(rows),'builds':len(list((site/'builds').iterdir())),'site_bytes':sum(v['bytes'] for v in files.values()),'file_count':len(files),'files':files}
(repo/'release-only-site-report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='files'}),flush=True)
print('Site data preserved at:',work)
