#!/usr/bin/env python3
"""Two independently restarted normal touch flows, not one combined playthrough."""
from pathlib import Path
import argparse, math, json, re
import scan_evidence as base
SCENARIO='native_routed_touch_independent_v2'
LABELS={
 'touch-gather':['opening','worker-selected','target-guidance','command-mode','gather-order-accepted','woodcutting','wood-cargo','cargo-return','deposit-complete','gather-resumed'],
 'touch-build':['opening','worker-selected','build-action-preview','build-preview','build-confirmed','construction-active','construction-quarter','construction-half','house-complete','house-complete-settled']}
ROLES={'touch-gather':['select-worker','target-guidance','command-button','order-wood'],
       'touch-build':['select-worker','house-button','hold-building-plot','confirm-build']}
def contract(flow):return {'scenario':SCENARIO,'flow':flow,'viewport':[390,844],'frames':LABELS[flow],
    'input':'viewport.push_input(InputEventScreenTouch,false)','simulation':'independent_normal_seeded_fixed20',
    'fixed_fps':20,'observed_process_delta_seconds':.05,'restart':False,'single_uninterrupted_combined_chain':False,**({'hud_settle_minimum_normal_frames':4} if flow=='touch-build' else {})}
ERRORS={'Touch contract differs','Touch ordinary runtime differs','Touch action order differs','Touch event schema differs',
        'Touch event coordinates differ','Touch stream ownership differs','Touch UI button differs','Touch intent transition differs',
        'Touch frame chronology differs','Touch public worker differs','Touch deposit provenance differs','Touch construction provenance differs',
        'Touch public pose differs','Touch geometry or capture sequence differs','Touch fixed pacing differs','Touch fresh source start differs','Touch HUD evidence malformed','Touch HUD refresh interval incomplete','Touch HUD snapshot differs'}
def need(ok,reason):base.require(ok,reason)
def number(x):return type(x) in (int,float) and math.isfinite(x)
def integer(x):return type(x) is int and x>=0
def pair(value):return type(value) is list and len(value)==2 and all(number(x) for x in value)
def within(point,rect):return rect[0]<=point[0]<rect[0]+rect[2] and rect[1]<=point[1]<rect[1]+rect[3]
def snapshot(s):
    need(type(s) is dict and s.get('build')=='vc-c7211e1083c8' and integer(s.get('tick')) and number(s.get('delivered')) and s['delivered']>=0 and integer(s.get('built')) and
         s.get('paused') is False and s.get('game_over') is False and s.get('economy_scale')==1000 and
         type(s.get('bank_milli')) is dict and all(integer(s['bank_milli'].get(k)) for k in ('food','wood')) and
         type(s.get('selected')) is list and all(integer(x) for x in s['selected']) and integer(s.get('own_pending_commands')),
         'Touch ordinary runtime differs')
def own(frame,worker):
    rows=[r for r in frame['own_units'] if r.get('id')==worker]
    need(len(rows)==1 and rows[0].get('kind')=='villager','Touch public worker differs')
    return rows[0]
def pose(frame,worker,clip,lock):
    roots=frame.get('animation_poses')
    need(type(roots) is list and len(roots)==1 and roots[0].get('node')=='.','Touch public pose differs')
    p=roots[0]['snapshot']['live'].get(str(worker))
    need(type(p) is dict and p.get('kind')=='villager' and p.get('clip')==clip and p.get('dead_visual_only') is False,'Touch public pose differs')
    return base.pose_identity(p,lock)

def validate_pacing(guard,lock):
    need(guard.get('fixed_fps')==lock.get('fixed_fps')==20 and type(guard['fixed_fps']) is int and type(lock['fixed_fps']) is int,'Touch fixed pacing differs')

def validate_touch(report,lock):
    flow=report.get('flow');need(flow in LABELS,'Touch contract differs')
    need(lock.get('touch_contract')==contract(flow) and type(lock.get('fixed_fps')) is int and lock['fixed_fps']==20 and
         lock['capture_contract']=={'mode':'gameplay','kind':'genuine_native_game_viewport','frame_count':10} and
         report.get('scenario')==SCENARIO and type(report.get('fixed_fps')) is int and report['fixed_fps']==20,'Touch contract differs')
    need(number(report.get('observed_process_delta_seconds')) and math.isclose(report['observed_process_delta_seconds'],.05,rel_tol=0,abs_tol=1e-8),'Touch fixed pacing differs')
    frames=report['frames'];events=report.get('events');actions=report.get('actions');worker=report.get('worker_id')
    need([f.get('label') for f in frames]==LABELS[flow] and len({f['image_sha256'] for f in frames})==10,'Touch geometry or capture sequence differs')
    need(integer(worker),'Touch public worker differs')
    for i,f in enumerate(frames):
        snapshot(f['snapshot'])
        need(number(f.get('observed_process_delta_seconds')) and math.isclose(f['observed_process_delta_seconds'],.05,rel_tol=0,abs_tol=1e-8),'Touch fixed pacing differs')
        need(f.get('scenario')==SCENARIO and f.get('flow')==flow and type(f.get('fixed_fps')) is int and f['fixed_fps']==20 and
             f.get('framebuffer')==f.get('logical_viewport')==[390,844] and f.get('content_scale_factor')==1 and
             f.get('camera_focus')==[-25,0,24] and f.get('camera_zoom')==30 and f.get('test_mode') is False and f.get('ai_enabled') is True and
             f.get('economy_audit_ok') is True,'Touch ordinary runtime differs')
        need(integer(f.get('game_tick')) and number(f.get('game_seconds')) and f['snapshot']['tick']==f['game_tick'] and
             math.isclose(f['game_seconds'],f['game_tick']*.05,abs_tol=1e-6) and (i==0 or f['game_tick']>=frames[i-1]['game_tick']),
             'Touch frame chronology differs')
        need(integer(f.get('input_event_count')) and (i==0 or f['input_event_count']>=frames[i-1]['input_event_count']),'Touch frame chronology differs')
        if i:need(worker in f['selected'] and worker in f['snapshot']['selected'],'Touch public worker differs')
    initial=frames[0]['snapshot']
    centers=[b for b in frames[0]['own_buildings'] if b.get('kind')=='town_center' and b.get('built') is True]
    need(len(centers)==1 and integer(centers[0].get('id')) and centers[0]['id']!=worker and initial['selected']==[centers[0]['id']] and frames[0]['selected']==initial['selected'],
         'Touch fresh source start differs')
    need(initial['bank_milli']=={'food':150000,'wood':200000} and initial['delivered']==report.get('initial_delivered')==0 and initial['built']==0 and
         report.get('initial_house_ids')==[] and initial['own_pending_commands']==0, 'Touch fresh source start differs')
    need(type(actions) is list and [a.get('role') for a in actions]==ROLES[flow] and all(a.get('kind')=='tap' for a in actions),'Touch action order differs')
    need(type(events) is list and 8<=len(events)<=23 and frames[0]['input_event_count']==0 and frames[-1]['input_event_count']==len(events),'Touch event schema differs')
    for i,event in enumerate(events):
        need(event.get('sequence')==i and event.get('type') in ('InputEventScreenTouch','InputEventScreenDrag') and event.get('index')==0 and
             event.get('role') in ROLES[flow]+['reveal-house'] and integer(event.get('tick')) and integer(event.get('process_frame')),'Touch event schema differs')
        need(pair(event.get('position')) and within(event['position'],[0,0,390,844]),'Touch event coordinates differ')
        need(i==0 or (event['tick']>=events[i-1]['tick'] and event['process_frame']>=events[i-1]['process_frame']),'Touch frame chronology differs')
        if event['type']=='InputEventScreenTouch':need(type(event.get('pressed')) is bool and event.get('canceled') is False,'Touch event schema differs')
    claimed=set()
    for index,action in enumerate(actions):
        ids=action.get('events');need(type(ids) is list and len(ids)==2 and all(integer(x) for x in ids) and ids[1]==ids[0]+1 and ids[1]<len(events),'Touch stream ownership differs')
        first,last=(events[x] for x in ids)
        need(not claimed.intersection(ids) and first['type']==last['type']=='InputEventScreenTouch' and first['pressed'] is True and last['pressed'] is False and
             first['role']==last['role']==action['role'] and first['position']==last['position'],'Touch stream ownership differs')
        claimed.update(ids);snapshot(action['before']);snapshot(action['after'])
        need(action['before']['tick']<=first['tick']<=last['tick']<=action['after']['tick'],'Touch frame chronology differs')
        if index:need(actions[index-1]['events'][1]<ids[0],'Touch stream ownership differs')
        if action['role'] in ('command-button','house-button','confirm-build'):
            w=action.get('widget',{});rect=w.get('rect')
            need(type(rect) is list and len(rect)==4 and all(number(x) for x in rect) and min(rect[2:])>=44 and within(first['position'],rect) and
                 rect[0]>=0 and rect[1]>=0 and rect[0]+rect[2]<=390 and rect[1]+rect[3]<=844 and w.get('visible') is True and w.get('disabled') is False and
                 type(w.get('text')) is str and w['text'].startswith({'command-button':'指令','house-button':'民居','confirm-build':'確認建造'}[action['role']]),'Touch UI button differs')
        else:need(action.get('widget')=={},'Touch UI button differs')
    extra=[i for i in range(len(events)) if i not in claimed]
    need((not extra if flow=='touch-gather' else len(extra)%3==0 and len(extra)<=15),'Touch stream ownership differs')
    for offset in range(0,len(extra),3):
        ids=extra[offset:offset+3];seq=[events[i] for i in ids]
        need(ids==list(range(ids[0],ids[0]+3)) and all(e['role']=='reveal-house' for e in seq) and
             [e['type'] for e in seq]==['InputEventScreenTouch','InputEventScreenDrag','InputEventScreenTouch'] and seq[0]['pressed'] is True and seq[2]['pressed'] is False and
             seq[1]['position']==seq[2]['position'] and pair(seq[1].get('relative')) and -110<=seq[1]['relative'][0]<0 and seq[1]['relative'][1]==0 and
             all(math.isclose(seq[1]['position'][k]-seq[0]['position'][k],seq[1]['relative'][k],abs_tol=1e-6) for k in (0,1)) and
             actions[0]['events'][1]<ids[0]<actions[1]['events'][0],'Touch stream ownership differs')
    for frame,index in zip(frames[1:],[0,1,2,3,3,3,3,3,3]):
        need(frame['input_event_count']==actions[index]['events'][1]+1,'Touch frame chronology differs')
    for action,(before,after) in zip(actions,[(0,1),(1,2),(2,3),(3,4)]):
        need(frames[before]['game_tick']<=action['before']['tick']<=action['after']['tick']<=frames[after]['game_tick'],'Touch frame chronology differs')
    need(actions[0]['target_id']==worker and actions[0]['before']['selected']==initial['selected'] and worker in actions[0]['after']['selected'],'Touch public worker differs')
    if flow=='touch-gather':validate_gather(report,lock)
    else:return validate_build(report,lock)
    return []

def validate_gather(r,lock):
    f=r['frames'];worker=r['worker_id'];resource=r.get('resource_id');select,guidance,command,order=r['actions']
    need(integer(resource) and resource!=worker and r.get('house_id')==-1 and r.get('confirm_bank_milli')=={},'Touch contract differs')
    need(guidance['target_id']==order['target_id']==resource and worker in guidance['after']['selected'] and guidance['after']['own_pending_commands']==0 and
         guidance['after']['touch_mode'] is False and command['after']['touch_mode'] is True and order['before']['touch_mode'] is True and
         order['after']['touch_mode'] is False and order['after']['own_pending_commands']==1,'Touch intent transition differs')
    need('指令' in f[2]['ui']['toast'] and f[2]['ui']['toast_visible'] is True and f[3]['ui']['touch_command'] is True,'Touch intent transition differs')
    for i in (4,5,6,9):need(own(f[i],worker)['state']=='gather' and own(f[i],worker)['target']==resource,'Touch public worker differs')
    pose(f[5],worker,'gather_wood',lock);pose(f[7],worker,'carry_walk',lock)
    need(number(own(f[6],worker)['carry']) and number(own(f[7],worker)['carry']) and own(f[6],worker)['carry']>0 and own(f[6],worker)['carry_type']=='wood' and own(f[7],worker)['state']=='deliver' and
         own(f[7],worker)['carry']>0 and own(f[7],worker)['carry_type']=='wood' and own(f[9],worker)['carry']==0,'Touch deposit provenance differs')
    carry=r.get('observations');need(type(carry) is list and len(carry)==1,'Touch deposit provenance differs');carry=carry[0];snapshot(carry['snapshot'])
    need(carry.get('stage')=='carry-observed' and carry.get('worker_id')==worker and number(carry.get('carry')) and carry['carry']>0 and
         carry.get('carry_type')=='wood' and integer(carry.get('tick')) and order['after']['tick']<=carry['tick']<=f[8]['game_tick'],'Touch deposit provenance differs')
    for i,frame in enumerate(f):
        s=frame['snapshot']
        need(s['built']==0 and s['bank_milli']['food']==150000,'Touch deposit provenance differs')
        if i<8:need(s['delivered']==0 and s['bank_milli']['wood']==200000,'Touch deposit provenance differs')
        else:need(s['delivered']>0 and math.isclose(s['bank_milli']['wood']-200000,s['delivered']*1000,abs_tol=1e-6),'Touch deposit provenance differs')
        need(all(b['kind']!='house' for b in frame['own_buildings']),'Touch construction provenance differs')
    need(f[9]['snapshot']['delivered']==f[8]['snapshot']['delivered'] and f[9]['snapshot']['bank_milli']==f[8]['snapshot']['bank_milli'],'Touch deposit provenance differs')

def validate_build(r,lock):
    f=r['frames'];worker=r['worker_id'];house=r.get('house_id');select,start,hold,confirm=r['actions'];plot=r.get('plot')
    need(integer(house) and house!=worker and r.get('resource_id')==-1 and r.get('observations')==[],'Touch contract differs')
    need(type(plot) is list and len(plot)==3 and all(number(x) for x in plot) and plot[1]==0 and -40<plot[0]<40 and -40<plot[2]<40,'Touch construction provenance differs')
    need(start['after']['build_mode']==hold['after']['build_mode']=='house' and start['after']['own_pending_commands']==hold['after']['own_pending_commands']==0 and
         start['before']['bank_milli']==start['after']['bank_milli']==hold['after']['bank_milli']=={'food':150000,'wood':200000} and
         confirm['before']['build_mode']=='house' and confirm['after']['build_mode']=='' and confirm['after']['own_pending_commands']==1 and
         confirm['before']['bank_milli']==confirm['after']['bank_milli']==r['confirm_bank_milli']=={'food':150000,'wood':200000},'Touch intent transition differs')
    need(f[2]['ui']['build_mode']=='house' and f[2]['ui']['held'] is False,'Touch construction provenance differs')
    preview=f[3]['ui'];need(preview['held'] is True and preview['placement_ok'] is True and preview['build_mode']=='house' and
         preview['confirm']['visible'] is True and preview['confirm']['disabled'] is False and preview['preview_position']==plot,'Touch construction provenance differs')
    previous=0
    for i,frame in enumerate(f):
        s=frame['snapshot'];need(s['delivered']==0 and s['bank_milli']=={'food':150000,'wood':150000 if i>=4 else 200000} and s['built']==(1 if i>=8 else 0),'Touch construction provenance differs')
        sites=[b for b in frame['own_buildings'] if b.get('kind')=='house']
        if i<4:need(not sites,'Touch construction provenance differs');continue
        need(len(sites)==1 and sites[0]['id']==house and sites[0]['position']==plot and sites[0]['built'] is (i>=8),'Touch construction provenance differs')
        progress=sites[0]['progress'];need(number(progress) and progress>=previous and (progress==1 if i>=8 else 0<=progress<1),'Touch construction provenance differs');previous=progress
        if i>=5 and i<8:
            need(own(frame,worker)['state']=='build' and own(frame,worker)['target']==house,'Touch public worker differs');pose(frame,worker,'build',lock)
    for i,lo,hi in [(5,0,.25),(6,.25,.5),(7,.5,1)]:
        progress=[b for b in f[i]['own_buildings'] if b['id']==house][0]['progress'];need(lo<=progress<hi and progress>0,'Touch construction provenance differs')
    need(r.get('required_house_work_ticks')==400 and r.get('tick_seconds')==.05 and r.get('required_house_work_seconds')==20 and
         f[8]['game_tick']-confirm['after']['tick']>=400 and f[8]['game_seconds']-confirm['after']['tick']*.05>=20-1e-6,
         'Touch construction provenance differs')

    return validate_hud_settle(f)

def validate_hud_settle(frames):
    for frame in frames:
        need(integer(frame.get('game_frame_counter')) and integer(frame.get('process_frame')),'Touch frame chronology differs')
        s=frame['snapshot'];need(integer(s.get('population')) and integer(s.get('capacity')),'Touch ordinary runtime differs')
        label=frame['ui'].get('top_resources',{});text=label.get('text');rect=label.get('rect')
        need(type(text) is str and re.fullmatch(r'食糧 ([0-9]{1,6})   木材 ([0-9]{1,6})   人口 ([0-9]{1,3})/([0-9]{1,3})',text) is not None and
             label.get('visible') is True and type(rect) is list and len(rect)==4 and all(number(x) for x in rect) and
             rect[0]>=0 and rect[1]>=0 and rect[2]>0 and rect[3]>0 and rect[0]+rect[2]<=390 and rect[1]+rect[3]<=844,
             'Touch HUD evidence malformed')
    immediate,settled=frames[8:]
    need(settled['game_frame_counter']-immediate['game_frame_counter']>=4 and settled['process_frame']-immediate['process_frame']>=4 and
         settled['game_frame_counter']//4>immediate['game_frame_counter']//4,'Touch HUD refresh interval incomplete')
    need(immediate['snapshot']['capacity']==settled['snapshot']['capacity']==15 and
         immediate['snapshot']['population']==settled['snapshot']['population']==frames[0]['snapshot']['population']==6 and
         frames[0]['snapshot']['capacity']==10,'Touch HUD snapshot differs')
    def displayed(frame):return [int(x) for x in re.fullmatch(r'食糧 ([0-9]{1,6})   木材 ([0-9]{1,6})   人口 ([0-9]{1,3})/([0-9]{1,3})',frame['ui']['top_resources']['text']).groups()]
    expected=[150,150,6,15];observed=displayed(settled)
    # Retain authentic defect pixels, but the separate post-upload UI gate must fail.
    return [] if observed==expected else [{'kind':'settled_hud_mismatch','expected':expected,'observed':observed,
         'normal_frame_advance':settled['game_frame_counter']-immediate['game_frame_counter']}]

original_scan=base.scan
def scan_with_pacing(directory,lock,lock_sha256):
    validate_pacing(json.loads((directory/'guard-receipt.json').read_text()),lock)
    return original_scan(directory,lock,lock_sha256)
base.scan=scan_with_pacing
base.validate_scenario=validate_touch
base.SAFE_SCAN_REASONS=base.SAFE_SCAN_REASONS|ERRORS
if __name__=='__main__':
    p=argparse.ArgumentParser()
    for name in ('directory','lock','report'):p.add_argument('--'+name,type=Path,required=True)
    args=p.parse_args();raise SystemExit(base.scan_to_report(args.directory,args.lock,args.report))
