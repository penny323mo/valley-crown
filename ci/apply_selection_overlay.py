"""File-only exact three-file apply/rollback on a DISPOSABLE source copy."""
from pathlib import Path,PurePosixPath
import argparse,hashlib,json,stat,zipfile
PACKAGE_SHA='69f5b245bcef0ea5e438a0a49195af37cb426ff7059d71c1a986b671f809c0c3'
CHANGED={'scripts/game.gd','scripts/rules.gd','reports/build-manifest.json'}
def require(ok,message):
 if not ok:raise ValueError(message)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def safe(path):
 path=Path(path).absolute()
 require(not any(p.is_symlink() for p in [path,*path.parents]),'Symlink path rejected')
 return path
def inventory(root):
 safe(root);require(root.is_dir(),'Missing project');result={}
 for p in root.rglob('*'):
  mode=p.lstat().st_mode;require(not stat.S_ISLNK(mode),'Source symlink rejected')
  if stat.S_ISDIR(mode):continue
  require(stat.S_ISREG(mode),'Special source rejected');result[str(p.relative_to(root))]=sha(p)
 return result
def entries(rows):
 result={}
 for row in rows:
  n=row['file'];p=PurePosixPath(n)
  require(n and not p.is_absolute() and '\\' not in n and all(x not in ('','.','..') for x in n.split('/')) and n not in result,'Unsafe/duplicate name')
  result[n]=row['sha256']
 require(len(result)==192,'Expected exact192');return result
def apply(project,base_package,package,overlay,receipt,rollback=False):
 project,base_package,package,overlay,receipt=map(safe,[project,base_package,package,overlay,receipt])
 require(sha(package)==PACKAGE_SHA,'Package mismatch');pkg=json.loads(package.read_text())
 require(sha(base_package)==pkg['base_package_sha256'],'Base package mismatch')
 base=json.loads(base_package.read_text());before=entries(base['files']);after=entries(pkg['files'])
 require(before==entries(pkg['base_files']),'Base binding mismatch')
 require(base['candidate']=='vc-d99ac5d19247' and pkg['candidate']=='vc-f605f947768e' and pkg['execution_enabled'] is False,'Identity mismatch')
 require(set(before)==set(after) and {n for n in before if before[n]!=after[n]}==CHANGED,'Unexpected source delta')
 require(not receipt.exists() and not receipt.is_relative_to(project) and receipt not in [base_package,package,overlay],'Fresh external receipt required')
 require(sha(overlay)==pkg['rollback_sha256' if rollback else 'overlay_sha256'],'Overlay mismatch')
 if rollback:before,after=after,before
 require(inventory(project)==before,'Disposable project is not exact expected source')
 verified={}
 with zipfile.ZipFile(overlay) as z:
  require(len(z.infolist())==3 and set(z.namelist())==CHANGED and z.testzip() is None,'Wrong overlay inventory/CRC')
  for info in z.infolist():
   require(not info.is_dir() and stat.S_IFMT(info.external_attr>>16)==stat.S_IFREG,'Nonregular overlay entry')
   data=z.read(info);require(hashlib.sha256(data).hexdigest()==after[info.filename],'Overlay member mismatch');verified[info.filename]=data
 for name,data in verified.items():(project/name).write_bytes(data)
 require(inventory(project)==after,'Final source mismatch')
 result={'passed':True,'scope':'File-only exact source rollback' if rollback else 'File-only exact source apply; not runtime or render acceptance','candidate':'vc-d99ac5d19247' if rollback else pkg['candidate'],'changed_files':sorted(CHANGED),'source_files':192,'package_sha256':PACKAGE_SHA,'overlay_sha256':sha(overlay)}
 with receipt.open('x') as f:json.dump(result,f,indent=2);f.write('\n')
 return result
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__)
 for n in ['project','base-package','package','overlay','receipt']:p.add_argument('--'+n,type=Path,required=True)
 p.add_argument('--rollback',action='store_true');a=p.parse_args()
 print(json.dumps(apply(a.project,a.base_package,a.package,a.overlay,a.receipt,a.rollback),sort_keys=True))
