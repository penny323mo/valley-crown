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
            if suite=='resource_visual_contract':line='\n'.join('RESOURCE_METRIC '+k+' vertices='+str(n)+' surfaces=1 bounds=(synthetic schema fixture)' for k,n in [('stone',1008),('iron',1008),('berry',3402)])+'\nRESOURCE_CONTRACT_PASS 27'
            if suite=='resource_polish_contract':line='RESOURCE_POLISH_PASS 24'
            if suite=='normal_probe':line='NORMALS_PASS 3'
            if suite=='skirmish_policy_contract':line='SKIRMISH 17/17'
            if suite in latest.ARMY_CONTRACTS:line=json.dumps({'suite':latest.ARMY_CONTRACTS[suite]['suite'],'checks':[{'name':n,'passed':True} for n in latest.ARMY_CONTRACTS[suite]['names']],'failed':0})
            if 'identity' in latest.ARMY_CONTRACTS.get(suite,{}):d=json.loads(line);d.update(latest.ARMY_CONTRACTS[suite]['identity']);line=json.dumps(d)
            if 'scope' in latest.ARMY_CONTRACTS.get(suite,{}):d=json.loads(line);d['scope']=latest.ARMY_CONTRACTS[suite]['scope'];line=json.dumps(d)
            if suite=='wall_line_contract':
                d=json.loads(line)
                d['geometry']=[{'size':size,'top':'synthetic schema fixture','bottom':'synthetic schema fixture','scroll':'synthetic schema fixture','queue':'synthetic schema fixture','summary':'synthetic schema fixture','buttons':[{'text':'synthetic schema fixture','rect':'synthetic schema fixture'} for _ in range(6)]} for size in ['(390, 844)','(320, 568)','(568, 320)','(1280, 800)']]
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


if __name__=='__main__':unittest.main(verbosity=2)
