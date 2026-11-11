import copy,json,tempfile,unittest
from pathlib import Path
import run_faction as a
import validate_faction as v

def report():
 r=dict(schema='vc-faction-publication-v1',build='vc-f3d75a2138cc',passed=True,failed=0,elapsed_ms=100,reference_sha256=v.REFERENCE_SHA,candidate_sha256=v.CANDIDATE_SHA,checks=[dict(name=str(i),passed=True) for i in range(40)],benchmarks=[])
 for name,u,s,n in [('opening',12,24,32),('developed',50,40,64)]:
  r['benchmarks'].append(dict(label=name,units=u,static_records=s,path_points_per_unit=n,warmup_publications=10,measured_publications=360,removed_final_freeze_dictionary_creations_per_publication=1+4*u+s,removed_final_freeze_array_creations_per_publication=5*u,removed_final_freeze_recursive_calls_per_publication=1+(27+n)*u+10*s,actual_allocator_calls=None,allocated_memory_bytes=None,input_serialized_bytes=100,output_serialized_bytes=100,reference_median_batch_usec=200,candidate_median_batch_usec=100,trials=[dict(trial=i,order='reference_first' if i%2==0 else 'candidate_first',reference=dict(publications=30,microseconds=200),candidate=dict(publications=30,microseconds=100)) for i in range(6)]))
 return r
class Tests(unittest.TestCase):
 def test_fixture_positive_is_not_execution(self):self.assertFalse(v.validate(report(),'vc-f3d75a2138cc')['whole_game_or_mobile_speedup_established'])
 def test_bad_reports(self):
  for key,value in [('passed',False),('failed',1),('build','wrong'),('candidate_sha256','bad'),('reference_sha256','bad'),('elapsed_ms',100000),('checks',[]),('benchmarks',[])]:
   with self.subTest(key=key):
    r=report();r[key]=value
    with self.assertRaises(AssertionError):v.validate(r,'vc-f3d75a2138cc')
 def test_bad_component_measurement(self):
  for key,value in [('measured_publications',359),('actual_allocator_calls',1),('allocated_memory_bytes',100),('candidate_median_batch_usec',101),('removed_final_freeze_recursive_calls_per_publication',0),('trials',[])]:
   with self.subTest(key=key):
    r=report();r['benchmarks'][0][key]=value
    with self.assertRaises(AssertionError):v.validate(r,'vc-f3d75a2138cc')
 def test_json_bounds(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'x.json'
   for content in ['{"a":1,"a":2}','{"a":NaN}','{"a":1e999}','x'*(4*1024*1024+1)]:
    p.write_text(content)
    with self.assertRaises((AssertionError,ValueError)):v.read(p)
   q=Path(d)/'link';q.symlink_to(p)
   with self.assertRaises(AssertionError):v.read(q)
 def test_explicit_gate(self):
  lock=dict(faction_reviewed_for_execution=True,faction_supervisor_sha256=a.LOGIC_SHA,faction_harness_sha256=a.HARNESS_SHA,faction_validator_sha256=a.VALIDATOR_SHA)
  a.validate_gate(lock)
  for k in lock:
   x=copy.copy(lock);x[k]=False
   with self.assertRaises(RuntimeError):a.validate_gate(x)
 def test_exact_argv(self):
  args=a.argv(Path('/engine'),Path('/project'),Path('/project/tests/faction_publish_contract.gd'),Path('/out'),'vc-f3d75a2138cc')
  self.assertEqual(args[-3:],['--','/out/faction-publication-report.json','vc-f3d75a2138cc'])
  self.assertEqual(args[args.index('--fixed-fps')+1],'30')
  with self.assertRaises(RuntimeError):a.argv(Path('/e'),Path('/p'),Path('/bad.gd'),Path('/o'),'x')
if __name__=='__main__':unittest.main()
