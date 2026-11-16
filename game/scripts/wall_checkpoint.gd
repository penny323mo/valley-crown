extends RefCounted
## Optional wall entities use the existing building/receipt schema. There are no
## free preplaced walls in supported games, so every saved wall has paid origin.
const FORBIDDEN=["rally_point","rally_mode","rally_target","repeat_kind","repeat_generation","garrison_host","garrison_pending","supply_station","supply_receipt_id","supply_completed_tick","tactical_points","escort_target","construction_return","ai_evacuation"]
static func exact(d,names):
 if not d is Dictionary or d.size()!=names.size():return false
 for name in names:
  if not d.has(name):return false
 return true
static func validate(data):
 var uses={}
 for e in data.entities:
  var rid=e.get("cost_receipt_id","")
  if rid is String and not rid.is_empty():uses[rid]=uses.get(rid,0)+1
  for order in e.get("queue",[]):
   if not order is Dictionary:return false
   rid=order.get("receipt_id","")
   if rid is String and not rid.is_empty():uses[rid]=uses.get(rid,0)+1
 var economy=data.modules.economy
 for e in data.entities:
  if e.get("kind","")!="wall":continue
  for field in FORBIDDEN:
   if e.has(field):return false
  if e.get("category","")!="building" or not e.get("team",null) is int or e.team not in [0,1] or not e.get("alive",null) is bool or not e.get("built",null) is bool:return false
  if not e.get("pos",null) is Vector3 or not e.pos.is_finite() or e.pos.y!=0 or e.pos.x!=floorf(e.pos.x) or e.pos.z!=floorf(e.pos.z):return false
  if typeof(e.get("radius",null)) not in [TYPE_INT,TYPE_FLOAT] or e.radius!=1:return false
  if not e.get("queue",null) is Array or not e.queue.is_empty():return false
  if not e.get("build_ticks",null) is int or e.build_ticks<0 or e.build_ticks>200:return false
  if typeof(e.get("progress",null)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(e.progress) or not is_equal_approx(float(e.progress),float(e.build_ticks)/200):return false
  if not e.get("construction_hcap",null) is int or e.construction_hcap!=25+floori(225.0*e.build_ticks/200):return false
  if typeof(e.get("hp",null)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(e.hp)) or e.hp>e.construction_hcap or e.get("max_hp",0)!=250:return false
  if e.alive and e.hp<=0:return false
  if e.built!=(e.build_ticks==200):return false
  if not e.get("cost_receipt_id",null) is String or e.cost_receipt_id.is_empty() or uses.get(e.cost_receipt_id,0)!=1:return false
  var r=economy._receipts.get(e.cost_receipt_id,{})
  if not exact(r,["team","cost_units","paid_milli","refund_policy","purpose","state"]):return false
  if not r.team is int or r.team!=e.team or r.purpose!="purchase" or r.refund_policy!="started":return false
  if not exact(r.cost_units,["wood"]) or not r.cost_units.wood is int or r.cost_units.wood!=30:return false
  if not exact(r.paid_milli,["food","wood","stone","iron"]):return false
  for resource in r.paid_milli:
   if not r.paid_milli[resource] is int or r.paid_milli[resource]!=(30000 if resource=="wood" else 0):return false
  if e.built:
   if r.state!="fulfilled":return false # Completed then destroyed retains fulfilled origin.
  elif e.alive:
   if r.state!="open":return false
  elif r.state not in ["cancelled","destroyed"]:return false
  if economy.get("_workers",{}).has(e.id) or economy.get("_farms",{}).has(e.id):return false
 return true
