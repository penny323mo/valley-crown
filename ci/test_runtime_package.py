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


if __name__=='__main__':unittest.main(verbosity=2)
