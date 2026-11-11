"""Synthetic/source-only tests. All execution/metrics dependencies mocked."""
import copy,hashlib,json,tempfile,types,unittest
from pathlib import Path
from contextlib import ExitStack
from unittest.mock import patch
import run_military as r
import validate_military as v
C=v.C
LOCK={'build':v.BUILD,'project_files':{'scripts/game.gd':v.GAME_SHA,**dict(v.FIXTURES.values())}}
def example(suite):
    key='results' if suite=='military_progression_contract' else 'checks'
    rows=[{'name':n,'passed':True} for n in C['names'][suite]]
    report={'build':v.BUILD,'scope':v.SCOPES[suite],'total':len(rows),'failed':0,'elapsed_ms':100,key:rows}
    if key=='results':report['engine']={'major':4,'minor':6,'patch':3,'status':'stable'}
    else:report.update(suite=suite,max_path_queries=4,max_path_expansions=16384)
    return report
class Tests(unittest.TestCase):
    def test_reports(self):
        for suite in r.SUITES:v.validate(example(suite),suite,LOCK)
    def test_negative_reports(self):
        for suite in r.SUITES:
            for key in ('missing','false','name','count','bool','deadline','scope','build','extra'):
                q=example(suite);rows=q['results' if suite=='military_progression_contract' else 'checks']
                if key=='missing':rows.pop()
                elif key=='false':rows[0]['passed']=False
                elif key=='name':rows[0]['name']='other'
                elif key=='count':q['total']+=1
                elif key=='bool':q['failed']=False
                elif key=='deadline':q['elapsed_ms']=100000
                elif key=='scope':q['scope']='Natural victory proof'
                elif key=='build':q['build']='wrong'
                else:q['extra']=True
                with self.subTest(suite=suite,key=key),self.assertRaises(ValueError):v.validate(q,suite,LOCK)
    def test_disabled_before_metrics(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'lock.json';p.write_text('{"military_reviewed_for_execution":false}')
            with patch.object(r.p,'metrics',side_effect=AssertionError('No sampling permitted')):
                with self.assertRaisesRegex(RuntimeError,'not reviewed'):r.run(types.SimpleNamespace(lock=p))
    def test_argv_rejects_unknown_or_extra(self):
        self.assertEqual(r.argv('/godot','/game',r.SUITES[0])[-1],'res://tests/military_progression_contract.gd')
        with self.assertRaises(RuntimeError):r.argv('/godot','/game','other')
        with self.assertRaises(RuntimeError):r.argv('/godot','/game',r.SUITES[0],Path('/extra'))
    def test_strict_log(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'godot.log'
            for suite in r.SUITES:
                line=v.PREFIXES[suite]+json.dumps(example(suite))
                p.write_text('Godot\n'+line+'\n');v.read_log(p,suite,LOCK)
                for bad in [line+'\n'+line,line+'\n[]',line+' '*131073]:
                    p.write_text(bad)
                    with self.assertRaises(ValueError):v.read_log(p,suite,LOCK)
    def test_exact_source_and_unchanged_supervisor(self):
        here=Path(__file__).parent
        self.assertEqual(hashlib.sha256(Path(r.logic.__file__).read_bytes()).hexdigest(),r.LOGIC_SHA)
        self.assertIs(r.p,r.logic.p)
        for name,sha in v.FIXTURES.values():self.assertEqual(hashlib.sha256((here.parent/'game'/name).read_bytes()).hexdigest(),sha)
        self.assertEqual(hashlib.sha256((here.parent/'game/scripts/game.gd').read_bytes()).hexdigest(),v.GAME_SHA)
    def exercise(self,fail=False,drift=False):
        with tempfile.TemporaryDirectory() as t,ExitStack() as stack:
            root=Path(t);project=root/'project';project.mkdir()
            for name in ('godot','marker'):(root/name).write_text('fake')
            lock=copy.deepcopy(LOCK);lock.update(military_reviewed_for_execution=True,military_supervisor_sha256=r.LOGIC_SHA,source_commit='fake',game_tree='fake')
            for key in ('runner_sha256','owned_process_sha256','military_runner_sha256','military_validator_sha256','military_names_sha256'):lock[key]='fake'
            path=root/'lock.json';path.write_text(json.dumps(lock));state={'drift':False,'calls':0,'reports':0,'inventories':0}
            def inventory(*args):
                state['inventories']+=1
                return ({'fake':'changed' if state['drift'] else 'source'},{})
            def monitor(argv,env,stage,before):
                state['calls']+=1;(stage/'receipt.json').write_text('{}');(stage/'godot.log').write_text('fake')
                return {'passed':not fail,'cleanup_complete':True,'test_dependencies':False,'unexpected_descendants':[],'log_sha256':r.p.digest(stage/'godot.log')}
            def report(*args):
                state['reports']+=1
                if drift and state['reports']==2:state['drift']=True
                q=example(args[1]);return {'checks':q.get('checks',q.get('results')),'report':q}
            read=Path.read_text
            def read_text(p,*args,**kw):return 'VERSION_ID="24.04"' if str(p)=='/etc/os-release' else read(p,*args,**kw)
            stack.enter_context(patch.object(Path,'read_text',read_text));stack.enter_context(patch.dict(r.os.environ,{'GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted'}))
            for obj,name,options in [(r.r,'validate_lock',{'return_value':None}),(r.r,'checked',{'side_effect':lambda path,sha:Path(path)}),(r.r,'validate_import',{'return_value':[]}),(r.p,'source_inventory',{'side_effect':inventory}),(r.p,'cache_inputs',{'return_value':{'fake':'cache'}}),(r.p,'metrics',{'return_value':{'fake':'no live metrics'}}),(r.logic,'supervise',{'side_effect':monitor}),(r.v,'read_log',{'side_effect':report})]:stack.enter_context(patch.object(obj,name,**options))
            code=r.run(types.SimpleNamespace(lock=path,project=project,output=root/'out',private=root/'private',godot=root/'godot',import_marker=root/'marker'))
            return code,json.loads((root/'out/military-contracts-receipt.json').read_text()),state
    def test_success_counts(self):
        code,report,state=self.exercise();self.assertEqual(code,0);self.assertEqual(report['assertions_executed'],95);self.assertEqual(state['calls'],2)
    def test_failure_no_next_process_final_binding(self):
        code,report,state=self.exercise(fail=True);self.assertEqual(code,1);self.assertEqual(state['calls'],1);self.assertTrue(report['post_run_binding_matches']);self.assertEqual(state['inventories'],3)
    def test_final_report_drift_rejected(self):
        code,report,state=self.exercise(drift=True);self.assertEqual(code,1);self.assertFalse(report['post_run_binding_matches']);self.assertEqual(state['calls'],2)
if __name__=='__main__':unittest.main()
