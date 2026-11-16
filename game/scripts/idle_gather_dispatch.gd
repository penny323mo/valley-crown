extends RefCounted
const Idle=preload("res://scripts/idle_worker_selection.gd")
const TYPES={"pine":"wood","oak":"wood","berry":"food","stone":"stone","iron":"iron"}
static func threatened(point:Vector3,records:Dictionary)->bool:
	for e in records.values():
		if not e.get("alive",false) or e.get("remembered",false) or e.get("team",-1)!=1:continue
		if e.get("category","")!="unit" and not (e.get("kind","")=="tower" and e.get("built",false)):continue
		if point.distance_to(e.pos)<=9.0:return true
	return false
static func orders(records:Dictionary,commands:Array,resource:String)->Array:
	if resource not in ["food","wood","stone","iron"]:return []
	var nodes=[]
	for r in records.values():
		if r.get("category","")=="resource" and r.get("alive",false) and not r.get("remembered",true) and r.get("hp",0)>0 and TYPES.get(r.get("kind",""),"")==resource and not threatened(r.pos,records):nodes.append(r)
	# Advisory load comes only from current owned work and queued player orders.
	# Count each worker once; a pending order supersedes its observed old target.
	var assignments={}
	for w in records.values():
		if w.get("owned",false) and w.get("alive",false) and not w.get("remembered",false) and w.get("team",-1)==0 and w.get("kind","")=="villager" and w.get("state","")=="gather":
			assignments[w.id]=w.get("target",-1)
	for c in commands:
		if not c is Dictionary or c.get("team",-1)!=0 or c.get("type","") not in ["order","stop","defend","advance","patrol"]:continue
		for id in c.get("ids",[]):
			var w=records.get(id,{})
			if not w.get("owned",false) or not w.get("alive",false) or w.get("remembered",false) or w.get("team",-1)!=0 or w.get("kind","")!="villager":continue
			assignments[id]=c.get("target",-1) if c.get("type","")=="order" else -1
	var loads={}
	for target in assignments.values():loads[target]=loads.get(target,0)+1
	var workers=[]
	for id in Idle.eligible(records,commands):
		var w=records[id]
		if w.get("cargo_milli",0)>0 or w.get("carry",0.0)>0 or threatened(w.pos,records):continue
		workers.append(w)
	var result=[]
	# Three bounded pair scans, no path queries or authority mutation. Two world
	# units per already-assigned worker favor nearby alternatives, not a remote
	# empty forest. Actual routes, collision and harvest remain ordinary orders.
	for index in mini(3,workers.size()):
		var best_worker={};var best_node={};var score=INF
		for w in workers:
			for node in nodes:
				var candidate=w.pos.distance_to(node.pos)+2.0*loads.get(node.id,0)
				if candidate<score or (candidate==score and (best_worker.is_empty() or w.id<best_worker.id or (w.id==best_worker.id and node.id<best_node.id))):
					score=candidate;best_worker=w;best_node=node
		if best_worker.is_empty():break
		result.append({"ids":[best_worker.id],"target":best_node.id,"position":best_node.pos,"idle_gather":resource})
		workers.erase(best_worker)
		loads[best_node.id]=loads.get(best_node.id,0)+1
	return result
