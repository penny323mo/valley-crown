"""Strict bounded military report parser. No process execution or telemetry."""
from pathlib import Path
import json
from validate_contracts import parse_json, need
CONTRACT=Path(__file__).with_name('military_contract.json')
C=parse_json(CONTRACT.read_text())
FIXTURES=C['fixtures']
GAME_SHA=C['game_sha256']
BUILD=C['build']
PREFIXES={'military_progression_contract':'MILITARY_PROGRESSION ', 'military_runtime_edges':'MILITARY_RUNTIME_EDGES '}
SCOPES={'military_progression_contract':'controlled integration fixture, not natural gameplay or art acceptance',
        'military_runtime_edges':'Controlled funded route and command integration, not natural full-match, rendered Web, release-template or art acceptance'}
def validate(report,suite,lock,contract=C):
    need(suite in FIXTURES,'Unsupported military suite')
    need(lock.get('build')==BUILD and lock.get('project_files',{}).get('scripts/game.gd')==GAME_SHA,'Unreviewed source')
    name,sha=FIXTURES[suite];need(lock['project_files'].get(name)==sha,'Unreviewed fixture')
    common={'build','scope','total','failed','elapsed_ms'}
    extra={'results','engine'} if suite=='military_progression_contract' else {'suite','checks','max_path_queries','max_path_expansions'}
    need(type(report) is dict and set(report)==common|extra,'Wrong military report fields')
    need(report['build']==BUILD and report['scope']==SCOPES[suite],'Wrong military identity/scope')
    checks=report['results' if suite=='military_progression_contract' else 'checks']
    need(type(checks) is list and len(checks)==len(contract['names'][suite]),'Missing military assertions')
    need(all(type(row) is dict and set(row)=={'name','passed'} and type(row['name']) is str and row['passed'] is True for row in checks),'Failed/malformed assertion')
    need([row['name'] for row in checks]==contract['names'][suite],'Military assertion order/name mismatch')
    need(type(report['total']) is int and report['total']==len(checks) and type(report['failed']) is int and report['failed']==0,'Wrong military counts')
    need(type(report['elapsed_ms']) is int and 0<=report['elapsed_ms']<100000,'Military fixture deadline exceeded')
    if suite=='military_progression_contract':
        engine=report['engine'];need(type(engine) is dict and (engine.get('major'),engine.get('minor'),engine.get('patch'),engine.get('status'))==(4,6,3,'stable'),'Wrong engine report')
    else:
        need(report['suite']==suite,'Wrong suite')
        for key,ceiling in [('max_path_queries',4),('max_path_expansions',16384)]:
            need(type(report[key]) is int and 0<=report[key]<=ceiling,'Path limit breached')
    return {'checks':checks,'report':report}
def read_log(path,suite,lock,contract=C):
    need(suite in PREFIXES,'Unsupported military stdout')
    path=Path(path);need(path.is_file() and not path.is_symlink() and 0<path.stat().st_size<=16*1024*1024,'Invalid log')
    rows=[line for line in path.read_text(encoding='utf-8').splitlines() if line.lstrip().startswith(('{','[','MILITARY_'))]
    need(len(rows)==1 and rows[0].startswith(PREFIXES[suite]) and len(rows[0].encode())<=128*1024,'Missing/duplicate/wrong military report')
    return validate(parse_json(rows[0][len(PREFIXES[suite]):]),suite,lock,contract)
