#!/usr/bin/env python3
"""Fail-closed material-native result scanner. Reject private data; never redact evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import stat
import zipfile
import tempfile
import run_material_native as gate
PHASES = ('import','material-baseline','native-pack','reload-diagnostic','material-proof','stamp','reload-final')
SUFFIXES = ('.before.json','.json','.invocation.json','.log')
EVIDENCE = {'summary.json'} | {p+s for p in PHASES for s in SUFFIXES} | {p+'.report.json' for p in PHASES if p!='import'}
RUNTIME = {'accepted-runtime/'+n for n in ('runtime-delta.zip','final-source-lock.json','receipt.json')}
PATTERNS = (rb'/workspace/(?:scratch|shared)/',rb'/(?:agent_notes|user_notes)/',rb'/home/agent/',rb'gh[pousr]_[A-Za-z0-9]{20,}',rb'github_pat_[A-Za-z0-9_]{20,}',rb'AKIA[0-9A-Z]{16}',rb'sk-[A-Za-z0-9_-]{24,}',rb'xox[baprs]-[A-Za-z0-9-]{16,}',rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----')
def scan(data, text=True):
    gate.require(not any(re.search(p,data) for p in PATTERNS),'Private path/token in output')
    if text: data.decode('utf-8')
def run(args):
    controls=gate.bind_material_inputs(args)
    review=gate.read_json(args.review_pin)
    expected_commands=gate.expected_phase_argv(review.get('execution_paths'))
    root=gate.clean_path(args.evidence)
    files=gate.inventory(root)
    gate.require(set(files)==EVIDENCE|RUNTIME,'Missing or unknown evidence file')
    gate.require(sum((root/n).stat().st_size for n in files)<=192*1024*1024,'Evidence too large')
    for n in files:
        gate.require((root/n).stat().st_size<=64*1024*1024,'Oversized evidence')
        if not n.endswith('.zip'):
            scan((root/n).read_bytes())
            if n.endswith('.json'): gate.read_json(root/n)
    summary=gate.read_json(root/'summary.json')
    gate.require(summary.get('passed') is True and summary.get('source_lock_sha256')==gate.SOURCE_LOCK_SHA,'Unaccepted/unbound runtime')
    gate.require([r['name'] for r in summary['commands']]==list(PHASES),'Phase coverage differs')
    for row in summary['commands']:
        name=row['name']; result=gate.read_json(root/(name+'.json')); invocation=gate.read_json(root/(name+'.invocation.json'))
        gate.require(result.get('passed') is True and result.get('cleanup_complete') is True and result.get('child_started') is True and type(result.get('exit')) is int and result['exit']==0,'Process did not pass')
        gate.require(not any(result.get(k) for k in ('stop_reason','exception','cleanup_errors','output_errors')),'Process errors')
        gate.require(result['invocation_sha256']==files[name+'.invocation.json'] and result['log_sha256']==files[name+'.log'],'Receipt drift')
        gate.require(invocation['helper']['load_sha256']==invocation['helper']['invocation_sha256']==gate.MONITOR_SHA,'Monitor drift')
        gate.require(invocation.get('test_dependencies') is False and invocation['argv']==invocation['requested_argv']==expected_commands[name],'Injected invocation')
        bindings=result.get('post_run_binding_matches',{})
        gate.require({'helper','executable'}|{'artifact:'+k for k in invocation['artifacts']} <= set(bindings) and all(v is True for v in bindings.values()),'Missing/failed postrun binding')
        for key,digest in {'adapter':gate.LOADED_ADAPTER_SHA,'engine':gate.ENGINE_SHA,'monitor':gate.MONITOR_SHA,'source-lock':gate.SOURCE_LOCK_SHA}.items(): gate.require(invocation['artifacts'][key]['sha256']==digest,'Core control binding differs')
        for key,(_,digest) in controls.items(): gate.require(invocation['artifacts'][key]['sha256']==digest,'Control binding differs')
        for key,suffix in [('before_inventory_sha256','.before.json'),('receipt_sha256','.json'),('invocation_sha256','.invocation.json'),('log_sha256','.log')]: gate.require(row[key]==files[name+suffix],'Summary receipt drift')
        if name != 'import':
            gate.require(row['validated_report']['sha256'] == files[name+'.report.json'] and row['validated_report']['path'] == name+'.report.json','Validated report not bound to delivered bytes')
        for prior in PHASES[:PHASES.index(name)]:
            for suffix in SUFFIXES + (() if prior=='import' else ('.report.json',)):
                n=prior+suffix
                gate.require(invocation['artifacts']['prior-evidence:'+n]['sha256']==files[n], 'Prior evidence not frozen')
    receipt=gate.read_json(root/'accepted-runtime/receipt.json');lock=gate.read_json(root/'accepted-runtime/final-source-lock.json')
    gate.require(receipt['final_source_lock_sha256']==files['accepted-runtime/final-source-lock.json'],'Lock drift')
    archive=root/'accepted-runtime/runtime-delta.zip'
    gate.require(receipt['archive_sha256']==files['accepted-runtime/runtime-delta.zip'] and receipt['archive_bytes']==archive.stat().st_size,'Archive drift')
    gate.require(receipt['build']==lock['build']==summary['runtime_build'] and receipt['build']!='vc-fe500d2ea0b5','Build identity drift')
    initial={r['file']:r['sha256'] for r in gate.read_json(args.source_lock)['files']}
    gate.require_exact(gate.inventory(gate.clean_path(args.project)),initial,'Scanner requires original assembled source, never stamped project')
    full={r['file']:r['sha256'] for r in lock['files']};members=receipt['member_sha256']
    required=gate.NATIVE|{gate.RULES,gate.BUILD_REPORT}
    uids={n+'.uid' for n in initial if n.endswith(('.gd','.gdshader')) and n+'.uid' not in initial}
    gate.require(len(full)==len(lock['files']) and set(full)==set(initial)|set(members),'Final inventory differs')
    gate.require(required<=set(members)<=required|uids,'Delta inventory differs')
    gate.require(all(full[n]==h for n,h in initial.items() if n not in required),'Forbidden source drift')
    with zipfile.ZipFile(archive) as z:
        gate.require(len(z.namelist())==len(set(z.namelist())) and set(z.namelist())==set(members) and z.testzip() is None,'Unsafe ZIP inventory')
        gate.require(sum(i.file_size for i in z.infolist())<=128*1024*1024,'Oversized ZIP')
        for item in z.infolist():
            n=gate.relative(item.filename)
            gate.require(stat.S_IFMT(item.external_attr>>16) in (0,stat.S_IFREG),'Nonregular ZIP member')
            data=z.read(item);scan(data,False)
            gate.require(hashlib.sha256(data).hexdigest()==members[n]==full[n],'Member drift')
            if n==gate.RULES:
                original=(gate.clean_path(args.project)/n).read_bytes()
                gate.require(('const BUILD_ID = "'+receipt['build']+'"').encode() in data and hashlib.sha256(re.sub(gate.BUILD_RE,b'const BUILD_ID = "vc-fe500d2ea0b5"',data)).hexdigest()==initial[gate.RULES], 'Stamped rule reconstruction differs from accepted source')
                gate.require(len(re.findall(gate.BUILD_RE,data))==1 and re.sub(gate.BUILD_RE,b'normalized',data)==re.sub(gate.BUILD_RE,b'normalized',original),'Rule logic drift')
    # Independently replay report semantics against verified final bytes, without an engine.
    with tempfile.TemporaryDirectory(prefix='material-native-scan-') as temp:
        assembled=Path(temp)/'project'
        shutil.copytree(gate.clean_path(args.project),assembled)
        with zipfile.ZipFile(archive) as z:
            for n in members:
                target=assembled/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(n))
        manifest=gate.read_json(assembled/'reports/asset_manifest.json')
        for phase,target in [('native-pack',gate.IMPORT_REPORT),('material-proof','reports/native-material-proof.json')]:
            (assembled/target).write_bytes((root/(phase+'.report.json')).read_bytes())
        gate.validate_import_report(assembled,manifest)
        gate.validate_material_report(assembled)
        for phase in ('reload-diagnostic','reload-final'):
            (assembled/gate.TEST_REPORT).write_bytes((root/(phase+'.report.json')).read_bytes())
            gate.validate_test_report(assembled,manifest)
        gate.require((assembled/gate.BUILD_REPORT).read_bytes()==(root/'stamp.report.json').read_bytes(),'Stamp delivered report differs from runtime')
        gate.validate_stamp(assembled,(gate.clean_path(args.project)/gate.RULES).read_bytes(),full)
        baseline=gate.read_json(root/'material-baseline.report.json')
        gate.require(set(baseline)==set(gate.KINDS),'Baseline material class coverage differs')
        for kind in gate.KINDS:
            gate.require(baseline[kind]['native_sha256']==initial[f'assets/mature/models/{kind}_action.scn'], 'Material baseline source differs')
    destination=gate.clean_path(args.destination)
    gate.require(not destination.exists() and not destination.is_relative_to(root),'Fresh disjoint staging required')
    destination.mkdir()
    for n in sorted(files):
        target=destination/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(root/n,target)
    gate.write_json(destination/'scan.json',{'passed':True,'files_sha256':files})

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for n in ('inputs','review-pin','baseline-lock','generated-inventory','generated','probe','source-lock','project','evidence','destination'): parser.add_argument('--'+n,type=Path,required=True)
    parser.add_argument('--inputs-sha256',required=True)
    run(parser.parse_args())
if __name__=='__main__':main()
