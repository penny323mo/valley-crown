"""Future guarded diagnostic packaging only; blocked by disabled admission now."""
from pathlib import Path
import argparse,json,os,shutil
import diagnostic_policy as d
from prepare_diagnostic_export import dump
import run_export

def package(work):
    lock=json.loads((work/'export-lock.json').read_text());d.admitted(lock['side']);d.lock_policy(lock);run_export.validate_lock(lock)
    d.need(lock.get('source_policy_extension_applied') is True,'Reviewed diagnostic policy extension not applied')
    receipt=json.loads((work/'exports/web-export-receipt.json').read_text())
    d.need(receipt.get('passed') is True and receipt.get('diagnostic_only') is True and receipt.get('release_artifact_identity_claim') is False,'Diagnostic export failed/mislabelled')
    d.need((receipt['build'],receipt['source_commit'],receipt['game_tree'])==(lock['build'],lock['source_commit'],lock['game_tree']),'Product identity differs')
    d.need(receipt['diagnostic_overlay_sha256']==lock['diagnostic_overlay_sha256'],'Observer receipt differs')
    rows=receipt['exports'];d.need(len(rows)==2 and all(x['passed'] is True and x['cleanup_complete'] is True and x['test_dependencies'] is False and not x['unexpected_descendants'] for x in rows),'Export guard incomplete')
    d.need(rows[0]['output_sha256']==rows[1]['output_sha256'] and sorted(rows[0]['output_sha256'])==lock['output_files'],'Repeat export mismatch')
    for path,digest in receipt['input_sha256'].items():d.need(d.sha(path)==digest,'Post-export binding drift')
    candidate=work/'candidate';d.need(not candidate.exists(),'Fresh package required');candidate.mkdir()
    for number,label in [(1,'clean-a'),(2,'clean-b')]:
        src=work/'exports'/('export-'+str(number))/'web';expected=rows[number-1]['output_sha256']
        d.need(d.tree(src)==expected,'Export bytes changed');dst=candidate/'artifacts'/label;shutil.copytree(src,dst);d.need(d.tree(dst)==expected,'Packaged bytes differ')
    # Preserve all original license/notices, with source-hash checks.
    notices=[n for n in lock['project_files'] if n in ['GODOT-LICENSES.txt','THIRD_PARTY_NOTICES.txt'] or '/licenses/' in n or n.endswith('-LICENSE.txt')]
    for name in notices:
        src=work/'project'/name;d.need(src.is_file() and not src.is_symlink() and d.sha(src)==lock['project_files'][name],'Notice source differs')
        dst=candidate/'notices'/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
    manifest=dict(schema='vc-paused-diagnostic-web-artifact-v1',side=lock['side'],diagnostic_only=True,release_artifact_identity_claim=False,
        product_build=lock['build'],product_source_commit=lock['source_commit'],product_game_tree=lock['game_tree'],
        diagnostic_export_commit=os.environ['GITHUB_SHA'],diagnostic_export_run_id=os.environ['GITHUB_RUN_ID'],diagnostic_export_run_attempt=1,
        diagnostic_overlay_sha256=lock['diagnostic_overlay_sha256'],diagnostic_project_sha256=lock['project_files']['project.godot'],
        source_archive_sha256=lock['source_archive_sha256'],import_manifest_sha256=lock['import_manifest_sha256'],
        export_lock_sha256=d.sha(work/'export-lock.json'),guard_receipt_sha256=d.sha(work/'exports/web-export-receipt.json'),
        bound_files_sha256=lock['bound_files_sha256'],files_sha256=rows[0]['output_sha256'],not_yet_deployed=True,
        scope='Two repeat diagnostic Web exports from one guarded import; no browser, gameplay, visual or release acceptance',
        browser_consumption_requires='Independent actual artifact/source/import/export/PCK-chain review and separate original-budget browser approval')
    dump(work/'diagnostic-export-manifest.json',manifest);dump(candidate/'diagnostic-export-manifest.json',manifest)
    summary=dict(diagnostic_export=manifest,files_sha256=d.tree(candidate),not_yet_deployed=True)
    dump(work/'diagnostic-export-summary.json',summary);return summary

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--work',type=Path,required=True);a=p.parse_args();package(a.work.resolve())
