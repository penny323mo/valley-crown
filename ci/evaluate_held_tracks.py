"""Independent bounded expected-value evaluation for pinned Godot4.6.3 held tracks.
Only forward seeks within clips, endpoint keys0/length, transitions1, native
nearest/linear interpolation and loop_none/loop_linear are supported.
This evaluator changes no animation, timestamp or acceptance tolerance.
"""
import math,struct
EPS=1e-5
def f32(x):return struct.unpack('<f',struct.pack('<f',x))[0]
def close_time(a,b):return a==b or abs(a-b)<max(EPS,EPS*abs(a))
def find(times,t):
 lo,hi=0,len(times)-1
 while lo<=hi:
  mid=(lo+hi)//2
  if close_time(t,times[mid]):return mid
  if t<times[mid]:hi=mid-1
  else:lo=mid+1
 return mid-1 if times[mid]>t else mid

def slerp(a,b,u):
 dot=f32(sum(f32(x*y) for x,y in zip(a,b)))
 if dot<0:dot=-dot;b=[-x for x in b]
 if f32(1-dot)>EPS:
  omega=f32(math.acos(max(-1.,min(1.,dot))));sinom=f32(math.sin(omega))
  l=f32(math.sin((1.-u)*omega)/sinom);r=f32(math.sin(f32(u*omega))/sinom)
 else:l=f32(1-u);r=u
 return [f32(f32(l*x)+f32(r*y)) for x,y in zip(a,b)]

def sample(track,time,length,loop):
 assert track['type'] in ('position_3d','rotation_3d')
 assert track['interpolation'] in (0,1) and type(track['loop_wrap']) is bool
 assert loop in (0,1) and math.isfinite(time) and 0<=time<=length
 times=[f32(t) for t in track['times']];values=[[f32(v) for v in row] for row in track['values']]
 width=4 if track['type']=='rotation_3d' else 3
 assert len(times)==len(values)>=2 and times==sorted(set(times))
 assert times[0]==0 and times[-1]==f32(length)
 assert all(len(row)==width and all(math.isfinite(v) for v in row) for row in values)
 idx=find(times,time);last=len(times)-1
 assert 0<=idx<=last
 wrap=loop==1 and track['loop_wrap']
 nxt=(idx+1)%len(times) if wrap else min(idx+1,last)
 if idx==last:
  delta=f32((length-times[idx])+times[nxt]) if wrap else 0.
  offset=f32(time-times[idx]) if wrap else 0.
 else:delta=f32(times[nxt]-times[idx]);offset=f32(time-times[idx])
 u=0. if abs(delta)<EPS else f32(offset/delta)
 if track['interpolation']==0:return values[idx]
 if track['type']=='rotation_3d':return slerp(values[idx],values[nxt],u)
 return [f32(x+f32(f32(y-x)*u)) for x,y in zip(values[idx],values[nxt])]

def reference(plan,clip,prop,time):
 changes=plan['clips'][clip]['changes']
 tracks=[c['replacement'] for c in changes if c['replacement']['type']==prop+'_3d']
 assert len(tracks)==1
 return sample(tracks[0],time,plan['clips'][clip]['length_unchanged'],1 if clip in ('idle','walk') else 0)
