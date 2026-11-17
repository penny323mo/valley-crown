extends RefCounted
## Eligible reserves have already passed home defense and recovery filters.
## No authority lookups, private opponent state, or persistent state.
const Rules=preload("res://scripts/rules.gd")
const Difficulty=preload("res://scripts/ai_difficulty.gd")
const Policy=preload("res://scripts/skirmish_policy.gd")
static func batch(army: Array,members: Array,castle: Dictionary,mode: String,tick: int,last_departure: int,difficulty:String="standard",victory:String="conquest") -> Array:
 var result=[]
 if members.is_empty() or castle.is_empty() or not Policy.offensive(mode):return result
 if not castle.get("owned",false) or not castle.get("alive",false) or castle.get("remembered",true) or castle.get("team",-1)!=1 or not castle.get("built",false) or castle.get("category","")!="building" or castle.get("kind","")!="town_center":return result
 if tick-last_departure<Difficulty.interval(mode,victory,difficulty):return result
 for ent in army:
  if not ent.get("owned",false) or not ent.get("alive",false) or ent.get("remembered",false) or ent.get("team",-1)!=1 or ent.get("category","")!="unit":continue
  if ent.get("kind","") not in ["spearman","archer","cavalry","siege"] or ent.get("id",-1) in members:continue
  if ent.get("state","")!="idle":continue
  if ent.get("id",-1)<0 or ent.id in result:continue
  # Match _attack_distance/_ai_move_home: square building footprint, not
  # circumscribed radial distance. Corner arrivals must remain eligible.
  var half=Rules.FOOTPRINT.town_center/2.0
  var delta=ent.pos-castle.pos
  if Vector2(maxf(0,absf(delta.x)-half),maxf(0,absf(delta.z)-half)).length()>3.0:continue
  result.append(ent.id)
 result.sort()
 return Difficulty.limit(result,mode,victory,difficulty) if result.size()>=Policy.muster(mode) else []
