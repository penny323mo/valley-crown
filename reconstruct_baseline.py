#!/usr/bin/env python3
"""File-only exact public baseline reconstruction. No network or engine commands."""
import argparse,hashlib,json,os,shutil,stat,subprocess,sys
from pathlib import Path

def need(ok,message):
    if not ok:raise RuntimeError(message)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def regular(path):
    p=Path(path).absolute();need(not any(x.is_symlink() for x in (p,*p.parents)), 'Symlink path')
    need(p.is_file() and stat.S_ISREG(p.stat().st_mode),'Nonregular input');return p

def inventory(root):
    root=Path(root);need(root.is_dir() and not root.is_symlink(),'Missing/unsafe root');result={}
    for p in root.rglob('*'):
        need(not p.is_symlink(),'Symlink entry')
        if p.is_dir():continue
        regular(p);result[p.relative_to(root).as_posix()]=sha(p)
    return dict(sorted(result.items()))

def reconstruct(args):
    plan_path=regular(args.plan);need(sha(plan_path)==args.plan_sha256,'Baseline chain pin differs');plan=json.loads(plan_path.read_text())
    lock=regular(args.baseline_lock);need(sha(lock)==plan['baseline_lock_sha256'],'Accepted baseline lock differs')
    root=Path(args.source).resolve();out=Path(args.output).absolute()
    need(not out.exists() and out != root and not root.is_relative_to(out),'Fresh disjoint reconstruction root required')
    need(not any(p.is_symlink() for p in out.parents),'Unsafe output parent')
    for n,h in plan['public_files'].items():need(sha(regular(root/n))==h,'Public baseline source changed: '+n)
    licensed=Path(args.licensed).resolve();native=Path(args.native).resolve()
    inventory(licensed);inventory(native)
    out.mkdir()
    for n in plan['public_files']:
        target=out/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(root/n,target)
    shutil.copytree(licensed,out/'licensed-artifact');shutil.copytree(native,out/'native-artifact')
    env={k:os.environ[k] for k in ('PATH','LANG','LC_ALL','TZ') if k in os.environ};env['PYTHONDONTWRITEBYTECODE']='1'
    for argv in plan['commands']:
        need(argv and argv[0] in plan['public_files'] and argv[0].startswith('ci/') and argv[0].endswith('.py'),'Unknown file-only assembly helper')
        # Exact pinned legacy helper source and argv; no shell and no downloaded code.
        subprocess.run([sys.executable,*argv],cwd=out,env=env,check=True,timeout=120,stdin=subprocess.DEVNULL)
    expected=json.loads(lock.read_text())
    need(expected['build']==plan['baseline_build']=='vc-fe500d2ea0b5' and len(expected['files'])==192,'Wrong baseline identity')
    need(inventory(out/'project')==expected['files'],'Reconstructed baseline does not match exact accepted192')
    (out/'baseline-receipt.json').write_text(json.dumps({'passed':True,'build':expected['build'],'source_files':192,'baseline_lock_sha256':sha(lock),'baseline_chain_sha256':sha(plan_path),'source_commit':plan['source_commit']},indent=2)+'\n')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('source','licensed','native','plan','baseline-lock','output'):p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--plan-sha256',required=True);reconstruct(p.parse_args())
if __name__=='__main__':main()
