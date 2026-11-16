extends RefCounted
## Presentation-only reminders of actual settled damage to our own property.
## Store no attacker identity, enemy position, HP, order or mutable entity reference.
const LIFETIME_TICKS = 240 # Twelve simulation seconds; pause does not age alerts.
const MAX_ALERTS = 4
const AREA_RADIUS_SQUARED = 36.0
var entries=[]
var serial=0

func reset():
	entries.clear()
	# Keep serial monotonic across diagnostic resets, invalidating old UI bindings.

func _prune(tick: int):
	var active=[]
	for entry in entries:
		if tick<entry.expires: active.append(entry)
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
			return false
	serial+=1
	entries.append({"sequence":serial,"position":point,"kind":victim.get("kind",""),
		"expires":tick+LIFETIME_TICKS,"acknowledged":false})
	if entries.size()>MAX_ALERTS: entries.pop_front()
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
