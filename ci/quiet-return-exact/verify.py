#!/usr/bin/env python3
"""Verify actual routed gameplay states, immutable builds and original PNG bytes."""
import hashlib,json,struct,sys,zlib
from pathlib import Path
out,pins=map(Path,sys.argv[1:3]);mode=sys.argv[3]
assert mode in ('RENDERED','METADATA_ONLY')
p=json.loads(pins.read_bytes())
sha=lambda b:hashlib.sha256(b).hexdigest()
sizes=((480,270),(568,320)); counts={}; images={}; paired={}
roles=('baseline','candidate')
def assert_png(path,w,h):
    b=path.read_bytes();assert b.startswith(b'\x89PNG\r\n\x1a\n')
    i=8; chunks=[]
    while i<len(b):
        n,tag=struct.unpack_from('>I4s',b,i);raw=b[i+8:i+8+n];crc,=struct.unpack_from('>I',b,i+8+n)
        assert zlib.crc32(tag+raw)&0xffffffff==crc
        if tag==b'IHDR':assert struct.unpack_from('>II',raw)==(w,h)
        chunks.append(tag);i+=n+12
    assert i==len(b) and chunks[0]==b'IHDR' and chunks.count(b'IHDR')==1 and b'IDAT' in chunks and chunks[-1]==b'IEND'
    return sha(b)
for role in roles:
    a=json.loads((out/role/'source-check.json').read_text())
    assert a['status']=='PASS_SOURCE_ONLY' and a['build']==p[role]['build'] and a['runtime_inputs']==353
    imports=(out/role/'import.log').read_text().splitlines()
    assert not any(s.startswith(('ERROR:','SCRIPT ERROR:')) for s in imports)
for w,h in sizes:
    dim=f'{w}x{h}'; reports={}
    for role,expected_count in zip(roles,(19,21)):
        root=out/role/dim
        b=(root/'run.log').read_text()
        assert not any(line.startswith(('ERROR:','SCRIPT ERROR:')) for line in b.splitlines())
        a,=[json.loads(x[len('ACTUAL_QUIET_RETURN '):]) for x in b.splitlines() if x.startswith('ACTUAL_QUIET_RETURN ')]
        reports[role]=a
        assert a['role']==role and a['engine_hex']==0x040603 and a['failed']==0 and a['size']==[w,h]
        assert all(y['pass'] for y in a['checks'])
        assert a['source_basis']==p['baseline']['source']
        assert all(a[k]==p[role][k] for k in ('build','runtime_sha256','alert_sha256','rules_sha256','manifest_sha256'))
        assert (a['renderer']=='gl_compatibility' and a['display']!='headless') if mode=='RENDERED' else a['display']=='headless'
        frames=['offscreen-drawer']+(['fight-returned'] if role=='candidate' else [])
        assert set(a['capture'])==set(frames)
        assert len(a['checks'])==expected_count+(4*len(frames) if mode=='RENDERED' else 0)
        n=a['observations']['natural_defeat'];end=a['observations']['review_after_natural_defeat']
        assert n['tick']==6558 and n['title']=='聚落失守' and end['terminal_unchanged']=='defeat'
        assert a['observations']['first_damage_alert']['tick']==3692
        post=a['observations']['offscreen_fight_after_ack']
        assert len(post['own_attack_log'])==25 and len(post['samples'])==20 and sum(x['victim']=='town_center' for x in post['own_attack_log'])==14
        assert all(x['same_entry'] and x['acknowledged'] and x['pending']==0 and not x['button_visible'] for x in post['samples'])
        counts[f'{role}/{dim}']=len(a['checks'])
        assert {f.name for f in root.glob('*.png')}==({k+'.png' for k in frames} if mode=='RENDERED' else set())
        for frame in frames:
            v=a['capture'][frame]
            if mode=='METADATA_ONLY':
                assert 'png_sha256' not in v
                continue
            name=frame+'.png';digest=assert_png(root/name,w,h)
            assert digest==v['png_sha256']
            images[f'{role}/{dim}/{name}']=digest
    equal=lambda x:{k:v for k,v in x.items() if k!='png_sha256'}
    old,new=(reports[r] for r in roles)
    a,b=(equal(q['capture']['offscreen-drawer']) for q in (old,new))
    assert a==b and a['drawer_open'] and not a['tutorial_collapsed']
    assert a['world']['tick']==4092 and a['world']['unread']==0 and a['world']['player_commands']=={}
    owners=[x for x in a['world']['actors'] if x[0] in a['world']['selected']]
    assert len(owners)==1 and owners[0][1]=='town_center' and owners[0][3]==1150
    old_d,new_d=(q['marks']['menu_offscreen'] for q in (old,new))
    without_button=lambda d:{k:v for k,v in d.items() if k!='button'}
    assert without_button(old_d)==without_button(new_d) and old_d['button']==[] and old_d['keep_projected'][0]<0 and old_d['keep_last_damage_tick']==4091
    assert new_d['button']==([348,126,56,46] if w==480 else [436,126,56,46])
    x,y,rw,rh=new_d['button'];mx,my,mw,mh=new_d['menu_rect']
    assert mx<=x and my<=y and x+rw<=mx+mw and y+rh<=my+mh and 0<=x and 0<=y and x+rw<=w and y+rh<=h
    after=equal(new['capture']['fight-returned']); m=new['marks']['return']
    assert after['world']==a['world'] and after['camera']!=a['camera'] and after['camera_focus']==[-25,0,24] and not after['drawer_open'] and not after['tutorial_collapsed']
    assert m['tick']==4092 and m['keep_hp']==1150 and m['unread']==0 and not m['drawer']
    assert all(abs(v-e)<.05 for v,e in zip(m['keep_center'],[w/2,h/2]))
    assert len(m['footprint'])==4 and all(x['world_roi'] for x in m['footprint'])
    assert sorted(x['kind'] for x in m['opposing_force'])==['archer','archer','spearman','spearman']
    paired[dim]={'shared_tick':4092,'known_actor_count':len(a['world']['actors']),'offscreen_keep_px':old_d['keep_projected'],'same_drawer_camera':a['camera'],
                 'new_drawer_button':new_d['button'],'returned_keep_px':m['keep_center'],'retained_world':a['world'],'returned_visible_foes':m['opposing_force'],
                 'world_footprint_samples':m['footprint'],'same_natural_keep_loss_tick':6558}
assert len(images)==(6 if mode=='RENDERED' else 0) and len(set(images.values()))==len(images)
print(json.dumps({'status':mode,'builds':[p[r]['build'] for r in roles],'commits':[p[r]['source'] for r in roles],'checks':counts,
 'pairs':paired,'original_pngs':images,'png_count':len(images),
 'scope':'Matched ordinary Standard native route: real menu touches, real two-finger pan, genuine AI first alert, 25 settled after ACK, active offscreen Keep and explicit candidate return. Current and old screenshots are full native originals; no WebGL/iPhone claim.'},ensure_ascii=False,indent=2))
