extends RefCounted
# Observation-only policy: callers supply their faction publication, never
# authority enemies. A hit is required; mere proximity cannot seize a worker.
const Rules=preload("res://scripts/rules.gd")
const SAFE_TICKS=100
const MANUAL_GRACE_TICKS=200
const MAX_REFUGE_DISTANCE=18.0
static func threats(records: Dictionary,team: int,point: Vector3) -> Array:
	var result=[]
	for record in records.values():
		if record.get("remembered",false) or not record.get("alive",false) or record.get("team",-1)!=1-team: continue
		if record.get("category","")!="unit" and not (record.get("kind","")=="tower" and record.get("built",false)): continue
		if Rules.DAMAGE.get(record.get("kind",""),0)<=0: continue
		var radius=maxf(6.0,Rules.RANGE.get(record.kind,1.0)+1.5)
		if point.distance_to(record.pos)<=radius: result.append(record)
	return result
static func refuges(records: Dictionary,worker: Dictionary) -> Array:
	var result=[]
	for record in records.values():
		if not record.get("owned",false) or not record.get("alive",false) or not record.get("built",false) or record.get("kind","") not in ["town_center","tower"]: continue
		if worker.pos.distance_to(record.pos)>MAX_REFUGE_DISTANCE or not threats(records,worker.team,record.pos).is_empty(): continue
		result.append(record)
	result.sort_custom(func(a,b): return worker.pos.distance_squared_to(a.pos)<worker.pos.distance_squared_to(b.pos) or (worker.pos.distance_squared_to(a.pos)==worker.pos.distance_squared_to(b.pos) and a.id<b.id))
	return result
