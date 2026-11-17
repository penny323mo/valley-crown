extends RefCounted
## Optional surplus-wood tower flank shields. Observation only, no hidden authority.
const RESERVE=200000
const COST=30000
const INTERVAL=100 # five game seconds, not every simulation tick
const MAX_ATTEMPTS=4
static func owned(r):
 return r.get("owned",false) and r.get("alive",false) and not r.get("remembered",true) and r.get("team",-1)==1
static func safe(records,point):
 for r in records:
  if not r.get("alive",false) or r.get("remembered",true) or r.get("team",-1)!=0:continue
  if r.get("category","")!="unit" and not (r.get("kind","")=="tower" and r.get("built",false)):continue
  if r.pos.distance_to(point)<14:return false
 return true
static func plan(records:Array,claimed:Dictionary,commands:Array,wood:int,attempts:Dictionary,now:int,skipped:Dictionary={})->Dictionary:
 if now%INTERVAL!=0 or wood<RESERVE+COST:return {}
 var used=0
 for mask in attempts.values():used+=int(mask)&1;used+=(int(mask)>>1)&1
 if used>=MAX_ATTEMPTS:return {}
 var workers=[];var towers=[];var foods=0;var pending={}
 for c in commands:
  if c.get("team",-1)!=1:continue
  if c.get("type","")=="build":return {}
  for id in c.get("ids",[]):pending[id]=true
 var keep={}
 for r in records:
  if not owned(r):continue
  if r.get("category","")=="building" and not r.get("built",false):return {}
  if r.get("kind","")=="town_center":keep=r
  if r.get("kind","")=="tower" and r.get("built",false):towers.append(r)
  if r.get("kind","")=="villager":
   workers.append(r)
   if r.get("state","") in ["gather","deliver"] and r.get("gather_type","")=="food":foods+=1
 if keep.is_empty() or workers.size()<8 or foods<2 or towers.is_empty():return {}
 towers.sort_custom(func(a,b):return a.id<b.id)
 if towers.size()>2:towers.resize(2)
 for tower in towers:
  if not safe(records,tower.pos):continue
  var forward=(Vector3.ZERO-keep.pos).normalized()
  if forward.length_squared()<0.5:forward=Vector3.FORWARD
  # Cardinal flank axis makes integer snapping retain >= 6 m central clearance.
  var lateral=Vector3.RIGHT if absf(forward.z)>=absf(forward.x) else Vector3.BACK
  for side in 2:
   if ((int(attempts.get(tower.id,0))|int(skipped.get(tower.id,0)))&(1<<side))!=0:continue
   var front=Vector3.FORWARD if absf(forward.z)>=absf(forward.x) else Vector3.LEFT
   if front.dot(forward)<0:front=-front
   var point=tower.pos+front*3+lateral*(-4 if side==0 else 4)
   if not safe(records,point):continue
   var occupied=false
   for r in records:
    if owned(r) and r.get("kind","")=="wall" and r.pos.distance_to(point)<2:occupied=true;break
   if occupied:continue
   var builder={};var best=INF
   for w in workers:
    if claimed.has(w.id) or pending.has(w.id) or w.get("cargo_milli",0)>0 or w.get("state","") not in ["idle","gather"] or w.get("gather_type","")=="food" or w.get("path_status","") in ["NO_PATH","LIMIT_REACHED","NO_WORK"]:continue
    if not safe(records,w.pos):continue
    var score=w.pos.distance_to(point)+(0 if w.state=="idle" else 8)
    if score<best or (score==best and (builder.is_empty() or w.id<builder.id)):builder=w;best=score
   if not builder.is_empty():return {"tower":tower.id,"side":side,"builder":builder.id,"position":point}
 return {}
