extends RefCounted
## Own current observations only. Queue means paid orders, not pending requests.
const KINDS=["scout","spearman","archer","cavalry","siege"]
static func snapshot(records: Dictionary,commands: Array=[]) -> Dictionary:
	var result={};var pending={}
	for kind in KINDS:result[kind]={"ids":[],"wounded":[],"idle":0,"queued":0}
	for command in commands:
		if command.get("team",-1)!=0:continue
		for id in command.get("ids",[]):pending[id]=true
	for id in records:
		var unit=records[id]
		if not unit is Dictionary or unit.get("id",-1)!=id or not unit.get("alive",false) or not unit.get("owned",false) or unit.get("remembered",false) or unit.get("team",-1)!=0:continue
		if unit.get("category","")=="building" and unit.get("built",false):
			for order in unit.get("queue",[]):
				if order.get("kind","") in KINDS:result[order.kind].queued+=1
		if unit.get("category","")!="unit" or unit.get("kind","") not in KINDS:continue
		var group=result[unit.kind];group.ids.append(id)
		if unit.get("hp",0)<unit.get("max_hp",0):group.wounded.append(id)
		if unit.get("state","")=="idle" and not unit.get("path_pending",false) and unit.get("path",[]).is_empty() and not pending.has(id):group.idle+=1
	for kind in KINDS:
		result[kind].ids.sort();result[kind].wounded.sort()
	return result
