extends RefCounted
## Completed, currently owned production buildings only. No hidden enemy queues.
const KINDS=["town_center","barracks","range","stable","workshop"]
static func snapshot(records: Dictionary) -> Dictionary:
	var result={}
	for kind in KINDS: result[kind]={"ids":[],"idle":0,"busy":0,"automatic":0,"queued":0}
	for id in records:
		var b=records[id]
		if not b is Dictionary or b.get("id",-1)!=id or not b.get("alive",false) or not b.get("owned",false) or b.get("remembered",false): continue
		if b.get("team",-1)!=0 or b.get("category","")!="building" or not b.get("built",false) or b.get("kind","") not in KINDS: continue
		var group=result[b.kind]
		group.ids.append(id)
		var count=b.get("queue",[]).size()
		group.queued+=count
		if count>0: group.busy+=1
		elif not b.get("repeat_kind","").is_empty(): group.automatic+=1
		else: group.idle+=1
	for kind in KINDS: result[kind].ids.sort()
	return result
static func next_id(ids: Array,previous: int) -> int:
	if ids.is_empty(): return -1
	var index=ids.find(previous)
	return ids[(index+1)%ids.size()]
