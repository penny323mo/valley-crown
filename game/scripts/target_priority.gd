extends RefCounted
## Ranking only after the caller enforces observation, range and stance bounds.
const Content=preload("res://scripts/bal01_content.gd")
static func bonus(kind: String, record: Dictionary) -> int:
 if record.get("category","")!="unit":return 0
 return Content.UNIT_COUNTER_BONUSES.get(kind,{}).get(record.get("kind",""),0)
static func better(kind: String, policy: String, candidate: Dictionary, current: Dictionary, distance: float, current_distance: float) -> bool:
 if current.is_empty():return true
 if policy=="counter":
  var advantage=bonus(kind,candidate);var previous=bonus(kind,current)
  if advantage!=previous:return advantage>previous
 return distance<current_distance or (is_equal_approx(distance,current_distance) and candidate.id<current.id)
