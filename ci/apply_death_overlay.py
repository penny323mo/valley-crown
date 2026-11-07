"""File-only overlay for an already-verified DISPOSABLE exact f6a2 source tree.
No engine/import, source archive, material/camera generation, network or promotion.
"""
from pathlib import Path,PurePosixPath
import argparse,hashlib,json,re,stat,subprocess,sys
PACKAGE_SHA='76417073bd0a653c5ceebcb88ca3f680cc193188ac640f441638480db459ab52'
BUILD='vc-470d98d0c3ee'
MODELS={'assets/mature/models/'+k+'_action.scn' for k in ('spearman','archer','scout')}
STAMP={'scripts/rules.gd','reports/build-manifest.json'}
def require(ok,message):
    if not ok:raise ValueError(message)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def inventory(root):
    require(root.is_dir() and not root.is_symlink(),'Invalid root')
    result={}
    for p in root.rglob('*'):
        mode=p.lstat().st_mode;require(not stat.S_ISLNK(mode),'Symlink rejected')
        if stat.S_ISDIR(mode):continue
        require(stat.S_ISREG(mode),'Special entry rejected')
        result[p.relative_to(root).as_posix()]=sha(p)
    return result
def entries(package):
    result={}
    for row in package['files']:
        name=row['file'];p=PurePosixPath(name)
        require(not p.is_absolute() and all(x not in ('','.','..') for x in name.split('/')) and '\\' not in name,'Unsafe name')
        require(name not in result,'Duplicate entry');result[name]=row['sha256']
    require(len(result)==192,'Expected192 sources');return result
def apply(project,base_package,package,native_output,receipt):
    require(sha(package)==PACKAGE_SHA,'Visual package hash mismatch')
    pkg=json.loads(package.read_text());require(sha(base_package)==pkg['base_package_sha256'],'Base package hash mismatch')
    base=json.loads(base_package.read_text());before=entries(base);after=entries(pkg)
    require(base['candidate']=='vc-f6a2f9514b4d' and pkg['candidate']==BUILD and pkg['execution_enabled'] is False,'Wrong identities')
    require(set(before)==set(after) and {n for n in before if before[n]!=after[n]}==MODELS|STAMP,'Unexpected source delta')
    require(not receipt.exists() and not receipt.is_symlink() and not receipt.resolve().is_relative_to(project.resolve()) and not receipt.resolve().is_relative_to(native_output.resolve()),'Fresh external receipt required')
    require(inventory(project)==before,'Disposable project must be exact unimported f6a2 source')
    native=pkg['native_overlay'];require(inventory(native_output)==native['files'],'Native artifact inventory/hash mismatch')
    require(set(native['replacement_files'])==MODELS,'Unexpected native replacement set')
    probe=json.loads((native_output/'native-probe-report.json').read_text());patch=json.loads((native_output/'patch-report.json').read_text())
    require(probe['status']=='PASS' and probe['visual_acceptance'] is False and probe['continuous_clearance_certified'] is False,'Wrong native evidence scope')
    verified={}
    for name in sorted(MODELS):
        data=(native_output/Path(name).name).read_bytes();digest=hashlib.sha256(data).hexdigest();kind=Path(name).stem.removesuffix('_action')
        require(digest==after[name]==probe['units'][kind]['output_native_sha256']==patch[kind]['output_sha256'],'Native output binding failed')
        verified[name]=data
    original_rules=(project/'scripts/rules.gd').read_bytes()
    # The stamp programs themselves are original exact192 inputs, not new code.
    for name,data in verified.items():(project/name).write_bytes(data)
    stamped=subprocess.run([sys.executable,'-B',str(project/'tools/stamp_build.py'),'--root',str(project)],check=True,capture_output=True,text=True)
    require(stamped.stdout.strip()==BUILD,'Unexpected derived build')
    normalize=lambda b:re.sub(rb'const BUILD_ID = "[^"]*"',b'const BUILD_ID = "normalized"',b)
    require(normalize(original_rules)==normalize((project/'scripts/rules.gd').read_bytes()),'Nonstamp rules change')
    require(inventory(project)==after,'Final exact192 source mismatch')
    runtime=json.loads((project/'reports/build-manifest.json').read_text())
    require(runtime['build']==BUILD and sha(project/'reports/build-manifest.json')==pkg['runtime_manifest']['sha256'],'Runtime stamp mismatch')
    require(inventory(native_output)==native['files'],'Native inputs mutated')
    result={'status':'PASS FILE-ONLY STAGING; NOT RENDER OR PROMOTION','build':BUILD,'base_build':base['candidate'],'source_files':192,'unchanged_files':187,'changed_files':sorted(MODELS|STAMP),'package_sha256':PACKAGE_SHA,'base_package_sha256':sha(base_package),'runtime_manifest_sha256':sha(project/'reports/build-manifest.json'),'native_run_id':native['accepted_run_id'],'correction_source_manifest_sha256':native['correction_source_manifest_sha256'],'blender_source_updated':False,'rollback':{n:before[n] for n in sorted(MODELS|STAMP)}}
    receipt.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,sort_keys=True))
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('project','base-package','package','native-output','receipt'):parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();apply(args.project,args.base_package,args.package,args.native_output,args.receipt)
