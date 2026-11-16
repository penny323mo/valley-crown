extends RefCounted
## Local cavalry harassment from sanitized current observations only.
## No extra soldiers, economy privilege, hidden positions or persistent state.
const Rules=preload("res://scripts/rules.gd")
const KEEP_BUFFER=12.0
const GUARD_BUFFER=6.0
static func choose(attacker:Dictionary,records:Array,keep:Dictionary)->Dictionary:
 if attacker.get("category","")!="unit" or attacker.get("remembered",true) or not attacker.get("owned",false) or not attacker.get("alive",false) or attacker.get("team",-1)!=1 or attacker.get("kind","")!="cavalry":return {}
 # Never detach from a keep assault already in striking range.
 if not keep.is_empty() and attacker.pos.distance_to(keep.pos)<=keep.get("radius",2.0)+Rules.RANGE.cavalry:return {}
 var best={};var distance=INF
 for worker in records:
  if worker.get("category","")!="unit" or worker.get("owned",false) or not worker.get("alive",false) or worker.get("remembered",true) or worker.get("team",-1)!=0 or worker.get("kind","")!="villager":continue
  var d=attacker.pos.distance_to(worker.pos)
  if d>Rules.SIGHT.cavalry:continue
  if not keep.is_empty() and worker.pos.distance_to(keep.pos)<KEEP_BUFFER:continue
  var protected=false
  for guard in records:
   if guard.get("owned",false) or not guard.get("alive",false) or guard.get("remembered",true) or guard.get("team",-1)!=0:continue
   if guard.get("category","")=="building" and guard.get("kind","")=="tower" and guard.get("built",false):
    if guard.pos.distance_to(worker.pos)<Rules.RANGE.tower+guard.get("radius",1.0)+2:protected=true;break
   if guard.get("category","")=="unit" and guard.get("kind","") in ["spearman","archer","cavalry","siege"]:
    if guard.pos.distance_to(worker.pos)<=GUARD_BUFFER or guard.pos.distance_to(attacker.pos)<=Rules.RANGE.cavalry+guard.get("radius",0.4):protected=true;break
  if protected:continue
  if d<distance or (is_equal_approx(d,distance) and (best.is_empty() or worker.id<best.id)):
   best=worker;distance=d
 return best
