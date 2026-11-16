extends RefCounted
## Local contact breach only. Sanitized faction observations, no authority grid,
## route search, failed-route retry or hidden obstacle discovery.
const Rules=preload("res://scripts/rules.gd")
const KINDS=["spearman","cavalry","siege"]

static func edge_distance(point:Vector3,building:Dictionary)->float:
 var half=float(Rules.FOOTPRINT.get(building.get("kind",""),2))*0.5
 return Vector2(maxf(0,absf(point.x-building.pos.x)-half),maxf(0,absf(point.z-building.pos.z)-half)).length()

static func blocks_forward(start:Vector3,goal:Vector3,wall:Vector3)->bool:
 # Closed segment against the real 2x2 AABB; side/rear walls are not targets.
 var delta=Vector2(goal.x-start.x,goal.z-start.z)
 if delta.length_squared()<0.0001:return false
 var enter=0.0;var leave=1.0
 for axis in 2:
  var p=start.x if axis==0 else start.z
  var d=delta[axis];var center=wall.x if axis==0 else wall.z
  if absf(d)<0.00001:
   if p<center-1.0 or p>center+1.0:return false
  else:
   var a=(center-1.0-p)/d;var b=(center+1.0-p)/d
   enter=maxf(enter,minf(a,b));leave=minf(leave,maxf(a,b))
   if enter>leave:return false
 return leave>0.00001 and enter<1.0

static func choose(attacker:Dictionary,records:Array,keep:Dictionary)->Dictionary:
 if not attacker.get("owned",false) or not attacker.get("alive",false) or attacker.get("remembered",true) or attacker.get("team",-1)!=1 or attacker.get("category","")!="unit" or attacker.get("kind","") not in KINDS:return {}
 if keep.is_empty() or not keep.get("alive",false) or keep.get("team",-1)!=0 or keep.get("kind","")!="town_center" or keep.get("category","")!="building":return {}
 if not keep.get("pos",Vector3.INF).is_finite() or not attacker.get("pos",Vector3.INF).is_finite():return {}
 var reach=float(Rules.RANGE[attacker.kind])
 if not keep.get("remembered",true) and edge_distance(attacker.pos,keep)<=reach:return {}
 var best={};var score=[]
 for wall in records:
  if wall.get("owned",false) or not wall.get("alive",false) or wall.get("remembered",true) or wall.get("team",-1)!=0 or wall.get("category","")!="building" or wall.get("kind","")!="wall":continue
  if not wall.get("pos",Vector3.INF).is_finite():continue
  var distance=edge_distance(attacker.pos,wall)
  if distance>reach or not blocks_forward(attacker.pos,keep.pos,wall.pos):continue
  var candidate=[0 if attacker.get("state","")=="attack" and attacker.get("target",-1)==wall.id else 1,distance,wall.id]
  var before=score.is_empty()
  if not before:
   for i in candidate.size():
    if candidate[i]!=score[i]:before=candidate[i]<score[i];break
  if before:best=wall;score=candidate
 return best
