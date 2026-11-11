extends RefCounted
## Player convenience only. Inputs are the current faction projection and own
## queued commands; outputs go through the ordinary order submission boundary.
## No authority, path retry, resource mutation, or remembered-target fallback.

static func owned_current(record: Dictionary) -> bool:
	return record.get("owned",false) and record.get("team",-1)==0 and record.get("alive",false) and not record.get("remembered",false)

static func villager(record: Dictionary) -> bool:
	return owned_current(record) and record.get("category","")=="unit" and record.get("kind","")=="villager"

static func has_villager(records: Dictionary, selection: Array) -> bool:
	for id in selection:
		if villager(records.get(id,{})): return true
	return false

static func orders(records: Dictionary, selection: Array, pending: Array) -> Array:
	var busy={}
	# Preserve queued user intent. A new tap after the next tick can override it,
	# but repeated taps cannot append duplicate delivery orders in one batch.
	for command in pending:
		if command.get("team",-1)!=0: continue
		if command.get("type","") in ["order","stop","defend"]:
			for id in command.get("ids",[]): busy[id]=true
		elif command.get("type","")=="build": busy[command.get("builder",-1)]=true
	var drops=[]
	for record in records.values():
		if owned_current(record) and record.get("category","")=="building" and record.get("built",false) and record.get("kind","") in ["town_center","storehouse"]:
			drops.append(record)
	var ids=selection.duplicate(); ids.sort()
	var result=[]
	var seen={}
	for id in ids:
		if seen.has(id) or busy.has(id): continue
		seen[id]=true
		var worker: Dictionary=records.get(id,{})
		if not villager(worker) or worker.get("cargo_milli",0)<=0: continue
		# Do not reset an in-flight delivery, including queued searches/waits.
		if worker.get("state","")=="deliver" and worker.get("path_status","") not in ["NO_PATH","LIMIT_REACHED"]: continue
		var best={}; var distance=INF
		for drop in drops:
			var d=worker.pos.distance_squared_to(drop.pos)
			if d<distance or (d==distance and (best.is_empty() or drop.id<best.id)):
				best=drop; distance=d
		if not best.is_empty(): result.append({"ids":[id],"target":best.id,"position":best.pos})
	return result
