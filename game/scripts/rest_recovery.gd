extends RefCounted
## Passive recovery never creates movement, cancels orders, or reads hidden enemies.
const KINDS=["scout","spearman","archer","cavalry"]
const RADIUS=7.0
const THREAT_RADIUS=9.0
const SAFE_TICKS=200
const HEAL_TICKS=40

static func base_for(unit: Dictionary, bases: Array) -> Dictionary:
	var best={}
	for base in bases:
		if not base.get("alive",false) or not base.get("built",false) or base.get("kind","")!="town_center" or base.get("team",-1)!=unit.get("team",-2): continue
		if unit.pos.distance_to(base.pos)>RADIUS: continue
		if best.is_empty() or base.id<best.id: best=base
	return best

static func blocked(unit: Dictionary, base: Dictionary, threats: Array, now: int) -> String:
	if not unit.get("alive",false) or unit.get("kind","") not in KINDS or unit.get("team",-1) not in [0,1]: return "ineligible"
	if unit.hp>=unit.max_hp: return "full"
	if unit.get("state","")!="idle" or not unit.get("path",[]).is_empty() or unit.get("path_pending",false): return "orders"
	if base.is_empty(): return "away"
	if unit.get("last_damage_tick",-1000)==now or unit.get("last_attack_tick",-1000)==now or base.get("last_damage_tick",-1000)==now: return "combat"
	for enemy in threats:
		if not enemy.get("alive",false) or enemy.get("remembered",false) or enemy.get("team",-1)!=1-unit.team: continue
		if enemy.get("category","")!="unit" and not (enemy.get("kind","")=="tower" and enemy.get("built",false)): continue
		if unit.pos.distance_to(enemy.pos)<=THREAT_RADIUS or base.pos.distance_to(enemy.pos)<=THREAT_RADIUS: return "threat"
	return ""

static func label(record: Dictionary) -> String:
	if not record.get("owned",false) or record.get("kind","") not in KINDS or record.get("hp",0)>=record.get("max_hp",0): return ""
	var ticks=int(record.get("rest_ticks",0))
	if ticks<=0: return "回己方主堡旁安全待命，可休整回血"
	if ticks<SAFE_TICKS: return "回城休整：安全待命 %d 秒" % ceili((SAFE_TICKS-ticks)/20.0)
	return "回城休整：每 2 秒恢復 1 生命"
