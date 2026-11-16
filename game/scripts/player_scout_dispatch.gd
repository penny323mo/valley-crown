extends RefCounted
const Rules=preload("res://scripts/rules.gd")
const Frontier=preload("res://scripts/scout_frontier.gd")
const Threats=preload("res://scripts/idle_gather_dispatch.gd")
const MAX_DISTANCE=18.0
static func plan(records: Dictionary,pending: Array,explored: PackedByteArray)->Dictionary:
 if explored.size()!=Rules.MAP_SIZE*Rules.MAP_SIZE:return {}
 var busy={};var scouts=[];var home=Vector3.ZERO;var threats={}
 for id in records:
  var e=records[id]
  if e.get("alive",false) and not e.get("remembered",true) and e.get("team",-1)==1 and (e.get("category","")=="unit" or (e.get("kind","")=="tower" and e.get("built",false))):threats[id]=e
 for c in pending:
  if c.get("team",-1)==0:
   for id in c.get("ids",[]):busy[id]=true
 for r in records.values():
  if not r.get("owned",false) or not r.get("alive",false) or r.get("remembered",true) or r.get("team",-1)!=0:continue
  if r.get("kind","")=="town_center":home=r.pos
  if r.get("kind","")!="scout" or r.get("state","")!="idle" or r.get("path_pending",false) or not r.get("path",[]).is_empty() or busy.has(r.id):continue
  if r.get("path_status","") in ["NO_PATH","LIMIT_REACHED","NO_WORK"] or Threats.threatened(r.pos,threats):continue
  scouts.append(r)
 scouts.sort_custom(func(a,b):return a.id<b.id)
 if scouts.is_empty():return {}
 # Public known-threat mask computed once, not rescanned per candidate/scout.
 var blocked={}
 for e in threats.values():
  var ex=int(floor(e.pos.x+Rules.MAP_HALF));var ey=int(floor(e.pos.z+Rules.MAP_HALF))
  for y in range(maxi(Rules.MAP_BORDER,ey-9),mini(Rules.MAP_LAST_PLAYABLE,ey+9)+1):
   for x in range(maxi(Rules.MAP_BORDER,ex-9),mini(Rules.MAP_LAST_PLAYABLE,ex+9)+1):
    if Vector3(x-Rules.MAP_HALF+.5,0,y-Rules.MAP_HALF+.5).distance_squared_to(e.pos)<=81:blocked[y*Rules.MAP_SIZE+x]=true
 var result={};var best=INF
 for s in scouts:
  var cx=int(floor(s.pos.x+Rules.MAP_HALF));var cy=int(floor(s.pos.z+Rules.MAP_HALF))
  for y in range(maxi(Rules.MAP_BORDER,cy-18),mini(Rules.MAP_LAST_PLAYABLE,cy+18)+1):
   for x in range(maxi(Rules.MAP_BORDER,cx-18),mini(Rules.MAP_LAST_PLAYABLE,cx+18)+1):
    var index=y*Rules.MAP_SIZE+x
    if explored[index]!=0 or blocked.has(index):continue
    var p=Vector3(x-Rules.MAP_HALF+.5,0,y-Rules.MAP_HALF+.5)
    if s.pos.distance_squared_to(p)>MAX_DISTANCE*MAX_DISTANCE:continue
    var score=Frontier.score(s.pos,p,home,Rules.SIGHT.scout)
    if score<best:
     best=score;result={"ids":[s.id],"target":-1,"position":p,"scout_dispatch":true,"source_work_epoch":s.get("work_epoch",0),"scout_cell":index}
  # Choose the first eligible scout with a frontier; no per-frame global army optimization.
  if not result.is_empty():break
 return result
