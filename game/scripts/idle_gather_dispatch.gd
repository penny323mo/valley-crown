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
	var result=[]
	for id in Idle.eligible(records,commands):
		var w=records[id]
		if w.get("cargo_milli",0)>0 or w.get("carry",0.0)>0 or threatened(w.pos,records):continue
		var best={};var distance=INF
		for node in nodes:
			var d=w.pos.distance_squared_to(node.pos)
			if d<distance or (d==distance and (best.is_empty() or node.id<best.id)):best=node;distance=d
		if best.is_empty():continue
		result.append({"ids":[id],"target":best.id,"position":best.pos,"idle_gather":resource})
		if result.size()>=3:break
	return result
