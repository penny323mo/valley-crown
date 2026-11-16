extends RefCounted
const Repair=preload("res://scripts/repair_dispatch.gd")
const Gather=preload("res://scripts/idle_gather_dispatch.gd")
static func orders(records: Dictionary,pending: Array,tick: int)->Array:
 var targets=[]
 for b in records.values():
  if not b.get("owned",false) or not b.get("alive",false) or b.get("remembered",true) or b.get("team",-1)!=0 or b.get("category","")!="building" or not b.get("built",false):continue
  if b.get("hp",0)<=0 or b.get("hp",0)>=b.get("max_hp",0) or Gather.threatened(b.pos,records):continue
  targets.append(b)
 targets.sort_custom(func(a,b):
  var ap=0 if a.kind=="town_center" else 1 if a.kind=="tower" else 2
  var bp=0 if b.kind=="town_center" else 1 if b.kind=="tower" else 2
  if ap!=bp:return ap<bp
  var ar=float(a.hp)/a.max_hp;var br=float(b.hp)/b.max_hp
  return a.id<b.id if ar==br else ar<br)
 var commands=pending.duplicate(true);var result=[]
 var safe_records=records.duplicate()
 for id in records:
  var w=records[id]
  if w.get("kind","")=="villager" and w.get("state","")=="idle" and Gather.threatened(w.pos,records):safe_records.erase(id)
 for b in targets:
  var p=Repair.plan(safe_records,commands,b.id,tick)
  if p.worker<0:continue
  var order={"ids":[p.worker],"target":b.id,"repair_dispatch":true,"repair_batch":true,"source_work_epoch":records[p.worker].get("work_epoch",0)}
  result.append(order)
  var future=order.duplicate(true);future.type="order";future.team=0;commands.append(future)
  if result.size()>=3:break
 return result
