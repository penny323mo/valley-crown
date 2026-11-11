"""Package independently reviewed diagnostic exports only. No browser run or deploy."""
from pathlib import Path
import argparse,json,os,shutil
from prepare_diagnostic_export import admitted,tree,dump,ROOT
import diagnostic_policy as d
import run_export
NOTICES = ['GODOT-LICENSES.txt', 'THIRD_PARTY_NOTICES.txt', 'assets/fonts/NOTO-LICENSE.txt', 'assets/fonts/DEJAVU-LICENSE.txt', 'assets/fonts/MENU-TITLE-LICENSE.txt'] + [
    'art/action_characters/licenses/' + name for name in ['quaternius-outfits.txt', 'kaykit-animations.txt', 'quaternius-ual.txt', 'quaternius-ual2.txt', 'quaternius-base.txt']]

def package(work):
    admitted();lock=json.loads((work/'export-lock.json').read_text());run_export.validate_lock(lock)
    receipt=json.loads((work/'exports/web-export-receipt.json').read_text())
    d.need(receipt.get('passed') is True and receipt.get('diagnostic_only') is True and receipt.get('release_artifact_identity_claim') is False,'Diagnostic export failed or mislabelled')
    d.need((receipt['build'],receipt['source_commit'],receipt['game_tree'])==(lock['build'],lock['source_commit'],lock['game_tree']),'Product identity differs')
    d.need(receipt['diagnostic_overlay_sha256']==lock['diagnostic_overlay_sha256'],'Overlay receipt mismatch')
    d.need(len(receipt['exports'])==2 and all(x['passed'] is True and x['cleanup_complete'] is True and x['test_dependencies'] is False and not x['unexpected_descendants'] for x in receipt['exports']),'Export guard incomplete')
    d.need(receipt['exports'][0]['output_sha256']==receipt['exports'][1]['output_sha256'] and sorted(receipt['exports'][0]['output_sha256'])==lock['output_files'],'Repeat export mismatch')
    for path,digest in receipt['input_sha256'].items():d.need(d.sha(path)==digest,'Post-export binding drift')
    candidate=work/'candidate';candidate.mkdir()
    for number,label in [(1,'clean-a'),(2,'clean-b')]:
        src=work/'exports'/('export-'+str(number))/'web';expected=receipt['exports'][number-1]['output_sha256']
        d.need(tree(src)==expected,'Export bytes changed');dst=candidate/'artifacts'/label;shutil.copytree(src,dst);d.need(tree(dst)==expected,'Packaged bytes differ')
    for name in NOTICES:
        src=work/'project'/name;d.need(src.is_file() and not src.is_symlink() and d.sha(src)==lock['project_files'][name],'Notice source differs')
        dst=candidate/'clean-a'/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
    manifest=dict(schema='vc-diagnostic-web-artifact-v1',diagnostic_only=True,release_artifact_identity_claim=False,
      product_build=lock['build'],product_source_commit=lock['source_commit'],product_game_tree=lock['game_tree'],
      diagnostic_export_commit=os.environ['GITHUB_SHA'],diagnostic_export_run_id=os.environ['GITHUB_RUN_ID'],diagnostic_export_run_attempt=1,
      diagnostic_export_run='https://github.com/penny323mo/valley-crown/actions/runs/'+os.environ['GITHUB_RUN_ID'],
      diagnostic_overlay_sha256=lock['diagnostic_overlay_sha256'],diagnostic_project_sha256=lock['project_files']['project.godot'],
      baseline_sha256=d.BASELINE_SHA,source_archive_sha256=lock['source_archive_sha256'],import_manifest_sha256=lock['import_manifest_sha256'],
      export_lock_sha256=d.sha(work/'export-lock.json'),guard_receipt_sha256=d.sha(work/'exports/web-export-receipt.json'),
      adapter_inventory_sha256=d.sha(ROOT/'adapter-inventory.json'),files_sha256=receipt['exports'][0]['output_sha256'],
      scope='Two repeat diagnostic Web exports from one guarded import; not release artifact 13853296416; no gameplay, visual, or browser success claimed',
      browser_consumption_requires='Actual run/artifact/output pins and separate independent exact review before browser execution',not_yet_deployed=True)
    dump(work/'diagnostic-export-manifest.json',manifest);dump(candidate/'diagnostic-export-manifest.json',manifest)
    summary=dict(diagnostic_export=manifest,files_sha256=tree(candidate),not_yet_deployed=True)
    dump(work/'diagnostic-export-summary.json',summary);print(json.dumps(summary,sort_keys=True))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--work',type=Path,required=True);a=p.parse_args();package(a.work.resolve())
