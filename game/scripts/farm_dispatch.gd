extends RefCounted
const Idle=preload("res://scripts/idle_worker_selection.gd")
static func plan(records: Dictionary,commands: Array,id: int,occupant: int) -> Dictionary:
	var result={"worker":-1,"reason":"農田已失效"}
	var farm=records.get(id,{})
	if not farm.get("owned",false) or not farm.get("alive",false) or farm.get("remembered",false) or farm.get("team",-1)!=0 or farm.get("kind","")!="farm" or not farm.get("built",false):return result
	if occupant>=0:result.reason="已有村民耕作";return result
	for c in commands:
		if c.get("team",-1)==0 and c.get("type","")=="order" and c.get("target",-1)==id:result.reason="已有指令前往農田";return result
	var distance=INF
	for worker_id in Idle.eligible(records,commands):
		var worker=records[worker_id]
		if worker.get("cargo_milli",0)>0 or worker.get("carry",0.0)>0:continue
		var d=worker.pos.distance_squared_to(farm.pos)
		if d<distance or (d==distance and (result.worker<0 or worker_id<result.worker)):distance=d;result.worker=worker_id
	result.reason="派閒置村民耕作" if result.worker>=0 else "沒有空手閒置村民"
	return result
