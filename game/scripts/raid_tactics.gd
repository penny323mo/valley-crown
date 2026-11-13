extends RefCounted
## Deterministic raid escorts, sanitized faction-1 observations only.
## No pathfinding, authority lookup, resource grant or combat settlement here.
const Rules=preload("res://scripts/rules.gd")

static func _before(score,best):
	if best.is_empty(): return true
	for index in range(score.size()):
		if score[index]!=best[index]: return score[index]<best[index]
	return false

static func choose(attacker,records):
	if not attacker.get("owned",false) or not attacker.get("alive",false) or attacker.get("team",-1)!=1 or attacker.get("category","")!="unit": return {}
	var kind=attacker.get("kind","")
	if kind not in Rules.UNIT_KINDS or kind in ["villager","siege"]: return {}
	var chosen={}; var best=[]
	for target in records:
		if not target.get("alive",false) or target.get("owned",false) or target.get("remembered",false) or target.get("team",-1)!=0 or target.get("category","")!="unit": continue
		var target_kind=target.get("kind","")
		if target_kind not in Rules.UNIT_KINDS: continue
		var center_distance=attacker.pos.distance_to(target.pos)
		# A faction-shared distant observation cannot send an escort across
		# the map. Existing public personal sight bounds this local decision.
		if center_distance>Rules.SIGHT[kind]: continue
		var distance=maxf(0,center_distance-target.get("radius",Rules.UNIT_RADIUS))
		var bonus=Rules.CONTENT.UNIT_COUNTER_BONUSES.get(kind,{}).get(target_kind,0)
		var current=attacker.get("state","")=="attack" and attacker.get("target",-1)==target.id
		# In-range threats first, then real counter bonus. Retain an equivalent
		# target rather than reordering every second as nearby units shuffle.
		var score=[0 if distance<=Rules.RANGE[kind] else 1,-bonus,0 if current else 1,distance,target.id]
		if _before(score,best): chosen=target; best=score
	return chosen
