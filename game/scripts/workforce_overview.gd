extends RefCounted
## Work assignments, not estimated production rates. Only sanitized owned records.
const RESOURCES=["food","wood","stone","iron"]
static func snapshot(records: Dictionary,commands: Array) -> Dictionary:
	var groups={"food":[],"wood":[],"stone":[],"iron":[],"building":[],"idle":[],"other":[],"pending":[]}
	var pending={}
	for command in commands:
		if not command is Dictionary or command.get("team",-1)!=0: continue
		if command.get("type","")=="build": pending[command.get("builder",-1)]=true
		elif command.get("type","") in ["order","stop","defend","advance","patrol"]:
			for id in command.get("ids",[]): pending[id]=true
	var total=0
	for id in records:
		var worker=records[id]
		if not worker is Dictionary or worker.get("id",-1)!=id or not worker.get("alive",false) or not worker.get("owned",false) or worker.get("remembered",false): continue
		if worker.get("team",-1)!=0 or worker.get("category","")!="unit" or worker.get("kind","")!="villager": continue
		var group="other"
		var state=worker.get("state","")
		var resource=worker.get("gather_type","")
		if pending.has(id): group="pending"
		elif state in ["gather","deliver"] and resource in RESOURCES: group=resource
		elif state in ["build","repair"]: group="building"
		elif state=="idle" and not worker.get("path_pending",false) and worker.get("path",[]).is_empty(): group="idle"
		groups[group].append(id); total+=1
	for group in groups: groups[group].sort()
	return {"groups":groups,"total":total}
