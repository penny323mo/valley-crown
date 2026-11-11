#!/usr/bin/env python3
"""Pure JSON validation only. A successful report still needs bound guard receipt."""
import json,sys
from pathlib import Path
REQUIRED={'menu_started','cargo_collected','cargo_deposited','house_complete','barracks_complete','range_complete','spearman_produced','archer_produced','enemy_attack_observed','own_health_loss','enemy_health_loss','enemy_keep_damaged','normal_victory'}
def validate(r):
 assert r['schema']=='vc-normal-full-match-v1'
 assert r['policy_version']=='ordinary-policy-v2'
 assert len(r['commands'])<=2048
 assert isinstance(r['final_public_records'],list) and r['final_public_records']
 samples=r['public_samples']; assert isinstance(samples,list) and 0<len(samples)<=64
 assert all(a['tick']<b['tick'] for a,b in zip(samples,samples[1:]))
 assert samples[-1]['tick']<=r['final']['tick']
 assert all(x['owned'] or (x['team']==1 and not x['remembered']) for sample in samples for x in sample['public_records'])
 assert r['engine_time_scale']==1
 assert r['wall_seconds']<=105
 assert r['passed'] is True
 assert REQUIRED<=r['phases'].keys(), 'Missing normal-match phases'
 events={e['label']:e for e in r['events']}
 assert REQUIRED<=events.keys()
 assert r['final']['game_over'] is True and r['final']['outcome']=='victory'
 assert events['normal_victory']['detail']['reason']=='keep_destroyed'
 assert events['cargo_collected']['detail']['cargo_milli']>0
 assert events['cargo_deposited']['snapshot']['delivered']>0
 for kind in ('house','barracks','range'):
  d=events[kind+'_complete']['detail']; assert d['kind']==kind and d['owned'] and d['built']
 for kind in ('spearman','archer'):
  d=events[kind+'_produced']['detail']; assert d['kind']==kind and d['owned']
  assert any(c['type']=='train' and c['payload']['kind']==kind for c in r['commands'])
 for side in ('own','enemy'):
  d=events[side+'_health_loss']['detail']; assert d['before']['id']==d['after']['id'] and d['before']['hp']>d['after']['hp']
  assert not d['after']['remembered'] and d['after']['owned']==(side=='own')
 d=events['enemy_attack_observed']['detail']; assert d['team']==1 and not d['remembered'] and d['visual_attack_tick']>=0
 d=events['enemy_keep_damaged']['detail']; assert d['team']==1 and d['kind']=='town_center' and d['hp']<d['max_hp'] and not d['remembered']
 assert all(c['type'] in ('order','build','train') for c in r['commands'])
 for c in r['commands']:
  if c['type']=='order' and c['payload']['target']>=0:
   target=c['public_target_at_submit']; assert target['id']==c['payload']['target'] and not target['remembered']
 assert all(c['payload'].get('team',0)==0 for c in r['commands'])
 assert all(c['type']!='build' or c['payload']['kind'] in ('house','barracks','range') for c in r['commands'])
 return {'passed':True,'scope':r['scope'],'required_phases':len(REQUIRED),'not_verified':r['not_verified']}
if __name__=='__main__':
 print(json.dumps(validate(json.loads(Path(sys.argv[1]).read_text())),indent=2))
