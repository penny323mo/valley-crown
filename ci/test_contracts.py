"""Synthetic reports and static assertions only. No engine/live telemetry."""
import ast
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))

import run_contracts as r
import validate_contracts as v
C=json.loads((HERE/'check_contract.json').read_text())
LOCK={'build':v.BUILD,'project_files':{'scripts/construction_status.gd':v.STATUS_SHA,'scripts/game.gd':v.GAME_SHA,'scripts/main_menu.gd':v.MENU_SHA,**dict(v.FIXTURES.values())}}

def example(suite):
    if suite in v.ARRAY_COUNTS:
        return [{'name':n,'passed':True} for n in C[suite+'_names']]
    if suite=='main_menu_flow_contract':
        return {'suite':suite,'build':LOCK['build'],'scope':v.MENU_SCOPE,
                'checks':[{'name':n,'passed':True} for n in C[suite+'_names']],
                'failure_count':0,'source_sha256':{'scripts/game.gd':v.GAME_SHA,'scripts/main_menu.gd':v.MENU_SHA}}
    if suite in v.STOP_COUNTS:
        report={'build':LOCK['build'],'checks':[{'name':n,'passed':True} for n in C[suite+'_names']],
                'scope':v.STOP_SCOPES[suite]}
        if suite==v.FILE_SUITE: report.update({'pass':True,'touch_events':56})
        else:
            report.update({'suite':suite,'failed':0,'source_sha256':v.GAME_SHA})
            if suite=='mobile_stop_control_phone': report['input_events']=77
        return report
    if suite=='construction_status_hud':
        names=C['hud_names'];sha={name:LOCK['project_files'][name] for name in ('scripts/game.gd','scripts/construction_status.gd','tests/construction_status_hud.gd')}
        scope='Controlled actual game/HUD transitions at portrait and landscape logical sizes; route fixture and approach relocation are synthetic. Not natural play, pixels or physical-phone acceptance.'
    else:
        s=C['value_static_names']
        names=s[:5]+[x+' explains route stopped and manual recovery' for x in ('NO_PATH','LIMIT_REACHED','NO_WORK')]+s[5:8]
        names+=['ignore invalid builder even with work cue '+json.dumps(x) for x in C['invalid_builder_patches']]
        names+=['unrelated action is not construction '+x for x in ('idle','gather_wood','gather_food','repair','attack')]
        names+=['no construction status for excluded site '+json.dumps(x) for x in C['invalid_site_patches']]+s[-2:]
        sha=v.STATUS_SHA;scope='Value-only presentation; not gameplay, rendered pixels or physical-phone acceptance'
    report={'contract':suite,'passed':len(names),'failed':0,'checks':[{'name':n,'pass':True} for n in names],'source_sha256':sha,'scope':scope}
    if suite=='construction_status_hud':report['build']=LOCK['build']
    return report

class Tests(unittest.TestCase):
    def test_valid_synthetic(self):
        for suite in r.SUITES:v.validate(example(suite),suite,LOCK,C)
    def test_negative_reports(self):
        for suite in ('construction_status','construction_status_hud'):
            for mutation in ('duplicate','missing','false','count_bool','source','scope','name'):
                report=example(suite)
                if mutation=='duplicate':report['checks'][-1]=report['checks'][0]
                if mutation=='missing':report['checks'].pop()
                if mutation=='false':report['checks'][0]['pass']=False
                if mutation=='count_bool':report['failed']=False
                if mutation=='source':report['source_sha256']='bad'
                if mutation=='scope':report['scope']='natural-play proof'
                if mutation=='name':report['checks'][3]['name']='wrong'
                with self.subTest(suite=suite,mutation=mutation),self.assertRaises(ValueError):v.validate(report,suite,LOCK,C)
    def test_bad_json(self):
        for value in ('{"a":1,"a":2}','{"a":NaN}','{"a":Infinity}','{"a":-Infinity}','{"a":1e999}'):
            with self.assertRaises(ValueError):v.parse_json(value)
    def test_exact_argv(self):
        command=r.argv('/godot','/game','construction_status_hud')
        self.assertEqual(command,['/godot','--headless','--path','/game','--audio-driver','Dummy','--resolution','390x844','--fixed-fps','30','--script','res://tests/construction_status_hud.gd'])
        with self.assertRaises(RuntimeError):r.argv('/godot','/game','arbitrary')
        command=r.argv('/godot','/game',v.FILE_SUITE,Path('/stage'))
        self.assertEqual(command,['/godot','--headless','--path','/game','--audio-driver','Dummy','--resolution','390x844','--fixed-fps','30','--script','res://tests/stance_target_cancel_phone.gd','--','/stage/stance-target-cancel-phone.json'])
        with self.assertRaises(RuntimeError):r.argv('/godot','/game',v.FILE_SUITE)
        with self.assertRaises(RuntimeError):r.argv('/godot','/game','mobile_stop_control_phone',Path('/extra'))
    def test_disabled_before_metrics(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'lock.json';path.write_text('{"contracts_reviewed_for_execution":false}')
            with self.assertRaisesRegex(RuntimeError,'not reviewed'):r.run(types.SimpleNamespace(lock=path))
            path.write_text('{"contracts_reviewed_for_execution":true,"contracts_stop_reviewed_for_execution":false}')
            with self.assertRaisesRegex(RuntimeError,'Stop adapter not reviewed'):r.run(types.SimpleNamespace(lock=path))
            path.write_text('{"contracts_reviewed_for_execution":true,"contracts_stop_reviewed_for_execution":true,"contracts_consolidated_reviewed_for_execution":false}')
            with self.assertRaisesRegex(RuntimeError,'Consolidated adapter not reviewed'):r.run(types.SimpleNamespace(lock=path))
    def test_log(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'godot.log';line=json.dumps(example('construction_status'))
            path.write_text('Godot startup\n'+line+'\n')
            v.read_log(path,'construction_status',LOCK,C)
            path.write_text(line+'\n'+line+'\n')
            with self.assertRaises(ValueError):v.read_log(path,'construction_status',LOCK,C)
    def test_fixture_pins(self):
        # Verify the frozen reviewed fixture, not the source worker's in-progress telemetry edit.
        game=Path(__import__('os').environ.get('CONSTRUCTION_TEST_GAME', str(HERE.parent/'game')))
        for name,sha in v.FIXTURES.values():self.assertEqual(hashlib.sha256((game/name).read_bytes()).hexdigest(),sha)
    def test_approved_hud_execution_order(self):
        self.assertEqual(len(C['hud_names']),34)
        self.assertEqual(C['hud_names'][19],'QA HUD is absent without opt in')
        self.assertEqual(C['hud_names'][-2],'QA excludes fully clipped button')
        self.assertEqual(C['hud_names'][-1],'restart clears construction recovery directions')
        report=example('construction_status_hud');report['checks']=report['checks'][:19]+[report['checks'][-1]]
        report['passed']=20
        with self.assertRaises(ValueError):v.validate(report,'construction_status_hud',LOCK,C)
    def test_supervisor_pin(self):
        self.assertEqual(hashlib.sha256(Path(r.logic.__file__).read_bytes()).hexdigest(),r.LOGIC_SHA)
        self.assertIs(r.logic.p,r.p)
    def test_syntax(self):
        for path in HERE.glob('*.py'):compile(path.read_text(),str(path),'exec')


class FinalBindingTests(unittest.TestCase):
    def exercise(self, fail_monitor=False, drift_on_parse=False):
        from contextlib import ExitStack
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp, ExitStack() as stack:
            root=Path(temp);project=root/'project';project.mkdir()
            for name in ('godot','marker'): (root/name).write_text('fake')
            lock=copy.deepcopy(LOCK)
            lock.update({'contracts_reviewed_for_execution':True,'contracts_stop_reviewed_for_execution':True,'contracts_consolidated_reviewed_for_execution':True,'contracts_supervisor_sha256':r.LOGIC_SHA,
                         'source_commit':'fake-source','game_tree':'fake-tree'})
            for name,sha in v.FIXTURES.values():lock['project_files'][name]=sha
            for key in ('runner_sha256','owned_process_sha256','contracts_runner_sha256','contracts_validator_sha256','contracts_names_sha256'):lock[key]='fake-test-pin'
            lockpath=root/'lock.json';lockpath.write_text(json.dumps(lock))
            state={'drift':False,'inventories':0,'monitor_calls':0,'reports':0}
            def inventory(*args):
                state['inventories']+=1
                return ({'fake':'changed' if state['drift'] else 'source'},{})
            def monitor(argv,env,stage,before):
                state['monitor_calls']+=1
                (stage/'receipt.json').write_text('{}')
                (stage/'godot.log').write_text('fake log')
                if stage.name==v.FILE_SUITE: (stage/v.FILE_REPORT).write_text('{}')
                return {'passed':not fail_monitor,'cleanup_complete':True,'test_dependencies':False,
                        'unexpected_descendants':[],'log_sha256':r.p.digest(stage/'godot.log')}
            def report(*args):
                state['reports']+=1
                if drift_on_parse and state['reports']==len(r.SUITES):state['drift']=True
                return example(args[1])
            original_read=Path.read_text
            def read_text(path,*args,**kwargs):
                if str(path)=='/etc/os-release':return 'VERSION_ID="24.04"'
                return original_read(path,*args,**kwargs)
            stack.enter_context(patch.dict(r.os.environ,{'GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted'}))
            stack.enter_context(patch.object(Path,'read_text',read_text))
            stack.enter_context(patch.object(r.r,'validate_lock',return_value=None))
            stack.enter_context(patch.object(r.r,'checked',side_effect=lambda path,sha:Path(path)))
            stack.enter_context(patch.object(r.r,'validate_import',return_value=[]))
            stack.enter_context(patch.object(r.p,'source_inventory',side_effect=inventory))
            stack.enter_context(patch.object(r.p,'cache_inputs',return_value={'fake':'cache'}))
            stack.enter_context(patch.object(r.p,'metrics',return_value={'fake':'no-live-telemetry'}))
            stack.enter_context(patch.object(r.logic,'supervise',side_effect=monitor))
            stack.enter_context(patch.object(r.v,'read_log',side_effect=report))
            stack.enter_context(patch.object(r.v,'read_file_report',side_effect=report))
            args=types.SimpleNamespace(lock=lockpath,project=project,output=root/'out',private=root/'private',godot=root/'godot',import_marker=root/'marker')
            code=r.run(args)
            receipt=json.loads((root/'out/construction-contracts-receipt.json').read_text())
            return code,receipt,state
    def test_failed_run_still_checks_bindings(self):
        code,receipt,state=self.exercise(fail_monitor=True)
        self.assertEqual(code,1);self.assertFalse(receipt['passed'])
        self.assertTrue(receipt['post_run_binding_matches'])
        self.assertEqual(state['inventories'],3) # initial, pre-child, unconditional finally
        self.assertEqual(state['monitor_calls'],1)
    def test_success_counts_reported_executed_assertions(self):
        code,receipt,state=self.exercise()
        self.assertEqual(code,0);self.assertTrue(receipt['passed'])
        self.assertEqual([row['assertions_executed'] for row in receipt['suites']],[34,34,22,64,58,76,26,726])
        self.assertEqual(receipt['assertions_executed'],1040)
        self.assertEqual(state['monitor_calls'],8)
    def test_drift_after_last_report_parse_fails(self):
        code,receipt,state=self.exercise(drift_on_parse=True)
        self.assertEqual(code,1);self.assertFalse(receipt['passed'])
        self.assertFalse(receipt['post_run_binding_matches']);self.assertIn('binding_error',receipt)
        self.assertEqual(state['reports'],8);self.assertEqual(state['monitor_calls'],8)

class StopTests(unittest.TestCase):
    def test_exact_names(self):
        for suite,count in v.STOP_COUNTS.items():
            self.assertEqual(len(C[suite+'_names']),count)
        names=C[v.FILE_SUITE+'_names']
        self.assertEqual([i for i,n in enumerate(names) if n=='fixture has scout'],[0,12,29,41])
        self.assertEqual(len(set(names)),55)
        for suite in ('mobile_stop_control_contract','mobile_stop_control_phone'):
            self.assertEqual(len(C[suite+'_names']),v.STOP_COUNTS[suite])

    def test_stop_negative_reports(self):
        for suite in v.STOP_COUNTS:
            for mutation in ('duplicate','missing','false','name','reorder','extra','scope','build','verdict_integer','wrong_keys'):
                report=example(suite)
                if mutation=='duplicate':report['checks'][-1]=report['checks'][0]
                if mutation=='missing':report['checks'].pop()
                if mutation=='false':report['checks'][0]['passed']=False
                if mutation=='name':report['checks'][0]['name']='wrong'
                if mutation=='reorder':report['checks'][0],report['checks'][1]=report['checks'][1],report['checks'][0]
                if mutation=='extra':report['extra']=True
                if mutation=='scope':report['scope']='natural-play proof'
                if mutation=='build':report['build']='other'
                if mutation=='verdict_integer':report['checks'][0]['passed']=1
                if mutation=='wrong_keys':report['checks'][0]={'name':report['checks'][0]['name'],'pass':True}
                with self.subTest(suite=suite,mutation=mutation),self.assertRaises(ValueError):v.validate(report,suite,LOCK,C)
            bad_lock=copy.deepcopy(LOCK);bad_lock['project_files']['scripts/game.gd']='b'*64
            with self.assertRaises(ValueError):v.validate(example(suite),suite,bad_lock,C)
        for suite in ('mobile_stop_control_contract','mobile_stop_control_phone'):
            for key,value in [('suite','wrong'),('failed',True),('failed',1),('source_sha256','b'*64)]:
                report=example(suite);report[key]=value
                with self.subTest(suite=suite,key=key),self.assertRaises(ValueError):v.validate(report,suite,LOCK,C)

    def test_exact_phone_events(self):
        for number in (True,0,76,78,77.0,'77'):
            report=example('mobile_stop_control_phone');report['input_events']=number
            with self.subTest(number=number),self.assertRaises(ValueError):v.validate(report,'mobile_stop_control_phone',LOCK,C)

    def test_stance_events_and_pass(self):
        for number in range(56,147,3):
            report=example(v.FILE_SUITE);report['touch_events']=number;v.validate(report,v.FILE_SUITE,LOCK,C)
        for number in (True,0,55,57,147,149,56.0,'56'):
            report=example(v.FILE_SUITE);report['touch_events']=number
            with self.subTest(number=number),self.assertRaises(ValueError):v.validate(report,v.FILE_SUITE,LOCK,C)
        for value in (False,1,'true'):
            report=example(v.FILE_SUITE);report['pass']=value
            with self.assertRaises(ValueError):v.validate(report,v.FILE_SUITE,LOCK,C)

    def test_unknown_suite(self):
        with self.assertRaisesRegex(ValueError,'Unsupported suite'):v.validate({},'arbitrary',LOCK,C)

    def test_stop_logs(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'godot.log'
            for suite in ('mobile_stop_control_contract','mobile_stop_control_phone'):
                line=json.dumps(example(suite));path.write_text('Godot startup\n'+line+'\n')
                v.read_log(path,suite,LOCK,C)
                for data in ('',line+'\n'+line+'\n','{"suite":"x","suite":"y"}',line[:-1]+',"unexpected":NaN}'):
                    path.write_text(data)
                    with self.assertRaises(ValueError):v.read_log(path,suite,LOCK,C)

    def test_stance_file(self):
        with tempfile.TemporaryDirectory() as temp:
            stage=Path(temp);path=stage/v.FILE_REPORT;log=stage/'godot.log'
            line=json.dumps(example(v.FILE_SUITE));path.write_text(line);log.write_text('Godot startup\n')
            v.read_file_report(stage,v.FILE_SUITE,LOCK,C)
            log.write_text('{}\n')
            with self.assertRaises(ValueError):v.read_file_report(stage,v.FILE_SUITE,LOCK,C)
            log.write_text('Godot startup\n')
            for data in ('',line+'\n'+line,'{"pass":true,"pass":true}',' '*131073):
                path.write_text(data)
                with self.assertRaises(ValueError):v.read_file_report(stage,v.FILE_SUITE,LOCK,C)
            path.unlink();target=stage/'other';target.write_text(line);path.symlink_to(target)
            with self.assertRaises(ValueError):v.read_file_report(stage,v.FILE_SUITE,LOCK,C)

    def test_source_and_supervisor_are_exact(self):
        game=Path(__import__('os').environ.get('CONSTRUCTION_TEST_GAME', str(HERE.parent/'game')))
        self.assertEqual(hashlib.sha256((game/'scripts/game.gd').read_bytes()).hexdigest(),v.GAME_SHA)
        code=Path(r.logic.__file__).read_text()
        for fragment in ("'timeout_seconds': 120", "time.monotonic() - start <= 120", "'OOM count changed'", "'Unexpected descendant; no retry'", "'cleanup_complete'"):
            self.assertIn(fragment,code)

    def test_packager_requires_eight_suites(self):
        tree=ast.parse((HERE/'package_web_release.py').read_text())
        matching=[n for n in ast.walk(tree) if isinstance(n,ast.List) and all(isinstance(e,ast.Constant) for e in n.elts)
                  and [e.value for e in n.elts]==list(r.SUITES)]
        self.assertEqual(len(matching),1)

class ConsolidatedTests(unittest.TestCase):
    def test_exact_suite_order_and_count(self):
        self.assertEqual(r.SUITES,('construction_status','construction_status_hud','mobile_stop_control_contract',
            'mobile_stop_control_phone','stance_target_cancel_phone','contextual_touch_contract','contextual_touch_phone','main_menu_flow_contract'))
        for suite,count in {**v.ARRAY_COUNTS,'main_menu_flow_contract':726}.items():
            self.assertEqual(len(C[suite+'_names']),count)
            self.assertEqual(len(C[suite+'_names']),count)
            self.assertEqual(r.argv('/godot','/game',suite)[-1],'res://'+v.FIXTURES[suite][0])

    def test_new_suite_negative_reports(self):
        for suite in (*v.ARRAY_COUNTS,'main_menu_flow_contract'):
            for mutation in ('empty','missing','extra','duplicate','false','int_verdict','wrong_keys','name','reorder','null'):
                report=example(suite);checks=report if type(report) is list else report['checks']
                if mutation=='empty':checks.clear()
                if mutation=='missing':checks.pop()
                if mutation=='extra':checks.append(checks[-1])
                if mutation=='duplicate':checks[-1]=checks[0]
                if mutation=='false':checks[0]['passed']=False
                if mutation=='int_verdict':checks[0]['passed']=1
                if mutation=='wrong_keys':checks[0]={'name':checks[0]['name'],'pass':True}
                if mutation=='name':checks[0]['name']='wrong'
                if mutation=='reorder':checks[0],checks[1]=checks[1],checks[0]
                if mutation=='null':checks[0]=None
                with self.subTest(suite=suite,mutation=mutation),self.assertRaises(ValueError):v.validate(report,suite,LOCK,C)
            # An early success report must never pass, even if every emitted
            # check is true and no failure count is reported.
            for length in range(len(C[suite+'_names'])):
                report=example(suite)
                if type(report) is list:report=report[:length]
                else:report['checks']=report['checks'][:length]
                with self.subTest(suite=suite,early_length=length),self.assertRaises(ValueError):v.validate(report,suite,LOCK,C)

    def test_menu_identity_and_failure_fields(self):
        for key,value in [('suite','other'),('build','other'),('scope','played victory'),('failure_count',False),('failure_count',1),('failure_count',0.0),('source_sha256',{})]:
            report=example('main_menu_flow_contract');report[key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):v.validate(report,'main_menu_flow_contract',LOCK,C)
        report=example('main_menu_flow_contract');report['passed']=16
        with self.assertRaises(ValueError):v.validate(report,'main_menu_flow_contract',LOCK,C)
        report=example('main_menu_flow_contract');report['source_sha256']['scripts/main_menu.gd']='0'*64
        with self.assertRaises(ValueError):v.validate(report,'main_menu_flow_contract',LOCK,C)

    def test_all_suite_source_and_build_binding(self):
        for suite in r.SUITES:
            for name in (v.FIXTURES[suite][0],'scripts/game.gd','scripts/construction_status.gd'):
                bad=copy.deepcopy(LOCK);bad['project_files'][name]='0'*64
                with self.subTest(suite=suite,name=name),self.assertRaises(ValueError):v.validate(example(suite),suite,bad,C)
            bad=copy.deepcopy(LOCK);bad['build']='other'
            with self.assertRaises(ValueError):v.validate(example(suite),suite,bad,C)
        bad=copy.deepcopy(LOCK);bad['project_files']['scripts/main_menu.gd']='0'*64
        with self.assertRaises(ValueError):v.validate(example('main_menu_flow_contract'),'main_menu_flow_contract',bad,C)

    def test_contextual_dictionary_name_is_strict(self):
        report=example('contextual_touch_contract')
        report[11]['name']='reject invalid selection { "alive": false }'
        v.validate(report,'contextual_touch_contract',LOCK,C)
        for tail in ('{"alive":true}','{"alive":false,"alive":false}','{"alive":NaN}','{"alive":1e999}','{"alive":0}','{"alive":false,"extra":false}'):
            report[11]['name']='reject invalid selection '+tail
            with self.subTest(tail=tail),self.assertRaises(ValueError):v.validate(report,'contextual_touch_contract',LOCK,C)

    def test_prefixed_array_logs(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'godot.log'
            for suite in v.ARRAY_COUNTS:
                raw=json.dumps(example(suite));line=v.PREFIXES[suite]+' '+raw
                path.write_text('Godot startup\n'+line+'\n');v.read_log(path,suite,LOCK,C)
                for data in (raw,line+'\n'+line,line+'\n{}',line+'\n[]','CONTEXTUAL_TOUCH_WRONG '+raw,' '+line,
                             v.PREFIXES[suite]+': '+raw,v.PREFIXES[suite]+' []',
                             v.PREFIXES[suite]+' [{"name":"x","name":"x","passed":true}]',
                             line[:-1]+',NaN]',line+' '*131073):
                    path.write_text(data)
                    with self.subTest(suite=suite,data=data[:90]),self.assertRaises(ValueError):v.read_log(path,suite,LOCK,C)

    def test_menu_log_and_wrong_report_combinations(self):
        with tempfile.TemporaryDirectory() as temp:
            stage=Path(temp);path=stage/'godot.log';suite='main_menu_flow_contract';line=json.dumps(example(suite))
            path.write_text('Godot startup\n'+line+'\n');v.read_log(path,suite,LOCK,C)
            for data in ('MAIN_MENU_FLOW: PASS',line+'\n'+line,line+'\nCONTEXTUAL_TOUCH_PHONE []',line+' '*131073):
                path.write_text(data)
                with self.assertRaises(ValueError):v.read_log(path,suite,LOCK,C)
            (stage/v.FILE_REPORT).write_text(json.dumps(example(v.FILE_SUITE)))
            for data in ('[]','CONTEXTUAL_TOUCH_PHONE []','CONTEXTUAL_TOUCH_CONTRACT []'):
                path.write_text(data)
                with self.assertRaises(ValueError):v.read_file_report(stage,v.FILE_SUITE,LOCK,C)

    def test_logs_reject_oversize_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            stage=Path(temp);path=stage/'godot.log';target=stage/'other'
            target.write_text(v.PREFIXES['contextual_touch_phone']+' '+json.dumps(example('contextual_touch_phone')))
            path.symlink_to(target)
            with self.assertRaises(ValueError):v.read_log(path,'contextual_touch_phone',LOCK,C)
            path.unlink()
            with path.open('wb') as out:out.truncate(16*1024*1024+1)
            with self.assertRaises(ValueError):v.read_log(path,'contextual_touch_phone',LOCK,C)

    def test_monitors_exact_identity_and_reviewed_exit_race(self):
        expected={'owned_process.py':'e25db8799c62725ee6af547484c7414a6f2685dcbd5ad97d78ea9b059657f320',
                  'run_logic.py':'2800e75273335ce8ffefccb1db6128b54f09850b50dc243cf73e7065ff107607',
                  'run_export.py':'f16e36308ee76c6dc7759cf9540bc2a00b13d635b398c6881d0eb5f5fca34819'}
        for name,sha in expected.items():
            data=(HERE/name).read_bytes()
            if name in ('run_logic.py','run_export.py'):
                current=b"MONITOR_SHA = 'f0daa328970f63704c8419f332d42a5abefbc6d03fbd256127697a40c349a6bd'"
                prior=b"MONITOR_SHA = '4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50'"
                self.assertEqual(data.count(current),1)
                data=data.replace(current,prior,1)
            if name=='owned_process.py':
                # Remove only the reviewed exact shader-UID derivation line before baseline comparison.
                delta=b"    if 'assets/mature/menu/menu_backdrop.gdshader' in original and 'assets/mature/menu/menu_backdrop.gdshader.uid' not in original: expected = sorted(expected + ['assets/mature/menu/menu_backdrop.gdshader.uid'])\n"
                self.assertEqual(data.count(delta),1)
                data=data.replace(delta,b'')
            if name=='run_export.py':
                # Reverse only the independently reviewed, evidence-bound exit-mm phase additions.
                exit_phase_hunks = [('def exit_read(path):\n    with path.open() as stream:\n        value = stream.read(65537)\n    if len(value) > 65536:\n        raise RuntimeError(\'Oversized exit-phase field\')\n    return value\n\nclass ExitPhaseDescendants(RuntimeError):\n    def __init__(self, pids):\n        super().__init__(\'Exit-phase unexpected descendants\')\n        self.pids = pids\n\ndef exit_identity(pid, root=Path(\'/proc\')):\n    raw = exit_read(root / str(pid) / \'stat\')\n    opened, closed = raw.find(\'(\'), raw.rfind(\')\')\n    if opened <= 0 or closed <= opened:\n        raise RuntimeError(\'Malformed exit-phase identity\')\n    tail = raw[closed + 2:].split()\n    if len(tail) < 50 or int(raw[:opened].strip()) != pid:\n        raise RuntimeError(\'Incomplete exit-phase identity\')\n    return {\'pid\': pid, \'ppid\': int(tail[1]), \'starttime_ticks\': int(tail[19]),\n            \'flags\': int(tail[6]), \'state\': tail[0]}\n\ndef exit_snapshot(pid, expected, root=Path(\'/proc\')):\n    """All reads must succeed; identity and single-task proof bracket status/mm."""\n    path = root / str(pid)\n    before = exit_identity(pid, root)\n    for key in (\'pid\', \'ppid\', \'starttime_ticks\'):\n        if before[key] != expected[key]:\n            raise RuntimeError(\'Exit-phase lifetime changed\')\n    if before[\'flags\'] & 4 == 0:\n        raise RuntimeError(\'Exit-phase PF_EXITING absent\')\n    tasks = sorted(x.name for x in (path / \'task\').iterdir())\n    if tasks != [str(pid)]:\n        raise RuntimeError(\'Exit-phase task set not sole owned leader\')\n    task_identity = exit_identity(pid, path / \'task\')\n    if any(task_identity[k] != before[k] for k in (\'pid\',\'ppid\',\'starttime_ticks\')) or task_identity[\'flags\'] & 4 == 0:\n        raise RuntimeError(\'Exit-phase task identity/flag mismatch\')\n    for current in (path, path / \'task\' / str(pid)):\n        status = dict(line.split(\':\', 1) for line in exit_read(current / \'status\').splitlines() if \':\' in line)\n        if any(int(status[k]) != v for k, v in ((\'Pid\',pid),(\'Tgid\',pid),(\'Threads\',1))):\n            raise RuntimeError(\'Exit-phase status identity mismatch\')\n        if \'VmRSS\' in status or \'VmHWM\' in status:\n            raise RuntimeError(\'Exit-phase memory still present\')\n        mm = exit_read(current / \'statm\').split()\n        if mm != [\'0\'] * 7:\n            raise RuntimeError(\'Exit-phase mm not detached\')\n    children = exit_read(path / \'task\' / str(pid) / \'children\').split()\n    if children:\n        if len(children) > 128 or any(not x.isdigit() or int(x) <= 0 for x in children):\n            raise RuntimeError(\'Invalid exit-phase descendants\')\n        raise ExitPhaseDescendants(children)\n    after = exit_identity(pid, root)\n    if any(after[k] != before[k] for k in (\'pid\',\'ppid\',\'starttime_ticks\')) or after[\'flags\'] & 4 == 0:\n        raise RuntimeError(\'Exit-phase identity/flag changed\')\n    if sorted(x.name for x in (path / \'task\').iterdir()) != [str(pid)]:\n        raise RuntimeError(\'Exit-phase task set changed\')\n    return {\'pid\':pid,\'starttime_ticks\':before[\'starttime_ticks\'],\'flags\':after[\'flags\'],\n            \'single_task\':True,\'mm_detached\':True,\'children_empty\':True}\n\n\nREAL += (exit_read, exit_identity, exit_snapshot)\n\n', ''), ('                    p.select.select, os.close, exit_read, exit_identity, exit_snapshot), REAL))}\n', '                    p.select.select, os.close), REAL))}\n'), ('    complete_sample_seen = False\n', ''), ("    def verified_exit_phase(event):\n        p.require(complete_sample_seen, 'No prior complete owned sample')\n        if child.poll() is not None:\n            event['outcome'] = 'confirmed_exit'\n            return\n        expected_identity = exit_identity(child.pid)\n        p.require(expected_identity['pid'] == child.pid and expected_identity['ppid'] == os.getpid(), 'Owned export parent mismatch')\n        if child.poll() is not None:\n            event['outcome'] = 'confirmed_exit'\n            return\n        phase_start = time.monotonic()\n        observations = []\n        receipt.setdefault('exit_phase_attempts', []).append({'start_seconds': phase_start-start, 'observations': observations})\n        def phase_check():\n            p.require(not stopped, 'Termination requested')\n            p.require(time.monotonic() - start <= 300, 'Export timeout')\n            p.require(time.monotonic() - phase_start <= 1.0, 'Exit-phase timeout')\n            logpath = directory / 'godot.log'\n            if logpath.exists():\n                p.require(logpath.stat().st_size <= 16*1024*1024, 'Export log oversized')\n            check_sample(p.metrics(), before, None)\n        while True:\n            phase_check()\n            if child.poll() is not None:\n                break\n            try:\n                pair = [exit_snapshot(child.pid, expected_identity), exit_snapshot(child.pid, expected_identity)]\n            except ExitPhaseDescendants as exc:\n                receipt['unexpected_descendants'].append({'status': 'unexpected_child_detected',\n                    'parent_pid': child.pid, 'pids': exc.pids[:16], 'truncated': len(exc.pids) > 16})\n                save()\n                try:\n                    receipt['unexpected_descendants'].extend(p.observe_descendants('godot', child, exc.pids, tracked))\n                except Exception as observed_error:\n                    receipt['unexpected_descendants'].append({'status': 'observation_failed', 'type': type(observed_error).__name__})\n                raise RuntimeError('Unexpected descendant; no retry')\n            except (FileNotFoundError, ProcessLookupError):\n                if child.poll() is None:\n                    raise\n                break\n            observations.append({'seconds': round(time.monotonic()-start, 6), 'proof': pair})\n            p.require(len(observations) <= 101, 'Exit-phase observation bound')\n            phase_check()\n            time.sleep(0.01)\n        phase_check()\n        if not observations:\n            event['outcome'] = 'confirmed_exit'\n            return\n        event['outcome'] = 'verified_exit_phase_then_owned_exit'\n        receipt.setdefault('verified_exit_phase', []).append({'elapsed': time.monotonic()-phase_start,\n            'observations': observations, 'owned_exit': child.poll()})\n\n", ''), ('        nonlocal complete_sample_seen\n', ''), ("                        try:\n                            row = p.process_metrics(child)  # One complete read or narrow proven exit phase.\n                        except KeyError:\n                            verified_exit_phase(event)\n                        else:\n                            event['outcome'] = 'recovered_live_complete_telemetry'\n", "                        row = p.process_metrics(child)  # One complete read or fail closed.\n                        event['outcome'] = 'recovered_live_complete_telemetry'\n"), ('        if row is not None:\n            complete_sample_seen = True\n', '')]
                for current_phase, prior_phase in exit_phase_hunks:
                    self.assertEqual(data.count(current_phase.encode()),1)
                    data=data.replace(current_phase.encode(),prior_phase.encode())
                # Reverse only the independently reviewed exit-race hunk, then retain full original guard hash.
                reviewed_delta=b"            except (FileNotFoundError, KeyError, ProcessLookupError) as exc:\n                event = {'initial_error': type(exc).__name__, 'wait_timeout_seconds': 0.05}\n                receipt.setdefault('telemetry_races', []).append(event)\n                try:\n                    child.wait(timeout=0.05)\n                    event['outcome'] = 'confirmed_exit'\n                except subprocess.TimeoutExpired:\n                    # No longer wait and never accept an unobserved live process.\n                    if child.poll() is not None:\n                        event['outcome'] = 'confirmed_exit'\n                    else:\n                        event['outcome'] = 'live_reread_required'\n                        row = p.process_metrics(child)  # One complete read or fail closed.\n                        event['outcome'] = 'recovered_live_complete_telemetry'\n                # The bounded wait must not hide stop, deadline, reserve or OOM changes.\n                p.require(not stopped, 'Termination requested')\n                p.require(time.monotonic() - start <= 300, 'Export timeout')\n                system = p.metrics()\n"
                original_delta=b'            except (FileNotFoundError, KeyError, ProcessLookupError):\n                child.wait(timeout=0.05)\n'
                self.assertEqual(data.count(reviewed_delta),1)
                data=data.replace(reviewed_delta,original_delta)
                for current,baseline in [('727bfc928d6962df34095b00076abba4a07eaf16','677096aaaa5131089971c2ec85b598ad20bd91da'),('276bdc285d2c9a41128c3fb88d0e0926994e4678','dec0eabb654f36c837e68db547d4282bea0754fb'),('vc-21fe3bd842be','vc-cf764648c52f')]:
                    self.assertEqual(data.count(current.encode()),1)
                    data=data.replace(current.encode(),baseline.encode())
            self.assertEqual(hashlib.sha256(data).hexdigest(),sha)

class ImportMonitorConsumerPins(unittest.TestCase):
    def test_every_consumer_matches_actual_monitor(self):
        import guarded_manifest_ci,run_logic,run_export,run_export_diagnostic
        digest=hashlib.sha256((HERE/'hardened_monitored_run.py').read_bytes()).hexdigest()
        import run_contracts,run_military,run_faction,run_building_contracts,run_latest_contracts
        logic_digest=hashlib.sha256((HERE/'run_logic.py').read_bytes()).hexdigest()
        for consumer in (run_contracts,run_military,run_faction,run_building_contracts,run_latest_contracts):
            self.assertEqual(consumer.LOGIC_SHA,logic_digest)
        for module in (guarded_manifest_ci,run_logic,run_export,run_export_diagnostic):
            with self.subTest(module=module.__name__):self.assertEqual(module.MONITOR_SHA,digest)
    def test_complete_import_receipt_new_old_mixed_pins(self):
        import run_logic,run_export,run_export_diagnostic
        new=hashlib.sha256((HERE/'hardened_monitored_run.py').read_bytes()).hexdigest()
        old='4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50'
        for module in (run_logic,run_export,run_export_diagnostic):
            for load,invoke,accepted in ((new,new,True),(old,old,False),(old,new,False),(new,old,False)):
                with self.subTest(module=module.__name__,load=load,invoke=invoke),tempfile.TemporaryDirectory() as td:
                    root=Path(td);project=root/'project';project.mkdir()
                    request={'test_dependencies':False,'helper':{'load_sha256':load,'invocation_sha256':invoke}}
                    invocation=root/'import.invocation.json';invocation.write_text(json.dumps(request))
                    log=root/'import.log';log.write_text('SYNTHETIC complete import receipt; no engine executed')
                    receipt=root/'import.json'
                    result={'passed':True,'cleanup_complete':True,'child_started':True,'exit':0,'log_sha256':module.p.digest(log),'invocation_sha256':module.p.digest(invocation),'exception':None,'stop_reason':None,'cleanup_errors':[],'output_errors':[],'post_run_binding_matches':{'synthetic':True}}
                    receipt.write_text(json.dumps(result))
                    lock={'source_archive_sha256':'a'*64,'import_manifest_sha256':'b'*64,'import_adapter_sha256':'c'*64}
                    cert={'build':module.BUILD,'project':str(project),'archive_sha256':lock['source_archive_sha256'],'engine_sha256':module.ENGINE_SHA,'manifest_sha256':lock['import_manifest_sha256'],'adapter_sha256':lock['import_adapter_sha256'],'cache_sha256':{},'generated_uid_sha256':{},'receipt':str(receipt),'receipt_sha256':module.p.digest(receipt),'invocation':str(invocation),'invocation_sha256':module.p.digest(invocation)}
                    marker=root/'import-complete.json';marker.write_text(json.dumps(cert))
                    if accepted:self.assertEqual(module.validate_import(project,lock,marker,{},{}),[receipt,invocation,log])
                    else:
                        with self.assertRaisesRegex(RuntimeError,'Wrong import monitor'):module.validate_import(project,lock,marker,{},{})


if __name__=='__main__':unittest.main()
