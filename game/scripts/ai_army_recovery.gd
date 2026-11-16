extends RefCounted
const Rest=preload("res://scripts/rest_recovery.gd")
## No private enemy truth or persistent state. Critically wounded troops return
## physically; once near home, they stay in reserve until eighty percent health.
static func base_for(unit: Dictionary,records: Array)->Dictionary:
 if not unit.get("owned",false) or not unit.get("alive",false) or unit.get("remembered",true) or unit.get("team",-1)!=1 or unit.get("kind","") not in Rest.KINDS:return {}
 var hp=int(unit.get("hp",0));var maximum=int(unit.get("max_hp",0))
 if maximum<=0 or hp<=0 or hp*5>=maximum*4:return {}
 var best={};var distance=INF
 for b in records:
  if not b.get("owned",false) or not b.get("alive",false) or b.get("remembered",true) or b.get("team",-1)!=1 or b.get("kind","")!="town_center" or not b.get("built",false):continue
  var d=unit.pos.distance_squared_to(b.pos)
  if hp*100>maximum*35 and d>Rest.RADIUS*Rest.RADIUS:continue
  var danger=false
  for e in records:
   if not e.get("alive",false) or e.get("remembered",true) or e.get("team",-1)!=0:continue
   if e.get("category","")!="unit" and not(e.get("kind","")=="tower" and e.get("built",false)):continue
   if e.pos.distance_to(b.pos)<=Rest.THREAT_RADIUS+5.0 or (d<=Rest.RADIUS*Rest.RADIUS and e.pos.distance_to(unit.pos)<=Rest.THREAT_RADIUS):danger=true;break
  if danger:continue
  if d<distance or (d==distance and (best.is_empty() or b.id<best.id)):best=b;distance=d
 return best
