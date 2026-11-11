#!/usr/bin/env python3
"""Pure JSON validation only. A successful report still needs bound guard receipt."""
import json,sys
from pathlib import Path
REQUIRED={'menu_started','cargo_collected','cargo_deposited','house_complete','barracks_complete','range_complete','spearman_produced','archer_produced','enemy_attack_observed','own_health_loss','enemy_health_loss','enemy_keep_damaged','normal_victory'}
def validate_recoveries(r):
 events=r.get('recovery_events'); assert type(events) is list and len(events)<=64
 seen=set();counts={};last={};cargo_counts={}
 for event in events:
  assert type(event) is dict and set(event)=={'kind','tick','detail'}
  assert type(event['tick']) is int and event['tick']>=0
  d=event['detail']; assert type(d) is dict
  actor=d['actor']; assert actor['owned'] is True and actor['team']==0 and actor['alive'] is True and actor['remembered'] is False and actor['kind']=='villager'
  if event['kind']=='construction_takeover':
   assert set(d)=={'actor','site','terminal_builder','reason','terminal_signature'}
   site=d['site'];stopped=d['terminal_builder']
   assert site['owned'] is True and site['alive'] is True and site['remembered'] is False and site['built'] is False
   assert stopped['owned'] is True and stopped['alive'] is True and stopped['remembered'] is False and stopped['state']=='idle'
   assert stopped['path_status'] in ('NO_PATH','LIMIT_REACHED') and d['reason']==stopped['path_reason']
   assert actor['id']!=stopped['id'] and actor['state'] in ('idle','gather')
   assert type(d['terminal_signature']) is str and d['terminal_signature'] not in seen;seen.add(d['terminal_signature'])
   sid=site['id'];counts[sid]=counts.get(sid,0)+1;assert counts[sid]<=3
   assert event['tick']-last.get(sid,-100)>=100;last[sid]=event['tick']
   target=site['id']
  else:
   assert event['kind']=='return_idle_cargo' and set(d)=={'actor','dropoff','reason','cargo_milli_before'}
   assert actor['state']=='idle' and type(d['cargo_milli_before']) is int and d['cargo_milli_before']>0 and d['cargo_milli_before']==actor['cargo_milli']
   drop=d['dropoff'];assert drop['owned'] is True and drop['alive'] is True and drop['remembered'] is False and drop['built'] is True and drop['kind'] in ('town_center','storehouse')
   assert d['reason']=='idle_with_earned_cargo';target=drop['id']
   aid=actor['id'];cargo_counts[aid]=cargo_counts.get(aid,0)+1;assert cargo_counts[aid]<=3
   assert event['tick']-last.get(('cargo',aid),-100)>=100;last[('cargo',aid)]=event['tick']
  assert any(c['type']=='order' and c['tick']==event['tick'] and c['payload']['ids']==[actor['id']] and c['payload']['target']==target for c in r['commands'])
 return True

def validate_throughput(r):
 t=r['throughput'];assert type(t) is dict
 for key in ('process_frames_observed','simulation_ticks','observation_calls','observation_usec','decision_calls','decision_usec'):
  assert type(t[key]) is int and t[key]>=0
 assert t['simulation_ticks']==r['final']['tick']
 assert abs(t['game_seconds']-t['simulation_ticks']*.05)<1e-6
 assert t['observation_calls']<=t['process_frames_observed'] and t['decision_calls']<=t['observation_calls']
 assert t['observation_usec']+t['decision_usec']<=r['wall_seconds']*1000000+10000
 samples=t['samples'];assert type(samples) is list and len(samples)<=10
 assert all(a['wall_ms']<b['wall_ms'] and a['tick']<=b['tick'] for a,b in zip(samples,samples[1:]))
 assert type(r['additional_coverage']) is dict
 for event in r['additional_coverage'].values():
  assert 0<=event['tick']<=r['final']['tick'] and event['actor']['owned'] and not event['actor']['remembered']
 return True

def validate(r):
 validate_recoveries(r)
 validate_throughput(r)
 assert r['schema']=='vc-normal-full-match-v1'
 assert r['policy_version']=='ordinary-rendered-440-ack-v2'
 assert len(r['commands'])<=2048
 assert isinstance(r['final_public_records'],list) and r['final_public_records']
 samples=r['public_samples']; assert isinstance(samples,list) and 0<len(samples)<=64
 assert all(a['tick']<b['tick'] for a,b in zip(samples,samples[1:]))
 assert samples[-1]['tick']<=r['final']['tick']
 assert all(x['owned'] or (x['team']==1 and not x['remembered']) for sample in samples for x in sample['public_records'])
 assert r['engine_time_scale']==1
 assert r['wall_seconds']<=445
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
