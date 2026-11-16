extends RefCounted
const KINDS=["tower","workshop","barracks","range","stable","storehouse"]
const RESERVE=80000
static func owned(r: Dictionary)->bool:
 return r.get("owned",false) and r.get("alive",false) and not r.get("remembered",true) and r.get("team",-1)==1
static func safe(target: Dictionary,records: Array)->bool:
 for e in records:
  if not e.get("alive",false) or e.get("remembered",true) or e.get("team",-1)!=0:continue
  if e.get("category","")!="unit" and not(e.get("kind","")=="tower" and e.get("built",false)):continue
  if e.pos.distance_to(target.pos)<=12:return false
 return true
static func target(records: Array,now: int)->Dictionary:
 var best={};var score=INF
 for b in records:
  if not owned(b) or b.get("category","")!="building" or not b.get("built",false) or b.get("kind","") not in KINDS:continue
  if b.get("hp",0)<=0 or b.get("max_hp",0)<=0 or b.hp*4>b.max_hp*3 or now-b.get("last_damage_tick",now)<100 or not safe(b,records):continue
  var rank=KINDS.find(b.kind)*2.0+float(b.hp)/b.max_hp
  if rank<score or (rank==score and (best.is_empty() or b.id<best.id)):best=b;score=rank
 return best
