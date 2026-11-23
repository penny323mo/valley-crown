"""Verify original PNG structure and exact same-state 480×270 native pair."""
import hashlib,json,struct,sys,zlib
from pathlib import Path
path,pins=map(Path,sys.argv[1:3]); mode=sys.argv[3]
assert mode in ('RENDERED','METADATA_ONLY')
p=json.loads(pins.read_text())
roles=('baseline','candidate'); frames=['opening','menu-open','worker-focused','paused']
builds=[]; counts=[]; digests={}
rr={}
for role in roles:
 v=rr[role]=json.loads((path/role/'report.json').read_bytes()); s=p[role]
 assert v['role']==role and v['build']==s['build'] and v['viewport']==[480,270] and v['engine']['hex']==0x040603
 assert all(v[h]==s[h] for h in ('game_sha','rules_sha','manifest_sha'))
 assert v['renderer']=='gl_compatibility' if mode=='RENDERED' else v['display']=='headless'
 assert v['checks'] and all(x['pass'] for x in v['checks'])
 counts.append(len(v['checks']));builds.append(v['build'])
 assert set(v['reports'])==set(frames)
 assert {n.name for n in (path/role).glob('*.png')}==({x+'.png' for x in frames} if mode=='RENDERED' else set())
 logs=path/(role+'.log')
 if logs.is_file():assert 'SCRIPT ERROR' not in logs.read_text()
for label in frames:
 a,b=[rr[role]['reports'][label] for role in roles]
 state=a['state']
 assert state==b['state'] and state['tick']==0 and state['bank']==rr['baseline']['reports']['opening']['state']['bank'] and state['sequence']==0 and state['queue']==[]
 if label=='opening':
  assert a['geometry']['menu_label']=='閒置' and a['geometry']['menu_visible']==[465,10,15,46] and a['geometry']['idle']==[]
  assert b['geometry']['menu_label']=='選單' and b['geometry']['menu_visible']==[404,10,60,46] and b['geometry']['idle']==[286,10,46,46]
  assert not state['menu'] and state['selected']==[0] and not state['paused']
 if label=='menu-open':
  assert state['menu'] and state['selected']==[0] and not state['paused']
 if label in ('worker-focused','paused'):
  assert not state['menu'] and len(state['selected'])==1 and state['paused']==(label=='paused')
  assert any(k[0]==state['selected'][0] and k[1]=='villager' and k[2]==state['focus'] for k in state['owned'])
 if mode=='RENDERED':
  digests[label]=[]
  for role,v in zip(roles,(a,b)):
   png=(path/role/(label+'.png')).read_bytes()
   digest=hashlib.sha256(png).hexdigest()
   assert digest==v['png_sha256'] and png[:8]==b'\x89PNG\r\n\x1a\n'
   off=8; chunks=[]
   while off<len(png):
    n,typ=struct.unpack_from('>I4s',png,off)
    data=png[off+8:off+8+n];crc,=struct.unpack_from('>I',png,off+8+n)
    assert crc==zlib.crc32(typ+data)&0xffffffff
    if typ==b'IHDR':assert struct.unpack_from('>II',data)==(480,270)
    chunks.append(typ);off+=12+n
   assert off==len(png) and chunks[0]==b'IHDR' and chunks.count(b'IHDR')==1 and b'IDAT' in chunks and chunks[-1]==b'IEND'
   digests[label].append(digest)
  assert digests[label][0]!=digests[label][1]
ordinary=['StartMatchButton','BattleGroup0','ChooseBattle_standard','LaunchMatchButton']
assert [x['name'] for x in rr['baseline']['actions']]==ordinary+['Menu','drawer Idle','Pause']
assert [x['name'] for x in rr['candidate']['actions']]==ordinary+['Menu']+ordinary+['top-row Idle','Pause']
assert rr['baseline']['actions'][4]['point']==[472.5,33] and rr['candidate']['actions'][4]['point']==[434,33]
print(json.dumps({'status':mode,'builds':builds,'checks':counts,'png_count':sum(map(len,digests.values())),
 'original_sha256':digests,'frames':frames,'menu_visible_px':[15,60],'frame_state_matches':True,
 'scope':'Both Standard openings are real game states, frozen after ordinary native routed menu at natural tick 0; native synthetic tap and original Linux llvmpipe PNGs, not Web or physical device.'},ensure_ascii=False,indent=2))
