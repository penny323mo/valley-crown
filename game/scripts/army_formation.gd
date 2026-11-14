extends RefCounted
## Destination slots only, not synchronized movement or a pathfinding override.
## Owned military input; no enemy/world access and no mutation.
const Rules=preload("res://scripts/rules.gd")
const TYPES=["line","spread"]
static func plan(units: Array, destination: Vector3, style: String) -> Dictionary:
	if style not in TYPES or not destination.is_finite() or units.is_empty(): return {}
	var members=[]; var seen={}; var center=Vector3.ZERO
	for unit in units:
		if unit.get("kind","") not in Rules.UNIT_KINDS or unit.kind=="villager" or not unit.get("alive",false) or not unit.get("pos",Vector3.INF).is_finite() or seen.has(unit.id): continue
		seen[unit.id]=true; members.append(unit)
	if members.is_empty(): return {}
	members.sort_custom(func(a,b):return a.id<b.id)
	for unit in members: center+=unit.pos
	center/=members.size()
	var forward=destination-center; forward.y=0
	forward=forward.normalized() if forward.length_squared()>0.01 else Vector3(0,0,-1)
	var side=Vector3(-forward.z,0,forward.x)
	var rank={"spearman":0,"cavalry":0,"scout":0,"archer":1,"siege":2}
	members.sort_custom(func(a,b): return rank[a.kind]<rank[b.kind] if rank[a.kind]!=rank[b.kind] else a.id<b.id)
	var spacing=3.0 if style=="spread" else 1.5
	var columns=mini(8,maxi(2,ceili(sqrt(members.size())*1.5)))
	var result={}; var row=0
	# Start each role on a new row so even a two-unit melee/ranged group
	# actually has a front and rear, rather than sharing one lateral row.
	for tier in [0,1,2]:
		var group=members.filter(func(unit):return rank[unit.kind]==tier)
		for i in group.size():
			var local_row=i/columns
			var row_size=mini(columns,group.size()-local_row*columns)
			var lateral=(float(i%columns)-float(row_size-1)*0.5)*spacing
			var slot=destination+side*lateral-forward*float(row+local_row)*spacing
			var limit=float(Rules.MAP_WORLD_LIMIT)-0.5
			slot.x=clampf(slot.x,-limit,limit); slot.z=clampf(slot.z,-limit,limit)
			result[group[i].id]=slot
		row+=ceili(float(group.size())/columns)
	return result
