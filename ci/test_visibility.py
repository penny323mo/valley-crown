"""Inert synthetic schema/argv/failure checks, never engine or telemetry."""
import copy,json,hashlib,tempfile,types,unittest,os
from pathlib import Path
from unittest.mock import patch
import run_visibility as r
import validate_visibility as v
HERE=Path(__file__).resolve().parent
NAMES=json.loads((HERE/'visibility_names.json').read_text())
SOURCE=Path(os.environ.get('VISIBILITY_TEST_GAME',str(HERE.parent/'game')))
FILES={n:hashlib.sha256((SOURCE/n).read_bytes()).hexdigest() for n in v.SOURCE_NAMES}
FILES[v.FIXTURE]=v.FIXTURE_SHA

def example(variant='candidate'):
    files=dict(FILES);files['scripts/game.gd']=v.SOURCE_SHAS[variant]
    lock={'build':r.r.BUILD,'project_files':files}
    phases=[n.removesuffix(' real root signal count') for n in NAMES if n.endswith(' real root signal count')]
    report={'suite':v.SUITE,'build':lock['build'],'scope':v.SCOPE,'variant':variant,'source_sha256':{n:files[n] for n in v.SOURCE_NAMES},'fixture_sha256':v.FIXTURE_SHA,'engine':{'major':4,'minor':6,'patch':3,'status':'stable','build':'official'},'passed':124,'failure_count':0,'checks':[{'name':n,'passed':True} for n in NAMES],'signal_batches':[{'phase':p,'repeats':3 if p in ('own selected damaged','enemy observed damaged') else 2,'counts':{} if variant=='candidate' else {'root':4}} for p in phases],'signal_samples':[],'signal_sample_limit':128,'signal_events_seen':0,'projection_states':[{'label':str(i),'record':{},'authority_visible':False,'authority_in_tree':False,'ring':False,'bar':None} for i in range(44)]}
    return report,lock

class Tests(unittest.TestCase):
    def test_both_synthetic_schemas(self):
        for variant in ('baseline','candidate'):
            report,lock=example(variant);self.assertIs(v.validate(report,lock,NAMES),report)
    def test_report_negatives(self):
        changes=[lambda x:x.update(extra=True),lambda x:x.update(build='wrong'),lambda x:x.update(scope='FPS proof'),lambda x:x.update(variant='unknown'),lambda x:x.update(fixture_sha256='0'*64),lambda x:x['source_sha256'].update({'scripts/game.gd':'0'*64}),lambda x:x['checks'].pop(),lambda x:x['checks'][0].update(passed=False),lambda x:x['checks'][0].update(passed=1),lambda x:x['checks'][0].update(name='wrong'),lambda x:x.update(passed=True),lambda x:x.update(failure_count=False),lambda x:x['engine'].update(patch=2),lambda x:x['signal_batches'].pop(),lambda x:x['signal_batches'][0].update(counts={'root':1}),lambda x:x['signal_batches'][0].update(repeats=99),lambda x:x.update(signal_sample_limit=512),lambda x:x.update(signal_events_seen=-1),lambda x:x['projection_states'].pop(),lambda x:x['projection_states'][0].update(secret='forbidden')]
        for index,change in enumerate(changes):
            report,lock=example();change(report)
            with self.subTest(index=index),self.assertRaises((ValueError,KeyError,TypeError)):v.validate(report,lock,NAMES)
    def test_strict_json_and_logs(self):
        report,lock=example();line=json.dumps(report)
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'godot.log';p.write_text('Godot startup\n'+line+'\n');v.read_log(p,lock,NAMES)
            for bad in [line+'\n'+line,'{"a":1,"a":2}','{"a":NaN}','{"a":Infinity}','{"a":1e999}','{bad',line[:-1]+',"padding":"'+'x'*(128*1024)+'"}']:
                p.write_text(bad+'\n')
                with self.assertRaises((ValueError,KeyError)):v.read_log(p,lock,NAMES)
    def test_fixed_argv(self):
        self.assertEqual(r.argv('/godot','/project'),['/godot','--headless','--path','/project','--audio-driver','Dummy','--resolution','390x844','--fixed-fps','30','--script','res://tests/visibility_once_lifecycle.gd'])
    def test_pending_stops_before_metrics(self):
        with tempfile.TemporaryDirectory() as d,patch.object(r.p,'metrics',side_effect=AssertionError('live metrics forbidden')):
            p=Path(d)/'lock.json';p.write_text('{"visibility_reviewed_for_execution":false}')
            with self.assertRaisesRegex(RuntimeError,'not reviewed'):r.run(types.SimpleNamespace(lock=p))
    def test_original_supervisor_bytes(self):
        self.assertEqual(hashlib.sha256(Path(r.logic.__file__).read_bytes()).hexdigest(),r.LOGIC_SHA)
        self.assertEqual(hashlib.sha256(Path(r.p.__file__).read_bytes()).hexdigest(),'7fd227386d083f35bf55390a26a96c70472ba4a0def0f781f9a28aeeaa59cb2e')

if __name__=='__main__':unittest.main()
