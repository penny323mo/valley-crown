"""Strict bounded stdout contract parser; no process creation or telemetry."""
import json
import math
from pathlib import Path

FIXTURES = {
 'construction_status': ('tests/construction_status_contract.gd', 'd67dc52d6e60152fb783112ba99afc19d610e20b935566b67b8b9268f7c6065a'),
 'construction_status_hud': ('tests/construction_status_hud.gd', 'dfb464ce2e645a865845a5a567c7670cb6885e73b460f668ef98246debc0189a'),
 'mobile_stop_control_contract': ('tests/mobile_stop_control_contract.gd', '102c1da25e4c526364a340d57cfa0b7ae336b8ee33da032ac3493c2820db4543'),
 'mobile_stop_control_phone': ('tests/mobile_stop_control_phone.gd', '6952491d7cfd8aa92d79c357823ffc1302e55c6cab69b173ad0b1e64008e0f4a'),
 'stance_target_cancel_phone': ('tests/stance_target_cancel_phone.gd', 'fe1a38da69e900aeef7edd4403f5b553727a704ca30c2ade83df654116b653e6'),
 'contextual_touch_contract': ('tests/contextual_touch_contract.gd', '0eb10211bc5577f54923f6edc0c86f3ae700020d0ef373d1fe04b09d0e597c24'),
 'contextual_touch_phone': ('tests/contextual_touch_phone.gd', '9da858aa0801cc881bf10dc9b91d03822e16fc4cb70d9a46080f33ea6c4e01d1'),
 'main_menu_flow_contract': ('tests/main_menu_flow_contract.gd', 'be9f81844a2c6aa66bc02a318afeafa9c943c6b620e132b7601c93bdfe4aef47')}
MENU_SHA = '1c117486b7ebf2cb868bdf0ddce1f30be384aea5a4b9102cb3648b8357ccd4d7'
MENU_SCOPE = 'Controlled button-signal and synthetic event-handler integration; not browser input dispatch, rendering, or physical-device acceptance. Terminal navigation uses an explicitly synthetic game_over assignment, not a played victory.'
BUILD = 'vc-893b58f24e69'
ARRAY_COUNTS = {'contextual_touch_contract':23, 'contextual_touch_phone':10}
PREFIXES = {'contextual_touch_contract':'CONTEXTUAL_TOUCH_CONTRACT',
            'contextual_touch_phone':'CONTEXTUAL_TOUCH_PHONE'}
STATUS_SHA = '3d858e112dc953e3365003b535df0843751d3238ad80ffa9b0f25069a7c80d3b'
GAME_SHA = '286174e4f48ed03098fe0cfe05de2105d24b107943d4fefaeb14cd339913aefd'
FILE_SUITE = 'stance_target_cancel_phone'
FILE_REPORT = 'stance-target-cancel-phone.json'
STOP_COUNTS = {'mobile_stop_control_contract':21, 'mobile_stop_control_phone':64,
               'stance_target_cancel_phone':58}
STOP_SCOPES = {
 'mobile_stop_control_contract':'Synthetic control fixture, not rendered or physical-device acceptance',
 'mobile_stop_control_phone':'Controlled actual HUD geometry and synthetic viewport input; not browser pixels, natural play or physical-iPhone acceptance',
 'stance_target_cancel_phone':'native routed synthetic touch; not physical-phone or Web acceptance'}

def need(ok, reason):
    if not ok: raise ValueError(reason)

def unique(pairs):
    result={}
    for key,value in pairs:
        need(key not in result, 'Duplicate JSON key'); result[key]=value
    return result

def finite_float(value):
    result=float(value)
    need(math.isfinite(result), 'Nonfinite JSON')
    return result

def parse_json(value):
    return json.loads(value, object_pairs_hook=unique, parse_float=finite_float, parse_constant=lambda x: (_ for _ in ()).throw(ValueError('Nonfinite JSON')))

def canonical(value): return json.dumps(value,sort_keys=True,separators=(',',':'))

def validate_stop(report, suite, lock, contract):
    need(type(report) is dict, 'Wrong report identity')
    expected_keys={'build','checks','scope'} | ({'pass','touch_events'} if suite==FILE_SUITE else {'suite','failed','source_sha256'})
    if suite=='mobile_stop_control_phone': expected_keys.add('input_events')
    need(set(report)==expected_keys, 'Unexpected report fields')
    count=STOP_COUNTS[suite]
    checks=report['checks']
    need(type(checks) is list and len(checks)==count, 'Missing checks')
    need(all(type(c) is dict and set(c)=={'name','passed'} and type(c['name']) is str and c['passed'] is True for c in checks), 'Failed/malformed check')
    # The stance source intentionally repeats "fixture has scout" four times.
    # Exact list comparison, including those positions, replaces uniqueness.
    need([c['name'] for c in checks]==contract[suite+'_names'], 'Check order/name mismatch')
    need(report['build']==lock['build'], 'Build mismatch')
    need(report['scope']==STOP_SCOPES[suite], 'Wrong scope')
    need(lock['project_files']['scripts/game.gd']==GAME_SHA, 'Unreviewed Stop source')
    if suite==FILE_SUITE:
        need(report['pass'] is True, 'Report failed')
        events=report['touch_events']
        # 56 unconditional events plus at most 30 successful reveal swipes,
        # each exactly three events. Initial compact Stop needs no reveal.
        need(type(events) is int and 56<=events<=146 and (events-56)%3==0, 'Wrong touch event count')
    else:
        need(report['suite']==suite, 'Wrong report identity')
        need(type(report['failed']) is int and report['failed']==0, 'Report failure count')
        need(report['source_sha256']==GAME_SHA, 'Stop source mismatch')
        if suite=='mobile_stop_control_phone':
            need(type(report['input_events']) is int and report['input_events']==77, 'Wrong input event count')
    return report

def validate_source(suite, lock):
    need(type(lock) is dict and lock.get('build')==BUILD, 'Unreviewed build')
    files=lock.get('project_files')
    need(type(files) is dict, 'Missing source binding')
    name,sha=FIXTURES[suite]
    need(files.get(name)==sha, 'Unreviewed fixture source')
    need(files.get('scripts/game.gd')==GAME_SHA, 'Unreviewed game source')
    need(files.get('scripts/construction_status.gd')==STATUS_SHA, 'Unreviewed status source')

def validate_array(report, suite, contract):
    count=ARRAY_COUNTS[suite]
    need(type(report) is list and len(report)==count, 'Missing checks')
    need(all(type(c) is dict and set(c)=={'name','passed'} and type(c['name']) is str and c['passed'] is True for c in report), 'Failed/malformed check')
    names=[c['name'] for c in report]
    need(len(set(names))==count, 'Duplicate checks')
    if suite=='contextual_touch_contract':
        # Godot str(Dictionary) whitespace is not a report identity. Compare the
        # five exact, ordered invalid-selection objects after strict parsing.
        prefix='reject invalid selection '
        for i in range(11,16):
            need(names[i].startswith(prefix), 'Missing invalid-selection case')
            names[i]=prefix+canonical(parse_json(names[i][len(prefix):]))
    need(names==contract[suite+'_names'], 'Check order/name mismatch')
    return report

def validate_menu(report, lock, contract):
    need(type(report) is dict and set(report)=={'suite','build','scope','checks','failure_count','source_sha256'}, 'Unexpected menu report fields')
    need(report['suite']=='main_menu_flow_contract' and report['build']==lock['build'], 'Menu report identity mismatch')
    need(report['scope']==MENU_SCOPE, 'Wrong menu scope')
    need(type(report['failure_count']) is int and report['failure_count']==0, 'Menu report failure count')
    checks=report['checks']
    need(type(checks) is list and len(checks)==16, 'Missing menu checks')
    need(all(type(c) is dict and set(c)=={'name','passed'} and type(c['name']) is str and c['passed'] is True for c in checks), 'Failed/malformed menu check')
    need([c['name'] for c in checks]==contract['main_menu_flow_contract_names'], 'Menu check order/name mismatch')
    expected={'scripts/game.gd':GAME_SHA,'scripts/main_menu.gd':MENU_SHA}
    need(all(lock['project_files'].get(name)==sha for name,sha in expected.items()), 'Unreviewed menu source')
    need(report['source_sha256']==expected, 'Menu source mismatch')
    return report

def validate(report, suite, lock, contract):
    need(suite in FIXTURES, 'Unsupported suite')
    validate_source(suite,lock)
    if suite=='main_menu_flow_contract': return validate_menu(report,lock,contract)
    if suite in ARRAY_COUNTS: return validate_array(report,suite,contract)
    if suite in STOP_COUNTS: return validate_stop(report,suite,lock,contract)
    need(type(report) is dict and report.get('contract')==suite, 'Wrong report identity')
    expected_keys={'contract','passed','failed','checks','source_sha256','scope'} | ({'build'} if suite=='construction_status_hud' else set())
    need(set(report)==expected_keys, 'Unexpected report fields')
    count=34
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

def is_report_line(line):
    value=line.lstrip()
    return value.startswith(('{','[')) or any(value.startswith(prefix) for prefix in PREFIXES.values())

def read_log(path,suite,lock,contract):
    need(suite in FIXTURES and suite!=FILE_SUITE, 'Unsupported stdout report')
    path=Path(path); need(path.is_file() and not path.is_symlink() and 0<path.stat().st_size<=16*1024*1024, 'Invalid/oversized log')
    rows=[line for line in path.read_text(encoding='utf-8').splitlines() if is_report_line(line)]
    need(len(rows)==1 and len(rows[0].encode())<=128*1024, 'Missing/duplicate/oversized JSON report')
    value=rows[0]
    if suite in PREFIXES:
        prefix=PREFIXES[suite]+' '
        need(value.startswith(prefix), 'Wrong report prefix')
        value=value[len(prefix):]
    return validate(parse_json(value),suite,lock,contract)

def read_file_report(stage,suite,lock,contract):
    need(suite==FILE_SUITE, 'Unsupported file report')
    stage=Path(stage); path=stage/FILE_REPORT; log=stage/'godot.log'
    need(path.is_file() and not path.is_symlink() and 0<path.stat().st_size<=128*1024, 'Invalid/oversized file report')
    need(log.is_file() and not log.is_symlink() and 0<log.stat().st_size<=16*1024*1024, 'Invalid/oversized log')
    need(not any(is_report_line(line) for line in log.read_text(encoding='utf-8').splitlines()), 'Unexpected stdout JSON report')
    return validate(parse_json(path.read_text(encoding='utf-8')),suite,lock,contract)
