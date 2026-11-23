from pathlib import Path
import hashlib,json,struct,sys,zlib
out,pins_path=map(Path,sys.argv[1:3]); mode=sys.argv[3] if len(sys.argv)==4 else 'RENDERED'
assert mode in ('RENDERED','METADATA_ONLY')
pins=json.loads(pins_path.read_text())
old,new=(json.loads((out/r/'report.json').read_text()) for r in ('baseline','candidate'))
for role,r in [('baseline',old),('candidate',new)]:
 spec=pins[role]
 assert not r['failed'] and r['build']==spec['build'] and r['size']==[568,320] and r['engine']['hex']==0x040603
 for k in ('game_sha','rules_sha','manifest_sha'):assert r[k]==spec[k], (role,k)
 assert r['display']!='headless' and r['renderer']=='gl_compatibility' if mode=='RENDERED' else r['display']=='headless'
 assert not any('SCRIPT ERROR' in p.read_text() for p in (out/(role+'.log'),))
assert old['build']!=new['build']
frames=[]
expected={'first_storehouse':('(284.0, 160.0)','(-7.0, 0.0, 6.0)',300),'first_tower':('(263.5223, 161.2527)','(-8.0, 0.0, 7.0)',818)}
for name,(sc,plot,tick) in expected.items():
 a,b=(r['evidence'] for r in (old,new))
 red=a[name+'_blocking_real_touch'];green=b[name+'_restored_touch']
 assert red['position']==green['position']==plot and red['screen']==green['screen']==sc and red['t']==tick
 assert red['legal_at_tap'] and red['blocked'] and not red['held_after'] and red['no_orders']
 assert green['matches_exact_prior_direct_tap'] and green['after_held']
 label=name+'-plot-tapped'
 baseline_state,candidate_state=(r[label+'_frame_state'] for r in (a,b))
 assert baseline_state==candidate_state and baseline_state['pending']==0 and baseline_state['tick']==tick and baseline_state['mission_stage']==1
 ap,bp=(r[label+'_frame_presentation'] for r in (a,b))
 assert not ap['held'] and ap['confirm_disabled'] and ap['tutorial_panel']
 assert bp['held'] and bp['placement_ok'] and not bp['confirm_disabled'] and not bp['tutorial_panel'] and bp['inline_status']=='前哨內 · 按確認'
 result=dict(item=name,screen=sc,position=plot,tick=tick,old_held=False,new_held=True,world_before_after_equal=True,camera=baseline_state['camera'])
 if mode=='RENDERED':
  aa,bb=(r[label+'_original_png'] for r in (a,b))
  assert aa['actual_tick']==bb['actual_tick']==tick and aa['camera']==bb['camera']==baseline_state['camera'] and not aa['held'] and bb['held']
  assert aa['sha256']!=bb['sha256']
  for r,frame in [('baseline',aa),('candidate',bb)]:
   assert frame['original_native'] and frame['viewport']=='(568, 320)' and frame['file']==label+'.png'
   p=out/r/frame['file'];data=p.read_bytes(); assert hashlib.sha256(data).hexdigest()==frame['sha256']
   assert data[:8]==b'\x89PNG\r\n\x1a\n'
   off=8;types=[]
   while off<len(data):
    n,t=struct.unpack_from('>I4s',data,off);payload=data[off+8:off+8+n];stored=struct.unpack_from('>I',data,off+8+n)[0]
    assert zlib.crc32(t+payload)&0xffffffff==stored;types.append(t);off+=n+12
    if t==b'IHDR':assert struct.unpack_from('>II',payload)==(568,320)
   assert off==len(data) and types[0]==b'IHDR' and types.count(b'IHDR')==1 and b'IDAT' in types and types[-1]==b'IEND'
  result.update(sha256=[aa['sha256'],bb['sha256']])
 else:
  assert all(label+'_original_png' not in r for r in (a,b))
 frames.append(result)
files={p.name for p in (out/'baseline').glob('*.png')}
assert files=={p.name for p in (out/'candidate').glob('*.png')}==({n+'-plot-tapped.png' for n in expected} if mode=='RENDERED' else set())
for key in ('tick','stage','stage_ticks','alive','built','bank','audit','strategic_orders'):
 assert old[key]==new[key],key
assert old['stage']==new['stage']==2 and old['bank']['wood']==new['bank']['wood']==40000 and old['tick']==new['tick']==1718
print(json.dumps({'result':mode,'scope':'Exact stamped Chapter 3 ordinary routed placement; synthetic native touch harness, not physical iPhone. No pixel claim in metadata-only mode.', 'builds':[old['build'],new['build']],'checks':[len(old['checks']),len(new['checks'])],'png_count':len(files)*2,'frames':frames},ensure_ascii=False,indent=2))
