extends RefCounted
## Stateless bounded interception. Inputs are faction observations only.
const Defense=preload("res://scripts/home_defense.gd")
const Rules=preload("res://scripts/rules.gd")

static func plan(army:Array, threats:Array, castle:Dictionary, prior:Dictionary) -> Dictionary:
	var valid=[]
	for threat in threats:
		if not threat.get("owned",false) and threat.get("alive",false) and not threat.get("remembered",true) and threat.get("team",-1)==0 and threat.get("category","")=="unit" and threat.get("kind","") in Rules.UNIT_KINDS: valid.append(threat)
	var close_armed=0; var siege=false
	for threat in valid:
		if castle.get("owned",false) and castle.get("alive",false) and castle.get("kind","")=="town_center" and threat.kind!="villager":
			var half=Rules.FOOTPRINT.town_center/2.0
			var delta=threat.pos-castle.pos
			if Vector2(maxf(0,absf(delta.x)-half),maxf(0,absf(delta.z)-half)).length()<=6.0:
				close_armed+=1
				if threat.kind=="siege": siege=true
	# Three armed invaders or a siege engine at the keep warrant full recall.
	var emergency=close_armed>=3 or siege or (close_armed>0 and castle.get("hp",INF)<=Rules.HP.town_center*0.4)
	var candidates=[]
	for ent in army:
		var target=Defense.choose(ent,valid)
		if target.is_empty(): continue
		var distance=ent.pos.distance_to(target.pos)
		# Local response is bounded to 18 world units; remote raids keep going.
		if not emergency and distance>18.0: continue
		candidates.append({"unit":ent,"target":target,"distance":distance,"retained":prior.get(ent.id,-1)==target.id})
	candidates.sort_custom(func(a,b):
		if a.retained!=b.retained:return a.retained
		if not is_equal_approx(a.distance,b.distance):return a.distance<b.distance
		return a.unit.id<b.unit.id)
	var budget=0
	for threat in valid: budget+=1 if threat.kind=="villager" or threat.kind=="scout" else 2
	var assignments={}
	for candidate in candidates:
		if not emergency and assignments.size()>=budget:break
		assignments[candidate.unit.id]=candidate.target
	return {"emergency":emergency,"assignments":assignments}
