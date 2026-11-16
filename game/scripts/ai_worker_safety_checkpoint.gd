extends RefCounted
# Optional AI evacuation state; no version migration or serialized fixture.
const FIELDS=["resource","origin","epoch","safe_since_tick","hit_tick"]
const RESOURCES=["pine","oak","berry","stone","iron"]
const RESOURCE_TYPES={"pine":"wood","oak":"wood","berry":"food","stone":"stone","iron":"iron"}
static func validate(data)->bool:
 var by_id={}
 for e in data.entities:by_id[e.id]=e
 for e in data.entities:
  if not e.has("ai_evacuation"):continue
  if data.game.get("skirmish_mode","standard") in ["survival","expedition","escort"]:return false
  var memo=e.ai_evacuation
  if not memo is Dictionary or memo.size()!=FIELDS.size():return false
  for key in FIELDS:
   if not memo.has(key):return false
  if e.get("alive",null)!=true or not e.get("alive",null) is bool or not e.get("team",null) is int or e.team!=1 or e.get("kind","")!="villager":return false
  if e.get("mode","")!="MOVE" or e.get("state","") not in ["move","idle"]:return false
  if e.get("path_status","") in ["NO_PATH","LIMIT_REACHED","NO_WORK"]:return false
  for key in e:
   if key in ["garrison_host","garrison_pending","construction_return"] or str(key).begins_with("escort_") or str(key).begins_with("tactical_"):return false
  for key in ["resource","epoch","safe_since_tick","hit_tick"]:
   if not memo[key] is int:return false
  if memo.resource<0 or memo.epoch<0 or not e.get("work_epoch",null) is int or memo.epoch!=e.work_epoch:return false
  if not memo.origin is Vector3 or not memo.origin.is_finite():return false
  var resource=by_id.get(memo.resource,{})
  if resource.get("category","")!="resource" or resource.get("kind","") not in RESOURCES or not resource.get("pos",null) is Vector3 or not resource.pos.is_finite() or memo.origin!=resource.pos:return false
  if not e.get("gather_type",null) is String or e.gather_type!=RESOURCE_TYPES[resource.kind]:return false
  if not e.get("resource_target",null) is int or e.resource_target!=memo.resource:return false
  var tick=data.game.tick_count
  if memo.hit_tick<0 or memo.hit_tick>tick or not e.get("last_damage_tick",null) is int or e.last_damage_tick<memo.hit_tick or e.last_damage_tick>tick:return false
  if memo.safe_since_tick< -1 or memo.safe_since_tick>tick:return false
  if memo.safe_since_tick>=0 and (memo.safe_since_tick<e.last_damage_tick or e.state!="idle"):return false
  var economy=data.modules.economy
  if economy._worker_farms.has(e.id):return false
  for farm in economy._farms.values():
   if not farm is Dictionary or farm.get("worker_id",-1)==e.id:return false
 return true
