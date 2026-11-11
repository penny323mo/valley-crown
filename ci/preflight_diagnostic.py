"""Pure syntax, pins and negative-policy tests; no launch/resource sampling."""
import ast,copy,json,hashlib,sys
from pathlib import Path
import diagnostic_policy as d
ROOT=Path(__file__).resolve().parents[1]
def check(work=None):
    inventory=json.loads((ROOT/'adapter-inventory.json').read_text())
    for name,digest in inventory.items():d.need(d.sha(ROOT/name)==digest,'Adapter pin differs: '+name)
    for path in (ROOT/'ci').glob('*.py'):ast.parse(path.read_text(),filename=str(path))
    d.need(d.sha(ROOT/'ci/hardened_monitored_run.py')=='4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50','Monitor changed')
    base=d.baseline();d.need(len(base['project_files'])==232 and len(base['runtime']['source_sha256'])==140,'Baseline counts differ')
    rejected=0
    if work:
        import run_export,guarded_manifest_ci
        work=Path(work).resolve();lock=json.loads((work/'export-lock.json').read_text())
        approved=dict(lock,reviewed_for_execution=True);run_export.validate_lock(approved)
        guarded_manifest_ci.verify_source(work/'project',work/'source.zip',work/'import-manifest.json',lock['source_archive_sha256'],lock['import_manifest_sha256'])
        mutations=[lambda x:x.update(diagnostic_only=False),lambda x:x.update(release_artifact_identity_claim=True),lambda x:x.update(baseline_sha256='0'*64),lambda x:x.update(source_commit='0'*40),lambda x:x['project_files'].update({'scripts/game.gd':'0'*64}),lambda x:x['project_files'].update({'project.godot':base['project_files']['project.godot']}),lambda x:x['diagnostic_overlay_sha256'].update({'diagnostic/extra.gd':'0'*64}),lambda x:x.update(reviewed_for_execution=False)]
        for mutate in mutations:
            bad=copy.deepcopy(approved);mutate(bad)
            try:run_export.validate_lock(bad)
            except (RuntimeError,ValueError):rejected+=1
            else:raise ValueError('Negative policy mutation accepted')
        d.need(rejected==8,'Negative checks incomplete')
    return dict(adapter_inventory_verified=True,engine_executed=False,live_sampling=False,prepared_lock_verified=bool(work),negative_policy_cases=rejected,overlay_bound=json.loads((ROOT/'overlay-binding.json').read_text())['bound'])
if __name__=='__main__':print(json.dumps(check(sys.argv[1] if len(sys.argv)>1 else None),sort_keys=True))
