#!/usr/bin/env python3
"""File-only acceptance checker; never launches the engine."""
from pathlib import Path
import argparse,hashlib,json,math
P=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=P.parent/'rts_occlusion_local_demo_integration/candidate');p.add_argument('--report',type=Path);a=p.parse_args()
lock=json.loads((P/'replay_source_lock.json').read_text());checks=[]
def check(name,ok):checks.append({'name':name,'pass':bool(ok)})
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
check('frozen runtime unchanged',all((a.root/k).is_file() and sha(a.root/k)==v for k,v in lock['runtime_sha256'].items()))
check('frozen harness',sha(P/'ordinary_map80_replay.gd')==lock['harness_sha256'])
s=(P/'ordinary_map80_replay.gd').read_text()
for forbidden in ['_test_reset','_kill(','game.entities','game.visible_cells','game.ai_enabled=','game.stocks[','"surrender"','emit_signal','reload_current_scene(']:
 check('no forced authority '+forbidden,forbidden not in s)
check('legitimate current scene host','current_scene=game' in s)
check('bounded native keyboard route','root.push_input(press,true)' in s and 'root.push_input(release,true)' in s and 'button.grab_focus()' in s and 'for i in 10:' in s)
check('finite ordinary ticks','const MAX_TICKS=48000' in s and 'for i in MAX_TICKS:' in s and 'for i in 40:' in s)
if a.report:
 r=json.loads(a.report.read_text());term=r['terminal']['snapshot'];initial=r['initial'];fresh=r['restarted'];post=r['post_restart'];trace=r['input_trace'];ui=r['ui_restart']
 check('exact report binding',r['build']==lock['expected_build'] and r['source_sha256']==lock['runtime_sha256']['scripts/game.gd'] and r['harness_sha256']==lock['harness_sha256'])
 check('natural defeat not surrender',term['game_over'] and term['outcome']=='defeat' and r['end_reason'] in ['keep_destroyed','irrecoverable'])
 check('finite terminal and wall bounds',r['bound_ticks']==48000 and 0<term['tick']<=48000 and math.isfinite(term['time']) and abs(term['time']-term['tick']*.05)<.01 and math.isfinite(r['wall_ms']) and 0<=r['wall_ms']<=300000)
 check('ordinary opening nonvacuous',term['delivered']>0 and term['trained']>0 and bool(trace))
 check('terminal economy',r['economy_audit']['ok'] and not r['economy_audit']['errors'] and not r['invariant_failures'])
 check('normal initial tick',initial['snapshot']['tick']==0 and not initial['snapshot']['game_over'] and initial['ai_enabled'])
 check('AI never suppressed',all(c['ai_enabled'] for c in r['checkpoints']) and r['terminal']['ai_enabled'])
 check('ordinary command kinds',{t['command']['type'] for t in trace}=={'order','train'})
 check('unique commands per scene',len({(t['phase'],t['command']['command_id']) for t in trace})==len(trace))
 check('phases nonvacuous', {t['phase'] for t in trace}=={'opening','restarted'})
 check('normal enqueue and actor observation',all(t['tick']==t['command']['enqueue_tick'] and t['tick']%20==0 and t['command']['team']==0 and t['actor']['owned'] and t['actor']['alive'] and not t['actor']['remembered'] and t['actor']['last_seen_tick']==t['tick'] for t in trace))
 check('targets fresh matching berries',all(not t['target'] or (t['target']['kind']=='berry' and t['target']['alive'] and not t['target']['remembered'] and t['target']['last_seen_tick']==t['tick'] and t['target']['id']==t['command']['target']) for t in trace))
 check('one paid villager request per scene',all(sum(t['command']['type']=='train' and t['phase']==phase for t in trace)==1 for phase in ['opening','restarted']) and all(t['tick']==0 and t['actor']['built'] and t['actor']['kind']=='town_center' and t['command']['kind']=='villager' and t['command']['building']==t['actor']['id'] for t in trace if t['command']['type']=='train'))
 check('gather orders real own villagers',all(t['actor']['kind']=='villager' and t['command']['ids']==[t['actor']['id']] and bool(t['target']) for t in trace if t['command']['type']=='order'))
 check('actual native restart activation',all(ui.get(k) is True for k in ['attempted','button_found','terminal_panel_visible','focus_owned','button_enabled','old_instance_released','new_instance']) and ui['button_text']=='再開一局' and ui['reload_events']==1)
 check('fresh scene exact initial state',bool(fresh) and fresh['snapshot']==initial['snapshot'] and fresh['records']==initial['records'] and fresh['ai_enabled'] and fresh['scene_file_path']=='res://main.tscn')
 check('no stale terminal or presentation',bool(fresh) and fresh['commands_empty'] and fresh['action_history_empty'] and fresh['corpses_empty'] and not fresh['end_panel_visible'])
 check('restarted match advances ordinary command',bool(post) and post['snapshot']['tick']==40 and abs(post['snapshot']['time']-2)<.01 and not post['snapshot']['game_over'] and not post['snapshot']['paused'] and post['ai_enabled'] and post['command_count']>0 and post['economy_audit']['ok'])
 check('phase tick bounds',all((t['phase']=='opening' and 0<=t['tick']<term['tick']) or (t['phase']=='restarted' and t['tick']==0) for t in trace))
 post_records=post.get('records',{}).values()
 check('paid restart villager debit',bool(post) and post['snapshot']['food']==fresh['snapshot']['food']-50 and post['snapshot']['wood']==fresh['snapshot']['wood'])
 check('restart queue executed forty ticks',any(e['owned'] and e['kind']=='town_center' and len(e.get('queue',[]))==1 and e['queue'][0]['kind']=='villager' and e['queue'][0]['started'] and e['queue'][0]['remaining_ticks']==260 for e in post_records))
 check('issued restart gather target active',any(e['owned'] and e['alive'] and e['kind']=='villager' and e['state']=='gather' and e['last_seen_tick']==40 and any(t['phase']=='restarted' and t['command']['type']=='order' and t['actor']['id']==e['id'] and t['target']['id']==e['target'] for t in trace) for e in post_records))
 check('execution assertions present',all(r.get('restart_execution',{}).get(k) is True for k in ['paid_villager','training_advanced','gather_target_active']))
 check('reported pass',r['status']=='PASS_DEFEAT_RESTART')
result={'scope':'Inert source checks' if not a.report else 'Defeat and native keyboard restart evidence checks; not phone/render acceptance','passed':sum(c['pass'] for c in checks),'failed':sum(not c['pass'] for c in checks),'checks':checks}
print(json.dumps(result,indent=2));raise SystemExit(1 if result['failed'] else 0)
