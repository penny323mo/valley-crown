extends RefCounted
const Construction=preload("res://scripts/construction_dispatch.gd")
const Gather=preload("res://scripts/idle_gather_dispatch.gd")
static func orders(records: Dictionary,pending: Array)->Array:
 var targets=[]
 for b in records.values():
  if not b.get("owned",false) or not b.get("alive",false) or b.get("remembered",true) or b.get("team",-1)!=0 or b.get("category","")!="building" or b.get("built",true):continue
  if Gather.threatened(b.pos,records):continue
  targets.append(b)
 targets.sort_custom(func(a,b):
  var ap=0 if a.kind=="house" else 1
  var bp=0 if b.kind=="house" else 1
  if ap!=bp:return ap<bp
  var ar=-float(a.get("progress",0));var br=-float(b.get("progress",0))
  return a.id<b.id if ar==br else ar<br)
 var commands=pending.duplicate(true);var result=[]
 var safe_records=records.duplicate()
 for id in records:
  var w=records[id]
  if w.get("kind","")=="villager" and w.get("state","")=="idle" and Gather.threatened(w.pos,records):safe_records.erase(id)
 for b in targets:
  var p=Construction.plan(safe_records,commands,b.id)
  if p.worker<0:continue
  var order={"ids":[p.worker],"target":b.id,"construction_dispatch":true,"construction_batch":true,"source_work_epoch":records[p.worker].get("work_epoch",0)}
  result.append(order)
  var future=order.duplicate(true);future.type="order";future.team=0;commands.append(future)
  if result.size()>=3:break
 return result
