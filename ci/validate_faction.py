"""Strict component report validation, not evidence that the benchmark was run."""
import json,math,statistics
from pathlib import Path
REFERENCE_SHA='5862071a65d1d3a0bf513c8ff48258664013a84ef19f63936c2a891e576a5ab5'
CANDIDATE_SHA='cf2f462e2d20b91a699775d5b290c8ccf3d604fe7a07a8165c4e215add836931'
def pairs(rows):
 d={}
 for k,v in rows:
  if k in d: raise ValueError('Duplicate JSON key')
  d[k]=v
 return d
def finite(value):
 if isinstance(value,float): assert math.isfinite(value)
 elif isinstance(value,dict):
  for x in value.values():finite(x)
 elif isinstance(value,list):
  for x in value:finite(x)
def read(path):
 p=Path(path);assert not p.is_symlink() and p.is_file() and 0<p.stat().st_size<=4*1024*1024
 r=json.loads(p.read_text(),object_pairs_hook=pairs,parse_constant=lambda x:(_ for _ in ()).throw(ValueError('Nonfinite JSON')));finite(r);return r
def validate(r,build):
 assert r['schema']=='vc-faction-publication-v1' and r['build']==build
 assert r['passed'] is True and r['failed']==0 and 0<=r['elapsed_ms']<100000
 assert r['reference_sha256']==REFERENCE_SHA and r['candidate_sha256']==CANDIDATE_SHA
 checks=r['checks'];assert len(checks)==40 and len({x['name'] for x in checks})==40 and all(x['passed'] is True for x in checks)
 assert len(r['benchmarks'])==2
 results=[]
 for b,(name,u,s,n) in zip(r['benchmarks'],[('opening',12,24,32),('developed',50,40,64)]):
  assert (b['label'],b['units'],b['static_records'],b['path_points_per_unit'])==(name,u,s,n)
  assert b['warmup_publications']==10 and b['measured_publications']==360 and len(b['trials'])==6
  assert b['removed_final_freeze_dictionary_creations_per_publication']==1+4*u+s
  assert b['removed_final_freeze_array_creations_per_publication']==5*u
  assert b['removed_final_freeze_recursive_calls_per_publication']==1+(27+n)*u+10*s
  assert b['actual_allocator_calls'] is None and b['allocated_memory_bytes'] is None
  assert type(b['input_serialized_bytes']) is int and b['input_serialized_bytes']>0
  assert type(b['output_serialized_bytes']) is int and b['output_serialized_bytes']>0
  old=[];new=[]
  for index,t in enumerate(b['trials']):
   assert t['trial']==index and t['order']==('reference_first' if index%2==0 else 'candidate_first')
   for key,values in [('reference',old),('candidate',new)]:
    assert t[key]['publications']==30 and type(t[key]['microseconds']) is int and t[key]['microseconds']>0;values.append(t[key]['microseconds'])
  assert b['reference_median_batch_usec']==statistics.median(old) and b['candidate_median_batch_usec']==statistics.median(new)
  results.append({'case':name,'component_median_ratio_reference_over_candidate':statistics.median(old)/statistics.median(new),'candidate_faster_trials':sum(a>b for a,b in zip(old,new)),'trials':6})
 return {'semantics_passed':True,'component_measurements':results,'whole_game_or_mobile_speedup_established':False}
