extends RefCounted
## Presentation-only reminders of actual settled damage to our own property.
## Store no attacker identity, enemy position, HP, order or mutable entity reference.
const LIFETIME_TICKS = 240 # Twelve simulation seconds; pause does not age alerts.
const MAX_ALERTS = 4
const AREA_RADIUS_SQUARED = 36.0
var entries=[]
var serial=0
# Presentation-only, bounded by the retained incidents. Never serialized as
# part of entries; a restored checkpoint safely falls back to its frozen point.
var _recent_friendly_positions={}

func reset():
	entries.clear()
	_recent_friendly_positions.clear()
	# Keep serial monotonic across diagnostic resets, invalidating old UI bindings.

func _prune(tick: int):
	var active=[]
	for entry in entries:
		if tick<entry.expires: active.append(entry)
		else: _recent_friendly_positions.erase(entry.get("sequence",-1))
	entries=active

func record_hit(victim: Dictionary,damage: float,tick: int) -> bool:
	if tick<0 or not is_finite(damage) or damage<=0: return false
	if victim.is_empty() or victim.get("team",-1)!=0 or not victim.get("alive",false): return false
	if victim.get("category","") not in ["unit","building"]: return false
	var point=victim.get("pos",Vector3.INF)
	if not point is Vector3 or not point.is_finite(): return false
	_prune(tick)
	for entry in entries:
		if entry.position.distance_squared_to(point)<=AREA_RADIUS_SQUARED:
			# Repeated fighting extends the same reminder, never its frozen point.
			# An acknowledged area stays quiet until twelve seconds without a hit.
			entry.expires=tick+LIFETIME_TICKS
			_recent_friendly_positions[entry.sequence]=point
			return false
	serial+=1
	entries.append({"sequence":serial,"position":point,"kind":victim.get("kind",""),
		"expires":tick+LIFETIME_TICKS,"acknowledged":false})
	if entries.size()>MAX_ALERTS: _recent_friendly_positions.erase(entries.pop_front().sequence)
	return true

func peek(tick: int) -> Dictionary:
	_prune(tick)
	for entry in entries:
		if not entry.acknowledged: return entry.duplicate(true)
	return {}

func acknowledge(sequence: int,tick: int) -> Dictionary:
	var current=peek(tick)
	if current.is_empty() or current.sequence!=sequence: return {}
	for entry in entries:
		if entry.sequence==sequence:
			entry.acknowledged=true
			return current
	return {}

# Read-only presentation snapshot: only frozen own-victim positions, no attackers.
func pending(tick: int) -> Array:
	_prune(tick)
	return entries.filter(func(entry):return not entry.acknowledged).duplicate(true)


# Quiet camera return: give the last still-current acknowledged friendly hit
# area, not a new unread alert or a live actor position. No persisted fields change.
func acknowledged_site(tick: int) -> Dictionary:
	_prune(tick)
	for i in range(entries.size()-1,-1,-1):
		var entry=entries[i]
		if not entry.acknowledged:continue
		var sequence=entry.get("sequence",-1)
		if not sequence is int or sequence<1:continue
		var point=_recent_friendly_positions.get(sequence,entry.get("position",Vector3.INF))
		if point is Vector3 and point.is_finite():return {"sequence":sequence,"position":point}
	return {}
