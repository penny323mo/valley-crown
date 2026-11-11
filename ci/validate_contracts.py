"""Strict bounded stdout contract parser; no process creation or telemetry."""
import json
from pathlib import Path

FIXTURES = {
 'construction_status': ('tests/construction_status_contract.gd', 'd67dc52d6e60152fb783112ba99afc19d610e20b935566b67b8b9268f7c6065a'),
 'construction_status_hud': ('tests/construction_status_hud.gd', '439c8827137306d6e775c237bc060e8becade720d49c9e278f5d367b7ccd88f3')}
STATUS_SHA = '3d858e112dc953e3365003b535df0843751d3238ad80ffa9b0f25069a7c80d3b'

def need(ok, reason):
    if not ok: raise ValueError(reason)

def unique(pairs):
    result={}
    for key,value in pairs:
        need(key not in result, 'Duplicate JSON key'); result[key]=value
    return result

def parse_json(value):
    return json.loads(value, object_pairs_hook=unique, parse_constant=lambda x: (_ for _ in ()).throw(ValueError('Nonfinite JSON')))

def canonical(value): return json.dumps(value,sort_keys=True,separators=(',',':'))

def validate(report, suite, lock, contract):
    need(type(report) is dict and report.get('contract')==suite, 'Wrong report identity')
    expected_keys={'contract','passed','failed','checks','source_sha256','scope'} | ({'build'} if suite=='construction_status_hud' else set())
    need(set(report)==expected_keys, 'Unexpected report fields')
    count=34 if suite=='construction_status' else 30
    need(type(report['passed']) is int and report['passed']==count and type(report['failed']) is int and report['failed']==0, 'Report count mismatch/failure')
    checks=report['checks']
    need(type(checks) is list and len(checks)==count, 'Missing checks')
    need(all(type(c) is dict and set(c)=={'name','pass'} and type(c['name']) is str and c['pass'] is True for c in checks), 'Failed/malformed check')
    names=[c['name'] for c in checks]; need(len(set(names))==count, 'Duplicate checks')
    if suite=='construction_status_hud':
        need(names==contract['hud_names'], 'HUD check order/name mismatch')
        need(report['build']==lock['build'], 'HUD build mismatch')
        expected={name:lock['project_files'][name] for name in ('scripts/game.gd','scripts/construction_status.gd','tests/construction_status_hud.gd')}
        need(report['source_sha256']==expected, 'HUD source mismatch')
        need(report['scope']=='Controlled actual game/HUD transitions at portrait and landscape logical sizes; route fixture and approach relocation are synthetic. Not natural play, pixels or physical-phone acceptance.', 'Wrong HUD scope')
    else:
        static=contract['value_static_names']
        expected=static[:5]+[x+' explains route stopped and manual recovery' for x in ('NO_PATH','LIMIT_REACHED','NO_WORK')]+static[5:8]
        need(names[:11]==expected and names[-2:]==static[-2:], 'Value check order/name mismatch')
        for start, end, prefix, patches in [(11,21,'ignore invalid builder even with work cue ',contract['invalid_builder_patches']), (26,32,'no construction status for excluded site ',contract['invalid_site_patches'])]:
            actual=[]
            for name in names[start:end]:
                need(name.startswith(prefix), 'Missing case prefix')
                actual.append(canonical(parse_json(name[len(prefix):])))
            need(actual==[canonical(x) for x in patches], 'Wrong invalid-observation cases')
        need(names[21:26]==['unrelated action is not construction '+x for x in ('idle','gather_wood','gather_food','repair','attack')], 'Missing action cases')
        need(report['source_sha256']==lock['project_files']['scripts/construction_status.gd']==STATUS_SHA, 'Value source mismatch')
        need(report['scope']=='Value-only presentation; not gameplay, rendered pixels or physical-phone acceptance', 'Wrong value scope')
    return report

def read_log(path,suite,lock,contract):
    path=Path(path); need(path.is_file() and not path.is_symlink() and 0<path.stat().st_size<=16*1024*1024, 'Invalid/oversized log')
    rows=[line for line in path.read_text(encoding='utf-8').splitlines() if line.lstrip().startswith('{')]
    need(len(rows)==1 and len(rows[0].encode())<=128*1024, 'Missing/duplicate/oversized JSON report')
    return validate(parse_json(rows[0]),suite,lock,contract)
