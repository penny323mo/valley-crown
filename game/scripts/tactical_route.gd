extends RefCounted
const Rules=preload("res://scripts/rules.gd")
const LIMIT=5
static func valid_points(points)->bool:
 if not points is Array or points.is_empty() or points.size()>LIMIT:return false
 var previous=Vector3.INF
 for point in points:
  if not point is Vector3 or not point.is_finite() or absf(point.x)>=Rules.MAP_WORLD_LIMIT or absf(point.z)>=Rules.MAP_WORLD_LIMIT or point.y!=0:return false
  if previous!=Vector3.INF and previous.distance_to(point)<1:return false
  previous=point
 return true
static func clear(ent):
 for key in ["tactical_points","tactical_index","tactical_advance"]:ent.erase(key)
static func valid_entity(ent)->bool:
 var count=0
 for key in ["tactical_points","tactical_index","tactical_advance"]:
  if ent.has(key):count+=1
 if count==0:return true
 if count!=3 or not valid_points(ent.tactical_points):return false
 if not ent.get("alive",false) or ent.get("team",-1) not in [0,1]:return false
 if not ent.tactical_index is int or ent.tactical_index<0 or ent.tactical_index>=ent.tactical_points.size() or not ent.tactical_advance is bool:return false
 var expected="ADVANCE" if ent.tactical_advance and ent.tactical_index==ent.tactical_points.size()-1 else "MOVE"
 return ent.get("mode","")==expected and ent.get("category","")=="unit" and ent.get("kind","") in Rules.UNIT_KINDS and ent.kind!="villager" and ent.tactical_index is int and ent.tactical_index>=0 and ent.tactical_index<ent.tactical_points.size() and ent.tactical_advance is bool and ent.get("state","")=="move" and ent.get("mode","") in ["MOVE","ADVANCE"]
