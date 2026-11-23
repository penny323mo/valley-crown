#!/usr/bin/env python3
"""Hash/authority verification and native unaltered PNG pixel metrics (stdlib)."""
import hashlib,json,statistics,struct,sys,zlib
from pathlib import Path

def sha(d): return hashlib.sha256(d).hexdigest()
def load(p): return json.loads(Path(p).read_text())
def rect_has(rect,x,y):
    if not rect:return False
    l,t,w,h=rect
    return l<=x<l+w and t<=y<t+h

def png(path,header_expected):
    content=path.read_bytes()
    if content[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError(path)
    pos=8;chunks=[]
    while pos<len(content):
        length,typ=struct.unpack_from('>I4s',content,pos)
        payload=content[pos+8:pos+8+length]
        assert len(payload)==length
        assert (zlib.crc32(typ+payload)&0xffffffff)==struct.unpack_from('>I',content,pos+8+length)[0]
        chunks.append((typ,payload));pos+=12+length
    assert chunks[-1]==(b'IEND',b'') and chunks[0][0]==b'IHDR'
    w,h,depth,kind,compression,filter_,interleave=struct.unpack('>IIBBBBB',chunks[0][1])
    assert [w,h]==header_expected and depth==8 and kind in (2,6) and not(compression or filter_ or interleave)
    stride=3+(kind==6); width=w*stride
    raw=zlib.decompress(b''.join(p for t,p in chunks if t==b'IDAT'))
    assert len(raw)==(width+1)*h
    def paeth(a,b,c):
        d=a+b-c;pa=abs(d-a);pb=abs(d-b);pc=abs(d-c)
        return a if pa<=pb and pa<=pc else b if pb<=pc else c
    rows=[]; id_=0; prior=bytearray(width)
    for y in range(h):
        f=raw[id_]; assert 0<=f<=4
        row=bytearray(raw[id_+1:id_+1+width]); id_+=width+1
        if f:
            for x in range(width):
                a=row[x-stride] if x>=stride else 0
                b=prior[x]
                c=prior[x-stride] if x>=stride else 0
                num=(a,b,(a+b)//2,paeth(a,b,c))[f-1]
                row[x]=(row[x]+num)&255
        rows.append(row);prior=row
    return rows,stride

def bright_grass(color):
    r,g,b=color
    return g>=65 and g-b>=20 and g>r

def compare(report1,report2,pins,mode):
    a_path,b_path=(Path(r).parent for r in (report1,report2))
    a,b=(load(r) for r in (report1,report2))
    for role,r in [('baseline',a),('candidate',b)]:
        assert r['failed']==0 and r['role']==role and r['result']==mode
        assert r['runtime']['hex']==0x040603
        assert r['reported_build']==pins[role]['reported_build']
        for key in ('game_sha','fog_sha','rules_sha','manifest_sha'): assert r[key]==pins[role][key]
        if mode=='RENDERED':
            assert r['png_count']==6 and r['display']!='headless' and r['renderer']=='gl_compatibility' and 'llvmpipe' in r['adapter'].lower()
        else:assert r['png_count']==0
    shared=('name','size','focus','zoom','ground_extents','map_half','projection','base_projection','authority_sha','hud','input_grid','top','bottom','minimap','visibility_sha')
    names=('survival-reproduced-camera','west','east','north','south','wide-zoomed-corner')
    assert tuple(f['name'] for f in a['frames'])==names
    assert tuple(f['name'] for f in b['frames'])==names
    frame_results=[]
    count_probes=0
    for old,new in zip(a['frames'],b['frames'],strict=True):
        n=new['name']
        for key in shared:assert old[key]==new[key], (n,key)
        assert old['veil_extents']==[40.,40.] and new['veil_extents']==new['ground_extents'],n
        count_probes+=len(old['input_grid'])
        if mode=='METADATA_ONLY':continue
        assert new['draw_calls']>0 and new['primitives']>0
        assert old['draw_calls']==new['draw_calls'] and old['primitives']==new['primitives'], n
        assert old['file']==new['file']==n+'.png'
        ap,bp=a_path/old['file'],b_path/new['file']
        assert sha(ap.read_bytes())==old['sha256'] and sha(bp.read_bytes())==new['sha256']
        ar,ast=png(ap,old['size']);br,bst=png(bp,new['size'])
        start,dx,dy=old['base_projection'];half=old['map_half'];measure=.12
        inside=inside_diff=inside_diff_2=outside=obright=nbright=0
        seam_total=seam_bright_old=seam_bright_new=inner_flank=inner_flank_diff_gt2=0
        oldband=[];newband=[];unknown=[]
        edges={}
        for y,(aa,bb) in enumerate(zip(ar,br,strict=True)):
            for x in range(old['size'][0]):
                if any(rect_has(old[k],x+.5,y+.5) for k in ('top','bottom','minimap')):continue
                wx,wz=(start[k]+x*dx[k]+y*dy[k] for k in (0,2))
                m=max(abs(wx),abs(wz))
                aa_rgb=aa[x*ast:x*ast+3];bb_rgb=bb[x*bst:x*bst+3]
                if abs(m-half)<=measure:
                    seam_total+=1
                    seam_bright_old+=bright_grass(aa_rgb)
                    seam_bright_new+=bright_grass(bb_rgb)
                    if m<=half-.012:
                        inner_flank+=1
                        inner_flank_diff_gt2+=max(abs(i-j) for i,j in zip(aa_rgb,bb_rgb))>2
                if m<=half-measure:
                    inside+=1
                    diff=max(abs(i-j) for i,j in zip(aa_rgb,bb_rgb))
                    inside_diff+=diff>0
                    inside_diff_2+=diff>2
                    if n==names[0] and -40+measure<wx<=-39:unknown.append(tuple(aa_rgb))
                elif m>half+measure:
                    outside+=1;obright+=bright_grass(aa_rgb);nbright+=bright_grass(bb_rgb)
                    edge=('west' if wx<0 else 'east') if abs(wx)>=abs(wz) else ('north' if wz<0 else 'south')
                    edges[edge]=edges.get(edge,0)+1
                    if n==names[0] and -41<=wx<-40-measure:oldband.append(tuple(aa_rgb));newband.append(tuple(bb_rgb))
        assert outside>=1000 and inside>=1000 and obright>=500,(n,inside,outside,obright)
        assert inside_diff_2<=inside*.001,(n,inside_diff_2,inside)
        assert nbright<=obright*.05,(n,obright,nbright)
        assert seam_total>=300 and seam_bright_old>=100 and seam_bright_new==0,(n,'bright seam raw pixels',seam_total,seam_bright_old,seam_bright_new)
        assert inner_flank>=100 and inner_flank_diff_gt2==0,(n,'in-map seam flank',inner_flank,inner_flank_diff_gt2)
        if n in names[1:5]:assert edges.get(n,0)>=1000,(n,edges)
        summary=dict(name=n,inside=inside,inside_diff=inside_diff,inside_diff_over2=inside_diff_2,outside=outside,exterior_bright_old=obright,exterior_bright_candidate=nbright,draw_calls=old['draw_calls'],primitives=old['primitives'],outside_edges=edges,seam_band_pixels=seam_total,seam_bright_old=seam_bright_old,seam_bright_candidate=seam_bright_new,inner_flank_pixels=inner_flank,inner_flank_diff_over2=inner_flank_diff_gt2)
        if n==names[0]:
            median=lambda x: [statistics.median(ch) for ch in zip(*x)]
            a_med,b_med,u_med=map(median,(oldband,newband,unknown))
            assert len(oldband)>=500 and len(unknown)>=500
            assert max(abs(i-j) for i,j in zip(b_med,u_med))<=10,(b_med,u_med)
            summary['paired_edge_band_median_rgb']={'old_exterior':a_med,'new_exterior':b_med,'inside_unknown':u_med}
        frame_results.append(summary)
    if mode=='RENDERED':
        for path in (a_path,b_path):assert {p.name for p in path.glob('*.png')}=={name+'.png' for name in names}
    return dict(result=mode,scope='Exact committed/stamped original old and new runtime, matched actual native tick-zero Survival and camera-only edge probes. Only top-level build string omitted from cross-release checkpoint comparison. Metadata-only mode provides no pixel evidence.',checks=[len(a['checks']),len(b['checks'])],exact_authority_camera_hud_and_input_frames=len(names),same_touch_pick_ground_grid_samples=count_probes,cases=frame_results)
if __name__=='__main__':
    a,b,pins,mode=sys.argv[1:]
    assert mode in ('METADATA_ONLY','RENDERED')
    print(json.dumps(compare(a,b,load(pins),mode),ensure_ascii=False,indent=2))
