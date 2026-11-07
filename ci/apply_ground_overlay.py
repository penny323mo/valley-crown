"""Hash-bound file-only overlay. No engine, import, archive regeneration or network."""
from pathlib import Path, PurePosixPath
import argparse, hashlib, json, re, stat, zipfile
PACKAGE_SHA='cea648726cee0bb525fe835e6750021058c0997963dfbc6f1a01467af809435c'
BUILD='vc-8bf358474c6a'
ALLOWED={'assets/mature/terrain/ground.gdshader','scripts/rules.gd','reports/build-manifest.json'}
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,msg):
 if not ok: raise ValueError(msg)
def inventory(root):
 require(root.is_dir() and not root.is_symlink(),'Invalid root')
 result={}
 for p in root.rglob('*'):
  require(not p.is_symlink(),'Symlink rejected')
  if p.is_dir(): continue
  require(p.is_file(),'Special entry rejected')
  result[p.relative_to(root).as_posix()]=sha(p)
 return result
def apply(project,base_package,package,overlay):
 require(sha(package)==PACKAGE_SHA,'Package hash mismatch')
 pkg=json.loads(package.read_text())
 require(sha(base_package)==pkg['base_package_sha256'],'Base package hash mismatch')
 base=json.loads(base_package.read_text())
 require(base['candidate']=='vc-43276605e0fb' and pkg['candidate']==BUILD,'Wrong identities')
 before={r['file']:r['sha256'] for r in base['files']};after={r['file']:r['sha256'] for r in pkg['files']}
 require(len(before)==len(base['files'])==len(after)==len(pkg['files'])==192,'Wrong source counts')
 require(before.keys()==after.keys() and {n for n in after if before[n]!=after[n]}==ALLOWED,'Invalid delta')
 require(inventory(project)==before,'Initial exact source mismatch')
 require(sha(overlay)==pkg['ground_overlay']['sha256'] and overlay.stat().st_size<100000,'Overlay mismatch')
 verified={}
 with zipfile.ZipFile(overlay) as z:
  require(len(z.infolist())==3 and set(z.namelist())==ALLOWED,'Wrong members')
  require(sum(i.file_size for i in z.infolist())<100000,'Expansion bound exceeded')
  for i in z.infolist():
   n=i.filename
   require(not PurePosixPath(n).is_absolute() and all(x not in ('','.','..') for x in n.split('/')) and '\\' not in n,'Unsafe name')
   require(stat.S_IFMT(i.external_attr>>16) in (0,stat.S_IFREG),'Special member')
   data=z.read(i)
   require(hashlib.sha256(data).hexdigest()==after[n]==pkg['ground_overlay']['files'][n],'Member mismatch')
   verified[n]=data
 # Validate complete prospective stamp before writing anything.
 runtime=json.loads(verified['reports/build-manifest.json']);h=hashlib.sha256()
 require(runtime['build']==BUILD and len(runtime['source_sha256'])==122,'Invalid runtime manifest')
 for n,digest in sorted(runtime['source_sha256'].items()):
  require(after.get(n)==digest,'Runtime input mismatch')
  data=verified[n] if n in verified else (project/n).read_bytes()
  if n=='scripts/rules.gd':
   require(re.findall(rb'const BUILD_ID = "([^"]*)"',data)==[BUILD.encode()],'Rules stamp mismatch')
   data=re.sub(rb'const BUILD_ID = "[^"]*"',b'const BUILD_ID = "normalized"',data)
  h.update(n.encode());h.update(b'\0');h.update(data)
 require('vc-'+h.hexdigest()[:12]==BUILD,'Calculated stamp mismatch')
 for n,data in verified.items(): (project/n).write_bytes(data)
 require(inventory(project)==after,'Final exact source mismatch')
 print(json.dumps({'passed':True,'build':BUILD,'source_files':192,'changed_files':sorted(ALLOWED),'scope':'File-only, not rendered'}))
if __name__=='__main__':
 p=argparse.ArgumentParser()
 for n in ('project','base-package','package','overlay'):p.add_argument('--'+n,type=Path,required=True)
 a=p.parse_args();apply(a.project,a.base_package,a.package,a.overlay)
