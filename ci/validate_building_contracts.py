"""Strict six-suite evidence contracts; no engine calls and no visual acceptance."""
import hashlib
import json
import re
from pathlib import Path
BUILD = 'vc-394dab3b674d'
GAME_TREE = 'a54b56e9c190e688c873b49c4b83dcc316b5881b'
INVENTORY_SHA = '24f914e68dd779decba7dc33ebd7a26ccc3d1d0c6922c668c5803cf6ee4bdacb'
COUNTS = {'advanced_building_visuals':175, 'advanced_building_observation':52,
          'construction_visual':203, 'building_damage_component':100,
          'building_damage_projection':17, 'map80_sparse_memory':10}
SUITES = tuple(COUNTS)
EXTERNAL = ('building_damage_component','building_damage_projection')
REPORT = 'construction-report.json'
SCOPE = 'controlled geometry and actual observation lifecycle; not ordinary gameplay or visual acceptance'
SPARSE_SCOPE = 'Isolated real FactionWorkMemory sparse updates; not game/phone/visual acceptance.'
LIMITS = {'timeout_seconds':120,'admission_kib':4194304,'reserve_kib':1048576,
          'godot_rss_hwm_kib':2621440,'combined_rss_kib':3145728}

def require(value, message):
    if not value: raise ValueError(message)

def parse_json(text):
    def unique(pairs):
        result = {}
        for key,value in pairs:
            require(key not in result, 'Duplicate JSON key')
            result[key] = value
        return result
    def invalid(value): raise ValueError('Nonfinite JSON')
    return json.loads(text, object_pairs_hook=unique, parse_constant=invalid)

def validate_identity(lock):
    require(lock.get('building_reviewed_for_execution') is True,'Building execution not reviewed')
    require(lock.get('build') == BUILD and lock.get('game_tree') == GAME_TREE,'Wrong product identity')
    files = lock.get('project_files')
    require(type(files) is dict and len(files) == 342,'Wrong frozen inventory size')
    digest = hashlib.sha256(json.dumps(files,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    require(digest == INVENTORY_SHA,'Frozen source inventory drift')

def check_rows(report, suite):
    count = COUNTS[suite]
    require(type(report.get('passed')) is int and report['passed'] == count,'Wrong pass count')
    require(type(report.get('failed')) is int and report['failed'] == 0,'Failed checks')
    rows=report.get('checks')
    require(type(rows) is list and len(rows) == count,'Wrong check count')
    for row in rows:
        keys={'name','pass','detail'} if suite == 'map80_sparse_memory' else {'name','pass'}
        require(type(row) is dict and set(row) == keys and type(row['name']) is str and row['name'] and row['pass'] is True,'Invalid/failed check row')
        if 'detail' in row: require(type(row['detail']) is dict,'Invalid detail')
    return report

def validate_report(report,suite):
    require(suite in SUITES and type(report) is dict,'Unsupported suite/report')
    if suite.startswith('advanced_'):
        key='visual_acceptance' if suite=='advanced_building_visuals' else 'ordinary_gameplay_visual'
        require(set(report)=={'suite','checks','failures',key},'Wrong advanced schema')
        require(report['suite']==suite and type(report['checks']) is int and report['checks']==COUNTS[suite],'Wrong advanced suite/count')
        require(type(report['failures']) is list and report['failures']==[] and report[key]=='NOT_TESTED','Failed/overclaimed advanced report')
    elif suite in EXTERNAL:
        require(set(report)=={'suite','build','checks','passed','failed'},'Wrong damage schema')
        require(report['suite']==suite and report['build']==BUILD,'Wrong damage identity')
        check_rows(report,suite)
    else:
        keys={'checks','passed','failed','scope'} | ({'build'} if suite=='construction_visual' else set())
        require(set(report)==keys,'Wrong file/sparse schema')
        require(report['scope']==(SCOPE if suite=='construction_visual' else SPARSE_SCOPE),'Wrong scope')
        if suite=='construction_visual': require(report['build']==BUILD,'Wrong construction identity')
        check_rows(report,suite)
    return report

def read_report(stage,suite):
    stage=Path(stage)
    log=(stage/'godot.log').read_text()
    require(not re.search(r'(?im)^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:|FAIL )',log),'Error in log')
    json_lines=[line.strip() for line in log.splitlines() if line.lstrip().startswith(('{','MAP80_SPARSE_MEMORY '))]
    if suite=='construction_visual':
        require(not json_lines,'Unexpected additional JSON report')
        summaries=[line for line in log.splitlines() if line.startswith('CONSTRUCTION_VISUAL_CONTRACT')]
        require(summaries==['CONSTRUCTION_VISUAL_CONTRACT passed=203 failed=0'],'Missing/duplicate construction summary')
        report=parse_json((stage/REPORT).read_text())
    else:
        require(len(json_lines)==1,'Missing/duplicate report')
        line=json_lines[0]
        if suite=='map80_sparse_memory':
            require(line.startswith('MAP80_SPARSE_MEMORY '),'Wrong sparse prefix')
            line=line[len('MAP80_SPARSE_MEMORY '):]
        report=parse_json(line)
    return validate_report(report,suite)

def validate_monitor(result):
    require(type(result) is dict and result.get('passed') is True and result.get('cleanup_complete') is True,'Failed monitor')
    require(result.get('test_dependencies') is False and result.get('unexpected_descendants')==[],'Mocked/descendant monitor')
    require(type(result.get('exit')) is int and result['exit']==0 and result.get('limits')==LIMITS,'Wrong monitor exit/limits')
    require(result.get('logic_completed') is True and not result.get('error') and not result.get('final_error'),'Incomplete actual process')
    require(type(result.get('samples')) is list and bool(result['samples']) and type(result.get('pid')) is int,'Missing process samples')
