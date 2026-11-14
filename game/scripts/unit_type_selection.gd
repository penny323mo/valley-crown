extends RefCounted
const Rules=preload("res://scripts/rules.gd")
static func groups(records: Dictionary,selection: Array) -> Dictionary:
	var result={}; var seen={}
	for id in selection:
		if seen.has(id): continue
		seen[id]=true
		var unit=records.get(id,{})
		if unit.get("id",-1)!=id or not unit.get("owned",false) or not unit.get("alive",false) or unit.get("remembered",false): continue
		if unit.get("team",-1)!=0 or unit.get("category","")!="unit" or unit.get("kind","") not in Rules.UNIT_KINDS: continue
		if not result.has(unit.kind): result[unit.kind]=[]
		result[unit.kind].append(id)
	for kind in result: result[kind].sort()
	return result
