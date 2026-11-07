"""File-only result gate. Never represents a native engine run by itself."""
import argparse, hashlib, json, math
from pathlib import Path
LABELS=['synthetic_victory','routed_surrender_defeat','fresh_restart','fresh_touch_order']
CHECKS=['portrait viewport','synthetic victory semantics','synthetic_victory image','surrender menu touch target','routed surrender dialog','one surrender command','one normal process tick consumes surrender','actual surrender defeat','routed_surrender_defeat image','restart fit and hit target','held press does not restart','release reloads once and frees old scene','fresh exact initial state','fresh_restart image','repeat tap no extra restart payment queue or command','fresh worker available','fresh worker selects','fresh command targets','fresh touch submits exactly one order','fresh_touch_order image']
def validate(r):
    def need(ok,why):
        if not ok: raise ValueError(why)
    need(r.get('build')=='vc-d99ac5d19247','build')
    need(r.get('passed') is True and r.get('failed')==0,'reported status')
    need(r.get('checks')==[{'name':s,'pass':True} for s in CHECKS],'ordered checks')
    need(r.get('reload_events')==1,'exactly one reload')
    need(r.get('initial')==r.get('fresh') and isinstance(r.get('initial'),dict),'fresh state parity')
    initial=r['initial'];snap=initial['snapshot']
    for key in ['touch_points','touch_epochs','action_touch_scroll','box_cancel_press','box_cancel_repeat','canceled_touches','processed_commands']:
        need(initial.get(key)=={},'fresh empty '+key)
    for key in ['touches','path_requests','spawn_commits','commands']:
        need(initial.get(key)==[],'fresh empty '+key)
    for key in ['gui_presses','command_sequence','next_queue_id']:
        need(type(initial.get(key)) is int and initial[key]==0,'fresh zero '+key)
    need(initial.get('touch_gesture') is False and initial.get('touch_command') is False,'fresh gestures')
    for key in ['resources_hud','time_hud','title','detail']:
        need(type(initial.get(key)) is str and len(initial[key])>0,'fresh HUD '+key)
    need(snap['tick']==0 and snap['outcome']=='' and snap['game_over'] is False and snap['food']==150 and snap['wood']==200 and initial['commands']==[] and initial['selected']==[0] and initial['panel'] is False,'initial')
    frames=r.get('frames',[])
    need(len(frames)==4 and [f['label'] for f in frames]==LABELS,'frame sequence')
    for i,f in enumerate(frames):
        need(f['build']==r['build'] and f['viewport']==[390,844] and f['display']=='X11','frame provenance')
        need(f['reloads']==int(i>=2),'frame reload count')
        need(f['state']['over'] is (i<2) and f['state']['panel'] is (i<2),'terminal visibility')
        if i<2:
            for rect in [f['panel'],f['title']['rect'],f['body']['rect'],f['restart']['rect']]:
                need(len(rect)==4 and all(type(x) in (int,float) and math.isfinite(x) for x in rect),'finite rect')
                x,y,w,h=rect
                need(x>=-1 and y>=-1 and w>=0 and h>=0 and x+w<=391 and y+h<=845,'clipping')
            need(f['body']['minimum_height']<=f['body']['rect'][3]+1,'body clipped')
            need(f['restart']['text']=='再開一局' and f['restart']['disabled'] is False and min(f['restart']['rect'][2:])>=44,'restart target')
    need(frames[0]['title']['text']=='王旗再起' and frames[0]['body']['text']=='敵方持續 60 秒沒有單位或任何復原途徑，已自動投降。','victory display')
    need(frames[1]['title']['text']=='我方投降' and frames[1]['body']['text']=='你已確認投降。本局判定為失敗。','defeat display')
    need(frames[2]['state']==initial,'captured fresh parity')
    commands=frames[3]['state']['commands'];need(len(commands)==1 and commands[0]['type']=='order' and commands[0]['target']==-1 and commands[0]['ids']==frames[3]['state']['selected'],'fresh order')
    need(frames[3]['state']['bank']==initial['bank'],'no accidental payment')
    inputs=r.get('inputs',[])
    need(len(inputs)==16,'input count')
    previous_frame=-1
    for e in inputs:
        need(type(e.get('frame')) is int and e['frame']>previous_frame,'input frame sequence');previous_frame=e['frame']
        need(all(type(e.get(k)) in (int,float) and math.isfinite(e[k]) for k in ['x','y']) and 0<=e['x']<390 and 0<=e['y']<844,'touch bounds')
    for i in range(0,len(inputs),2):
        a,b=inputs[i:i+2]
        need(a['pressed'] is True and b['pressed'] is False and a['x']==b['x'] and a['y']==b['y'] and a['canceled'] is False and b['canceled'] is False,'touch pair')
        need(a['viewport']==b['viewport']==('surrender_dialog' if i==4 else 'root'),'touch viewport')
    need(inputs[6]['reloads']==inputs[7]['reloads']==0 and all(e['reloads']==1 for e in inputs[8:]),'restart input boundary')
    need(inputs[7]['frame']-inputs[6]['frame']>=20,'held frame interval')
    need(inputs[8]['double_tap'] is True and sum(e['double_tap'] for e in inputs)==1,'repeat boundary')
    return {'passed':True,'checks':len(CHECKS),'frames':4,'scope':'file-only verification of controlled portrait report; requires separately verified actual runner and raw images'}
def main():
    p=argparse.ArgumentParser();p.add_argument('report',type=Path);args=p.parse_args()
    r=json.loads(args.report.read_text());result=validate(r)
    for f in r['frames']:
        path=args.report.parent/f['image']
        if path.name!=f['image'] or hashlib.sha256(path.read_bytes()).hexdigest()!=f['image_sha256']:raise ValueError('image binding')
        if json.loads(Path(str(path)+'.json').read_text())!=f:raise ValueError('sidecar parity')
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
