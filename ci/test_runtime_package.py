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
            if suite=='resource_visual_contract':line='Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org\n\nRESOURCE_METRIC stone vertices=732 surfaces=1 bounds=[P: (-0.489852, 0.0, -0.398318), S: (0.979703, 0.610226, 0.796637)]\nRESOURCE_METRIC iron vertices=930 surfaces=1 bounds=[P: (-0.489852, 0.0, -0.398318), S: (0.979703, 0.669126, 0.796637)]\nRESOURCE_METRIC berry vertices=1800 surfaces=2 bounds=[P: (-0.460012, 0.0, -0.472095), S: (0.920025, 0.76, 0.944191)]\nRESOURCE_CONTRACT_PASS 27\n'
            if suite=='resource_polish_contract':line='RESOURCE_POLISH_PASS 24'
            if suite=='normal_probe':line='NORMALS_PASS 3'
            if suite=='skirmish_policy_contract':line='SKIRMISH 17/17'
            if suite in latest.ARMY_CONTRACTS:line=json.dumps({'suite':latest.ARMY_CONTRACTS[suite]['suite'],'checks':[{'name':n,latest.ARMY_CONTRACTS[suite].get('check_field','passed'):True} for n in latest.ARMY_CONTRACTS[suite]['names']],'failed':0})
            if 'identity' in latest.ARMY_CONTRACTS.get(suite,{}):d=json.loads(line);d.update(latest.ARMY_CONTRACTS[suite]['identity']);line=json.dumps(d)
            if 'scope' in latest.ARMY_CONTRACTS.get(suite,{}):d=json.loads(line);d['scope']=latest.ARMY_CONTRACTS[suite]['scope'];line=json.dumps(d)
            if suite=='wall_line_contract':
                d=json.loads(line)
                d['geometry']=json.loads(json.dumps(latest.WALL_LINE_GEOMETRY)) # parser fixture, not gameplay proof
                line=json.dumps(d)
            if suite=='army_formation_integration':d=json.loads(line);d['scope']='Controlled actual game handlers; not natural battle or rendered acceptance';line=json.dumps(d)
            if suite=='touch_camera_continuity_contract':line=latest.CONTINUITY_SPEC['prefix']+' '+json.dumps({'checks':[{'name':n,'passed':True} for n in latest.CONTINUITY_SPEC['names']],'failure_count':0,'scope':latest.CONTINUITY_SPEC['scope']})
            if suite in latest.INPUT_CONTRACTS:line=latest.INPUT_CONTRACTS[suite]['prefix']+' '+json.dumps([{'name':n,'passed':True} for n in latest.INPUT_CONTRACTS[suite]['names']])
            (stage/'godot.log').write_text(line+'\n');result=mon(stage)
            latest_rows.append({'suite':suite,'monitor':result,'report':latest.read_report(stage,suite),'assertions_executed':latest.COUNTS[suite],'receipt_sha256':q.sha(stage/'receipt.json'),'log_sha256':q.sha(stage/'godot.log')})
        self.save(self.root/'latest-contracts/latest-contracts-receipt.json',dict(base,suites=latest_rows,assertions_executed=sum(latest.COUNTS.values())))
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
    def test_notice_side_specific_inventory(self):
        diagnostic=q.notices_for_side('diagnostic');product=q.notices_for_side('product')
        self.assertEqual(diagnostic,q.NOTICES)
        self.assertEqual(product,diagnostic+['art/resource_donors/License_Standard.txt','assets/diagnostic/bush_common/License_Standard.txt'])
        self.assertEqual(len(product),13);self.assertEqual(len(set(product)),13)
        product.pop();self.assertEqual(len(q.notices_for_side('product')),13)
        with self.assertRaises(ValueError):q.notices_for_side('unknown')
    def test_notice_original_bytes_required_product_only(self):
        project=self.root/'project';bound={}
        for name in q.notices_for_side('diagnostic'):
            path=project/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(name.encode());bound[name]=q.sha(path)
        q.validate_notice_files(project,bound,q.notices_for_side('diagnostic'))
        with self.assertRaises(RuntimeError):q.validate_notice_files(project,bound,q.notices_for_side('product'))
        path=project/q.RESOURCE_NOTICE;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'original CC0 donor notice');bound[q.RESOURCE_NOTICE]=q.sha(path)
        with self.assertRaises(RuntimeError):q.validate_notice_files(project,bound,q.notices_for_side('product'))
        berry=project/q.BERRY_NOTICE;berry.parent.mkdir(parents=True,exist_ok=True);berry.write_bytes(b'original berry CC0 notice');bound[q.BERRY_NOTICE]=q.sha(berry)
        q.validate_notice_files(project,bound,q.notices_for_side('product'))
        berry.write_bytes(b'wrong berry notice')
        with self.assertRaises(ValueError):q.validate_notice_files(project,bound,q.notices_for_side('product'))
        berry.write_bytes(b'original berry CC0 notice')
        path.write_bytes(b'changed')
        with self.assertRaises(ValueError):q.validate_notice_files(project,bound,q.notices_for_side('product'))
        path.unlink();path.symlink_to(self.bound)
        with self.assertRaises(RuntimeError):q.validate_notice_files(project,bound,q.notices_for_side('product'))
        q.validate_notice_files(project,bound,q.notices_for_side('diagnostic'))
    def test_workflow_scope_and_order(self):
        text=(ROOT.parent/'.github/workflows/building-runtime.yml').read_text()
        tokens=['sha256sum --strict --check ci/SUPPORT_SHA256SUMS','python3 -B ci/prepare_web_release.py prepare --side product','ci/run_building_contracts.py','ci/run_contracts.py','ci/run_military.py','ci/run_faction.py','ci/run_export.py','ci/package_web_release.py --side product']
        positions=[text.index(t) for t in tokens];self.assertEqual(positions,sorted(positions))
        self.assertIn('fetch-depth: 2',text);self.assertIn('timeout-minutes: 90',text)
        self.assertNotIn('continue-on-error',text);self.assertNotIn('contents: write',text);self.assertNotIn('/private/',text.split('path: |')[-1]);self.assertNotIn('**',text)
    def test_python_grammar_only(self):
        for name in ('package_web_release.py','preflight_runtime_lock.py','test_runtime_package.py'):ast.parse((ROOT/name).read_text())

class CurrentObjectiveMenuContractTests(unittest.TestCase):
    """Exact captured 30-row native report; mutants are synthetic negatives."""
    def test_current_report_and_each_row_is_mandatory(self):
        import copy
        import validate_latest_contracts as validator
        report = {'checks': [{'name': 'fourth option selects control mode', 'passed': True}, {'name': 'setup explains goal and public information', 'passed': True}, {'name': 'setup action fits (390, 844) ChooseBattleButton', 'passed': True}, {'name': 'setup action fits (390, 844) LaunchMatchButton', 'passed': True}, {'name': 'setup action fits (390, 844) BackButton', 'passed': True}, {'name': 'setup action fits (320, 568) ChooseBattleButton', 'passed': True}, {'name': 'setup action fits (320, 568) LaunchMatchButton', 'passed': True}, {'name': 'setup action fits (320, 568) BackButton', 'passed': True}, {'name': 'setup action fits (568, 320) ChooseBattleButton', 'passed': True}, {'name': 'setup action fits (568, 320) LaunchMatchButton', 'passed': True}, {'name': 'setup action fits (568, 320) BackButton', 'passed': True}, {'name': 'setup action fits (1280, 800) ChooseBattleButton', 'passed': True}, {'name': 'setup action fits (1280, 800) LaunchMatchButton', 'passed': True}, {'name': 'setup action fits (1280, 800) BackButton', 'passed': True}, {'name': 'actual menu launches objective match', 'passed': True}, {'name': 'objective HUD fits (390, 844)', 'passed': True}, {'name': 'objective HUD does not overlap lower panel (390, 844)', 'passed': True}, {'name': 'objective HUD fits (320, 568)', 'passed': True}, {'name': 'objective HUD does not overlap lower panel (320, 568)', 'passed': True}, {'name': 'objective HUD fits (568, 320)', 'passed': True}, {'name': 'objective HUD does not overlap lower panel (568, 320)', 'passed': True}, {'name': 'objective HUD fits (1280, 800)', 'passed': True}, {'name': 'objective HUD does not overlap lower panel (1280, 800)', 'passed': True}, {'name': 'score button focuses known central landmark only', 'passed': True}, {'name': 'restart preserves mode but resets score', 'passed': True}, {'name': 'fifth option selects supply mode', 'passed': True}, {'name': 'sixth option selects quick battle', 'passed': True}, {'name': 'seventh option selects fortress battle', 'passed': True}, {'name': 'eighth option selects staged defense', 'passed': True}, {'name': 'ninth option selects frontier expedition', 'passed': True}, {'name': 'direct selection returns to ordinary practice', 'passed': True}], 'failed': 0, 'scope': 'native controls, viewport geometry and real menu transitions; no rendered or physical-device acceptance', 'suite': 'control_point_menu_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(value):
                (stage/'godot.log').write_text(json.dumps(value)+'\n')
                return validator.read_report(stage,'control_point_menu_contract')
            self.assertEqual(validator.COUNTS['control_point_menu_contract'],31)
            self.assertEqual(validator.ARMY_CONTRACTS['control_point_menu_contract']['names'],[r['name'] for r in report['checks']])
            self.assertEqual(read(report),report)
            for i in range(31):
                for mutation in ('missing','false','renamed','duplicate'):
                    with self.subTest(row=i,mutation=mutation):
                        bad=copy.deepcopy(report)
                        if mutation=='missing':bad['checks'].pop(i)
                        elif mutation=='false':bad['checks'][i]['passed']=False
                        elif mutation=='renamed':bad['checks'][i]['name']='unrecognized assertion'
                        else:bad['checks'][i]['name']=bad['checks'][(i+1)%31]['name']
                        with self.assertRaises(ValueError):read(bad)
            bad=copy.deepcopy(report);bad['checks'][25],bad['checks'][26]=bad['checks'][26],bad['checks'][25]
            with self.assertRaises(ValueError):read(bad)
            bad=copy.deepcopy(report);bad['checks'].append(copy.deepcopy(bad['checks'][-1]))
            with self.assertRaises(ValueError):read(bad)


class DifficultyFailureCountSchemaTests(unittest.TestCase):
    """Synthetic admission negatives, not substitute gameplay evidence."""
    def test_difficulty_suites_require_integer_zero_failed(self):
        import validate_latest_contracts as validator
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            for suite,count in (('ai_difficulty_contract',26),('difficulty_menu_contract',15)):
                spec=validator.ARMY_CONTRACTS[suite]
                self.assertEqual(validator.COUNTS[suite],count)
                report={'suite':spec['suite'],'checks':[{'name':name,'passed':True} for name in spec['names']],'failed':0,'scope':spec['scope']}
                report.update(spec.get('identity',{}))
                def read(value):
                    (stage/'godot.log').write_text(json.dumps(value)+'\n')
                    return validator.read_report(stage,suite)
                self.assertEqual(read(report),report)
                for failed in (False,True,0.0,1.0,'0',None,[],{}):
                    with self.subTest(suite=suite,failed=repr(failed)):
                        bad=copy.deepcopy(report);bad['failed']=failed
                        with self.assertRaises(ValueError):read(bad)


class FriendlyPickReportSchemaTests(unittest.TestCase):
    """Frozen native 38-row report, not generated from validator expectations."""
    def test_exact_frozen_report_and_fail_closed_mutations(self):
        import copy
        import validate_latest_contracts as validator
        report = {'checks': [{'name': 'world projection usable (390, 844) z15.0', 'passed': True}, {'name': 'routed closer worker selected (390, 844) z15.0', 'passed': True}, {'name': 'routed building center retains priority (390, 844) z15.0', 'passed': True}, {'name': 'world projection usable (390, 844) z30.0', 'passed': True}, {'name': 'routed closer worker selected (390, 844) z30.0', 'passed': True}, {'name': 'routed building center retains priority (390, 844) z30.0', 'passed': True}, {'name': 'world projection usable (390, 844) z46.0', 'passed': True}, {'name': 'routed closer worker selected (390, 844) z46.0', 'passed': True}, {'name': 'routed building center retains priority (390, 844) z46.0', 'passed': True}, {'name': 'world projection usable (844, 390) z15.0', 'passed': True}, {'name': 'routed closer worker selected (844, 390) z15.0', 'passed': True}, {'name': 'routed building center retains priority (844, 390) z15.0', 'passed': True}, {'name': 'world projection usable (844, 390) z30.0', 'passed': True}, {'name': 'routed closer worker selected (844, 390) z30.0', 'passed': True}, {'name': 'routed building center retains priority (844, 390) z30.0', 'passed': True}, {'name': 'world projection usable (844, 390) z46.0', 'passed': True}, {'name': 'routed closer worker selected (844, 390) z46.0', 'passed': True}, {'name': 'routed building center retains priority (844, 390) z46.0', 'passed': True}, {'name': 'world projection usable (320, 568) z15.0', 'passed': True}, {'name': 'routed closer worker selected (320, 568) z15.0', 'passed': True}, {'name': 'routed building center retains priority (320, 568) z15.0', 'passed': True}, {'name': 'world projection usable (320, 568) z30.0', 'passed': True}, {'name': 'routed closer worker selected (320, 568) z30.0', 'passed': True}, {'name': 'routed building center retains priority (320, 568) z30.0', 'passed': True}, {'name': 'world projection usable (320, 568) z46.0', 'passed': True}, {'name': 'routed closer worker selected (320, 568) z46.0', 'passed': True}, {'name': 'routed building center retains priority (320, 568) z46.0', 'passed': True}, {'name': 'identical unit centers resolve stable lower id', 'passed': True}, {'name': 'remembered and dead unit observations cannot steal selection', 'passed': True}, {'name': 'absent units never queried through authority for selection', 'passed': True}, {'name': 'unseen actual enemy has no pick record', 'passed': True}, {'name': 'farm precondition legacy winner with closer worker', 'passed': True}, {'name': 'selected villager farm tap remains gather command', 'passed': True}, {'name': 'paused farm tap selects nearer worker without gather', 'passed': True}, {'name': 'unfinished farm tap selects nearer worker without gather', 'passed': True}, {'name': 'selected army tapping friendly building center selects without order', 'passed': True}, {'name': 'visible enemy winner remains command-target eligible', 'passed': True}, {'name': 'visible resource mesh winner is not overridden', 'passed': True}], 'failed': 0, 'scope': 'Actual viewport touch routing and camera at three sizes/zooms; controlled positions and explicit observation-filter fixtures; not physical phone or natural combat.', 'suite': 'friendly_pick_routed_contract'}
        suite = 'friendly_pick_routed_contract'
        with tempfile.TemporaryDirectory() as td:
            stage = Path(td)
            def read_raw(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,suite)
            self.assertEqual(read_raw(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                bad=copy.deepcopy(report);bad[key]=value;mutants.append(json.dumps(bad))
            for i in range(38):
                for value in (False,1):
                    bad=copy.deepcopy(report);bad['checks'][i]['passed']=value;mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);bad['checks'].pop(i);mutants.append(json.dumps(bad))
            bad=copy.deepcopy(report);bad['checks'].reverse();mutants.append(json.dumps(bad))
            bad=copy.deepcopy(report);bad['checks'].append(bad['checks'][0]);mutants.append(json.dumps(bad))
            bad=copy.deepcopy(report);bad['extra']=True;mutants.append(json.dumps(bad))
            bad=copy.deepcopy(report);del bad['scope'];mutants.append(json.dumps(bad))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            for index,raw in enumerate(mutants):
                with self.subTest(mutation=index):
                    with self.assertRaises(ValueError):read_raw(raw)

class SiegeServiceReportSchemaTests(unittest.TestCase):
    """Frozen official 23/6/9 reports; negative fixtures never count as gameplay proof."""
    def test_three_exact_reports_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        reports = [{'checks': [{'name': 'controlled siege positions are statically legal', 'passed': True}, {'name': 'two damaged stationary siege get distinct workers', 'passed': True}, {'name': 'policy leaves observed data intact', 'passed': True}, {'name': 'menu names siege maintenance', 'passed': True}, {'name': 'pending orders prevent duplicate dispatch', 'passed': True}, {'name': 'moving and pending siege excluded', 'passed': True}, {'name': 'recently hit and enemy siege excluded', 'passed': True}, {'name': 'remembered and living troop targets excluded', 'passed': True}, {'name': 'existing gather workers are not commandeered', 'passed': True}, {'name': 'observed enemy prevents dangerous fleet dispatch', 'passed': True}, {'name': 'batch only queues ordinary guarded commands', 'passed': True}, {'name': 'click gives no instant health or payment', 'passed': True}, {'name': 'both siege fully repaired by ordinary game ticks', 'passed': True}, {'name': 'exact four wood pays twenty health', 'passed': True}, {'name': 'workers physically travelled to targets', 'passed': True}, {'name': 'completed workers stop without repeat charge', 'passed': True}, {'name': 'healthy fleet causes no continuing expense', 'passed': True}, {'name': 'siege moving before execution preserves worker epoch', 'passed': True}, {'name': 'stationary target accepts fresh batch', 'passed': True}, {'name': 'target movement cancels active repair without extra heal', 'passed': True}, {'name': 'controlled zero wood setup debits ledger', 'passed': True}, {'name': 'no wood disables batch and cannot heal for free', 'passed': True}, {'name': 'repair ledger conserves resources', 'passed': True}], 'failed': 0, 'scope': 'Controlled two-siege fixture; existing menu callback, normal travel and paid tick repair, no physical-phone claim.', 'suite': 'batch_siege_repair_contract'}, {'checks': [{'name': 'controlled full-health mechanical force starts legal', 'passed': True}, {'name': 'ordinary enemy attacks damage both siege', 'passed': True}, {'name': 'active visible enemy blocks batch service', 'passed': True}, {'name': 'after enemy departure fleet offers two repairs', 'passed': True}, {'name': 'battle damaged fleet restored through ordinary paid work', 'passed': True}, {'name': 'repair expenses reconcile without resource grants', 'passed': True}], 'failed': 0, 'scope': 'Controlled unit-spawn encounter with economic AI disabled; all HP damage, retreat, travel and repairs use ordinary commands/ticks, no HP/resource grants or forced deaths.', 'suite': 'siege_service_journey'}, {'checks': [{'name': 'original fortress two siege and enemy archer', 'passed': True}, {'name': 'ordinary attacks damage both central siege', 'passed': True}, {'name': 'existing economy action dispatches two repair workers', 'passed': True}, {'name': 'both central workers retain their accepted contact slot', 'passed': True}, {'name': 'central repairs finish without exhausted route retries', 'passed': True}, {'name': 'central full repair debits exact ordinary wood', 'passed': True}, {'name': 'enemy alive and ledger conservation retained', 'passed': True}, {'name': 'non-perimeter request cannot anchor repair', 'passed': True}, {'name': 'stale work epoch uses ordinary legal slot selection', 'passed': True}], 'failed': 0, 'scope': 'Controlled original fortress units and ordinary orders, attacks, traffic and paid repair. AI scheduling disabled; no spawns, teleports, HP/resource/fog edits. Copied-record stale-request checks. Not natural full-match or physical-phone validation.', 'suite': 'repair_contact_route_contract'}]
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            for report in reports:
                suite=report['suite']
                def read(raw):
                    (stage/'godot.log').write_text(raw+'\n')
                    return validator.read_report(stage,suite)
                self.assertEqual(read(json.dumps(report)),report)
                mutants=[]
                for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                    bad=copy.deepcopy(report);bad[key]=value;mutants.append(json.dumps(bad))
                for i in range(len(report['checks'])):
                    for value in (False,1):
                        bad=copy.deepcopy(report);bad['checks'][i]['passed']=value;mutants.append(json.dumps(bad))
                    bad=copy.deepcopy(report);bad['checks'].pop(i);mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);bad['checks'].reverse();mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);bad['checks'].append(bad['checks'][0]);mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);bad['extra']=True;mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);del bad['scope'];mutants.append(json.dumps(bad))
                raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
                for i,raw in enumerate(mutants):
                    with self.subTest(suite=suite,mutation=i):
                        with self.assertRaises(ValueError):read(raw)

class BattleNavigationReportSchemaTests(unittest.TestCase):
    """Frozen official 14-row report; negative fixtures never count as gameplay proof."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        reports = [{'checks': [{'name': 'first ordinary settled hit creates own-location alert', 'passed': True}, {'name': 'two separated ordinary own hits expose two frozen alert positions', 'passed': True}, {'name': 'direct battle action reachable (320, 568)', 'passed': True}, {'name': 'HUD retains world gap (320, 568)', 'passed': True}, {'name': 'direct battle action reachable (844, 390)', 'passed': True}, {'name': 'HUD retains world gap (844, 390)', 'passed': True}, {'name': 'direct battle action reachable (390, 844)', 'passed': True}, {'name': 'HUD retains world gap (390, 844)', 'passed': True}, {'name': 'one routed tap focuses first alert without opening menu', 'passed': True}, {'name': 'navigation leaves selected orders and visibility unchanged', 'passed': True}, {'name': 'expired held tap does not jump to stale alert', 'passed': True}, {'name': 'pause disables jump and preserves simulation expiry', 'passed': True}, {'name': 'acknowledged alert absent from minimap presentation snapshot', 'passed': True}, {'name': 'continuing acknowledged combat does not spam again', 'passed': True}], 'failed': 0, 'scope': 'Controlled combat setup with real damage settlement and viewport-routed touch, three simulated sizes; not physical phone or natural whole match.', 'suite': 'battle_navigation_contract'}]
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            for report in reports:
                suite=report['suite']
                def read(raw):
                    (stage/'godot.log').write_text(raw+'\n')
                    return validator.read_report(stage,suite)
                self.assertEqual(read(json.dumps(report)),report)
                mutants=[]
                for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                    bad=copy.deepcopy(report);bad[key]=value;mutants.append(json.dumps(bad))
                for i in range(len(report['checks'])):
                    for value in (False,1):
                        bad=copy.deepcopy(report);bad['checks'][i]['passed']=value;mutants.append(json.dumps(bad))
                    bad=copy.deepcopy(report);bad['checks'].pop(i);mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);bad['checks'].reverse();mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);bad['checks'].append(bad['checks'][0]);mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);bad['extra']=True;mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);del bad['scope'];mutants.append(json.dumps(bad))
                raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
                for i,raw in enumerate(mutants):
                    with self.subTest(suite=suite,mutation=i):
                        with self.assertRaises(ValueError):read(raw)


class ProductionWaitReportSchemaTests(unittest.TestCase):
    """Frozen official 37-row report; negative fixtures never count as gameplay proof."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        reports = [{'checks': [{'name': 'completed unit front is waiting not busy', 'passed': True}, {'name': 'waiting excludes { "owned": false }', 'passed': True}, {'name': 'waiting excludes { "alive": false }', 'passed': True}, {'name': 'waiting excludes { "remembered": true }', 'passed': True}, {'name': 'waiting excludes { "team": 1 }', 'passed': True}, {'name': 'waiting excludes { "built": false }', 'passed': True}, {'name': 'non-ready unit order excluded { "kind": "age2", "remaining_ticks": 0, "research": true }', 'passed': True}, {'name': 'non-ready unit order excluded { "kind": "spearman", "remaining_ticks": 1 }', 'passed': True}, {'name': 'non-ready unit order excluded { "kind": "spearman", "remaining_ticks": 0, "trade": true }', 'passed': True}, {'name': 'paid training accepted with available capacity', 'passed': True}, {'name': 'actual training finishes but occupied exit blocks birth', 'passed': True}, {'name': 'global overview separates ready from producing', 'passed': True}, {'name': 'locator binds actual stalled producer', 'passed': True}, {'name': 'waiting locator reachable (320, 568)', 'passed': True}, {'name': 'waiting locator reachable (844, 390)', 'passed': True}, {'name': 'waiting locator reachable (390, 844)', 'passed': True}, {'name': 'routed locator selects stalled producer and closes menu', 'passed': True}, {'name': 'locator preserves paid queue and shows actual exit cause', 'passed': True}, {'name': 'population-full boundary actually reached', 'passed': True}, {'name': 'full population explains wait and disables exit clearing', 'passed': True}, {'name': 'population wait remains discoverable without spending', 'passed': True}, {'name': 'small-unit exit geometry unchanged', 'passed': True}, {'name': 'large-unit exit geometry and order unchanged', 'passed': True}, {'name': 'ready producer offers clearing', 'passed': True}, {'name': 'bounded ordinary move plan', 'passed': True}, {'name': 'enemy occupying exit never receives move order', 'passed': True}, {'name': 'paused clear does not issue orders', 'passed': True}, {'name': 'pending unit order protected', 'passed': True}, {'name': 'only ordinary movement submitted', 'passed': True}, {'name': 'queue and payment unchanged by clearing request', 'passed': True}, {'name': 'repeated clear cannot duplicate pending units', 'passed': True}, {'name': 'native movement enables normal birth', 'passed': True}, {'name': 'no second payment or duplicate unit', 'passed': True}, {'name': 'clear action removed when queue completed', 'passed': True}, {'name': 'completed birth retires locator', 'passed': True}, {'name': 'retired queue cannot move former blocker', 'passed': True}, {'name': 'economy conserved', 'passed': True}], 'failed': 0, 'scope': 'Controlled housing/blockers; full paid train, viewport-routed waiting locator, ordinary exit movement and single birth. Pure observation exclusions. Not natural full match or physical phone acceptance', 'suite': 'production_wait_navigation_contract'}]
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            for report in reports:
                suite=report['suite']
                def read(raw):
                    (stage/'godot.log').write_text(raw+'\n')
                    return validator.read_report(stage,suite)
                self.assertEqual(read(json.dumps(report)),report)
                mutants=[]
                for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                    bad=copy.deepcopy(report);bad[key]=value;mutants.append(json.dumps(bad))
                for i in range(len(report['checks'])):
                    for value in (False,1):
                        bad=copy.deepcopy(report);bad['checks'][i]['passed']=value;mutants.append(json.dumps(bad))
                    bad=copy.deepcopy(report);bad['checks'].pop(i);mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);bad['checks'].reverse();mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);bad['checks'].append(bad['checks'][0]);mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);bad['extra']=True;mutants.append(json.dumps(bad))
                bad=copy.deepcopy(report);del bad['scope'];mutants.append(json.dumps(bad))
                raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
                for i,raw in enumerate(mutants):
                    with self.subTest(suite=suite,mutation=i):
                        with self.assertRaises(ValueError):read(raw)


class BuildingAttentionWaitingSchemaTests(unittest.TestCase):
    """CI-observed 28 checks retain all original 25, adding waiting-layout checks."""
    def test_frozen_report_and_waiting_assertions_required(self):
        import copy
        import validate_latest_contracts as validator
        report = {'checks': [{'name': 'unassigned sites sorted', 'passed': True}, {'name': 'only completed damaged buildings need repair', 'passed': True}, {'name': 'active builder protects assigned site', 'passed': True}, {'name': 'pending own order protects site', 'passed': True}, {'name': 'enemy order does not protect site', 'passed': True}, {'name': 'exclude { "owned": false }', 'passed': True}, {'name': 'exclude { "alive": false }', 'passed': True}, {'name': 'exclude { "remembered": true }', 'passed': True}, {'name': 'exclude { "team": 1 }', 'passed': True}, {'name': 'exclude { "category": "unit" }', 'passed': True}, {'name': 'native damaged base counted', 'passed': True}, {'name': 'native button locates building', 'passed': True}, {'name': 'existing repair action exposed', 'passed': True}, {'name': 'navigation does not repair spend or command', 'passed': True}, {'name': 'unfinished site opens existing resume control', 'passed': True}, {'name': 'stale pending site cannot select', 'passed': True}, {'name': 'pause disables navigation', 'passed': True}, {'name': 'hidden tab cannot navigate', 'passed': True}, {'name': 'fits 320 BuildingAttention_waiting', 'passed': True}, {'name': 'fits 320 BuildingAttention_unassigned', 'passed': True}, {'name': 'fits 320 BuildingAttention_damaged', 'passed': True}, {'name': 'fits 390 BuildingAttention_waiting', 'passed': True}, {'name': 'fits 390 BuildingAttention_unassigned', 'passed': True}, {'name': 'fits 390 BuildingAttention_damaged', 'passed': True}, {'name': 'fits 844 BuildingAttention_waiting', 'passed': True}, {'name': 'fits 844 BuildingAttention_unassigned', 'passed': True}, {'name': 'fits 844 BuildingAttention_damaged', 'passed': True}, {'name': 'economy conserved', 'passed': True}], 'failed': 0, 'scope': 'Controlled records and native selection/UI; not natural match or physical phone acceptance', 'suite': 'building_attention_contract'}
        added = ['fits 320 BuildingAttention_waiting', 'fits 390 BuildingAttention_waiting', 'fits 844 BuildingAttention_waiting']
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(d):
                (stage/'godot.log').write_text(json.dumps(d)+'\n')
                return validator.read_report(stage,'building_attention_contract')
            self.assertEqual(read(report),report)
            for name in added:
                i=next(i for i,c in enumerate(report['checks']) if c['name']==name)
                for kind in ('missing','false','nonbool','rename','extra','reorder'):
                    bad=copy.deepcopy(report)
                    if kind=='missing':bad['checks'].pop(i)
                    elif kind=='false':bad['checks'][i]['passed']=False
                    elif kind=='nonbool':bad['checks'][i]['passed']=1
                    elif kind=='rename':bad['checks'][i]['name']='wrong'
                    elif kind=='extra':bad['checks'].append(bad['checks'][i])
                    else:bad['checks'][i],bad['checks'][i+1]=bad['checks'][i+1],bad['checks'][i]
                    with self.subTest(name=name,kind=kind):
                        with self.assertRaises(ValueError):read(bad)

class UnitYawReportSchemaTests(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'controlled circular path is statically free', 'passed': True}, {'name': 'ordinary movement phase completes all circular steps', 'passed': True}, {'name': 'legacy unwrapped angle exceeds checkpoint limit', 'passed': True}, {'name': 'all new rotations remain finite canonical radians', 'passed': True}, {'name': 'every step preserves legacy facing direction', 'passed': True}, {'name': 'turning does not alter economy', 'passed': True}, {'name': 'turning does not alter health', 'passed': True}, {'name': 'turning does not emit commands', 'passed': True}, {'name': 'long-turn state passes unchanged strict checkpoint validation', 'passed': True}, {'name': 'long-turn checkpoint exact transport roundtrip', 'passed': True}, {'name': 'NaN rotation remains rejected', 'passed': True}, {'name': 'infinite rotation remains rejected', 'passed': True}, {'name': 'out-of-world position remains rejected', 'passed': True}, {'name': 'strict long-turn checkpoint restores', 'passed': True}, {'name': 'immediate restored full capture is exact', 'passed': True}, {'name': 'full 100-tick continuation is exact after restore', 'passed': True}, {'name': 'restored economy audit passes', 'passed': True}], 'failed': 0, 'scope': 'controlled movement-phase long-turn orientation and strict checkpoint continuation; not natural full-match or physical-phone acceptance', 'suite': 'unit_yaw_checkpoint_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class PreciseShortfallReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'fractional milli shortage rounds up one', 'passed': True}, {'name': 'workshop exact missing stone only', 'passed': True}, {'name': 'all deficits stable resource order', 'passed': True}, {'name': 'housing differs from hard limit', 'passed': True}, {'name': 'hard population limit explicit', 'passed': True}, {'name': 'building not blocked by population', 'passed': True}, {'name': 'queue technology and deficits all retained', 'passed': True}, {'name': 'exact payment boundary', 'passed': True}, {'name': 'bank remains unchanged', 'passed': True}], 'failed': 0, 'scope': 'Pure presentation rules, milli precision, population, queue, technology. No authority actions.', 'suite': 'production_shortfall_rules_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class PreciseShortfallReportSchemaTests1(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'build preview has explicit economy navigation', 'passed': True}, {'name': 'second finger cancels held economy navigation', 'passed': True}, {'name': 'canceled touch does not navigate', 'passed': True}, {'name': 'navigation opens existing economy page', 'passed': True}, {'name': 'navigation cancels armed preview explicitly', 'passed': True}, {'name': 'navigation preserves selection orders and bank', 'passed': True}, {'name': 'shortfall text reachable (320, 568)', 'passed': True}, {'name': 'shortfall text reachable (844, 390)', 'passed': True}, {'name': 'shortfall text reachable (390, 844)', 'passed': True}, {'name': 'recruit exact food shortage visible', 'passed': True}, {'name': 'stale selection cannot navigate', 'passed': True}, {'name': 'focus loss blocks navigation', 'passed': True}, {'name': 'empty automatic queue diagnoses exact next cost', 'passed': True}, {'name': 'changed repeat recipe invalidates held navigation', 'passed': True}, {'name': 'paid ready order keeps birth cause not shortage', 'passed': True}, {'name': 'unseen resource positions not exposed', 'passed': True}, {'name': 'inspection never pays or submits', 'passed': True}, {'name': 'economy audit conserved', 'passed': True}], 'failed': 0, 'scope': 'Controlled stock fixture; contextual shortage and navigation with cancellation and phone-size layout. Not physical phone or natural economy match.', 'suite': 'production_shortfall_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class WallWorkforceGeometrySchemaTests(unittest.TestCase):
    def test_actual_seven_controls_and_geometry_fail_closed(self):
        import copy
        import validate_latest_contracts as v
        report={'checks': [{'name': 'default single segment preserves helper construction', 'passed': True}, {'name': 'explicit row toggle gives two segments', 'passed': True}, {'name': 'row bounded by selected crew', 'passed': True}, {'name': 'row cycles back to single', 'passed': True}, {'name': 'ordinary visible three segment plot found', 'passed': True}, {'name': 'row preview shows three adjacent two metre footprints', 'passed': True}, {'name': 'HUD shows full ninety wood price', 'passed': True}, {'name': 'confirm queues one existing build per unique worker', 'passed': True}, {'name': 'no charge before authoritative execution', 'passed': True}, {'name': 'pending row remains existing valid checkpoint schema', 'passed': True}, {'name': 'duplicate confirmation cannot requeue', 'passed': True}, {'name': 'all three ordinary paid sites created', 'passed': True}, {'name': 'each worker has independent target', 'passed': True}, {'name': 'actual row success count displayed', 'passed': True}, {'name': 'paid row valid checkpoint', 'passed': True}, {'name': 'paid row restores through existing codec', 'passed': True}, {'name': 'all three workers finish their own ordinary ten-second walls', 'passed': True}, {'name': 'restored paid row follows identical continuation', 'passed': True}, {'name': 'all receipts fulfilled and economy conserved', 'passed': True}, {'name': 'cancel no sites no debit', 'passed': True}, {'name': 'total cost insufficient blocks whole preview', 'passed': True}, {'name': 'rotate retires held placement', 'passed': True}, {'name': 'rotated row is axis aligned', 'passed': True}, {'name': 'later row obstruction prevents confirmation', 'passed': True}, {'name': 'clear site includes later row blockers', 'passed': True}, {'name': 'blocked row does not queue any purchase', 'passed': True}, {'name': 'row clearance remains separate move only', 'passed': True}, {'name': 'dead worker rejects only own site without free work', 'passed': True}, {'name': 'partial result displays actual count and price', 'passed': True}, {'name': 'competing ordinary storehouse site available', 'passed': True}, {'name': 'same-tick prior spending cannot overdraw row', 'passed': True}, {'name': 'zero-success row reports no row payment', 'passed': True}, {'name': 'selection replacement cancels held row', 'passed': True}, {'name': 'single worker cannot enable multi row', 'passed': True}, {'name': 'paused row cannot command', 'passed': True}, {'name': 'camera gesture cannot confirm row', 'passed': True}, {'name': 'web touch cancel retires row', 'passed': True}, {'name': 'held confirmation cannot survive selected worker death', 'passed': True}, {'name': 'held confirmation cannot survive replacement selection', 'passed': True}, {'name': 'two finger gesture cancels held GUI confirm', 'passed': True}, {'name': 'real GUI touch release submits row exactly once', 'passed': True}, {'name': 'short HUD guidance includes quantity and total cost', 'passed': True}, {'name': 'four selected workers allow four segment plan', 'passed': True}, {'name': 'four segment upper bound cycles to single', 'passed': True}, {'name': 'late detached button event preserves newer same-index press', 'passed': True}, {'name': 'newer replacement button press still confirms exactly once', 'passed': True}, {'name': 'ledger audit remains conserved', 'passed': True}, {'name': 'layout (390, 844) actual viewport requested', 'passed': True}, {'name': 'layout (390, 844) top and bottom contained', 'passed': True}, {'name': 'layout (390, 844) HUD no overlap with battlefield gap', 'passed': True}, {'name': 'layout (390, 844) scroll reaches count', 'passed': True}, {'name': 'layout (390, 844) scroll issues no commands', 'passed': True}, {'name': 'layout (390, 844) touch count activates once', 'passed': True}, {'name': 'layout (390, 844) count still reachable', 'passed': True}, {'name': 'layout (390, 844) touch count reaches three', 'passed': True}, {'name': 'layout (390, 844) scroll reaches direction', 'passed': True}, {'name': 'layout (390, 844) touch direction activates once', 'passed': True}, {'name': 'layout (390, 844) UI touches no world build', 'passed': True}, {'name': 'layout (390, 844) visible legal row fixture found', 'passed': True}, {'name': 'layout (390, 844) scroll back reaches confirm', 'passed': True}, {'name': 'layout (390, 844) row plan HUD stays within viewport', 'passed': True}, {'name': 'layout (390, 844) row plan leaves battlefield gap', 'passed': True}, {'name': 'layout (390, 844) row action buttons do not overlap', 'passed': True}, {'name': 'layout (390, 844) touch confirm exactly three queued commands', 'passed': True}, {'name': 'layout (390, 844) confirm exits placement without changing selected workers', 'passed': True}, {'name': 'layout (390, 844) UI leaked no extra orders', 'passed': True}, {'name': 'layout (320, 568) actual viewport requested', 'passed': True}, {'name': 'layout (320, 568) top and bottom contained', 'passed': True}, {'name': 'layout (320, 568) HUD no overlap with battlefield gap', 'passed': True}, {'name': 'layout (320, 568) scroll reaches count', 'passed': True}, {'name': 'layout (320, 568) scroll issues no commands', 'passed': True}, {'name': 'layout (320, 568) touch count activates once', 'passed': True}, {'name': 'layout (320, 568) count still reachable', 'passed': True}, {'name': 'layout (320, 568) touch count reaches three', 'passed': True}, {'name': 'layout (320, 568) scroll reaches direction', 'passed': True}, {'name': 'layout (320, 568) touch direction activates once', 'passed': True}, {'name': 'layout (320, 568) UI touches no world build', 'passed': True}, {'name': 'layout (320, 568) visible legal row fixture found', 'passed': True}, {'name': 'layout (320, 568) scroll back reaches confirm', 'passed': True}, {'name': 'layout (320, 568) row plan HUD stays within viewport', 'passed': True}, {'name': 'layout (320, 568) row plan leaves battlefield gap', 'passed': True}, {'name': 'layout (320, 568) row action buttons do not overlap', 'passed': True}, {'name': 'layout (320, 568) touch confirm exactly three queued commands', 'passed': True}, {'name': 'layout (320, 568) confirm exits placement without changing selected workers', 'passed': True}, {'name': 'layout (320, 568) UI leaked no extra orders', 'passed': True}, {'name': 'layout (568, 320) actual viewport requested', 'passed': True}, {'name': 'layout (568, 320) top and bottom contained', 'passed': True}, {'name': 'layout (568, 320) HUD no overlap with battlefield gap', 'passed': True}, {'name': 'layout (568, 320) scroll reaches count', 'passed': True}, {'name': 'layout (568, 320) scroll issues no commands', 'passed': True}, {'name': 'layout (568, 320) touch count activates once', 'passed': True}, {'name': 'layout (568, 320) count still reachable', 'passed': True}, {'name': 'layout (568, 320) touch count reaches three', 'passed': True}, {'name': 'layout (568, 320) scroll reaches direction', 'passed': True}, {'name': 'layout (568, 320) touch direction activates once', 'passed': True}, {'name': 'layout (568, 320) UI touches no world build', 'passed': True}, {'name': 'layout (568, 320) visible legal row fixture found', 'passed': True}, {'name': 'layout (568, 320) scroll back reaches confirm', 'passed': True}, {'name': 'layout (568, 320) row plan HUD stays within viewport', 'passed': True}, {'name': 'layout (568, 320) row plan leaves battlefield gap', 'passed': True}, {'name': 'layout (568, 320) row action buttons do not overlap', 'passed': True}, {'name': 'layout (568, 320) touch confirm exactly three queued commands', 'passed': True}, {'name': 'layout (568, 320) confirm exits placement without changing selected workers', 'passed': True}, {'name': 'layout (568, 320) UI leaked no extra orders', 'passed': True}, {'name': 'layout (1280, 800) actual viewport requested', 'passed': True}, {'name': 'layout (1280, 800) top and bottom contained', 'passed': True}, {'name': 'layout (1280, 800) HUD no overlap with battlefield gap', 'passed': True}, {'name': 'layout (1280, 800) scroll reaches count', 'passed': True}, {'name': 'layout (1280, 800) scroll issues no commands', 'passed': True}, {'name': 'layout (1280, 800) touch count activates once', 'passed': True}, {'name': 'layout (1280, 800) count still reachable', 'passed': True}, {'name': 'layout (1280, 800) touch count reaches three', 'passed': True}, {'name': 'layout (1280, 800) scroll reaches direction', 'passed': True}, {'name': 'layout (1280, 800) touch direction activates once', 'passed': True}, {'name': 'layout (1280, 800) UI touches no world build', 'passed': True}, {'name': 'layout (1280, 800) visible legal row fixture found', 'passed': True}, {'name': 'layout (1280, 800) scroll back reaches confirm', 'passed': True}, {'name': 'layout (1280, 800) row plan HUD stays within viewport', 'passed': True}, {'name': 'layout (1280, 800) row plan leaves battlefield gap', 'passed': True}, {'name': 'layout (1280, 800) row action buttons do not overlap', 'passed': True}, {'name': 'layout (1280, 800) touch confirm exactly three queued commands', 'passed': True}, {'name': 'layout (1280, 800) confirm exits placement without changing selected workers', 'passed': True}, {'name': 'layout (1280, 800) UI leaked no extra orders', 'passed': True}], 'failed': 0, 'geometry': [{'bottom': '[P: (6.0, 695.0), S: (378.0, 143.0)]', 'buttons': [{'rect': '[P: (16.0, 778.0), S: (120.0, 48.0)]', 'text': '確認建造'}, {'rect': '[P: (144.0, 778.0), S: (54.0, 48.0)]', 'text': '詳情'}, {'rect': '[P: (206.0, 778.0), S: (110.0, 48.0)]', 'text': '取消建造'}, {'rect': '[P: (324.0, 778.0), S: (150.0, 48.0)]', 'text': '木柵段數：3'}, {'rect': '[P: (482.0, 778.0), S: (130.0, 48.0)]', 'text': '方向：直排'}, {'rect': '[P: (620.0, 778.0), S: (170.0, 48.0)]', 'text': '移開己方單位 · 0'}, {'rect': '[P: (798.0, 778.0), S: (150.0, 48.0)]', 'text': '工人分配\n退出建造預覽'}], 'queue': '3 段木柵 · 木材 90 · 每段一位村民', 'scroll': '[P: (16.0, 778.0), S: (358.0, 56.0)]', 'size': '(390, 844)', 'summary': '3 段木柵／木材 90／每段一人。位置已選，按確認建造', 'top': '[P: (6.0, 6.0), S: (378.0, 104.0)]'}, {'bottom': '[P: (6.0, 394.0), S: (308.0, 168.0)]', 'buttons': [{'rect': '[P: (16.0, 502.0), S: (120.0, 48.0)]', 'text': '確認建造'}, {'rect': '[P: (144.0, 502.0), S: (54.0, 48.0)]', 'text': '詳情'}, {'rect': '[P: (206.0, 502.0), S: (110.0, 48.0)]', 'text': '取消建造'}, {'rect': '[P: (324.0, 502.0), S: (150.0, 48.0)]', 'text': '木柵段數：3'}, {'rect': '[P: (482.0, 502.0), S: (130.0, 48.0)]', 'text': '方向：直排'}, {'rect': '[P: (620.0, 502.0), S: (170.0, 48.0)]', 'text': '移開己方單位 · 0'}, {'rect': '[P: (798.0, 502.0), S: (150.0, 48.0)]', 'text': '工人分配\n退出建造預覽'}], 'queue': '3 段木柵 · 木材 90 · 每段一位村民', 'scroll': '[P: (16.0, 502.0), S: (288.0, 56.0)]', 'size': '(320, 568)', 'summary': '3 段木柵／木材 90／每段一人。位置已選，按確認建造', 'top': '[P: (6.0, 6.0), S: (308.0, 104.0)]'}, {'bottom': '[P: (6.0, 221.0), S: (556.0, 93.0)]', 'buttons': [{'rect': '[P: (16.0, 254.0), S: (120.0, 48.0)]', 'text': '確認建造'}, {'rect': '[P: (144.0, 254.0), S: (54.0, 48.0)]', 'text': '詳情'}, {'rect': '[P: (206.0, 254.0), S: (110.0, 48.0)]', 'text': '取消建造'}, {'rect': '[P: (324.0, 254.0), S: (150.0, 48.0)]', 'text': '木柵段數：3'}, {'rect': '[P: (482.0, 254.0), S: (130.0, 48.0)]', 'text': '方向：直排'}, {'rect': '[P: (620.0, 254.0), S: (170.0, 48.0)]', 'text': '移開己方單位 · 0'}, {'rect': '[P: (798.0, 254.0), S: (150.0, 48.0)]', 'text': '工人分配\n退出建造預覽'}], 'queue': '3段 · 木90', 'scroll': '[P: (16.0, 254.0), S: (536.0, 56.0)]', 'size': '(568, 320)', 'summary': '位置已選，按確認', 'top': '[P: (6.0, 6.0), S: (556.0, 54.0)]'}, {'bottom': '[P: (8.0, 685.0), S: (1264.0, 107.0)]', 'buttons': [{'rect': '[P: (18.0, 740.0), S: (120.0, 48.0)]', 'text': '確認建造'}, {'rect': '[P: (146.0, 740.0), S: (54.0, 48.0)]', 'text': '詳情'}, {'rect': '[P: (208.0, 740.0), S: (110.0, 48.0)]', 'text': '取消建造'}, {'rect': '[P: (326.0, 740.0), S: (150.0, 48.0)]', 'text': '木柵段數：3'}, {'rect': '[P: (484.0, 740.0), S: (130.0, 48.0)]', 'text': '方向：直排'}, {'rect': '[P: (622.0, 740.0), S: (170.0, 48.0)]', 'text': '移開己方單位 · 0'}, {'rect': '[P: (800.0, 740.0), S: (150.0, 48.0)]', 'text': '工人分配\n退出建造預覽'}], 'queue': '3 段木柵 · 木材 90 · 每段一位村民', 'scroll': '[P: (18.0, 740.0), S: (1244.0, 48.0)]', 'size': '(1280, 800)', 'summary': '3 段木柵／木材 90／每段一人。位置已選，按確認建造', 'top': '[P: (8.0, 8.0), S: (1264.0, 54.0)]'}], 'scope': 'Controlled current game UI planning plus actual paid commands, ticks, travel, construction and checkpoint continuation; no phone or natural battle claim.', 'suite': 'wall_line_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(d):
                (stage/'godot.log').write_text(json.dumps(d)+'\n')
                return v.read_report(stage,'wall_line_contract')
            self.assertEqual(read(report),report)
            bad=[]
            for i in range(4):
                d=copy.deepcopy(report);d['geometry'][i]['buttons'].pop();bad.append(d) # old six
                for j in range(7):
                    d=copy.deepcopy(report);d['geometry'][i]['buttons'].pop(j);bad.append(d)
                d=copy.deepcopy(report);d['geometry'][i]['buttons'][-1]=copy.deepcopy(d['geometry'][i]['buttons'][0]);bad.append(d)
                d=copy.deepcopy(report);d['geometry'][i]['buttons'].append(copy.deepcopy(d['geometry'][i]['buttons'][-1]));bad.append(d)
                for text in ('工人分配','退出建造預覽','錯誤',''):
                    d=copy.deepcopy(report);d['geometry'][i]['buttons'][-1]['text']=text;bad.append(d)
                for rect in ('[P: (798.0, 502.0), S: (149.0, 48.0)]','[P: (798.0, 502.0), S: (150.0, 20.0)]','[P: (0.0, 0.0), S: (150.0, 48.0)]','NaN'):
                    d=copy.deepcopy(report);d['geometry'][i]['buttons'][-1]['rect']=rect;bad.append(d)
                d=copy.deepcopy(report);d['geometry'][i]['buttons'].reverse();bad.append(d)
                for field in ('scroll','bottom','top','queue','summary','size'):
                    d=copy.deepcopy(report);d['geometry'][i][field]='wrong';bad.append(d)
            self.assertEqual(len(bad),100)
            for d in bad:
                with self.subTest(geometry=d['geometry']):
                    with self.assertRaises(ValueError):read(d)

class AITrafficEscapeReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'controlled worker earns real gathered cargo', 'passed': True}, {'name': 'fixture has nearby observed safe escape', 'passed': True}, {'name': 'persistent traffic worker eligible', 'passed': True}, {'name': 'cooldown refuses early restart', 'passed': True}, {'name': 'static no path never reset', 'passed': True}, {'name': 'general search limit never reset', 'passed': True}, {'name': 'player worker never eligible', 'passed': True}, {'name': 'persistent occupied endpoints never submit or search', 'passed': True}, {'name': 'ordinary blocker movement opens recovery endpoint', 'passed': True}, {'name': 'queued builder-only command blocks recovery before epoch changes', 'passed': True}, {'name': 'one recovery command submitted', 'passed': True}, {'name': 'duplicate think cannot queue another worker command', 'passed': True}, {'name': 'mixed marker fixture passes escape preflight', 'passed': True}, {'name': 'rejected mixed marker keeps worker terminal and budget', 'passed': True}, {'name': 'pending recovery captures with existing schema', 'passed': True}, {'name': 'pending recovery strict encode decode', 'passed': True}, {'name': 'execution preserves cargo bank and retry history', 'passed': True}, {'name': 'execution uses new ordinary move epoch', 'passed': True}, {'name': 'executed recovery captures', 'passed': True}, {'name': 'restore pending recovery succeeds', 'passed': True}, {'name': 'restored pending recovery executes same authority', 'passed': True}, {'name': 'real ticks move worker to escape endpoint', 'passed': True}, {'name': 'real travel deposits preserved earned cargo', 'passed': True}, {'name': 'stale epoch leaves newer command untouched', 'passed': True}, {'name': 'full AI think reserves recovery worker without overwriting', 'passed': True}, {'name': 'full AI submitted recovery executes ordinary move', 'passed': True}, {'name': 'all ordinary economy audit conserved', 'passed': True}], 'failed': 0, 'scope': 'Controlled exhausted traffic fixture, ordinary gathered cargo, native move/deposit and same-build pending checkpoint; not old-match cross-version recovery or natural victory.', 'suite': 'ai_traffic_escape_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class CommandPortraitReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'actual model portrait path villager', 'passed': True}, {'name': 'actual model portrait path scout', 'passed': True}, {'name': 'actual model portrait path spearman', 'passed': True}, {'name': 'actual model portrait path archer', 'passed': True}, {'name': 'actual model portrait path cavalry', 'passed': True}, {'name': 'actual model portrait path siege', 'passed': True}, {'name': 'actual model portrait path wall', 'passed': True}, {'name': 'actual model portrait path farm', 'passed': True}, {'name': 'actual model portrait path house', 'passed': True}, {'name': 'actual model portrait path storehouse', 'passed': True}, {'name': 'actual model portrait path barracks', 'passed': True}, {'name': 'actual model portrait path range', 'passed': True}, {'name': 'actual model portrait path stable', 'passed': True}, {'name': 'actual model portrait path tower', 'passed': True}, {'name': 'actual model portrait path workshop', 'passed': True}, {'name': 'actual model portrait path town_center', 'passed': True}, {'name': 'sixteen distinct kind portraits', 'passed': True}, {'name': 'all nine build labels reserve full 40px portrait (320, 568)', 'passed': True}, {'name': 'build portrait 40px and name price retained (320, 568)', 'passed': True}, {'name': 'locked building portrait visibly disabled (320, 568)', 'passed': True}, {'name': 'two finger portrait press never builds (320, 568)', 'passed': True}, {'name': '40px recruit portrait fully reachable (320, 568)', 'passed': True}, {'name': 'single portrait press submits exactly one train (320, 568)', 'passed': True}, {'name': 'portrait recruits once with ordinary price (320, 568)', 'passed': True}, {'name': 'all nine build labels reserve full 40px portrait (390, 844)', 'passed': True}, {'name': 'build portrait 40px and name price retained (390, 844)', 'passed': True}, {'name': 'locked building portrait visibly disabled (390, 844)', 'passed': True}, {'name': 'two finger portrait press never builds (390, 844)', 'passed': True}, {'name': '40px recruit portrait fully reachable (390, 844)', 'passed': True}, {'name': 'single portrait press submits exactly one train (390, 844)', 'passed': True}, {'name': 'portrait recruits once with ordinary price (390, 844)', 'passed': True}, {'name': 'all nine build labels reserve full 40px portrait (640, 360)', 'passed': True}, {'name': 'build portrait 40px and name price retained (640, 360)', 'passed': True}, {'name': 'locked building portrait visibly disabled (640, 360)', 'passed': True}, {'name': 'two finger portrait press never builds (640, 360)', 'passed': True}, {'name': '40px recruit portrait fully reachable (640, 360)', 'passed': True}, {'name': 'single portrait press submits exactly one train (640, 360)', 'passed': True}, {'name': 'portrait recruits once with ordinary price (640, 360)', 'passed': True}, {'name': 'repeat training uses actual configured troop portrait', 'passed': True}, {'name': 'every troop price reserves full portrait villager', 'passed': True}, {'name': 'every troop price reserves full portrait scout', 'passed': True}, {'name': 'every troop price reserves full portrait spearman', 'passed': True}, {'name': 'every troop price reserves full portrait archer', 'passed': True}, {'name': 'every troop price reserves full portrait cavalry', 'passed': True}, {'name': 'every troop price reserves full portrait siege', 'passed': True}, {'name': 'dynamic dense list reserves full 32px portrait', 'passed': True}, {'name': 'economy audit remains conserved', 'passed': True}], 'failed': 0, 'scope': 'Actual-model portrait mapping, native synthetic touch at three mobile viewports, ordinary paid recruitment; not physical phone validation.', 'suite': 'command_portraits_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class CommandPortraitReportSchemaTests1(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'icon texture present villager', 'passed': True}, {'name': 'icon texture present scout', 'passed': True}, {'name': 'icon texture present spearman', 'passed': True}, {'name': 'icon texture present archer', 'passed': True}, {'name': 'icon texture present cavalry', 'passed': True}, {'name': 'icon texture present siege', 'passed': True}, {'name': 'icon texture present wall', 'passed': True}, {'name': 'icon texture present town_center', 'passed': True}, {'name': 'icon texture present house', 'passed': True}, {'name': 'icon texture present storehouse', 'passed': True}, {'name': 'icon texture present barracks', 'passed': True}, {'name': 'icon texture present range', 'passed': True}, {'name': 'icon texture present farm', 'passed': True}, {'name': 'icon texture present stable', 'passed': True}, {'name': 'icon texture present tower', 'passed': True}, {'name': 'icon texture present workshop', 'passed': True}, {'name': 'unknown keeps original text and no icon', 'passed': True}, {'name': 'train text cost icon retained (320, 568)', 'passed': True}, {'name': 'train reachable 44px target (320, 568)', 'passed': True}, {'name': 'icon touch queues one normal train (320, 568)', 'passed': True}, {'name': 'disabled icon cannot queue train (320, 568)', 'passed': True}, {'name': 'icon strip drag cancels command (320, 568)', 'passed': True}, {'name': 'build text cost icon target retained (320, 568)', 'passed': True}, {'name': 'icon touch starts ordinary house placement (320, 568)', 'passed': True}, {'name': 'train text cost icon retained (390, 844)', 'passed': True}, {'name': 'train reachable 44px target (390, 844)', 'passed': True}, {'name': 'icon touch queues one normal train (390, 844)', 'passed': True}, {'name': 'disabled icon cannot queue train (390, 844)', 'passed': True}, {'name': 'icon strip drag cancels command (390, 844)', 'passed': True}, {'name': 'build text cost icon target retained (390, 844)', 'passed': True}, {'name': 'icon touch starts ordinary house placement (390, 844)', 'passed': True}, {'name': 'train text cost icon retained (640, 360)', 'passed': True}, {'name': 'train reachable 44px target (640, 360)', 'passed': True}, {'name': 'icon touch queues one normal train (640, 360)', 'passed': True}, {'name': 'disabled icon cannot queue train (640, 360)', 'passed': True}, {'name': 'icon strip drag cancels command (640, 360)', 'passed': True}, {'name': 'build text cost icon target retained (640, 360)', 'passed': True}, {'name': 'icon touch starts ordinary house placement (640, 360)', 'passed': True}], 'failed': 0, 'scope': 'Native synthetic touch, real button rectangles and ordinary queued commands; actual-model portraits, not new artwork or physical phone.', 'suite': 'command_icons_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class CommandRecoveryReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'visible legal ordinary house plot', 'passed': True}, {'name': 'ordinary command pays once and assigns real site', 'passed': True}, {'name': 'actual HUD instructs direct tap recovery', 'passed': True}, {'name': 'target is visible site in world', 'passed': True}, {'name': 'advertised direct tap actually queues build order', 'passed': True}, {'name': 'direct tap restarts ordinary construction route without repaying', 'passed': True}, {'name': 'normal travel and work actually finish paid house', 'passed': True}, {'name': 'completed friendly house still selects normally', 'passed': True}, {'name': 'mixed selection continuation only submits selected villagers', 'passed': True}, {'name': 'mixed escort original job survives continuation', 'passed': True}, {'name': 'military only tap selects unfinished site', 'passed': True}, {'name': 'paused tap selects site without construction order', 'passed': True}, {'name': 'hard cap rejection never suggests building more houses', 'passed': True}, {'name': 'ordinary building economy audit conserved', 'passed': True}], 'failed': 0, 'scope': 'Ordinary paid build; controlled route terminal; real routed screen touch; no natural blockage claim.', 'suite': 'contextual_construction_resume_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class CommandRecoveryReportSchemaTests1(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'controlled start is legal', 'passed': True}, {'name': 'ordinary move genuinely exhausts route', 'passed': True}, {'name': 'terminal move HUD no longer claims movement', 'passed': True}, {'name': 'failed intent guide is hidden', 'passed': True}, {'name': 'noncurrent military excluded owned', 'passed': True}, {'name': 'noncurrent military excluded alive', 'passed': True}, {'name': 'inapplicable route excluded remembered', 'passed': True}, {'name': 'inapplicable route excluded path_pending', 'passed': True}, {'name': 'enemy route never inspected', 'passed': True}, {'name': 'pending player intent suppresses stale failure', 'passed': True}, {'name': 'group names stopped military count', 'passed': True}, {'name': 'recovery touch target reachable (320, 568)', 'passed': True}, {'name': 'real recovery touch only selects failed member (320, 568)', 'passed': True}, {'name': 'recovery touch target reachable (390, 844)', 'passed': True}, {'name': 'real recovery touch only selects failed member (390, 844)', 'passed': True}, {'name': 'recovery touch target reachable (640, 360)', 'passed': True}, {'name': 'real recovery touch only selects failed member (640, 360)', 'passed': True}, {'name': 'recovery selects only failed members', 'passed': True}, {'name': 'recovery selection changes no orders budgets hp or payment', 'passed': True}, {'name': 'new pending command retires displayed old failure', 'passed': True}, {'name': 'new explicit reachable move actually succeeds', 'passed': True}, {'name': 'stale recovery identity cannot mutate newer job', 'passed': True}], 'failed': 0, 'scope': 'Controlled legal enclosure, normal MOVE and true bounded search; sanitized own status and selection-only recovery, not natural full-match blockage.', 'suite': 'military_route_feedback_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class BlockedCombatReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'advance legal controlled starts', 'passed': True}, {'name': 'advance actual terminal before combat', 'passed': True}, {'name': 'advance outside range no shot', 'passed': True}, {'name': 'advance ordinary in-range fire damages', 'passed': True}, {'name': 'advance HUD reports current attack', 'passed': True}, {'name': 'advance rate remains authoritative', 'passed': True}, {'name': 'advance terminal and budget preserved', 'passed': True}, {'name': 'advance departure restores terminal warning', 'passed': True}, {'name': 'advance does not chase after departure', 'passed': True}, {'name': 'advance economy audit stays valid', 'passed': True}, {'name': 'patrol legal controlled starts', 'passed': True}, {'name': 'patrol actual terminal before combat', 'passed': True}, {'name': 'patrol outside range no shot', 'passed': True}, {'name': 'patrol ordinary in-range fire damages', 'passed': True}, {'name': 'patrol HUD reports current attack', 'passed': True}, {'name': 'patrol rate remains authoritative', 'passed': True}, {'name': 'patrol terminal and budget preserved', 'passed': True}, {'name': 'patrol departure restores terminal warning', 'passed': True}, {'name': 'patrol does not chase after departure', 'passed': True}, {'name': 'patrol economy audit stays valid', 'passed': True}, {'name': 'attack legal controlled starts', 'passed': True}, {'name': 'attack actual terminal before combat', 'passed': True}, {'name': 'attack outside range no shot', 'passed': True}, {'name': 'attack ordinary in-range fire damages', 'passed': True}, {'name': 'attack HUD reports current attack', 'passed': True}, {'name': 'attack rate remains authoritative', 'passed': True}, {'name': 'attack terminal and budget preserved', 'passed': True}, {'name': 'attack departure restores terminal warning', 'passed': True}, {'name': 'attack departing target retains ordinary bounded pursuit', 'passed': True}, {'name': 'attack economy audit stays valid', 'passed': True}], 'failed': 0, 'scope': 'Controlled legal enclosure; ordinary orders and true search/combat ticks; no natural full-match claim.', 'suite': 'blocked_combat_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class ShelterDeliveryReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'cargo earned by normal gathering', 'passed': True}, {'name': 'real hit creates ordinary evacuation', 'passed': True}, {'name': 'ordinary travel reaches shelter', 'passed': True}, {'name': 'original work area remains unobserved', 'passed': True}, {'name': 'shelter needs full safety interval', 'passed': True}, {'name': 'waiting checkpoint strict roundtrip', 'passed': True}, {'name': 'saved ninety nine tick shelter clock resumes identically', 'passed': True}, {'name': 'unknown origin does not prevent safe delivery', 'passed': True}, {'name': 'delivery preserves origin danger and earned cargo', 'passed': True}, {'name': 'delivery does not reroute to unchecked depots', 'passed': True}, {'name': 'delivery checkpoint strict roundtrip', 'passed': True}, {'name': 'delivery ten tick restored continuation is exact', 'passed': True}, {'name': 'ordinary travel deposits exact earned load', 'passed': True}, {'name': 'deposit never blindly resumes hidden original', 'passed': True}, {'name': 'deposit grants no healing', 'passed': True}, {'name': 'post deposit danger survives checkpoint', 'passed': True}, {'name': 'alternative is current visible outside old danger', 'passed': True}, {'name': 'safe alternative starts normally without forgetting danger', 'passed': True}, {'name': 'alternative work checkpoint strict roundtrip', 'passed': True}, {'name': 'alternative ten tick restored continuation is exact', 'passed': True}, {'name': 'alternative completes ordinary gather and next delivery', 'passed': True}, {'name': 'second cycle retains unknown danger', 'passed': True}, {'name': 'new explicit stop owns worker and cancels memo', 'passed': True}, {'name': 'normal economy audit remains valid', 'passed': True}, {'name': 'traffic stop after real evacuation retains cargo danger and MOVE mode', 'passed': True}, {'name': 'traffic stop does not reset search retry or congestion budget', 'passed': True}, {'name': 'ordinary traffic stop strict capture restore remains valid', 'passed': True}, {'name': 'blocked branch reaches actual alternative gathering', 'passed': True}, {'name': 'controlled depot enclosure leaves worker start legal', 'passed': True}, {'name': 'normal delivery search genuinely reaches terminal', 'passed': True}, {'name': 'terminal delivery keeps cargo and danger', 'passed': True}, {'name': 'terminal danger checkpoint is strictly valid', 'passed': True}, {'name': 'persistent blockage cannot reset budgets or loop jobs', 'passed': True}], 'failed': 0, 'scope': 'Controlled actors; earned cargo and real hit; normal travel/deposit and safety updates; no hidden-origin return or natural full-match claim.', 'suite': 'ai_shelter_delivery_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class ShelterDeliveryReportSchemaTests1(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'AI gathers earned cargo before threat', 'passed': True}, {'name': 'proximity without actual hit does not seize worker', 'passed': True}, {'name': 'controlled actual attack issued', 'passed': True}, {'name': 'real hit starts independent opponent evacuation', 'passed': True}, {'name': 'evacuation preserves true hit-tick harvest', 'passed': True}, {'name': 'evacuation gives no bank or healing', 'passed': True}, {'name': 'same hit cannot repeat order or reset path attempts', 'passed': True}, {'name': 'retreat snapshot is valid', 'passed': True}, {'name': 'retreat restores paused candidate', 'passed': True}, {'name': 'normal walking reaches safe refuge', 'passed': True}, {'name': 'retreat restored continuation matches', 'passed': True}, {'name': 'enemy not erased by hiding original work area', 'passed': True}, {'name': 'regular AI policy claims evacuee', 'passed': True}, {'name': 'opening food floor housing and idle policy do not steal evacuee', 'passed': True}, {'name': 'direct gather dispatch cannot steal evacuee', 'passed': True}, {'name': 'builder selector cannot steal evacuee', 'passed': True}, {'name': 'fog does not permit original return during safe delivery', 'passed': True}, {'name': 'active danger memory blocks another worker during fog', 'passed': True}, {'name': 'observed safety requires full five seconds', 'passed': True}, {'name': 'new visible threat resets continuous safety clock', 'passed': True}, {'name': 'ninety nine safe ticks do not resume', 'passed': True}, {'name': 'danger memory still blocks other worker at ninety nine', 'passed': True}, {'name': 'safe wait checkpoint restores', 'passed': True}, {'name': 'hundred safe ticks resume original gather', 'passed': True}, {'name': 'saved safe clock resumes on identical tick', 'passed': True}, {'name': 'same tick AI planning preserves resumed order', 'passed': True}, {'name': 'completed safety window releases resource for other worker', 'passed': True}, {'name': 'returned worker actually deposits normal earned food', 'passed': True}, {'name': 'economic dispatch chooses observed safe resource', 'passed': True}, {'name': 'economic assignment never falls back to threatened node', 'passed': True}, {'name': 'second worker starts independent shelter', 'passed': True}, {'name': 'terminal route preserves danger without restarting journey', 'passed': True}, {'name': 'same hit cannot restart terminal route', 'passed': True}, {'name': 'depletion branch restores real retreat', 'passed': True}, {'name': 'depleted origin safely deposits retained cargo', 'passed': True}, {'name': 'no safe refuge keeps ordinary work and bounded attempts', 'passed': True}, {'name': 'ordinary harvest reaches delivery before attack', 'passed': True}, {'name': 'delivery evacuation retains original resource and full cargo', 'passed': True}, {'name': 'farm worker is not automatically evacuated', 'passed': True}, {'name': 'manual replacement fixture enters evacuation', 'passed': True}, {'name': 'explicit stop retires AI memo', 'passed': True}, {'name': 'new actual hit can start new evacuation', 'passed': True}, {'name': 'player safety toggle never clears AI memo', 'passed': True}, {'name': 'worker death clears AI memo and settles cargo', 'passed': True}, {'name': 'all controlled ledgers conserve', 'passed': True}], 'failed': 0, 'scope': 'Controlled true-hit AI evacuation, current observation safety, ordinary cargo and save continuation; not natural battle or physical phone acceptance', 'suite': 'ai_worker_safety_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class TutorialFoldReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'fresh tutorial retains expanded onboarding', 'passed': True}, {'name': 'pre fold strict capture is valid and nonempty', 'passed': True}, {'name': 'real collapse removes full width tutorial row', 'passed': True}, {'name': 'collapse is not skip or a simulation command', 'passed': True}, {'name': 'collapse is absent from strict saved authority', 'passed': True}, {'name': 'progress entry fits (640, 360)', 'passed': True}, {'name': 'essential top controls fit (640, 360)', 'passed': True}, {'name': 'rotation relayout preserves collapsed preference (640, 360)', 'passed': True}, {'name': 'progress entry fits (568, 320)', 'passed': True}, {'name': 'essential top controls fit (568, 320)', 'passed': True}, {'name': 'rotation relayout preserves collapsed preference (568, 320)', 'passed': True}, {'name': 'progress entry fits (320, 568)', 'passed': True}, {'name': 'essential top controls fit (320, 568)', 'passed': True}, {'name': 'rotation relayout preserves collapsed preference (320, 568)', 'passed': True}, {'name': 'progress entry fits (390, 844)', 'passed': True}, {'name': 'essential top controls fit (390, 844)', 'passed': True}, {'name': 'rotation relayout preserves collapsed preference (390, 844)', 'passed': True}, {'name': 'real selection still records while folded', 'passed': True}, {'name': 'ordinary gather target is current observed', 'passed': True}, {'name': 'normal gather and paid in cargo progress survives folding', 'passed': True}, {'name': 'canceled entry touch leaves fold unchanged', 'passed': True}, {'name': 'second finger cancels tutorial entry', 'passed': True}, {'name': 'fresh entry expands current earned progress', 'passed': True}, {'name': 'folded feedback remains visible', 'passed': True}, {'name': 'full feedback still reachable', 'passed': True}, {'name': 'toast expiry returns folded without empty panel', 'passed': True}, {'name': 'fold controls preserve unpaid build preview and bank', 'passed': True}, {'name': 'ordinary settled damage creates active alert fixture', 'passed': True}, {'name': 'narrow alert keeps battle pause and menu visible', 'passed': True}, {'name': 'menu fallback progress entry reachable without new row', 'passed': True}, {'name': 'fallback opens lesson without orders selection or payment', 'passed': True}, {'name': 'focus loss cancels held fold entry', 'passed': True}, {'name': 'explicit skip remains distinct and hides progress entry', 'passed': True}, {'name': 'resume restores accessible entry without losing facts', 'passed': True}, {'name': 'pause control pauses before folding', 'passed': True}, {'name': 'paused fold remains paused and preserves simulation', 'passed': True}, {'name': 'resume control preserves chosen folded preference', 'passed': True}, {'name': 'return to main menu pauses folded match', 'passed': True}, {'name': 'new match still requires discard confirmation', 'passed': True}, {'name': 'cancel new match and resume retain folded preference', 'passed': True}, {'name': 'confirmed fresh match restores expanded onboarding', 'passed': True}], 'failed': 0, 'scope': 'Native routed fold and unchanged tutorial facts, ordinary gather/deposit, four viewports and feedback; no physical phone performance claim.', 'suite': 'tutorial_fold_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class AiFoodFeasibilityReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'safe remembered food retains ordinary exploration goal', 'passed': True}, {'name': 'safe visible food retains ordinary goal', 'passed': True}, {'name': 'dead berries do not suppress farm', 'passed': True}, {'name': 'observed hostile threat excludes otherwise known food', 'passed': True}, {'name': 'remembered enemy is not a hidden live threat oracle', 'passed': True}, {'name': 'dead enemy does not block safe food', 'passed': True}, {'name': 'existing owned danger memory excludes food planning', 'passed': True}, {'name': 'farm deficit selects ordinary wood funding', 'passed': True}, {'name': 'house priority remains above food fallback', 'passed': True}, {'name': 'affordable minimum workforce priority unchanged', 'passed': True}, {'name': 'four unfinished farms still cap farm plan', 'passed': True}, {'name': 'three farms still allow final farm', 'passed': True}, {'name': 'policy does not mutate observations', 'passed': True}, {'name': 'ordinary AI farm uses existing paid build submission', 'passed': True}, {'name': 'pending ordinary farm checkpoint remains strict', 'passed': True}, {'name': 'pending farm restores without duplicate commands', 'passed': True}, {'name': 'ordinary travel and ticks complete paid farm', 'passed': True}, {'name': 'farm payment debits exactly sixty wood', 'passed': True}, {'name': 'construction preserves economic conservation', 'passed': True}], 'failed': 0, 'scope': 'Controlled observed-record planning boundaries and fresh normal-stock paid farm construction; no natural full-match victory claim.', 'suite': 'ai_food_feasibility_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class AiRecoveryReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'fresh uninitialized idle worker safely declined', 'passed': True}, {'name': 'carrier cargo earned by ordinary gather ticks', 'passed': True}, {'name': 'controlled real collision has safe adjacent yield plan', 'passed': True}, {'name': 'planning leaves full captured authority unchanged', 'passed': True}, {'name': 'disabled AI never plans a yield', 'passed': True}, {'name': 'scripted survival never plans a yield', 'passed': True}, {'name': 'player worker never commandeered', 'passed': True}, {'name': 'explicit stopped worker never commandeered', 'passed': True}, {'name': '599 tick cooldown still blocks', 'passed': True}, {'name': 'manual command grace prevents yield', 'passed': True}, {'name': 'queued construction intent prevents yield', 'passed': True}, {'name': 'active worker job is never stolen', 'passed': True}, {'name': 'actual anticipation queues normal command and leaves carrier unchanged', 'passed': True}, {'name': 'pending yield strict capture accepts unchanged schema', 'passed': True}, {'name': 'pending marker roundtrips exact through codec', 'passed': True}, {'name': 'pending marker strict restore succeeds', 'passed': True}, {'name': 'stale blocker epoch rejects without move', 'passed': True}, {'name': 'stale carrier epoch rejects without move', 'passed': True}, {'name': 'accepted yield is ordinary MOVE with new epoch', 'passed': True}, {'name': 'carrier cargo and path budgets are untouched', 'passed': True}, {'name': 'yield cooldown persists on ordinary actor', 'passed': True}, {'name': 'executed strict continuation captures complete equal authority', 'passed': True}], 'failed': 0, 'scope': 'Controlled collision frontier after ordinary earned cargo; safe AI yield and strict command continuation, not full-match recovery claim.', 'suite': 'ai_idle_yield_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class AiRecoveryReportSchemaTests1(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'fixture is living sheltered workforce with ordinary funds', 'passed': True}, {'name': 'housing priority never diverts into staffing', 'passed': True}, {'name': 'nonfarm goals keep existing progression', 'passed': True}, {'name': 'queued worker prevents duplicate relief', 'passed': True}, {'name': 'full population prevents relief', 'passed': True}, {'name': 'eight existing workers retain prior workforce ceiling', 'passed': True}, {'name': 'one milli below price cannot enqueue', 'passed': True}, {'name': 'any unsheltered live worker blocks extra recruitment', 'passed': True}, {'name': 'stale shelter epoch is not proof of unavailable labor', 'passed': True}, {'name': 'unfinished keep cannot train relief', 'passed': True}, {'name': 'disabled AI never recruits', 'passed': True}, {'name': 'negative checks preserve bank and queue', 'passed': True}, {'name': 'eligible relief submits ordinary train once', 'passed': True}, {'name': 'submission reserves fifty food but does not mint or debit early', 'passed': True}, {'name': 'pending ordinary train blocks same tick repeat', 'passed': True}, {'name': 'pending relief strict same build codec roundtrip', 'passed': True}, {'name': 'pending relief restores without duplicate', 'passed': True}, {'name': 'hundred normal ticks after restore preserve complete authority', 'passed': True}, {'name': 'normal execution pays exactly fifty food', 'passed': True}, {'name': 'normal production ticks create exactly one new worker', 'passed': True}, {'name': 'new worker without shelter permanently ends this relief episode', 'passed': True}, {'name': 'ordinary economy remains conserved', 'passed': True}], 'failed': 0, 'scope': 'Controlled coherent sheltered workforce with normal initial resources, paid training and strict continuation; no complete economy recovery claim.', 'suite': 'ai_shelter_staffing_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class LicensedResourceReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'stone variant 0 stage 0 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 0 stage 0 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 0 stage 0 cached immutable observation', 'passed': True}, {'name': 'stone variant 0 stage 1 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 0 stage 1 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 0 stage 1 cached immutable observation', 'passed': True}, {'name': 'stone variant 0 stage 2 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 0 stage 2 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 0 stage 2 cached immutable observation', 'passed': True}, {'name': 'stone variant 0 stage 3 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 0 stage 3 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 0 stage 3 cached immutable observation', 'passed': True}, {'name': 'stone variant 0 four coherent depletion heights', 'passed': True}, {'name': 'stone variant 0 memory dim applied per proxy', 'passed': True}, {'name': 'stone variant 0 visible stage restores shared material', 'passed': True}, {'name': 'stone variant 1 stage 0 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 1 stage 0 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 1 stage 0 cached immutable observation', 'passed': True}, {'name': 'stone variant 1 stage 1 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 1 stage 1 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 1 stage 1 cached immutable observation', 'passed': True}, {'name': 'stone variant 1 stage 2 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 1 stage 2 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 1 stage 2 cached immutable observation', 'passed': True}, {'name': 'stone variant 1 stage 3 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 1 stage 3 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 1 stage 3 cached immutable observation', 'passed': True}, {'name': 'stone variant 1 four coherent depletion heights', 'passed': True}, {'name': 'stone variant 1 memory dim applied per proxy', 'passed': True}, {'name': 'stone variant 1 visible stage restores shared material', 'passed': True}, {'name': 'stone variant 2 stage 0 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 2 stage 0 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 2 stage 0 cached immutable observation', 'passed': True}, {'name': 'stone variant 2 stage 1 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 2 stage 1 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 2 stage 1 cached immutable observation', 'passed': True}, {'name': 'stone variant 2 stage 2 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 2 stage 2 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 2 stage 2 cached immutable observation', 'passed': True}, {'name': 'stone variant 2 stage 3 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'stone variant 2 stage 3 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'stone variant 2 stage 3 cached immutable observation', 'passed': True}, {'name': 'stone variant 2 four coherent depletion heights', 'passed': True}, {'name': 'stone variant 2 memory dim applied per proxy', 'passed': True}, {'name': 'stone variant 2 visible stage restores shared material', 'passed': True}, {'name': 'stone variant rules', 'passed': True}, {'name': 'iron variant 0 stage 0 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 0 stage 0 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 0 stage 0 cached immutable observation', 'passed': True}, {'name': 'iron variant 0 stage 1 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 0 stage 1 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 0 stage 1 cached immutable observation', 'passed': True}, {'name': 'iron variant 0 stage 2 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 0 stage 2 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 0 stage 2 cached immutable observation', 'passed': True}, {'name': 'iron variant 0 stage 3 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 0 stage 3 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 0 stage 3 cached immutable observation', 'passed': True}, {'name': 'iron variant 0 four coherent depletion heights', 'passed': True}, {'name': 'iron variant 0 memory dim applied per proxy', 'passed': True}, {'name': 'iron variant 0 visible stage restores shared material', 'passed': True}, {'name': 'iron variant 1 stage 0 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 1 stage 0 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 1 stage 0 cached immutable observation', 'passed': True}, {'name': 'iron variant 1 stage 1 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 1 stage 1 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 1 stage 1 cached immutable observation', 'passed': True}, {'name': 'iron variant 1 stage 2 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 1 stage 2 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 1 stage 2 cached immutable observation', 'passed': True}, {'name': 'iron variant 1 stage 3 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 1 stage 3 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 1 stage 3 cached immutable observation', 'passed': True}, {'name': 'iron variant 1 four coherent depletion heights', 'passed': True}, {'name': 'iron variant 1 memory dim applied per proxy', 'passed': True}, {'name': 'iron variant 1 visible stage restores shared material', 'passed': True}, {'name': 'iron variant 2 stage 0 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 2 stage 0 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 2 stage 0 cached immutable observation', 'passed': True}, {'name': 'iron variant 2 stage 1 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 2 stage 1 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 2 stage 1 cached immutable observation', 'passed': True}, {'name': 'iron variant 2 stage 2 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 2 stage 2 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 2 stage 2 cached immutable observation', 'passed': True}, {'name': 'iron variant 2 stage 3 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'iron variant 2 stage 3 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'iron variant 2 stage 3 cached immutable observation', 'passed': True}, {'name': 'iron variant 2 four coherent depletion heights', 'passed': True}, {'name': 'iron variant 2 memory dim applied per proxy', 'passed': True}, {'name': 'iron variant 2 visible stage restores shared material', 'passed': True}, {'name': 'iron variant rules', 'passed': True}, {'name': 'berry variant 0 stage 0 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 0 stage 0 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 0 stage 0 cached immutable observation', 'passed': True}, {'name': 'berry variant 0 stage 1 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 0 stage 1 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 0 stage 1 cached immutable observation', 'passed': True}, {'name': 'berry variant 0 stage 2 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 0 stage 2 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 0 stage 2 cached immutable observation', 'passed': True}, {'name': 'berry variant 0 stage 3 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 0 stage 3 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 0 stage 3 cached immutable observation', 'passed': True}, {'name': 'berry variant 0 four coherent depletion heights', 'passed': True}, {'name': 'berry variant 0 memory dim applied per proxy', 'passed': True}, {'name': 'berry variant 0 visible stage restores shared material', 'passed': True}, {'name': 'berry variant 1 stage 0 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 1 stage 0 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 1 stage 0 cached immutable observation', 'passed': True}, {'name': 'berry variant 1 stage 1 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 1 stage 1 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 1 stage 1 cached immutable observation', 'passed': True}, {'name': 'berry variant 1 stage 2 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 1 stage 2 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 1 stage 2 cached immutable observation', 'passed': True}, {'name': 'berry variant 1 stage 3 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 1 stage 3 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 1 stage 3 cached immutable observation', 'passed': True}, {'name': 'berry variant 1 four coherent depletion heights', 'passed': True}, {'name': 'berry variant 1 memory dim applied per proxy', 'passed': True}, {'name': 'berry variant 1 visible stage restores shared material', 'passed': True}, {'name': 'berry variant 2 stage 0 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 2 stage 0 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 2 stage 0 cached immutable observation', 'passed': True}, {'name': 'berry variant 2 stage 1 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 2 stage 1 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 2 stage 1 cached immutable observation', 'passed': True}, {'name': 'berry variant 2 stage 2 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 2 stage 2 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 2 stage 2 cached immutable observation', 'passed': True}, {'name': 'berry variant 2 stage 3 finite nondegenerate material-appropriate geometry', 'passed': True}, {'name': 'berry variant 2 stage 3 asset-specific surface count bounded vertices footprint', 'passed': True}, {'name': 'berry variant 2 stage 3 cached immutable observation', 'passed': True}, {'name': 'berry variant 2 four coherent depletion heights', 'passed': True}, {'name': 'berry variant 2 memory dim applied per proxy', 'passed': True}, {'name': 'berry variant 2 visible stage restores shared material', 'passed': True}, {'name': 'berry variant rules', 'passed': True}, {'name': 'rock shared texture actual dimensions', 'passed': True}, {'name': 'stone same-stage memory does not mutate second proxy', 'passed': True}, {'name': 'stone same-stage visibility restores original shared material', 'passed': True}, {'name': 'iron same-stage memory does not mutate second proxy', 'passed': True}, {'name': 'iron same-stage visibility restores original shared material', 'passed': True}, {'name': 'berry same-stage memory does not mutate second proxy', 'passed': True}, {'name': 'berry same-stage visibility restores original shared material', 'passed': True}, {'name': 'iron exactly sixty-six solid chunk triangles 0', 'passed': True}, {'name': 'ore retains exact authored base vertices 0', 'passed': True}, {'name': 'closed outward-wound thick flat-top blocks 0', 'passed': True}, {'name': 'all six bottom corners embedded in actual donor surface 0', 'passed': True}, {'name': 'chunk footprint and height bounded 0', 'passed': True}, {'name': 'stone and ore share original texture one surface 0', 'passed': True}, {'name': 'iron exactly sixty-six solid chunk triangles 1', 'passed': True}, {'name': 'ore retains exact authored base vertices 1', 'passed': True}, {'name': 'closed outward-wound thick flat-top blocks 1', 'passed': True}, {'name': 'all six bottom corners embedded in actual donor surface 1', 'passed': True}, {'name': 'chunk footprint and height bounded 1', 'passed': True}, {'name': 'stone and ore share original texture one surface 1', 'passed': True}, {'name': 'iron exactly sixty-six solid chunk triangles 2', 'passed': True}, {'name': 'ore retains exact authored base vertices 2', 'passed': True}, {'name': 'closed outward-wound thick flat-top blocks 2', 'passed': True}, {'name': 'all six bottom corners embedded in actual donor surface 2', 'passed': True}, {'name': 'chunk footprint and height bounded 2', 'passed': True}, {'name': 'stone and ore share original texture one surface 2', 'passed': True}, {'name': 'normal game strict authority unchanged by mineral presentation', 'passed': True}, {'name': 'normal game RNG and observed records unchanged', 'passed': True}, {'name': 'normal game economic ledger remains conserved', 'passed': True}], 'failed': 0, 'scope': 'Cached mineral variants and multi-surface berries across observed depletion stages; strict normal-game authority and RNG invariance. No visual quality or physical phone performance claim.', 'suite': 'licensed_resource_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class ResourceGeometryExactTests(unittest.TestCase):
    def test_actual_and_malformed_geometry(self):
        import validate_latest_contracts as v
        raw='Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org\n\nRESOURCE_METRIC stone vertices=732 surfaces=1 bounds=[P: (-0.489852, 0.0, -0.398318), S: (0.979703, 0.610226, 0.796637)]\nRESOURCE_METRIC iron vertices=930 surfaces=1 bounds=[P: (-0.489852, 0.0, -0.398318), S: (0.979703, 0.669126, 0.796637)]\nRESOURCE_METRIC berry vertices=1800 surfaces=2 bounds=[P: (-0.460012, 0.0, -0.472095), S: (0.920025, 0.76, 0.944191)]\nRESOURCE_CONTRACT_PASS 27\n'
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)
            def read(x):
                (p/'godot.log').write_text(x)
                return v.read_report(p,'resource_visual_contract')
            self.assertEqual(read(raw)['assertions'],27)
            bad=[raw.replace('vertices=732','vertices=1008'),raw.replace('vertices=930','vertices=1008'),raw.replace('0.610226','0.610227'),raw.replace('surfaces=1','surfaces=2'),raw.replace('RESOURCE_CONTRACT_PASS 27','RESOURCE_CONTRACT_PASS 26')]
            lines=raw.splitlines()
            for metric in [l for l in lines if l.startswith('RESOURCE_METRIC ')]:
                bad.extend([raw.replace(metric+'\n',''),raw+metric+'\n'])
            for x in bad:
                with self.assertRaises(ValueError):read(x)

class ResourceHeightSpecificationTests(unittest.TestCase):
    def test_exact_authored_height_spec_and_negative_boundaries(self):
        # Pure specification/fixture test, not native rendering evidence.
        import re, ast
        source=(Path(__file__).resolve().parents[1]/'game/tests/resource_polish_contract.gd').read_text()
        matches=re.findall(r'var expected_height=(\{[^\n]+\})\[kind\]',source)
        self.assertEqual(len(matches),1)
        heights=ast.literal_eval(matches[0])
        self.assertEqual(heights,{'stone':0.610226,'iron':0.669126,'berry':0.76})
        self.assertEqual(source.count('assert(absf(visual.mesh.get_aabb().size.y-expected_height)<=0.00001 and visual.mesh.get_aabb().size.y<1.0);checks+=1'),1)
        for expected in heights.values():
            accepts=lambda actual: abs(actual-expected)<=0.00001 and actual<1.0
            self.assertTrue(accepts(expected))
            self.assertTrue(accepts(expected+0.000009))
            self.assertTrue(accepts(expected-0.000009))
            for wrong in [expected+0.000011,expected-0.000011,0.65,1.0,float('nan'),float('inf')]+[v for v in heights.values() if v!=expected]:
                self.assertFalse(accepts(wrong))

class QueuedSimultaneousReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'fresh uninitialized idle worker safely declined', 'passed': True}, {'name': 'carrier cargo earned by ordinary gather ticks', 'passed': True}, {'name': 'controlled real collision has safe adjacent yield plan', 'passed': True}, {'name': 'planning leaves full captured authority unchanged', 'passed': True}, {'name': 'scheduled work retry can request same safe empty yield', 'passed': True}, {'name': 'queued planning changes no full authoritative field', 'passed': True}, {'name': 'stale queued request epoch cannot yield', 'passed': True}, {'name': 'terminal carrier never reopened by queued yield', 'passed': True}, {'name': 'remote queued goal cannot become local yield', 'passed': True}, {'name': 'nonpending empty path cannot yield', 'passed': True}, {'name': 'queued request target must still match delivery', 'passed': True}, {'name': 'unset queued goal cannot request movement', 'passed': True}, {'name': 'queued request submission preserves carrier all fields', 'passed': True}, {'name': 'queued carrier plus yield marker strict codec accepts', 'passed': True}, {'name': 'queued carrier plus yield marker strict restore accepts', 'passed': True}, {'name': 'queued marker restoration preserves complete captured authority', 'passed': True}, {'name': 'same epoch changed queued goal atomically rejects old marker', 'passed': True}, {'name': 'disabled AI never plans a yield', 'passed': True}, {'name': 'scripted survival never plans a yield', 'passed': True}, {'name': 'player worker never commandeered', 'passed': True}, {'name': 'explicit stopped worker never commandeered', 'passed': True}, {'name': '599 tick cooldown still blocks', 'passed': True}, {'name': 'manual command grace prevents yield', 'passed': True}, {'name': 'queued construction intent prevents yield', 'passed': True}, {'name': 'active worker job is never stolen', 'passed': True}, {'name': 'actual anticipation queues normal command and leaves carrier unchanged', 'passed': True}, {'name': 'pending yield strict capture accepts unchanged schema', 'passed': True}, {'name': 'pending marker roundtrips exact through codec', 'passed': True}, {'name': 'pending marker strict restore succeeds', 'passed': True}, {'name': 'stale blocker epoch rejects without move', 'passed': True}, {'name': 'stale carrier epoch rejects without move', 'passed': True}, {'name': 'accepted yield is ordinary MOVE with new epoch', 'passed': True}, {'name': 'carrier cargo and path budgets are untouched', 'passed': True}, {'name': 'yield cooldown persists on ordinary actor', 'passed': True}, {'name': 'executed strict continuation captures complete equal authority', 'passed': True}], 'failed': 0, 'scope': 'Controlled collision frontier after ordinary earned cargo; safe AI yield and strict command continuation, not full-match recovery claim.', 'suite': 'ai_queued_yield_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class QueuedSimultaneousReportSchemaTests1(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'build': 'vc-3a05feaf79f1', 'checks': [{'name': 'villager native bind', 'passed': True}, {'name': 'villager simultaneous release displays contact', 'passed': True}, {'name': 'villager both cues consumed and record immutable', 'passed': True}, {'name': 'villager repeated observation never replays release', 'passed': True}, {'name': 'villager later hit still interrupts recovery', 'passed': True}, {'name': 'villager attack-only still shows contact', 'passed': True}, {'name': 'villager unequal newer hit retains priority', 'passed': True}, {'name': 'villager interrupted attack never replayed', 'passed': True}, {'name': 'villager reappearing historical events consumed not replayed', 'passed': True}, {'name': 'villager death wins over simultaneous cues', 'passed': True}, {'name': 'spearman native bind', 'passed': True}, {'name': 'spearman simultaneous release displays contact', 'passed': True}, {'name': 'spearman both cues consumed and record immutable', 'passed': True}, {'name': 'spearman repeated observation never replays release', 'passed': True}, {'name': 'spearman later hit still interrupts recovery', 'passed': True}, {'name': 'spearman attack-only still shows contact', 'passed': True}, {'name': 'spearman unequal newer hit retains priority', 'passed': True}, {'name': 'spearman interrupted attack never replayed', 'passed': True}, {'name': 'spearman reappearing historical events consumed not replayed', 'passed': True}, {'name': 'spearman death wins over simultaneous cues', 'passed': True}, {'name': 'archer native bind', 'passed': True}, {'name': 'archer simultaneous release displays contact', 'passed': True}, {'name': 'archer both cues consumed and record immutable', 'passed': True}, {'name': 'archer repeated observation never replays release', 'passed': True}, {'name': 'archer later hit still interrupts recovery', 'passed': True}, {'name': 'archer attack-only still shows contact', 'passed': True}, {'name': 'archer unequal newer hit retains priority', 'passed': True}, {'name': 'archer interrupted attack never replayed', 'passed': True}, {'name': 'archer reappearing historical events consumed not replayed', 'passed': True}, {'name': 'archer death wins over simultaneous cues', 'passed': True}, {'name': 'scout native bind', 'passed': True}, {'name': 'scout simultaneous release displays contact', 'passed': True}, {'name': 'scout both cues consumed and record immutable', 'passed': True}, {'name': 'scout repeated observation never replays release', 'passed': True}, {'name': 'scout later hit still interrupts recovery', 'passed': True}, {'name': 'scout attack-only still shows contact', 'passed': True}, {'name': 'scout unequal newer hit retains priority', 'passed': True}, {'name': 'scout interrupted attack never replayed', 'passed': True}, {'name': 'scout reappearing historical events consumed not replayed', 'passed': True}, {'name': 'scout death wins over simultaneous cues', 'passed': True}, {'name': 'spearman initial strict state valid', 'passed': True}, {'name': 'spearman ordinary tick 0', 'passed': True}, {'name': 'spearman release damage unchanged 1', 'passed': True}, {'name': 'spearman real reciprocal release has attack pose 1', 'passed': True}, {'name': 'spearman ordinary tick 1', 'passed': True}, {'name': 'spearman ordinary tick 2', 'passed': True}, {'name': 'spearman ordinary tick 3', 'passed': True}, {'name': 'spearman ordinary tick 4', 'passed': True}, {'name': 'spearman ordinary tick 5', 'passed': True}, {'name': 'spearman ordinary tick 6', 'passed': True}, {'name': 'spearman ordinary tick 7', 'passed': True}, {'name': 'spearman ordinary tick 8', 'passed': True}, {'name': 'spearman ordinary tick 9', 'passed': True}, {'name': 'spearman ordinary tick 10', 'passed': True}, {'name': 'spearman ordinary tick 11', 'passed': True}, {'name': 'spearman ordinary tick 12', 'passed': True}, {'name': 'spearman ordinary tick 13', 'passed': True}, {'name': 'spearman ordinary tick 14', 'passed': True}, {'name': 'spearman ordinary tick 15', 'passed': True}, {'name': 'spearman ordinary tick 16', 'passed': True}, {'name': 'spearman ordinary tick 17', 'passed': True}, {'name': 'spearman ordinary tick 18', 'passed': True}, {'name': 'spearman ordinary tick 19', 'passed': True}, {'name': 'spearman ordinary tick 20', 'passed': True}, {'name': 'spearman ordinary tick 21', 'passed': True}, {'name': 'spearman ordinary tick 22', 'passed': True}, {'name': 'spearman ordinary tick 23', 'passed': True}, {'name': 'spearman ordinary tick 24', 'passed': True}, {'name': 'spearman ordinary tick 25', 'passed': True}, {'name': 'spearman ordinary tick 26', 'passed': True}, {'name': 'spearman ordinary tick 27', 'passed': True}, {'name': 'spearman ordinary tick 28', 'passed': True}, {'name': 'spearman ordinary tick 29', 'passed': True}, {'name': 'spearman ordinary tick 30', 'passed': True}, {'name': 'spearman release damage unchanged 2', 'passed': True}, {'name': 'spearman real reciprocal release has attack pose 2', 'passed': True}, {'name': 'spearman presentation authority invariant', 'passed': True}, {'name': 'archer initial strict state valid', 'passed': True}, {'name': 'archer ordinary tick 0', 'passed': True}, {'name': 'archer release damage unchanged 1', 'passed': True}, {'name': 'archer real reciprocal release has attack pose 1', 'passed': True}, {'name': 'archer ordinary tick 1', 'passed': True}, {'name': 'archer ordinary tick 2', 'passed': True}, {'name': 'archer ordinary tick 3', 'passed': True}, {'name': 'archer ordinary tick 4', 'passed': True}, {'name': 'archer ordinary tick 5', 'passed': True}, {'name': 'archer ordinary tick 6', 'passed': True}, {'name': 'archer ordinary tick 7', 'passed': True}, {'name': 'archer ordinary tick 8', 'passed': True}, {'name': 'archer ordinary tick 9', 'passed': True}, {'name': 'archer ordinary tick 10', 'passed': True}, {'name': 'archer ordinary tick 11', 'passed': True}, {'name': 'archer ordinary tick 12', 'passed': True}, {'name': 'archer ordinary tick 13', 'passed': True}, {'name': 'archer ordinary tick 14', 'passed': True}, {'name': 'archer ordinary tick 15', 'passed': True}, {'name': 'archer ordinary tick 16', 'passed': True}, {'name': 'archer ordinary tick 17', 'passed': True}, {'name': 'archer ordinary tick 18', 'passed': True}, {'name': 'archer ordinary tick 19', 'passed': True}, {'name': 'archer ordinary tick 20', 'passed': True}, {'name': 'archer ordinary tick 21', 'passed': True}, {'name': 'archer ordinary tick 22', 'passed': True}, {'name': 'archer ordinary tick 23', 'passed': True}, {'name': 'archer ordinary tick 24', 'passed': True}, {'name': 'archer ordinary tick 25', 'passed': True}, {'name': 'archer ordinary tick 26', 'passed': True}, {'name': 'archer ordinary tick 27', 'passed': True}, {'name': 'archer ordinary tick 28', 'passed': True}, {'name': 'archer ordinary tick 29', 'passed': True}, {'name': 'archer ordinary tick 30', 'passed': True}, {'name': 'archer release damage unchanged 2', 'passed': True}, {'name': 'archer real reciprocal release has attack pose 2', 'passed': True}, {'name': 'archer presentation authority invariant', 'passed': True}, {'name': 'spearman baseline real controller bound 0', 'passed': True}, {'name': 'spearman baseline real controller bound 1', 'passed': True}, {'name': 'spearman baseline strict capture nonempty', 'passed': True}, {'name': 'spearman baseline fixed 31tick full authority equal', 'passed': True}, {'name': 'spearman baseline fixed release ledger equal', 'passed': True}, {'name': 'spearman baseline reproduces hit masking release', 'passed': True}, {'name': 'archer baseline real controller bound 0', 'passed': True}, {'name': 'archer baseline real controller bound 1', 'passed': True}, {'name': 'archer baseline strict capture nonempty', 'passed': True}, {'name': 'archer baseline fixed 31tick full authority equal', 'passed': True}, {'name': 'archer baseline fixed release ledger equal', 'passed': True}, {'name': 'archer baseline reproduces hit masking release', 'passed': True}, {'name': 'actual currently observed enemy has controller', 'passed': True}, {'name': 'ordinary scout movement removes actual enemy vision', 'passed': True}, {'name': 'actual fog reconciles enemy controller away', 'passed': True}, {'name': 'ordinary scout return restores current observation', 'passed': True}, {'name': 'reobserved controller comes from actual current record', 'passed': True}, {'name': 'fog movement final authority remains strict valid', 'passed': True}], 'failed': 0, 'scope': 'Controller contracts plus ordinary reciprocal combat; controlled spawned pairs; no render or phone claims.', 'suite': 'simultaneous_attack_display_contract', 'total': 132}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class SimultaneousIdentityTests(unittest.TestCase):
    def test_exact_identity_rejects_value_type_and_missing(self):
        import validate_latest_contracts as v
        spec=v.ARMY_CONTRACTS['simultaneous_attack_display_contract']
        report={'suite':spec['suite'],'scope':spec['scope'],'checks':[{'name':n,'passed':True} for n in spec['names']],'failed':0,**spec['identity']}
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)
            for key,wrong in [('build','wrong'),('build',None),('total',131),('total',132.0),('total','132'),('total',True)]:
                d=dict(report);d[key]=wrong;(p/'godot.log').write_text(json.dumps(d))
                with self.assertRaises(ValueError):v.read_report(p,report['suite'])
            for key in ['build','total']:
                d=dict(report);del d[key];(p/'godot.log').write_text(json.dumps(d))
                with self.assertRaises(ValueError):v.read_report(p,report['suite'])

class TowerSpacingReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'adjacent own footprint is not selected', 'ok': True}, {'name': 'one empty grid cell is not enough', 'ok': True}, {'name': 'two empty grid cells remain permitted', 'ok': True}, {'name': 'unfinished paid construction reserves its footprint', 'ok': True}, {'name': 'dead own building does not reserve new lane', 'ok': True}, {'name': 'policy does not derive lane from enemy building', 'ok': True}, {'name': 'wall formation remains outside ordinary spacing policy', 'ok': True}, {'name': 'natural obstacle clearance remains placement authority', 'ok': True}, {'name': 'mixed odd workshop footprint obeys cell spacing', 'ok': True}, {'name': 'selection policy is read only and cannot pay or submit', 'ok': True}, {'name': 'tower policy enforces the same building gap', 'ok': True}, {'name': 'non-tower house preserves ordinary placement selection', 'ok': True}, {'name': 'non-tower barracks preserves ordinary placement selection', 'ok': True}, {'name': 'non-tower range preserves ordinary placement selection', 'ok': True}, {'name': 'non-tower workshop preserves ordinary placement selection', 'ok': True}, {'name': 'non-tower farm preserves ordinary placement selection', 'ok': True}, {'name': 'non-tower storehouse preserves ordinary placement selection', 'ok': True}, {'name': 'non-tower stable preserves ordinary placement selection', 'ok': True}, {'name': 'non-tower wall preserves ordinary placement selection', 'ok': True}], 'failed': 0, 'scope': 'Pure tower-only selection policy and unchanged non-tower delegation; no reachability or match-benefit assertion', 'suite': 'ai_building_spacing_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['ok']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class BushFruitReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'explicit surface count 0', 'passed': True}, {'name': 'finite nondegenerate 0', 'passed': True}, {'name': 'exact triangle budget 0', 'passed': True}, {'name': 'bounds footprint 0', 'passed': True}, {'name': 'leaf cutout retained 0', 'passed': True}, {'name': 'only fruit opaque 0', 'passed': True}, {'name': 'stage cached 0', 'passed': True}, {'name': 'explicit surface count 1', 'passed': True}, {'name': 'finite nondegenerate 1', 'passed': True}, {'name': 'exact triangle budget 1', 'passed': True}, {'name': 'bounds footprint 1', 'passed': True}, {'name': 'leaf cutout retained 1', 'passed': True}, {'name': 'only fruit opaque 1', 'passed': True}, {'name': 'stage cached 1', 'passed': True}, {'name': 'explicit surface count 2', 'passed': True}, {'name': 'finite nondegenerate 2', 'passed': True}, {'name': 'exact triangle budget 2', 'passed': True}, {'name': 'bounds footprint 2', 'passed': True}, {'name': 'leaf cutout retained 2', 'passed': True}, {'name': 'only fruit opaque 2', 'passed': True}, {'name': 'stage cached 2', 'passed': True}, {'name': 'explicit surface count 3', 'passed': True}, {'name': 'finite nondegenerate 3', 'passed': True}, {'name': 'exact triangle budget 3', 'passed': True}, {'name': 'bounds footprint 3', 'passed': True}, {'name': 'leaf cutout retained 3', 'passed': True}, {'name': 'only fruit opaque 3', 'passed': True}, {'name': 'stage cached 3', 'passed': True}, {'name': 'strict depletion counts', 'passed': True}, {'name': 'both surfaces remembered', 'passed': True}, {'name': 'separate proxy unaffected', 'passed': True}, {'name': 'input unchanged 50', 'passed': True}, {'name': 'all current surfaces dim 50', 'passed': True}, {'name': 'input unchanged 25', 'passed': True}, {'name': 'all current surfaces dim 25', 'passed': True}, {'name': 'input unchanged 100', 'passed': True}, {'name': 'all current surfaces dim 100', 'passed': True}, {'name': 'all full surfaces restore', 'passed': True}, {'name': 'shared material immutable', 'passed': True}, {'name': 'no physics additions', 'passed': True}], 'failed': 0, 'suite': 'bush_fruit_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['suite'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class BushRuntimeIdentityTests(unittest.TestCase):
    def test_deployed_donor_inputs_bound_and_unrelated_files_excluded(self):
        import subprocess,sys,shutil
        source=Path(__file__).resolve().parents[1]/'game'
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);(root/'scripts').mkdir();(root/'tools').mkdir()
            for n in ('project.godot','main.tscn','main_menu.tscn','export_presets.cfg'):(root/n).write_bytes((source/n).read_bytes())
            (root/'scripts/rules.gd').write_text('const BUILD_ID = "test"\n')
            for n in ('stamp_build.py','runtime_manifest.py'):shutil.copy2(source/'tools'/n,root/'tools'/n)
            folder='assets/diagnostic/bush_common';shutil.copytree(source/folder,root/folder)
            def stamp():
                proc=subprocess.run([sys.executable,'-B',str(root/'tools/stamp_build.py'),'--root',str(root),'--dry-run'],text=True,capture_output=True,check=True)
                d=json.loads(proc.stdout);self.assertEqual(d['writes'],0);return d['manifest']
            base=stamp();paths=base['source_sha256'];expected={str(p.relative_to(root)) for p in (root/folder).iterdir() if p.suffix in ('.gltf','.bin','.png','.import')}
            self.assertTrue(expected);self.assertEqual({p for p in paths if p.startswith(folder+'/')},expected)
            for name in ('Bush_Common.gltf','Bush_Common.bin','Leaves_TwistedTree.png','Leaves_TwistedTree_C.png','Leaves_TwistedTree.png.import','Leaves_TwistedTree_C.png.import','Bush_Common.gltf.import'):
                p=root/folder/name;original=p.read_bytes();p.write_bytes(original+b' identity mutation')
                changed=stamp();self.assertNotEqual(changed['build'],base['build']);self.assertNotEqual(changed['source_sha256'][folder+'/'+name],paths[folder+'/'+name]);p.write_bytes(original)
            for name in ('License_Standard.txt','unrelated.md'):
                (root/folder/name).write_text('source-archive only notice or notes');self.assertEqual(stamp(),base)
            other=root/'assets/diagnostic/unrelated';other.mkdir();(other/'unrelated.png').write_bytes(b'not deployed');self.assertEqual(stamp(),base)


class InitialCameraReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'fresh (640, 360)', 'passed': True}, {'name': 'layout preserves manual (640, 360)', 'passed': True}, {'name': 'resize preserves manual (640, 360)', 'passed': True}, {'name': 'resume preserves manual (640, 360)', 'passed': True}, {'name': 'pan changes focus not zoom (640, 360)', 'passed': True}, {'name': 'pinch min unchanged (640, 360)', 'passed': True}, {'name': 'pinch max unchanged (640, 360)', 'passed': True}, {'name': 'snapshot valid 17.0', 'passed': True}, {'name': 'restore exact manual camera 17.0', 'passed': True}, {'name': 'snapshot valid 35.0', 'passed': True}, {'name': 'restore exact manual camera 35.0', 'passed': True}, {'name': 'explicit override preserved', 'passed': True}, {'name': 'fresh (390, 844)', 'passed': True}, {'name': 'layout preserves manual (390, 844)', 'passed': True}, {'name': 'resize preserves manual (390, 844)', 'passed': True}, {'name': 'resume preserves manual (390, 844)', 'passed': True}, {'name': 'pan changes focus not zoom (390, 844)', 'passed': True}, {'name': 'pinch min unchanged (390, 844)', 'passed': True}, {'name': 'pinch max unchanged (390, 844)', 'passed': True}, {'name': 'snapshot valid 17.0', 'passed': True}, {'name': 'restore exact manual camera 17.0', 'passed': True}, {'name': 'snapshot valid 35.0', 'passed': True}, {'name': 'restore exact manual camera 35.0', 'passed': True}, {'name': 'explicit override preserved', 'passed': True}, {'name': 'fresh (844, 390)', 'passed': True}, {'name': 'layout preserves manual (844, 390)', 'passed': True}, {'name': 'resize preserves manual (844, 390)', 'passed': True}, {'name': 'resume preserves manual (844, 390)', 'passed': True}, {'name': 'pan changes focus not zoom (844, 390)', 'passed': True}, {'name': 'pinch min unchanged (844, 390)', 'passed': True}, {'name': 'pinch max unchanged (844, 390)', 'passed': True}, {'name': 'snapshot valid 17.0', 'passed': True}, {'name': 'restore exact manual camera 17.0', 'passed': True}, {'name': 'snapshot valid 35.0', 'passed': True}, {'name': 'restore exact manual camera 35.0', 'passed': True}, {'name': 'explicit override preserved', 'passed': True}, {'name': 'fresh (1280, 720)', 'passed': True}, {'name': 'layout preserves manual (1280, 720)', 'passed': True}, {'name': 'resize preserves manual (1280, 720)', 'passed': True}, {'name': 'resume preserves manual (1280, 720)', 'passed': True}, {'name': 'pan changes focus not zoom (1280, 720)', 'passed': True}, {'name': 'pinch min unchanged (1280, 720)', 'passed': True}, {'name': 'pinch max unchanged (1280, 720)', 'passed': True}, {'name': 'snapshot valid 17.0', 'passed': True}, {'name': 'restore exact manual camera 17.0', 'passed': True}, {'name': 'snapshot valid 35.0', 'passed': True}, {'name': 'restore exact manual camera 35.0', 'passed': True}, {'name': 'explicit override preserved', 'passed': True}, {'name': 'battle preset focus preserved', 'passed': True}, {'name': 'fortress preset focus preserved', 'passed': True}, {'name': 'breach preset focus preserved', 'passed': True}], 'failed': 0, 'scope': 'new match short viewport camera; headless contract, not physical phone', 'suite': 'compact_initial_camera_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class InitialCameraReportSchemaTests1(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'real start boundary (760, 560)', 'passed': True}, {'name': 'real start boundary (759, 560)', 'passed': True}, {'name': 'real start boundary (760, 559)', 'passed': True}, {'name': 'real restart compact fresh', 'passed': True}, {'name': 'save through actual slot 17.0', 'passed': True}, {'name': 'menu restore preserves 17.0', 'passed': True}, {'name': 'save through actual slot 35.0', 'passed': True}, {'name': 'menu restore preserves 35.0', 'passed': True}, {'name': 'touch world pick 15.0', 'passed': True}, {'name': 'contextual destination without command 15.0', 'passed': True}, {'name': 'touch world pick 22.0', 'passed': True}, {'name': 'contextual destination without command 22.0', 'passed': True}, {'name': 'touch world pick 30.0', 'passed': True}, {'name': 'contextual destination without command 30.0', 'passed': True}], 'failed': 0, 'scope': 'menu start restore and contextual tap paths; headless contract, not physical phone', 'suite': 'compact_camera_routes_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class GatherContactReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'fresh ordinary map provides known legal contact', 'ok': True}, {'name': 'safe actual contact is allowed', 'ok': True}, {'name': 'resource center can be safe while contact is unsafe', 'ok': True}, {'name': 'remembered enemy cannot reject contact', 'ok': True}, {'name': 'absent hidden enemy cannot reject contact', 'ok': True}, {'name': 'dead enemy cannot reject contact', 'ok': True}, {'name': 'own unit does not become threat', 'ok': True}, {'name': 'safe remembered exploration retains existing center policy', 'ok': True}, {'name': 'beyond existing six meter policy remains legal', 'ok': True}, {'name': 'built tower uses existing seven point five margin', 'ok': True}, {'name': 'unfinished tower is not attack threat', 'ok': True}, {'name': 'unoccupied travel advisory delegates ordinary nearest slot', 'ok': True}, {'name': 'policy preserves observation inputs', 'ok': True}, {'name': 'policy preserves complete authority and save schema', 'ok': True}, {'name': 'standing point cannot bypass all unavailable known slots', 'ok': True}, {'name': 'restored known slots allow same contact again', 'ok': True}], 'failed': 0, 'scope': 'Observation-only advisory contact risk; no new slot routing or global safe route guarantee', 'suite': 'ai_gather_contact_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['ok']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class V119ReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'current hostile attack reach creates detached edges', 'ok': True}, {'name': 'no current enemies leaves legacy search unconstrained', 'ok': True}, {'name': 'excluded record { "remembered": true }', 'ok': True}, {'name': 'excluded record { "alive": false }', 'ok': True}, {'name': 'excluded record { "team": 1 }', 'ok': True}, {'name': 'observed built tower contributes original range', 'ok': True}, {'name': 'unbuilt tower cannot contribute attack reach', 'ok': True}, {'name': 'malformed resource tower is not an attacking building', 'ok': True}, {'name': 'outside segment cannot enter attack circle', 'ok': True}, {'name': 'inside circle may escape outward', 'ok': True}, {'name': 'inside circle cannot move deeper', 'ok': True}, {'name': 'offcentre first movement is assessed from actual position', 'ok': True}, {'name': 'overlapping circles cannot erase each others constraints', 'ok': True}, {'name': 'observation insertion order yields identical edges', 'ok': True}, {'name': 'bounded existing search can route around observed threat', 'ok': True}, {'name': 'zero expansion ceiling is not increased', 'ok': True}, {'name': 'risk analysis preserves observations and shared occupancy', 'ok': True}, {'name': 'existing traffic constraint survives union', 'ok': True}, {'name': 'indexed search exactly matches eager result', 'ok': True}, {'name': 'indexed risk preserves zero expansion ceiling', 'ok': True}, {'name': 'indexed risk unions original traffic without mutation', 'ok': True}, {'name': 'empty index leaves legacy result exact', 'ok': True}, {'name': 'index is detached from later observation mutation', 'ok': True}, {'name': 'new index uses same tick changed observations', 'ok': True}, {'name': 'batch canonical memo matches uncached eager route', 'ok': True}, {'name': 'offcentre first edges never reuse canonical cache', 'ok': True}, {'name': 'offcentre query cannot poison another start', 'ok': True}, {'name': 'fresh drain index has no prior canonical memo', 'ok': True}, {'name': 'shared memo stays bounded by map outgoing edges', 'ok': True}], 'failed': 0, 'scope': 'Detached observation-only edge risk and bounded search; actual AI continuation separately evidenced', 'suite': 'ai_worker_route_risk_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['ok']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class V119ReportSchemaTests1(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'exact CPU byte encoding 0', 'passed': True}, {'name': 'CPU encoder does not mutate source 0', 'passed': True}, {'name': 'CPU output does not alias source 0', 'passed': True}, {'name': 'exact CPU byte encoding 1', 'passed': True}, {'name': 'CPU encoder does not mutate source 1', 'passed': True}, {'name': 'CPU output does not alias source 1', 'passed': True}, {'name': 'exact CPU byte encoding 2', 'passed': True}, {'name': 'CPU encoder does not mutate source 2', 'passed': True}, {'name': 'CPU output does not alias source 2', 'passed': True}, {'name': 'exact CPU byte encoding 3', 'passed': True}, {'name': 'CPU encoder does not mutate source 3', 'passed': True}, {'name': 'CPU output does not alias source 3', 'passed': True}, {'name': 'exact CPU byte encoding 4', 'passed': True}, {'name': 'CPU encoder does not mutate source 4', 'passed': True}, {'name': 'CPU output does not alias source 4', 'passed': True}, {'name': 'plane dimensions exact', 'passed': True}, {'name': 'inward width exact', 'passed': True}, {'name': 'overlay height exact', 'passed': True}, {'name': 'shadow casting disabled', 'passed': True}, {'name': 'texture dimensions metadata only', 'passed': True}, {'name': 'separate instances have separate textures', 'passed': True}, {'name': 'first state uploads', 'passed': True}, {'name': 'identical values skip upload', 'passed': True}, {'name': 'texture material resource identities retained', 'passed': True}, {'name': 'cached state owns a copy', 'passed': True}, {'name': 'changed state uploads', 'passed': True}, {'name': 'new state retained exactly', 'passed': True}, {'name': 'same tick replacement array uploads', 'passed': True}, {'name': 'replacement content copied exactly', 'passed': True}, {'name': 'replacement same content cache hit', 'passed': True}, {'name': 'other instance remains uninitialized', 'passed': True}, {'name': 'second instance independently uploads', 'passed': True}, {'name': 'second refresh cannot mutate first', 'passed': True}, {'name': 'original rendered shader visible-only gate retained', 'passed': True}, {'name': 'original rendered shader nearest mask retained', 'passed': True}, {'name': 'original rendered shader cannot write depth', 'passed': True}, {'name': 'presentation node lifecycle releases', 'passed': True}, {'name': 'freeing one instance leaves other intact', 'passed': True}, {'name': 'before authority capture valid', 'passed': True}, {'name': 'after authority capture valid', 'passed': True}, {'name': 'complete valid authority unchanged', 'passed': True}, {'name': 'all team visibility unchanged', 'passed': True}, {'name': 'all team explored unchanged', 'passed': True}, {'name': 'render states unchanged', 'passed': True}, {'name': 'unit fog plane footprint exact', 'passed': True}, {'name': 'existing fog instance count unchanged', 'passed': True}, {'name': 'helper follows existing current states', 'passed': True}, {'name': 'repeat refresh is presentation cache hit', 'passed': True}, {'name': 'game destruction frees attached helper', 'passed': True}, {'name': 'new game has independent initialized helper', 'passed': True}, {'name': 'valid same build paused restore succeeds', 'passed': True}, {'name': 'restore does not advance simulation', 'passed': True}, {'name': 'restore refreshes CPU upload state while paused', 'passed': True}, {'name': 'restored cached state differs from synthetic stale', 'passed': True}, {'name': 'paused same state refresh is cache hit', 'passed': True}, {'name': 'restored game teardown frees helper', 'passed': True}], 'failed': 0, 'scope': 'CPU encoding/cache/lifecycle and valid complete checkpoint equality. No headless GPU readback or framebuffer concealment claim; native evidence is separate.', 'suite': 'fog_inward_edge_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class V120FogTileReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'exact CPU byte encoding 0', 'passed': True}, {'name': 'CPU encoder does not mutate source 0', 'passed': True}, {'name': 'CPU output does not alias source 0', 'passed': True}, {'name': 'exact CPU byte encoding 1', 'passed': True}, {'name': 'CPU encoder does not mutate source 1', 'passed': True}, {'name': 'CPU output does not alias source 1', 'passed': True}, {'name': 'exact CPU byte encoding 2', 'passed': True}, {'name': 'CPU encoder does not mutate source 2', 'passed': True}, {'name': 'CPU output does not alias source 2', 'passed': True}, {'name': 'exact CPU byte encoding 3', 'passed': True}, {'name': 'CPU encoder does not mutate source 3', 'passed': True}, {'name': 'CPU output does not alias source 3', 'passed': True}, {'name': 'exact CPU byte encoding 4', 'passed': True}, {'name': 'CPU encoder does not mutate source 4', 'passed': True}, {'name': 'CPU output does not alias source 4', 'passed': True}, {'name': 'plane dimensions exact', 'passed': True}, {'name': 'inward width exact', 'passed': True}, {'name': 'overlay height exact', 'passed': True}, {'name': 'shadow casting disabled', 'passed': True}, {'name': 'texture dimensions metadata only', 'passed': True}, {'name': 'separate instances have separate textures', 'passed': True}, {'name': 'first state uploads', 'passed': True}, {'name': 'identical values skip upload', 'passed': True}, {'name': 'texture material resource identities retained', 'passed': True}, {'name': 'cached state owns a copy', 'passed': True}, {'name': 'changed state uploads', 'passed': True}, {'name': 'new state retained exactly', 'passed': True}, {'name': 'same tick replacement array uploads', 'passed': True}, {'name': 'replacement content copied exactly', 'passed': True}, {'name': 'replacement same content cache hit', 'passed': True}, {'name': 'other instance remains uninitialized', 'passed': True}, {'name': 'second instance independently uploads', 'passed': True}, {'name': 'second refresh cannot mutate first', 'passed': True}, {'name': 'original rendered shader visible-only gate retained', 'passed': True}, {'name': 'original rendered shader nearest mask retained', 'passed': True}, {'name': 'original rendered shader cannot write depth', 'passed': True}, {'name': 'presentation node lifecycle releases', 'passed': True}, {'name': 'freeing one instance leaves other intact', 'passed': True}, {'name': 'before authority capture valid', 'passed': True}, {'name': 'after authority capture valid', 'passed': True}, {'name': 'complete valid authority unchanged', 'passed': True}, {'name': 'all team visibility unchanged', 'passed': True}, {'name': 'all team explored unchanged', 'passed': True}, {'name': 'render states unchanged', 'passed': True}, {'name': 'new exact unit fog footprint', 'passed': True}, {'name': 'existing fog instance count unchanged', 'passed': True}, {'name': 'helper follows existing current states', 'passed': True}, {'name': 'repeat refresh is presentation cache hit', 'passed': True}, {'name': 'exact lattice construction source retained', 'passed': True}, {'name': 'exact unit tile source bound', 'passed': True}, {'name': 'every entity both faction visibility unchanged', 'passed': True}, {'name': 'game destruction frees attached helper', 'passed': True}, {'name': 'new game has independent initialized helper', 'passed': True}, {'name': 'valid same build paused restore succeeds', 'passed': True}, {'name': 'restore does not advance simulation', 'passed': True}, {'name': 'restore refreshes CPU upload state while paused', 'passed': True}, {'name': 'restored cached state differs from synthetic stale', 'passed': True}, {'name': 'paused same state refresh is cache hit', 'passed': True}, {'name': 'restored game teardown frees helper', 'passed': True}], 'failed': 0, 'scope': 'CPU encoding/cache/lifecycle and valid complete checkpoint equality. No headless GPU readback or framebuffer concealment claim; native evidence is separate.', 'suite': 'fog_unit_tile_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['ok']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class FogTileLegacyLabelTests(unittest.TestCase):
    def test_legacy_overlap_footprint_claim_rejected(self):
        import validate_latest_contracts as validator
        spec=validator.ARMY_CONTRACTS['fog_inward_edge_contract']
        report={'suite':spec['suite'],'scope':spec['scope'],'failed':0,'checks':[{'name':n,'passed':True} for n in spec['names']]}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            (stage/'godot.log').write_text(json.dumps(report)+'\n')
            self.assertEqual(validator.read_report(stage,report['suite']),report)
            report['checks'][44]['name']='existing fog plane footprint unchanged'
            (stage/'godot.log').write_text(json.dumps(report)+'\n')
            with self.assertRaises(ValueError):validator.read_report(stage,report['suite'])

class V121MusterReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'full affordable gap uses existing composition and exact prices', 'passed': True}, {'name': 'pure forecast preserves observations queues and budget', 'passed': True}, {'name': 'empty legal producer set never defaults to free spearman', 'passed': True}, {'name': 'full gap population reserves every future birth', 'passed': True}, {'name': 'affordable first unit but unaffordable full gap refuses', 'passed': True}, {'name': 'exact two villager food reserve is accepted', 'passed': True}, {'name': 'one milli below full gap food reserve refuses', 'passed': True}, {'name': 'moving scout and attacking soldier count toward army cap', 'passed': True}, {'name': 'five living troops prevent further fallback', 'passed': True}, {'name': 'already paid military queue is not purchased again', 'passed': True}, {'name': 'existing worker birth retains priority', 'passed': True}, {'name': 'producer alive required', 'passed': True}, {'name': 'producer built required', 'passed': True}, {'name': 'producer owned required', 'passed': True}, {'name': 'locked cavalry cannot pass age gate', 'passed': True}, {'name': 'full producer queues forbid virtual training', 'passed': True}, {'name': 'remembered enemy cannot alter composition forecast', 'passed': True}, {'name': 'controlled fixture has four troops and farm assignments', 'passed': True}, {'name': 'other primary goal never diverted', 'passed': True}, {'name': 'affordable farm always retains priority', 'passed': True}, {'name': 'disabled AI cannot use fallback', 'passed': True}, {'name': 'paused game cannot use fallback', 'passed': True}, {'name': 'practice does not buy offensive muster', 'passed': True}, {'name': 'terminal food worker is not operating floor', 'passed': True}, {'name': 'pending own economic commitment blocks fallback', 'passed': True}, {'name': 'pending military research cannot spend forecast reserve twice', 'passed': True}, {'name': 'negative guards neither pay nor reserve', 'passed': True}, {'name': 'eligible fallback submits one ordinary train', 'passed': True}, {'name': 'forecast did not debit bank before execution', 'passed': True}, {'name': 'pending same birth is not double counted or duplicated', 'passed': True}, {'name': 'ordinary pending train strict same build transport', 'passed': True}, {'name': 'pending train restores without custom schema', 'passed': True}, {'name': 'restored normal execution preserves full authority', 'passed': True}, {'name': 'real queue paid exact normal spear cost once', 'passed': True}, {'name': 'ordinary training ticks produce exactly one real troop', 'passed': True}, {'name': 'normal payment and farm ledgers remain conserved', 'passed': True}], 'failed': 0, 'scope': 'Pure full-gap planning negatives; controlled initial farm/army fixture with ordinary paid training and strict restore, not natural military or economy success', 'suite': 'ai_muster_fallback_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['ok']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class V122MeasuredTopbarReportSchemaTests0(unittest.TestCase):
    """Frozen engine report; malformed parser fixtures are not gameplay evidence."""
    def test_exact_report_and_all_rows_fail_closed(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': '000 fresh own keep exists', 'passed': True}, {'name': '001 controlled integer bank initialized', 'passed': True}, {'name': '002 actual four-resource bank exact (640, 360) high=false', 'passed': True}, {'name': '003 640 actual measured fallback false', 'passed': True}, {'name': '004 (640, 360) high=false inside resources', 'passed': True}, {'name': '005 (640, 360) high=false panel encloses resources', 'passed': True}, {'name': '006 (640, 360) high=false font readable resources', 'passed': True}, {'name': '007 (640, 360) high=false inside clock', 'passed': True}, {'name': '008 (640, 360) high=false panel encloses clock', 'passed': True}, {'name': '009 (640, 360) high=false font readable clock', 'passed': True}, {'name': '010 (640, 360) high=false inside pause', 'passed': True}, {'name': '011 (640, 360) high=false panel encloses pause', 'passed': True}, {'name': '012 (640, 360) high=false font readable pause', 'passed': True}, {'name': '013 (640, 360) high=false touch46 pause', 'passed': True}, {'name': '014 (640, 360) high=false inside alert', 'passed': True}, {'name': '015 (640, 360) high=false panel encloses alert', 'passed': True}, {'name': '016 (640, 360) high=false font readable alert', 'passed': True}, {'name': '017 (640, 360) high=false touch46 alert', 'passed': True}, {'name': '018 (640, 360) high=false inside menu', 'passed': True}, {'name': '019 (640, 360) high=false panel encloses menu', 'passed': True}, {'name': '020 (640, 360) high=false font readable menu', 'passed': True}, {'name': '021 (640, 360) high=false touch46 menu', 'passed': True}, {'name': '022 (640, 360) high=false disjoint 0/1', 'passed': True}, {'name': '023 (640, 360) high=false disjoint 0/2', 'passed': True}, {'name': '024 (640, 360) high=false disjoint 0/3', 'passed': True}, {'name': '025 (640, 360) high=false disjoint 0/4', 'passed': True}, {'name': '026 (640, 360) high=false disjoint 1/2', 'passed': True}, {'name': '027 (640, 360) high=false disjoint 1/3', 'passed': True}, {'name': '028 (640, 360) high=false disjoint 1/4', 'passed': True}, {'name': '029 (640, 360) high=false disjoint 2/3', 'passed': True}, {'name': '030 (640, 360) high=false disjoint 2/4', 'passed': True}, {'name': '031 (640, 360) high=false disjoint 3/4', 'passed': True}, {'name': '032 (640, 360) high=false routed alert acknowledges', 'passed': True}, {'name': '033 (640, 360) high=false routed pause', 'passed': True}, {'name': '034 (640, 360) high=false paused alert disabled', 'passed': True}, {'name': '035 (640, 360) high=false paused alert no acknowledgement', 'passed': True}, {'name': '036 (640, 360) high=false routed resume', 'passed': True}, {'name': '037 (640, 360) high=false routed menu', 'passed': True}, {'name': '038 (640, 360) high=false routed close', 'passed': True}, {'name': '039 controlled integer bank initialized', 'passed': True}, {'name': '040 actual four-resource bank exact (640, 360) high=true', 'passed': True}, {'name': '041 640 actual measured fallback true', 'passed': True}, {'name': '042 (640, 360) high=true inside resources', 'passed': True}, {'name': '043 (640, 360) high=true panel encloses resources', 'passed': True}, {'name': '044 (640, 360) high=true font readable resources', 'passed': True}, {'name': '045 (640, 360) high=true inside clock', 'passed': True}, {'name': '046 (640, 360) high=true panel encloses clock', 'passed': True}, {'name': '047 (640, 360) high=true font readable clock', 'passed': True}, {'name': '048 (640, 360) high=true inside pause', 'passed': True}, {'name': '049 (640, 360) high=true panel encloses pause', 'passed': True}, {'name': '050 (640, 360) high=true font readable pause', 'passed': True}, {'name': '051 (640, 360) high=true touch46 pause', 'passed': True}, {'name': '052 (640, 360) high=true inside alert', 'passed': True}, {'name': '053 (640, 360) high=true panel encloses alert', 'passed': True}, {'name': '054 (640, 360) high=true font readable alert', 'passed': True}, {'name': '055 (640, 360) high=true touch46 alert', 'passed': True}, {'name': '056 (640, 360) high=true inside menu', 'passed': True}, {'name': '057 (640, 360) high=true panel encloses menu', 'passed': True}, {'name': '058 (640, 360) high=true font readable menu', 'passed': True}, {'name': '059 (640, 360) high=true touch46 menu', 'passed': True}, {'name': '060 (640, 360) high=true disjoint 0/1', 'passed': True}, {'name': '061 (640, 360) high=true disjoint 0/2', 'passed': True}, {'name': '062 (640, 360) high=true disjoint 0/3', 'passed': True}, {'name': '063 (640, 360) high=true disjoint 0/4', 'passed': True}, {'name': '064 (640, 360) high=true disjoint 1/2', 'passed': True}, {'name': '065 (640, 360) high=true disjoint 1/3', 'passed': True}, {'name': '066 (640, 360) high=true disjoint 1/4', 'passed': True}, {'name': '067 (640, 360) high=true disjoint 2/3', 'passed': True}, {'name': '068 (640, 360) high=true disjoint 2/4', 'passed': True}, {'name': '069 (640, 360) high=true disjoint 3/4', 'passed': True}, {'name': '070 (640, 360) high=true routed alert acknowledges', 'passed': True}, {'name': '071 (640, 360) high=true routed pause', 'passed': True}, {'name': '072 (640, 360) high=true paused alert disabled', 'passed': True}, {'name': '073 (640, 360) high=true paused alert no acknowledgement', 'passed': True}, {'name': '074 (640, 360) high=true routed resume', 'passed': True}, {'name': '075 (640, 360) high=true routed menu', 'passed': True}, {'name': '076 (640, 360) high=true routed close', 'passed': True}, {'name': '077 controlled integer bank initialized', 'passed': True}, {'name': '078 actual four-resource bank exact (667, 375) high=false', 'passed': True}, {'name': '079 (667, 375) high=false inside resources', 'passed': True}, {'name': '080 (667, 375) high=false panel encloses resources', 'passed': True}, {'name': '081 (667, 375) high=false font readable resources', 'passed': True}, {'name': '082 (667, 375) high=false inside clock', 'passed': True}, {'name': '083 (667, 375) high=false panel encloses clock', 'passed': True}, {'name': '084 (667, 375) high=false font readable clock', 'passed': True}, {'name': '085 (667, 375) high=false inside pause', 'passed': True}, {'name': '086 (667, 375) high=false panel encloses pause', 'passed': True}, {'name': '087 (667, 375) high=false font readable pause', 'passed': True}, {'name': '088 (667, 375) high=false touch46 pause', 'passed': True}, {'name': '089 (667, 375) high=false inside alert', 'passed': True}, {'name': '090 (667, 375) high=false panel encloses alert', 'passed': True}, {'name': '091 (667, 375) high=false font readable alert', 'passed': True}, {'name': '092 (667, 375) high=false touch46 alert', 'passed': True}, {'name': '093 (667, 375) high=false inside menu', 'passed': True}, {'name': '094 (667, 375) high=false panel encloses menu', 'passed': True}, {'name': '095 (667, 375) high=false font readable menu', 'passed': True}, {'name': '096 (667, 375) high=false touch46 menu', 'passed': True}, {'name': '097 (667, 375) high=false disjoint 0/1', 'passed': True}, {'name': '098 (667, 375) high=false disjoint 0/2', 'passed': True}, {'name': '099 (667, 375) high=false disjoint 0/3', 'passed': True}, {'name': '100 (667, 375) high=false disjoint 0/4', 'passed': True}, {'name': '101 (667, 375) high=false disjoint 1/2', 'passed': True}, {'name': '102 (667, 375) high=false disjoint 1/3', 'passed': True}, {'name': '103 (667, 375) high=false disjoint 1/4', 'passed': True}, {'name': '104 (667, 375) high=false disjoint 2/3', 'passed': True}, {'name': '105 (667, 375) high=false disjoint 2/4', 'passed': True}, {'name': '106 (667, 375) high=false disjoint 3/4', 'passed': True}, {'name': '107 (667, 375) high=false routed alert acknowledges', 'passed': True}, {'name': '108 (667, 375) high=false routed pause', 'passed': True}, {'name': '109 (667, 375) high=false paused alert disabled', 'passed': True}, {'name': '110 (667, 375) high=false paused alert no acknowledgement', 'passed': True}, {'name': '111 (667, 375) high=false routed resume', 'passed': True}, {'name': '112 (667, 375) high=false routed menu', 'passed': True}, {'name': '113 (667, 375) high=false routed close', 'passed': True}, {'name': '114 controlled integer bank initialized', 'passed': True}, {'name': '115 actual four-resource bank exact (667, 375) high=true', 'passed': True}, {'name': '116 (667, 375) high=true inside resources', 'passed': True}, {'name': '117 (667, 375) high=true panel encloses resources', 'passed': True}, {'name': '118 (667, 375) high=true font readable resources', 'passed': True}, {'name': '119 (667, 375) high=true inside clock', 'passed': True}, {'name': '120 (667, 375) high=true panel encloses clock', 'passed': True}, {'name': '121 (667, 375) high=true font readable clock', 'passed': True}, {'name': '122 (667, 375) high=true inside pause', 'passed': True}, {'name': '123 (667, 375) high=true panel encloses pause', 'passed': True}, {'name': '124 (667, 375) high=true font readable pause', 'passed': True}, {'name': '125 (667, 375) high=true touch46 pause', 'passed': True}, {'name': '126 (667, 375) high=true inside alert', 'passed': True}, {'name': '127 (667, 375) high=true panel encloses alert', 'passed': True}, {'name': '128 (667, 375) high=true font readable alert', 'passed': True}, {'name': '129 (667, 375) high=true touch46 alert', 'passed': True}, {'name': '130 (667, 375) high=true inside menu', 'passed': True}, {'name': '131 (667, 375) high=true panel encloses menu', 'passed': True}, {'name': '132 (667, 375) high=true font readable menu', 'passed': True}, {'name': '133 (667, 375) high=true touch46 menu', 'passed': True}, {'name': '134 (667, 375) high=true disjoint 0/1', 'passed': True}, {'name': '135 (667, 375) high=true disjoint 0/2', 'passed': True}, {'name': '136 (667, 375) high=true disjoint 0/3', 'passed': True}, {'name': '137 (667, 375) high=true disjoint 0/4', 'passed': True}, {'name': '138 (667, 375) high=true disjoint 1/2', 'passed': True}, {'name': '139 (667, 375) high=true disjoint 1/3', 'passed': True}, {'name': '140 (667, 375) high=true disjoint 1/4', 'passed': True}, {'name': '141 (667, 375) high=true disjoint 2/3', 'passed': True}, {'name': '142 (667, 375) high=true disjoint 2/4', 'passed': True}, {'name': '143 (667, 375) high=true disjoint 3/4', 'passed': True}, {'name': '144 (667, 375) high=true routed alert acknowledges', 'passed': True}, {'name': '145 (667, 375) high=true routed pause', 'passed': True}, {'name': '146 (667, 375) high=true paused alert disabled', 'passed': True}, {'name': '147 (667, 375) high=true paused alert no acknowledgement', 'passed': True}, {'name': '148 (667, 375) high=true routed resume', 'passed': True}, {'name': '149 (667, 375) high=true routed menu', 'passed': True}, {'name': '150 (667, 375) high=true routed close', 'passed': True}, {'name': '151 controlled integer bank initialized', 'passed': True}, {'name': '152 actual four-resource bank exact (740, 360) high=false', 'passed': True}, {'name': '153 (740, 360) high=false inside resources', 'passed': True}, {'name': '154 (740, 360) high=false panel encloses resources', 'passed': True}, {'name': '155 (740, 360) high=false font readable resources', 'passed': True}, {'name': '156 (740, 360) high=false inside clock', 'passed': True}, {'name': '157 (740, 360) high=false panel encloses clock', 'passed': True}, {'name': '158 (740, 360) high=false font readable clock', 'passed': True}, {'name': '159 (740, 360) high=false inside pause', 'passed': True}, {'name': '160 (740, 360) high=false panel encloses pause', 'passed': True}, {'name': '161 (740, 360) high=false font readable pause', 'passed': True}, {'name': '162 (740, 360) high=false touch46 pause', 'passed': True}, {'name': '163 (740, 360) high=false inside alert', 'passed': True}, {'name': '164 (740, 360) high=false panel encloses alert', 'passed': True}, {'name': '165 (740, 360) high=false font readable alert', 'passed': True}, {'name': '166 (740, 360) high=false touch46 alert', 'passed': True}, {'name': '167 (740, 360) high=false inside menu', 'passed': True}, {'name': '168 (740, 360) high=false panel encloses menu', 'passed': True}, {'name': '169 (740, 360) high=false font readable menu', 'passed': True}, {'name': '170 (740, 360) high=false touch46 menu', 'passed': True}, {'name': '171 (740, 360) high=false disjoint 0/1', 'passed': True}, {'name': '172 (740, 360) high=false disjoint 0/2', 'passed': True}, {'name': '173 (740, 360) high=false disjoint 0/3', 'passed': True}, {'name': '174 (740, 360) high=false disjoint 0/4', 'passed': True}, {'name': '175 (740, 360) high=false disjoint 1/2', 'passed': True}, {'name': '176 (740, 360) high=false disjoint 1/3', 'passed': True}, {'name': '177 (740, 360) high=false disjoint 1/4', 'passed': True}, {'name': '178 (740, 360) high=false disjoint 2/3', 'passed': True}, {'name': '179 (740, 360) high=false disjoint 2/4', 'passed': True}, {'name': '180 (740, 360) high=false disjoint 3/4', 'passed': True}, {'name': '181 (740, 360) high=false routed alert acknowledges', 'passed': True}, {'name': '182 (740, 360) high=false routed pause', 'passed': True}, {'name': '183 (740, 360) high=false paused alert disabled', 'passed': True}, {'name': '184 (740, 360) high=false paused alert no acknowledgement', 'passed': True}, {'name': '185 (740, 360) high=false routed resume', 'passed': True}, {'name': '186 (740, 360) high=false routed menu', 'passed': True}, {'name': '187 (740, 360) high=false routed close', 'passed': True}, {'name': '188 controlled integer bank initialized', 'passed': True}, {'name': '189 actual four-resource bank exact (740, 360) high=true', 'passed': True}, {'name': '190 (740, 360) high=true inside resources', 'passed': True}, {'name': '191 (740, 360) high=true panel encloses resources', 'passed': True}, {'name': '192 (740, 360) high=true font readable resources', 'passed': True}, {'name': '193 (740, 360) high=true inside clock', 'passed': True}, {'name': '194 (740, 360) high=true panel encloses clock', 'passed': True}, {'name': '195 (740, 360) high=true font readable clock', 'passed': True}, {'name': '196 (740, 360) high=true inside pause', 'passed': True}, {'name': '197 (740, 360) high=true panel encloses pause', 'passed': True}, {'name': '198 (740, 360) high=true font readable pause', 'passed': True}, {'name': '199 (740, 360) high=true touch46 pause', 'passed': True}, {'name': '200 (740, 360) high=true inside alert', 'passed': True}, {'name': '201 (740, 360) high=true panel encloses alert', 'passed': True}, {'name': '202 (740, 360) high=true font readable alert', 'passed': True}, {'name': '203 (740, 360) high=true touch46 alert', 'passed': True}, {'name': '204 (740, 360) high=true inside menu', 'passed': True}, {'name': '205 (740, 360) high=true panel encloses menu', 'passed': True}, {'name': '206 (740, 360) high=true font readable menu', 'passed': True}, {'name': '207 (740, 360) high=true touch46 menu', 'passed': True}, {'name': '208 (740, 360) high=true disjoint 0/1', 'passed': True}, {'name': '209 (740, 360) high=true disjoint 0/2', 'passed': True}, {'name': '210 (740, 360) high=true disjoint 0/3', 'passed': True}, {'name': '211 (740, 360) high=true disjoint 0/4', 'passed': True}, {'name': '212 (740, 360) high=true disjoint 1/2', 'passed': True}, {'name': '213 (740, 360) high=true disjoint 1/3', 'passed': True}, {'name': '214 (740, 360) high=true disjoint 1/4', 'passed': True}, {'name': '215 (740, 360) high=true disjoint 2/3', 'passed': True}, {'name': '216 (740, 360) high=true disjoint 2/4', 'passed': True}, {'name': '217 (740, 360) high=true disjoint 3/4', 'passed': True}, {'name': '218 (740, 360) high=true routed alert acknowledges', 'passed': True}, {'name': '219 (740, 360) high=true routed pause', 'passed': True}, {'name': '220 (740, 360) high=true paused alert disabled', 'passed': True}, {'name': '221 (740, 360) high=true paused alert no acknowledgement', 'passed': True}, {'name': '222 (740, 360) high=true routed resume', 'passed': True}, {'name': '223 (740, 360) high=true routed menu', 'passed': True}, {'name': '224 (740, 360) high=true routed close', 'passed': True}, {'name': '225 controlled integer bank initialized', 'passed': True}, {'name': '226 actual four-resource bank exact (844, 390) high=false', 'passed': True}, {'name': '227 (844, 390) high=false inside resources', 'passed': True}, {'name': '228 (844, 390) high=false panel encloses resources', 'passed': True}, {'name': '229 (844, 390) high=false font readable resources', 'passed': True}, {'name': '230 (844, 390) high=false inside clock', 'passed': True}, {'name': '231 (844, 390) high=false panel encloses clock', 'passed': True}, {'name': '232 (844, 390) high=false font readable clock', 'passed': True}, {'name': '233 (844, 390) high=false inside pause', 'passed': True}, {'name': '234 (844, 390) high=false panel encloses pause', 'passed': True}, {'name': '235 (844, 390) high=false font readable pause', 'passed': True}, {'name': '236 (844, 390) high=false touch46 pause', 'passed': True}, {'name': '237 (844, 390) high=false inside alert', 'passed': True}, {'name': '238 (844, 390) high=false panel encloses alert', 'passed': True}, {'name': '239 (844, 390) high=false font readable alert', 'passed': True}, {'name': '240 (844, 390) high=false touch46 alert', 'passed': True}, {'name': '241 (844, 390) high=false inside menu', 'passed': True}, {'name': '242 (844, 390) high=false panel encloses menu', 'passed': True}, {'name': '243 (844, 390) high=false font readable menu', 'passed': True}, {'name': '244 (844, 390) high=false touch46 menu', 'passed': True}, {'name': '245 (844, 390) high=false disjoint 0/1', 'passed': True}, {'name': '246 (844, 390) high=false disjoint 0/2', 'passed': True}, {'name': '247 (844, 390) high=false disjoint 0/3', 'passed': True}, {'name': '248 (844, 390) high=false disjoint 0/4', 'passed': True}, {'name': '249 (844, 390) high=false disjoint 1/2', 'passed': True}, {'name': '250 (844, 390) high=false disjoint 1/3', 'passed': True}, {'name': '251 (844, 390) high=false disjoint 1/4', 'passed': True}, {'name': '252 (844, 390) high=false disjoint 2/3', 'passed': True}, {'name': '253 (844, 390) high=false disjoint 2/4', 'passed': True}, {'name': '254 (844, 390) high=false disjoint 3/4', 'passed': True}, {'name': '255 (844, 390) high=false routed alert acknowledges', 'passed': True}, {'name': '256 (844, 390) high=false routed pause', 'passed': True}, {'name': '257 (844, 390) high=false paused alert disabled', 'passed': True}, {'name': '258 (844, 390) high=false paused alert no acknowledgement', 'passed': True}, {'name': '259 (844, 390) high=false routed resume', 'passed': True}, {'name': '260 (844, 390) high=false routed menu', 'passed': True}, {'name': '261 (844, 390) high=false routed close', 'passed': True}, {'name': '262 controlled integer bank initialized', 'passed': True}, {'name': '263 actual four-resource bank exact (844, 390) high=true', 'passed': True}, {'name': '264 (844, 390) high=true inside resources', 'passed': True}, {'name': '265 (844, 390) high=true panel encloses resources', 'passed': True}, {'name': '266 (844, 390) high=true font readable resources', 'passed': True}, {'name': '267 (844, 390) high=true inside clock', 'passed': True}, {'name': '268 (844, 390) high=true panel encloses clock', 'passed': True}, {'name': '269 (844, 390) high=true font readable clock', 'passed': True}, {'name': '270 (844, 390) high=true inside pause', 'passed': True}, {'name': '271 (844, 390) high=true panel encloses pause', 'passed': True}, {'name': '272 (844, 390) high=true font readable pause', 'passed': True}, {'name': '273 (844, 390) high=true touch46 pause', 'passed': True}, {'name': '274 (844, 390) high=true inside alert', 'passed': True}, {'name': '275 (844, 390) high=true panel encloses alert', 'passed': True}, {'name': '276 (844, 390) high=true font readable alert', 'passed': True}, {'name': '277 (844, 390) high=true touch46 alert', 'passed': True}, {'name': '278 (844, 390) high=true inside menu', 'passed': True}, {'name': '279 (844, 390) high=true panel encloses menu', 'passed': True}, {'name': '280 (844, 390) high=true font readable menu', 'passed': True}, {'name': '281 (844, 390) high=true touch46 menu', 'passed': True}, {'name': '282 (844, 390) high=true disjoint 0/1', 'passed': True}, {'name': '283 (844, 390) high=true disjoint 0/2', 'passed': True}, {'name': '284 (844, 390) high=true disjoint 0/3', 'passed': True}, {'name': '285 (844, 390) high=true disjoint 0/4', 'passed': True}, {'name': '286 (844, 390) high=true disjoint 1/2', 'passed': True}, {'name': '287 (844, 390) high=true disjoint 1/3', 'passed': True}, {'name': '288 (844, 390) high=true disjoint 1/4', 'passed': True}, {'name': '289 (844, 390) high=true disjoint 2/3', 'passed': True}, {'name': '290 (844, 390) high=true disjoint 2/4', 'passed': True}, {'name': '291 (844, 390) high=true disjoint 3/4', 'passed': True}, {'name': '292 (844, 390) high=true routed alert acknowledges', 'passed': True}, {'name': '293 (844, 390) high=true routed pause', 'passed': True}, {'name': '294 (844, 390) high=true paused alert disabled', 'passed': True}, {'name': '295 (844, 390) high=true paused alert no acknowledgement', 'passed': True}, {'name': '296 (844, 390) high=true routed resume', 'passed': True}, {'name': '297 (844, 390) high=true routed menu', 'passed': True}, {'name': '298 (844, 390) high=true routed close', 'passed': True}, {'name': '299 controlled integer bank initialized', 'passed': True}, {'name': '300 actual four-resource bank exact (390, 844) high=false', 'passed': True}, {'name': '301 (390, 844) high=false inside resources', 'passed': True}, {'name': '302 (390, 844) high=false panel encloses resources', 'passed': True}, {'name': '303 (390, 844) high=false font readable resources', 'passed': True}, {'name': '304 (390, 844) high=false inside clock', 'passed': True}, {'name': '305 (390, 844) high=false panel encloses clock', 'passed': True}, {'name': '306 (390, 844) high=false font readable clock', 'passed': True}, {'name': '307 (390, 844) high=false inside pause', 'passed': True}, {'name': '308 (390, 844) high=false panel encloses pause', 'passed': True}, {'name': '309 (390, 844) high=false font readable pause', 'passed': True}, {'name': '310 (390, 844) high=false touch46 pause', 'passed': True}, {'name': '311 (390, 844) high=false inside alert', 'passed': True}, {'name': '312 (390, 844) high=false panel encloses alert', 'passed': True}, {'name': '313 (390, 844) high=false font readable alert', 'passed': True}, {'name': '314 (390, 844) high=false touch46 alert', 'passed': True}, {'name': '315 (390, 844) high=false inside menu', 'passed': True}, {'name': '316 (390, 844) high=false panel encloses menu', 'passed': True}, {'name': '317 (390, 844) high=false font readable menu', 'passed': True}, {'name': '318 (390, 844) high=false touch46 menu', 'passed': True}, {'name': '319 (390, 844) high=false disjoint 0/1', 'passed': True}, {'name': '320 (390, 844) high=false disjoint 0/2', 'passed': True}, {'name': '321 (390, 844) high=false disjoint 0/3', 'passed': True}, {'name': '322 (390, 844) high=false disjoint 0/4', 'passed': True}, {'name': '323 (390, 844) high=false disjoint 1/2', 'passed': True}, {'name': '324 (390, 844) high=false disjoint 1/3', 'passed': True}, {'name': '325 (390, 844) high=false disjoint 1/4', 'passed': True}, {'name': '326 (390, 844) high=false disjoint 2/3', 'passed': True}, {'name': '327 (390, 844) high=false disjoint 2/4', 'passed': True}, {'name': '328 (390, 844) high=false disjoint 3/4', 'passed': True}, {'name': '329 (390, 844) high=false routed alert acknowledges', 'passed': True}, {'name': '330 (390, 844) high=false routed pause', 'passed': True}, {'name': '331 (390, 844) high=false paused alert disabled', 'passed': True}, {'name': '332 (390, 844) high=false paused alert no acknowledgement', 'passed': True}, {'name': '333 (390, 844) high=false routed resume', 'passed': True}, {'name': '334 (390, 844) high=false routed menu', 'passed': True}, {'name': '335 (390, 844) high=false routed close', 'passed': True}, {'name': '336 controlled integer bank initialized', 'passed': True}, {'name': '337 actual four-resource bank exact (390, 844) high=true', 'passed': True}, {'name': '338 (390, 844) high=true inside resources', 'passed': True}, {'name': '339 (390, 844) high=true panel encloses resources', 'passed': True}, {'name': '340 (390, 844) high=true font readable resources', 'passed': True}, {'name': '341 (390, 844) high=true inside clock', 'passed': True}, {'name': '342 (390, 844) high=true panel encloses clock', 'passed': True}, {'name': '343 (390, 844) high=true font readable clock', 'passed': True}, {'name': '344 (390, 844) high=true inside pause', 'passed': True}, {'name': '345 (390, 844) high=true panel encloses pause', 'passed': True}, {'name': '346 (390, 844) high=true font readable pause', 'passed': True}, {'name': '347 (390, 844) high=true touch46 pause', 'passed': True}, {'name': '348 (390, 844) high=true inside alert', 'passed': True}, {'name': '349 (390, 844) high=true panel encloses alert', 'passed': True}, {'name': '350 (390, 844) high=true font readable alert', 'passed': True}, {'name': '351 (390, 844) high=true touch46 alert', 'passed': True}, {'name': '352 (390, 844) high=true inside menu', 'passed': True}, {'name': '353 (390, 844) high=true panel encloses menu', 'passed': True}, {'name': '354 (390, 844) high=true font readable menu', 'passed': True}, {'name': '355 (390, 844) high=true touch46 menu', 'passed': True}, {'name': '356 (390, 844) high=true disjoint 0/1', 'passed': True}, {'name': '357 (390, 844) high=true disjoint 0/2', 'passed': True}, {'name': '358 (390, 844) high=true disjoint 0/3', 'passed': True}, {'name': '359 (390, 844) high=true disjoint 0/4', 'passed': True}, {'name': '360 (390, 844) high=true disjoint 1/2', 'passed': True}, {'name': '361 (390, 844) high=true disjoint 1/3', 'passed': True}, {'name': '362 (390, 844) high=true disjoint 1/4', 'passed': True}, {'name': '363 (390, 844) high=true disjoint 2/3', 'passed': True}, {'name': '364 (390, 844) high=true disjoint 2/4', 'passed': True}, {'name': '365 (390, 844) high=true disjoint 3/4', 'passed': True}, {'name': '366 (390, 844) high=true routed alert acknowledges', 'passed': True}, {'name': '367 (390, 844) high=true routed pause', 'passed': True}, {'name': '368 (390, 844) high=true paused alert disabled', 'passed': True}, {'name': '369 (390, 844) high=true paused alert no acknowledgement', 'passed': True}, {'name': '370 (390, 844) high=true routed resume', 'passed': True}, {'name': '371 (390, 844) high=true routed menu', 'passed': True}, {'name': '372 (390, 844) high=true routed close', 'passed': True}, {'name': '373 controlled integer bank initialized', 'passed': True}, {'name': '374 actual four-resource bank exact (430, 932) high=false', 'passed': True}, {'name': '375 (430, 932) high=false inside resources', 'passed': True}, {'name': '376 (430, 932) high=false panel encloses resources', 'passed': True}, {'name': '377 (430, 932) high=false font readable resources', 'passed': True}, {'name': '378 (430, 932) high=false inside clock', 'passed': True}, {'name': '379 (430, 932) high=false panel encloses clock', 'passed': True}, {'name': '380 (430, 932) high=false font readable clock', 'passed': True}, {'name': '381 (430, 932) high=false inside pause', 'passed': True}, {'name': '382 (430, 932) high=false panel encloses pause', 'passed': True}, {'name': '383 (430, 932) high=false font readable pause', 'passed': True}, {'name': '384 (430, 932) high=false touch46 pause', 'passed': True}, {'name': '385 (430, 932) high=false inside alert', 'passed': True}, {'name': '386 (430, 932) high=false panel encloses alert', 'passed': True}, {'name': '387 (430, 932) high=false font readable alert', 'passed': True}, {'name': '388 (430, 932) high=false touch46 alert', 'passed': True}, {'name': '389 (430, 932) high=false inside menu', 'passed': True}, {'name': '390 (430, 932) high=false panel encloses menu', 'passed': True}, {'name': '391 (430, 932) high=false font readable menu', 'passed': True}, {'name': '392 (430, 932) high=false touch46 menu', 'passed': True}, {'name': '393 (430, 932) high=false disjoint 0/1', 'passed': True}, {'name': '394 (430, 932) high=false disjoint 0/2', 'passed': True}, {'name': '395 (430, 932) high=false disjoint 0/3', 'passed': True}, {'name': '396 (430, 932) high=false disjoint 0/4', 'passed': True}, {'name': '397 (430, 932) high=false disjoint 1/2', 'passed': True}, {'name': '398 (430, 932) high=false disjoint 1/3', 'passed': True}, {'name': '399 (430, 932) high=false disjoint 1/4', 'passed': True}, {'name': '400 (430, 932) high=false disjoint 2/3', 'passed': True}, {'name': '401 (430, 932) high=false disjoint 2/4', 'passed': True}, {'name': '402 (430, 932) high=false disjoint 3/4', 'passed': True}, {'name': '403 (430, 932) high=false routed alert acknowledges', 'passed': True}, {'name': '404 (430, 932) high=false routed pause', 'passed': True}, {'name': '405 (430, 932) high=false paused alert disabled', 'passed': True}, {'name': '406 (430, 932) high=false paused alert no acknowledgement', 'passed': True}, {'name': '407 (430, 932) high=false routed resume', 'passed': True}, {'name': '408 (430, 932) high=false routed menu', 'passed': True}, {'name': '409 (430, 932) high=false routed close', 'passed': True}, {'name': '410 controlled integer bank initialized', 'passed': True}, {'name': '411 actual four-resource bank exact (430, 932) high=true', 'passed': True}, {'name': '412 (430, 932) high=true inside resources', 'passed': True}, {'name': '413 (430, 932) high=true panel encloses resources', 'passed': True}, {'name': '414 (430, 932) high=true font readable resources', 'passed': True}, {'name': '415 (430, 932) high=true inside clock', 'passed': True}, {'name': '416 (430, 932) high=true panel encloses clock', 'passed': True}, {'name': '417 (430, 932) high=true font readable clock', 'passed': True}, {'name': '418 (430, 932) high=true inside pause', 'passed': True}, {'name': '419 (430, 932) high=true panel encloses pause', 'passed': True}, {'name': '420 (430, 932) high=true font readable pause', 'passed': True}, {'name': '421 (430, 932) high=true touch46 pause', 'passed': True}, {'name': '422 (430, 932) high=true inside alert', 'passed': True}, {'name': '423 (430, 932) high=true panel encloses alert', 'passed': True}, {'name': '424 (430, 932) high=true font readable alert', 'passed': True}, {'name': '425 (430, 932) high=true touch46 alert', 'passed': True}, {'name': '426 (430, 932) high=true inside menu', 'passed': True}, {'name': '427 (430, 932) high=true panel encloses menu', 'passed': True}, {'name': '428 (430, 932) high=true font readable menu', 'passed': True}, {'name': '429 (430, 932) high=true touch46 menu', 'passed': True}, {'name': '430 (430, 932) high=true disjoint 0/1', 'passed': True}, {'name': '431 (430, 932) high=true disjoint 0/2', 'passed': True}, {'name': '432 (430, 932) high=true disjoint 0/3', 'passed': True}, {'name': '433 (430, 932) high=true disjoint 0/4', 'passed': True}, {'name': '434 (430, 932) high=true disjoint 1/2', 'passed': True}, {'name': '435 (430, 932) high=true disjoint 1/3', 'passed': True}, {'name': '436 (430, 932) high=true disjoint 1/4', 'passed': True}, {'name': '437 (430, 932) high=true disjoint 2/3', 'passed': True}, {'name': '438 (430, 932) high=true disjoint 2/4', 'passed': True}, {'name': '439 (430, 932) high=true disjoint 3/4', 'passed': True}, {'name': '440 (430, 932) high=true routed alert acknowledges', 'passed': True}, {'name': '441 (430, 932) high=true routed pause', 'passed': True}, {'name': '442 (430, 932) high=true paused alert disabled', 'passed': True}, {'name': '443 (430, 932) high=true paused alert no acknowledgement', 'passed': True}, {'name': '444 (430, 932) high=true routed resume', 'passed': True}, {'name': '445 (430, 932) high=true routed menu', 'passed': True}, {'name': '446 (430, 932) high=true routed close', 'passed': True}, {'name': '447 dynamic bank init', 'passed': True}, {'name': '448 deferred all observed frames valid [640, false, 4, false]', 'passed': True}, {'name': '449 deferred final valid [640, false, 4, false]', 'passed': True}, {'name': '450 deferred settled stable [640, false, 4, false]', 'passed': True}, {'name': '451 dynamic bank init', 'passed': True}, {'name': '452 deferred all observed frames valid [640, true, 4, false]', 'passed': True}, {'name': '453 deferred final valid [640, true, 4, false]', 'passed': True}, {'name': '454 deferred settled stable [640, true, 4, false]', 'passed': True}, {'name': '455 dynamic bank init', 'passed': True}, {'name': '456 deferred all observed frames valid [640, false, 4, false]', 'passed': True}, {'name': '457 deferred final valid [640, false, 4, false]', 'passed': True}, {'name': '458 deferred settled stable [640, false, 4, false]', 'passed': True}, {'name': '459 dynamic bank init', 'passed': True}, {'name': '460 deferred all observed frames valid [640, false, 0, false]', 'passed': True}, {'name': '461 deferred final valid [640, false, 0, false]', 'passed': True}, {'name': '462 deferred settled stable [640, false, 0, false]', 'passed': True}, {'name': '463 dynamic bank init', 'passed': True}, {'name': '464 deferred all observed frames valid [640, false, 4, false]', 'passed': True}, {'name': '465 deferred final valid [640, false, 4, false]', 'passed': True}, {'name': '466 deferred settled stable [640, false, 4, false]', 'passed': True}, {'name': '467 dynamic bank init', 'passed': True}, {'name': '468 deferred all observed frames valid [640, false, 0, true]', 'passed': True}, {'name': '469 deferred final valid [640, false, 0, true]', 'passed': True}, {'name': '470 deferred settled stable [640, false, 0, true]', 'passed': True}, {'name': '471 dynamic bank init', 'passed': True}, {'name': '472 deferred all observed frames valid [640, false, 0, false]', 'passed': True}, {'name': '473 deferred final valid [640, false, 0, false]', 'passed': True}, {'name': '474 deferred settled stable [640, false, 0, false]', 'passed': True}, {'name': '475 dynamic bank init', 'passed': True}, {'name': '476 deferred all observed frames valid [619, false, 4, false]', 'passed': True}, {'name': '477 deferred final valid [619, false, 4, false]', 'passed': True}, {'name': '478 deferred settled stable [619, false, 4, false]', 'passed': True}, {'name': '479 dynamic bank init', 'passed': True}, {'name': '480 deferred all observed frames valid [620, false, 4, false]', 'passed': True}, {'name': '481 deferred final valid [620, false, 4, false]', 'passed': True}, {'name': '482 deferred settled stable [620, false, 4, false]', 'passed': True}, {'name': '483 dynamic bank init', 'passed': True}, {'name': '484 deferred all observed frames valid [844, false, 4, false]', 'passed': True}, {'name': '485 deferred final valid [844, false, 4, false]', 'passed': True}, {'name': '486 deferred settled stable [844, false, 4, false]', 'passed': True}, {'name': '487 dynamic bank init', 'passed': True}, {'name': '488 deferred all observed frames valid [740, false, 4, false]', 'passed': True}, {'name': '489 deferred final valid [740, false, 4, false]', 'passed': True}, {'name': '490 deferred settled stable [740, false, 4, false]', 'passed': True}], 'failed': 0, 'rows': [{'controls': [{'min': '(265.0, 24.0)', 'rect': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'text': '食 185  木 215  石 100  鐵 0  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (385.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (430.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (500.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (564.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': False, 'size': '(640, 360)'}, {'controls': [{'min': '(389.0, 24.0)', 'rect': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'text': '食 999999  木 999999  石 999999  鐵 999999  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 49.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 37.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 37.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 37.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 81.0, 'high': True, 'size': '(640, 360)'}, {'controls': [{'min': '(265.0, 24.0)', 'rect': '[P: (16.0, 21.0), S: (386.0, 24.0)]', 'text': '食 185  木 215  石 100  鐵 0  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (412.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (457.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (527.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (591.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': False, 'size': '(667, 375)'}, {'controls': [{'min': '(389.0, 24.0)', 'rect': '[P: (16.0, 10.0), S: (635.0, 24.0)]', 'text': '食 999999  木 999999  石 999999  鐵 999999  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 49.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 37.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 37.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 37.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 81.0, 'high': True, 'size': '(667, 375)'}, {'controls': [{'min': '(265.0, 24.0)', 'rect': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'text': '食 185  木 215  石 100  鐵 0  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (485.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (530.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (600.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (664.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': False, 'size': '(740, 360)'}, {'controls': [{'min': '(389.0, 24.0)', 'rect': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'text': '食 999999  木 999999  石 999999  鐵 999999  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (485.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (530.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (600.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (664.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': True, 'size': '(740, 360)'}, {'controls': [{'min': '(265.0, 24.0)', 'rect': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'text': '食 185  木 215  石 100  鐵 0  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (589.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (634.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (704.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (768.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': False, 'size': '(844, 390)'}, {'controls': [{'min': '(389.0, 24.0)', 'rect': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'text': '食 999999  木 999999  石 999999  鐵 999999  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (589.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (634.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (704.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (768.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': True, 'size': '(844, 390)'}, {'controls': [{'min': '(154.0, 47.0)', 'rect': '[P: (16.0, 10.0), S: (358.0, 47.0)]', 'text': '食 185  木 215  人口 6/10\n石 100  鐵 0  聚落時代'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 72.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 60.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 60.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 60.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 104.0, 'high': False, 'size': '(390, 844)'}, {'controls': [{'min': '(200.0, 47.0)', 'rect': '[P: (16.0, 10.0), S: (358.0, 47.0)]', 'text': '食 999999  木 999999  人口 6/10\n石 999999  鐵 999999  聚落時代'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 72.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 60.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 60.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 60.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 104.0, 'high': True, 'size': '(390, 844)'}, {'controls': [{'min': '(154.0, 47.0)', 'rect': '[P: (16.0, 10.0), S: (398.0, 47.0)]', 'text': '食 185  木 215  人口 6/10\n石 100  鐵 0  聚落時代'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 72.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 60.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 60.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 60.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 104.0, 'high': False, 'size': '(430, 932)'}, {'controls': [{'min': '(200.0, 47.0)', 'rect': '[P: (16.0, 10.0), S: (398.0, 47.0)]', 'text': '食 999999  木 999999  人口 6/10\n石 999999  鐵 999999  聚落時代'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 72.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 60.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 60.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 60.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 104.0, 'high': True, 'size': '(430, 932)'}], 'scope': 'Controlled isolated high-bank and four real alert API records for layout stress, not natural match screenshot.', 'suite': 'measured_battle_topbar_contract', 'transitions': [{'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}], 'spec': [640, False, 4, False]}, {'frames': [{'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}, {'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}, {'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}, {'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}, {'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}, {'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}], 'spec': [640, True, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}], 'spec': [640, False, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}], 'spec': [640, False, 0, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}], 'spec': [640, False, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}], 'spec': [640, False, 0, True]}, {'frames': [{'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}], 'spec': [640, False, 0, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}], 'spec': [619, False, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}], 'spec': [620, False, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}], 'spec': [844, False, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}], 'spec': [740, False, 4, False]}]}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key,value in [('failed',False),('failed',0.0),('failed',1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].reverse();mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['checks'].append(d['checks'][0]);mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            d=copy.deepcopy(report);del d['scope'];mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            self.assertEqual(len(mutants),5*len(report['checks'])+12)
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class V122MeasuredDiagnosticsTests(unittest.TestCase):
    def test_all_diagnostic_leaves_types_and_structure_exact(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': '000 fresh own keep exists', 'passed': True}, {'name': '001 controlled integer bank initialized', 'passed': True}, {'name': '002 actual four-resource bank exact (640, 360) high=false', 'passed': True}, {'name': '003 640 actual measured fallback false', 'passed': True}, {'name': '004 (640, 360) high=false inside resources', 'passed': True}, {'name': '005 (640, 360) high=false panel encloses resources', 'passed': True}, {'name': '006 (640, 360) high=false font readable resources', 'passed': True}, {'name': '007 (640, 360) high=false inside clock', 'passed': True}, {'name': '008 (640, 360) high=false panel encloses clock', 'passed': True}, {'name': '009 (640, 360) high=false font readable clock', 'passed': True}, {'name': '010 (640, 360) high=false inside pause', 'passed': True}, {'name': '011 (640, 360) high=false panel encloses pause', 'passed': True}, {'name': '012 (640, 360) high=false font readable pause', 'passed': True}, {'name': '013 (640, 360) high=false touch46 pause', 'passed': True}, {'name': '014 (640, 360) high=false inside alert', 'passed': True}, {'name': '015 (640, 360) high=false panel encloses alert', 'passed': True}, {'name': '016 (640, 360) high=false font readable alert', 'passed': True}, {'name': '017 (640, 360) high=false touch46 alert', 'passed': True}, {'name': '018 (640, 360) high=false inside menu', 'passed': True}, {'name': '019 (640, 360) high=false panel encloses menu', 'passed': True}, {'name': '020 (640, 360) high=false font readable menu', 'passed': True}, {'name': '021 (640, 360) high=false touch46 menu', 'passed': True}, {'name': '022 (640, 360) high=false disjoint 0/1', 'passed': True}, {'name': '023 (640, 360) high=false disjoint 0/2', 'passed': True}, {'name': '024 (640, 360) high=false disjoint 0/3', 'passed': True}, {'name': '025 (640, 360) high=false disjoint 0/4', 'passed': True}, {'name': '026 (640, 360) high=false disjoint 1/2', 'passed': True}, {'name': '027 (640, 360) high=false disjoint 1/3', 'passed': True}, {'name': '028 (640, 360) high=false disjoint 1/4', 'passed': True}, {'name': '029 (640, 360) high=false disjoint 2/3', 'passed': True}, {'name': '030 (640, 360) high=false disjoint 2/4', 'passed': True}, {'name': '031 (640, 360) high=false disjoint 3/4', 'passed': True}, {'name': '032 (640, 360) high=false routed alert acknowledges', 'passed': True}, {'name': '033 (640, 360) high=false routed pause', 'passed': True}, {'name': '034 (640, 360) high=false paused alert disabled', 'passed': True}, {'name': '035 (640, 360) high=false paused alert no acknowledgement', 'passed': True}, {'name': '036 (640, 360) high=false routed resume', 'passed': True}, {'name': '037 (640, 360) high=false routed menu', 'passed': True}, {'name': '038 (640, 360) high=false routed close', 'passed': True}, {'name': '039 controlled integer bank initialized', 'passed': True}, {'name': '040 actual four-resource bank exact (640, 360) high=true', 'passed': True}, {'name': '041 640 actual measured fallback true', 'passed': True}, {'name': '042 (640, 360) high=true inside resources', 'passed': True}, {'name': '043 (640, 360) high=true panel encloses resources', 'passed': True}, {'name': '044 (640, 360) high=true font readable resources', 'passed': True}, {'name': '045 (640, 360) high=true inside clock', 'passed': True}, {'name': '046 (640, 360) high=true panel encloses clock', 'passed': True}, {'name': '047 (640, 360) high=true font readable clock', 'passed': True}, {'name': '048 (640, 360) high=true inside pause', 'passed': True}, {'name': '049 (640, 360) high=true panel encloses pause', 'passed': True}, {'name': '050 (640, 360) high=true font readable pause', 'passed': True}, {'name': '051 (640, 360) high=true touch46 pause', 'passed': True}, {'name': '052 (640, 360) high=true inside alert', 'passed': True}, {'name': '053 (640, 360) high=true panel encloses alert', 'passed': True}, {'name': '054 (640, 360) high=true font readable alert', 'passed': True}, {'name': '055 (640, 360) high=true touch46 alert', 'passed': True}, {'name': '056 (640, 360) high=true inside menu', 'passed': True}, {'name': '057 (640, 360) high=true panel encloses menu', 'passed': True}, {'name': '058 (640, 360) high=true font readable menu', 'passed': True}, {'name': '059 (640, 360) high=true touch46 menu', 'passed': True}, {'name': '060 (640, 360) high=true disjoint 0/1', 'passed': True}, {'name': '061 (640, 360) high=true disjoint 0/2', 'passed': True}, {'name': '062 (640, 360) high=true disjoint 0/3', 'passed': True}, {'name': '063 (640, 360) high=true disjoint 0/4', 'passed': True}, {'name': '064 (640, 360) high=true disjoint 1/2', 'passed': True}, {'name': '065 (640, 360) high=true disjoint 1/3', 'passed': True}, {'name': '066 (640, 360) high=true disjoint 1/4', 'passed': True}, {'name': '067 (640, 360) high=true disjoint 2/3', 'passed': True}, {'name': '068 (640, 360) high=true disjoint 2/4', 'passed': True}, {'name': '069 (640, 360) high=true disjoint 3/4', 'passed': True}, {'name': '070 (640, 360) high=true routed alert acknowledges', 'passed': True}, {'name': '071 (640, 360) high=true routed pause', 'passed': True}, {'name': '072 (640, 360) high=true paused alert disabled', 'passed': True}, {'name': '073 (640, 360) high=true paused alert no acknowledgement', 'passed': True}, {'name': '074 (640, 360) high=true routed resume', 'passed': True}, {'name': '075 (640, 360) high=true routed menu', 'passed': True}, {'name': '076 (640, 360) high=true routed close', 'passed': True}, {'name': '077 controlled integer bank initialized', 'passed': True}, {'name': '078 actual four-resource bank exact (667, 375) high=false', 'passed': True}, {'name': '079 (667, 375) high=false inside resources', 'passed': True}, {'name': '080 (667, 375) high=false panel encloses resources', 'passed': True}, {'name': '081 (667, 375) high=false font readable resources', 'passed': True}, {'name': '082 (667, 375) high=false inside clock', 'passed': True}, {'name': '083 (667, 375) high=false panel encloses clock', 'passed': True}, {'name': '084 (667, 375) high=false font readable clock', 'passed': True}, {'name': '085 (667, 375) high=false inside pause', 'passed': True}, {'name': '086 (667, 375) high=false panel encloses pause', 'passed': True}, {'name': '087 (667, 375) high=false font readable pause', 'passed': True}, {'name': '088 (667, 375) high=false touch46 pause', 'passed': True}, {'name': '089 (667, 375) high=false inside alert', 'passed': True}, {'name': '090 (667, 375) high=false panel encloses alert', 'passed': True}, {'name': '091 (667, 375) high=false font readable alert', 'passed': True}, {'name': '092 (667, 375) high=false touch46 alert', 'passed': True}, {'name': '093 (667, 375) high=false inside menu', 'passed': True}, {'name': '094 (667, 375) high=false panel encloses menu', 'passed': True}, {'name': '095 (667, 375) high=false font readable menu', 'passed': True}, {'name': '096 (667, 375) high=false touch46 menu', 'passed': True}, {'name': '097 (667, 375) high=false disjoint 0/1', 'passed': True}, {'name': '098 (667, 375) high=false disjoint 0/2', 'passed': True}, {'name': '099 (667, 375) high=false disjoint 0/3', 'passed': True}, {'name': '100 (667, 375) high=false disjoint 0/4', 'passed': True}, {'name': '101 (667, 375) high=false disjoint 1/2', 'passed': True}, {'name': '102 (667, 375) high=false disjoint 1/3', 'passed': True}, {'name': '103 (667, 375) high=false disjoint 1/4', 'passed': True}, {'name': '104 (667, 375) high=false disjoint 2/3', 'passed': True}, {'name': '105 (667, 375) high=false disjoint 2/4', 'passed': True}, {'name': '106 (667, 375) high=false disjoint 3/4', 'passed': True}, {'name': '107 (667, 375) high=false routed alert acknowledges', 'passed': True}, {'name': '108 (667, 375) high=false routed pause', 'passed': True}, {'name': '109 (667, 375) high=false paused alert disabled', 'passed': True}, {'name': '110 (667, 375) high=false paused alert no acknowledgement', 'passed': True}, {'name': '111 (667, 375) high=false routed resume', 'passed': True}, {'name': '112 (667, 375) high=false routed menu', 'passed': True}, {'name': '113 (667, 375) high=false routed close', 'passed': True}, {'name': '114 controlled integer bank initialized', 'passed': True}, {'name': '115 actual four-resource bank exact (667, 375) high=true', 'passed': True}, {'name': '116 (667, 375) high=true inside resources', 'passed': True}, {'name': '117 (667, 375) high=true panel encloses resources', 'passed': True}, {'name': '118 (667, 375) high=true font readable resources', 'passed': True}, {'name': '119 (667, 375) high=true inside clock', 'passed': True}, {'name': '120 (667, 375) high=true panel encloses clock', 'passed': True}, {'name': '121 (667, 375) high=true font readable clock', 'passed': True}, {'name': '122 (667, 375) high=true inside pause', 'passed': True}, {'name': '123 (667, 375) high=true panel encloses pause', 'passed': True}, {'name': '124 (667, 375) high=true font readable pause', 'passed': True}, {'name': '125 (667, 375) high=true touch46 pause', 'passed': True}, {'name': '126 (667, 375) high=true inside alert', 'passed': True}, {'name': '127 (667, 375) high=true panel encloses alert', 'passed': True}, {'name': '128 (667, 375) high=true font readable alert', 'passed': True}, {'name': '129 (667, 375) high=true touch46 alert', 'passed': True}, {'name': '130 (667, 375) high=true inside menu', 'passed': True}, {'name': '131 (667, 375) high=true panel encloses menu', 'passed': True}, {'name': '132 (667, 375) high=true font readable menu', 'passed': True}, {'name': '133 (667, 375) high=true touch46 menu', 'passed': True}, {'name': '134 (667, 375) high=true disjoint 0/1', 'passed': True}, {'name': '135 (667, 375) high=true disjoint 0/2', 'passed': True}, {'name': '136 (667, 375) high=true disjoint 0/3', 'passed': True}, {'name': '137 (667, 375) high=true disjoint 0/4', 'passed': True}, {'name': '138 (667, 375) high=true disjoint 1/2', 'passed': True}, {'name': '139 (667, 375) high=true disjoint 1/3', 'passed': True}, {'name': '140 (667, 375) high=true disjoint 1/4', 'passed': True}, {'name': '141 (667, 375) high=true disjoint 2/3', 'passed': True}, {'name': '142 (667, 375) high=true disjoint 2/4', 'passed': True}, {'name': '143 (667, 375) high=true disjoint 3/4', 'passed': True}, {'name': '144 (667, 375) high=true routed alert acknowledges', 'passed': True}, {'name': '145 (667, 375) high=true routed pause', 'passed': True}, {'name': '146 (667, 375) high=true paused alert disabled', 'passed': True}, {'name': '147 (667, 375) high=true paused alert no acknowledgement', 'passed': True}, {'name': '148 (667, 375) high=true routed resume', 'passed': True}, {'name': '149 (667, 375) high=true routed menu', 'passed': True}, {'name': '150 (667, 375) high=true routed close', 'passed': True}, {'name': '151 controlled integer bank initialized', 'passed': True}, {'name': '152 actual four-resource bank exact (740, 360) high=false', 'passed': True}, {'name': '153 (740, 360) high=false inside resources', 'passed': True}, {'name': '154 (740, 360) high=false panel encloses resources', 'passed': True}, {'name': '155 (740, 360) high=false font readable resources', 'passed': True}, {'name': '156 (740, 360) high=false inside clock', 'passed': True}, {'name': '157 (740, 360) high=false panel encloses clock', 'passed': True}, {'name': '158 (740, 360) high=false font readable clock', 'passed': True}, {'name': '159 (740, 360) high=false inside pause', 'passed': True}, {'name': '160 (740, 360) high=false panel encloses pause', 'passed': True}, {'name': '161 (740, 360) high=false font readable pause', 'passed': True}, {'name': '162 (740, 360) high=false touch46 pause', 'passed': True}, {'name': '163 (740, 360) high=false inside alert', 'passed': True}, {'name': '164 (740, 360) high=false panel encloses alert', 'passed': True}, {'name': '165 (740, 360) high=false font readable alert', 'passed': True}, {'name': '166 (740, 360) high=false touch46 alert', 'passed': True}, {'name': '167 (740, 360) high=false inside menu', 'passed': True}, {'name': '168 (740, 360) high=false panel encloses menu', 'passed': True}, {'name': '169 (740, 360) high=false font readable menu', 'passed': True}, {'name': '170 (740, 360) high=false touch46 menu', 'passed': True}, {'name': '171 (740, 360) high=false disjoint 0/1', 'passed': True}, {'name': '172 (740, 360) high=false disjoint 0/2', 'passed': True}, {'name': '173 (740, 360) high=false disjoint 0/3', 'passed': True}, {'name': '174 (740, 360) high=false disjoint 0/4', 'passed': True}, {'name': '175 (740, 360) high=false disjoint 1/2', 'passed': True}, {'name': '176 (740, 360) high=false disjoint 1/3', 'passed': True}, {'name': '177 (740, 360) high=false disjoint 1/4', 'passed': True}, {'name': '178 (740, 360) high=false disjoint 2/3', 'passed': True}, {'name': '179 (740, 360) high=false disjoint 2/4', 'passed': True}, {'name': '180 (740, 360) high=false disjoint 3/4', 'passed': True}, {'name': '181 (740, 360) high=false routed alert acknowledges', 'passed': True}, {'name': '182 (740, 360) high=false routed pause', 'passed': True}, {'name': '183 (740, 360) high=false paused alert disabled', 'passed': True}, {'name': '184 (740, 360) high=false paused alert no acknowledgement', 'passed': True}, {'name': '185 (740, 360) high=false routed resume', 'passed': True}, {'name': '186 (740, 360) high=false routed menu', 'passed': True}, {'name': '187 (740, 360) high=false routed close', 'passed': True}, {'name': '188 controlled integer bank initialized', 'passed': True}, {'name': '189 actual four-resource bank exact (740, 360) high=true', 'passed': True}, {'name': '190 (740, 360) high=true inside resources', 'passed': True}, {'name': '191 (740, 360) high=true panel encloses resources', 'passed': True}, {'name': '192 (740, 360) high=true font readable resources', 'passed': True}, {'name': '193 (740, 360) high=true inside clock', 'passed': True}, {'name': '194 (740, 360) high=true panel encloses clock', 'passed': True}, {'name': '195 (740, 360) high=true font readable clock', 'passed': True}, {'name': '196 (740, 360) high=true inside pause', 'passed': True}, {'name': '197 (740, 360) high=true panel encloses pause', 'passed': True}, {'name': '198 (740, 360) high=true font readable pause', 'passed': True}, {'name': '199 (740, 360) high=true touch46 pause', 'passed': True}, {'name': '200 (740, 360) high=true inside alert', 'passed': True}, {'name': '201 (740, 360) high=true panel encloses alert', 'passed': True}, {'name': '202 (740, 360) high=true font readable alert', 'passed': True}, {'name': '203 (740, 360) high=true touch46 alert', 'passed': True}, {'name': '204 (740, 360) high=true inside menu', 'passed': True}, {'name': '205 (740, 360) high=true panel encloses menu', 'passed': True}, {'name': '206 (740, 360) high=true font readable menu', 'passed': True}, {'name': '207 (740, 360) high=true touch46 menu', 'passed': True}, {'name': '208 (740, 360) high=true disjoint 0/1', 'passed': True}, {'name': '209 (740, 360) high=true disjoint 0/2', 'passed': True}, {'name': '210 (740, 360) high=true disjoint 0/3', 'passed': True}, {'name': '211 (740, 360) high=true disjoint 0/4', 'passed': True}, {'name': '212 (740, 360) high=true disjoint 1/2', 'passed': True}, {'name': '213 (740, 360) high=true disjoint 1/3', 'passed': True}, {'name': '214 (740, 360) high=true disjoint 1/4', 'passed': True}, {'name': '215 (740, 360) high=true disjoint 2/3', 'passed': True}, {'name': '216 (740, 360) high=true disjoint 2/4', 'passed': True}, {'name': '217 (740, 360) high=true disjoint 3/4', 'passed': True}, {'name': '218 (740, 360) high=true routed alert acknowledges', 'passed': True}, {'name': '219 (740, 360) high=true routed pause', 'passed': True}, {'name': '220 (740, 360) high=true paused alert disabled', 'passed': True}, {'name': '221 (740, 360) high=true paused alert no acknowledgement', 'passed': True}, {'name': '222 (740, 360) high=true routed resume', 'passed': True}, {'name': '223 (740, 360) high=true routed menu', 'passed': True}, {'name': '224 (740, 360) high=true routed close', 'passed': True}, {'name': '225 controlled integer bank initialized', 'passed': True}, {'name': '226 actual four-resource bank exact (844, 390) high=false', 'passed': True}, {'name': '227 (844, 390) high=false inside resources', 'passed': True}, {'name': '228 (844, 390) high=false panel encloses resources', 'passed': True}, {'name': '229 (844, 390) high=false font readable resources', 'passed': True}, {'name': '230 (844, 390) high=false inside clock', 'passed': True}, {'name': '231 (844, 390) high=false panel encloses clock', 'passed': True}, {'name': '232 (844, 390) high=false font readable clock', 'passed': True}, {'name': '233 (844, 390) high=false inside pause', 'passed': True}, {'name': '234 (844, 390) high=false panel encloses pause', 'passed': True}, {'name': '235 (844, 390) high=false font readable pause', 'passed': True}, {'name': '236 (844, 390) high=false touch46 pause', 'passed': True}, {'name': '237 (844, 390) high=false inside alert', 'passed': True}, {'name': '238 (844, 390) high=false panel encloses alert', 'passed': True}, {'name': '239 (844, 390) high=false font readable alert', 'passed': True}, {'name': '240 (844, 390) high=false touch46 alert', 'passed': True}, {'name': '241 (844, 390) high=false inside menu', 'passed': True}, {'name': '242 (844, 390) high=false panel encloses menu', 'passed': True}, {'name': '243 (844, 390) high=false font readable menu', 'passed': True}, {'name': '244 (844, 390) high=false touch46 menu', 'passed': True}, {'name': '245 (844, 390) high=false disjoint 0/1', 'passed': True}, {'name': '246 (844, 390) high=false disjoint 0/2', 'passed': True}, {'name': '247 (844, 390) high=false disjoint 0/3', 'passed': True}, {'name': '248 (844, 390) high=false disjoint 0/4', 'passed': True}, {'name': '249 (844, 390) high=false disjoint 1/2', 'passed': True}, {'name': '250 (844, 390) high=false disjoint 1/3', 'passed': True}, {'name': '251 (844, 390) high=false disjoint 1/4', 'passed': True}, {'name': '252 (844, 390) high=false disjoint 2/3', 'passed': True}, {'name': '253 (844, 390) high=false disjoint 2/4', 'passed': True}, {'name': '254 (844, 390) high=false disjoint 3/4', 'passed': True}, {'name': '255 (844, 390) high=false routed alert acknowledges', 'passed': True}, {'name': '256 (844, 390) high=false routed pause', 'passed': True}, {'name': '257 (844, 390) high=false paused alert disabled', 'passed': True}, {'name': '258 (844, 390) high=false paused alert no acknowledgement', 'passed': True}, {'name': '259 (844, 390) high=false routed resume', 'passed': True}, {'name': '260 (844, 390) high=false routed menu', 'passed': True}, {'name': '261 (844, 390) high=false routed close', 'passed': True}, {'name': '262 controlled integer bank initialized', 'passed': True}, {'name': '263 actual four-resource bank exact (844, 390) high=true', 'passed': True}, {'name': '264 (844, 390) high=true inside resources', 'passed': True}, {'name': '265 (844, 390) high=true panel encloses resources', 'passed': True}, {'name': '266 (844, 390) high=true font readable resources', 'passed': True}, {'name': '267 (844, 390) high=true inside clock', 'passed': True}, {'name': '268 (844, 390) high=true panel encloses clock', 'passed': True}, {'name': '269 (844, 390) high=true font readable clock', 'passed': True}, {'name': '270 (844, 390) high=true inside pause', 'passed': True}, {'name': '271 (844, 390) high=true panel encloses pause', 'passed': True}, {'name': '272 (844, 390) high=true font readable pause', 'passed': True}, {'name': '273 (844, 390) high=true touch46 pause', 'passed': True}, {'name': '274 (844, 390) high=true inside alert', 'passed': True}, {'name': '275 (844, 390) high=true panel encloses alert', 'passed': True}, {'name': '276 (844, 390) high=true font readable alert', 'passed': True}, {'name': '277 (844, 390) high=true touch46 alert', 'passed': True}, {'name': '278 (844, 390) high=true inside menu', 'passed': True}, {'name': '279 (844, 390) high=true panel encloses menu', 'passed': True}, {'name': '280 (844, 390) high=true font readable menu', 'passed': True}, {'name': '281 (844, 390) high=true touch46 menu', 'passed': True}, {'name': '282 (844, 390) high=true disjoint 0/1', 'passed': True}, {'name': '283 (844, 390) high=true disjoint 0/2', 'passed': True}, {'name': '284 (844, 390) high=true disjoint 0/3', 'passed': True}, {'name': '285 (844, 390) high=true disjoint 0/4', 'passed': True}, {'name': '286 (844, 390) high=true disjoint 1/2', 'passed': True}, {'name': '287 (844, 390) high=true disjoint 1/3', 'passed': True}, {'name': '288 (844, 390) high=true disjoint 1/4', 'passed': True}, {'name': '289 (844, 390) high=true disjoint 2/3', 'passed': True}, {'name': '290 (844, 390) high=true disjoint 2/4', 'passed': True}, {'name': '291 (844, 390) high=true disjoint 3/4', 'passed': True}, {'name': '292 (844, 390) high=true routed alert acknowledges', 'passed': True}, {'name': '293 (844, 390) high=true routed pause', 'passed': True}, {'name': '294 (844, 390) high=true paused alert disabled', 'passed': True}, {'name': '295 (844, 390) high=true paused alert no acknowledgement', 'passed': True}, {'name': '296 (844, 390) high=true routed resume', 'passed': True}, {'name': '297 (844, 390) high=true routed menu', 'passed': True}, {'name': '298 (844, 390) high=true routed close', 'passed': True}, {'name': '299 controlled integer bank initialized', 'passed': True}, {'name': '300 actual four-resource bank exact (390, 844) high=false', 'passed': True}, {'name': '301 (390, 844) high=false inside resources', 'passed': True}, {'name': '302 (390, 844) high=false panel encloses resources', 'passed': True}, {'name': '303 (390, 844) high=false font readable resources', 'passed': True}, {'name': '304 (390, 844) high=false inside clock', 'passed': True}, {'name': '305 (390, 844) high=false panel encloses clock', 'passed': True}, {'name': '306 (390, 844) high=false font readable clock', 'passed': True}, {'name': '307 (390, 844) high=false inside pause', 'passed': True}, {'name': '308 (390, 844) high=false panel encloses pause', 'passed': True}, {'name': '309 (390, 844) high=false font readable pause', 'passed': True}, {'name': '310 (390, 844) high=false touch46 pause', 'passed': True}, {'name': '311 (390, 844) high=false inside alert', 'passed': True}, {'name': '312 (390, 844) high=false panel encloses alert', 'passed': True}, {'name': '313 (390, 844) high=false font readable alert', 'passed': True}, {'name': '314 (390, 844) high=false touch46 alert', 'passed': True}, {'name': '315 (390, 844) high=false inside menu', 'passed': True}, {'name': '316 (390, 844) high=false panel encloses menu', 'passed': True}, {'name': '317 (390, 844) high=false font readable menu', 'passed': True}, {'name': '318 (390, 844) high=false touch46 menu', 'passed': True}, {'name': '319 (390, 844) high=false disjoint 0/1', 'passed': True}, {'name': '320 (390, 844) high=false disjoint 0/2', 'passed': True}, {'name': '321 (390, 844) high=false disjoint 0/3', 'passed': True}, {'name': '322 (390, 844) high=false disjoint 0/4', 'passed': True}, {'name': '323 (390, 844) high=false disjoint 1/2', 'passed': True}, {'name': '324 (390, 844) high=false disjoint 1/3', 'passed': True}, {'name': '325 (390, 844) high=false disjoint 1/4', 'passed': True}, {'name': '326 (390, 844) high=false disjoint 2/3', 'passed': True}, {'name': '327 (390, 844) high=false disjoint 2/4', 'passed': True}, {'name': '328 (390, 844) high=false disjoint 3/4', 'passed': True}, {'name': '329 (390, 844) high=false routed alert acknowledges', 'passed': True}, {'name': '330 (390, 844) high=false routed pause', 'passed': True}, {'name': '331 (390, 844) high=false paused alert disabled', 'passed': True}, {'name': '332 (390, 844) high=false paused alert no acknowledgement', 'passed': True}, {'name': '333 (390, 844) high=false routed resume', 'passed': True}, {'name': '334 (390, 844) high=false routed menu', 'passed': True}, {'name': '335 (390, 844) high=false routed close', 'passed': True}, {'name': '336 controlled integer bank initialized', 'passed': True}, {'name': '337 actual four-resource bank exact (390, 844) high=true', 'passed': True}, {'name': '338 (390, 844) high=true inside resources', 'passed': True}, {'name': '339 (390, 844) high=true panel encloses resources', 'passed': True}, {'name': '340 (390, 844) high=true font readable resources', 'passed': True}, {'name': '341 (390, 844) high=true inside clock', 'passed': True}, {'name': '342 (390, 844) high=true panel encloses clock', 'passed': True}, {'name': '343 (390, 844) high=true font readable clock', 'passed': True}, {'name': '344 (390, 844) high=true inside pause', 'passed': True}, {'name': '345 (390, 844) high=true panel encloses pause', 'passed': True}, {'name': '346 (390, 844) high=true font readable pause', 'passed': True}, {'name': '347 (390, 844) high=true touch46 pause', 'passed': True}, {'name': '348 (390, 844) high=true inside alert', 'passed': True}, {'name': '349 (390, 844) high=true panel encloses alert', 'passed': True}, {'name': '350 (390, 844) high=true font readable alert', 'passed': True}, {'name': '351 (390, 844) high=true touch46 alert', 'passed': True}, {'name': '352 (390, 844) high=true inside menu', 'passed': True}, {'name': '353 (390, 844) high=true panel encloses menu', 'passed': True}, {'name': '354 (390, 844) high=true font readable menu', 'passed': True}, {'name': '355 (390, 844) high=true touch46 menu', 'passed': True}, {'name': '356 (390, 844) high=true disjoint 0/1', 'passed': True}, {'name': '357 (390, 844) high=true disjoint 0/2', 'passed': True}, {'name': '358 (390, 844) high=true disjoint 0/3', 'passed': True}, {'name': '359 (390, 844) high=true disjoint 0/4', 'passed': True}, {'name': '360 (390, 844) high=true disjoint 1/2', 'passed': True}, {'name': '361 (390, 844) high=true disjoint 1/3', 'passed': True}, {'name': '362 (390, 844) high=true disjoint 1/4', 'passed': True}, {'name': '363 (390, 844) high=true disjoint 2/3', 'passed': True}, {'name': '364 (390, 844) high=true disjoint 2/4', 'passed': True}, {'name': '365 (390, 844) high=true disjoint 3/4', 'passed': True}, {'name': '366 (390, 844) high=true routed alert acknowledges', 'passed': True}, {'name': '367 (390, 844) high=true routed pause', 'passed': True}, {'name': '368 (390, 844) high=true paused alert disabled', 'passed': True}, {'name': '369 (390, 844) high=true paused alert no acknowledgement', 'passed': True}, {'name': '370 (390, 844) high=true routed resume', 'passed': True}, {'name': '371 (390, 844) high=true routed menu', 'passed': True}, {'name': '372 (390, 844) high=true routed close', 'passed': True}, {'name': '373 controlled integer bank initialized', 'passed': True}, {'name': '374 actual four-resource bank exact (430, 932) high=false', 'passed': True}, {'name': '375 (430, 932) high=false inside resources', 'passed': True}, {'name': '376 (430, 932) high=false panel encloses resources', 'passed': True}, {'name': '377 (430, 932) high=false font readable resources', 'passed': True}, {'name': '378 (430, 932) high=false inside clock', 'passed': True}, {'name': '379 (430, 932) high=false panel encloses clock', 'passed': True}, {'name': '380 (430, 932) high=false font readable clock', 'passed': True}, {'name': '381 (430, 932) high=false inside pause', 'passed': True}, {'name': '382 (430, 932) high=false panel encloses pause', 'passed': True}, {'name': '383 (430, 932) high=false font readable pause', 'passed': True}, {'name': '384 (430, 932) high=false touch46 pause', 'passed': True}, {'name': '385 (430, 932) high=false inside alert', 'passed': True}, {'name': '386 (430, 932) high=false panel encloses alert', 'passed': True}, {'name': '387 (430, 932) high=false font readable alert', 'passed': True}, {'name': '388 (430, 932) high=false touch46 alert', 'passed': True}, {'name': '389 (430, 932) high=false inside menu', 'passed': True}, {'name': '390 (430, 932) high=false panel encloses menu', 'passed': True}, {'name': '391 (430, 932) high=false font readable menu', 'passed': True}, {'name': '392 (430, 932) high=false touch46 menu', 'passed': True}, {'name': '393 (430, 932) high=false disjoint 0/1', 'passed': True}, {'name': '394 (430, 932) high=false disjoint 0/2', 'passed': True}, {'name': '395 (430, 932) high=false disjoint 0/3', 'passed': True}, {'name': '396 (430, 932) high=false disjoint 0/4', 'passed': True}, {'name': '397 (430, 932) high=false disjoint 1/2', 'passed': True}, {'name': '398 (430, 932) high=false disjoint 1/3', 'passed': True}, {'name': '399 (430, 932) high=false disjoint 1/4', 'passed': True}, {'name': '400 (430, 932) high=false disjoint 2/3', 'passed': True}, {'name': '401 (430, 932) high=false disjoint 2/4', 'passed': True}, {'name': '402 (430, 932) high=false disjoint 3/4', 'passed': True}, {'name': '403 (430, 932) high=false routed alert acknowledges', 'passed': True}, {'name': '404 (430, 932) high=false routed pause', 'passed': True}, {'name': '405 (430, 932) high=false paused alert disabled', 'passed': True}, {'name': '406 (430, 932) high=false paused alert no acknowledgement', 'passed': True}, {'name': '407 (430, 932) high=false routed resume', 'passed': True}, {'name': '408 (430, 932) high=false routed menu', 'passed': True}, {'name': '409 (430, 932) high=false routed close', 'passed': True}, {'name': '410 controlled integer bank initialized', 'passed': True}, {'name': '411 actual four-resource bank exact (430, 932) high=true', 'passed': True}, {'name': '412 (430, 932) high=true inside resources', 'passed': True}, {'name': '413 (430, 932) high=true panel encloses resources', 'passed': True}, {'name': '414 (430, 932) high=true font readable resources', 'passed': True}, {'name': '415 (430, 932) high=true inside clock', 'passed': True}, {'name': '416 (430, 932) high=true panel encloses clock', 'passed': True}, {'name': '417 (430, 932) high=true font readable clock', 'passed': True}, {'name': '418 (430, 932) high=true inside pause', 'passed': True}, {'name': '419 (430, 932) high=true panel encloses pause', 'passed': True}, {'name': '420 (430, 932) high=true font readable pause', 'passed': True}, {'name': '421 (430, 932) high=true touch46 pause', 'passed': True}, {'name': '422 (430, 932) high=true inside alert', 'passed': True}, {'name': '423 (430, 932) high=true panel encloses alert', 'passed': True}, {'name': '424 (430, 932) high=true font readable alert', 'passed': True}, {'name': '425 (430, 932) high=true touch46 alert', 'passed': True}, {'name': '426 (430, 932) high=true inside menu', 'passed': True}, {'name': '427 (430, 932) high=true panel encloses menu', 'passed': True}, {'name': '428 (430, 932) high=true font readable menu', 'passed': True}, {'name': '429 (430, 932) high=true touch46 menu', 'passed': True}, {'name': '430 (430, 932) high=true disjoint 0/1', 'passed': True}, {'name': '431 (430, 932) high=true disjoint 0/2', 'passed': True}, {'name': '432 (430, 932) high=true disjoint 0/3', 'passed': True}, {'name': '433 (430, 932) high=true disjoint 0/4', 'passed': True}, {'name': '434 (430, 932) high=true disjoint 1/2', 'passed': True}, {'name': '435 (430, 932) high=true disjoint 1/3', 'passed': True}, {'name': '436 (430, 932) high=true disjoint 1/4', 'passed': True}, {'name': '437 (430, 932) high=true disjoint 2/3', 'passed': True}, {'name': '438 (430, 932) high=true disjoint 2/4', 'passed': True}, {'name': '439 (430, 932) high=true disjoint 3/4', 'passed': True}, {'name': '440 (430, 932) high=true routed alert acknowledges', 'passed': True}, {'name': '441 (430, 932) high=true routed pause', 'passed': True}, {'name': '442 (430, 932) high=true paused alert disabled', 'passed': True}, {'name': '443 (430, 932) high=true paused alert no acknowledgement', 'passed': True}, {'name': '444 (430, 932) high=true routed resume', 'passed': True}, {'name': '445 (430, 932) high=true routed menu', 'passed': True}, {'name': '446 (430, 932) high=true routed close', 'passed': True}, {'name': '447 dynamic bank init', 'passed': True}, {'name': '448 deferred all observed frames valid [640, false, 4, false]', 'passed': True}, {'name': '449 deferred final valid [640, false, 4, false]', 'passed': True}, {'name': '450 deferred settled stable [640, false, 4, false]', 'passed': True}, {'name': '451 dynamic bank init', 'passed': True}, {'name': '452 deferred all observed frames valid [640, true, 4, false]', 'passed': True}, {'name': '453 deferred final valid [640, true, 4, false]', 'passed': True}, {'name': '454 deferred settled stable [640, true, 4, false]', 'passed': True}, {'name': '455 dynamic bank init', 'passed': True}, {'name': '456 deferred all observed frames valid [640, false, 4, false]', 'passed': True}, {'name': '457 deferred final valid [640, false, 4, false]', 'passed': True}, {'name': '458 deferred settled stable [640, false, 4, false]', 'passed': True}, {'name': '459 dynamic bank init', 'passed': True}, {'name': '460 deferred all observed frames valid [640, false, 0, false]', 'passed': True}, {'name': '461 deferred final valid [640, false, 0, false]', 'passed': True}, {'name': '462 deferred settled stable [640, false, 0, false]', 'passed': True}, {'name': '463 dynamic bank init', 'passed': True}, {'name': '464 deferred all observed frames valid [640, false, 4, false]', 'passed': True}, {'name': '465 deferred final valid [640, false, 4, false]', 'passed': True}, {'name': '466 deferred settled stable [640, false, 4, false]', 'passed': True}, {'name': '467 dynamic bank init', 'passed': True}, {'name': '468 deferred all observed frames valid [640, false, 0, true]', 'passed': True}, {'name': '469 deferred final valid [640, false, 0, true]', 'passed': True}, {'name': '470 deferred settled stable [640, false, 0, true]', 'passed': True}, {'name': '471 dynamic bank init', 'passed': True}, {'name': '472 deferred all observed frames valid [640, false, 0, false]', 'passed': True}, {'name': '473 deferred final valid [640, false, 0, false]', 'passed': True}, {'name': '474 deferred settled stable [640, false, 0, false]', 'passed': True}, {'name': '475 dynamic bank init', 'passed': True}, {'name': '476 deferred all observed frames valid [619, false, 4, false]', 'passed': True}, {'name': '477 deferred final valid [619, false, 4, false]', 'passed': True}, {'name': '478 deferred settled stable [619, false, 4, false]', 'passed': True}, {'name': '479 dynamic bank init', 'passed': True}, {'name': '480 deferred all observed frames valid [620, false, 4, false]', 'passed': True}, {'name': '481 deferred final valid [620, false, 4, false]', 'passed': True}, {'name': '482 deferred settled stable [620, false, 4, false]', 'passed': True}, {'name': '483 dynamic bank init', 'passed': True}, {'name': '484 deferred all observed frames valid [844, false, 4, false]', 'passed': True}, {'name': '485 deferred final valid [844, false, 4, false]', 'passed': True}, {'name': '486 deferred settled stable [844, false, 4, false]', 'passed': True}, {'name': '487 dynamic bank init', 'passed': True}, {'name': '488 deferred all observed frames valid [740, false, 4, false]', 'passed': True}, {'name': '489 deferred final valid [740, false, 4, false]', 'passed': True}, {'name': '490 deferred settled stable [740, false, 4, false]', 'passed': True}], 'failed': 0, 'rows': [{'controls': [{'min': '(265.0, 24.0)', 'rect': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'text': '食 185  木 215  石 100  鐵 0  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (385.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (430.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (500.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (564.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': False, 'size': '(640, 360)'}, {'controls': [{'min': '(389.0, 24.0)', 'rect': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'text': '食 999999  木 999999  石 999999  鐵 999999  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 49.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 37.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 37.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 37.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 81.0, 'high': True, 'size': '(640, 360)'}, {'controls': [{'min': '(265.0, 24.0)', 'rect': '[P: (16.0, 21.0), S: (386.0, 24.0)]', 'text': '食 185  木 215  石 100  鐵 0  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (412.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (457.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (527.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (591.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': False, 'size': '(667, 375)'}, {'controls': [{'min': '(389.0, 24.0)', 'rect': '[P: (16.0, 10.0), S: (635.0, 24.0)]', 'text': '食 999999  木 999999  石 999999  鐵 999999  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 49.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 37.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 37.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 37.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 81.0, 'high': True, 'size': '(667, 375)'}, {'controls': [{'min': '(265.0, 24.0)', 'rect': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'text': '食 185  木 215  石 100  鐵 0  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (485.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (530.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (600.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (664.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': False, 'size': '(740, 360)'}, {'controls': [{'min': '(389.0, 24.0)', 'rect': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'text': '食 999999  木 999999  石 999999  鐵 999999  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (485.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (530.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (600.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (664.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': True, 'size': '(740, 360)'}, {'controls': [{'min': '(265.0, 24.0)', 'rect': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'text': '食 185  木 215  石 100  鐵 0  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (589.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (634.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (704.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (768.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': False, 'size': '(844, 390)'}, {'controls': [{'min': '(389.0, 24.0)', 'rect': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'text': '食 999999  木 999999  石 999999  鐵 999999  人口 6/10'}, {'min': '(35.0, 22.0)', 'rect': '[P: (589.0, 22.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (634.0, 10.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (704.0, 10.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (768.0, 10.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 54.0, 'high': True, 'size': '(844, 390)'}, {'controls': [{'min': '(154.0, 47.0)', 'rect': '[P: (16.0, 10.0), S: (358.0, 47.0)]', 'text': '食 185  木 215  人口 6/10\n石 100  鐵 0  聚落時代'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 72.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 60.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 60.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 60.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 104.0, 'high': False, 'size': '(390, 844)'}, {'controls': [{'min': '(200.0, 47.0)', 'rect': '[P: (16.0, 10.0), S: (358.0, 47.0)]', 'text': '食 999999  木 999999  人口 6/10\n石 999999  鐵 999999  聚落時代'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 72.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 60.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 60.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 60.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 104.0, 'high': True, 'size': '(390, 844)'}, {'controls': [{'min': '(154.0, 47.0)', 'rect': '[P: (16.0, 10.0), S: (398.0, 47.0)]', 'text': '食 185  木 215  人口 6/10\n石 100  鐵 0  聚落時代'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 72.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 60.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 60.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 60.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 104.0, 'high': False, 'size': '(430, 932)'}, {'controls': [{'min': '(200.0, 47.0)', 'rect': '[P: (16.0, 10.0), S: (398.0, 47.0)]', 'text': '食 999999  木 999999  人口 6/10\n石 999999  鐵 999999  聚落時代'}, {'min': '(35.0, 22.0)', 'rect': '[P: (16.0, 72.0), S: (35.0, 22.0)]', 'text': '00:00'}, {'min': '(60.0, 46.0)', 'rect': '[P: (61.0, 60.0), S: (60.0, 46.0)]', 'text': '暫停'}, {'min': '(54.0, 46.0)', 'rect': '[P: (131.0, 60.0), S: (54.0, 46.0)]', 'text': '受襲4'}, {'min': '(60.0, 46.0)', 'rect': '[P: (195.0, 60.0), S: (60.0, 46.0)]', 'text': '受襲'}], 'height': 104.0, 'high': True, 'size': '(430, 932)'}], 'scope': 'Controlled isolated high-bank and four real alert API records for layout stress, not natural match screenshot.', 'suite': 'measured_battle_topbar_contract', 'transitions': [{'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}], 'spec': [640, False, 4, False]}, {'frames': [{'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}, {'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}, {'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}, {'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}, {'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}, {'height': 81.0, 'resource': '[P: (16.0, 10.0), S: (608.0, 24.0)]', 'valid': True}], 'spec': [640, True, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}], 'spec': [640, False, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}], 'spec': [640, False, 0, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (359.0, 24.0)]', 'valid': True}], 'spec': [640, False, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (361.0, 24.0)]', 'valid': True}], 'spec': [640, False, 0, True]}, {'frames': [{'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (331.0, 24.0)]', 'valid': True}], 'spec': [640, False, 0, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 22.0), S: (338.0, 22.0)]', 'valid': True}], 'spec': [619, False, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (339.0, 24.0)]', 'valid': True}], 'spec': [620, False, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (108.0, 21.0), S: (471.0, 24.0)]', 'valid': True}], 'spec': [844, False, 4, False]}, {'frames': [{'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}, {'height': 54.0, 'resource': '[P: (16.0, 21.0), S: (459.0, 24.0)]', 'valid': True}], 'spec': [740, False, 4, False]}]}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def reject(d):
                (stage/'godot.log').write_text(json.dumps(d)+'\n')
                with self.assertRaises(ValueError):validator.read_report(stage,report['suite'])
            def leaves(value,path):
                if isinstance(value,dict):
                    for k,v in value.items():yield from leaves(v,path+[k])
                elif isinstance(value,list):
                    for i,v in enumerate(value):yield from leaves(v,path+[i])
                else:yield path,value
            for key in ('rows','transitions'):
                for replacement in (None,{},[],report[key][:-1],report[key]+[report[key][0]],list(reversed(report[key]))):
                    d=copy.deepcopy(report);d[key]=replacement;reject(d)
                d=copy.deepcopy(report);del d[key];reject(d)
                for path,value in leaves(report[key],[key]):
                    replacements=['WRONG'] if isinstance(value,str) else ([not value,int(value)] if type(value) is bool else [value+1,str(value)])
                    if type(value) is float:replacements.append(int(value))
                    if type(value) is int:replacements.append(float(value))
                    for replacement in replacements:
                        d=copy.deepcopy(report);ptr=d
                        for p in path[:-1]:ptr=ptr[p]
                        ptr[path[-1]]=replacement;reject(d)
                d=copy.deepcopy(report);d[key][0]['extra']=True;reject(d)


"""Pure injected process races only, never engine evidence or actual process launches."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from contextlib import ExitStack
import subprocess
import signal

class ExportExitRaceTests(unittest.TestCase):
    def exercise(self, module_name, case):
        spec=importlib.util.spec_from_file_location('isolated_'+module_name,Path(__file__).with_name(module_name+'.py'))
        m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
        state={'done':False,'reads':0,'clock':0.0,'waits':0,'signals':{}}
        normal={'available_kib':8388608,'oom_kill':0}
        class Child:
            pid=12345
            def poll(self):return (7 if case=='nonzero' else 0) if state['done'] else None
            def wait(self,timeout):
                if state['done']:return self.poll()
                self.assert_wait(timeout)
                state['waits']+=1
                if case=='deadline':state['clock']=300.001
                if case=='stop':state['signals'][signal.SIGTERM](signal.SIGTERM,None)
                if case in ('exit_after_timeout','nonzero'):state['done']=True
                if case=='exit_during_wait':state['done']=True;return 0
                raise subprocess.TimeoutExpired(['owned'],timeout)
            def assert_wait(self,timeout):assert timeout==0.05
        child=Child()
        def process(c):
            assert c is child
            state['reads']+=1
            if case=='unknown_permission':raise PermissionError('unavailable')
            if state['reads']==1:raise KeyError('VmRSS')
            if case in ('repeat_missing','still_unknown'):raise FileNotFoundError('gone')
            state['done']=True
            return {'VmRSS':2621441 if case=='rss' else 100,'VmHWM':2621441 if case=='hwm' else 100,'Threads':1,'child_pids':['54321'] if case=='descendant' else []}
        def metrics():
            return {'available_kib':100 if case=='reserve' and state['waits'] else 8388608,'oom_kill':1 if case=='oom' and state['waits'] else 0}
        def sig(sig,handler):old=state['signals'].get(sig);state['signals'][sig]=handler;return old
        with tempfile.TemporaryDirectory() as td,ExitStack() as stack:
            for obj,name,value in [(m.subprocess,'Popen',lambda *a,**k:child),(m.p,'metrics',metrics),(m.p,'process_metrics',process),(m.p,'reap_owned',lambda c:{'complete':True,'errors':[],'signals':[]}),(m.p,'observe_descendants',lambda *a:[]),(m.time,'monotonic',lambda:state['clock']),(m.time,'sleep',lambda t:None),(m.signal,'signal',sig)]:stack.enter_context(patch.object(obj,name,value))
            result=m.supervise(['owned'],{},Path(td),normal)
        self.assertEqual(result['cleanup_complete'],case!='descendant');self.assertTrue(result['test_dependencies'])
        self.assertEqual(result['limits'],{'timeout_seconds':300,'admission_kib':4194304,'reserve_kib':1048576,'godot_rss_hwm_kib':2621440,'combined_rss_kib':3145728})
        return result,state

    def test_confirmed_exit_and_complete_live_reread(self):
        for module in ('run_export','run_export_diagnostic'):
            for case in ('exit_after_timeout','exit_during_wait','live_complete'):
                with self.subTest(module=module,case=case):
                    r,s=self.exercise(module,case);self.assertTrue(r['passed']);self.assertTrue(r['export_completed']);self.assertEqual(r['exit'],0)
                    self.assertEqual(r['telemetry_races'][0]['outcome'],'recovered_live_complete_telemetry' if case=='live_complete' else 'confirmed_exit')
                    self.assertEqual(s['reads'],2 if case=='live_complete' else 1)
    def test_unknown_unsafe_or_nonzero_never_pass(self):
        for module in ('run_export','run_export_diagnostic'):
            for case in ('repeat_missing','still_unknown','unknown_permission','rss','hwm','descendant','nonzero','deadline','stop','reserve','oom'):
                with self.subTest(module=module,case=case):
                    r,s=self.exercise(module,case);self.assertFalse(r['passed']);self.assertIn('error',r)
                    self.assertLessEqual(s['reads'],2)
                    if case=='unknown_permission':self.assertEqual(s['waits'],0)

class V123AttackReadabilitySchema0(unittest.TestCase):
    """Frozen actual report, not synthetic gameplay acceptance."""
    def test_exact_five_or_seven_keys_and_nested_values(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'spearman bind 0', 'passed': True}, {'name': 'spearman AB first two preparation ticks still hit', 'passed': True}, {'name': 'spearman AB dense hit preparation cap', 'passed': True}, {'name': 'spearman AB same tick release always wins', 'passed': True}, {'name': 'spearman AB next tick release window', 'passed': True}, {'name': 'spearman AB second tick release window', 'passed': True}, {'name': 'spearman AB age three hit interrupts', 'passed': True}, {'name': 'spearman bind 7', 'passed': True}, {'name': 'spearman target protected release cleared', 'passed': True}, {'name': 'spearman target old attack not retained', 'passed': True}, {'name': 'spearman target observation unchanged', 'passed': True}, {'name': 'spearman bind 11', 'passed': True}, {'name': 'spearman epoch protected release cleared', 'passed': True}, {'name': 'spearman epoch old attack not retained', 'passed': True}, {'name': 'spearman epoch observation unchanged', 'passed': True}, {'name': 'spearman bind 15', 'passed': True}, {'name': 'spearman STOP protected release cleared', 'passed': True}, {'name': 'spearman STOP old attack not retained', 'passed': True}, {'name': 'spearman STOP observation unchanged', 'passed': True}, {'name': 'spearman bind 19', 'passed': True}, {'name': 'spearman MOVE protected release cleared', 'passed': True}, {'name': 'spearman MOVE old attack not retained', 'passed': True}, {'name': 'spearman MOVE observation unchanged', 'passed': True}, {'name': 'spearman bind 23', 'passed': True}, {'name': 'spearman lost protected release cleared', 'passed': True}, {'name': 'spearman lost old attack not retained', 'passed': True}, {'name': 'spearman lost observation unchanged', 'passed': True}, {'name': 'spearman bind 27', 'passed': True}, {'name': 'spearman moving protected release cleared', 'passed': True}, {'name': 'spearman moving old attack not retained', 'passed': True}, {'name': 'spearman moving observation unchanged', 'passed': True}, {'name': 'spearman bind 31', 'passed': True}, {'name': 'spearman garrison protected release cleared', 'passed': True}, {'name': 'spearman garrison old attack not retained', 'passed': True}, {'name': 'spearman garrison observation unchanged', 'passed': True}, {'name': 'spearman bind 35', 'passed': True}, {'name': 'spearman pause_STOP protected release cleared', 'passed': True}, {'name': 'spearman pause_STOP old attack not retained', 'passed': True}, {'name': 'spearman pause_STOP observation unchanged', 'passed': True}, {'name': 'spearman bind 39', 'passed': True}, {'name': 'spearman pause_MOVE protected release cleared', 'passed': True}, {'name': 'spearman pause_MOVE old attack not retained', 'passed': True}, {'name': 'spearman pause_MOVE observation unchanged', 'passed': True}, {'name': 'spearman bind 43', 'passed': True}, {'name': 'spearman pause_same protected release cleared', 'passed': True}, {'name': 'spearman pause_same old attack not retained', 'passed': True}, {'name': 'spearman pause_same observation unchanged', 'passed': True}, {'name': 'spearman bind 47', 'passed': True}, {'name': 'spearman reset protected release cleared', 'passed': True}, {'name': 'spearman reset old attack not retained', 'passed': True}, {'name': 'spearman reset observation unchanged', 'passed': True}, {'name': 'spearman bind 51', 'passed': True}, {'name': 'spearman AB same tick no replay', 'passed': True}, {'name': 'spearman AB death wins', 'passed': True}, {'name': 'spearman bind 54', 'passed': True}, {'name': 'spearman enemy remains original hit priority', 'passed': True}, {'name': 'spearman bind 56', 'passed': True}, {'name': 'spearman nonexplicit attack remains baseline', 'passed': True}, {'name': 'spearman bind 58', 'passed': True}, {'name': 'spearman expired protection never replays consumed hit', 'passed': True}, {'name': 'spearman bind 60', 'passed': True}, {'name': 'spearman cancelled ready restores new hit priority', 'passed': True}, {'name': 'archer bind 62', 'passed': True}, {'name': 'archer AB first two preparation ticks still hit', 'passed': True}, {'name': 'archer AB dense hit preparation cap', 'passed': True}, {'name': 'archer AB same tick release always wins', 'passed': True}, {'name': 'archer AB next tick release window', 'passed': True}, {'name': 'archer AB second tick release window', 'passed': True}, {'name': 'archer AB age three hit interrupts', 'passed': True}, {'name': 'archer bind 69', 'passed': True}, {'name': 'archer target protected release cleared', 'passed': True}, {'name': 'archer target old attack not retained', 'passed': True}, {'name': 'archer target observation unchanged', 'passed': True}, {'name': 'archer bind 73', 'passed': True}, {'name': 'archer epoch protected release cleared', 'passed': True}, {'name': 'archer epoch old attack not retained', 'passed': True}, {'name': 'archer epoch observation unchanged', 'passed': True}, {'name': 'archer bind 77', 'passed': True}, {'name': 'archer STOP protected release cleared', 'passed': True}, {'name': 'archer STOP old attack not retained', 'passed': True}, {'name': 'archer STOP observation unchanged', 'passed': True}, {'name': 'archer bind 81', 'passed': True}, {'name': 'archer MOVE protected release cleared', 'passed': True}, {'name': 'archer MOVE old attack not retained', 'passed': True}, {'name': 'archer MOVE observation unchanged', 'passed': True}, {'name': 'archer bind 85', 'passed': True}, {'name': 'archer lost protected release cleared', 'passed': True}, {'name': 'archer lost old attack not retained', 'passed': True}, {'name': 'archer lost observation unchanged', 'passed': True}, {'name': 'archer bind 89', 'passed': True}, {'name': 'archer moving protected release cleared', 'passed': True}, {'name': 'archer moving old attack not retained', 'passed': True}, {'name': 'archer moving observation unchanged', 'passed': True}, {'name': 'archer bind 93', 'passed': True}, {'name': 'archer garrison protected release cleared', 'passed': True}, {'name': 'archer garrison old attack not retained', 'passed': True}, {'name': 'archer garrison observation unchanged', 'passed': True}, {'name': 'archer bind 97', 'passed': True}, {'name': 'archer pause_STOP protected release cleared', 'passed': True}, {'name': 'archer pause_STOP old attack not retained', 'passed': True}, {'name': 'archer pause_STOP observation unchanged', 'passed': True}, {'name': 'archer bind 101', 'passed': True}, {'name': 'archer pause_MOVE protected release cleared', 'passed': True}, {'name': 'archer pause_MOVE old attack not retained', 'passed': True}, {'name': 'archer pause_MOVE observation unchanged', 'passed': True}, {'name': 'archer bind 105', 'passed': True}, {'name': 'archer pause_same protected release cleared', 'passed': True}, {'name': 'archer pause_same old attack not retained', 'passed': True}, {'name': 'archer pause_same observation unchanged', 'passed': True}, {'name': 'archer bind 109', 'passed': True}, {'name': 'archer reset protected release cleared', 'passed': True}, {'name': 'archer reset old attack not retained', 'passed': True}, {'name': 'archer reset observation unchanged', 'passed': True}, {'name': 'archer bind 113', 'passed': True}, {'name': 'archer AB same tick no replay', 'passed': True}, {'name': 'archer AB death wins', 'passed': True}, {'name': 'archer bind 116', 'passed': True}, {'name': 'archer enemy remains original hit priority', 'passed': True}, {'name': 'archer bind 118', 'passed': True}, {'name': 'archer nonexplicit attack remains baseline', 'passed': True}, {'name': 'archer bind 120', 'passed': True}, {'name': 'archer expired protection never replays consumed hit', 'passed': True}, {'name': 'archer bind 122', 'passed': True}, {'name': 'archer cancelled ready restores new hit priority', 'passed': True}], 'failed': 0, 'scope': 'Combined owned explicit attack controller fixtures. Not natural gameplay or phone proof.', 'suite': 'attack_readability_combined_contract', 'total': 124}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key in report:
                d=copy.deepcopy(report);del d[key];mutants.append(json.dumps(d))
            for key,value in [('failed',False),('failed',0.0),('failed',1),('total',True),('total',float(report['total'])),('total',report['total']-1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                for key in ('name','passed'):
                    d=copy.deepcopy(report);del d['checks'][i][key];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            for value in (None,{},[],list(reversed(report['checks'])),report['checks']+[report['checks'][0]]):
                d=copy.deepcopy(report);d['checks']=value;mutants.append(json.dumps(d))
            if 'build' in report:
                d=copy.deepcopy(report);d['build']='wrong';mutants.append(json.dumps(d))
                def leaves(value,path):
                    if isinstance(value,dict):
                        for k,v in value.items():yield from leaves(v,path+[k])
                    elif isinstance(value,list):
                        for i,v in enumerate(value):yield from leaves(v,path+[i])
                    else:yield path,value
                for path,value in leaves(report['events'],['events']):
                    for replacement in (['wrong'] if isinstance(value,str) else [value+1,str(value),float(value)]):
                        d=copy.deepcopy(report);cur=d
                        for k in path[:-1]:cur=cur[k]
                        cur[path[-1]]=replacement;mutants.append(json.dumps(d))
                for replacement in (None,{},[],report['events'][:-1],report['events']+[report['events'][0]],list(reversed(report['events']))):
                    d=copy.deepcopy(report);d['events']=replacement;mutants.append(json.dumps(d))
                for i in range(len(report['events'])):
                    d=copy.deepcopy(report);d['events'][i]['extra']=True;mutants.append(json.dumps(d))
                    for k in report['events'][i]:
                        d=copy.deepcopy(report);del d['events'][i][k];mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class V123AttackReadabilitySchema1(unittest.TestCase):
    """Frozen actual report, not synthetic gameplay acceptance."""
    def test_exact_five_or_seven_keys_and_nested_values(self):
        import copy
        import validate_latest_contracts as validator
        report={'build': 'vc-3a05feaf79f1', 'checks': [{'name': 'reference target-loss initial unit cells statically legal', 'passed': True}, {'name': 'reference target initially current visible', 'passed': True}, {'name': 'reference ordinary explicit attack really releases', 'passed': True}, {'name': 'reference release protection follows B flag', 'passed': True}, {'name': 'reference actual hidden target removes current ready cue', 'passed': True}, {'name': 'reference hidden target has no active release-age protection', 'passed': True}, {'name': 'reference enemy ordinary move actually travels', 'passed': True}, {'name': 'reference target naturally exits player vision', 'passed': True}, {'name': 'reference game itself retires lost attack target', 'passed': True}, {'name': 'reference own record remains current without ready', 'passed': True}, {'name': 'reference lost target leaves no active protection', 'passed': True}, {'name': 'reference target loss nonempty strict authority', 'passed': True}, {'name': 'reference target loss presentation authority unchanged', 'passed': True}, {'name': 'reference garrison snapped footprints legal against seeded world', 'passed': True}, {'name': 'reference garrison exact snapped positions', 'passed': True}, {'name': 'reference worker outside all static footprints', 'passed': True}, {'name': 'reference villager ordinary attack really releases', 'passed': True}, {'name': 'reference real queued garrison starts pending or enters', 'passed': True}, {'name': 'reference real pending cancels protected release immediately', 'passed': True}, {'name': 'reference real queued garrison cancels combined protected recovery', 'passed': True}, {'name': 'reference ordinary garrison enters host', 'passed': True}, {'name': 'reference garrison removes own current record', 'passed': True}, {'name': 'reference garrison reconciles controller away', 'passed': True}, {'name': 'reference released old controller clears anchors', 'passed': True}, {'name': 'reference ordinary exit restores resident alive', 'passed': True}, {'name': 'reference new current controller after actual garrison', 'passed': True}, {'name': 'reference replacement binds requested flags', 'passed': True}, {'name': 'reference no stale attack or hit replay after exit', 'passed': True}, {'name': 'reference shelter return nonempty strict authority', 'passed': True}, {'name': 'reference shelter return presentation authority unchanged', 'passed': True}, {'name': 'repeat target-loss initial unit cells statically legal', 'passed': True}, {'name': 'repeat target initially current visible', 'passed': True}, {'name': 'repeat ordinary explicit attack really releases', 'passed': True}, {'name': 'repeat release protection follows B flag', 'passed': True}, {'name': 'repeat actual hidden target removes current ready cue', 'passed': True}, {'name': 'repeat hidden target has no active release-age protection', 'passed': True}, {'name': 'repeat enemy ordinary move actually travels', 'passed': True}, {'name': 'repeat target naturally exits player vision', 'passed': True}, {'name': 'repeat game itself retires lost attack target', 'passed': True}, {'name': 'repeat own record remains current without ready', 'passed': True}, {'name': 'repeat lost target leaves no active protection', 'passed': True}, {'name': 'repeat target loss nonempty strict authority', 'passed': True}, {'name': 'repeat target loss presentation authority unchanged', 'passed': True}, {'name': 'repeat target loss full authority equals identical combined repeat', 'passed': True}, {'name': 'repeat garrison snapped footprints legal against seeded world', 'passed': True}, {'name': 'repeat garrison exact snapped positions', 'passed': True}, {'name': 'repeat worker outside all static footprints', 'passed': True}, {'name': 'repeat villager ordinary attack really releases', 'passed': True}, {'name': 'repeat real queued garrison starts pending or enters', 'passed': True}, {'name': 'repeat real pending cancels protected release immediately', 'passed': True}, {'name': 'repeat real queued garrison cancels combined protected recovery', 'passed': True}, {'name': 'repeat ordinary garrison enters host', 'passed': True}, {'name': 'repeat garrison removes own current record', 'passed': True}, {'name': 'repeat garrison reconciles controller away', 'passed': True}, {'name': 'repeat released old controller clears anchors', 'passed': True}, {'name': 'repeat ordinary exit restores resident alive', 'passed': True}, {'name': 'repeat new current controller after actual garrison', 'passed': True}, {'name': 'repeat replacement binds requested flags', 'passed': True}, {'name': 'repeat no stale attack or hit replay after exit', 'passed': True}, {'name': 'repeat shelter return nonempty strict authority', 'passed': True}, {'name': 'repeat shelter return presentation authority unchanged', 'passed': True}, {'name': 'repeat shelter return full authority equals identical combined repeat', 'passed': True}], 'events': [{'attack_tick': 1, 'case': 'target loss', 'mode': 'reference', 'phase': 'release', 'target_hp': 107, 'tick': 1}, {'case': 'target loss', 'enemy_hp': 107, 'enemy_position': '(29.25, 0.0, -2.5)', 'hidden_tick': 34, 'mode': 'reference', 'own_position': '(16.95, 0.0, -3.5)', 'own_state': 'idle', 'own_target': -1, 'phase': 'retired', 'tick': 125}, {'attack_tick': 1, 'case': 'shelter return', 'mode': 'reference', 'phase': 'release', 'target_hp': 247, 'tick': 1}, {'case': 'shelter return', 'clip': 'idle', 'mode': 'reference', 'phase': 'pending', 'protected_release_tick': -1, 'tick': 2}, {'case': 'shelter return', 'garrison_host': 102, 'mode': 'reference', 'phase': 'inside', 'tick': 20}, {'case': 'shelter return', 'mode': 'reference', 'phase': 'exited', 'tick': 21, 'worker_hp': 35, 'worker_pos': '(5.5, 0.0, -5.5)'}, {'attack_tick': 1, 'case': 'target loss', 'mode': 'repeat', 'phase': 'release', 'target_hp': 107, 'tick': 1}, {'case': 'target loss', 'enemy_hp': 107, 'enemy_position': '(29.25, 0.0, -2.5)', 'hidden_tick': 34, 'mode': 'repeat', 'own_position': '(16.95, 0.0, -3.5)', 'own_state': 'idle', 'own_target': -1, 'phase': 'retired', 'tick': 125}, {'attack_tick': 1, 'case': 'shelter return', 'mode': 'repeat', 'phase': 'release', 'target_hp': 247, 'tick': 1}, {'case': 'shelter return', 'clip': 'idle', 'mode': 'repeat', 'phase': 'pending', 'protected_release_tick': -1, 'tick': 2}, {'case': 'shelter return', 'garrison_host': 102, 'mode': 'repeat', 'phase': 'inside', 'tick': 20}, {'case': 'shelter return', 'mode': 'repeat', 'phase': 'exited', 'tick': 21, 'worker_hp': 35, 'worker_pos': '(5.5, 0.0, -5.5)'}], 'failed': 0, 'scope': 'Controlled initial actors and AI disabled; subsequent ordinary attack/move/garrison commands and real ticks. No post-setup HP, resource, terrain, fog, teleport or target-field writes. Not a natural economic match.', 'suite': 'attack_readability_combined_lifecycle', 'total': 62}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key in report:
                d=copy.deepcopy(report);del d[key];mutants.append(json.dumps(d))
            for key,value in [('failed',False),('failed',0.0),('failed',1),('total',True),('total',float(report['total'])),('total',report['total']-1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                for key in ('name','passed'):
                    d=copy.deepcopy(report);del d['checks'][i][key];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            for value in (None,{},[],list(reversed(report['checks'])),report['checks']+[report['checks'][0]]):
                d=copy.deepcopy(report);d['checks']=value;mutants.append(json.dumps(d))
            if 'build' in report:
                d=copy.deepcopy(report);d['build']='wrong';mutants.append(json.dumps(d))
                def leaves(value,path):
                    if isinstance(value,dict):
                        for k,v in value.items():yield from leaves(v,path+[k])
                    elif isinstance(value,list):
                        for i,v in enumerate(value):yield from leaves(v,path+[i])
                    else:yield path,value
                for path,value in leaves(report['events'],['events']):
                    for replacement in (['wrong'] if isinstance(value,str) else [value+1,str(value),float(value)]):
                        d=copy.deepcopy(report);cur=d
                        for k in path[:-1]:cur=cur[k]
                        cur[path[-1]]=replacement;mutants.append(json.dumps(d))
                for replacement in (None,{},[],report['events'][:-1],report['events']+[report['events'][0]],list(reversed(report['events']))):
                    d=copy.deepcopy(report);d['events']=replacement;mutants.append(json.dumps(d))
                for i in range(len(report['events'])):
                    d=copy.deepcopy(report);d['events'][i]['extra']=True;mutants.append(json.dumps(d))
                    for k in report['events'][i]:
                        d=copy.deepcopy(report);del d['events'][i][k];mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)

class V123AttackReadabilitySchema2(unittest.TestCase):
    """Frozen actual report, not synthetic gameplay acceptance."""
    def test_exact_five_or_seven_keys_and_nested_values(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': '[true, true] flags bind before initial observation', 'passed': True}, {'name': '[true, true] actual currently observed enemy has controller', 'passed': True}, {'name': '[true, true] ordinary scout movement removes actual enemy vision', 'passed': True}, {'name': '[true, true] actual fog reconciles enemy controller away', 'passed': True}, {'name': '[true, true] ordinary scout return restores current observation', 'passed': True}, {'name': '[true, true] reobserved controller comes from actual current record', 'passed': True}, {'name': '[true, true] new controller rebound after real fog removal', 'passed': True}, {'name': '[true, true] enemy has no owned attack protection', 'passed': True}, {'name': '[true, true] fog movement final authority remains strict valid', 'passed': True}], 'failed': 0, 'scope': 'Actual executed fixture when this report is emitted: actual enemy fog removal/reappearance with fixed flags, not protected own-unit hidden release proof.', 'suite': 'attack_readability_combined_fog', 'total': 9}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key in report:
                d=copy.deepcopy(report);del d[key];mutants.append(json.dumps(d))
            for key,value in [('failed',False),('failed',0.0),('failed',1),('total',True),('total',float(report['total'])),('total',report['total']-1),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                for key in ('name','passed'):
                    d=copy.deepcopy(report);del d['checks'][i][key];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            for value in (None,{},[],list(reversed(report['checks'])),report['checks']+[report['checks'][0]]):
                d=copy.deepcopy(report);d['checks']=value;mutants.append(json.dumps(d))
            if 'build' in report:
                d=copy.deepcopy(report);d['build']='wrong';mutants.append(json.dumps(d))
                def leaves(value,path):
                    if isinstance(value,dict):
                        for k,v in value.items():yield from leaves(v,path+[k])
                    elif isinstance(value,list):
                        for i,v in enumerate(value):yield from leaves(v,path+[i])
                    else:yield path,value
                for path,value in leaves(report['events'],['events']):
                    for replacement in (['wrong'] if isinstance(value,str) else [value+1,str(value),float(value)]):
                        d=copy.deepcopy(report);cur=d
                        for k in path[:-1]:cur=cur[k]
                        cur[path[-1]]=replacement;mutants.append(json.dumps(d))
                for replacement in (None,{},[],report['events'][:-1],report['events']+[report['events'][0]],list(reversed(report['events']))):
                    d=copy.deepcopy(report);d['events']=replacement;mutants.append(json.dumps(d))
                for i in range(len(report['events'])):
                    d=copy.deepcopy(report);d['events'][i]['extra']=True;mutants.append(json.dumps(d))
                    for k in report['events'][i]:
                        d=copy.deepcopy(report);del d['events'][i][k];mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


class V124FoodFarmSchema0(unittest.TestCase):
    """Frozen actual report, not synthetic gameplay acceptance."""
    def test_exact_four_keys_names_order_and_types(self):
        import copy
        import validate_latest_contracts as validator
        report={'checks': [{'name': 'loaded selected miner can plan vacant farm with ordinary marker', 'passed': True}, {'name': 'unknown occupancy fails closed', 'passed': True}, {'name': 'occupied farm excluded', 'passed': True}, {'name': 'pending farm destination reserved', 'passed': True}, {'name': 'pending worker construction preserved', 'passed': True}, {'name': 'farm rejects alive', 'passed': True}, {'name': 'farm rejects built', 'passed': True}, {'name': 'farm rejects owned', 'passed': True}, {'name': 'farm rejects remembered', 'passed': True}, {'name': 'farm rejects team', 'passed': True}, {'name': 'loaded pending farmer reserves field before ledger claim', 'passed': True}, {'name': 'currently observed threat excludes farm', 'passed': True}, {'name': 'remembered enemy not hidden threat oracle', 'passed': True}, {'name': 'three miners two fields assign distinct farmers once', 'passed': True}, {'name': 'surplus worker may still use ordinary berries', 'passed': True}, {'name': 'farm never becomes wood target', 'passed': True}, {'name': 'empty idle worker food dispatch includes vacant farm', 'passed': True}, {'name': 'idle dispatch still refuses loaded worker', 'passed': True}, {'name': 'planning does not mutate records or ledger', 'passed': True}, {'name': 'ordinary construction costs exactly sixty wood', 'passed': True}, {'name': 'ordinary paid farm completes and automatically farms', 'passed': True}, {'name': 'both workers earn real wood and farm is vacant', 'passed': True}, {'name': 'actual current observation food plan chooses nearby paid farm', 'passed': True}, {'name': 'food reassign target remains reachable (320, 568)', 'passed': True}, {'name': 'food reassign target remains reachable (390, 844)', 'passed': True}, {'name': 'food reassign target remains reachable (640, 360)', 'passed': True}, {'name': 'pause cannot submit food shortcut', 'passed': True}, {'name': 'changed held selection cannot submit', 'passed': True}, {'name': 'food shortcut root touch point visible inside scroll', 'passed': True}, {'name': 'controller submits one marked ordinary farm order', 'passed': True}, {'name': 'pending farm shortcut exact build codec accepts', 'passed': True}, {'name': 'pending farm shortcut restore preserves full authority', 'passed': True}, {'name': 'accepted loaded worker preserves cargo before normal delivery', 'passed': True}, {'name': 'cargo delivery awaiting farm claim exact build codec accepts', 'passed': True}, {'name': 'cargo delivery awaiting farm claim restore preserves full authority', 'passed': True}, {'name': 'competing worker receives distinct ordinary command identity', 'passed': True}, {'name': 'same tick second loaded farmer rejected atomically', 'passed': True}, {'name': 'duplicate command cannot reset work', 'passed': True}, {'name': 'stale epoch command has a fresh identity', 'passed': True}, {'name': 'fresh identity stale epoch rejected atomically', 'passed': True}, {'name': 'shortcut farmer physically generates and deposits ten food', 'passed': True}, {'name': 'normal ledger remains conserved', 'passed': True}, {'name': 'normal stop releases a genuinely empty farmer', 'passed': True}, {'name': 'actual idle food plan includes nearby vacant paid field', 'passed': True}, {'name': 'idle shortcut actually assigns one farmer without extra payment', 'passed': True}], 'failed': 0, 'scope': 'Pure observed-policy negatives plus fresh practice paid farm, real wood cargo, normal controller transfer and food delivery; no phone claim', 'suite': 'food_farm_shortcut_contract'}
        with tempfile.TemporaryDirectory() as td:
            stage=Path(td)
            def read(raw):
                (stage/'godot.log').write_text(raw+'\n')
                return validator.read_report(stage,report['suite'])
            self.assertEqual(read(json.dumps(report)),report)
            mutants=[]
            for key in report:
                d=copy.deepcopy(report);del d[key];mutants.append(json.dumps(d))
            for key,value in [('failed',False),('failed',0.0),('failed',1),('total',45),('scope','wrong'),('suite','wrong')]:
                d=copy.deepcopy(report);d[key]=value;mutants.append(json.dumps(d))
            for i in range(len(report['checks'])):
                for value in (False,1):
                    d=copy.deepcopy(report);d['checks'][i]['passed']=value;mutants.append(json.dumps(d))
                for key in ('name','passed'):
                    d=copy.deepcopy(report);del d['checks'][i][key];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);del d['checks'][i];mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['name']+=' wrong';mutants.append(json.dumps(d))
                d=copy.deepcopy(report);d['checks'][i]['extra']=True;mutants.append(json.dumps(d))
            for value in (None,{},[],list(reversed(report['checks'])),report['checks']+[report['checks'][0]]):
                d=copy.deepcopy(report);d['checks']=value;mutants.append(json.dumps(d))
            if 'build' in report:
                d=copy.deepcopy(report);d['build']='wrong';mutants.append(json.dumps(d))
                def leaves(value,path):
                    if isinstance(value,dict):
                        for k,v in value.items():yield from leaves(v,path+[k])
                    elif isinstance(value,list):
                        for i,v in enumerate(value):yield from leaves(v,path+[i])
                    else:yield path,value
                for path,value in leaves(report['events'],['events']):
                    for replacement in (['wrong'] if isinstance(value,str) else [value+1,str(value),float(value)]):
                        d=copy.deepcopy(report);cur=d
                        for k in path[:-1]:cur=cur[k]
                        cur[path[-1]]=replacement;mutants.append(json.dumps(d))
                for replacement in (None,{},[],report['events'][:-1],report['events']+[report['events'][0]],list(reversed(report['events']))):
                    d=copy.deepcopy(report);d['events']=replacement;mutants.append(json.dumps(d))
                for i in range(len(report['events'])):
                    d=copy.deepcopy(report);d['events'][i]['extra']=True;mutants.append(json.dumps(d))
                    for k in report['events'][i]:
                        d=copy.deepcopy(report);del d['events'][i][k];mutants.append(json.dumps(d))
            d=copy.deepcopy(report);d['extra']=True;mutants.append(json.dumps(d))
            raw=json.dumps(report);mutants.extend([raw+'\n'+raw,raw[:-1]+',"failed":0}', 'ERROR: failure\n'+raw])
            for raw in mutants:
                with self.subTest(raw=raw):
                    with self.assertRaises(ValueError):read(raw)


if __name__=='__main__':unittest.main(verbosity=2)


import unittest,tempfile
from pathlib import Path
from unittest.mock import patch
import run_export as e
class ExportExitPhaseReaderTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name);self.p=self.root/'123';self.t=self.p/'task/123';self.t.mkdir(parents=True)
  tail=['0']*50;tail[0]='R';tail[1]='122';tail[6]='4194316';tail[19]='42'
  for d in (self.p,self.t):
   (d/'stat').write_text('123 (name (parens)) '+' '.join(tail))
   (d/'status').write_text('Pid: 123\nTgid: 123\nThreads: 1\n')
   (d/'statm').write_text('0 0 0 0 0 0 0\n')
  (self.t/'children').write_text('')
  self.expected=e.exit_identity(123,self.root)
 def run_snapshot(self):return e.exit_snapshot(123,self.expected,self.root)
 def test_valid(self):self.assertTrue(self.run_snapshot()['mm_detached'])
 def test_bad_evidence(self):
  cases=[('status','Pid: 124\nTgid: 123\nThreads: 1\n'),('status','Pid: 123\nTgid: 124\nThreads: 1\n'),('status','Pid: 123\nTgid: 123\nThreads: 2\n'),('status','Pid: 123\nTgid: 123\nThreads: 1\nVmRSS: 0 kB\n'),('status','Pid: 123\nTgid: 123\nThreads: 1\nVmHWM: 2 kB\n'),('statm','0 0 0 0 0 0'),('statm','0 0 0 0 0 0 0 0'),('statm','1 0 0 0 0 0 0'),('statm','-1 0 0 0 0 0 0'),('statm','x 0 0 0 0 0 0')]
  for d in (self.p,self.t):
   for name,value in cases:
    with self.subTest(path=str(d),value=value):
     f=d/name;original=f.read_text();f.write_text(value)
     try:
      with self.assertRaises((RuntimeError,ValueError,KeyError)):self.run_snapshot()
     finally:f.write_text(original)
 def test_children(self):
  (self.t/'children').write_text('456')
  with self.assertRaises(RuntimeError):self.run_snapshot()
 def test_siblings(self):
  (self.p/'task/124').mkdir()
  with self.assertRaises(RuntimeError):self.run_snapshot()
 def test_flag_lifetime(self):
  for d in (self.p,self.t):
   f=d/'stat';original=f.read_text()
   for old,new in [('4194316','4194312'),('122','125'),('42','43')]:
    with self.subTest(path=str(d),change=old):
     f.write_text(original.replace(old,new))
     try:
      with self.assertRaises(RuntimeError):self.run_snapshot()
     finally:f.write_text(original)
 def test_unknown(self):
  for exc in (PermissionError,FileNotFoundError,ProcessLookupError):
   with patch.object(e,'exit_read',side_effect=exc):
    with self.assertRaises(exc):self.run_snapshot()
 def test_oversized(self):
  (self.t/'children').write_text(' '*65537)
  with self.assertRaises(RuntimeError):self.run_snapshot()


import unittest,importlib.util,sys,tempfile,signal,subprocess,os
from pathlib import Path
from unittest.mock import patch
from contextlib import ExitStack
class ExportExitPhaseRunnerTests(unittest.TestCase):
 def run_case(self,name,case):
  spec=importlib.util.spec_from_file_location('isolated_'+name,Path(__file__).with_name(name+'.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  s={'done':False,'reads':0,'proof':0,'clock':0.,'signals':{},'phase':False}
  normal={'available_kib':8388608,'oom_kill':0}
  class Child:
   pid=12345
   def poll(self):return (7 if case=='nonzero' else 0) if s['done'] else None
   def wait(self,timeout):
    if s['done']:return self.poll()
    raise subprocess.TimeoutExpired(['owned'],timeout)
  child=Child()
  def process(c):
   s['reads']+=1
   if s['reads']==1 and case!='no_sample':return {'VmRSS':100,'VmHWM':100,'Threads':1,'child_pids':[]}
   raise KeyError('VmRSS')
  def ident(pid):return {'pid':pid,'ppid':os.getpid()+int(case=='wrong_parent'),'starttime_ticks':42}
  def proof(pid,expected):
   s['proof']+=1;s['phase']=True
   if case=='descendant':raise m.ExitPhaseDescendants(['54321'])
   if case=='unknown':raise PermissionError()
   if case=='mismatch':raise RuntimeError('Bad proof')
   if case=='missing_alive':raise FileNotFoundError()
   if case=='missing_exited':s['done']=True;raise FileNotFoundError()
   return {'pid':pid,'mm_detached':True}
  def sleep(t):
   s['clock']+=t
   if s['phase']:
    if case=='stop':s['signals'][signal.SIGTERM](signal.SIGTERM,None)
    elif case=='deadline':s['clock']=300.001
    elif case not in ('stuck','reserve','oom','oversize'):s['done']=True
  def metrics():return {'available_kib':100 if case=='reserve' and s['phase'] else 8388608,'oom_kill':int(case=='oom' and s['phase'])}
  def sig(k,h):old=s['signals'].get(k);s['signals'][k]=h;return old
  with tempfile.TemporaryDirectory() as td,ExitStack() as st:
   def proof_with_log(pid,expected):
    value=proof(pid,expected)
    if case=='oversize':
     with (Path(td)/'godot.log').open('ab') as f:f.truncate(16*1024*1024+1)
    return value
   for obj,k,v in [(m.subprocess,'Popen',lambda *a,**kw:child),(m.p,'metrics',metrics),(m.p,'process_metrics',process),(m.p,'observe_descendants',lambda *a: s.update(observed=True) or []),(m.p,'reap_owned',lambda c:{'complete':True,'errors':[],'signals':[]}),(m.time,'monotonic',lambda:s['clock']),(m.time,'sleep',sleep),(m.signal,'signal',sig),(m,'exit_identity',ident),(m,'exit_snapshot',proof_with_log)]:st.enter_context(patch.object(obj,k,v))
   result=m.supervise(['owned'],{},Path(td),normal)
  self.assertTrue(result['test_dependencies']);self.assertEqual(result['cleanup_complete'],case!='descendant');
  if case=='descendant':self.assertTrue(s.get('observed'));
  self.assertEqual(result['limits']['timeout_seconds'],300)
  return result,s
 def test_cases(self):
  for name in ('run_export','run_export_diagnostic'):
   for case in ('valid','missing_exited','nonzero','no_sample','wrong_parent','descendant','unknown','mismatch','missing_alive','stuck','stop','deadline','reserve','oom','oversize'):
    with self.subTest(name=name,case=case):
     r,s=self.run_case(name,case);self.assertEqual(r['passed'],case in ('valid','missing_exited'))
     if r['passed']:
      self.assertEqual(r['exit'],0)
      if case=='valid':self.assertTrue(r['verified_exit_phase'])
      else:self.assertNotIn('verified_exit_phase',r);self.assertEqual(r['telemetry_races'][0]['outcome'],'confirmed_exit')
     else:self.assertIn('error',r)
