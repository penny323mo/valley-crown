#!/usr/bin/env python3
"""File-only native-delta packaging for a separately reviewed hosted render run."""
from pathlib import Path
import argparse, copy, hashlib, json, re, zipfile
ASSEMBLY_HELPER_SHA = '732f1b634788bd15d5dad4211a1f876468ed76455e6be11cfdff7057d7be2487'
_HELPER = Path(__file__).with_name('assemble_material_source.py').absolute()
if any(p.is_symlink() for p in (_HELPER,*_HELPER.parents)) or not _HELPER.is_file() or hashlib.sha256(_HELPER.read_bytes()).hexdigest()!=ASSEMBLY_HELPER_SHA:
    raise RuntimeError('Bound assembly helper differs')
from assemble_material_source import need,sha,regular,inventory,json_file,archive_members,write_json,digest
NATIVE={f'assets/mature/models/{k}_action.scn' for k in ('villager','spearman','archer','scout')}
RULES='scripts/rules.gd';BUILD='reports/build-manifest.json'
UIDS={f'tests/{n}.gd.uid' for n in ('occlusion_geometry_contract','occlusion_observation_lifecycle','occlusion_stencil_contract','occlusion_stencil_matrix','occlusion_viewport_lifecycle')}
BUILD_RE=rb'const BUILD_ID = "[^"\n]*"'

def prepare(a):
    need(sha(regular(a.inputs))==digest(a.inputs_sha256),'Render source contract mismatch');c=json_file(a.inputs)
    need(c.get('schema')=='material-render-source-v1' and c.get('reviewed_for_packaging') is True and c.get('execution_enabled') is False,'Render source packaging disabled')
    pairs=[('assembled_lock_sha256',a.assembled_lock),('native_archive_sha256',a.native_archive),('native_final_lock_sha256',a.native_final_lock),('native_receipt_sha256',a.native_receipt),('native_review_sha256',a.native_review),('baseline_package_sha256',a.baseline_package)]
    for key,p in pairs:need(sha(regular(p))==digest(c.get(key)),'Actual render input mismatch: '+key)
    need(type(c.get('native_run_id')) is int and c['native_run_id']>0 and type(c.get('native_artifact_id')) is int and c['native_artifact_id']>0,'Missing native artifact identity')
    digest(c.get('native_artifact_archive_sha256'))
    review=json_file(a.native_review);need(review.get('passed') is True and review.get('run_id')==c['native_run_id'] and review.get('artifact_id')==c['native_artifact_id'] and review.get('artifact_archive_sha256')==c['native_artifact_archive_sha256'] and review.get('runtime_delta_sha256')==c['native_archive_sha256'],'Native output not independently accepted')
    assembled=json_file(a.assembled_lock);initial={r['file']:r['sha256'] for r in assembled['files']}
    project=Path(a.assembled_project).absolute();need(len(initial)==192 and inventory(project)==initial,'Assembled source changed')
    receipt=json_file(a.native_receipt);final=json_file(a.native_final_lock);need(final.get('source_input_lock_sha256')==c['assembled_lock_sha256'],'Native output not bound to assembled material source');entries={r['file']:r['sha256'] for r in final['files']}
    need(len(entries)==len(final['files'])==197 and set(entries)==set(initial)|UIDS,'Final native source inventory differs')
    need(receipt['build']==final['build'] and re.fullmatch('vc-[a-f0-9]{12}',final['build']) and final['build']!='vc-fe500d2ea0b5','Native build not fresh')
    need(receipt['final_source_lock_sha256']==c['native_final_lock_sha256'] and receipt['archive_sha256']==c['native_archive_sha256'],'Native receipt binding mismatch')
    expected_delta=NATIVE|{RULES,BUILD}|UIDS;need(set(receipt['member_sha256'])==expected_delta,'Native delta scope differs')
    delta=archive_members(a.native_archive,receipt['member_sha256'])
    need(all(entries[n]==initial[n] for n in initial if n not in NATIVE|{RULES,BUILD}),'Non-native source changed')
    need(all(hashlib.sha256(b).hexdigest()==entries[n] for n,b in delta.items()),'Delta/final lock mismatch')
    rules=delta[RULES];need(len(re.findall(BUILD_RE,rules))==1 and ('const BUILD_ID = "'+final['build']+'"').encode() in rules,'Final rules stamp differs')
    restored=re.sub(BUILD_RE,b'const BUILD_ID = "vc-fe500d2ea0b5"',rules);need(hashlib.sha256(restored).hexdigest()==initial[RULES],'Gameplay rules changed')
    runtime=json.loads(delta[BUILD]);need(runtime['build']==final['build'] and runtime['engine']=='4.6.3.stable.official.7d41c59c4','Runtime descriptor differs')
    need(len(runtime['source_sha256'])==122,'Runtime input scope differs')
    h=hashlib.sha256()
    for n,d in sorted(runtime['source_sha256'].items()):
        need(entries.get(n)==d,'Runtime file outside final source');b=delta[n] if n in delta else (project/n).read_bytes();need(hashlib.sha256(b).hexdigest()==d,'Runtime input differs')
        if n==RULES:b=re.sub(BUILD_RE,b'const BUILD_ID = "normalized"',b)
        h.update(n.encode());h.update(b'\0');h.update(b)
    need('vc-'+h.hexdigest()[:12]==final['build'],'Runtime ID recomputation differs')
    out=Path(a.output).absolute();need(not out.exists() and not out.is_relative_to(project) and not project.is_relative_to(out),'Packaging root not fresh/disjoint');need(not any(p.is_symlink() for p in out.parents),'Packaging ancestor symlink')
    out.mkdir();render=out/'project';render.mkdir()
    for n in sorted(entries):
        p=render/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(delta[n] if n in delta else (project/n).read_bytes())
    need(inventory(render)==entries,'Packaged source drift')
    archive=out/'material-render-source.zip'
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for n in sorted(entries):
            row=zipfile.ZipInfo(n,date_time=(2026,1,1,0,0,0));row.compress_type=zipfile.ZIP_DEFLATED;row.external_attr=0o100644<<16;z.writestr(row,(render/n).read_bytes())
    baseline=json_file(a.baseline_package);need(baseline['candidate']=='vc-fe500d2ea0b5' and sha(a.baseline_package)=='ac489bbd227660dd1629b74e6351e68ea86c17bae9bf56e3fb1a2c7430f0ae91','Wrong accepted import manifest template')
    suites=copy.deepcopy(baseline['suites'])
    for suite in suites:
        need(entries[suite['script']]==suite['script_sha256'],'Inherited compatibility metadata drift')
        suite['report_contract']['required_field_values']['build']=final['build']
        ext=suite['report_contract']['required_external_receipt'];ext['candidate_build']=final['build'];ext['runtime_manifest_sha256']=entries[BUILD]
    package={'candidate':final['build'],'engine_expected':runtime['engine'],'execution_enabled':False,'scope':'Exact material native source for separately reviewed clean import and raw material renders only; no export/deployment',
       'source_archive_sha256':sha(archive),'files':[{'file':n,'sha256':entries[n],'size':(render/n).stat().st_size} for n in sorted(entries)],
       'runtime_manifest':{'file':BUILD,'sha256':entries[BUILD],'inputs':len(runtime['source_sha256'])},'suites':suites,
       'inherited_suites_status':'Import adapter schema compatibility only. These inherited suites are NOT RUN and give no new acceptance.',
       'native_final_lock_sha256':c['native_final_lock_sha256'],'native_review_sha256':c['native_review_sha256']}
    write_json(out/'MATERIAL_RENDER_SOURCE_PACKAGE.json',package)
    result={'passed':True,'build':final['build'],'source_count':197,'runtime_count':122,'source_archive_sha256':sha(archive),'manifest_sha256':sha(out/'MATERIAL_RENDER_SOURCE_PACKAGE.json'),'execution_enabled':False,'render_not_run':True}
    write_json(out/'render-source-receipt.json',result);return result

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('inputs','assembled-project','assembled-lock','native-archive','native-final-lock','native-receipt','native-review','baseline-package','output'):p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--inputs-sha256',required=True);print(json.dumps(prepare(p.parse_args()),indent=2))
if __name__=='__main__':main()
