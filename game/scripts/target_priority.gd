extends RefCounted
## Ranking only after the caller enforces observation, range and stance bounds.
const Content=preload("res://scripts/bal01_content.gd")
static func bonus(kind: String, record: Dictionary) -> int:
 var target_kind=record.get("kind","")
 var category=record.get("category","")
 if category=="unit":
  if not Content.UNITS.has(target_kind):return 0
 elif category=="building":
  if not Content.BUILDINGS.has(target_kind):return 0
 else:return 0
 # Exactly the same base matchup bonus as authoritative damage settlement.
 # Ranking never multiplies damage, changes range or discovers a target.
 return int(Content.resolve_damage(kind,target_kind).get("bonus",0))
static func better(kind: String, policy: String, candidate: Dictionary, current: Dictionary, distance: float, current_distance: float) -> bool:
 if current.is_empty():return true
 if policy=="counter":
  var advantage=bonus(kind,candidate);var previous=bonus(kind,current)
  if advantage!=previous:return advantage>previous
 return distance<current_distance or (is_equal_approx(distance,current_distance) and candidate.id<current.id)
