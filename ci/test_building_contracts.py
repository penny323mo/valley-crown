"""Pure negative/data tests. Never invoke Godot, monitors, resource sampling or jobs."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
import validate_building_contracts as v
ROOT=Path(__file__).resolve().parent

def report(suite):
    if suite.startswith('advanced_'):
        key='visual_acceptance' if suite=='advanced_building_visuals' else 'ordinary_gameplay_visual'
        return {'suite':suite,'checks':v.COUNTS[suite],'failures':[],key:'NOT_TESTED'}
    result={'checks':[{'name':'fixture '+str(i),'pass':True,**({'detail':{}} if suite=='map80_sparse_memory' else {})} for i in range(v.COUNTS[suite])], 'passed':v.COUNTS[suite],'failed':0}
    if suite in v.EXTERNAL:result.update(suite=suite,build=v.BUILD)
    elif suite=='construction_visual':result.update(build=v.BUILD,scope=v.SCOPE)
    else:result['scope']=v.SPARSE_SCOPE
    return result

class Contracts(unittest.TestCase):
    def test_good_schemas(self):
        for suite in v.SUITES:v.validate_report(report(suite),suite)
    def test_wrong_suite(self):
        for suite in v.SUITES:
            r=report(suite);r['suite']='wrong'
            with self.assertRaises(ValueError):v.validate_report(r,suite)
    def test_wrong_build(self):
        for suite in (*v.EXTERNAL,'construction_visual'):
            r=report(suite);r['build']='vc-old'
            with self.assertRaises(ValueError):v.validate_report(r,suite)
    def test_wrong_counts(self):
        for suite in v.SUITES:
            for count in (-1,0,True,v.COUNTS[suite]-1,v.COUNTS[suite]+1):
                r=report(suite)
                if suite.startswith('advanced_'):r['checks']=count
                else:r['passed']=count
                with self.assertRaises(ValueError):v.validate_report(r,suite)
    def test_failed_checks(self):
        for suite in v.SUITES:
            r=report(suite)
            if suite.startswith('advanced_'):r['failures']=['failed']
            else:r['checks'][0]['pass']=False
            with self.assertRaises(ValueError):v.validate_report(r,suite)
    def test_missing_check(self):
        for suite in v.SUITES:
            r=report(suite);del r['checks']
            with self.assertRaises((ValueError,KeyError)):v.validate_report(r,suite)
    def test_duplicate_json_and_nonfinite(self):
        for text in ('{"checks":175,"checks":175}', '{"checks":NaN}', '{"checks":Infinity}'):
            with self.assertRaises(ValueError):v.parse_json(text)
    def test_missing_duplicate_and_error_reports(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            stage=Path(directory)
            for suite in v.SUITES:
                r=report(suite)
                if suite=='construction_visual':
                    (stage/v.REPORT).write_text(json.dumps(r));line='CONSTRUCTION_VISUAL_CONTRACT passed=203 failed=0'
                else:line=('MAP80_SPARSE_MEMORY ' if suite=='map80_sparse_memory' else '')+json.dumps(r)
                (stage/'godot.log').write_text('Godot Engine\n'+line+'\n')
                self.assertEqual(v.read_report(stage,suite),r)
                for text in ('Godot Engine\n',line+'\n'+line+'\n','ERROR: failure\n'+line+'\n'):
                    (stage/'godot.log').write_text(text)
                    with self.assertRaises(ValueError):v.read_report(stage,suite)
            (stage/'godot.log').write_text('CONSTRUCTION_VISUAL_CONTRACT passed=203 failed=0\n')
            (stage/v.REPORT).unlink()
            with self.assertRaises(FileNotFoundError):v.read_report(stage,'construction_visual')
    def test_identity_and_source_drift(self):
        good={'building_reviewed_for_execution':True,'build':v.BUILD,'game_tree':v.GAME_TREE,
              'project_files':json.loads((ROOT/'frozen-project-files.json').read_text())}
        v.validate_identity(good)
        for key,value in [('building_reviewed_for_execution',False),('build','wrong'),('game_tree','wrong')]:
            changed=copy.deepcopy(good);changed[key]=value
            with self.assertRaises(ValueError):v.validate_identity(changed)
        for mode in ('missing','extra','changed'):
            changed=copy.deepcopy(good);files=changed['project_files']
            if mode=='missing':files.pop('scripts/game.gd')
            elif mode=='extra':files['unexpected']='0'*64
            else:files['scripts/game.gd']='0'*64
            with self.assertRaises(ValueError):v.validate_identity(changed)
    def test_monitor_rejects_mocks_missing_and_failed(self):
        good={'passed':True,'cleanup_complete':True,'test_dependencies':False,'unexpected_descendants':[],
              'exit':0,'limits':v.LIMITS,'logic_completed':True,'samples':[{}],'pid':123}
        v.validate_monitor(good)
        for key,value in [('passed',False),('cleanup_complete',False),('test_dependencies',True),('unexpected_descendants',[1]),('exit',True),('limits',{}),('logic_completed',False),('samples',[]),('pid',None),('error',{'message':'failed'})]:
            bad=copy.deepcopy(good);bad[key]=value
            with self.assertRaises(ValueError):v.validate_monitor(bad)
        for key in good:
            bad=copy.deepcopy(good);del bad[key]
            with self.assertRaises(ValueError):v.validate_monitor(bad)

if __name__=='__main__':unittest.main(verbosity=2)
