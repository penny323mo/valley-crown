extends RefCounted
const IdleWorkers=preload("res://scripts/idle_worker_selection.gd")
const Status=preload("res://scripts/worker_idle_status.gd")
const RESOURCE_TYPES={"pine":"wood","oak":"wood","berry":"food","stone":"stone","iron":"iron"}
static func orders(records: Dictionary,selected: Array,commands: Array) -> Array:
	var eligible=IdleWorkers.eligible(records,commands)
	var result=[];var seen={}
	for id in selected:
		if id not in eligible or seen.has(id): continue
		seen[id]=true
		var worker=records[id]
		if Status.route_failure(worker,false).is_empty() or worker.get("cargo_milli",0)>0 or worker.get("carry",0.0)>0: continue
		var target=records.get(worker.get("path_request_target",-1),{})
		if target.is_empty() or target.get("remembered",true) or not target.get("alive",false) or target.get("category","")!="resource": continue
		if RESOURCE_TYPES.get(target.get("kind",""),"")=="" or RESOURCE_TYPES.get(target.kind,"")!=worker.get("gather_type",""): continue
		result.append({"ids":[id],"target":target.id,"retry_gather":true})
	return result
