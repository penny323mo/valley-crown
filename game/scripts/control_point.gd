extends RefCounted
# Public objective. Control/score are public, unit identities/positions are not.
const Rules=preload("res://scripts/rules.gd")
const CENTER=Vector3.ZERO
const RADIUS=5.0
const HOLD_TICKS=3600 # 180 seconds of sole control, cumulative.
const MIN_TROOPS=2
var scores=[0,0]
var owner=-1
var contested=false
var last_tick=-1
func reset():
	scores=[0,0];owner=-1;contested=false;last_tick=-1
func advance(records: Array,tick: int) -> bool:
	if tick<=last_tick: return false
	last_tick=tick
	var presence=[0,0];var seen={}
	for unit in records:
		if not unit.get("alive",false) or unit.get("team",-1) not in [0,1] or unit.get("category","")!="unit" or unit.get("kind","") not in Rules.UNIT_KINDS or unit.kind=="villager": continue
		if unit.pos.distance_to(CENTER)>RADIUS or seen.has(unit.id): continue
		seen[unit.id]=true;presence[unit.team]+=1
	contested=presence[0]>0 and presence[1]>0
	owner=-1
	if not contested:
		for team in 2:
			if presence[team]>=MIN_TROOPS: owner=team
	if owner<0 or scores[owner]>=HOLD_TICKS:return false
	scores[owner]+=1
	return true
func winner() -> int:
	for team in 2:
		if scores[team]>=HOLD_TICKS:return team
	return -1
func caption() -> String:
	var status="爭奪中，停止計時" if contested else ("我軍控制" if owner==0 else ("敵軍控制" if owner==1 else "至少兩名軍人進圈"))
	return "中央王旗 · "+status+" · 我方 %d / 敵方 %d 秒（180 勝利）" % [scores[0]/20,scores[1]/20]
