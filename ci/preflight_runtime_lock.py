#!/usr/bin/env python3
"""Read-only exact locks/support preflight, before any executable download or import."""
import argparse
import re
from pathlib import Path
import prepare_web_release as prep
import owned_process as p
import validate_building_contracts as b

def check(work,side):
    import run_export as product
    import run_export_diagnostic as diagnostic
    runner=product if side=='product' else diagnostic
    lock=b.parse_json((work/'export-lock.json').read_text())
    prep.need(re.fullmatch('[a-f0-9]{40}',prep.SOURCE),'Pending reviewed source pin')
    runner.validate_lock(lock)
    prep.need(lock.get('diagnostic_only') is (side=='diagnostic'),'Side classification mismatch')
    prep.need(p.tree(work/'project')==lock['project_files'],'Pre-import source drift')
    ci=Path(__file__).parent
    runner.checked(ci/prep.SIDES[side]['runner'],lock['runner_sha256'])
    runner.checked(p.__file__,lock['owned_process_sha256'])
    runner.checked(work/'source.zip',lock['source_archive_sha256'])
    runner.checked(work/'import-manifest.json',lock['import_manifest_sha256'])
    runner.checked(ci/'guarded_manifest_ci.py',lock['import_adapter_sha256'])
    if side=='product':
        import run_building_contracts as building
        import run_contracts as contracts
        import run_military as military
        import run_faction as faction
        b.validate_identity(lock);faction.validate_gate(lock)
        for flag in ('contracts_reviewed_for_execution','contracts_stop_reviewed_for_execution','contracts_consolidated_reviewed_for_execution','military_reviewed_for_execution'):
            prep.need(lock.get(flag) is True,'Unreviewed '+flag)
        for prefix,module,validator in [('building',building,b),('contracts',contracts,contracts.v),('military',military,military.v),('faction',faction,faction.v)]:
            runner.checked(module.__file__,lock[prefix+'_runner_sha256'])
            runner.checked(validator.__file__,lock[prefix+'_validator_sha256'])
            prep.need(lock[prefix+'_supervisor_sha256']==building.LOGIC_SHA,'Wrong supervisor identity')
            runner.checked(building.logic.__file__,lock[prefix+'_supervisor_sha256'])
        prep.need(lock['owned_process_sha256']==building.OWNED_SHA,'Changed ownership helpers')
        for prefix,name in [('contracts','check_contract.json'),('military','military_contract.json')]:runner.checked(ci/name,lock[prefix+'_names_sha256'])
        hashes=lock.get('building_harness_sha256');prep.need(type(hashes) is dict and set(hashes)==set(b.SUITES),'Six exact building harnesses required')
        for suite,path in building.harness_paths(work/'project').items():runner.checked(path,hashes[suite])
        for module in (contracts,military):
            for name,digest in module.v.FIXTURES.values():prep.need(lock['project_files'].get(name)==digest,'Original suite identity differs')
        runner.checked(work/'project/tests/faction_publish_contract.gd',lock['faction_harness_sha256'])
    return lock

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--work',type=Path,required=True);parser.add_argument('--side',choices=prep.SIDES,required=True);args=parser.parse_args()
    prep.admitted();check(args.work,args.side);print('Exact '+args.side+' preflight passed; no engine called')
