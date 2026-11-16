extends RefCounted
## Observation-only remote supply infrastructure planning; ordinary build owns cost/routes.
const OFFSETS=[Vector3(4,0,0),Vector3(-4,0,0),Vector3(0,0,4),Vector3(0,0,-4),Vector3(3,0,3),Vector3(-3,0,3),Vector3(3,0,-3),Vector3(-3,0,-3)]
static func plan(records:Array,claimed:Dictionary,commands:Array,wood_milli:int)->Dictionary:
 if wood_milli<160000:return {}
 var nodes={};var drops=[];var workers=[];var pending={};var foods=0
 for c in commands:
  if c.get("team",-1)!=1:continue
  if c.get("type","")=="build":
   if c.get("kind","")=="storehouse":return {}
   pending[c.get("builder",-1)]=true
  for id in c.get("ids",[]):pending[id]=true
 for r in records:
  if not r.get("alive",false) or r.get("remembered",false):continue
  if r.get("category","")=="resource" and r.get("hp",0)>=100:nodes[r.id]=r
  if not r.get("owned",false) or r.get("team",-1)!=1:continue
  if r.get("kind","") in ["town_center","storehouse"]:drops.append(r)
  if r.get("kind","")=="villager":
   workers.append(r)
   if r.get("state","") in ["gather","deliver"] and r.get("gather_type","")=="food":foods+=1
 if workers.size()<5 or foods<2:return {}
 var clusters=[]
 for node in nodes.values():
  var nearby=false
  for drop in drops:
   if drop.pos.distance_to(node.pos)<12:nearby=true;break
  if nearby:continue
  var assigned=0
  for w in workers:
   if not claimed.has(w.id) and not pending.has(w.id) and w.get("state","")=="gather" and nodes.has(w.get("target",-1)) and nodes[w.target].pos.distance_to(node.pos)<=5:assigned+=1
  if assigned<2:continue
  if threatened(records,node.pos):continue
  clusters.append({"node":node,"assigned":assigned})
 clusters.sort_custom(func(a,b):return a.assigned>b.assigned or (a.assigned==b.assigned and a.node.id<b.node.id))
 if clusters.is_empty():return {}
 var center=clusters[0].node;var builder={};var score=INF
 for w in workers:
  if claimed.has(w.id) or pending.has(w.id) or w.get("cargo_milli",0)>0 or w.get("state","") not in ["idle","gather"] or w.get("gather_type","")=="food" or w.get("path_status","") in ["NO_PATH","LIMIT_REACHED","NO_WORK"]:continue
  var cost=w.pos.distance_to(center.pos)+(0 if w.state=="idle" else 8)
  if cost<score or (cost==score and (builder.is_empty() or w.id<builder.id)):builder=w;score=cost
 if builder.is_empty():return {}
 var plots=[]
 for offset in OFFSETS:plots.append(center.pos+offset)
 return {"builder":builder.id,"resource":center.id,"plots":plots,"assigned":clusters[0].assigned}

static func threatened(records:Array,point:Vector3)->bool:
 for e in records:
  if e.get("alive",false) and not e.get("remembered",false) and e.get("team",-1)==0 and (e.get("category","")=="unit" or (e.get("kind","")=="tower" and e.get("built",false))) and e.pos.distance_to(point)<12:return true
 return false
