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
LOCK={'build':'vc-0f3970202382','project_files':{'scripts/construction_status.gd':v.STATUS_SHA,'scripts/game.gd':'a'*64,'tests/construction_status_hud.gd':v.FIXTURES['construction_status_hud'][1]}}

def example(suite):
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
        for suite in r.SUITES:
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
        for value in ('{"a":1,"a":2}','{"a":NaN}'):
            with self.assertRaises(ValueError):v.parse_json(value)
    def test_exact_argv(self):
        command=r.argv('/godot','/game','construction_status_hud')
        self.assertEqual(command,['/godot','--headless','--path','/game','--audio-driver','Dummy','--resolution','390x844','--fixed-fps','30','--script','res://tests/construction_status_hud.gd'])
        with self.assertRaises(RuntimeError):r.argv('/godot','/game','arbitrary')
    def test_disabled_before_metrics(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'lock.json';path.write_text('{"contracts_reviewed_for_execution":false}')
            with self.assertRaisesRegex(RuntimeError,'not reviewed'):r.run(types.SimpleNamespace(lock=path))
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
        self.assertEqual(len(C['hud_names']),30)
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
            lock.update({'contracts_reviewed_for_execution':True,'contracts_supervisor_sha256':r.LOGIC_SHA,
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
                return {'passed':not fail_monitor,'cleanup_complete':True,'test_dependencies':False,
                        'unexpected_descendants':[],'log_sha256':r.p.digest(stage/'godot.log')}
            def report(*args):
                state['reports']+=1
                if drift_on_parse and state['reports']==2:state['drift']=True
                return {'synthetic':True}
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
    def test_drift_after_last_report_parse_fails(self):
        code,receipt,state=self.exercise(drift_on_parse=True)
        self.assertEqual(code,1);self.assertFalse(receipt['passed'])
        self.assertFalse(receipt['post_run_binding_matches']);self.assertIn('binding_error',receipt)
        self.assertEqual(state['reports'],2);self.assertEqual(state['monitor_calls'],2)

if __name__=='__main__':unittest.main()
