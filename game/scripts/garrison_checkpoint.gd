extends RefCounted
const Rules=preload("res://scripts/rules.gd")
# Optional shelter intent/state. No migration, teleport or slot changes.
static func validate(data)->bool:
 if not data is Dictionary or not data.get("entities",null) is Array:return false
 var economy=data.get("modules",{}).get("economy",{})
 if not economy is Dictionary or not economy.get("_worker_farms",null) is Dictionary or not economy.get("_farms",null) is Dictionary:return false
 var by_id={};var counts={}
 for entity in data.entities:
  if not entity is Dictionary or not entity.get("id",null) is int or entity.id<0 or by_id.has(entity.id):return false
  by_id[entity.id]=entity
 for entity in data.entities:
  var pending=entity.has("garrison_pending");var inside=entity.has("garrison_host")
  if not pending and not inside:continue
  if pending and inside:return false
  if entity.get("alive",null)!=true or not entity.get("alive",null) is bool or entity.get("kind","")!="villager" or not entity.get("team",null) is int or entity.team not in [0,1]:return false
  var host_id=entity.garrison_host if inside else entity.garrison_pending
  if not host_id is int or host_id<0:return false
  var host=by_id.get(host_id,{})
  if host.get("kind","")!="town_center" or not host.get("alive",null) is bool or not host.alive or not host.get("built",null) is bool or not host.built or host.get("team",-1)!=entity.team:return false
  counts[host_id]=counts.get(host_id,0)+1
  if counts[host_id]>5:return false
  if pending:
   if not entity.get("pos",null) is Vector3 or not entity.pos.is_finite() or not entity.get("dest",null) is Vector3 or not entity.dest.is_finite() or not host.get("pos",null) is Vector3 or not host.pos.is_finite():return false
   var half=Rules.FOOTPRINT.town_center/2.0
   var dx=maxf(0,absf(entity.dest.x-host.pos.x)-half)
   var dz=maxf(0,absf(entity.dest.z-host.pos.z)-half)
   if sqrt(dx*dx+dz*dz)>1.1:return false
   if entity.get("mode","")!=("MOVE" if entity.get("state","")=="move" else "STOP"):return false
   if entity.get("state","") not in ["move","idle"] or entity.get("path_status","") in ["NO_PATH","LIMIT_REACHED","NO_WORK"]:return false
  else:
   if not entity.get("pos",null) is Vector3 or not host.get("pos",null) is Vector3 or not entity.pos.is_finite() or not host.pos.is_finite():return false
   var half=Rules.FOOTPRINT.town_center/2.0
   var dx=maxf(0,absf(entity.pos.x-host.pos.x)-half)
   var dz=maxf(0,absf(entity.pos.z-host.pos.z)-half)
   if sqrt(dx*dx+dz*dz)>1.1:return false
   var game=data.get("game",{})
   if not game is Dictionary:return false
   if entity.id in game.get("selected",[]) or entity.id in game.get("path_requests",[]) or game.get("worker_evacuations",{}).has(entity.id):return false
   var views=data.get("faction_views",[])
   if not views is Array:return false
   for view in views:
    if not view is Dictionary or not view.get("current",{}) is Dictionary:return false
    if view.get("current",{}).has(entity.id):return false
   if entity.get("state","")!="idle" or entity.get("mode","")!="STOP" or not entity.get("target",null) is int or entity.target!= -1:return false
   if not entity.get("path",null) is PackedVector3Array or not entity.path.is_empty() or not entity.get("path_pending",null) is bool or entity.path_pending:return false
   for key in entity:
    if key=="construction_return" or str(key).begins_with("escort_") or str(key).begins_with("tactical_"):return false
   if economy._worker_farms.has(entity.id):return false
   for farm in economy._farms.values():
    if not farm is Dictionary or farm.get("worker_id",-1)==entity.id:return false
 return true
