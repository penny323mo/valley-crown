extends RefCounted
## Match-local selection shortcuts. Only sanitized own military records enter.
const Rules=preload("res://scripts/rules.gd")
const SLOT_COUNT=3
var groups=[[],[],[]]

static func eligible(records,ids):
	if typeof(ids)!=TYPE_ARRAY or ids.size()>Rules.POP_LIMIT: return []
	var result=[]; var seen={}
	for id in ids:
		if typeof(id)!=TYPE_INT: return []
		if seen.has(id): continue
		seen[id]=true
		var record=records.get(id,{})
		if record.get("id",-1)!=id or not record.get("owned",false) or not record.get("alive",false) or record.get("remembered",false) or record.get("team",-1)!=0 or record.get("category","")!="unit": continue
		if record.get("kind","") not in Rules.UNIT_KINDS or record.kind=="villager": continue
		result.append(id)
	result.sort()
	return result

func members(slot,records):
	if typeof(slot)!=TYPE_INT or slot<0 or slot>=SLOT_COUNT: return []
	return eligible(records,groups[slot])

func assign(slot,records,ids,expected):
	if typeof(slot)!=TYPE_INT or slot<0 or slot>=SLOT_COUNT: return false
	var current=eligible(records,ids)
	if current.is_empty() or current!=expected: return false
	groups[slot]=current.duplicate()
	return true

func reset():
	groups=[[],[],[]]
