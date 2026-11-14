extends RefCounted
## Owned live records only. Counts indicate assignments, not reachability.
static func snapshot(records: Dictionary,commands: Array) -> Dictionary:
	var result={"unfinished":[],"unassigned":[],"damaged":[]}
	var assigned={}
	for r in records.values():
		if r.get("owned",false) and r.get("alive",false) and not r.get("remembered",false) and r.get("team",-1)==0 and r.get("kind","")=="villager" and r.get("state","")=="build":assigned[r.get("target",-1)]=true
	for c in commands:
		if c.get("team",-1)==0 and c.get("type","")=="order":assigned[c.get("target",-1)]=true
	for id in records:
		var b=records[id]
		if b.get("id",-1)!=id or not b.get("owned",false) or not b.get("alive",false) or b.get("remembered",false) or b.get("team",-1)!=0 or b.get("category","")!="building":continue
		if not b.get("built",true):
			result.unfinished.append(id)
			if not assigned.has(id):result.unassigned.append(id)
		elif b.get("hp",0)<b.get("max_hp",0):result.damaged.append(id)
	for key in result:result[key].sort()
	return result
