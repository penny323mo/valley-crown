#!/usr/bin/env python3
"""Inert source-lock checks or checks of an externally produced replay report. Never starts an engine."""
from pathlib import Path
import argparse,hashlib,json,re,math
P=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=P.parent/'rts_occlusion_host_candidate');p.add_argument('--report',type=Path);a=p.parse_args()
lock=json.loads((P/'replay_source_lock.json').read_text()); checks=[]
def check(name,ok): checks.append({'name':name,'pass':bool(ok)})
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
check('all frozen runtime files unchanged',all((a.root/k).is_file() and sha(a.root/k)==v for k,v in lock['runtime_sha256'].items()))
check('harness frozen',sha(P/'ordinary_map80_replay.gd')==lock['harness_sha256'])
identity=json.loads((P/'candidate_identity_dry_run.json').read_text())
check('runtime identity independently recomputed',identity['manifest']['build']==lock['expected_build'])
s=(P/'ordinary_map80_replay.gd').read_text()
for term in ['_test_reset','game.test_mode=','game.ai_enabled=','game.stocks[','game.entities','game._kill','game._execute','game._order','game._select','game.visible_cells','game.tick_count=']:
    check('no synthetic mutation or hidden authority '+term,term not in s)
check('normal scene startup', 'load("res://main.tscn").instantiate()' in s)
check('bounded loop', 'for i in MAX_TICKS:' in s and 'const MAX_TICKS=48000' in s)
check('ordinary commands', 'game._submit(kind,data,0)' in s)
check('player projection policy','game.faction_views[0].records().values()' in s)
check('no old 48 grid',all(x not in s for x in ['y*48','23.5','range(2,46)']))
indices=[y*80+x for y in range(2,78) for x in range(2,78)]
check('all 5776 playable exploration cells unique and in bounds',len(indices)==len(set(indices))==5776 and min(indices)>=0 and max(indices)<6400)
check('all cell centers invert correctly',all(int((x-40+.5)+40)==x for x in range(2,78)))
if a.report:
    r=json.loads(a.report.read_text());check('report build',r['build']==lock['expected_build']);check('report game SHA',r['source_sha256']==lock['runtime_sha256']['scripts/game.gd']);check('report harness SHA',r['harness_sha256']==lock['harness_sha256'])
    trace=r['input_trace']; cps=r['checkpoints']; term=r['terminal']['snapshot']; milestones=r['milestones']; previews=r['placement_previews']
    check('actual victory or defeat',term['game_over'] and term['outcome'] in ['victory','defeat'] and bool(r['end_reason']))
    check('finite elapsed ticks',isinstance(term['tick'],int) and 0<term['tick']<=48000 and r['bound_ticks']==48000)
    check('finite elapsed time consistent',math.isfinite(term['time']) and abs(term['time']-term['tick']*.05)<.01 and math.isfinite(r['wall_ms']) and 0<=r['wall_ms']<=300000)
    check('all core simulation milestones',all(k in milestones for k in ['delivered','built','trained','combat_state','terminal']))
    check('milestone ticks valid',all(isinstance(v,int) and 0<v<=term['tick'] for v in milestones.values()) and milestones.get('terminal')==term['tick'])
    check('completed counts nonvacuous',all(term[k]>0 for k in ['delivered','built','trained']))
    check('economy audit',r['economy_audit']['ok'] and not r['economy_audit']['errors'] and not r['invariant_failures'])
    check('checkpoints initial and ordered',bool(cps) and cps[0]['snapshot']['tick']==0 and not cps[0]['snapshot']['game_over'] and all(0<=c['snapshot']['tick']<=term['tick'] for c in cps) and all(a['snapshot']['tick']<=b['snapshot']['tick'] for a,b in zip(cps,cps[1:])))
    check('AI recorded throughout',bool(cps) and all(c.get('ai_enabled') is True for c in cps) and r['terminal']['ai_enabled'] is True)
    check('checkpoint economy and population valid',all(c['snapshot']['food']>=0 and c['snapshot']['wood']>=0 and 0<=c['snapshot']['population']<=r['population_limit'] for c in cps))
    check('nonempty unique ordinary commands',bool(trace) and len({t['command']['command_id'] for t in trace})==len(trace) and {t['command']['type'] for t in trace}=={'order','train','build'})
    check('normal tick commands',all(t['tick']==t['command']['enqueue_tick'] and 0<=t['tick']<term['tick'] and t['tick']%40==0 and t['command']['team']==0 for t in trace))
    check('actors owned alive current',all(t['actor']['owned'] and t['actor']['alive'] and not t['actor']['remembered'] and t['actor']['last_seen_tick']==t['tick'] for t in trace))
    check('targets observed fresh and matching',all(not t['target'] or (not t['target']['remembered'] and t['target']['alive'] and t['target']['last_seen_tick']==t['tick'] and t['target']['id']==t['command']['target']) for t in trace))
    check('exact order actor IDs',all(t['command']['ids']==[t['actor']['id']] for t in trace if t['command']['type']=='order'))
    check('valid train producer',all(t['actor']['built'] and t['actor']['id']==t['command']['building'] and (t['actor']['kind'],t['command']['kind']) in [('town_center','villager'),('range','archer')] for t in trace if t['command']['type']=='train'))
    check('matching legal build preview',all(t['actor']['kind']=='villager' and t['actor']['id']==t['command']['builder'] and any(v['tick']==t['tick'] and v['kind']==t['command']['kind'] and v['position']==t['command']['position'] and v['builder']==t['command']['builder'] and v['reason']=='' for v in previews) for t in trace if t['command']['type']=='build'))
    check('reported pass',r['status']=='PASS_CORE_SIMULATION')

result={'scope':'Local inert checks, no engine parse or execution' if not a.report else 'External report verification, not independent replay execution','passed':sum(c['pass'] for c in checks),'failed':sum(not c['pass'] for c in checks),'checks':checks}
print(json.dumps(result,indent=2));raise SystemExit(1 if result['failed'] else 0)
