"""Pure exact-pin verification before any hosted import/fixture process."""
import copy,hashlib,json,re,sys
from pathlib import Path
import run_export as r
import prepare_public_capture as source
import run_visibility as runner
import validate_visibility as v
HERE=Path(__file__).resolve().parent

def verify(lock):
    r.validate_lock(lock)
    assert lock.get('visibility_reviewed_for_execution') is True
    expected=(r.SOURCE,r.GAME_TREE,r.BUILD)
    assert expected==(source.SOURCE_COMMIT,source.GAME_TREE,source.BUILD)
    assert re.fullmatch('[0-9a-f]{40}',expected[0]) and re.fullmatch('[0-9a-f]{40}',expected[1]) and re.fullmatch('vc-[0-9a-f]{12}',expected[2])
    assert len(lock['project_files'])==233
    required={'runner_sha256':'run_export.py','owned_process_sha256':'owned_process.py','import_adapter_sha256':'guarded_manifest_ci.py','visibility_runner_sha256':'run_visibility.py','visibility_supervisor_sha256':'run_logic.py','visibility_validator_sha256':'validate_visibility.py','visibility_names_sha256':'visibility_names.json','contracts_validator_sha256':'validate_contracts.py'}
    for key,name in required.items():assert lock[key]==hashlib.sha256((HERE/name).read_bytes()).hexdigest(),key
    assert lock['visibility_supervisor_sha256']==runner.LOGIC_SHA
    assert lock['owned_process_sha256']=='7fd227386d083f35bf55390a26a96c70472ba4a0def0f781f9a28aeeaa59cb2e'
    assert lock['project_files'][v.FIXTURE]==v.FIXTURE_SHA
    assert lock['project_files']['scripts/game.gd']==v.strict.GAME_SHA and v.strict.GAME_SHA in v.SOURCE_SHAS.values()
    assert v.strict.BUILD==lock['build']
    files=lock['project_files'];uids=sorted(n+'.uid' for n in files if n.endswith('.gd') and n+'.uid' not in files)
    for n in ['assets/mature/shaders/building_damage_soot.gdshader.uid','assets/mature/menu/menu_backdrop.gdshader.uid']:
        if n[:-4] in files and n not in files:uids.append(n)
    assert lock['allowed_generated_uid_files']==sorted(uids) and len(uids)==31
    assert len(json.loads((HERE/'visibility_names.json').read_text()))==124

def check(path):
    lock=json.loads(Path(path).read_text());verify(lock);rejected=0
    mutations=[lambda x:x.update(source_commit='0'*40),lambda x:x.update(game_tree='0'*40),lambda x:x.update(build='vc-000000000000'),lambda x:x.update(visibility_reviewed_for_execution=False),lambda x:x.update(visibility_runner_sha256='0'*64),lambda x:x.update(visibility_validator_sha256='0'*64),lambda x:x.update(visibility_supervisor_sha256='0'*64),lambda x:x['project_files'].update({v.FIXTURE:'0'*64}),lambda x:x['project_files'].update({'scripts/game.gd':'0'*64}),lambda x:x['allowed_generated_uid_files'].pop()]
    for mutate in mutations:
        bad=copy.deepcopy(lock);mutate(bad)
        try:verify(bad)
        except (RuntimeError,ValueError,AssertionError):rejected+=1
        else:raise AssertionError('Wrong visibility binding accepted')
    assert rejected==10
    return {'actual_prepared_lock_valid':True,'negative_pin_cases_rejected':rejected,'source_files':233,'generated_uid_names':31,'engine_executed':False}

if __name__=='__main__':print(json.dumps(check(sys.argv[1])))
