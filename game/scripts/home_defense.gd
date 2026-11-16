extends RefCounted
## Home interception from sanitized faction observations only. No hidden lookup,
## health mutation, economic privilege, movement bypass or enemy memory targeting.
const Rules=preload("res://scripts/rules.gd")

static func threats(records: Array, radius: float) -> Array:
	var homes=[]; var result=[]; var seen={}
	for record in records:
		if record.get("owned",false) and record.get("alive",false) and record.get("team",-1)==1 and record.get("category","")=="building": homes.append(record)
	for record in records:
		if record.get("owned",false) or not record.get("alive",false) or record.get("remembered",true) or record.get("team",-1)!=0 or record.get("category","")!="unit" or record.get("kind","") not in Rules.UNIT_KINDS: continue
		if seen.has(record.id): continue
		for home in homes:
			var half=Rules.FOOTPRINT.get(home.kind,3)/2.0
			var dx=maxf(0,absf(record.pos.x-home.pos.x)-half)
			var dz=maxf(0,absf(record.pos.z-home.pos.z)-half)
			if sqrt(dx*dx+dz*dz)<=radius:
				result.append(record); seen[record.id]=true; break
	result.sort_custom(func(a,b): return a.id<b.id)
	return result

static func choose(attacker: Dictionary, candidates: Array) -> Dictionary:
	var kind=attacker.get("kind","")
	if not attacker.get("owned",false) or not attacker.get("alive",false) or attacker.get("team",-1)!=1 or attacker.get("category","")!="unit" or kind not in Rules.UNIT_KINDS or kind=="villager": return {}
	var chosen={}; var best=[]
	for target in candidates:
		if target.get("owned",false) or not target.get("alive",false) or target.get("remembered",true) or target.get("team",-1)!=0 or target.get("category","")!="unit" or target.get("kind","") not in Rules.UNIT_KINDS: continue
		var distance=maxf(0,attacker.pos.distance_to(target.pos)-target.get("radius",Rules.UNIT_RADIUS))
		var bonus=Rules.CONTENT.UNIT_COUNTER_BONUSES.get(kind,{}).get(target.kind,0)
		var current=attacker.get("state","")=="attack" and attacker.get("target",-1)==target.id
		# Armed raids cannot be distracted by a closer lone worker. Among
		# military threats take a shot already in reach, then favorable counters.
		var score=[1 if target.kind=="villager" else 0,0 if distance<=Rules.RANGE[kind] else 1,-bonus,0 if current else 1,distance,target.id]
		var before=best.is_empty()
		if not before:
			for index in range(score.size()):
				if score[index]!=best[index]: before=score[index]<best[index]; break
		if before: chosen=target; best=score
	return chosen
