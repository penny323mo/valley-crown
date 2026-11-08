#!/usr/bin/env python3
"""File-only assembly. No engine/process/network/external writes. Never enables execution."""
from pathlib import Path, PurePosixPath
import argparse, hashlib, importlib.util, json, re, shutil, stat, zipfile
KINDS=('villager','spearman','archer','scout')
MUTABLE={f'art/action_characters/{k}.blend' for k in KINDS}|{f'art/action_characters/interchange/{k}.glb' for k in KINDS}|{f'art/action_characters/textures/{k}_atlas.png' for k in KINDS}|{'reports/asset_manifest.json'}
IMMUTABLE={'art/action_characters/input-manifest.json'}|{f'art/action_characters/licenses/{n}.txt' for n in ('kaykit-animations','quaternius-base','quaternius-outfits','quaternius-ual','quaternius-ual2')}
GENERATOR='tools/build_licensed_action_characters.py'
SENSITIVE=[rb'/workspace/(?:scratch|shared)/',rb'/home/agent/',rb'/(?:agent_notes|user_notes)/',rb'gh[pousr]_[A-Za-z0-9]{20,}',rb'github_pat_[A-Za-z0-9_]{20,}',rb'AKIA[0-9A-Z]{16}',rb'sk-[A-Za-z0-9_-]{24,}',rb'xox[baprs]-[A-Za-z0-9-]{16,}',rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----']
def need(ok,message):
    if not ok: raise ValueError(message)
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def relative(name):
    need(type(name) is str and bool(name) and '\\' not in name,'Invalid relative name')
    p=PurePosixPath(name);need(not p.is_absolute() and all(x not in ('','.','..') for x in name.split('/')),'Unsafe relative name');return name

def regular(path):
    p=Path(path).absolute();need(not any(x.is_symlink() for x in (p,*p.parents)),'Symlink path');need(p.is_file(),'Missing regular input');return p

def digest(value):need(type(value) is str and re.fullmatch('[a-f0-9]{64}',value) is not None,'Missing actual SHA256');return value

def scan(data):need(not any(re.search(p,data) for p in SENSITIVE),'Public source privacy scan failed')

def inventory(root):
    out={};need(root.is_dir() and not root.is_symlink(),'Invalid tree root')
    for p in sorted(root.rglob('*')):
        need(not p.is_symlink() and (p.is_file() or p.is_dir()),'Tree special file')
        if p.is_file():out[relative(p.relative_to(root).as_posix())]=sha(p)
    return out

def json_file(path):
    def bad(x):raise ValueError('Nonfinite JSON')
    def pairs(rows):
        d={}
        for k,v in rows:need(k not in d,'Duplicate JSON key');d[k]=v
        return d
    return json.loads(regular(path).read_text(),parse_constant=bad,object_pairs_hook=pairs)

def validate_contract(c):
    need(c.get('schema')=='material-source-inputs-v1' and c.get('reviewed_for_assembly') is True,'Material assembly not reviewed')
    need(c.get('execution_enabled') is False,'Assembly cannot authorize execution')
    need(c.get('base_build')=='vc-fe500d2ea0b5','Wrong baseline')
    need(c.get('baseline_lock_sha256')=='36e6441b6dac681d4194a6d21e14c18660b38ea7082c1cddc7d9e48e5b07a93c','Wrong baseline lock')
    for key in ('generated_archive_sha256','generated_manifest_sha256','generator_sha256','generation_review_sha256','geometry_check_sha256'):digest(c.get(key))
    need(type(c.get('generation_run_id')) is int and c['generation_run_id']>0 and type(c.get('generation_artifact_id')) is int and c['generation_artifact_id']>0,'Missing real artifact identity')
    need(type(c.get('generation_commit')) is str and re.fullmatch('[a-f0-9]{40}',c['generation_commit']) is not None,'Missing exact generation commit')
    files=c.get('generated_files');need(type(files) is dict,'Missing actual generated inventory')
    for n,h in files.items():relative(n);digest(h)
    need(set(files) in (MUTABLE|IMMUTABLE,MUTABLE|IMMUTABLE|{'art/.gdignore'}),'Generated artifact inventory outside closed material scope')
    if 'art/.gdignore' in files:need(files['art/.gdignore']==hashlib.sha256(b'').hexdigest(),'Art ignore changed')
    need(files['reports/asset_manifest.json']==c['generated_manifest_sha256'],'Generated manifest not bound')
    need(c.get('changed_paths')==sorted(MUTABLE|{GENERATOR}),'Material source delta allowlist differs')
    return files

def archive_members(path,expected):
    need(Path(path).stat().st_size<=64*1024*1024,'Oversize generated archive')
    with zipfile.ZipFile(path) as z:
        rows=z.infolist();need(len(rows)==len(expected) and len({r.filename for r in rows})==len(rows) and {r.filename for r in rows}==set(expected),'Generated ZIP inventory differs')
        need(sum(r.file_size for r in rows)<=128*1024*1024,'Oversize generated extraction')
        data={}
        for row in rows:
            n=relative(row.filename);need(stat.S_IFMT(row.external_attr>>16) in (0,stat.S_IFREG),'ZIP special member');need(not row.flag_bits&1,'Encrypted ZIP forbidden')
            need(row.file_size<=32*1024*1024,'Oversize generated member')
            b=z.read(row);need(hashlib.sha256(b).hexdigest()==expected[n],'Generated member hash mismatch');scan(b);data[n]=b
        need(z.testzip() is None,'Generated ZIP CRC mismatch');return data

def write_json(path,obj):
    with Path(path).open('x') as f:json.dump(obj,f,indent=2,allow_nan=False);f.write('\n')

def assemble(a):
    contract=regular(a.inputs);need(sha(contract)==digest(a.inputs_sha256),'Assembly contract pin mismatch');c=json_file(contract);expected_generated=validate_contract(c)
    baseline=Path(a.baseline).absolute();baseline_lock=regular(a.baseline_lock)
    need(sha(baseline_lock)==c['baseline_lock_sha256'],'Baseline lock drift');base=json_file(baseline_lock)['files'];need(len(base)==192 and inventory(baseline)==base,'Baseline source changed')
    for key,path in [('generated_archive_sha256',a.generated_archive),('generator_sha256',a.generator),('generation_review_sha256',a.review),('geometry_check_sha256',a.geometry_check)]:need(sha(regular(path))==c[key],'Actual input pin mismatch: '+key)
    review=json_file(a.review)
    need(review.get('passed') is True and review.get('all_generation_phases_passed') is True and review.get('diagnostic_only') is False and review.get('artifact_id')==c['generation_artifact_id'] and review.get('run_id')==c['generation_run_id'] and review.get('archive_sha256')==c['generated_archive_sha256'],'Generation not independently reconciled')
    data=archive_members(a.generated_archive,expected_generated)
    for name in IMMUTABLE:need(hashlib.sha256(data[name]).hexdigest()==base[name],'Original license/input manifest changed')
    need(data.get('art/.gdignore',b'')==b'' and (baseline/'art/.gdignore').read_bytes()==b'','Editable art not ignored')
    manifest=json.loads(data['reports/asset_manifest.json']);need(set(manifest['units'])==set(KINDS),'Wrong current classes')
    for kind in KINDS:
        unit=manifest['units'][kind]
        for key,name in [('blend_sha256',f'art/action_characters/{kind}.blend'),('glb_sha256',f'art/action_characters/interchange/{kind}.glb')]:need(unit[key]==expected_generated[name],'Manifest unit data mismatch')
        need(unit['atlas']['atlas_sha256']==expected_generated[f'art/action_characters/textures/{kind}_atlas.png'],'Manifest atlas identity mismatch')
    out=Path(a.output).absolute();need(not out.exists(),'Output must be fresh')
    need(not out.is_relative_to(baseline) and not baseline.is_relative_to(out),'Source/output roots overlap')
    need(not any(p.is_symlink() for p in out.parents),'Output ancestor symlink')
    # Load only the exact independently reviewed pure data parser, no engine or code from archives.
    spec=importlib.util.spec_from_file_location('reviewed_nonmaterial_checker',a.geometry_check);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    out.mkdir();temporary=out/'generated-verified';temporary.mkdir()
    for name,b in data.items():p=temporary/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
    normalized=out/'generated-native-19';normalized.mkdir()
    normalized_hashes={n:expected_generated[n] for n in sorted(MUTABLE|IMMUTABLE)}
    for name in normalized_hashes:
        p=normalized/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data[name])
    need(inventory(normalized)==normalized_hashes,'Normalized exact19 artifact differs')
    write_json(out/'GENERATED_19_SHA256.json',normalized_hashes)
    geometry={}
    for kind in KINDS:
        name=f'art/action_characters/interchange/{kind}.glb';before=module.nonmaterial(baseline/name);after=module.nonmaterial(temporary/name)
        result={key:before[key]==after[key] for key in before};need(all(result.values()),'Nonmaterial GLB data changed: '+kind)
        geometry[kind]={'before_sha256':base[name],'after_sha256':expected_generated[name],'equal':result}
    project=out/'project';project.mkdir()
    for name in base:
        p=project/name;p.parent.mkdir(parents=True,exist_ok=True);source=data[name] if name in MUTABLE else (baseline/name).read_bytes()
        if name==GENERATOR:source=Path(a.generator).read_bytes()
        scan(source);p.write_bytes(source)
    final=inventory(project);need(set(final)==set(base),'Assembled source name drift')
    changes=sorted(n for n in final if final[n]!=base[n]);need(set(changes)<=MUTABLE|{GENERATOR} and GENERATOR in changes,'Material source delta differs')
    need(all(final[n]!=base[n] for n in MUTABLE),'A corrected material output still equals old pale source')
    lock={'schema':'material-assembled-source-v1','execution_enabled':False,'base_build':c['base_build'],'build':c['base_build'],'scope':'Exact 192-file material source replacement; inherited build is not corrected runtime acceptance',
          'material_inputs_sha256':sha(contract),'generated_archive_sha256':c['generated_archive_sha256'],'generated_manifest_sha256':c['generated_manifest_sha256'],'generator_sha256':c['generator_sha256'],
          'generation_review_sha256':c['generation_review_sha256'],'changed_paths':changes,'files':[{'file':n,'sha256':final[n],'size':(project/n).stat().st_size} for n in sorted(final)]}
    write_json(out/'assembled-source-lock.json',lock);write_json(out/'material-geometry-proof.json',{'passed':True,'checker_sha256':c['geometry_check_sha256'],'units':geometry,'scope':'Expanded oriented triangle/skin/node/animation data with exact decoded numeric equality; UV/color/image/material changes excluded'})
    archive=out/'material-source.zip'
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for n in sorted(final):
            row=zipfile.ZipInfo(n,date_time=(2026,1,1,0,0,0));row.compress_type=zipfile.ZIP_DEFLATED;row.external_attr=0o100644<<16;z.writestr(row,(project/n).read_bytes())
    receipt={'passed':True,'source_count':192,'changed_paths':changes,'source_archive_sha256':sha(archive),'assembled_lock_sha256':sha(out/'assembled-source-lock.json'),'geometry_proof_sha256':sha(out/'material-geometry-proof.json'),'execution_enabled':False,'runtime_build_pending':True,'native_generated_inventory_sha256':sha(out/'GENERATED_19_SHA256.json'),'native_generated_count':19,'verified_empty_art_ignore_omitted_from_native_input':('art/.gdignore' in data)}
    write_json(out/'assembly-receipt.json',receipt);return receipt

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('baseline','baseline-lock','generated-archive','generator','inputs','review','geometry-check','output'):p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--inputs-sha256',required=True);print(json.dumps(assemble(p.parse_args()),indent=2))
if __name__=='__main__':main()
