extends RefCounted
## Advisory decisions from current faction observations only. Normal orders own movement/combat.
const GUARDS=["scout","spearman","archer","cavalry"]
const PROTECTED=["villager","siege"]
const THREAT_RADIUS=3.0
const LEASH_RADIUS=5.0
const FOLLOW_DISTANCE=2.0
static func _current(record,id,team,owned):
 return record is Dictionary and record.get("id",-1)==id and record.get("alive",false) and not record.get("remembered",false) and record.get("team",-1)==team and (not owned or record.get("owned",false)) and record.get("pos") is Vector3 and record.pos.is_finite()
static func decide(records: Dictionary,guard_id: int,protected_id: int,team: int,explicit_pending: bool=false) -> Dictionary:
 var cancel={"action":"cancel"}
 if team not in [0,1] or explicit_pending or guard_id==protected_id:return cancel
 var guard=records.get(guard_id,{})
 var ally=records.get(protected_id,{})
 if not _current(guard,guard_id,team,true) or guard.get("category","")!="unit" or guard.get("kind","") not in GUARDS:return cancel
 if not _current(ally,protected_id,team,true) or ally.get("category","")!="unit" or ally.get("kind","") not in PROTECTED:return cancel
 # Never chase while already outside the moving ally's leash.
 var separation=guard.pos.distance_to(ally.pos)
 if separation<=LEASH_RADIUS:
  var chosen=-1
  var distance=INF
  for id in records:
   var candidate=records[id]
   if not _current(candidate,id,1-team,false):continue
   if candidate.get("category","")!="unit" or candidate.get("kind","") not in GUARDS+["siege"]:continue
   if candidate.pos.distance_to(ally.pos)>THREAT_RADIUS or candidate.pos.distance_to(guard.pos)>LEASH_RADIUS:continue
   var d=guard.pos.distance_squared_to(candidate.pos)
   if d<distance or (d==distance and (chosen<0 or id<chosen)):chosen=id;distance=d
  if chosen>=0:return {"action":"intercept","target":chosen}
 if separation>FOLLOW_DISTANCE:return {"action":"follow","target":protected_id,"observed_position":ally.pos}
 return {"action":"hold","target":protected_id}
