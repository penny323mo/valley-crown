extends RefCounted
const Manual=preload("res://scripts/field_manual.gd")
static func selected_entry(records: Dictionary,selection: Array) -> Dictionary:
	if selection.is_empty(): return {}
	var kind="";var category=""
	for id in selection:
		var r=records.get(id,{})
		if not r.get("owned",false) or not r.get("alive",false) or r.get("remembered",false) or r.get("team",-1)!=0: return {}
		if r.get("category","") not in ["unit","building"]: return {}
		if kind!="" and (kind!=r.get("kind","") or category!=r.category): return {}
		kind=r.get("kind","");category=r.category
	var section=0 if category=="unit" else 1
	var index=Manual.entries(section).find(kind)
	return {} if index<0 else Manual.entry(section,index)
