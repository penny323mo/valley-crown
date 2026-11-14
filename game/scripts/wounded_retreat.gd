extends RefCounted
const Rest=preload("res://scripts/rest_recovery.gd")
static func owned(r:Dictionary)->bool:
	return r.get("owned",false) and r.get("alive",false) and r.get("team",-1)==0 and not r.get("remembered",false)
static func injured(records:Dictionary,selection:Array)->Array:
	var ids=[]
	for id in selection:
		var r=records.get(id,{})
		if id not in ids and owned(r) and r.get("category","")=="unit" and r.get("kind","") in Rest.KINDS and r.get("hp",0)<r.get("max_hp",0):ids.append(id)
	ids.sort();return ids
static func orders(records:Dictionary,selection:Array,pending:Array)->Array:
	var busy={}
	for c in pending:
		if c.get("team",-1)==0:
			for id in c.get("ids",[]):busy[id]=true
	var bases=[]
	for r in records.values():
		if not owned(r) or r.get("category","")!="building" or r.get("kind","")!="town_center" or not r.get("built",false):continue
		var danger=false
		for e in records.values():
			if not e.get("alive",false) or e.get("remembered",false) or e.get("team",-1)!=1:continue
			if e.get("category","")!="unit" and not (e.get("kind","")=="tower" and e.get("built",false)):continue
			if e.pos.distance_to(r.pos)<=Rest.THREAT_RADIUS+5.0:danger=true;break
		if not danger:bases.append(r)
	var result=[]
	for id in injured(records,selection):
		if busy.has(id):continue
		var u=records[id];var best={};var distance=INF
		for b in bases:
			var d=u.pos.distance_squared_to(b.pos)
			if d<distance or (d==distance and (best.is_empty() or b.id<best.id)):best=b;distance=d
		if best.is_empty() or distance<=Rest.RADIUS*Rest.RADIUS:continue
		result.append({"ids":[id],"target":-1,"position":best.pos+Vector3(5,0,0),"wounded_retreat":true,"retreat_base":best.id})
	return result
