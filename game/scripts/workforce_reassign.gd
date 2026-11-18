extends RefCounted
## Explicit selected-worker reassignment; no economic or world authority here.
const Dispatch=preload("res://scripts/idle_gather_dispatch.gd")
const Rules=preload("res://scripts/rules.gd")
static func orders(records:Dictionary,selected:Array,commands:Array,resource:String,farm_workers:Dictionary={})->Array:
 if resource not in ["food","wood","stone","iron"] or selected.size()>Rules.POP_LIMIT:return []
 var pending={}
 for c in commands:
  if not c is Dictionary or c.get("team",-1)!=0:continue
  if c.get("type","")=="build":pending[c.get("builder",-1)]=true
  for id in c.get("ids",[]):pending[id]=true
 var workers=[];var seen={};var nodes=[]
 for id in selected:
  if typeof(id)!=TYPE_INT or seen.has(id) or pending.has(id):continue
  seen[id]=true
  var w=records.get(id,{})
  if w.get("id",-1)!=id or not w.get("owned",false) or not w.get("alive",false) or w.get("remembered",false) or w.get("team",-1)!=0 or w.get("kind","")!="villager" or w.get("state","") not in ["gather","deliver"]:continue
  if w.get("gather_type","") not in ["food","wood","stone","iron"] or w.gather_type==resource or typeof(w.get("work_epoch",null))!=TYPE_INT or Dispatch.threatened(w.pos,records):continue
  workers.append(w)
 nodes=Dispatch.candidate_nodes(records,commands,resource,farm_workers)
 var result=[];var load={}
 for index in mini(3,workers.size()):
  var best={};var target={};var score=INF
  for w in workers:
   for n in nodes:
    var cost=w.pos.distance_to(n.pos)+2.0*load.get(n.id,0)
    if cost<score or (cost==score and (best.is_empty() or w.id<best.id or (w.id==best.id and n.id<target.id))):score=cost;best=w;target=n
  if best.is_empty():break
  result.append({"ids":[best.id],"target":target.id,"position":target.pos,"work_reassign":resource,"source_work_epoch":best.work_epoch,"source_resource":best.gather_type})
  if target.get("kind","")=="farm":
   result[-1].farm_gather=true;nodes.erase(target)
  workers.erase(best);load[target.id]=load.get(target.id,0)+1
 return result
