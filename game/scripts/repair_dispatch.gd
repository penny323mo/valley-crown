extends RefCounted
const IdleWorkers=preload("res://scripts/idle_worker_selection.gd")
static func plan(records: Dictionary,commands: Array,building: int,tick: int) -> Dictionary:
	var result={"worker":-1,"reason":"建築已失效"}
	var b=records.get(building,{})
	if not b.get("owned",false) or not b.get("alive",false) or b.get("remembered",false) or b.get("team",-1)!=0 or b.get("category","")!="building" or not b.get("built",false): return result
	if b.get("hp",0)>=b.get("max_hp",0): result.reason="建築毋須維修"; return result
	if tick-b.get("last_damage_tick",tick)<100: result.reason="受襲後 5 秒才可維修"; return result
	for r in records.values():
		if r.get("owned",false) and r.get("alive",false) and r.get("kind","")=="villager" and r.get("state","")=="repair" and r.get("target",-1)==building:
			result.reason="已有村民維修"; return result
	for c in commands:
		if c.get("team",-1)==0 and c.get("type","")=="order" and c.get("target",-1)==building:
			result.reason="已有指令前往此建築"; return result
	var distance=INF
	for id in IdleWorkers.eligible(records,commands):
		var w=records[id]
		if w.get("cargo_milli",0)>0 or w.get("carry",0.0)>0: continue
		var d=w.pos.distance_squared_to(b.pos)
		if d<distance: distance=d; result.worker=id
	result.reason="派閒置村民維修" if result.worker>=0 else "沒有空手閒置村民"
	return result
