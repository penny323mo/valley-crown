extends RefCounted
## Selection only. Caller supplies current sanitized player observations.
## Never read world authority, infer hidden state or submit commands here.
const Rules=preload("res://scripts/rules.gd")

static func eligible(records,commands):
	if typeof(records)!=TYPE_DICTIONARY or typeof(commands)!=TYPE_ARRAY: return []
	var pending={}
	for command in commands:
		if typeof(command)!=TYPE_DICTIONARY or command.get("team",-1)!=0: continue
		if command.get("type","")=="build":
			var builder=command.get("builder",-1)
			if typeof(builder)==TYPE_INT and builder>=0: pending[builder]=true
		elif command.get("type","") in ["order","stop","defend","advance","patrol"]:
			var ids=command.get("ids",[])
			if typeof(ids)!=TYPE_ARRAY: continue
			for id in ids:
				if typeof(id)==TYPE_INT and id>=0: pending[id]=true
	var result=[]
	for id in records:
		if typeof(id)!=TYPE_INT or id<0 or pending.has(id): continue
		var worker=records[id]
		if typeof(worker)!=TYPE_DICTIONARY or worker.get("id",-1)!=id: continue
		if not worker.get("owned",false) or not worker.get("alive",false) or worker.get("remembered",false) or worker.get("team",-1)!=0: continue
		if worker.get("category","")!="unit" or worker.get("kind","")!="villager" or worker.get("state","")!="idle": continue
		if worker.get("path_pending",false) or not worker.get("path",[]).is_empty(): continue
		result.append(id)
		if result.size()>Rules.POP_LIMIT: return []
	result.sort()
	return result

static func next_id(ids,previous):
	for id in ids:
		if id>previous: return id
	return -1 if ids.is_empty() else ids[0]
