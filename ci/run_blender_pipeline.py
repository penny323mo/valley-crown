#!/usr/bin/env python3
"""One isolated, bounded licensed-character generation and reopen validation."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,os,sys,zipfile
H=Path(__file__).resolve().parent
PINS={'hardened_monitored_run.py':'4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50','build_licensed_action_characters.py':'165b26611ec5ed6a9d235f919049cb63895e44dae2149d8cfee686f8e4520b5a','validate_generated_glbs.py':'09552b32857692a588b4d29774b0e5035ea725dce328b0526f5658b1f4792008','probe_generated_blends.py':'0796d6c2c8c3babbd5b82e904f6daf4865af2eb3e471b5f6b363ac37331e3a94'}
ZIP_SHA='145b44667a1a174cbf1efea19de9b081082a4e38fc1a808c80a731ad8d984e8a'
ARCHIVE_SHA='4da1c956673c0485e63054e563ee69198cc8f80d8157dd7592dffc8a6a5592e6'
MANIFEST_SHA='1cbfddb27a4ce08a765208d262f545e4bf560e382281caf505216c9be1f32bce'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def require(ok,msg):
 if not ok:raise RuntimeError(msg)
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
  invoke('validate-glbs',[sys.executable,str(H/'validate_generated_glbs.py'),'--output-root',str(generated),'--report',str(evidence/'glb-data.json')])
  invoke('reopen-deformation',prefix+['--python',str(H/'probe_generated_blends.py'),'--','--output-root',str(generated),'--report',str(evidence/'blend-deformation.json')])
  summary['output_sha256']={x.relative_to(generated).as_posix():sha(x) for x in generated.rglob('*') if x.is_file()};summary['passed']=True;save();return 0
 except BaseException as e:
  summary['error']={'type':type(e).__name__,'message':str(e)};save();print(json.dumps(summary['error']),flush=True);return 1
if __name__=='__main__':sys.exit(main())
