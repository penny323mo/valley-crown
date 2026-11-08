import ast,hashlib,json,tempfile,unittest
from pathlib import Path
import collect_render_failure as c
class Tests(unittest.TestCase):
    def fixture(self,root,render=True):
        imp=root/'import';imp.mkdir()
        invocation={'test_dependencies':False,'helper':{'load_sha256':c.MONITOR_SHA,'invocation_sha256':c.MONITOR_SHA},'artifacts':{'engine':{'sha256':c.ENGINE_SHA}},'argv':['/engine','--headless','--editor','--path','/project','--import']}
        invocation['requested_argv']=invocation['argv']
        (imp/'import.invocation.json').write_text(json.dumps(invocation));(imp/'import.log').write_text('ERROR: fixture import failure\n')
        receipt={'cleanup_complete':True,'child_started':True,'cleanup_errors':[],'exit':1,'log_sha256':c.digest((imp/'import.log').read_bytes()),'invocation_sha256':c.digest((imp/'import.invocation.json').read_bytes())}
        (imp/'import.json').write_text(json.dumps(receipt))
        if render:
            scenario=root/'render/studies';scenario.mkdir(parents=True);(scenario/'frames').mkdir();(scenario/'frames/private.png').write_bytes(b'NEVER COPY FRAME')
            for name in ('godot','xvfb'):(scenario/(name+'.log')).write_text('SCRIPT ERROR: fixture renderer failure\n')
            guard={'cleanup_complete':True,'test_dependencies':False,'unexpected_descendants':[],'observed_descendant_cleanup':[],'input_sha256':{'godot':c.ENGINE_SHA,'xvfb':'a'*64},'children':{'godot':{'pid':123,'executable_sha256':c.ENGINE_SHA},'xvfb':{'pid':122,'executable_sha256':'a'*64}},'cleanup':{n:{'complete':True,'exit':1,'errors':[],'signals':['SIGTERM']} for n in ('godot','xvfb')},'startup':{'complete':True,'detected':False,'helpers':[],'distribution':{'xvfb':{'sha256':'a'*64}}}}
            (scenario/'guard-receipt.json').write_text(json.dumps(guard))
        return imp,root/'render',root/'output'
    def collect(self,paths):return c.collect(*paths,True)
    def mutate(self,root,key,value):
        p=root/'render/studies/guard-receipt.json';r=json.loads(p.read_text());r[key]=value;p.write_text(json.dumps(r))
    def test_ast(self):ast.parse(Path(c.__file__).read_text())
    def test_exact_output_no_frames(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);self.assertEqual(self.collect(paths),7)
            names={p.relative_to(paths[2]).as_posix() for p in paths[2].rglob('*') if p.is_file()}
            self.assertEqual(names,{'import/'+n for n in c.IMPORT_NAMES}|{'studies/'+n for n in c.RENDER_NAMES}|{'UNACCEPTED_DIAGNOSTICS.json'})
            index=json.loads((paths[2]/'UNACCEPTED_DIAGNOSTICS.json').read_text());self.assertEqual(index['classification'],'UNACCEPTED_DIAGNOSTIC_RENDER_FAILURE');self.assertNotIn('passed',index)
    def test_import_only(self):
        with tempfile.TemporaryDirectory() as temp:self.assertEqual(self.collect(self.fixture(Path(temp),False)),4)
    def test_missing_import_receipt(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);(root/'import/import.json').unlink()
            with self.assertRaises(ValueError):self.collect(paths)
    def test_cleanup_gate(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);self.mutate(root,'cleanup_complete',False)
            with self.assertRaises(ValueError):self.collect(paths)
    def test_each_child_cleanup(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);self.mutate(root,'cleanup',{'xvfb':{'complete':True}})
            with self.assertRaises(ValueError):self.collect(paths)
    def test_readiness_gate(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);self.mutate(root,'startup',{'complete':False,'detected':True,'helpers':[]})
            with self.assertRaises(ValueError):self.collect(paths)
    def test_descendant_gate(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);self.mutate(root,'unexpected_descendants',[{'pid':999}])
            with self.assertRaises(ValueError):self.collect(paths)
    def test_startup_pidfd_lifetimes(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);p=root/'render/studies/guard-receipt.json';guard=json.loads(p.read_text())
            helpers=[];descendants=[]
            for role,pid,ppid in [('dash',124,122),('xkbcomp',125,124)]:
                helpers.append({'role':role,'identity':{'pid':pid,'ppid':ppid,'starttime_ticks':100+pid},'executable_sha256':'b'*64,'exit_confirmed_before_engine':True,'sampled_peak_rss_kib':1,'sampled_peak_hwm_kib':1,'sampled_peak_threads':1})
                descendants.append({'pid':pid,'starttime_ticks':100+pid,'exited':True,'pidfd_closed':True,'status':'exited_after_owned_parent_cleanup'})
                guard['startup']['distribution'][role]={'sha256':'b'*64}
            guard['startup'].update(detected=True,helpers=helpers);guard['observed_descendant_cleanup']=descendants
            p.write_text(json.dumps(guard));self.assertEqual(self.collect(paths),7)
            descendants[0]['pidfd_closed']=False;p.write_text(json.dumps(guard))
            with self.assertRaises(ValueError):c.validate_render(guard,{'godot.log','xvfb.log'})
    def test_missing_owned_log(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);(root/'render/studies/xvfb.log').unlink()
            with self.assertRaises(ValueError):self.collect(paths)
    def test_duplicate_and_nonfinite_json(self):
        for data in (b'{"x":1,"x":2}',b'{"x":NaN}',b'{"x":Infinity}',b'{"x":1e999}'):
            with self.assertRaises(ValueError):c.strict_json(data)
    def test_privacy(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);(root/'render/studies/godot.log').write_text('/home/agent/private')
            with self.assertRaises(ValueError):self.collect(paths)
    def test_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);p=root/'render/studies/godot.log';p.unlink();p.symlink_to(root/'import/import.log')
            with self.assertRaises(ValueError):self.collect(paths)
    def test_unknown_file(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);(root/'render/studies/private.txt').write_text('x')
            with self.assertRaises(ValueError):self.collect(paths)
    def test_oversized_log(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);(root/'render/studies/godot.log').write_bytes(b'x'*(c.MAX_LOG+1))
            with self.assertRaises(ValueError):self.collect(paths)
    def test_failure_context_required(self):
        with tempfile.TemporaryDirectory() as temp:
            paths=self.fixture(Path(temp))
            with self.assertRaises(ValueError):c.collect(*paths,False)
    def test_no_engine_receipt_no_artifact(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            with self.assertRaises(ValueError):c.collect(root/'absent-import',root/'absent-render',root/'out',True)
            self.assertFalse((root/'out').exists())
    def test_import_content_binding(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=self.fixture(root);(root/'import/import.log').write_text('changed')
            with self.assertRaises(ValueError):self.collect(paths)
if __name__=='__main__':unittest.main()
