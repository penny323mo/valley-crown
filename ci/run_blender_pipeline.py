#!/usr/bin/env python3
"""One isolated, bounded licensed-character generation and reopen validation."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,os,sys,zipfile
H=Path(__file__).resolve().parent
PINS={'hardened_monitored_run.py':'4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50','build_licensed_action_characters.py':'73743e1da16e50260623d322dc70ff5ba2ca71053c062a5d0f7d2a2d19043486','validate_generated_glbs.py':'511f3bbdfad597072fa879670b86849fb5de4c8e5ba44366054b06aa760fc665','probe_generated_blends.py':'2159f25cc96f011ac1a9091ed5cce57abd386e1a96aa690754684b4593f89ff6'}
ZIP_SHA='145b44667a1a174cbf1efea19de9b081082a4e38fc1a808c80a731ad8d984e8a'
ARCHIVE_SHA='4da1c956673c0485e63054e563ee69198cc8f80d8157dd7592dffc8a6a5592e6'
MANIFEST_SHA='1cbfddb27a4ce08a765208d262f545e4bf560e382281caf505216c9be1f32bce'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def require(ok,msg):
 if not ok:raise RuntimeError(msg)
def stage_rejected_outputs(generated, inputs, destination, output_hashes):
 """Copy only closed, hash-bound generation outputs for rejected-file diagnosis."""
 import re,shutil,stat,struct
 kinds=('villager','spearman','archer','scout');base='art/action_characters/'
 license_names=('quaternius-base.txt','quaternius-ual.txt','quaternius-outfits.txt','quaternius-ual2.txt','kaykit-animations.txt')
 expected={'art/.gdignore','reports/asset_manifest.json',base+'input-manifest.json'}
 expected.update(base+'licenses/'+n for n in license_names)
 for kind in kinds:expected.update({base+kind+'.blend',base+'interchange/'+kind+'.glb',base+'textures/'+kind+'_atlas.png'})
 require(len(expected)==20,'Rejected-output allowlist size mismatch')
 require(generated.is_dir() and not generated.is_symlink() and not destination.exists(),'Rejected-output roots must be closed and fresh')
 require(all(not p.is_symlink() for p in generated.rglob('*')),'Rejected output symlink forbidden')
 require(all(stat.S_ISREG(p.lstat().st_mode) or stat.S_ISDIR(p.lstat().st_mode) for p in generated.rglob('*')),'Rejected output special file forbidden')
 files={p.relative_to(generated).as_posix():p for p in generated.rglob('*') if p.is_file()}
 require(set(files)==expected==set(output_hashes),'Rejected-output inventory differs from exact allowlist')
 sizes={n:p.stat().st_size for n,p in files.items()};require(sum(sizes.values())<128*1024*1024,'Rejected-output total size exceeded')
 for n,p in files.items():
  limit=32*1024*1024 if p.suffix in ('.blend','.glb') else 8*1024*1024 if p.suffix=='.png' else 2*1024*1024
  require(0<=sizes[n]<limit and (sizes[n]>0 or n=='art/.gdignore'),'Rejected-output file size outside bound: '+n)
  require(sha(p)==output_hashes[n],'Rejected output changed after generation: '+n)
  raw=p.read_bytes()
  private_paths=(b'/workspace/scratch',b'/workspace/shared',b'/home/agent',b'/agent_notes',b'/user_notes')
  secret_patterns=(rb'gh[pousr]_[A-Za-z0-9]{20,}',rb'github_pat_[A-Za-z0-9_]{20,}',rb'sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}',rb'AKIA[0-9A-Z]{16}',rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----')
  require(not any(marker in raw for marker in private_paths) and not any(re.search(pattern,raw) for pattern in secret_patterns),'Private path or credential signature in rejected bytes: '+n)
 manifest=json.loads(files['reports/asset_manifest.json'].read_text())
 require(manifest['blender']=='4.3.2' and manifest['input_manifest_sha256']==MANIFEST_SHA and set(manifest['units'])==set(kinds),'Rejected output manifest identity mismatch')
 require(sha(files[base+'input-manifest.json'])==MANIFEST_SHA==sha(inputs/'input-manifest.json'),'Rejected copied input manifest mismatch')
 input_manifest=json.loads((inputs/'input-manifest.json').read_text())
 require(files['art/.gdignore'].read_bytes()==b'','Unexpected gdignore bytes')
 for n in license_names:require(sha(files[base+'licenses/'+n])==input_manifest['files']['licenses/'+n]['sha256']==sha(inputs/'licenses'/n),'Rejected license provenance mismatch')
 def scan_text(value):
  if isinstance(value,dict):
   for k,v in value.items():scan_text(k);scan_text(v)
  elif isinstance(value,list):
   for v in value:scan_text(v)
  elif isinstance(value,str):
   require(not value.startswith(('/','file:','data:')) and not any(t in value for t in ('/home/','/workspace/','-----BEGIN PRIVATE','github_pat_','ghp_','sk-proj-')),'Unexpected private or local text in rejected manifest')
 scan_text(manifest)
 for kind in kinds:
  unit=manifest['units'][kind]
  for n,key in [(base+kind+'.blend','blend_sha256'),(base+'interchange/'+kind+'.glb','glb_sha256')]:require(output_hashes[n]==unit[key],'Rejected unit hash mismatch')
  n=base+'textures/'+kind+'_atlas.png';require(output_hashes[n]==unit['atlas']['atlas_sha256'],'Rejected atlas hash mismatch')
  require(files[base+kind+'.blend'].read_bytes()[:7]==b'BLENDER','Rejected blend header mismatch')
  raw=files[base+'interchange/'+kind+'.glb'].read_bytes();require(struct.unpack_from('<III',raw)==(0x46546c67,2,len(raw)),'Rejected GLB header mismatch')
  raw=files[n].read_bytes();require(raw[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II',raw,16)==(1024,1024),'Rejected atlas header mismatch')
 # No copying occurs until inventory, size, format, provenance and hash checks pass.
 destination.mkdir()
 for n,p in files.items():
  dest=destination/'files'/n;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest);require(sha(dest)==output_hashes[n],'Rejected copy hash mismatch')
 report={'status':'UNVALIDATED_REJECTED_OUTPUTS','acceptance':'DIAGNOSTIC ONLY. Do not integrate or claim corrected rendering.','count':20,'total_bytes':sum(sizes.values()),'files':{n:{'sha256':output_hashes[n],'bytes':sizes[n]} for n in sorted(expected)},'checks':['exact closed 20-file allowlist','no symlinks or special files','all staged bytes private-path/credential-signature scan','per-file and total size bounds','post-generation hashes unchanged','pinned input/license identity','generated unit/atlas manifest hashes','expected binary formats','manifest private/local text scan']}
 (destination/'STATUS.json').write_text(json.dumps(report,indent=2)+'\n');return report

def main():
 p=argparse.ArgumentParser();p.add_argument('--blender',required=True,type=Path);p.add_argument('--blender-archive',required=True,type=Path);p.add_argument('--inputs-zip',required=True,type=Path);a=p.parse_args()
 evidence=Path('evidence').resolve();private=Path('private').resolve();generated=Path('generated').resolve();inputs=Path('inputs').resolve()
 require(not any(x.exists() for x in [evidence,private,generated,inputs]),'Output roots must be fresh')
 evidence.mkdir();private.mkdir();inputs.mkdir()
 for n,h in PINS.items():require(sha(H/n)==h,'Helper hash mismatch: '+n)
 require(sha(a.inputs_zip)==ZIP_SHA,'Input ZIP hash mismatch');require(sha(a.blender_archive)==ARCHIVE_SHA,'Official Blender archive mismatch')
 with zipfile.ZipFile(a.inputs_zip) as z:
  require(z.testzip() is None and len(z.infolist())==27,'Input ZIP inventory mismatch')
  for info in z.infolist():
   name=Path(info.filename);require(not name.is_absolute() and '..' not in name.parts and info.external_attr>>16&0o170000!=0o120000,'Unsafe archive member');z.extract(info,inputs)
 require(sha(inputs/'input-manifest.json')==MANIFEST_SHA,'Input manifest mismatch')
 m=json.loads((inputs/'input-manifest.json').read_text()); expected=m['files']
 require({x.relative_to(inputs).as_posix() for x in inputs.rglob('*') if x.is_file()}==set(expected)|{'input-manifest.json'},'Input allowlist mismatch')
 for n,v in expected.items():require(sha(inputs/n)==v['sha256'],'Input hash mismatch: '+n)
 spec=importlib.util.spec_from_file_location('guard',H/'hardened_monitored_run.py');guard=importlib.util.module_from_spec(spec);sys.modules[spec.name]=guard;spec.loader.exec_module(guard)
 env={k:os.environ[k] for k in ['PATH','LANG','LC_ALL','TZ'] if k in os.environ}
 for k,n in [('HOME','home'),('TMPDIR','tmp'),('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data'),('XDG_CACHE_HOME','cache')]:
  d=private/n;d.mkdir();env[k]=str(d)
 env.update({'OMP_NUM_THREADS':'1','OPENBLAS_NUM_THREADS':'1'})
 artifacts={n:H/n for n in PINS};artifacts.update({'wrapper':Path(__file__),'official-archive':a.blender_archive.resolve(),'input-zip':a.inputs_zip.resolve(),'blender':a.blender.resolve()})
 artifacts.update({'input:'+x.relative_to(inputs).as_posix():x for x in inputs.rglob('*') if x.is_file()});digests={n:sha(v) for n,v in artifacts.items()}
 limits=guard.Limits(timeout_s=900,sample_target_s=.05,terminate_grace_s=5,kill_reap_grace_s=5,launch_min_available_kib=6291456,runtime_min_available_kib=2097152,max_rss_kib=4194304)
 summary={'passed':False,'scope':'Licensed prototype generation and data/deformation validation; not artistic or runtime acceptance','commands':[]}
 def save(): (evidence/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
 def invoke(name,cmd):
  print('START '+name,flush=True);r=guard.run(evidence/name,cmd,env=env,limits=limits,artifacts=artifacts,expected_artifact_hashes=digests)
  row={k:r[k] for k in ['passed','exit','stop_reason','cleanup_complete','seconds','sampled_peak_rss_kib']};row['name']=name;summary['commands'].append(row);save();print(json.dumps(row),flush=True);require(r['passed'] and r['cleanup_complete'],'Guarded phase failed: '+name)
 save()
 try:
  blender=str(a.blender.resolve()); prefix=[blender,'--background','--factory-startup','--disable-autoexec','--threads','1','--python-exit-code','1']
  invoke('generate',prefix+['--python',str(H/'build_licensed_action_characters.py'),'--','--inputs',str(inputs),'--input-manifest-sha256',MANIFEST_SHA,'--output-root',str(generated)])
  for x in generated.rglob('*'):
   require(not x.is_symlink(),'Generated symlink rejected')
   if x.is_file():artifacts['output:'+x.relative_to(generated).as_posix()]=x;digests['output:'+x.relative_to(generated).as_posix()]=sha(x)
  invoke('validate-glbs',[sys.executable,str(H/'validate_generated_glbs.py'),'--output-root',str(generated),'--inputs',str(inputs),'--report',str(evidence/'glb-data.json')])
  invoke('reopen-deformation',prefix+['--python',str(H/'probe_generated_blends.py'),'--','--output-root',str(generated),'--inputs',str(inputs),'--report',str(evidence/'blend-deformation.json')])
  summary['output_sha256']={x.relative_to(generated).as_posix():sha(x) for x in generated.rglob('*') if x.is_file()};summary['passed']=True;save();return 0
 except BaseException as e:
  summary['error']={'type':type(e).__name__,'message':str(e)}
  if summary['commands'] and summary['commands'][0]['passed'] and all(row['cleanup_complete'] for row in summary['commands']):
   try:summary['rejected_output']=stage_rejected_outputs(generated,inputs,Path('rejected-output').resolve(),{n[7:]:h for n,h in digests.items() if n.startswith('output:')})
   except BaseException as stage_error:summary['rejected_output_error']={'type':type(stage_error).__name__,'message':str(stage_error)}
  save();print(json.dumps(summary['error']),flush=True);return 1
if __name__=='__main__':sys.exit(main())
