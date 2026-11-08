#!/usr/bin/env python3
"""Disabled-until-reviewed hosted native wiring. Invoked only by reviewed template."""
import argparse,hashlib,importlib.util,json,os,shutil,stat,subprocess,sys,zipfile
from pathlib import Path
from reconstruct_baseline import inventory,need,regular,sha

def bound(root,entry):
    need(type(entry) is dict and set(entry)=={'path','sha256'},'Missing bound delivery file')
    need(type(entry['sha256']) is str and len(entry['sha256'])==64,'Unbound delivery file hash')
    path=Path(entry['path']);need(not path.is_absolute() and '..' not in path.parts,'Unsafe delivery path')
    path=regular(root/path);need(sha(path)==entry['sha256'],'Delivery file changed');return path

def scanner_allowlist(scanner_path,adapter_path):
    # Both files must already have passed the reviewed binding checks.
    old_path=list(sys.path)
    try:
        sys.path.insert(0,str(scanner_path.parent))
        spec=importlib.util.spec_from_file_location('bound_native_delivery_scanner',scanner_path)
        scanner=importlib.util.module_from_spec(spec);spec.loader.exec_module(scanner)
        need(Path(scanner.gate.__file__).resolve()==adapter_path.resolve() and sha(scanner.gate.__file__)==sha(adapter_path),'Scanner adapter dependency differs')
        names=scanner.EVIDENCE | scanner.RUNTIME | {'scan.json'}
        need(type(names) is set and all(type(n) is str for n in names),'Invalid scanner output allowlist')
        return names
    finally:sys.path[:]=old_path

def run(args):
    root=Path.cwd().resolve();contract=regular(args.contract);c=json.loads(contract.read_text())
    need(c.get('execution_enabled') is True,'Native delivery disabled')
    need(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted','Approved hosted runner only')
    helper_spec=importlib.util.spec_from_file_location('reviewed_delivery_helper',regular(root/'delivery_helpers.py'))
    helper=importlib.util.module_from_spec(helper_spec);helper_spec.loader.exec_module(helper)
    verified_root,c=helper.validate_contract(contract,strict=False)
    need(verified_root==root and c['mode']=='native','Wrong native delivery root or mode')
    files={k:bound(root,v) for k,v in c['bindings'].items()}
    work=root/'material-work'
    def call(script,*argv):subprocess.run([sys.executable,str(script),*map(str,argv)],check=True,env={k:v for k,v in os.environ.items() if k not in ('GITHUB_TOKEN','GH_TOKEN')})
    need(not work.exists(),'Fresh material work root required');work.mkdir()
    call(files['reconstructor'],'--source',root,'--licensed',root/c['artifacts']['old_licensed']['destination'],'--native',root/c['artifacts']['old_native']['destination'],'--plan',files['baseline_chain'],'--plan-sha256',c['bindings']['baseline_chain']['sha256'],'--baseline-lock',files['baseline_lock'],'--output',work/'baseline')
    generated_archive=root/c['artifacts']['generated']['archive_path']
    call(files['assembler'],'--baseline',work/'baseline/project','--baseline-lock',files['baseline_lock'],'--generated-archive',generated_archive,'--generator',files['generator'],'--inputs',files['assembly_inputs'],'--inputs-sha256',c['bindings']['assembly_inputs']['sha256'],'--review',files['generation_review'],'--geometry-check',files['geometry_check'],'--output',work/'assembled')
    pristine=work/'assembled/project';initial=inventory(pristine)
    assembled_lock=work/'assembled/assembled-source-lock.json'
    native_inputs=json.loads(files['native_inputs'].read_text())
    need(sha(assembled_lock)==native_inputs['assembled_source_lock_sha256'],'Assembled source lock not reviewed')
    need(sha(work/'assembled/GENERATED_19_SHA256.json')==native_inputs['generated_inventory_sha256'],'Normalized generated19 not reviewed')
    need(initial=={r['file']:r['sha256'] for r in json.loads(assembled_lock.read_text())['files']} and len(initial)==192,'Pristine assembled source differs')
    project=work/'native-project';shutil.copytree(pristine,project)
    engine=c['engine'];engine_path=regular(root/engine['destination']/engine['member'])
    need(sha(engine_path)==engine['executable_sha256']=='f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3','Official engine executable differs')
    common=['--inputs',files['native_inputs'],'--inputs-sha256',c['bindings']['native_inputs']['sha256'],'--review-pin',files['native_review'],'--baseline-lock',files['baseline_lock'],'--generated-inventory',work/'assembled/GENERATED_19_SHA256.json','--generated',work/'assembled/generated-native-19','--probe',files['probe'],'--source-lock',assembled_lock]
    call(files['adapter'],*common,'--project',project,'--godot',engine_path,'--monitor',files['monitor'],'--output',work/'native-evidence','--private',work/'native-private','--hosted-execution-approved')
    need(inventory(pristine)==initial,'Pristine assembled source changed during native work')
    call(files['scanner'],*common,'--project',pristine,'--evidence',work/'native-evidence','--destination',work/'safe-native')
    staged=inventory(work/'safe-native')
    expected_staged=scanner_allowlist(files['scanner'],files['adapter'])
    need(set(staged)==expected_staged,'Scanned native delivery must match exact bound scanner allowlist')
    scan=json.loads((work/'safe-native/scan.json').read_text())
    need(scan.get('passed') is True and {k:v for k,v in staged.items() if k!='scan.json'}==scan.get('files_sha256'),'Scanned delivery bytes changed')
    # Only this success marker permits the separate upload step. No failure artifact upload.
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as stream:stream.write('native_scanned=true\n')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--contract',type=Path,required=True);p.add_argument('--stage',choices=('all',),required=True);run(p.parse_args())
if __name__=='__main__':main()
