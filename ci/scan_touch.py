#!/usr/bin/env python3
"""Strict ordinary touch scenario; the proven guard/PNG/privacy scanner is unchanged."""
from pathlib import Path
import argparse, math
import scan_evidence as base

SCENARIO='native_routed_touch_gather_build_v1'
LABELS=['opening','worker-selected','target-guidance','command-mode','woodcutting',
        'deposit-complete','build-preview','build-confirmed','construction-active','house-complete']
ROLES=['select-worker','target-guidance','command-button','order-wood','house-button','hold-building-plot','confirm-build']
CONTRACT={'scenario':SCENARIO,'viewport':[390,844],'frames':LABELS,'input':'viewport.push_input(InputEventScreenTouch,false)',
          'simulation':'normal_seeded_process_fixed30','restart':False}
ERRORS={'Touch contract differs','Touch ordinary runtime differs','Touch action order differs','Touch event schema differs',
        'Touch event coordinates differ','Touch stream ownership differs','Touch UI button differs','Touch intent transition differs',
        'Touch frame chronology differs','Touch public worker differs','Touch deposit provenance differs','Touch construction provenance differs',
        'Touch public pose differs','Touch geometry or capture sequence differs'}
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

def validate_touch(report,lock):
    need(lock.get('touch_contract')==CONTRACT and lock['capture_contract']=={'mode':'gameplay','kind':'genuine_native_game_viewport','frame_count':10}
         and report.get('scenario')==SCENARIO,'Touch contract differs')
    frames=report['frames'];events=report.get('events');actions=report.get('actions')
    need([f.get('label') for f in frames]==LABELS and len({f['image_sha256'] for f in frames})==10,'Touch geometry or capture sequence differs')
    worker,resource,house=(report.get(k) for k in ('worker_id','resource_id','house_id'))
    need(all(integer(x) for x in (worker,resource,house)) and len({worker,resource,house})==3 and
         type(report.get('initial_house_ids')) is list and all(integer(x) for x in report['initial_house_ids']) and house not in report['initial_house_ids'],'Touch construction provenance differs')
    plot=report.get('plot')
    need(type(plot) is list and len(plot)==3 and all(number(x) for x in plot) and plot[1]==0 and -40<plot[0]<40 and -40<plot[2]<40,'Touch construction provenance differs')
    for i,f in enumerate(frames):
        snapshot(f['snapshot'])
        need(f.get('scenario')==SCENARIO and f.get('framebuffer')==f.get('logical_viewport')==[390,844] and f.get('content_scale_factor')==1 and
             f.get('camera_focus')==[-25,0,24] and f.get('camera_zoom')==30 and f.get('test_mode') is False and f.get('ai_enabled') is True and
             f.get('economy_audit_ok') is True,'Touch ordinary runtime differs')
        need(integer(f.get('game_tick')) and number(f.get('game_seconds')) and f['snapshot']['tick']==f['game_tick'] and
             math.isclose(f['game_seconds'],f['game_tick']*.05,abs_tol=1e-6) and (i==0 or f['game_tick']>=frames[i-1]['game_tick']),
             'Touch frame chronology differs')
        need(integer(f.get('input_event_count')) and (i==0 or f['input_event_count']>=frames[i-1]['input_event_count']),'Touch frame chronology differs')
        if i:need(worker in f['selected'] and worker in f['snapshot']['selected'],'Touch public worker differs')
    need(type(actions) is list and [a.get('role') for a in actions]==ROLES and all(a.get('kind')=='tap' for a in actions),'Touch action order differs')
    need(type(events) is list and 14<=len(events)<=29 and frames[0]['input_event_count']==0 and frames[-1]['input_event_count']==len(events),'Touch event schema differs')
    for i,event in enumerate(events):
        need(event.get('sequence')==i and event.get('type') in ('InputEventScreenTouch','InputEventScreenDrag') and event.get('index')==0 and
             event.get('role') in ROLES+['reveal-house'] and integer(event.get('tick')) and integer(event.get('process_frame')),'Touch event schema differs')
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
    need(len(extra)%3==0 and len(extra)<=15,'Touch stream ownership differs')
    for offset in range(0,len(extra),3):
        ids=extra[offset:offset+3];seq=[events[i] for i in ids]
        need(ids==list(range(ids[0],ids[0]+3)) and all(e['role']=='reveal-house' for e in seq) and
             [e['type'] for e in seq]==['InputEventScreenTouch','InputEventScreenDrag','InputEventScreenTouch'] and seq[0]['pressed'] is True and seq[2]['pressed'] is False and
             seq[1]['position']==seq[2]['position'] and pair(seq[1].get('relative')) and -110<=seq[1]['relative'][0]<0 and seq[1]['relative'][1]==0 and
             all(math.isclose(seq[1]['position'][k]-seq[0]['position'][k],seq[1]['relative'][k],abs_tol=1e-6) for k in (0,1)) and
             actions[3]['events'][1]<ids[0]<actions[4]['events'][0],'Touch stream ownership differs')
    for frame,index in zip(frames[1:],[0,1,2,3,3,5,6,6,6]):
        need(frame['input_event_count']==actions[index]['events'][1]+1,'Touch frame chronology differs')
    for action,(before,after) in zip(actions,[(0,1),(1,2),(2,3),(3,4),(5,6),(5,6),(6,7)]):
        need(frames[before]['game_tick']<=action['before']['tick']<=action['after']['tick']<=frames[after]['game_tick'],'Touch frame chronology differs')
    select,guidance,command,order,start,hold,confirm=actions
    need(select['target_id']==worker and guidance['target_id']==order['target_id']==resource and worker in select['after']['selected'] and
         worker in guidance['after']['selected'] and guidance['after']['own_pending_commands']==0 and guidance['after']['touch_mode'] is False and
         command['after']['touch_mode'] is True and order['before']['touch_mode'] is True and order['after']['touch_mode'] is False and order['after']['own_pending_commands']==1,
         'Touch intent transition differs')
    need('指令' in frames[2]['ui']['toast'] and frames[2]['ui']['toast_visible'] is True and frames[3]['ui']['touch_command'] is True,'Touch intent transition differs')
    need(own(frames[4],worker)['state']=='gather' and own(frames[4],worker)['target']==resource,'Touch public worker differs');pose(frames[4],worker,'gather_wood',lock)
    carry=report.get('observations');need(type(carry) is list and len(carry)==1,'Touch deposit provenance differs');carry=carry[0];snapshot(carry['snapshot'])
    need(carry.get('stage')=='carry-observed' and carry.get('worker_id')==worker and number(carry.get('carry')) and carry['carry']>0 and carry.get('carry_type')=='wood' and
         integer(carry.get('tick')) and order['after']['tick']<=carry['tick']<=frames[5]['game_tick'],'Touch deposit provenance differs')
    initial,deposit=frames[0]['snapshot'],frames[5]['snapshot'];amount=deposit['delivered']-initial['delivered']
    need(report['initial_delivered']==initial['delivered'] and amount>0 and deposit['bank_milli']['wood']-initial['bank_milli']['wood']==amount*1000 and
         deposit['bank_milli']['food']==initial['bank_milli']['food'],'Touch deposit provenance differs')
    need(start['after']['build_mode']==hold['after']['build_mode']=='house' and start['after']['own_pending_commands']==hold['after']['own_pending_commands']==0 and
         start['before']['bank_milli']==start['after']['bank_milli']==hold['after']['bank_milli'] and confirm['before']['build_mode']=='house' and
         confirm['after']['build_mode']=='' and confirm['after']['own_pending_commands']==1 and confirm['before']['bank_milli']==confirm['after']['bank_milli']==report['confirm_bank_milli'],
         'Touch intent transition differs')
    preview=frames[6]['ui'];need(preview['held'] is True and preview['placement_ok'] is True and preview['build_mode']=='house' and
         preview['confirm']['visible'] is True and preview['confirm']['disabled'] is False and preview['preview_position']==report['plot'],'Touch construction provenance differs')
    for i in (7,8,9):
        frame=frames[i];sites=[s for s in frame['own_buildings'] if s.get('id')==house]
        need(len(sites)==1 and sites[0]['kind']=='house' and sites[0]['position']==report['plot'] and sites[0]['built'] is (i==9),'Touch construction provenance differs')
        progress=sites[0]['progress'];need(number(progress) and (progress==1 if i==9 else ((0<progress<1) if i==8 else (0<=progress<1))),'Touch construction provenance differs')
        need(frame['snapshot']['bank_milli']['wood']==report['confirm_bank_milli']['wood']-50000 and frame['snapshot']['bank_milli']['food']==report['confirm_bank_milli']['food'],'Touch construction provenance differs')
    need(own(frames[8],worker)['state']=='build' and own(frames[8],worker)['target']==house and frames[9]['snapshot']['built']==frames[0]['snapshot']['built']+1,'Touch construction provenance differs')
    pose(frames[8],worker,'build',lock)
    return []

base.validate_scenario=validate_touch
base.SAFE_SCAN_REASONS=base.SAFE_SCAN_REASONS|ERRORS
if __name__=='__main__':
    p=argparse.ArgumentParser()
    for name in ('directory','lock','report'):p.add_argument('--'+name,type=Path,required=True)
    args=p.parse_args();raise SystemExit(base.scan_to_report(args.directory,args.lock,args.report))
