"""Pure package/admission negatives. No process, metrics, download or browser calls."""
import ast
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import package_web_release as q
import preflight_runtime_lock as pre
ROOT=Path(__file__).resolve().parent

class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=ROOT);self.root=Path(self.temp.name)
        self.bound=self.root/'bound';self.bound.write_text('bound')
        self.lock={'build':'build','game_tree':'tree','source_commit':'commit'}
        self.receipt=dict(self.lock,passed=True,post_run_binding_matches=True,input_sha256={str(self.bound):q.sha(self.bound)})
    def tearDown(self):self.temp.cleanup()
    def save(self,path,value):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value))
    def test_identity_positive_and_wrong_identity(self):
        q.identity(self.receipt,self.lock)
        for key,value in [('passed',False),('build','other'),('game_tree','other'),('source_commit','other'),('post_run_binding_matches',False),('error',{'reason':'bad'}),('input_sha256',{})]:
            row=copy.deepcopy(self.receipt);row[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):q.identity(row,self.lock)
    def test_input_source_drift(self):
        self.bound.write_text('changed')
        with self.assertRaises(ValueError):q.identity(self.receipt,self.lock)
    def test_duplicate_and_missing_report(self):
        path=self.root/'receipt.json';path.write_text('{"passed":true,"passed":true}')
        with self.assertRaises(ValueError):q.read(path)
        path.unlink()
        with self.assertRaises(RuntimeError):q.read(path)
    def test_monitor_actual_file_bindings(self):
        stage=self.root/'stage';stage.mkdir();(stage/'godot.log').write_text('actual log')
        result={'passed':True,'cleanup_complete':True,'test_dependencies':False,'unexpected_descendants':[], 'exit':0,'limits':q.b.LIMITS,'samples':[{'seconds':0}],'pid':123,'log_sha256':q.sha(stage/'godot.log')}
        self.save(stage/'receipt.json',result);q.monitor(stage,result,120)
        for key,value in [('passed',False),('cleanup_complete',False),('test_dependencies',True),('unexpected_descendants',[123]),('exit',True),('limits',dict(q.b.LIMITS,timeout_seconds=300)),('samples',[]),('pid',None),('error',{'reason':'bad'})]:
            row=copy.deepcopy(result);row[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):q.monitor(stage,row,120)
        (stage/'godot.log').write_text('drift')
        with self.assertRaises(ValueError):q.monitor(stage,result,120)
    def test_monitor_receipt_substitution(self):
        stage=self.root;result={'passed':True,'cleanup_complete':True,'test_dependencies':False,'unexpected_descendants':[],'exit':0,'limits':q.b.LIMITS,'samples':[{}],'pid':1}
        self.save(stage/'receipt.json',dict(result,pid=2))
        with self.assertRaises(ValueError):q.monitor(stage,result,120)
    def test_missing_duplicate_reordered_suite_receipts(self):
        lock=dict(self.lock,building_reviewed_for_execution=True,project_files=json.loads((ROOT/'frozen-project-files.json').read_text()),build=q.b.BUILD,game_tree=q.b.GAME_TREE)
        row=dict(self.receipt,build=lock['build'],game_tree=lock['game_tree'])
        for names in [[],list(q.b.SUITES[:-1]),list(q.b.SUITES)+[q.b.SUITES[0]],list(reversed(q.b.SUITES))]:
            self.save(self.root/'building-contracts/building-contracts-receipt.json',dict(row,suites=[{'suite':n} for n in names]))
            with self.assertRaises(ValueError):q.validate_suites(self.root,lock)
    def test_export_success_cannot_replace_suites(self):
        lock=dict(self.lock,building_reviewed_for_execution=True,project_files=json.loads((ROOT/'frozen-project-files.json').read_text()),build=q.b.BUILD,game_tree=q.b.GAME_TREE)
        self.save(self.root/'exports/web-export-receipt.json',dict(self.receipt,passed=True))
        with self.assertRaises(RuntimeError):q.validate_suites(self.root,lock)
    def test_side_identity_rejected_before_source_access(self):
        self.save(self.root/'export-lock.json',{'build':'wrong','game_tree':'wrong','source_commit':'wrong'})
        for side in ('product','diagnostic'):
            with self.assertRaises(ValueError):q.package(self.root,side)
    def test_pending_source_rejected(self):
        self.save(self.root/'export-lock.json',{})
        with patch.object(pre.prep,'SOURCE','PENDING_REVIEWED_SOURCE_COMMIT'):
            with self.assertRaisesRegex(ValueError,'Pending'):pre.check(self.root,'product')
    def test_canonical_export_monitor_shape(self):
        stage=self.root;(stage/'godot.log').write_text('export log')
        stored={'passed':True,'cleanup_complete':True,'test_dependencies':False,'unexpected_descendants':[], 'exit':0,'limits':dict(q.b.LIMITS,timeout_seconds=300),'samples':[{}],'pid':123,'export_completed':True,'log_sha256':q.sha(stage/'godot.log')}
        self.save(stage/'receipt.json',stored)
        row=dict(stored,output_sha256={'index.html':'0'*64})
        q.monitor(stage,row,300)
        for mutation in ('extra','changed','missing'):
            bad=copy.deepcopy(row)
            if mutation=='extra':bad['invented']=True
            elif mutation=='changed':bad['pid']=124
            else:del bad['export_completed']
            with self.assertRaises(ValueError):q.monitor(stage,bad,300)
    def test_all_seventeen_real_report_schemas(self):
        import test_contracts as tc
        import test_military as tm
        import test_faction as tf
        import test_building_contracts as tb
        lock=dict(self.lock,building_reviewed_for_execution=True,project_files=json.loads((ROOT/'frozen-project-files.json').read_text()),build=q.b.BUILD,game_tree=q.b.GAME_TREE)
        base=dict(self.receipt,build=lock['build'],game_tree=lock['game_tree'])
        def mon(stage):
            result={'passed':True,'cleanup_complete':True,'test_dependencies':False,'unexpected_descendants':[], 'exit':0,'limits':q.b.LIMITS,'samples':[{}],'pid':123,'logic_completed':True,'log_sha256':q.sha(stage/'godot.log')}
            self.save(stage/'receipt.json',result);return result
        for group,filename,suites,example,validator in [('building-contracts','building-contracts-receipt.json',q.b.SUITES,tb.report,q.b),('construction-contracts','construction-contracts-receipt.json',q.RELEASE,tc.example,tc.v),('military-contracts','military-contracts-receipt.json',q.MILITARY,tm.example,tm.v)]:
            rows=[]
            for suite in suites:
                stage=self.root/group/suite;stage.mkdir(parents=True)
                raw=example(suite);line=json.dumps(raw);extra=None
                if validator is q.b:
                    if suite=='construction_visual':extra=q.b.REPORT;line='CONSTRUCTION_VISUAL_CONTRACT passed=203 failed=0'
                    elif suite=='map80_sparse_memory':line='MAP80_SPARSE_MEMORY '+line
                elif validator is tc.v:
                    if suite==tc.v.FILE_SUITE:extra=tc.v.FILE_REPORT;line='File report complete'
                    elif suite in tc.v.PREFIXES:line=tc.v.PREFIXES[suite]+' '+line
                else:line=tm.v.PREFIXES[suite]+line
                (stage/'godot.log').write_text(line+'\n')
                if extra:self.save(stage/extra,raw)
                if validator is q.b:parsed=q.b.read_report(stage,suite);count=q.b.COUNTS[suite]
                elif validator is tc.v:
                    parsed=tc.v.read_file_report(stage,suite,lock,tc.C) if extra else tc.v.read_log(stage/'godot.log',suite,lock,tc.C)
                    count=len(parsed if type(parsed) is list else parsed['checks'])
                else:parsed=tm.v.read_log(stage/'godot.log',suite,lock,tm.C);count=len(parsed['checks'])
                result=mon(stage);row={'suite':suite,'monitor':result,'report':parsed,'assertions_executed':count,'receipt_sha256':q.sha(stage/'receipt.json'),'log_sha256':q.sha(stage/'godot.log')}
                if extra:row['report_sha256']=q.sha(stage/extra)
                rows.append(row)
            self.save(self.root/group/filename,dict(base,suites=rows,assertions_executed=sum(row['assertions_executed'] for row in rows)))
        import validate_latest_contracts as latest
        latest_rows=[]
        for suite in latest.SUITES:
            stage=self.root/'latest-contracts'/suite;stage.mkdir(parents=True)
            raw={'suite':suite,'build':lock['build'],'failed':0,'checks':[{'name':n,'passed':True} for n in latest.TRAINING_NAMES]}
            line='FOG_MATERIAL_CONTRACT checks=13 failures=0' if suite=='material_contract' else json.dumps(raw)
            if suite=='resource_visual_contract':line='\n'.join('RESOURCE_METRIC '+k+' vertices='+str(n)+' surfaces=1 bounds=(synthetic schema fixture)' for k,n in [('stone',945),('iron',1365),('berry',3174)])+'\nRESOURCE_CONTRACT_PASS 27'
            if suite in latest.INPUT_CONTRACTS:line=latest.INPUT_CONTRACTS[suite]['prefix']+' '+json.dumps([{'name':n,'passed':True} for n in latest.INPUT_CONTRACTS[suite]['names']])
            (stage/'godot.log').write_text(line+'\n');result=mon(stage)
            latest_rows.append({'suite':suite,'monitor':result,'report':latest.read_report(stage,suite),'assertions_executed':latest.COUNTS[suite],'receipt_sha256':q.sha(stage/'receipt.json'),'log_sha256':q.sha(stage/'godot.log')})
        self.save(self.root/'latest-contracts/latest-contracts-receipt.json',dict(base,suites=latest_rows,assertions_executed=79))
        stage=self.root/'faction-contracts/faction-publication';stage.mkdir(parents=True)
        raw=tf.report();raw['build']=lock['build'];self.save(stage/tf.a.REPORT,raw);(stage/'godot.log').write_text('Faction report complete')
        result=mon(stage)
        self.save(stage.parent/'faction-publication-receipt.json',dict(base,monitor=result,monitor_receipt_sha256=q.sha(stage/'receipt.json'),log_sha256=q.sha(stage/'godot.log'),report_sha256=q.sha(stage/tf.a.REPORT),validation=tf.v.validate(raw,lock['build'])))
        q.validate_suites(self.root,lock)
        # A successful aggregate with a later changed actual report is rejected.
        (self.root/'building-contracts/advanced_building_visuals/godot.log').write_text('{}')
        with self.assertRaises(ValueError):q.validate_suites(self.root,lock)
    def test_notice_inventory_is_narrow(self):
        self.assertEqual(len(q.NOTICES),11);self.assertEqual(len(set(q.NOTICES)),11)
        self.assertEqual(q.NOTICES[-1],'art/advanced_buildings/upstream/QUATERNIUS-LICENSE.txt')
    def test_workflow_scope_and_order(self):
        text=(ROOT.parent/'.github/workflows/building-runtime.yml').read_text()
        tokens=['sha256sum --strict --check ci/SUPPORT_SHA256SUMS','python3 -B ci/prepare_web_release.py prepare --side product','ci/run_building_contracts.py','ci/run_contracts.py','ci/run_military.py','ci/run_faction.py','ci/run_export.py','ci/package_web_release.py --side product']
        positions=[text.index(t) for t in tokens];self.assertEqual(positions,sorted(positions))
        self.assertIn('fetch-depth: 2',text);self.assertIn('timeout-minutes: 90',text)
        self.assertNotIn('continue-on-error',text);self.assertNotIn('contents: write',text);self.assertNotIn('/private/',text.split('path: |')[-1]);self.assertNotIn('**',text)
    def test_python_grammar_only(self):
        for name in ('package_web_release.py','preflight_runtime_lock.py','test_runtime_package.py'):ast.parse((ROOT/name).read_text())

if __name__=='__main__':unittest.main(verbosity=2)
