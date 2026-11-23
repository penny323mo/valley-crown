"""Prove exact pair of untouched 568×320 pixels at the same remembered wall site."""
import hashlib,json,re,struct,sys,zlib
from pathlib import Path
out,pins=map(Path,sys.argv[1:3]);mode=sys.argv[3]
assert mode in ('RENDERED','METADATA_ONLY')
p=json.loads(pins.read_bytes());roles=('baseline','candidate'); reports={}; counts=[]; pngs={}
sha=lambda b:hashlib.sha256(b).hexdigest()
for role in roles:
 b=(out/(role+'.log')).read_text()
 assert not any(re.match(r'^(?:SCRIPT )?ERROR:',line) for line in b.splitlines())
 q=[json.loads(x[len('FAR_OPEN_BUILD '):]) for x in b.splitlines() if x.startswith('FAR_OPEN_BUILD ')]
 assert len(q)==1
 a=reports[role]=q[0];expected=p[role]
 assert a['role']==role and a['engine_hex']==0x040603 and a['size']==[568,320] and a['failed']==0
 assert all(a[k]==expected[k] for k in ('build','game_sha','rules_sha','manifest_sha'))
 assert (a['renderer']=='gl_compatibility' and a['display']!='headless') if mode=='RENDERED' else a['display']=='headless'
 counts.append(len(a['checks']))
 frames=['remembered-site']+(['recon-accepted','ready-to-confirm'] if role=='candidate' else [])
 assert {f.name for f in (out/role).glob('*.png')}==({k+'.png' for k in frames} if mode=='RENDERED' else set())
 pngs[role]={}
 for k in frames:
  v=a['observations'][k]
  if mode=='METADATA_ONLY':
   assert 'png_sha256' not in v;continue
  b=(out/role/(k+'.png')).read_bytes();h=sha(b)
  assert h==v['png_sha256'] and b[:8]==b'\x89PNG\r\n\x1a\n'
  i=8; chunks=[]
  while i<len(b):
   n,tag=struct.unpack_from('>I4s',b,i);raw=b[i+8:i+8+n]; crc,=struct.unpack_from('>I',b,i+8+n)
   assert zlib.crc32(tag+raw)&0xffffffff==crc
   if tag==b'IHDR':assert struct.unpack_from('>II',raw)==(568,320)
   chunks.append(tag);i+=12+n
  assert i==len(b) and chunks[0]==b'IHDR' and chunks.count(b'IHDR')==1 and b'IDAT' in chunks and chunks[-1]==b'IEND'
  pngs[role][k]=h
old,new=[reports[r]['observations'] for r in roles]
a,b=[x['remembered-site'] for x in (old,new)]
s=a['state'];assert s==b['state'] and s['bank']['wood']==30000 and s['pending_player_orders']==0 and s['completed']==2 and s['held'] and s['build_mode']=='wall'
assert len(s['wall_sight'])==4 and all(x['visible']==0 and x['explored']==1 for x in s['wall_sight'])
assert not a['placement_ok'] and not b['placement_ok'] and not a['confirm_enabled'] and not b['confirm_enabled'] and a['ghost_color']==b['ghost_color']=='d97c65'
assert a['recon']=={} and b['recon']=={'text':'前往查看','visible':True,'disabled':False,'rect':[324.,254.,112.,48.]}
assert a['summary']=='不可建造：先派村民探索建築範圍' and b['summary']=='已探索 · 查看不扣資源'
c,e=[new[k] for k in ('recon-accepted','ready-to-confirm')]
for frame in (c,e):
 for field in ('bank','camera','selected','position','held','completed','build_mode'):assert frame['state'][field]==s[field],field
assert c['state']['pending_player_orders']==1 and not c['confirm_enabled'] and c['summary']=='正前往查看 · 未扣資源'
assert c['recon']=={'text':'查看中','visible':True,'disabled':True,'rect':[324.,254.,112.,48.]}
assert e['state']['pending_player_orders']==0 and e['confirm_enabled'] and e['ghost_color']=='92d389' and not e['recon']['visible']
assert all(x['visible']==1 and x['explored']==1 for x in e['state']['wall_sight'])
assert new['far_wall_recon_no_repick_complete']['bank']['wood']==old['far_wall_complete']['bank']['wood']==0
if mode=='RENDERED':
 assert len({v for r in pngs.values() for v in r.values()})==4
print(json.dumps({'status':mode,'checks':counts,'builds':[reports[x]['build'] for x in roles],
 'original_pngs':pngs,'png_count':sum(map(len,pngs.values())),'exact_remembered_pair_state':s,
 'candidate_post_move_sight':e['state']['wall_sight'],'scope':'Ordinary routed native Practice opening, House and Barracks manually paid; real Scout reveal and withdrawal, no synthetic state seeding. Native Godot/Xvfb only, not browser or physical phone.'},ensure_ascii=False,indent=2))
